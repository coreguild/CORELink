--[[ CORELink - bridge guild chat between multiple co-guilds (retail 12.x API).
     Guild messages are relayed into a hidden custom channel; clients in other
     guilds show them in guild colours as "[GuildTag] [Author]: message".

     Configuration is done in game:
         /cl setup <channel> <password> [tag]     (use - for no password)
     Whoever can edit Guild Info pastes the line shown by /cl publish (setup
     shows it too) into Guild Info; every member's client then picks the
     settings up automatically. (Addons cannot write Guild Info themselves.)

     Midnight/Forever restriction: in M+, PvP and encounters chat arrives as
     secret values and addons cannot send chat; CORELink pauses there. ]]

local ADDON, PROTO, SEP = "CORELink", "CL4", "~"
local PREFIX = "CORELink"
local lastSendResult
local lastFailNotice = 0
local rankNameOf = {}  -- guild member name -> rank name
local rankOf = {}   -- guild member name -> rank index (0 = guild master)
local DEFAULT_OFFICER_COLOR = "e8c63e"
local heard = {}   -- guild tag -> last time seen on the link channel (on OUR realm)
-- Custom channels are per realm: a guild's lines reach a realm only if that guild has an addon user on it.
-- Guildmates on other realms tell us what they hear (HEARD messages on the guild addon channel), so
-- /cl guilds can show which realms each linked guild is actually reaching.
local heardRealms = {}      -- tag -> realm -> last time heard there (ours or a guildmate's realm)
-- What we know about authors from relay packets: class token and officer label, keyed by chat name.
-- Community lines carry neither, so this is how they get class and officer colours.
local authorClass, authorOfficer, authorNick, authorSeen = {}, {}, {}, {}   -- learned from relay packets
local rosterGuid = {}   -- guild member guid -> name (to recognise guildmates' community posts)
local guildRealms = {}      -- realm -> last time one of our own guildmates reported from it
local lastHeardSent, lastHeardSig = 0, ""
local coverageWarned = {}   -- tag -> true once we warned that it is not reaching our realm
-- Cross-realm bridge: a client that hears another guild's line on its realm forwards it to its own guild
-- (guild addon messages cross realms); a guildmate on another realm re-sends it into that realm's channel.
-- Guild lines of our own guild are not bridged: our couriers on each realm already relay them.
local bridged = {}          -- packet id -> time it was forwarded (by us or a guildmate) on the guild channel
local bridgeStats = { forwarded = 0, resent = 0, skipped = 0 }
local OnBridgeReceived      -- defined after the guild addon handler that calls it
-- Community mirror: the player's own typed guild lines are also posted into a Blizzard Community
-- ("club=<id|short name>" token on the Guild Info line). Community sends only work inside the player's
-- keypress, so this is done from the chat send hooks and never for relayed lines.
local mirror = { hooks = "not installed", streamId = nil, posted = 0, failed = 0, reminded = false, shown = 0,
                 focused = false, hidden = 0, lastText = nil, lastAt = 0, skipped = 0, clubType = nil, carried = 0 }
-- A line can reach us twice: on the relay channel (readable) and in the community (text sealed, so it cannot be
-- hashed). Each displayed line is remembered by author and time; the other path's copy within a few seconds is dropped.
local recentFrom = {}   -- author -> { { t = time, via = "relay"|"club" }, ... }
local CROSS_SECS = 5
-- Piggyback: a guild line typed by a member without the addon cannot be posted to the community by anyone
-- (only the typist's own keypress may post), so it waits here and rides along the next guild line an addon
-- user of this guild types. The first client to post claims the line for its guildmates (CARRIED) and tells
-- same-realm readers how many carried copies follow (CARRY), so they do not show the relayed line twice.
local carry = {}            -- { id, author, text, t, rank, nick }, oldest first
local carried = {}          -- line id -> time it was posted to the community, by us or a guildmate
local addonUsers = {}       -- guildmate -> last time a CORELink guild message came from them (they post their own)
local CARRY_MAX, CARRY_SECS, ADDON_USER_SECS, CLUB_SHOW_DELAY = 10, 300, 900, 2
local FocusClubStream       -- defined after the reminder that calls it
local MAX_MSG, DEDUPE_SECS = 200, 10

local db
local seen, pending, displayed = {}, {}, {}
local sendQueue = {}

---------------------------------------------------------------- helpers
local issecret = issecretvalue or function() return false end

local function Locked()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local ok, res = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and res then return true end
  end
  return false
end

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CORELink:|r " .. tostring(msg))
end

-- Debug log: always recorded (last DEBUG_MAX lines, shown by /cl report), echoed to chat when /cl debug on.
local DEBUG_MAX = 20
local debugLog = {}
local function Debug(fmt, ...)
  local text = select("#", ...) > 0 and string.format(fmt, ...) or fmt
  local stamp = (date and date("%H:%M:%S")) or tostring(math.floor(GetTime()))
  local line = stamp .. " " .. text
  debugLog[#debugLog + 1] = line
  if #debugLog > DEBUG_MAX then table.remove(debugLog, 1) end
  if db and db.debug then Print("|cff999999debug|r " .. text) end
end

local function Version()
  local v
  if C_AddOns and C_AddOns.GetAddOnMetadata then v = C_AddOns.GetAddOnMetadata(ADDON, "Version")
  elseif GetAddOnMetadata then v = GetAddOnMetadata(ADDON, "Version") end
  -- The repo's TOC holds "@project-version@"; releases stamp the real number. A symlinked dev checkout shows "dev".
  if not v or v == "" or v:find("@", 1, true) then return "dev" end
  return v
end

local function Clean(s) return (s:gsub("[%s~|]", "")) end

local function Hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  return string.format("%08x", h)
end

local function Configured() return db and db.channel and db.channel ~= "" end

local function MyRealm()
  local r = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
  return (type(r) == "string" and not issecret(r)) and r:gsub("[%s~|,]", "") or ""
end

local function NoteHeard(tag, realm, when)
  if not tag or tag == "" or not realm or realm == "" then return end
  heardRealms[tag] = heardRealms[tag] or {}
  heardRealms[tag][realm] = when
end

-- Who am I, in the format chat events and the roster use. On WoW: Forever that is "First Surname", while
-- UnitName("player") may return only the first name, so identify ourselves by GUID and learn the name from
-- the roster or from our own guild messages. Nicknames are keyed by this name.
local myGUID, myName
local function LearnMyName(name)
  if not name or name == "" or myName == name then return end
  local old = myName or UnitName("player")
  myName = name
  if db and db.nicks and old ~= name and db.nicks[old] and not db.nicks[name] then
    db.nicks[name] = db.nicks[old]; db.nicks[old] = nil      -- re-key a nickname saved under the short name
  end
end
local function MyName() return myName or UnitName("player") end
local function IsMe(author, guid)
  if guid and myGUID and not issecret(guid) and guid == myGUID then
    LearnMyName(author)
    return true
  end
  return author == MyName() or author == UnitName("player")
end

local function GetTag()
  if db.tag and db.tag ~= "" then return db.tag end
  local g = GetGuildInfo("player")
  if not g then return nil end
  return (g:gsub("[%s~|]", "")):sub(1, 6)
end

local function Trim(msg, limit)   -- trim without breaking links/colour codes/UTF-8
  limit = math.max(20, math.min(limit or MAX_MSG, MAX_MSG))
  if #msg <= limit then return msg end
  msg = msg:sub(1, limit - 3)
  local last = msg:byte(-1)
  if last and last >= 128 then msg = (msg:gsub("[\192-\255][\128-\191]*$", "")) end
  local _, o = msg:gsub("|c", "")
  local _, c = msg:gsub("|r", "")
  if o ~= c or msg:sub(-1) == "|" then
    msg = msg:sub(1, (msg:find("|c[^|]*$") or (#msg + 1)) - 1)
  end
  return msg .. "..."
end

---------------------------------------------------------------- channel
local function HideChannel()
  if not Configured() then return end
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local f = _G["ChatFrame" .. i]
    if f then ChatFrame_RemoveChannel(f, db.channel) end
  end
end

local function ChannelId()
  if not Configured() then return nil end
  local id = GetChannelName(db.channel)
  return (id and id > 0) and id or nil
end

-- Connection diagnostics: what the game told us about the link channel, and whether joining is on hold.
local conn = { giState = "not read yet", lastNotice = nil, lastNoticeAt = nil, joinAttempts = 0, blockedUntil = 0, blockedWhy = nil }
local JOIN_BLOCK_SECS = 600   -- after WRONG_PASSWORD / BANNED, stop retrying for this long (or until /cl reload)

local function EnsureChannel()
  if not db.enabled or not Configured() or Locked() then return end
  if not ChannelId() then
    if GetTime() < conn.blockedUntil then
      Debug("join of %s on hold (%s); /cl reload to retry now", db.channel, tostring(conn.blockedWhy))
      return
    end
    conn.joinAttempts = conn.joinAttempts + 1
    Debug("joining channel %s (attempt %d, password %s)", db.channel, conn.joinAttempts, db.password ~= "" and "set" or "none")
    local ok, err = pcall(JoinChannelByName, db.channel, (db.password ~= "" and db.password) or nil)
    if not ok then Debug("JoinChannelByName errored: %s", tostring(err)) end
  end
  C_Timer.After(1, HideChannel)
end

local function LeaveLink()
  if ChannelId() then LeaveChannelByName(db.channel) end
end

local function IsLinkChannel(name)
  if not name or issecret(name) or not Configured() then return false end
  return name:lower():find(db.channel:lower(), 1, true) ~= nil
end

-- Notices the game sends about channels: joined, left, wrong password, banned, too many channels ...
local function OnChannelNotice(notice, channelName, channelBaseName)
  if issecret(notice) or type(notice) ~= "string" then return end
  if not (IsLinkChannel(channelName) or IsLinkChannel(channelBaseName)) then return end
  conn.lastNotice, conn.lastNoticeAt = notice, (date and date("%H:%M:%S")) or ""
  Debug("channel notice for %s: %s", tostring(db.channel), notice)
  if notice == "WRONG_PASSWORD" or notice == "BANNED" or notice == "TOO_MANY_CHANNELS" then
    conn.blockedUntil = GetTime() + JOIN_BLOCK_SECS
    conn.blockedWhy = notice
    local why = (notice == "WRONG_PASSWORD" and "wrong channel password. Ask the Guild Master to check the CORELink line in Guild Info")
      or (notice == "BANNED" and "you are banned from that channel")
      or "you are in too many chat channels; leave one"
    Print("could not join " .. tostring(db.channel) .. ": " .. why .. ". /cl reload to retry, /cl report for details.")
  end
end

local function SetConfig(channel, password, tag, source)
  LeaveLink()
  db.channel, db.password, db.tag, db.source = channel, password, tag, source
  C_Timer.After(1.5, EnsureChannel)
end

---------------------------------------------------------------- Guild Info config
-- Always writes all four fields ("-" for an empty tag) so the GM can see the officer rank cutoff.
local function BuildLine()
  local hasTag = db.tag and db.tag ~= ""
  return "CORELink: " .. db.channel .. " " .. (db.password ~= "" and db.password or "-")
    .. " " .. (hasTag and db.tag or "-") .. " " .. (db.officerRank or 1)
    .. (db.club and (" club=" .. db.club) or "")
end

-- Members: pick up the "CORELink: <channel> <password> [tag]" line if it changed.
local function GIState(state)
  if conn.giState ~= state then
    conn.giState = state
    Debug("guild info: %s", state)
  end
end

local function ReadGuildInfo()
  if not db then return end
  if not IsInGuild() then GIState("not in a guild") return end
  local ok, text = pcall(GetGuildInfoText)
  if not ok or type(text) ~= "string" or issecret(text) then GIState("not readable") return end
  if text == "" then GIState("empty (not received yet, or nothing written)") return end
  local i = text:lower():find("corelink:", 1, true)
  if not i then GIState("no CORELink: line") return end
  local line = (text:sub(i):match("^[^\r\n]*") or ""):gsub("%s+$", "")
  if line == db.lastGI then GIState("line unchanged") return end   -- keep any local override
  local ch, pw, tag, orank = line:sub(10):match("^[ \t]*([^%s]+)[ \t]+([^%s]+)[ \t]*([^%s]*)[ \t]*([^%s]*)")
  if not ch then GIState("line present but could not be parsed: " .. line:sub(1, 60)) return end
  GIState("line read")
  db.officerRank = tonumber(orank) or 1
  local club = line:match("[%s]club=([^%s]+)")
  if club ~= db.club then
    db.club, db.clubId = club, nil          -- the id is resolved from the token when first needed
    mirror.streamId, mirror.focused, mirror.clubType = nil, false, nil
  end
  db.lastGI = line
  pw = (pw == "-") and "" or Clean(pw)
  tag = (tag ~= "" and tag ~= "-") and Clean(tag):sub(1, 8) or nil
  ch = Clean(ch)
  if ch ~= db.channel or pw ~= db.password or tag ~= db.tag then
    SetConfig(ch, pw, tag, "Guild Info")
    Debug("config from Guild Info: channel=%s tag=%s officerRank=%d", ch, tostring(tag), db.officerRank or 1)
    Print("settings loaded from Guild Info (channel: " .. ch .. ").")
  end
end

-- Leaders: Blizzard blocks addons from writing Guild Info (protected function),
-- so show the line in a copy box for the leader to paste in by hand.
-- Own copy window (Blizzard's StaticPopup is protected against addons).
local copyFrame
local function ShowCopyBox(line)
  if not copyFrame then
    local fr = CreateFrame("Frame", "CORELinkCopyFrame", UIParent, "BackdropTemplate")
    fr:SetSize(440, 100)
    fr:SetPoint("CENTER", 0, 150)
    fr:SetFrameStrata("DIALOG")
    fr:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    fr:SetBackdropColor(0, 0, 0, 0.9)
    fr:EnableMouse(true)
    fr:SetMovable(true)
    fr:RegisterForDrag("LeftButton")
    fr:SetScript("OnDragStart", fr.StartMoving)
    fr:SetScript("OnDragStop", fr.StopMovingOrSizing)

    local t = fr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOP", 0, -14)
    t:SetWidth(400)
    t:SetText("CORELink: press Ctrl+C to copy, then paste into Guild Info")

    local eb = CreateFrame("EditBox", nil, fr, "InputBoxTemplate")
    eb:SetSize(390, 24)
    eb:SetPoint("TOP", 0, -50)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function() fr:Hide() end)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    local x = CreateFrame("Button", nil, fr, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", -2, -2)

    fr.edit = eb
    copyFrame = fr
  end
  copyFrame:Show()
  copyFrame.edit:SetText(line)
  copyFrame.edit:SetFocus()
  copyFrame.edit:HighlightText()
end

local function Publish()
  if not Configured() then Print("nothing to share yet. Run /cl setup first.") return end
  local line = BuildLine()
  db.lastGI = line
  Print("Guild Info line (paste it into your Guild Info text):")
  Print(line)
  pcall(ShowCopyBox, line)
end

---------------------------------------------------------------- class lookup
local function ClassOf(author, guid)
  if guid and not issecret(guid) and GetPlayerInfoByGUID then
    local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
    if ok and type(class) == "string" then return class end
  end
  if IsMe(author, guid) then
    local _, class = UnitClass("player")
    return class or ""
  end
  return ""
end

---------------------------------------------------------------- officers
local function RefreshRoster()
  if not IsInGuild() then return end
  wipe(rankOf); wipe(rankNameOf)
  for i = 1, (GetNumGuildMembers() or 0) do
    local name, rankName, rankIndex, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
    if not name then break end
    name = Ambiguate(name, "none")
    rankOf[name] = rankIndex
    rankNameOf[name] = rankName
    if guid and not issecret(guid) then rosterGuid[guid] = name end
    if myGUID and guid and not issecret(guid) and guid == myGUID then LearnMyName(name) end
  end
end

local function IsGuildmate(name, guid)
  if guid and rosterGuid[guid] then return true end
  return name ~= nil and rankOf[name] ~= nil
end

-- Did the other delivery path show a line from this author in the last few seconds? Consumes the match.
local function CrossSeen(author, via)
  local list = recentFrom[author]
  local t = GetTime()
  if list then
    for i = #list, 1, -1 do
      local e = list[i]
      if t - e.t > CROSS_SECS then table.remove(list, i)
      elseif e.via ~= via and not e.used then e.used = true return true end
    end
  else
    list = {}; recentFrom[author] = list
  end
  list[#list + 1] = { t = t, via = via }
  return false
end

-- Returns the author's guild rank name if they are at or above the officer
-- cutoff, otherwise nil.
local function OfficerRank(author)
  if not db or db.officer == false then return nil end
  local rank, rankName
  if IsMe(author) then
    local _, rn, r = GetGuildInfo("player")
    rank, rankName = r, rn
  else
    rank, rankName = rankOf[author], rankNameOf[author]
  end
  if rank == nil or rank > (db.officerRank or 1) then return nil end
  rankName = (type(rankName) == "string" and rankName ~= "") and rankName or "Officer"
  return (rankName:gsub("[~|]", "")):sub(1, 20)
end

local function HexToRGB(hex)
  hex = (hex and hex:match("^%x%x%x%x%x%x$")) and hex or DEFAULT_OFFICER_COLOR
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

---------------------------------------------------------------- nicknames
local function CleanNick(str)
  str = (str or ""):gsub("[~|%c]", "")
  str = str:gsub("^%s+", ""):gsub("%s+$", "")
  return str:sub(1, 20)
end

-- (Rank Nickname) for officers with a nickname, (Rank) for officers without,
-- (Nickname) for everyone else, nothing if neither applies.
local function BuildTag(rank, nick)
  if nick and nick ~= "" then
    if rank then return "(" .. rank .. " " .. nick .. ") " end
    return "(" .. nick .. ") "
  end
  if rank then return "(" .. rank .. ") " end
  return ""
end

local function SendGuildAddon(text)
  if not IsInGuild() or Locked() then return end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "GUILD")
  end
end

local function BroadcastNick()
  SendGuildAddon("NICK" .. SEP .. (db.nicks[MyName()] or ""))
end

-- Messages on the guild addon channel: NICK~<name> and NREQ (please re-send).
local function OnGuildAddon(text, sender)
  if issecret(text) or issecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
  sender = Ambiguate(sender, "none")
  addonUsers[sender] = GetTime()
  local cmd, rest = text:match("^(%a+)" .. SEP .. "?(.*)$")
  if cmd == "CARRIED" then
    -- a guildmate posted these lines to the community: drop them from our piggyback queue
    local now = GetTime()
    for id in rest:gmatch("[^,]+") do carried[id] = now end
    for i = #carry, 1, -1 do if carried[carry[i].id] then table.remove(carry, i) end end
  elseif cmd == "NICK" then
    local n = CleanNick(rest)
    db.nicks[sender] = (n ~= "") and n or nil
  elseif cmd == "NREQ" then
    if not IsMe(sender) and db.nicks[MyName()] then
      C_Timer.After(1 + math.random() * 6, BroadcastNick)
    end
  elseif cmd == "BRIDGE" then
    OnBridgeReceived(rest, sender)
  elseif cmd == "HEARD" then
    -- HEARD~<realm>~tag1,tag2: a guildmate reports which guild tags it hears on its realm
    local realm, tags = rest:match("^([^" .. SEP .. "]*)" .. SEP .. "(.*)$")
    if not realm or realm == "" then return end
    local now = GetTime()
    guildRealms[realm] = now
    for tag in (tags or ""):gmatch("[^,]+") do
      NoteHeard(tag, realm, now)
      -- That guild reaches the guildmate's realm but has not reached ours in 10 minutes: no relay here.
      if realm ~= MyRealm() and tag ~= GetTag() and not coverageWarned[tag]
         and not (heard[tag] and now - heard[tag] < 600) and now > 600 then
        coverageWarned[tag] = true
        Print(string.format("guild %s is reaching %s but not %s: it has no member running CORELink on your realm. /cl guilds for details.", tag, realm, MyRealm()))
      end
    end
  end
end

-- Tell our guild (across realms) which tags we hear on our realm; at most once a minute, only when it changed
-- or every 5 minutes.
local function BroadcastHeard()
  if not db or not db.enabled or not Configured() or not IsInGuild() then return end
  local now, tags = GetTime(), {}
  for tag, t in pairs(heard) do if now - t <= 600 then tags[#tags + 1] = tag end end
  table.sort(tags)
  local sig = table.concat(tags, ",")
  if sig == lastHeardSig and now - lastHeardSent < 300 then return end
  lastHeardSent, lastHeardSig = now, sig
  SendGuildAddon("HEARD" .. SEP .. MyRealm() .. SEP .. sig:sub(1, 200))
end

-- Do we know of guildmates on a realm other than ours? (learned from HEARD reports)
local function HasGuildmatesElsewhere()
  local now, mine = GetTime(), MyRealm()
  for realm, t in pairs(guildRealms) do
    if realm ~= mine and now - t <= 600 then return true end
  end
  return false
end

local function BridgeEnabled() return db and db.enabled and db.bridge ~= false and Configured() end

-- Heard a foreign guild's line on our realm's channel: forward it to our guild for other realms.
local function ForwardToGuild(id, text)
  if not BridgeEnabled() or not HasGuildmatesElsewhere() then return end
  if #text + 7 > 255 then bridgeStats.skipped = bridgeStats.skipped + 1 return end
  C_Timer.After(0.3 + math.random() * 1.2, function()
    if bridged[id] then return end          -- a guildmate on our realm already forwarded it
    bridged[id] = GetTime()
    bridgeStats.forwarded = bridgeStats.forwarded + 1
    SendGuildAddon("BRIDGE" .. SEP .. text)
    Debug("bridged %s to the guild for other realms", id)
  end)
end

-- A guildmate forwarded a foreign line it heard on its realm: if it has not reached ours, re-send it here.
OnBridgeReceived = function(text, sender)
  local id = text:match("^CL%d+" .. SEP .. "(%x+)" .. SEP)
  if not id then return end
  bridged[id] = GetTime()
  if IsMe(sender) then return end
  if not BridgeEnabled() then return end
  if seen[id] then return end              -- already on our realm's channel (same-realm guildmate forwarded it)
  pending[id] = true
  C_Timer.After(0.3 + math.random() * 1.2, function()
    if not pending[id] or seen[id] then pending[id] = nil return end   -- someone else re-sent it meanwhile
    pending[id] = nil
    seen[id] = GetTime()
    table.insert(sendQueue, text)          -- verbatim packet; receivers display it as the original guild's line
    bridgeStats.resent = bridgeStats.resent + 1
    Debug("re-sent bridged %s from %s into %s", id, sender, tostring(db.channel))
  end)
end

local function Split(rest, n)   -- n fields; the last one takes the remainder
  local out, pos = {}, 1
  for i = 1, n - 1 do
    local e = rest:find(SEP, pos, true)
    if not e then return nil end
    out[i] = rest:sub(pos, e - 1)
    pos = e + 1
  end
  out[n] = rest:sub(pos)
  return unpack(out, 1, n)
end

---------------------------------------------------------------- relay out
local function Relay(id, tag, author, msg, class, flags, nick)
  pending[id] = nil
  seen[id] = GetTime()
  local head = table.concat({ PROTO, id, tag, author, class or "", flags or "", nick or "" }, SEP) .. SEP
  table.insert(sendQueue, head .. Trim(msg, 245 - #PREFIX - #head))
  Debug("queued relay %s from %s (%d bytes, queue %d)", id, author, #head + #msg, #sendQueue)
end

local function OnGuildMessage(msg, author, _, _, _, _, _, _, _, _, _, guid)
  if not db.enabled or not Configured() or Locked() then return end
  if issecret(msg) or issecret(author) or not msg or msg == "" then return end
  local tag = GetTag()
  if not tag then return end
  author = Ambiguate(author, "none")
  local mine = IsMe(author, guid)      -- also learns our chat-format name from our own messages
  local class = ClassOf(author, guid)
  local rn = OfficerRank(author)
  local flags = rn and ("O" .. rn) or ""
  local nick = db.nicks[author]
  local id = Hash(tag .. author .. msg)
  local now = GetTime()
  if (seen[id] and now - seen[id] < DEDUPE_SECS) or pending[id] then return end
  pending[id] = true
  if mine then
    Relay(id, tag, author, msg, class, flags, nick)
  else
    if db.mirror ~= false and db.club and not (addonUsers[author] and now - addonUsers[author] < ADDON_USER_SECS)
       and not carried[id] then
      carry[#carry + 1] = { id = id, author = author, text = msg, t = now, rank = rn, nick = nick }
      while #carry > CARRY_MAX do table.remove(carry, 1) end
    end
    -- random back-off: normally only one member's client relays
    C_Timer.After(0.3 + math.random() * 1.2, function()
      if pending[id] and not (seen[id] and GetTime() - seen[id] < DEDUPE_SECS) then
        Relay(id, tag, author, msg, class, flags, nick)
      end
      pending[id] = nil
    end)
  end
end

---------------------------------------------------------------- relay in
-- Chat windows that have Guild messages enabled (so bridged lines appear in the
-- same tab as /g). Override with /cl window <n>.
local function GuildFrames()
  if db.window then
    local f = _G["ChatFrame" .. db.window]
    if f then return { f } end
  end
  local frames = {}
  local get = GetChatWindowMessages or (C_ChatInfo and C_ChatInfo.GetChatWindowMessages)
  if get then
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
      local f = _G["ChatFrame" .. i]
      if f then
        local ok, groups = pcall(function() return { get(i) } end)
        if ok and type(groups) == "table" then
          for _, g in ipairs(groups) do
            if g == "GUILD" then frames[#frames + 1] = f break end
          end
        end
      end
    end
  end
  if #frames == 0 then frames[1] = DEFAULT_CHAT_FRAME end
  return frames
end

local function Display(tag, author, class, msg, officerLabel, nick, textHasPrefix)
  local c = ChatTypeInfo["GUILD"] or { r = .25, g = 1, b = .25 }
  local prefix = textHasPrefix and "" or BuildTag(officerLabel, (db.showNick ~= false) and nick or nil)
  if officerLabel then
    local r, g, b = HexToRGB(db.officerColorHex)
    c = { r = r, g = g, b = b }
  end
  local name = "[" .. author .. "]"
  if db.classColor ~= false and class and class ~= "" then
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc then
      name = string.format("|cff%02x%02x%02x%s|r", math.floor(cc.r * 255 + 0.5), math.floor(cc.g * 255 + 0.5), math.floor(cc.b * 255 + 0.5), name)
    end
  end
  -- msg may be sealed community text: it can be concatenated and drawn, but not formatted or inspected
  local line = (tag and ("[" .. tag .. "] ") or "") .. "|Hplayer:" .. author .. "|h" .. name .. "|h: " .. prefix .. msg
  for _, f in ipairs(GuildFrames()) do
    f:AddMessage(line, c.r, c.g, c.b)
  end
end

local function OnLinkMessage(text)
  if issecret(text) or not text then return end
  local proto, rest = text:match("^(%w+)" .. SEP .. "(.*)$")
  local id, tag, author, class, flags, msg, nick
  if proto == "CARRY" then
    -- "<poster>~<n>": the next n community lines from that character are carried copies of lines already
    -- relayed on this realm; reserve relay slots so the community copies are dropped
    local poster, n = rest:match("^([^" .. SEP .. "]+)" .. SEP .. "(%d+)$")
    if poster then
      local list = recentFrom[poster] or {}
      recentFrom[poster] = list
      for _ = 1, math.min(tonumber(n) or 0, CARRY_MAX) do list[#list + 1] = { t = GetTime(), via = "relay" } end
    end
    return
  elseif proto == "CL4" then
    id, tag, author, class, flags, nick, msg = Split(rest, 7)
    if id and not id:match("^%x+$") then id = nil end
  elseif proto == "CL3" then
    id, tag, author, class, flags, msg = rest:match("^(%x+)" .. SEP .. "([^" .. SEP .. "]*)" .. SEP ..
      "([^" .. SEP .. "]*)" .. SEP .. "([^" .. SEP .. "]*)" .. SEP .. "([^" .. SEP .. "]*)" .. SEP .. "(.*)$")
  elseif proto == "CL2" then
    id, tag, author, class, msg = rest:match("^(%x+)" .. SEP .. "([^" .. SEP .. "]*)" .. SEP ..
      "([^" .. SEP .. "]*)" .. SEP .. "([^" .. SEP .. "]*)" .. SEP .. "(.*)$")
  elseif proto == "CL1" then
    id, tag, author, msg = rest:match("^(%x+)" .. SEP .. "([^" .. SEP .. "]*)" .. SEP ..
      "([^" .. SEP .. "]*)" .. SEP .. "(.*)$")
  else
    return
  end
  if not id then return end
  seen[id] = GetTime()
  heard[tag] = GetTime()
  NoteHeard(tag, MyRealm(), GetTime())
  pending[id] = nil                  -- another client already relayed it
  if msg == "" then return end       -- presence beacon, nothing to display
  if tag ~= GetTag() and not bridged[id] then ForwardToGuild(id, text) end
  if displayed[id] then return end
  displayed[id] = GetTime()
  if tag == GetTag() then Debug("ignored %s packet %s: own guild tag", proto, id) return end -- own guild saw it natively
  if db.muted[tag:lower()] then Debug("ignored %s packet %s: tag %s muted", proto, id, tag) return end
  Debug("showing %s packet %s from %s <%s>", proto, id, author, tag)
  local label
  if db.officer ~= false and flags and flags:sub(1, 1) == "O" then
    label = (flags:sub(2):gsub("[~|]", ""))
    if label == "" then label = "Officer" end
  end
  if class and class ~= "" then authorClass[author] = class end
  authorOfficer[author] = label                    -- nil clears a stale officer label
  authorSeen[author] = true
  nick = CleanNick(nick)
  authorNick[author] = nick ~= "" and nick or nil
  if CrossSeen(author, "relay") then Debug("skipped %s packet %s: shown from the community", proto, id) return end
  Display(tag, author, class, msg, label, nick ~= "" and nick or nil)
end

---------------------------------------------------------------- status
local function StatusLine()
  if not Configured() then return "NOT CONFIGURED. Guild leaders: /cl setup <channel> <password> [tag]" end
  return string.format("%s | tag: %s | channel: %s (%s) | config: %s%s",
    db.enabled and "ON" or "OFF", tostring(GetTag()), db.channel,
    ChannelId() and "joined" or "not joined", db.source or "local",
    Locked() and " | PAUSED (chat lockdown)" or "")
end

-- Login: the guild roster, Guild Info text and the channel list all arrive at different times after
-- PLAYER_LOGIN, so retry the read-and-join a few times (5s, 10s, 15s ... up to ~75s) instead of once.
-- Equivalent to the player typing /cl reload, then /cl once it is connected.
local loginAttempts = 0
---------------------------------------------------------------- community mirror
-- "club=" names the community by numeric id, short name or full name (spaces dropped: Core Test -> CoreTest).
-- Names are looked up in the communities this character belongs to, so only members resolve them; that is
-- fine, since only members can post to or read the community anyway.
local function ResolveClubId()
  if not db or not db.club then return nil end
  if db.clubId then return db.clubId end
  local n = tonumber(db.club)
  if n then db.clubId = n return n end
  if not C_Club or not C_Club.GetSubscribedClubs then return nil end
  local ok, clubs = pcall(C_Club.GetSubscribedClubs)
  if not ok or type(clubs) ~= "table" then return nil end
  local want = db.club:lower()
  local found
  for _, c in ipairs(clubs) do
    local short, name = c.shortName, c.name
    if type(short) == "string" and not issecret(short) and short:lower() == want
      or type(name) == "string" and not issecret(name) and (name:lower():gsub("%s", "")) == want then
      -- several communities can share a short name: prefer a World of Warcraft (character) community
      if not found or (c.clubType == 1 and found.clubType ~= 1) then found = c end
    end
  end
  if not found then return nil end
  db.clubId = found.clubId
  Debug("community %s is club %s", db.club, tostring(found.clubId))
  return db.clubId
end

-- 1 = World of Warcraft (character) community: the community window already shows the character as the
-- author, so posted lines carry only the tag. 0 = Battle.net community: it shows account names, so the
-- character name goes into the text.
local function ClubIsCharacter()
  if mirror.clubType == nil then
    local id = ResolveClubId()
    if id and C_Club and C_Club.GetClubInfo then
      local ok, info = pcall(C_Club.GetClubInfo, id)
      if ok and type(info) == "table" and type(info.clubType) == "number" then mirror.clubType = info.clubType end
    end
  end
  return mirror.clubType == 1
end

local function ClubMember()
  local id = ResolveClubId()
  if not id or not C_Club or not C_Club.GetClubInfo then return false end
  local ok, info = pcall(C_Club.GetClubInfo, id)
  return ok and info ~= nil
end

local function ClubStream()
  if mirror.streamId then return mirror.streamId end
  local id = ResolveClubId()
  if not id or not C_Club or not C_Club.GetStreams then return nil end
  local ok, streams = pcall(C_Club.GetStreams, id)
  if not ok or type(streams) ~= "table" then return nil end
  local best
  for _, st in ipairs(streams) do
    if st.name == "General" then best = st.streamId break end
    if not best or (st.streamId and st.streamId < best) then best = st.streamId end
  end
  mirror.streamId = best
  return best
end

-- Called from the chat hooks, i.e. inside the keypress that sent the guild line. Two hooks can fire for
-- one line (edit box and SendChatMessage), so the same text within a second is posted once.
local function MirrorTypedLine(text)
  if not db or db.mirror == false or not Configured() then return end
  if text == mirror.lastText and GetTime() - mirror.lastAt < 1 then return end
  mirror.lastText, mirror.lastAt = text, GetTime()
  local id = ResolveClubId()
  if not id or not C_Club or not C_Club.SendMessage or not ClubMember() then return end
  local stream = ClubStream()
  if not stream then return end
  FocusClubStream()                 -- posting fails with "Couldn't send message" until the stream is loaded
  local tag = GetTag() or "?"
  local me = MyName()
  local nick = (db.showNick ~= false) and db.nicks[me] or nil
  local line
  if ClubIsCharacter() then
    -- the rank and nickname travel in the text: readers cannot inspect community text, but they can draw it
    line = string.format("[%s] %s%s", tag, BuildTag(OfficerRank(me), nick), text)
  else
    line = string.format("[%s] %s%s: %s", tag, me, nick and (" (" .. nick .. ")") or "", text)
  end
  local ok, err = pcall(C_Club.SendMessage, id, stream, line:sub(1, 250))
  if ok then mirror.posted = mirror.posted + 1
  else mirror.failed = mirror.failed + 1; mirror.focused = false; Debug("mirror failed: %s", tostring(err)) return end
  -- carry guildmates' waiting lines in this keypress: "[TAG] Name (Rank Nick): text"
  local now, ids = GetTime(), {}
  for k, t in pairs(carried) do if now - t > 600 then carried[k] = nil end end
  for _, e in ipairs(carry) do
    if now - e.t <= CARRY_SECS and not carried[e.id] then
      local who = BuildTag(e.rank, (db.showNick ~= false) and e.nick or nil)
      who = e.author .. (who ~= "" and (" " .. who:sub(1, -2)) or "")
      local okc = pcall(C_Club.SendMessage, id, stream, ("[" .. tag .. "] " .. who .. ": " .. e.text):sub(1, 250))
      if okc then carried[e.id] = now; ids[#ids + 1] = e.id; mirror.carried = mirror.carried + 1 end
    end
  end
  wipe(carry)
  if #ids > 0 then
    SendGuildAddon("CARRIED" .. SEP .. table.concat(ids, ","))
    table.insert(sendQueue, "CARRY" .. SEP .. me .. SEP .. #ids)
    Debug("carried %d guild line(s) into the community", #ids)
  end
end

-- Typed in a chat box whose type is already Guild.
local function OnEditBoxParseText(editBox, send)
  if send ~= 1 or not editBox or not editBox.GetAttribute then return end
  if editBox:GetAttribute("chatType") ~= "GUILD" then return end
  local text = editBox:GetText()
  if type(text) ~= "string" or not text:match("%S") or text:sub(1, 1) == "/" then return end
  MirrorTypedLine(text)
end

-- Any guild send: "/g text" typed in another chat type, macros, other addons.
local function OnSendChatMessage(msg, chatType)
  if type(chatType) ~= "string" or issecret(chatType) or chatType:upper() ~= "GUILD" then return end
  if type(msg) ~= "string" or issecret(msg) or not msg:match("%S") then return end
  MirrorTypedLine(msg)
end

local function InstallMirrorHooks()
  if mirror.hooks ~= "not installed" then return end
  local got = {}
  if ChatFrame1EditBox and ChatFrame1EditBox.ParseText then
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
      local eb = _G["ChatFrame" .. i .. "EditBox"]
      if eb and eb.ParseText then hooksecurefunc(eb, "ParseText", OnEditBoxParseText); got.editbox = true end
    end
  elseif ChatEdit_ParseText then
    hooksecurefunc("ChatEdit_ParseText", OnEditBoxParseText); got.editbox = true
  end
  if SendChatMessage then hooksecurefunc("SendChatMessage", OnSendChatMessage); got.send = true end
  if C_ChatInfo and C_ChatInfo.SendChatMessage then hooksecurefunc(C_ChatInfo, "SendChatMessage", OnSendChatMessage); got.send = true end
  mirror.hooks = (got.editbox and got.send and "editbox+send") or (got.editbox and "editbox") or (got.send and "send")
    or "FAILED (no chat hooks)"
end

local function RemindAboutClub()
  if mirror.reminded or not db or not db.club or db.mirror == false then return end
  if not C_Club then return end
  mirror.reminded = true
  FocusClubStream()
  if not ClubMember() then
    Print("your guild mirrors chat into community " .. db.club .. " but this character is not a member"
      .. (ResolveClubId() and "" or " (or no community you belong to has that name)")
      .. ". Ask the Guild Master for the invite link; linked guilds' lines then show in your guild chat.")
  end
end

-- Subscribe to the club stream so CLUB_MESSAGE_ADDED fires for it.
FocusClubStream = function()
  if mirror.focused or not C_Club or not C_Club.FocusStream then return end
  local id = ResolveClubId()
  local stream = ClubStream()
  if not id or not stream or not ClubMember() then return end
  if pcall(C_Club.FocusStream, id, stream) then mirror.focused = true end
end

local function Plain(v) if v == nil or issecret(v) then return nil end return v end

-- The character behind a community post: the message's author record, completed from the member list.
-- WoW communities give the character name, guid and class; Battle.net communities give the account name.
local function ClubAuthor(clubId, author)
  local name, guid, classID, role = Plain(author.name), Plain(author.guid), Plain(author.classID), nil
  local mid = Plain(author.memberId)
  if mid and C_Club.GetMemberInfo then
    local ok, m = pcall(C_Club.GetMemberInfo, clubId, mid)
    if ok and type(m) == "table" then
      name = Plain(m.name) or name
      guid = Plain(m.guid) or guid
      classID = classID or Plain(m.classID)
      role = Plain(m.role)
    end
  end
  if name == "" then name = nil end
  return name, guid, classID, role
end

-- Officer colour for a community author. The relay packet is authoritative when we have heard one from this
-- character; otherwise (other realm, community only) a community role of Owner, Leader or Moderator counts.
local function ClubOfficerLabel(who, role)
  if not db or db.officer == false then return nil end
  if authorSeen[who] then return authorOfficer[who] end
  if type(role) == "number" and role >= 1 and role <= 3 then return "Officer" end
  return nil
end

local CLUB_LINE_FULL = "^%[([^%]]+)%] ([^:(]+)%s?%(?([^):]*)%)?: (.*)$"   -- [TAG] Name (nick): text
local CLUB_LINE_TAG = "^%[([^%]]+)%] (.*)$"                                -- [TAG] text

-- A message arrived in the club: show it in guild chat unless it is ours, our own guild's, muted, or already
-- shown from the relay channel. Community text may be sealed (drawable, not readable): then the tag cannot be
-- checked and the line is shown under the author's name, de-duplicated by author and time instead of by hash.
-- The author record can lag the message by a moment, so an authorless message is retried a few times.
local CLUB_RETRY = { 0.5, 1, 2 }
local function OnClubMessage(clubId, streamId, messageId, attempt)
  if not db or db.mirrorRead == false or clubId ~= ResolveClubId() then return end
  if streamId ~= ClubStream() then return end
  if not C_Club or not C_Club.GetMessageInfo then return end
  local ok, info = pcall(C_Club.GetMessageInfo, clubId, streamId, messageId)
  if not ok or type(info) ~= "table" or info.content == nil or info.destroyed then return end
  local author = info.author or {}
  if author.isSelf == true then return end
  local name, guid, classID, role = ClubAuthor(clubId, author)
  if not name and not guid then
    attempt = (attempt or 0) + 1
    if CLUB_RETRY[attempt] then
      C_Timer.After(CLUB_RETRY[attempt], function() OnClubMessage(clubId, streamId, messageId, attempt) end)
      return
    end
  end
  if (guid and myGUID and guid == myGUID) or (name and IsMe(name, guid)) then return end
  if IsGuildmate(name, guid) then return end          -- our own guild: already in our guild chat
  local content = info.content
  local tag, pname, nick, msg
  -- Community text reaches addons as a Kstring placeholder ("|Kw158|k", measured 2026-10-13 on Forever): the
  -- chat frame draws the real text, the addon holds only this client-local token. Not a secret value, but
  -- unreadable all the same, and meaningless on any other client, so it cannot be forwarded.
  local sealed = type(content) ~= "string" or issecret(content) or content:match("^|K.*|k$") ~= nil
  if not sealed then
    local okp, t, a, b, c = pcall(string.match, content, CLUB_LINE_FULL)
    if okp and t then tag, pname, nick, msg = t, (a:gsub("%s+$", "")), b, c
    else
      okp, t, a = pcall(string.match, content, CLUB_LINE_TAG)
      if okp and t then tag, msg = t, a end
    end
  end
  local who = pname or name or "?"
  local class = ""
  if classID and GetClassInfo then
    local okc, _, token = pcall(GetClassInfo, classID)
    if okc and type(token) == "string" then class = token end
  end
  if class == "" then class = authorClass[who] or "" end
  local label = ClubOfficerLabel(who, role)
  nick = (nick and nick ~= "" and nick) or authorNick[who]
  if tag then
    if tag == GetTag() then return end
    if db.muted[tag:lower()] then return end
    local id = Hash(tag .. who .. msg)
    if displayed[id] then return end                         -- already shown from the relay channel
    displayed[id] = GetTime(); seen[id] = GetTime()
    heard[tag] = GetTime(); NoteHeard(tag, "community", GetTime())
    CrossSeen(who, "club")
    mirror.shown = mirror.shown + 1
    -- "[TAG] text" lines (WoW community) already carry "(Rank Nick)" in the text; the full format does not
    Display(tag, who, class, msg, label, nick, pname == nil)
  else
    C_Timer.After(CLUB_SHOW_DELAY, function()
      if CrossSeen(who, "club") then mirror.skipped = mirror.skipped + 1 return end
      mirror.shown = mirror.shown + 1
      Display(nil, who, class, content, label, nick, true)
    end)
  end
end

local function LoginSync()
  if not db then return end
  loginAttempts = loginAttempts + 1
  db.lastGI = nil                  -- nothing is "unchanged" at login: always re-read Guild Info
  ReadGuildInfo()
  EnsureChannel()
  Debug("login sync %d: configured=%s joined=%s", loginAttempts, tostring(Configured() and true or false), tostring(ChannelId() ~= nil))
  if Configured() and ChannelId() then
    Print(StatusLine())
    FocusClubStream()                 -- subscribe to the community stream now; the reminder retries in 10 s
    C_Timer.After(10, RemindAboutClub)
    return
  end
  if loginAttempts < 6 then
    C_Timer.After(5 * loginAttempts, LoginSync)
    return
  end
  -- "Not configured" was already reported by the 20 s notice below; this line is for a configured client
  -- whose channel join did not happen.
  if not Configured() then return end
  local why
  if not IsInGuild() then why = "you are not in a guild"
  elseif conn.lastNotice then why = "the game answered " .. conn.lastNotice .. " when joining " .. db.channel
  else why = "joining " .. db.channel .. " got no answer from the server" end
  Print("not connected after login: " .. why .. ". Run /cl report and share it, or /cl reload to retry.")
end

---------------------------------------------------------------- filters
-- Recolour officers' messages in real guild chat (this client only).
ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", function(self, event, msg, author, ...)
  if not db or issecret(msg) or issecret(author) or type(msg) ~= "string" or type(author) ~= "string" then
    return false
  end
  local who = Ambiguate(author, "none")
  local nick = (db.showNick ~= false) and db.nicks[who] or nil
  local rn = OfficerRank(who)
  local tagText = BuildTag(rn, nick)
  if rn then
    return false, "|cff" .. (db.officerColorHex or DEFAULT_OFFICER_COLOR) .. tagText .. msg .. "|r", author, ...
  end
  if tagText ~= "" then return false, tagText .. msg, author, ... end
  return false
end)

local function ChannelFilter(self, event, msg, author, lang, channelString)
  if IsLinkChannel(channelString) then return true end
end
for _, ev in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_NOTICE",
                      "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
  ChatFrame_AddMessageEventFilter(ev, ChannelFilter)
end

-- The community also appears as a normal chat channel ("Community:<club>:<stream>") when it is checked in a
-- chat window. While we show its lines in guild chat, hide the raw copies so nobody reads everything twice.
local function IsClubChannel(name)
  if type(name) ~= "string" or issecret(name) then return false end
  local c, st = name:match("^[Cc]ommunity:(%d+):(%d+)")
  if not c then return false end
  local id, stream = ResolveClubId(), ClubStream()
  return id ~= nil and tonumber(c) == id and (stream == nil or tonumber(st) == stream)
end
ChatFrame_AddMessageEventFilter("CHAT_MSG_COMMUNITIES_CHANNEL", function(self, event, msg, author, lang, channelString, _, _, _, _, channelBaseName)
  if not db or db.mirrorRead == false or db.hideClub == false then return false end
  if IsClubChannel(channelString) or IsClubChannel(channelBaseName) then mirror.hidden = mirror.hidden + 1 return true end
  return false
end)

---------------------------------------------------------------- events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_GUILD")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("CHANNEL_UI_UPDATE")
f:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
f:RegisterEvent("CLUB_MESSAGE_ADDED")
f:RegisterEvent("CLUB_ERROR")

local lastRead, warned = 0, false
f:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    if (...) ~= ADDON then return end
    CORELinkDB = CORELinkDB or {}
    db = CORELinkDB
    if db.enabled == nil then db.enabled = true end
    db.debug = false          -- debug echo is per session: always off at login, /cl debug on to enable
    db.muted = db.muted or {}
    db.nicks = db.nicks or {}
    if db.clubId and not db.club then db.club = tostring(db.clubId) end   -- saved by versions before club names
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
      C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
  elseif event == "PLAYER_LOGIN" then
    myGUID = UnitGUID and UnitGUID("player") or nil
    mirror.reminded = false
    InstallMirrorHooks()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
    elseif GuildRoster then GuildRoster() end
    C_Timer.After(5, LoginSync)
    C_Timer.After(25, function()
      if db.nicks[MyName()] then BroadcastNick() end
      SendGuildAddon("NREQ")
    end)
    C_Timer.After(20, function()
      if not Configured() and not warned then
        warned = true
        Print("not configured: " .. conn.giState .. ". Guild leaders: /cl setup <channel> <password> [tag]")
      end
    end)
  elseif event == "GUILD_ROSTER_UPDATE" then
    if GetTime() - lastRead > 5 then lastRead = GetTime(); RefreshRoster(); ReadGuildInfo() end
  elseif event == "CHANNEL_UI_UPDATE" then
    -- the channel system just became ready (or changed); make sure we are in the link channel
    if Configured() then EnsureChannel() end
  elseif event == "CLUB_MESSAGE_ADDED" then
    local clubId, streamId, messageId = ...
    OnClubMessage(clubId, streamId, messageId)
  elseif event == "CLUB_ERROR" then
    local action, err = ...
    Debug("community error: action=%s error=%s", tostring(action), tostring(err))
    mirror.focused = false            -- load the stream again before the next post
  elseif event == "CHAT_MSG_CHANNEL_NOTICE" then
    local notice, _, _, channelName, _, _, _, _, channelBaseName = ...
    OnChannelNotice(notice, channelName, channelBaseName)
  elseif event == "CHAT_MSG_GUILD" then
    OnGuildMessage(...)
  elseif event == "CHAT_MSG_ADDON" then
    local prefix, text, chatType, sender, _, _, localId, chanName = ...
    if prefix ~= PREFIX then return end
    if chatType == "GUILD" then
      OnGuildAddon(text, sender)
    elseif chatType == "CHANNEL" then
      if IsLinkChannel(chanName) or (localId and localId == ChannelId()) then
        OnLinkMessage(text)
      end
    end
  end
end)

-- 1 channel message per second
C_Timer.NewTicker(1, function()
  if not db then return end
  local text = table.remove(sendQueue, 1)
  if not text then return end
  if Locked() then wipe(sendQueue) return end   -- cannot send during lockdown
  local id = ChannelId()
  if id and C_ChatInfo and C_ChatInfo.SendAddonMessage then
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "CHANNEL", tostring(id))
    lastSendResult = ok and tostring(res) or "error"
    Debug("sent on channel %d -> result %s", id, lastSendResult)
    if lastSendResult ~= "0" and lastSendResult ~= "true" and lastSendResult ~= "nil"
       and GetTime() - lastFailNotice > 60 then        -- at most one notice a minute, never per packet
      lastFailNotice = GetTime()
      Print("relay send failed (result " .. lastSendResult .. "). Run /cl report and share it.")
    end
  end
end)

-- presence beacon: lets /cl guilds show which guilds are on the link even when
-- nobody is chatting. Skipped if a member of our own guild beaconed recently.
C_Timer.NewTicker(30, function()
  if not db or not db.enabled or not Configured() or Locked() or not ChannelId() then return end
  local tag = GetTag()
  if not tag then return end
  local now = GetTime()
  if heard[tag] and now - heard[tag] < 120 then return end
  if math.random() > 0.34 then return end
  local id = Hash(tag .. now)
  seen[id] = now
  table.insert(sendQueue, table.concat({ PROTO, id, tag, "", "", "", "", "" }, SEP))
end)

-- housekeeping, re-read Guild Info, rejoin if dropped
C_Timer.NewTicker(60, function()
  if not db then return end
  local now = GetTime()
  for k, v in pairs(seen) do if now - v > 60 then seen[k] = nil end end
  for k, v in pairs(displayed) do if now - v > 60 then displayed[k] = nil end end
  for tag, realms in pairs(heardRealms) do
    for realm, t in pairs(realms) do if now - t > 600 then realms[realm] = nil end end
    if next(realms) == nil then heardRealms[tag] = nil end
  end
  for realm, t in pairs(guildRealms) do if now - t > 600 then guildRealms[realm] = nil end end
  for k, v in pairs(bridged) do if now - v > 60 then bridged[k] = nil end end
  BroadcastHeard()
  ReadGuildInfo()
  EnsureChannel()
  FocusClubStream()
  if C_GuildInfo and C_GuildInfo.GuildRoster and math.random() < 0.5 then C_GuildInfo.GuildRoster() end
end)

---------------------------------------------------------------- slash cmds
SLASH_CORELINK1, SLASH_CORELINK2 = "/corelink", "/cl"
-- Only the guild master (rank 0) may change the shared configuration. Everything that affects only this
-- client (on, off, mute, unmute, reload, display toggles) is open to every member.
local GM_ONLY = {
  setup = true, channel = true, password = true, tag = true, publish = true,
  officerrank = true, clear = true,
}

local function IsGM()
  local _, _, rankIndex = GetGuildInfo("player")
  return rankIndex == 0
end

SlashCmdList["CORELINK"] = function(input)
  local cmd, arg = input:match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if GM_ONLY[cmd] and not IsGM() then
    Print("only the guild master can use /cl " .. cmd .. ".")
    return
  end
  if cmd == "setup" then
    local ch, pw, tag = arg:match("^(%S+)%s+(%S+)%s*(%S*)")
    if not ch then
      Print("usage: /cl setup <channel> <password> [tag]   (use - for no password)")
      return
    end
    pw = (pw == "-") and "" or Clean(pw)
    tag = (tag ~= "" and tag ~= "-") and Clean(tag):sub(1, 8) or nil
    SetConfig(Clean(ch), pw, tag, "local")
    Print("configured. Channel: " .. Clean(ch) .. ", tag: " .. tostring(tag or "auto"))
    Publish()
  elseif cmd == "channel" and arg ~= "" then
    SetConfig(Clean(arg), db.password or "", db.tag, "local")
    Print("channel set to " .. Clean(arg) .. ". Use /cl publish to get the Guild Info line for your guild.")
  elseif cmd == "password" then
    if not Configured() then Print("set a channel first: /cl channel <name>") return end
    local pw = (arg == "" or arg == "-") and "" or Clean(arg)
    SetConfig(db.channel, pw, db.tag, "local")
    Print("password updated. Use /cl publish to get the Guild Info line for your guild.")
  elseif cmd == "tag" then
    local t = (arg ~= "" and arg:lower() ~= "auto") and Clean(arg):sub(1, 8) or nil
    db.tag, db.source = t, "local"
    Print("guild tag: " .. tostring(GetTag()) .. ". Use /cl publish to get the Guild Info line for your guild.")
  elseif cmd == "publish" then
    Publish()
  elseif cmd == "officercolor" then
    local a = arg:lower():gsub("^#", "")
    if a:match("^%x%x%x%x%x%x$") then
      db.officerColorHex = a; Print("officer colour set to #" .. a)
    elseif a == "reset" then
      db.officerColorHex = nil; Print("officer colour reset to the default (#e8c63e).")
    else
      local r, g, b = HexToRGB(db.officerColorHex)
      local function Save()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        db.officerColorHex = string.format("%02x%02x%02x", nr * 255 + 0.5, ng * 255 + 0.5, nb * 255 + 0.5)
      end
      local prev = db.officerColorHex
      local ok = pcall(function()
        if ColorPickerFrame.SetupColorPickerAndShow then
          ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = Save,
            cancelFunc = function() db.officerColorHex = prev end,
          })
        else
          ColorPickerFrame.func = Save
          ColorPickerFrame.cancelFunc = function() db.officerColorHex = prev end
          ColorPickerFrame.hasOpacity = false
          ColorPickerFrame:SetColorRGB(r, g, b)
          ColorPickerFrame:Hide(); ColorPickerFrame:Show()
        end
      end)
      if not ok then Print("couldn't open the colour picker. Use /cl officercolor RRGGBB instead (e.g. e8c63e).") end
    end
  elseif cmd == "officer" then
    db.officer = not (arg:lower() == "off")
    Print("officer highlighting: " .. (db.officer and "on" or "off"))
  elseif cmd == "officerrank" then
    local n = tonumber(arg)
    if n and n >= 0 then
      db.officerRank = math.floor(n)
      Print("ranks 0 to " .. db.officerRank .. " count as officers (0 = guild master). /cl publish to share via Guild Info.")
    else
      Print("officer rank cutoff: " .. (db.officerRank or 1) .. " (usage: /cl officerrank <n>)")
    end
  elseif cmd == "nickname" then
    local me = MyName()
    if arg == "" then
      Print("your nickname: " .. (db.nicks[me] or "(none)") .. "  (usage: /cl nickname <name> | clear)")
    elseif arg:lower() == "clear" then
      db.nicks[me] = nil; BroadcastNick(); Print("nickname cleared.")
    else
      local n = CleanNick(arg)
      if n == "" then Print("that nickname isn't valid.") return end
      db.nicks[me] = n; BroadcastNick()
      Print("nickname set to " .. n .. ". Your guild and linked guilds will see it.")
      if Locked() then Print("(sharing is paused right now; it will sync after you leave the instance.)") end
    end
  elseif cmd == "nicknames" then
    db.showNick = not (arg:lower() == "off")
    Print("showing nicknames: " .. (db.showNick and "on" or "off"))
  elseif cmd == "mirror" then
    local what, val = arg:lower():match("^(%a*)%s*(%a*)$")
    if what == "read" then db.mirrorRead = (val ~= "off")
    elseif what == "post" then db.mirror = (val ~= "off")
    elseif what == "hide" then db.hideClub = (val ~= "off")
    else db.mirror = (what ~= "off"); db.mirrorRead = (what ~= "off") end
    Print(string.format("community mirror: post %s, read %s, hide raw community lines %s%s", (db.mirror ~= false) and "on" or "off",
      (db.mirrorRead ~= false) and "on" or "off", (db.hideClub ~= false) and "on" or "off",
      db.club and (" (community " .. db.club .. ")") or " (no club= token in Guild Info)"))
    FocusClubStream()
  elseif cmd == "bridge" then
    db.bridge = not (arg:lower() == "off")
    Print("cross-realm bridging: " .. (db.bridge and "on" or "off") .. " (forward other guilds' lines to your guildmates on other realms)")
  elseif cmd == "classcolor" then
    db.classColor = not (arg:lower() == "off")
    Print("class-coloured names: " .. (db.classColor and "on" or "off"))
  elseif cmd == "debug" then
    db.debug = (arg:lower() == "on")
    Print("debug output: " .. (db.debug and "on (also kept in /cl report)" or "off"))
  elseif cmd == "report" then
    local heardTags = {}
    for tag, t in pairs(heard) do if GetTime() - t <= 600 then heardTags[#heardTags + 1] = tag end end
    local nSeen, nDisp, nNick = 0, 0, 0
    for _ in pairs(seen) do nSeen = nSeen + 1 end
    for _ in pairs(displayed) do nDisp = nDisp + 1 end
    for _ in pairs(db.nicks) do nNick = nNick + 1 end
    local report = table.concat({
      "CORELink " .. Version(),
      "proto " .. PROTO,
      db.enabled and "enabled" or "disabled",
      Configured() and ("channel " .. db.channel .. " id " .. tostring(ChannelId() or "not joined")) or "not configured",
      "tag " .. tostring(Configured() and GetTag() or nil),
      "config " .. tostring(db.source),
      "officerRank " .. tostring(db.officerRank or 1),
      "inGuild " .. tostring(IsInGuild()),
      "guildInfo " .. conn.giState,
      "joinAttempts " .. conn.joinAttempts,
      "lastNotice " .. (conn.lastNotice and (conn.lastNotice .. " at " .. conn.lastNoticeAt) or "none"),
      "joinHold " .. (GetTime() < conn.blockedUntil and tostring(conn.blockedWhy) or "no"),
      "lockdown " .. tostring(Locked()),
      "lastSend " .. tostring(lastSendResult),
      "queue " .. #sendQueue,
      "realm " .. MyRealm(),
      "heard " .. (#heardTags > 0 and table.concat(heardTags, ",") or "none"),
      "reach " .. (function()
        local out = {}
        for tag, realms in pairs(heardRealms) do
          local rs = {}
          for realm, t in pairs(realms) do if GetTime() - t <= 600 then rs[#rs + 1] = realm end end
          table.sort(rs)
          if #rs > 0 then out[#out + 1] = tag .. "@" .. table.concat(rs, "+") end
        end
        table.sort(out)
        return #out > 0 and table.concat(out, ",") or "none"
      end)(),
      string.format("tables seen=%d displayed=%d nicks=%d", nSeen, nDisp, nNick),
      string.format("mirror post=%s read=%s club=%s id=%s type=%s member=%s stream=%s posted=%d carried=%d waiting=%d failed=%d shown=%d skipped=%d hidden=%d focused=%s hooks=%s",
        (db.mirror ~= false) and "on" or "off", (db.mirrorRead ~= false) and "on" or "off", tostring(db.club),
        tostring(ResolveClubId()), (db.club and ClubIsCharacter()) and "wow" or tostring(mirror.clubType),
        tostring(db.club and ClubMember()), tostring(db.club and ClubStream()), mirror.posted, mirror.carried, #carry,
        mirror.failed, mirror.shown, mirror.skipped, mirror.hidden, tostring(mirror.focused), mirror.hooks),
      string.format("bridge %s fwd=%d resent=%d skipped=%d elsewhere=%s", (db.bridge ~= false) and "on" or "off",
        bridgeStats.forwarded, bridgeStats.resent, bridgeStats.skipped, tostring(HasGuildmatesElsewhere())),
      "debug " .. tostring(db.debug == true),
      "log: " .. (#debugLog > 0 and table.concat(debugLog, " / ") or "empty"),
    }, " | ")
    Print("report (also in the copy box, Ctrl+C and paste it to whoever is helping):")
    Print(report)
    pcall(ShowCopyBox, report)
  elseif cmd == "guilds" then
    local now, n, mine = GetTime(), 0, MyRealm()
    for tag, t in pairs(heard) do if now - t > 600 then heard[tag] = nil end end
    local tags = {}
    for tag in pairs(heardRealms) do tags[#tags + 1] = tag end
    table.sort(tags)
    for _, tag in ipairs(tags) do
      local parts = {}
      for realm, t in pairs(heardRealms[tag]) do
        if now - t <= 600 then parts[#parts + 1] = string.format("%s (%ds ago)", realm, math.floor(now - t)) end
      end
      if #parts > 0 then
        n = n + 1
        table.sort(parts)
        local note = ""
        if not (heard[tag] and now - heard[tag] <= 600) and tag ~= GetTag() then note = " | NOT reaching " .. mine end
        Print(string.format("%s%s - %s%s", tag, tag == GetTag() and " (your guild)" or "", table.concat(parts, ", "), note))
      end
    end
    if n == 0 then Print("no guilds heard on the link in the last 10 minutes.") end
    local realms = {}
    for realm in pairs(guildRealms) do realms[#realms + 1] = realm end
    if not guildRealms[mine] then realms[#realms + 1] = mine end
    table.sort(realms)
    Print("your realm: " .. mine .. " | your guild runs CORELink on: " .. table.concat(realms, ", "))
  elseif cmd == "window" then
    local n = tonumber(arg)
    if n and _G["ChatFrame" .. n] then
      db.window = n; Print("bridged messages will show in chat window " .. n .. ".")
    else
      db.window = nil; Print("bridged messages will show in the window(s) that have Guild chat enabled.")
    end
  elseif cmd == "reload" then
    db.lastGI = nil; conn.blockedUntil = 0; conn.blockedWhy = nil
    ReadGuildInfo(); EnsureChannel(); Print("re-read Guild Info and retried the channel.")
  elseif cmd == "clear" then
    LeaveLink(); db.channel, db.password, db.tag, db.source, db.lastGI = nil, nil, nil, nil, nil
    Print("settings cleared.")
  elseif cmd == "on" then
    db.enabled = true; EnsureChannel(); Print("enabled.")
  elseif cmd == "off" then
    db.enabled = false; LeaveLink(); Print("disabled.")
  elseif cmd == "mute" and arg ~= "" then
    db.muted[arg:lower()] = true; Print("muted guild tag " .. arg)
  elseif cmd == "unmute" and arg ~= "" then
    db.muted[arg:lower()] = nil; Print("unmuted guild tag " .. arg)
  else
    Print(StatusLine())
    if Configured() and lastSendResult then Print("last send result: " .. lastSendResult .. " (0 = success)") end
    if IsGM() then
      Print("/cl setup | channel | password | tag | publish | guilds | nickname | nicknames | classcolor | officer | officercolor | officerrank | window | bridge on|off | mirror on|off|read off|post off | reload | clear | on | off | mute | unmute | report | debug on|off")
    else
      Print("/cl reload | on | off | mute <tag> | unmute <tag> | nickname <name> | nicknames on|off | classcolor on|off | officercolor | officer on|off | guilds | window | bridge on|off | mirror on|off|read off|post off | report | debug on|off")
    end
  end
end
