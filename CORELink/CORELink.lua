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
local guildRealms = {}      -- realm -> last time one of our own guildmates reported from it
local lastHeardSent, lastHeardSig = 0, ""
local coverageWarned = {}   -- tag -> true once we warned that it is not reaching our realm
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
    if myGUID and guid and not issecret(guid) and guid == myGUID then LearnMyName(name) end
  end
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
  local cmd, rest = text:match("^(%a+)" .. SEP .. "?(.*)$")
  if cmd == "NICK" then
    local n = CleanNick(rest)
    db.nicks[sender] = (n ~= "") and n or nil
  elseif cmd == "NREQ" then
    if not IsMe(sender) and db.nicks[MyName()] then
      C_Timer.After(1 + math.random() * 6, BroadcastNick)
    end
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
  if sig == "" then return end
  if sig == lastHeardSig and now - lastHeardSent < 300 then return end
  lastHeardSent, lastHeardSig = now, sig
  SendGuildAddon("HEARD" .. SEP .. MyRealm() .. SEP .. sig:sub(1, 200))
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

local function Display(tag, author, class, msg, officerLabel, nick)
  local c = ChatTypeInfo["GUILD"] or { r = .25, g = 1, b = .25 }
  local prefix = BuildTag(officerLabel, (db.showNick ~= false) and nick or nil)
  if officerLabel then
    local r, g, b = HexToRGB(db.officerColorHex)
    c = { r = r, g = g, b = b }
  end
  msg = prefix .. msg
  local name = "[" .. author .. "]"
  if db.classColor ~= false and class and class ~= "" then
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc then
      name = string.format("|cff%02x%02x%02x%s|r", cc.r * 255, cc.g * 255, cc.b * 255, name)
    end
  end
  local line = string.format("[%s] |Hplayer:%s|h%s|h: %s", tag, author, name, msg)
  for _, f in ipairs(GuildFrames()) do
    f:AddMessage(line, c.r, c.g, c.b)
  end
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
  nick = CleanNick(nick)
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
local function LoginSync()
  if not db then return end
  loginAttempts = loginAttempts + 1
  db.lastGI = nil                  -- nothing is "unchanged" at login: always re-read Guild Info
  ReadGuildInfo()
  EnsureChannel()
  Debug("login sync %d: configured=%s joined=%s", loginAttempts, tostring(Configured() and true or false), tostring(ChannelId() ~= nil))
  if Configured() and ChannelId() then
    Print(StatusLine())
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

---------------------------------------------------------------- events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_GUILD")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("CHANNEL_UI_UPDATE")
f:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")

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
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
      C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
  elseif event == "PLAYER_LOGIN" then
    myGUID = UnitGUID and UnitGUID("player") or nil
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
  BroadcastHeard()
  ReadGuildInfo()
  EnsureChannel()
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
      Print("/cl setup | channel | password | tag | publish | guilds | nickname | nicknames | classcolor | officer | officercolor | officerrank | window | reload | clear | on | off | mute | unmute | report | debug on|off")
    else
      Print("/cl reload | on | off | mute <tag> | unmute <tag> | nickname <name> | nicknames on|off | classcolor on|off | officercolor | officer on|off | guilds | window | report | debug on|off")
    end
  end
end
