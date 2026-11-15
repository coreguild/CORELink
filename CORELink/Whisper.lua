-- CORELink/Whisper.lua: the courier, its peers, and the whisper path between guilds.
-- The courier is the alphabetically first guildmate running the addon (us included), on any realm; every client
-- computes the same answer from the PRESENT reports. It carries lines from members without the addon: one
-- whisper per other guild, to that guild's freshest peer. A peer is an addon user of another guild, learned
-- from their own lines on the channel, from a HELLO/PEER exchange, or from gossip. Whisper addon messages need
-- no keypress and cross realms by plain "First Surname".
-- Packets (whisper addon channel): HELLO~tag~realm~guild, PEER~tag~realm~guild (the answer),
-- DIR~name@realm@tag@guild;... (gossip), WB~<packet> (a carried line).
-- Provides NS.peers, NS.LoadPeers, NS.LivePeer, NS.NotePeer, NS.IsCourier, NS.Courier, NS.Hello, NS.ForgetHello,
-- NS.WhisperAvailable, NS.WhoNext, NS.WhisperOut, NS.OnWhisperAddon, NS.PeerName,
-- NS.whisperStats, NS.guildOnline, NS.PEER_ONLINE_SECS.
local _, NS = ...
local Debug, Locked, IsMe, MyName, MyRealm, GetTag = NS.Debug, NS.Locked, NS.IsMe, NS.MyName, NS.MyRealm, NS.GetTag
local issecret, SEP = NS.issecret, NS.SEP

local peers = {}             -- name (as the game gives it) -> { tag=, realm=, guild=, seen= }  (saved in db.peers)
NS.peers = peers
NS.guildOnline = {}          -- guild name -> { n = online count, t = time }  (from /who)
local helloAt = {}           -- whisper target -> last hello time
local fanned = {}            -- packet id -> time we fanned it out to our guild
NS.whisperStats = { who = 0, hello = 0, answered = 0, sent = 0, recv = 0, fanned = 0 }
local stats = NS.whisperStats
local whoPending             -- { guild=, at= } while a /cl who lookup waits for its results
local HELLO_EVERY, HELLO_PER_GUILD = 600, 3
local COURIER_SECS = 360      -- a guildmate silent this long is not a courier candidate
NS.PEER_ONLINE_SECS = 1200    -- a peer silent this long is not whispered to
local PEER_ONLINE_SECS, PEER_KEEP_SECS = NS.PEER_ONLINE_SECS, 7 * 86400

-- Saved peers from a previous session (ADDON_LOADED).
function NS.LoadPeers(saved)
  if type(saved) ~= "table" then return end
  peers = saved
  NS.peers = saved
end

local function SavePeers() if NS.db then NS.db.peers = peers end end

-- Heard from in the last 20 minutes. A peer that never answered has seen == 0 and is never live.
local function Live(p, now) return p.seen > 0 and now - p.seen <= PEER_ONLINE_SECS end
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
  if not key or key == "" or not tag or tag == "" then return end
  local p = peers[key] or {}
  p.tag, p.seen = tag, GetTime()
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

---------------------------------------------------------------- who lookup (optional bootstrap)
-- With guilds= on the Guild Info line, the courier's /cl who asks who is online in one listed guild and greets
-- a few, so a guild nobody has heard from yet still gets a peer. The game allows the query only inside the
-- player's own keypress (from a timer it is blocked with "Interface action failed because of an AddOn"), so
-- nothing here runs by itself: each /cl who asks about the next guild on the list.
local WHO_ANSWER_SECS = 6     -- results arriving later than this are someone else's lookup, not ours
local whoIndex = 0            -- the listed guild last answered; a lookup that got no answer is asked again
local whoRefused = false      -- the game blocked the lookup even from the command: stop offering it

local function WhoToUi(on)
  if C_FriendList and C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, on) end
end

-- Why no lookup can be sent right now, or nil.
local function WhoBusy()
  local C = C_FriendList
  if whoRefused then return "the game refuses the who lookup from an addon on this client." end
  if not (C and C.SendWho and C.GetNumWhoResults and C.GetWhoInfo) then return "this client has no who lookup." end
  if whoPending and GetTime() - whoPending.at <= WHO_ANSWER_SECS then
    return "still waiting for the answer about " .. whoPending.guild .. "; try again in a few seconds."
  end
  if FriendsFrame and FriendsFrame.IsShown and FriendsFrame:IsShown() then
    return "close the Friends window (the Who list is part of it), then run /cl who again."
  end
end

-- Ask about the next listed guild. Returns its name and how many guilds are listed, or nil and the reason.
function NS.WhoNext()
  local busy = WhoBusy()
  if busy then return nil, busy end
  local mine, others = GetGuildInfo("player"), {}
  for _, g in ipairs(NS.db.guilds or {}) do if g ~= mine then others[#others + 1] = g end end
  if #others == 0 then return nil, "no other guild on the guilds= list." end
  local index = whoIndex % #others + 1
  local g = others[index]
  WhoToUi(true)                 -- results as an event, not as lines in the chat window
  whoPending = { guild = g, at = GetTime(), index = index }
  if not pcall(C_FriendList.SendWho, 'g-"' .. g .. '"') then whoPending = nil return nil, "the who lookup failed." end
  stats.who = stats.who + 1
  C_Timer.After(WHO_ANSWER_SECS, function() if not whoPending or whoPending.guild == g then WhoToUi(false) end end)
  return g, #others
end

-- pcall does not see a blocked call: the game reports it with this event. If it names us while a lookup of ours
-- is waiting, even the command's keypress is not enough on this client; say so once and stop offering it.
NS.events.ADDON_ACTION_BLOCKED = function(addon)
  if addon ~= NS.ADDON or not whoPending or GetTime() - whoPending.at > 1 then return end
  whoPending, whoRefused = nil, true
  Debug("the game blocked the who lookup from /cl who")
  NS.Print("the game refused the who lookup. /cl who does not work on this client.")
end

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

-- Greet a few names we have not heard from, rotating through the list over the lookups (a name waits 30 min
-- between hellos). Known peers are pinged by PeerUpkeep instead.
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
  local asked = whoPending
  whoPending = nil
  if not asked or GetTime() - asked.at > WHO_ANSWER_SECS then return end
  WhoToUi(false)
  local g = asked.guild
  whoIndex = asked.index
  local online, names = WhoResults(g)
  NS.guildOnline[g] = { n = online, t = GetTime() }
  GreetSome(names)
end
NS.events.WHO_LIST_UPDATE = OnWhoList

---------------------------------------------------------------- carrying a line
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
    elseif IsCourier() and p.seen > 0 and now - p.seen > HELLO_EVERY then Hello(key, "HELLO") end
  end
  for id, t in pairs(fanned) do if now - t > NS.FORGET_SECS then fanned[id] = nil end end
  SavePeers()
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
