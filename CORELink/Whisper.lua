-- CORELink/Whisper.lua: the whisper bridge, for guilds that share no realm with ours.
-- "guilds=Name One, Name Two" on the Guild Info line names the collective. Each guild's courier on a realm
-- (alphabetically first guildmate running the addon there) asks the server who is online in each guild
-- (silent /who), greets a few of them over whisper addon messages, and remembers who answered (peers; a player
-- without the addon never answers). A line heard on this realm is whispered to one peer on every realm that
-- would not otherwise get it; that peer drops it into its own realm's channel. Whispers need no keypress and
-- are the only cross-realm path not tied to a guild or a community.
-- On Forever a "First Surname" is unique across realms: /who sees every realm but names carry no realm, and a
-- plain name whispers across realms. So a peer's realm is learned only from its PEER answer, and the courier
-- keeps greeting names it has not heard from, so that every realm a guild lives on ends up with a peer.
-- Packets (whisper addon channel): HELLO~tag~realm~guild, PEER~tag~realm~guild (the answer),
-- DIR~name@realm@tag@guild;... (gossip), WB~<relay packet> (a bridged line).
-- Provides NS.peers, NS.LoadPeers, NS.IsCourier, NS.Hello, NS.ForgetHello, NS.WhisperAvailable, NS.ScheduleWho,
-- NS.ResetWhoTimer, NS.WhisperOut, NS.OnWhisperAddon, NS.PeerName, NS.whisperStats, NS.guildOnline.
local _, NS = ...
local Debug, Locked, IsMe, MyName, MyRealm, GetTag = NS.Debug, NS.Locked, NS.IsMe, NS.MyName, NS.MyRealm, NS.GetTag
local issecret, SEP = NS.issecret, NS.SEP

local peers = {}             -- name (as the game gives it) -> { tag=, realm=, guild=, seen= }  (saved in db.peers)
NS.peers = peers
NS.guildOnline = {}          -- guild name -> { n = online count, t = time }  (from /who)
local helloAt = {}           -- whisper target -> last hello time
NS.whisperStats = { who = 0, hello = 0, answered = 0, sent = 0, recv = 0 }
local stats = NS.whisperStats
local whoQueue, whoPending, whoNext = {}, nil, 0
local WHO_EVERY, HELLO_EVERY, HELLO_PER_GUILD = 600, 600, 3
NS.PEER_ONLINE_SECS = 1200    -- a peer silent this long is not whispered to
local PEER_ONLINE_SECS, PEER_KEEP_SECS = NS.PEER_ONLINE_SECS, 7 * 86400

-- Saved peers from a previous session (ADDON_LOADED).
function NS.LoadPeers(saved)
  if type(saved) ~= "table" then return end
  peers = saved
  NS.peers = saved
end

local function SavePeers() if NS.db then NS.db.peers = peers end end

-- Answered us in the last 20 minutes. A peer that never answered has seen == 0 and is never live.
local function Live(p, now) return p.seen > 0 and now - p.seen <= PEER_ONLINE_SECS end
NS.LivePeer = Live

-- Our guild's courier on this realm: the alphabetically first guildmate (us included) seen running the addon
-- here in the last 6 minutes. Every client computes the same answer.
function NS.IsCourier()
  local me, now, mine = MyName(), GetTime(), MyRealm()
  local first = me
  for name, c in pairs(NS.courierSeen) do
    if c.realm == mine and now - c.t <= 360 and name < first then first = name end
  end
  return first == me
end
local IsCourier = NS.IsCourier

function NS.WhisperAvailable() return C_ChatInfo and C_ChatInfo.SendAddonMessage and not Locked() end

local function QueueWhisper(target, text)
  if not NS.WhisperAvailable() then return end
  NS.whisperQueue[#NS.whisperQueue + 1] = { target = target, text = text }
end

function NS.PeerName(key) return (key:match("^([^-]+)")) or key end
local PeerName = NS.PeerName

local function RememberPeer(key, tag, realm, guild)
  if not key or key == "" or not tag or tag == "" then return end
  local p = peers[key] or {}
  p.tag, p.seen = tag, GetTime()
  p.realm = (realm ~= "" and realm) or p.realm or "?"
  p.guild = (guild ~= "" and guild) or p.guild
  peers[key] = p
  SavePeers()
  NS.NoteHeard(tag, p.realm, GetTime())
end

local function MyCard(kind)
  local g = GetGuildInfo("player") or ""
  return kind .. SEP .. (GetTag() or "?") .. SEP .. MyRealm() .. SEP .. g:gsub(SEP, "")
end

-- Greet a player; true when a hello went out (one per target per 10 minutes).
function NS.Hello(target, kind)
  local now = GetTime()
  if helloAt[target] and now - helloAt[target] < HELLO_EVERY then return false end
  helloAt[target] = now
  stats.hello = stats.hello + 1
  QueueWhisper(target, MyCard(kind or "HELLO"))
  return true
end
local Hello = NS.Hello

function NS.ForgetHello(target) helloAt[target] = nil end

-- Up to ~240 bytes of "name@realm@tag@guild;" so one good contact teaches the rest. Forever realm names are
-- long (CAMWOWUS1Realm1PvE), so the realm is left empty when the name already ends in "-realm".
local function Directory()
  local now, out, size = GetTime(), {}, 0
  for key, p in pairs(peers) do
    if Live(p, now) then
      local realm = p.realm or "?"
      if key:sub(-#realm - 1) == "-" .. realm then realm = "" end
      local e = key .. "@" .. realm .. "@" .. p.tag .. "@" .. (p.guild or "")
      if size + #e + 1 > 230 then break end
      out[#out + 1] = e; size = size + #e + 1
    end
  end
  return table.concat(out, ";")
end

---------------------------------------------------------------- who rounds
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
  stats.who = stats.who + 1
  C_Timer.After(6, function() if whoPending and whoPending.guild == g then whoPending = nil; RunWho() end end)
end

function NS.ScheduleWho()
  local db = NS.db
  if not db or not db.guilds or #db.guilds == 0 or not IsCourier() then return end
  if GetTime() < whoNext then return end
  whoNext = GetTime() + WHO_EVERY
  wipe(whoQueue)
  local mineName = GetGuildInfo("player")
  for _, g in ipairs(db.guilds) do if g ~= mineName then whoQueue[#whoQueue + 1] = g end end
  RunWho()
end

function NS.ResetWhoTimer() whoNext = 0 end

-- The names in the Who results that are really in guild g, and how many there are. The server's g-"Name"
-- filter is a substring match (g-"CORE" also returns Molten Soft Core), so the guild name is checked exactly.
local function WhoResults(g)
  local n = C_FriendList.GetNumWhoResults() or 0
  local online, names = 0, {}
  for i = 1, n do
    local okw, info = pcall(C_FriendList.GetWhoInfo, i)
    local full = okw and type(info) == "table" and info.fullName
    local guild = okw and type(info) == "table" and info.fullGuildName
    local inGuild = type(guild) ~= "string" or issecret(guild) or guild == g
    if type(full) == "string" and not issecret(full) and full ~= "" and inGuild then
      online = online + 1
      if not IsMe(PeerName(full)) then names[#names + 1] = full end
    end
  end
  Debug("who %s: %d in that guild of %d results", g, online, n)
  return online, names
end

-- Greet a few names we have not heard from, rotating through the list over the rounds (a name waits 30 min
-- between hellos): results carry no realm, so this is how every realm the guild lives on gets a peer.
-- Known peers are pinged by PeerUpkeep instead.
local function GreetSome(names)
  local now, greeted = GetTime(), 0
  for _, key in ipairs(names) do
    if greeted >= HELLO_PER_GUILD then break end
    local p = peers[key]
    local known = p and p.seen > 0
    local rested = not helloAt[key] or now - helloAt[key] >= 3 * HELLO_EVERY
    if not known and rested and Hello(key) then greeted = greeted + 1 end
  end
end

local function OnWhoList()
  if not whoPending then return end
  local g = whoPending.guild
  whoPending = nil
  local online, names = WhoResults(g)
  NS.guildOnline[g] = { n = online, t = GetTime() }
  GreetSome(names)
  C_Timer.After(3, RunWho)
end
NS.events.WHO_LIST_UPDATE = OnWhoList

---------------------------------------------------------------- routing
-- A line heard natively on our realm: whisper it to one peer on every realm that would not otherwise get it
-- (no addon user of the origin guild there, no guildmate of ours there to bridge it).
function NS.WhisperOut(id, tag, text)
  local db = NS.db
  if not db or db.whisper == false or not IsCourier() or not NS.WhisperAvailable() then return end
  local now, mine = GetTime(), MyRealm()
  local heardThere, guildThere = NS.heardRealms[tag], NS.guildRealms
  local best = {}
  for key, p in pairs(peers) do
    local realm = p.realm
    local covered = (heardThere and heardThere[realm] and now - heardThere[realm] <= 600)
      or (guildThere[realm] and now - guildThere[realm] <= 600)
    if realm and realm ~= mine and Live(p, now) and not covered then
      if not best[realm] or p.seen > peers[best[realm]].seen then best[realm] = key end
    end
  end
  for realm, key in pairs(best) do
    QueueWhisper(key, "WB" .. SEP .. text)
    stats.sent = stats.sent + 1
    Debug("whispered %s to %s (%s on %s)", id, PeerName(key), peers[key].tag, realm)
  end
end

---------------------------------------------------------------- packets
-- HELLO and PEER carry the sender's card: tag~realm~guild. A HELLO is answered with PEER and our directory.
local function OnCard(cmd, rest, sender)
  local tag, realm, guild = rest:match("^([^" .. SEP .. "]*)" .. SEP .. "([^" .. SEP .. "]*)" .. SEP .. "(.*)$")
  if not tag then return end
  RememberPeer(sender, tag, realm, guild)
  stats.answered = stats.answered + 1
  if cmd == "HELLO" then
    QueueWhisper(sender, MyCard("PEER"))
    local dir = Directory()
    if dir ~= "" then QueueWhisper(sender, "DIR" .. SEP .. dir) end
  end
end
NS.whisperPackets.HELLO = function(rest, sender) OnCard("HELLO", rest, sender) end
NS.whisperPackets.PEER = function(rest, sender) OnCard("PEER", rest, sender) end

-- DIR: gossip, names worth greeting; never trusted as live peers until they answer a hello of ours.
NS.whisperPackets.DIR = function(rest)
  local greeted = 0
  for entry in rest:gmatch("[^;]+") do
    local key, realm, tag, guild = entry:match("^([^@]+)@([^@]*)@([^@]*)@(.*)$")
    if key and realm == "" then realm = key:match("%-(.+)$") or "?" end
    if key and tag ~= "" and not IsMe(PeerName(key)) and not peers[key] and greeted < 6 then
      peers[key] = { tag = tag, realm = realm, guild = guild, seen = 0 }   -- known, not yet confirmed
      SavePeers()
      greeted = greeted + 1
      Hello(key)
    end
  end
end

-- WB: a peer on another realm whispered us a line its realm heard; drop it into ours like a bridged line.
NS.whisperPackets.WB = function(rest, sender)
  if not NS.db or NS.db.whisper == false then return end
  stats.recv = stats.recv + 1
  if peers[sender] then peers[sender].seen = GetTime() end
  NS.OnBridgeReceived(rest, sender)
end

function NS.OnWhisperAddon(text, sender)
  if issecret(text) or issecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
  local cmd, rest = text:match("^(%a+)" .. SEP .. "?(.*)$")
  local handler = cmd and NS.whisperPackets[cmd]
  if handler then handler(rest, sender) end
end

-- Keep live peers fresh: couriers ping known peers every 10 minutes; anyone answers. Forget peers silent for
-- a week. Then run the who round if it is due.
local function PeerUpkeep()
  if not NS.db then return end
  local now = GetTime()
  for key, p in pairs(peers) do
    if now - p.seen > PEER_KEEP_SECS then peers[key] = nil
    elseif IsCourier() and p.seen > 0 and now - p.seen > HELLO_EVERY then Hello(key, "HELLO") end
  end
  SavePeers()
  NS.ScheduleWho()
end
C_Timer.NewTicker(60, PeerUpkeep)

-- A hello to someone who logged off makes the game print "No player named 'X' is currently playing."; hide it
-- when it is about a name we whispered in the last few seconds, and forget that peer for now.
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
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
