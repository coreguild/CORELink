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

local function LivePeers()
  local n, now = 0, GetTime()
  for _, p in pairs(NS.peers) do if NS.LivePeer(p, now) then n = n + 1 end end
  return n
end

local function OnOff(flag) return flag and "on" or "off" end

local function RecentTags()
  local tags = {}
  for tag, t in pairs(NS.heard) do if GetTime() - t <= 600 then tags[#tags + 1] = tag end end
  return #tags > 0 and table.concat(tags, ",") or "none"
end

-- "TAG@realm1+realm2,..." : which realms each guild was heard on in the last 10 minutes.
local function ReachSummary()
  local out, now = {}, GetTime()
  for tag, realms in pairs(NS.heardRealms) do
    local rs = {}
    for realm, t in pairs(realms) do if now - t <= 600 then rs[#rs + 1] = realm end end
    table.sort(rs)
    if #rs > 0 then out[#out + 1] = tag .. "@" .. table.concat(rs, "+") end
  end
  table.sort(out)
  return #out > 0 and table.concat(out, ",") or "none"
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

local function WhisperSummary()
  local db, s = NS.db, NS.whisperStats
  return string.format("whisper %s courier=%s guilds=%d peers=%d who=%d hello=%d answered=%d sent=%d recv=%d",
    OnOff(db.whisper ~= false), tostring(NS.IsCourier()), db.guilds and #db.guilds or 0, LivePeers(),
    s.who, s.hello, s.answered, s.sent, s.recv)
end

local function BridgeSummary()
  local s = NS.bridgeStats
  return string.format("bridge %s fwd=%d resent=%d skipped=%d elsewhere=%s", OnOff(NS.db.bridge ~= false),
    s.forwarded, s.resent, s.skipped, tostring(NS.HasGuildmatesElsewhere()))
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
    "lastNotice " .. (conn.lastNotice and (conn.lastNotice .. " at " .. conn.lastNoticeAt) or "none"),
    "joinHold " .. (GetTime() < conn.blockedUntil and tostring(conn.blockedWhy) or "no"),
    "lockdown " .. tostring(NS.Locked()),
    "lastSend " .. tostring(conn.lastSendResult),
    "queue " .. #NS.sendQueue,
    "realm " .. MyRealm(),
    "heard " .. RecentTags(),
    "reach " .. ReachSummary(),
    string.format("tables seen=%d displayed=%d nicks=%d",
      CountKeys(NS.seen), CountKeys(NS.displayed), CountKeys(db.nicks)),
    MirrorSummary(),
    WhisperSummary(),
    BridgeSummary(),
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
-- "TAG - realm (12s ago), realm2 (40s ago) | NOT reaching <ours>" for each guild heard in the last 10 minutes.
local function PrintHeardGuilds(now, mine)
  local n, tags = 0, {}
  for tag in pairs(NS.heardRealms) do tags[#tags + 1] = tag end
  table.sort(tags)
  for _, tag in ipairs(tags) do
    local parts = {}
    for realm, t in pairs(NS.heardRealms[tag]) do
      if now - t <= 600 then parts[#parts + 1] = string.format("%s (%ds ago)", realm, math.floor(now - t)) end
    end
    if #parts > 0 then
      n = n + 1
      table.sort(parts)
      local reachesUs = NS.heard[tag] and now - NS.heard[tag] <= 600
      local note = (not reachesUs and tag ~= GetTag()) and (" | NOT reaching " .. mine) or ""
      local ours = tag == GetTag() and " (your guild)" or ""
      Print(string.format("%s%s - %s%s", tag, ours, table.concat(parts, ", "), note))
    end
  end
  if n == 0 then Print("no guilds heard on the link in the last 10 minutes.") end
end

local function PrintOurRealms(mine)
  local realms = {}
  for realm in pairs(NS.guildRealms) do realms[#realms + 1] = realm end
  if not NS.guildRealms[mine] then realms[#realms + 1] = mine end
  table.sort(realms)
  Print("your realm: " .. mine .. " | your guild runs CORELink on: " .. table.concat(realms, ", "))
end

local function PrintWhoCounts(now)
  local names = {}
  for g in pairs(NS.guildOnline) do names[#names + 1] = g end
  table.sort(names)
  for _, g in ipairs(names) do
    local e = NS.guildOnline[g]
    Print(string.format("%s - %d online (asked %ds ago)", g, e.n, math.floor(now - e.t)))
  end
end

NS.commands.guilds = function()
  local now, mine = GetTime(), MyRealm()
  PrintHeardGuilds(now, mine)
  PrintOurRealms(mine)
  PrintWhoCounts(now)
end

---------------------------------------------------------------- /cl peers
local function PeerState(p, now)
  if p.seen == 0 then return "not yet answered" end
  if now - p.seen <= NS.PEER_ONLINE_SECS then return "seen " .. math.floor(now - p.seen) .. "s ago" end
  return "offline"
end

NS.commands.peers = function()
  local now, keys = GetTime(), {}
  for key in pairs(NS.peers) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local p = NS.peers[key]
    Print(string.format("%s - %s on %s (%s) %s", NS.PeerName(key), p.tag, tostring(p.realm), p.guild or "?",
      PeerState(p, now)))
  end
  if #keys == 0 then
    Print("no peers yet. Guild leaders: add guilds=<name>, <name> to the CORELink line in Guild Info.")
  end
  Print("courier on " .. MyRealm() .. ": " .. (NS.IsCourier() and "you" or "a guildmate"))
end
