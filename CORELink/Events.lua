-- CORELink/Events.lua: the event frame, login, and housekeeping.
-- Every file registers its handlers in NS.events; this file creates the one frame that listens for them and
-- adds the handlers that belong to no single feature: loading saved variables, login, message dispatch.
-- Provides NS.StatusLine.
local _, NS = ...
local Print, Debug, Configured = NS.Print, NS.Debug, NS.Configured
local conn = NS.conn

function NS.StatusLine()
  local db = NS.db
  if not Configured() then return "NOT CONFIGURED. Guild leaders: /cl setup <channel> <password> [tag]" end
  return string.format("%s | tag: %s | channel: %s (%s) | config: %s%s",
    db.enabled and "ON" or "OFF", tostring(NS.GetTag()), db.channel,
    NS.ChannelId() and "joined" or "not joined", db.source or "local",
    NS.Locked() and " | PAUSED (chat lockdown)" or "")
end

---------------------------------------------------------------- login
local loginAttempts = 0

local function NotConnectedWhy()
  if not IsInGuild() then return "you are not in a guild" end
  if conn.lastNotice then return "the game answered " .. conn.lastNotice .. " when joining " .. NS.db.channel end
  return "joining " .. NS.db.channel .. " got no answer from the server"
end

-- Login: the guild roster, Guild Info text and the channel list all arrive at different times after
-- PLAYER_LOGIN, so retry the read-and-join a few times (5s, 10s, 15s ... up to ~75s) instead of once.
-- Equivalent to the player typing /cl reload, then /cl once it is connected.
local function LoginSync()
  if not NS.db then return end
  loginAttempts = loginAttempts + 1
  NS.db.lastGI = nil                  -- nothing is "unchanged" at login: always re-read Guild Info
  NS.RefreshRoster()
  NS.ReadGuildInfo()
  NS.EnsureChannel()
  Debug("login sync %d: configured=%s joined=%s", loginAttempts, tostring(Configured() and true or false),
    tostring(NS.ChannelId() ~= nil))
  if Configured() and NS.ChannelId() then
    Print(NS.StatusLine())
    NS.FocusClubStream()              -- subscribe to the community stream now; the reminder retries in 10 s
    C_Timer.After(10, NS.RemindAboutClub)
    return
  end
  if loginAttempts < 6 then
    C_Timer.After(5 * loginAttempts, LoginSync)
    return
  end
  -- "Not configured" was already reported by the 20 s notice; this line is for a configured client
  -- whose channel join did not happen.
  if not Configured() then return end
  Print("not connected after login: " .. NotConnectedWhy() .. ". Run /cl report and share it, or /cl reload to retry.")
end

NS.events.ADDON_LOADED = function(name)
  if name ~= NS.ADDON then return end
  CORELinkDB = CORELinkDB or {}
  local db = CORELinkDB
  NS.db = db
  if db.enabled == nil then db.enabled = true end
  db.debug = false          -- debug echo is per session: always off at login, /cl debug on to enable
  db.muted = db.muted or {}
  db.nicks = db.nicks or {}
  NS.LoadPeers(db.peers)
  if db.clubId and not db.club then db.club = tostring(db.clubId) end   -- saved by versions before club names
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(NS.PREFIX)
  end
end

local warned = false
NS.events.PLAYER_LOGIN = function()
  NS.me.guid = UnitGUID and UnitGUID("player") or nil
  NS.mirror.reminded = false
  NS.InstallHooks()
  if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
  elseif GuildRoster then GuildRoster() end
  C_Timer.After(5, LoginSync)
  C_Timer.After(25, function()
    NS.SendPresence()
    if NS.db.nicks[NS.MyName()] then NS.BroadcastNick() end
    NS.SendGuildAddon("NREQ")
  end)
  C_Timer.After(45, NS.ScheduleWho)
  C_Timer.After(20, function()
    if not Configured() and not warned then
      warned = true
      Print("not configured: " .. conn.giState .. ". Guild leaders: /cl setup <channel> <password> [tag]")
    end
  end)
end

---------------------------------------------------------------- messages
-- CORELink packets arrive on two addon channels, GUILD (our guildmates, every realm) and WHISPER (peers in
-- other guilds), and as text on the link channel (addon users' own lines).
NS.events.CHAT_MSG_ADDON = function(prefix, text, chatType, sender)
  prefix, chatType = NS.Plain(prefix), NS.Plain(chatType)   -- comparing a secret value is an error
  if prefix ~= NS.PREFIX then return end
  if chatType == "GUILD" then
    NS.OnGuildAddon(text, sender)
  elseif chatType == "WHISPER" then
    NS.OnWhisperAddon(text, sender)
  end
end

NS.events.CHAT_MSG_CHANNEL = function(text, author, _, channelString, _, _, _, _, channelBaseName)
  if NS.IsLinkChannel(channelString) or NS.IsLinkChannel(channelBaseName) then
    NS.OnLinkMessage(text, author)
  end
end

---------------------------------------------------------------- the frame
local f = CreateFrame("Frame")
for event in pairs(NS.events) do f:RegisterEvent(event) end
-- A handler set by a later file, or at runtime, is registered with the game the moment it is set.
setmetatable(NS.events, { __newindex = function(t, event, handler)
  rawset(t, event, handler)
  f:RegisterEvent(event)
end })
f:SetScript("OnEvent", function(_, event, ...)
  local handler = NS.events[event]
  if handler then handler(...) end
end)

---------------------------------------------------------------- housekeeping
-- Once a minute: forget old ids, re-read Guild Info, rejoin the channel if dropped, refresh the roster.
local function Housekeeping()
  if not NS.db then return end
  local now = GetTime()
  for k, v in pairs(NS.seen) do if now - v > NS.FORGET_SECS then NS.seen[k] = nil end end
  for k, v in pairs(NS.displayed) do if now - v > NS.FORGET_SECS then NS.displayed[k] = nil end end
  for tag, t in pairs(NS.heard) do if now - t > NS.HEARD_SECS then NS.heard[tag] = nil end end
  NS.ReadGuildInfo()
  NS.EnsureChannel()
  NS.FocusClubStream()
  if C_GuildInfo and C_GuildInfo.GuildRoster and math.random() < 0.5 then C_GuildInfo.GuildRoster() end
end
C_Timer.NewTicker(60, Housekeeping)
