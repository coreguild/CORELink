-- CORELink/Report.lua: the diagnostic commands: /cl report, /cl guilds, /cl peers.
-- Everything here only reads state and prints it.
local _, NS = ...
local Print, Configured, GetTag, MyRealm = NS.Print, NS.Configured, NS.GetTag, NS.MyRealm
local conn, mirror, club = NS.conn, NS.mirror, NS.club

local function CountKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function OnOff(flag) return flag and "on" or "off" end

local function RecentTags()
  local tags, now = {}, GetTime()
  for tag, t in pairs(NS.heard) do if now - t <= NS.HEARD_SECS then tags[#tags + 1] = tag end end
  table.sort(tags)
  return #tags > 0 and table.concat(tags, ",") or "none"
end

-- live peers in total, and per guild tag
local function LivePeers()
  local n, perTag, now = 0, {}, GetTime()
  for _, p in pairs(NS.peers) do
    if NS.LivePeer(p, now) then n = n + 1; perTag[p.tag] = (perTag[p.tag] or 0) + 1 end
  end
  return n, perTag
end

local function StreamSummary()
  local sid = NS.db.club and NS.ClubStream()
  if not sid then return "nil" end
  return sid .. ":" .. (NS.StreamTag(sid) or "General")
end

local function MirrorSummary()
  local db = NS.db
  return string.format("mirror post=%s read=%s club=%s id=%s type=%s member=%s stream=%s channels=%d"
    .. " posted=%d failed=%d shown=%d skipped=%d hidden=%d focused=%s hooks=%s",
    OnOff(db.mirror ~= false), OnOff(db.mirrorRead ~= false), tostring(db.club), tostring(NS.ResolveClubId()),
    (db.club and NS.ClubIsCharacter()) and "wow" or tostring(club.clubType), tostring(db.club and NS.ClubMember()),
    StreamSummary(), CountKeys(NS.ClubStreams() or {}), mirror.posted, mirror.failed, mirror.shown,
    mirror.skipped, mirror.hidden, tostring(club.focused), mirror.hooks)
end

local function RelaySummary()
  local s = NS.relayStats
  return string.format("relay typed=%d carried=%d shown=%d", s.typed, s.carried, s.shown)
end

local function WhisperSummary()
  local db, s = NS.db, NS.whisperStats
  return string.format("whisper %s courier=%s guilds=%d peers=%d who=%d hello=%d answered=%d sent=%d recv=%d fanned=%d",
    OnOff(db.whisper ~= false), NS.IsCourier() and "me" or NS.Courier(), db.guilds and #db.guilds or 0, (LivePeers()),
    s.who, s.hello, s.answered, s.sent, s.recv, s.fanned)
end

local function EchoSummary()
  local db, s = NS.db, NS.echoStats
  return string.format("echo %s me=%s sent=%d hidden=%d", OnOff(db.echo), OnOff(db.echoer ~= false), s.sent, s.hidden)
end

local function BuildReport()
  local db = NS.db
  return table.concat({
    "CORELink " .. NS.Version(),
    "proto " .. NS.PROTO,
    db.enabled and "enabled" or "disabled",
    Configured() and ("channel " .. db.channel .. " id " .. tostring(NS.ChannelId() or "not joined"))
      or "not configured",
    "tag " .. tostring(Configured() and GetTag() or nil),
    "config " .. tostring(db.source),
    "officerRank " .. tostring(db.officerRank or 1),
    "inGuild " .. tostring(IsInGuild()),
    "guildInfo " .. conn.giState,
    "joinAttempts " .. conn.joinAttempts,
    "passwordAnswers " .. tostring(conn.passwordAnswers),
    "lastNotice " .. (conn.lastNotice and (conn.lastNotice .. " at " .. conn.lastNoticeAt) or "none"),
    "joinHold " .. (GetTime() < conn.blockedUntil and tostring(conn.blockedWhy) or "no"),
    "lockdown " .. tostring(NS.Locked()),
    "lastSend " .. tostring(conn.lastSendResult),
    "realm " .. MyRealm(),
    "me " .. tostring(NS.me.name or ("short: " .. tostring(UnitName("player")))),
    "heard " .. RecentTags(),
    string.format("tables seen=%d displayed=%d nicks=%d addonUsers=%d",
      CountKeys(NS.seen), CountKeys(NS.displayed), CountKeys(db.nicks), CountKeys(NS.addonUsers)),
    MirrorSummary(),
    RelaySummary(),
    WhisperSummary(),
    EchoSummary(),
    "debug " .. tostring(db.debug == true),
    "log: " .. (#NS.debugLog > 0 and table.concat(NS.debugLog, " / ") or "empty"),
  }, " | ")
end

NS.commands.report = function()
  local report = BuildReport()
  Print("report (also in the copy box, Ctrl+C and paste it to whoever is helping):")
  Print(report)
  pcall(NS.ShowCopyBox, report)
end

---------------------------------------------------------------- /cl guilds
-- "TAG - heard 12s ago, 2 peers" for each guild heard in the last 10 minutes, then the courier and the
-- counts from the last who round.
NS.commands.guilds = function()
  local now, n = GetTime(), 0
  local _, perTag = LivePeers()
  local tags = {}
  for tag, t in pairs(NS.heard) do if now - t <= NS.HEARD_SECS then tags[#tags + 1] = tag end end
  table.sort(tags)
  for _, tag in ipairs(tags) do
    n = n + 1
    local ours = tag == GetTag() and " (your guild)" or ""
    local peersText = tag == GetTag() and "" or string.format(", %d peer(s) to whisper to", perTag[tag] or 0)
    Print(string.format("%s%s - heard %ds ago%s", tag, ours, math.floor(now - NS.heard[tag]), peersText))
  end
  if n == 0 then Print("no guilds heard on the link in the last 10 minutes.") end
  Print("courier for your guild: " .. (NS.IsCourier() and "you" or NS.Courier())
    .. " (" .. CountKeys(NS.addonUsers) .. " guildmate(s) seen running the addon)")
  local names = {}
  for g in pairs(NS.guildOnline) do names[#names + 1] = g end
  table.sort(names)
  for _, g in ipairs(names) do
    local e = NS.guildOnline[g]
    Print(string.format("%s - %d online (asked %ds ago)", g, e.n, math.floor(now - e.t)))
  end
end

---------------------------------------------------------------- /cl peers
local function PeerState(p, now)
  if p.seen == 0 then return "not yet answered" end
  if NS.LivePeer(p, now) then return "seen " .. math.floor(now - p.seen) .. "s ago" end
  return "offline"
end

NS.commands.peers = function()
  local now, keys = GetTime(), {}
  for key in pairs(NS.peers) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local p = NS.peers[key]
    Print(string.format("%s - %s (%s) %s", NS.PeerName(key), p.tag, p.guild or "?", PeerState(p, now)))
  end
  if #keys == 0 then
    Print("no peers yet. They appear as soon as another guild's addon user says something in guild chat.")
  end
  Print("courier for your guild: " .. (NS.IsCourier() and "you" or NS.Courier()))
end
