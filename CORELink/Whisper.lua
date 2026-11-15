-- CORELink/Whisper.lua: the courier, its peers, and the whisper path between guilds.
-- The courier is the alphabetically first guildmate running the addon (us included), on any realm; every client
-- computes the same answer from the PRESENT reports. It carries lines from members without the addon: one
-- whisper per other guild, to that guild's freshest peer. A peer is an addon user of another guild, learned
-- from their own lines on the channel, from a HELLO/PEER exchange, or from gossip. Whisper addon messages need
-- no keypress and cross realms by plain "First Surname".
-- Packets (whisper addon channel): HELLO~tag~realm~guild, PEER~tag~realm~guild (the answer),
-- DIR~name@realm@tag@guild;... (gossip), WB~<packet> (a carried line).
-- Provides NS.peers, NS.LoadPeers, NS.LivePeer, NS.NotePeer, NS.IsCourier, NS.Courier, NS.Hello, NS.ForgetHello,
-- NS.WhisperAvailable, NS.WhisperOut, NS.OnWhisperAddon, NS.PeerName, NS.whisperStats, NS.PEER_ONLINE_SECS.
-- There is no /who lookup of other guilds: the game blocks C_FriendList.SendWho outside a keypress.
local _, NS = ...
local Debug, Locked, IsMe, MyName, MyRealm, GetTag = NS.Debug, NS.Locked, NS.IsMe, NS.MyName, NS.MyRealm, NS.GetTag
local issecret, SEP = NS.issecret, NS.SEP

local peers = {}             -- name (as the game gives it) -> { tag=, realm=, guild=, seen= }  (saved in db.peers)
NS.peers = peers
local helloAt = {}           -- whisper target -> last hello time
local fanned = {}            -- packet id -> time we fanned it out to our guild
NS.whisperStats = { hello = 0, answered = 0, sent = 0, recv = 0, fanned = 0 }
local stats = NS.whisperStats
local HELLO_EVERY = 600
local COURIER_SECS = 360      -- a guildmate silent this long is not a courier candidate
NS.PEER_ONLINE_SECS = 1200    -- a peer silent this long is not whispered to
local PEER_ONLINE_SECS, PEER_KEEP_SECS = NS.PEER_ONLINE_SECS, 7 * 86400
local GONE_PING_SECS = 3600   -- how long a peer the game called "not playing" is still greeted now and then
local NOT_PLAYING_SECS = 10   -- the game's "not playing" answer counts as ours this long after a whisper left

-- Saved peers from a previous session (ADDON_LOADED). Who logged off last session is not known now.
function NS.LoadPeers(saved)
  if type(saved) ~= "table" then return end
  for _, p in pairs(saved) do if type(p) == "table" then p.gone = nil end end
  peers = saved
  NS.peers = saved
end

local function SavePeers() if NS.db then NS.db.peers = peers end end

-- Heard from in the last 20 minutes, and the game has not said since that they are not playing (p.gone, the
-- time it first said so). A peer that never answered has seen == 0 and is never live.
local function Live(p, now) return p.seen > 0 and now - p.seen <= PEER_ONLINE_SECS and not p.gone end
NS.LivePeer = Live

---------------------------------------------------------------- courier election
-- Our guild's courier: the alphabetically first of ourselves and the guildmates whose PRESENT (or any addon
-- message) we saw in the last 6 minutes.
function NS.Courier()
  local first, now = MyName(), GetTime()
  for name, t in pairs(NS.addonUsers) do
    if now - t <= COURIER_SECS and name < first then first = name end
  end
  return first
end

function NS.IsCourier() return NS.Courier() == MyName() end
local IsCourier = NS.IsCourier

---------------------------------------------------------------- peers
function NS.WhisperAvailable() return C_ChatInfo and C_ChatInfo.SendAddonMessage and not Locked() end

local function QueueWhisper(target, text)
  if not NS.WhisperAvailable() then return end
  NS.whisperQueue[#NS.whisperQueue + 1] = { target = target, text = text }
end

function NS.PeerName(key) return (key:match("^([^-]+)")) or key end
local PeerName = NS.PeerName

local function RememberPeer(key, tag, realm, guild)
  tag = tag and NS.CleanTag(tag)
  if not key or key == "" or not tag or tag == "" then return end
  local p = peers[key] or {}
  p.tag, p.seen, p.gone = tag, GetTime(), nil
  p.realm = (realm and realm ~= "" and realm) or p.realm or "?"
  p.guild = (guild and guild ~= "" and guild) or p.guild
  peers[key] = p
  SavePeers()
  NS.heard[tag] = GetTime()
end

-- Another guild's addon user just relayed their own line: that is a live peer with no exchange needed.
function NS.NotePeer(author, tag) RememberPeer(author, tag, nil, nil) end

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

-- Up to ~240 bytes of "name@realm@tag@guild;" so one good contact teaches the rest.
local function Directory()
  local now, out, size = GetTime(), {}, 0
  for key, p in pairs(peers) do
    if Live(p, now) then
      local e = key .. "@" .. (p.realm or "?") .. "@" .. p.tag .. "@" .. (p.guild or "")
      if size + #e + 1 > 230 then break end
      out[#out + 1] = e; size = size + #e + 1
    end
  end
  return table.concat(out, ";")
end

---------------------------------------------------------------- carrying a line
local carriedTo = {}   -- whisper target -> the carried lines (WB~...) that left for them in the last few seconds

-- A whisper left for this target (called by the queue drain in Channel.lua). Carried lines are kept for a few
-- seconds: if the game answers that the target is not playing, they go to another peer of that guild.
function NS.NoteWhispered(target, text)
  local now = GetTime()
  local last = NS.whisperedAt[target]
  if not last or now - last > NOT_PLAYING_SECS then carriedTo[target] = nil end
  NS.whisperedAt[target] = now
  if text:sub(1, 3) == "WB" .. SEP then
    carriedTo[target] = carriedTo[target] or {}
    table.insert(carriedTo[target], text)
  end
end

-- The freshest live peer of a guild, or nil.
local function FreshestPeer(tag, now)
  local best
  for key, p in pairs(peers) do
    if p.tag == tag and Live(p, now) and (not best or p.seen > peers[best].seen) then best = key end
  end
  return best
end

-- The peer `key` of guild `tag` is not playing: the carried lines that just left for them, and those still
-- queued, go to that guild's next freshest peer. With no other live peer they are lost.
local function Reroute(key, tag)
  local lines, queue = carriedTo[key] or {}, NS.whisperQueue
  carriedTo[key] = nil
  for i = #queue, 1, -1 do
    if queue[i].target == key then
      local w = table.remove(queue, i)
      if w.text:sub(1, 3) == "WB" .. SEP then table.insert(lines, w.text) end
    end
  end
  local other = FreshestPeer(tag, GetTime())
  if other then for _, text in ipairs(lines) do QueueWhisper(other, text) end end
  Debug("%s is not playing: %d carried line(s) %s; no more to them until they are heard from again", key, #lines,
    other and ("sent on to " .. PeerName(other)) or "lost, no other live peer in <" .. tostring(tag) .. ">")
end

-- The courier carries a guildmate's line: one whisper to the freshest live peer of every other guild.
function NS.WhisperOut(id, tag, text)
  local db = NS.db
  if not db or db.whisper == false or not NS.WhisperAvailable() then return end
  local now, best = GetTime(), {}
  for key, p in pairs(peers) do
    local fresher = not best[p.tag] or p.seen > peers[best[p.tag]].seen
    if p.tag ~= tag and Live(p, now) and fresher then best[p.tag] = key end
  end
  for peerTag, key in pairs(best) do
    QueueWhisper(key, "WB" .. SEP .. text)
    stats.sent = stats.sent + 1
    Debug("carried %s to %s <%s>", id, PeerName(key), peerTag)
  end
end

---------------------------------------------------------------- packets
-- HELLO and PEER carry the sender's card: tag~realm~guild. A HELLO is answered with PEER and our directory.
local function OnCard(cmd, rest, sender)
  rest = NS.CleanField(rest)                 -- tag, realm and guild are saved and printed by /cl peers
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
  for entry in NS.CleanField(rest):gmatch("[^;]+") do
    local key, realm, tag, guild = entry:match("^([^@]+)@([^@]*)@([^@]*)@(.*)$")
    tag = tag and NS.CleanTag(tag)
    if key and tag ~= "" and not IsMe(PeerName(key)) and not peers[key] and greeted < 6 then
      peers[key] = { tag = tag, realm = realm ~= "" and realm or "?", guild = guild, seen = 0 }   -- not yet confirmed
      SavePeers()
      greeted = greeted + 1
      Hello(key)
    end
  end
end

-- WB: another guild's courier carried a line to us. Show it and fan it out to our guild once. Accepted from a
-- known peer, or for a guild we have heard on the channel; a stranger's whisper is dropped.
NS.whisperPackets.WB = function(rest, sender)
  if not NS.db or NS.db.whisper == false then return end
  local tag = rest:match("^CL%d+" .. SEP .. "%x+" .. SEP .. "([^" .. SEP .. "]+)")
  tag = tag and NS.CleanTag(tag)             -- as ShowPacket files it under NS.heard
  local known = peers[sender] or (tag and NS.heard[tag] and GetTime() - NS.heard[tag] <= NS.HEARD_SECS)
  if not known then
    Debug("dropped a carried line from %s: not a peer, tag %s not heard", sender, tostring(tag))
    return
  end
  stats.recv = stats.recv + 1
  if peers[sender] then peers[sender].seen = GetTime() end
  local id = rest:match("^CL%d+" .. SEP .. "(%x+)" .. SEP)
  NS.ShowPacket(rest, "whisper")
  if id and not fanned[id] then
    fanned[id] = GetTime()
    stats.fanned = stats.fanned + 1
    NS.SendGuildAddon("LINE" .. SEP .. rest)
  end
end

function NS.OnWhisperAddon(text, sender)
  if issecret(text) or issecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
  if not NS.db then return end               -- the handlers read settings
  local cmd, rest = text:match("^(%a+)" .. SEP .. "?(.*)$")
  local handler = cmd and NS.whisperPackets[cmd]
  if handler then handler(rest, sender) end
end

-- Keep live peers fresh: the courier pings known peers every 10 minutes; anyone answers. Forget peers silent
-- for a week and fanned ids after a minute.
local function PeerUpkeep()
  if not NS.db then return end
  local now = GetTime()
  for key, p in pairs(peers) do
    if now - p.seen > PEER_KEEP_SECS then peers[key] = nil
    elseif IsCourier() and p.seen > 0 and now - p.seen > HELLO_EVERY
      and (not p.gone or now - p.gone < GONE_PING_SECS) then
      Hello(key, "HELLO")     -- a peer who logged off is asked again for an hour, in case they came back quietly
    end
  end
  for id, t in pairs(fanned) do if now - t > NS.FORGET_SECS then fanned[id] = nil end end
  for key, t in pairs(NS.whisperedAt) do
    if now - t > NOT_PLAYING_SECS then NS.whisperedAt[key], carriedTo[key] = nil, nil end
  end
  SavePeers()
end
C_Timer.NewTicker(60, PeerUpkeep)

-- An addon whisper to someone who logged off makes the game answer the sender "No player named 'X' is
-- currently playing.", once per whisper: a hello, or every line the courier carries to that peer. When it is
-- about a name a whisper of ours left for in the last few seconds, the peer is marked gone (no more carried
-- lines; a hello now and then for an hour) until they are heard from again, the lines that just left for them
-- or are still queued go to their guild's next peer (Reroute), and the chat filter keeps the line out of chat.
local notPlaying   -- the client's wording of that answer as a pattern, built on first use
local function NotPlayingName(msg)
  if issecret(msg) or type(msg) ~= "string" then return nil end
  if not notPlaying then
    local text = type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" and ERR_CHAT_PLAYER_NOT_FOUND_S
      or "No player named '%s' is currently playing."
    notPlaying = "^" .. text:gsub("%%s", "\1"):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("\1", "(.+)") .. "$"
  end
  return msg:match(notPlaying)
end

-- The whisper target this name stands for, if a whisper left for them just now: the exact name first.
local function WhisperedJust(name, now)
  local sent = NS.whisperedAt
  if sent[name] and now - sent[name] <= NOT_PLAYING_SECS then return name end
  for key, t in pairs(sent) do
    if now - t <= NOT_PLAYING_SECS and PeerName(key) == name then return key end
  end
end

NS.events.CHAT_MSG_SYSTEM = function(msg)
  local name = NotPlayingName(msg)
  local key = name and WhisperedJust(name, GetTime())
  local p = key and peers[key]
  if not p or p.gone then return end
  p.gone = GetTime()
  Reroute(key, p.tag)
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
  local name = NotPlayingName(msg)
  return (name and WhisperedJust(name, GetTime())) ~= nil
end)
