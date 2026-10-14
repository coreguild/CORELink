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
                 focused = false, hidden = 0, lastText = nil, lastAt = 0, skipped = 0, clubType = nil }
-- A line can reach us twice: on the relay channel (readable) and in the community (text sealed, so it cannot be
-- hashed). Each displayed line is remembered by author and time; the other path's copy within a few seconds is dropped.
local recentFrom = {}   -- author -> { { t = time, via = "relay"|"club" }, ... }
local CROSS_SECS = 5
local addonUsers = {}       -- guildmate -> last time a CORELink guild message came from them
local ADDON_USER_SECS = 900
-- Whisper bridge: "guilds=Name One, Name Two" on the Guild Info line names the collective. Each guild's courier
-- on a realm (alphabetically first guildmate running the addon there) asks the server who is online in each
-- guild (silent /who), greets a few of them over whisper addon messages, and remembers who answered (peers;
-- a player without the addon never answers). A line heard on this realm is whispered to one peer on every
-- realm that would not otherwise get it; that peer drops it into its own realm's channel. Whispers need no
-- keypress and are the only cross-realm path not tied to a guild or a community.
local peers = {}             -- "Name-Realm" -> { tag=, realm=, guild=, seen= }  (saved in db.peers)
local guildOnline = {}       -- guild name -> realm -> { n = online count, t = time }  (from /who)
local helloAt = {}           -- whisper target -> last hello time
local courierSeen = {}       -- guildmate -> { realm=, t= } from their HEARD reports (courier election)
local whisperQueue = {}      -- { target=, text= }
local whisperStats = { who = 0, hello = 0, answered = 0, sent = 0, recv = 0 }
local whoQueue, whoPending, whoNext = {}, nil, 0
local WHO_EVERY, HELLO_EVERY, PEER_ONLINE_SECS, PEER_KEEP_SECS, HELLO_PER_GUILD = 600, 600, 1200, 7 * 86400, 3
-- Echo: with "echo=on" on the Guild Info line, one addon user per guild re-posts other guilds' readable lines
-- (relay and bridge; community text cannot be read) as real guild messages, so members without the addon see
-- them. The first client to claim a line (ECHO~id over the guild addon channel) posts it. Addon users hide
-- the echoed line and never relay, carry or mirror it, so nothing loops.
local echoed = {}           -- line id -> time it was claimed/echoed
local echoStats = { sent = 0, hidden = 0 }
local echoing = false       -- true while our own echo send runs, so the chat hooks ignore it
local FocusClubStream       -- defined after the reminder that calls it
local MaybeEcho             -- defined after Display
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
    .. (db.echo and " echo=on" or "")
    .. ((db.guilds and #db.guilds > 0) and (" guilds=" .. table.concat(db.guilds, ", ")) or "")
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
  local guildsText = line:match("[%s]guilds=(.*)$")
  db.guilds = {}
  for raw in (guildsText or ""):gmatch("[^,]+") do
    local g = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if g ~= "" then db.guilds[#db.guilds + 1] = g end
  end
  if guildsText then line = line:sub(1, (line:find("[%s]guilds=") or 0)) end   -- keep the short tokens parseable
  local echo = line:match("[%s]echo=(%w+)")
  db.echo = (echo ~= nil) and (echo:lower() == "on" or echo == "1" or echo:lower() == "yes") or false
  local club = line:match("[%s]club=([^%s]+)")
  if club ~= db.club then
    db.club, db.clubId = club, nil          -- the id is resolved from the token when first needed
    mirror.streamId, mirror.streams, mirror.focused, mirror.clubType = nil, nil, false, nil
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

-- An echoed line in real guild chat: "[TAG] Name (Rank Nick): text" sent by a guildmate who runs the addon.
local function IsEchoLine(msg, sender)
  if not db or not db.echo or type(msg) ~= "string" then return false end
  local seenAt = addonUsers[sender]
  if not ((seenAt and GetTime() - seenAt < ADDON_USER_SECS) or IsMe(sender)) then return false end
  local tag = msg:match("^%[([^%]]+)%] [^:]+: ")
  return tag ~= nil and tag ~= GetTag()
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
  if cmd == "ECHO" then
    echoed[rest] = GetTime()              -- a guildmate is echoing this line: we do not
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
    courierSeen[sender] = { realm = realm, t = now }
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

---------------------------------------------------------------- whisper bridge
-- Our guild's courier on this realm: the alphabetically first guildmate (us included) seen running the addon
-- here in the last 6 minutes. Every client computes the same answer.
local function IsCourier()
  local me, now, mine = MyName(), GetTime(), MyRealm()
  local first = me
  for name, c in pairs(courierSeen) do
    if c.realm == mine and now - c.t <= 360 and name < first then first = name end
  end
  return first == me
end

local function WhisperAvailable() return C_ChatInfo and C_ChatInfo.SendAddonMessage and not Locked() end
local function QueueWhisper(target, text)
  if not WhisperAvailable() then return end
  whisperQueue[#whisperQueue + 1] = { target = target, text = text }
end

local function PeerName(key) return (key:match("^([^-]+)")) or key end

local function RememberPeer(key, tag, realm, guild)
  if not key or key == "" or not tag or tag == "" then return end
  local p = peers[key] or {}
  p.tag, p.realm, p.guild, p.seen = tag, (realm ~= "" and realm) or p.realm or "?", (guild ~= "" and guild) or p.guild, GetTime()
  peers[key] = p
  if db then db.peers = peers end
  NoteHeard(tag, p.realm, GetTime())
end

local function Hello(target, kind)
  local now = GetTime()
  if helloAt[target] and now - helloAt[target] < HELLO_EVERY then return end
  helloAt[target] = now
  whisperStats.hello = whisperStats.hello + 1
  local g = GetGuildInfo("player") or ""
  QueueWhisper(target, (kind or "HELLO") .. SEP .. (GetTag() or "?") .. SEP .. MyRealm() .. SEP .. g:gsub(SEP, ""))
end

-- Up to ~240 bytes of "name@realm@tag@guild;" so one good contact teaches the rest.
local function Directory()
  local now, out, size = GetTime(), {}, 0
  for key, p in pairs(peers) do
    if now - p.seen <= PEER_ONLINE_SECS then
      local e = key .. "@" .. (p.realm or "?") .. "@" .. p.tag .. "@" .. (p.guild or "")
      if size + #e + 1 > 230 then break end
      out[#out + 1] = e; size = size + #e + 1
    end
  end
  return table.concat(out, ";")
end

-- Silent /who per guild of the collective, one at a time, never while the player's Who window is open.
local function WhoAvailable()
  return C_FriendList and C_FriendList.SendWho and C_FriendList.GetNumWhoResults and C_FriendList.GetWhoInfo
end
local function RunWho()
  if whoPending or #whoQueue == 0 or not WhoAvailable() then return end
  if FriendsFrame and FriendsFrame.IsShown and FriendsFrame:IsShown() then C_Timer.After(30, RunWho) return end
  local g = table.remove(whoQueue, 1)
  whoPending = { guild = g, at = GetTime() }
  if C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, true) end
  local ok = pcall(C_FriendList.SendWho, 'g-"' .. g .. '"')
  if not ok then whoPending = nil return end
  whisperStats.who = whisperStats.who + 1
  C_Timer.After(6, function() if whoPending and whoPending.guild == g then whoPending = nil; RunWho() end end)
end
local function ScheduleWho()
  if not db or not db.guilds or #db.guilds == 0 or not IsCourier() then return end
  if GetTime() < whoNext then return end
  whoNext = GetTime() + WHO_EVERY
  wipe(whoQueue)
  local mineName = GetGuildInfo("player")
  for _, g in ipairs(db.guilds) do if g ~= mineName then whoQueue[#whoQueue + 1] = g end end
  RunWho()
end

local function OnWhoList()
  if not whoPending then return end
  local g = whoPending.guild
  whoPending = nil
  local n = C_FriendList.GetNumWhoResults() or 0
  local mine, now = MyRealm(), GetTime()
  local counts, candidates = {}, {}
  for i = 1, n do
    local okw, info = pcall(C_FriendList.GetWhoInfo, i)
    local full = okw and type(info) == "table" and info.fullName
    if type(full) == "string" and not issecret(full) and full ~= "" then
      local name, realm = full:match("^([^-]+)-(.+)$")
      name, realm = name or full, realm or mine
      counts[realm] = (counts[realm] or 0) + 1
      if not IsMe(name) then candidates[#candidates + 1] = { key = full, realm = realm } end
    end
  end
  guildOnline[g] = guildOnline[g] or {}
  for realm, c in pairs(counts) do guildOnline[g][realm] = { n = c, t = now } end
  Debug("who %s: %d online", g, n)
  -- greet a few members on realms where we have no live peer of this guild yet
  local greeted, perRealm = 0, {}
  for _, c in ipairs(candidates) do
    local havePeer = false
    for key, p in pairs(peers) do
      if p.guild == g and p.realm == c.realm and now - p.seen <= PEER_ONLINE_SECS and key ~= c.key then havePeer = true break end
    end
    perRealm[c.realm] = perRealm[c.realm] or 0
    if not havePeer and perRealm[c.realm] < HELLO_PER_GUILD and greeted < HELLO_PER_GUILD * 2 then
      perRealm[c.realm] = perRealm[c.realm] + 1; greeted = greeted + 1
      Hello(c.key)
    end
  end
  C_Timer.After(3, RunWho)
end

-- A line heard natively on our realm: whisper it to one peer on every realm that would not otherwise get it
-- (no addon user of the origin guild there, no guildmate of ours there to bridge it).
local function WhisperOut(id, tag, text)
  if not db or db.whisper == false or not IsCourier() or not WhisperAvailable() then return end
  local now, mine = GetTime(), MyRealm()
  local best = {}
  for key, p in pairs(peers) do
    local realm = p.realm
    if realm and realm ~= mine and now - p.seen <= PEER_ONLINE_SECS
       and not (heardRealms[tag] and heardRealms[tag][realm] and now - heardRealms[tag][realm] <= 600)
       and not (guildRealms[realm] and now - guildRealms[realm] <= 600) then
      if not best[realm] or p.seen > peers[best[realm]].seen then best[realm] = key end
    end
  end
  for realm, key in pairs(best) do
    QueueWhisper(key, "WB" .. SEP .. text)
    whisperStats.sent = whisperStats.sent + 1
    Debug("whispered %s to %s (%s on %s)", id, PeerName(key), peers[key].tag, realm)
  end
end

local function OnWhisperAddon(text, sender)
  if issecret(text) or issecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
  local cmd, rest = text:match("^(%a+)" .. SEP .. "?(.*)$")
  if cmd == "HELLO" or cmd == "PEER" then
    local tag, realm, guild = rest:match("^([^" .. SEP .. "]*)" .. SEP .. "([^" .. SEP .. "]*)" .. SEP .. "(.*)$")
    if not tag then return end
    RememberPeer(sender, tag, realm, guild)
    whisperStats.answered = whisperStats.answered + 1
    if cmd == "HELLO" then
      local g = GetGuildInfo("player") or ""
      QueueWhisper(sender, "PEER" .. SEP .. (GetTag() or "?") .. SEP .. MyRealm() .. SEP .. g:gsub(SEP, ""))
      local dir = Directory()
      if dir ~= "" then QueueWhisper(sender, "DIR" .. SEP .. dir) end
    end
  elseif cmd == "DIR" then
    -- gossip: names worth greeting, never trusted as live peers until they answer a hello of ours
    local greeted = 0
    for entry in rest:gmatch("[^;]+") do
      local key, realm, tag, guild = entry:match("^([^@]+)@([^@]*)@([^@]*)@(.*)$")
      if key and tag ~= "" and not IsMe(PeerName(key)) and not peers[key] and greeted < 6 then
        peers[key] = { tag = tag, realm = realm, guild = guild, seen = 0 }   -- known, not yet confirmed
        if db then db.peers = peers end
        greeted = greeted + 1
        Hello(key)
      end
    end
  elseif cmd == "WB" then
    if not db or db.whisper == false then return end
    whisperStats.recv = whisperStats.recv + 1
    if peers[sender] then peers[sender].seen = GetTime() end
    OnBridgeReceived(rest, sender)
  end
end

-- Keep live peers fresh: couriers ping known peers every 10 minutes; anyone answers.
local function PeerUpkeep()
  if not db then return end
  local now = GetTime()
  for key, p in pairs(peers) do
    if now - p.seen > PEER_KEEP_SECS then peers[key] = nil
    elseif IsCourier() and p.seen > 0 and now - p.seen > HELLO_EVERY then Hello(key, "HELLO") end
  end
  if db then db.peers = peers end
  ScheduleWho()
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
  if IsEchoLine(msg, author) then return end   -- a guildmate's echo of another guild's line: not ours to relay
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

-- One client per guild re-posts the line into real guild chat for members without the addon. Random back-off
-- then a claim, like the relay courier, so two addon users rarely echo the same line.
MaybeEcho = function(id, tag, author, msg, label, nick)
  if not db.echo or db.echoer == false or not IsInGuild() or echoed[id] or not SendChatMessage then return end
  C_Timer.After(0.3 + math.random() * 1.2, function()
    if echoed[id] or Locked() or not db.echo then return end
    local now = GetTime()
    echoed[id] = now
    for k, t in pairs(echoed) do if now - t > 600 then echoed[k] = nil end end
    SendGuildAddon("ECHO" .. SEP .. id)
    local who = BuildTag(label, (db.showNick ~= false) and nick or nil)
    who = author .. (who ~= "" and (" " .. who:sub(1, -2)) or "")
    echoing = true
    local ok = pcall(SendChatMessage, Trim("[" .. tag .. "] " .. who .. ": " .. msg, 250), "GUILD")
    echoing = false
    if ok then echoStats.sent = echoStats.sent + 1; Debug("echoed %s into guild chat", id) end
  end)
end

local function OnLinkMessage(text)
  if issecret(text) or not text then return end
  local proto, rest = text:match("^(%w+)" .. SEP .. "(.*)$")
  local id, tag, author, class, flags, msg, nick
  if proto == "CL4" then
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
  if not bridged[id] and not displayed[id] then WhisperOut(id, tag, text) end
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
  MaybeEcho(id, tag, author, msg, label, nick ~= "" and nick or nil)
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

local function StreamKey(name) return (name:lower():gsub("[%s%-_]", "")) end

-- The community's channels (streams) we use: id -> name. Community text is unreadable, so a guild's tag
-- travels in the channel name instead: each guild posts into the channel named after its tag when the
-- community has one, and readers take the tag from the channel. A channel counts as a guild channel when its
-- description mentions CORELink, or its name is our tag or a tag we have heard; anything else in the community
-- (an Officers or Raids channel, say) is left alone. Guilds without a channel use General with the tag in the text.
local function ClubStreams()
  if mirror.streams then return mirror.streams end
  local id = ResolveClubId()
  if not id or not C_Club or not C_Club.GetStreams then return nil end
  local ok, streams = pcall(C_Club.GetStreams, id)
  if not ok or type(streams) ~= "table" then return nil end
  local map, general, lowest = {}, nil, nil
  local myTag = GetTag()
  for _, st in ipairs(streams) do
    if type(st.streamId) == "number" and type(st.name) == "string" and not issecret(st.name) then
      local key = StreamKey(st.name)
      local subject = (type(st.subject) == "string" and not issecret(st.subject)) and st.subject:lower() or ""
      local isGuild = not st.leadersAndModeratorsOnly and (subject:find("corelink", 1, true) ~= nil
        or (myTag and key == StreamKey(myTag)) or false)
      if not isGuild then
        for tag in pairs(heard) do if StreamKey(tag) == key then isGuild = true break end end
      end
      if st.name == "General" then
        general = st.streamId; map[st.streamId] = st.name
      elseif isGuild then
        map[st.streamId] = st.name
      end
      if not lowest or st.streamId < lowest then lowest = st.streamId end
    end
  end
  if lowest then
    if not general then general = lowest; map[lowest] = map[lowest] or "General" end
    mirror.streams = map
    mirror.general = general
  end
  return mirror.streams
end

-- The channel this guild posts into: the one named after our tag, else General.
local function ClubStream()
  if mirror.streamId then return mirror.streamId end
  local streams = ClubStreams()
  if not streams then return nil end
  local tag = GetTag()
  local best = mirror.general
  if tag then
    local want = StreamKey(tag)
    for sid, name in pairs(streams) do
      if StreamKey(name) == want then best = sid break end
    end
  end
  mirror.streamId = best
  return best
end

-- The guild tag a community channel stands for, or nil for General.
local function StreamTag(streamId)
  local streams = ClubStreams()
  if not streams or streamId == mirror.general then return nil end
  return streams[streamId]
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
  local tagChannel = StreamTag(stream) ~= nil      -- our own channel: the tag is the channel name
  if ClubIsCharacter() then
    -- the rank and nickname travel in the text: readers cannot inspect community text, but they can draw it
    line = (tagChannel and "" or ("[" .. tag .. "] ")) .. BuildTag(OfficerRank(me), nick) .. text
  else
    line = string.format("[%s] %s%s: %s", tag, me, nick and (" (" .. nick .. ")") or "", text)
  end
  local ok, err = pcall(C_Club.SendMessage, id, stream, line:sub(1, 250))
  if ok then mirror.posted = mirror.posted + 1
  else mirror.failed = mirror.failed + 1; mirror.focused = false; Debug("mirror failed: %s", tostring(err)) end
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
  if echoing then return end
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
  local streams = ClubStreams()
  if not id or not streams or not ClubMember() then return end
  local all = true
  for sid in pairs(streams) do
    if not pcall(C_Club.FocusStream, id, sid) then all = false end
  end
  if C_Club.FocusCommunityStreams then pcall(C_Club.FocusCommunityStreams) end
  mirror.focused = all
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
  local streams = ClubStreams()
  if not streams or not streams[streamId] then return end
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
  local channelTag = StreamTag(streamId)
  if channelTag then
    tag = channelTag                                   -- the channel is the guild: text is "(Rank Nick) text"
  elseif not sealed then
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
  if tag and ((GetTag() and StreamKey(tag) == StreamKey(GetTag())) or db.muted[tag:lower()]) then return end
  if channelTag then
    -- "[TAG] [Name]: (Rank Nick) text", the same shape as a relayed line; the text itself stays unreadable
    heard[tag] = GetTime(); NoteHeard(tag, "community", GetTime())
    if CrossSeen(who, "club") then mirror.skipped = mirror.skipped + 1 return end
    mirror.shown = mirror.shown + 1
    Display(tag, who, class, content, label, nick, true)
  elseif tag then
    local id = Hash(tag .. who .. msg)
    if displayed[id] then return end                         -- already shown from the relay channel
    displayed[id] = GetTime(); seen[id] = GetTime()
    heard[tag] = GetTime(); NoteHeard(tag, "community", GetTime())
    CrossSeen(who, "club")
    mirror.shown = mirror.shown + 1
    -- "[TAG] text" lines (WoW community) already carry "(Rank Nick)" in the text; the full format does not
    Display(tag, who, class, msg, label, nick, pname == nil)
  else
    if CrossSeen(who, "club") then mirror.skipped = mirror.skipped + 1 return end
    mirror.shown = mirror.shown + 1
    Display(nil, who, class, content, label, nick, true)
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
  if IsEchoLine(msg, who) then echoStats.hidden = echoStats.hidden + 1 return true end
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
  local id, streams = ResolveClubId(), ClubStreams()
  return id ~= nil and tonumber(c) == id and (streams == nil or streams[tonumber(st)] ~= nil)
end
ChatFrame_AddMessageEventFilter("CHAT_MSG_COMMUNITIES_CHANNEL", function(self, event, msg, author, lang, channelString, _, _, _, _, channelBaseName)
  if not db or db.mirrorRead == false or db.hideClub == false then return false end
  if IsClubChannel(channelString) or IsClubChannel(channelBaseName) then mirror.hidden = mirror.hidden + 1 return true end
  return false
end)

-- A hello to someone who logged off makes the game print "No player named 'X' is currently playing."; hide it
-- when it is about a name we whispered in the last few seconds, and forget that peer for now.
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(self, event, msg)
  if issecret(msg) or type(msg) ~= "string" then return false end
  local name = msg:match("^No player named '([^']+)' is currently playing")
  if not name then return false end
  local now = GetTime()
  for key, t in pairs(helloAt) do
    if now - t <= 10 and (key == name or PeerName(key) == name or key:gsub("%-.*$", "") == name) then
      if peers[key] then peers[key].seen = 0 end
      return true
    end
  end
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
f:RegisterEvent("WHO_LIST_UPDATE")
f:RegisterEvent("CLUB_STREAMS_LOADED")
f:RegisterEvent("CLUB_STREAM_ADDED")
f:RegisterEvent("CLUB_STREAM_REMOVED")

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
    if type(db.peers) == "table" then peers = db.peers end
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
    C_Timer.After(45, ScheduleWho)
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
  elseif event == "WHO_LIST_UPDATE" then
    OnWhoList()
  elseif event == "CLUB_STREAMS_LOADED" or event == "CLUB_STREAM_ADDED" or event == "CLUB_STREAM_REMOVED" then
    if (...) == ResolveClubId() then
      mirror.streams, mirror.streamId, mirror.focused = nil, nil, false
      FocusClubStream()
    end
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
    elseif chatType == "WHISPER" then
      OnWhisperAddon(text, sender)
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
  local w = table.remove(whisperQueue, 1)
  if w and not Locked() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, w.text, "WHISPER", w.target)
  end
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
C_Timer.NewTicker(60, PeerUpkeep)
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
  elseif cmd == "whisper" then
    db.whisper = not (arg:lower() == "off")
    Print("whisper bridge: " .. (db.whisper and "on" or "off"))
  elseif cmd == "who" then
    whoNext = 0
    if not db.guilds or #db.guilds == 0 then Print("no guilds= list on the CORELink line in Guild Info.")
    elseif not IsCourier() then Print("a guildmate is the courier on " .. MyRealm() .. "; only the courier queries.")
    else ScheduleWho(); Print("asking who is online in " .. #db.guilds .. " guild(s).") end
  elseif cmd == "peers" then
    local now, n = GetTime(), 0
    local keys = {}
    for key in pairs(peers) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
      local p = peers[key]
      n = n + 1
      Print(string.format("%s - %s on %s (%s) %s", PeerName(key), p.tag, tostring(p.realm), p.guild or "?",
        p.seen == 0 and "not yet answered" or (now - p.seen <= PEER_ONLINE_SECS and ("seen " .. math.floor(now - p.seen) .. "s ago") or "offline")))
    end
    if n == 0 then Print("no peers yet. Guild leaders: add guilds=<name>, <name> to the CORELink line in Guild Info.") end
    Print("courier on " .. MyRealm() .. ": " .. (IsCourier() and "you" or "a guildmate"))
  elseif cmd == "echo" then
    db.echoer = not (arg:lower() == "off")
    Print("this client " .. (db.echoer and "may echo" or "will not echo") .. " other guilds' lines into guild chat"
      .. (db.echo and "" or " (echo is off for this guild: the Guild Master adds echo=on to the CORELink line)"))
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
      string.format("mirror post=%s read=%s club=%s id=%s type=%s member=%s stream=%s channels=%d posted=%d failed=%d shown=%d skipped=%d hidden=%d focused=%s hooks=%s",
        (db.mirror ~= false) and "on" or "off", (db.mirrorRead ~= false) and "on" or "off", tostring(db.club),
        tostring(ResolveClubId()), (db.club and ClubIsCharacter()) and "wow" or tostring(mirror.clubType),
        tostring(db.club and ClubMember()), (function()
          local sid = db.club and ClubStream()
          if not sid then return "nil" end
          return sid .. ":" .. (StreamTag(sid) or "General")
        end)(), (function() local n = 0 for _ in pairs(ClubStreams() or {}) do n = n + 1 end return n end)(),
        mirror.posted, mirror.failed, mirror.shown, mirror.skipped, mirror.hidden, tostring(mirror.focused), mirror.hooks),
      string.format("whisper %s courier=%s guilds=%d peers=%d who=%d hello=%d answered=%d sent=%d recv=%d",
        (db.whisper ~= false) and "on" or "off", tostring(IsCourier()), db.guilds and #db.guilds or 0,
        (function() local n = 0 for _, p in pairs(peers) do if GetTime() - p.seen <= PEER_ONLINE_SECS then n = n + 1 end end return n end)(),
        whisperStats.who, whisperStats.hello, whisperStats.answered, whisperStats.sent, whisperStats.recv),
      string.format("bridge %s fwd=%d resent=%d skipped=%d elsewhere=%s", (db.bridge ~= false) and "on" or "off",
        bridgeStats.forwarded, bridgeStats.resent, bridgeStats.skipped, tostring(HasGuildmatesElsewhere())),
      string.format("echo %s me=%s sent=%d hidden=%d", db.echo and "on" or "off", (db.echoer ~= false) and "on" or "off", echoStats.sent, echoStats.hidden),
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
    local names = {}
    for g in pairs(guildOnline) do names[#names + 1] = g end
    table.sort(names)
    for _, g in ipairs(names) do
      local parts = {}
      for realm, e in pairs(guildOnline[g]) do parts[#parts + 1] = string.format("%s: %d online", realm, e.n) end
      table.sort(parts)
      Print(string.format("%s - %s", g, table.concat(parts, ", ")))
    end
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
