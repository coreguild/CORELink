-- CORELink/Whisper.lua: reading the lines 0.2.0 clients still carry by whisper. Nothing here sends a whisper.
-- Up to 0.2.0 one addon user per guild, the courier, whispered the lines of members without the addon to one
-- addon user of every other guild. From 0.2.1 the addon sends no whisper at all: no carried lines, no
-- greetings, no gossip, no who queries. A member without the addon is not bridged to other guilds.
-- Guilds update at different times, so a guild still on 0.2.0 keeps carrying its lines to us as WB~<packet>.
-- We show such a line once and hand it to our guildmates once as LINE~<packet> on the guild addon channel.
-- A WB is accepted from a known peer, or for a guild heard in the last ten minutes. A peer is an addon user of
-- another guild, learned from their own line on the channel and saved in CORELinkDB.peers for a week.
-- The other whisper packets of 0.2.0 (HELLO, PEER, DIR) have no handler: they are dropped, unanswered.
-- Provides NS.peers, NS.LoadPeers, NS.LivePeer, NS.NotePeer, NS.PeerName, NS.OnWhisperAddon, NS.whisperStats.
local _, NS = ...
local Debug, issecret, SEP = NS.Debug, NS.issecret, NS.SEP

local peers = {}             -- name (as the game gives it) -> { tag=, realm=, guild=, seen= }  (saved in db.peers)
NS.peers = peers
local fanned = {}            -- packet id -> time we fanned it out to our guild
NS.whisperStats = { recv = 0, fanned = 0 }
local stats = NS.whisperStats
local PEER_RECENT_SECS, PEER_KEEP_SECS = 1200, 7 * 86400

-- Saved peers from a previous session (ADDON_LOADED), whichever version wrote them.
function NS.LoadPeers(saved)
  if type(saved) ~= "table" then return end
  peers = saved
  NS.peers = saved
end

local function SavePeers() if NS.db then NS.db.peers = peers end end

-- Heard from in the last 20 minutes. A peer 0.2.0 saved from gossip has seen == 0 and is never live.
function NS.LivePeer(p, now) return p.seen > 0 and now - p.seen <= PEER_RECENT_SECS end

function NS.PeerName(key) return (key:match("^([^-]+)")) or key end

-- Another guild's addon user just relayed their own line on the channel: remember them as a peer of that guild.
function NS.NotePeer(author, tag)
  if not author or author == "" or not tag or tag == "" then return end
  local p = peers[author] or {}
  p.tag, p.seen = tag, GetTime()
  p.realm = p.realm or "?"
  peers[author] = p
  SavePeers()
  NS.heard[tag] = GetTime()
end

---------------------------------------------------------------- packets
-- WB: a 0.2.0 courier carried a line to us. Show it and fan it out to our guild once. Accepted from a known
-- peer, or for a guild we have heard on the channel; a stranger's whisper is dropped.
NS.whisperPackets.WB = function(rest, sender)
  if not NS.db or NS.db.whisper == false then return end
  local tag = rest:match("^CL%d+" .. SEP .. "%x+" .. SEP .. "([^" .. SEP .. "]+)")
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

-- A whisper addon message: handed to its handler when the kind has one, dropped otherwise.
function NS.OnWhisperAddon(text, sender)
  if issecret(text) or issecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
  local cmd, rest = text:match("^(%a+)" .. SEP .. "?(.*)$")
  local handler = cmd and NS.whisperPackets[cmd]
  if handler then handler(rest, sender) end
end

-- Once a minute: forget peers silent for a week and fanned ids after a minute.
local function PeerUpkeep()
  if not NS.db then return end
  local now = GetTime()
  for key, p in pairs(peers) do
    if now - p.seen > PEER_KEEP_SECS then peers[key] = nil end
  end
  for id, t in pairs(fanned) do if now - t > NS.FORGET_SECS then fanned[id] = nil end end
  SavePeers()
end
C_Timer.NewTicker(60, PeerUpkeep)
