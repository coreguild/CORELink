-- CORELink/Relay.lua: guild lines out to the link channel, and link packets in to guild chat.
-- Out: a guild line is hashed, one client relays it (the author's own client at once, anyone else after a random
-- back-off, unless a copy was already seen). In: a packet from another guild is deduplicated, bridged and
-- whispered onward, then displayed and maybe echoed.
-- Packet: CL4~id~tag~author~class~flags~nick~text (flags "O<rank>" for officers). CL1-CL3 are still read.
-- Provides NS.OnGuildMessage, NS.OnLinkMessage.
local _, NS = ...
local Debug, Configured, Locked, IsMe, GetTag = NS.Debug, NS.Configured, NS.Locked, NS.IsMe, NS.GetTag
local issecret, SEP, PROTO, PREFIX = NS.issecret, NS.SEP, NS.PROTO, NS.PREFIX
local seen, pending, displayed = NS.seen, NS.pending, NS.displayed

---------------------------------------------------------------- relay out
local function Relay(id, tag, author, msg, class, flags, nick)
  pending[id] = nil
  seen[id] = GetTime()
  local head = table.concat({ PROTO, id, tag, author, class or "", flags or "", nick or "" }, SEP) .. SEP
  table.insert(NS.sendQueue, head .. NS.Trim(msg, 245 - #PREFIX - #head))
  Debug("queued relay %s from %s (%d bytes, queue %d)", id, author, #head + #msg, #NS.sendQueue)
end

-- A line in our own guild chat (CHAT_MSG_GUILD): relay it unless another client already did.
function NS.OnGuildMessage(msg, author, _, _, _, _, _, _, _, _, _, guid)
  local db = NS.db
  if not db.enabled or not Configured() or Locked() then return end
  if issecret(msg) or issecret(author) or not msg or msg == "" then return end
  local tag = GetTag()
  if not tag then return end
  author = Ambiguate(author, "none")
  local mine = IsMe(author, guid)      -- also learns our chat-format name from our own messages
  if NS.IsEchoLine(msg, author) then return end   -- a guildmate's echo of another guild's line: not ours to relay
  local class = NS.ClassOf(author, guid)
  local rn = NS.OfficerRank(author)
  local flags = rn and ("O" .. rn) or ""
  local nick = db.nicks[author]
  local id = NS.Hash(tag .. author .. msg)
  local now = GetTime()
  if (seen[id] and now - seen[id] < NS.DEDUPE_SECS) or pending[id] then return end
  pending[id] = true
  if mine then
    Relay(id, tag, author, msg, class, flags, nick)
    return
  end
  -- random back-off: normally only one member's client relays
  C_Timer.After(0.3 + math.random() * 1.2, function()
    if pending[id] and not (seen[id] and GetTime() - seen[id] < NS.DEDUPE_SECS) then
      Relay(id, tag, author, msg, class, flags, nick)
    end
    pending[id] = nil
  end)
end
NS.events.CHAT_MSG_GUILD = function(...) NS.OnGuildMessage(...) end

---------------------------------------------------------------- relay in
local F = "([^" .. SEP .. "]*)" .. SEP     -- one packet field

-- proto, id, tag, author, class, flags, nick, msg from a packet of any protocol version we read; nil if not ours.
local function ParsePacket(text)
  local proto, rest = text:match("^(%w+)" .. SEP .. "(.*)$")
  local id, tag, author, class, flags, nick, msg
  if proto == "CL4" then
    id, tag, author, class, flags, nick, msg = NS.Split(rest, 7)
    if id and not id:match("^%x+$") then id = nil end
  elseif proto == "CL3" then
    id, tag, author, class, flags, msg = rest:match("^(%x+)" .. SEP .. F .. F .. F .. F .. "(.*)$")
  elseif proto == "CL2" then
    id, tag, author, class, msg = rest:match("^(%x+)" .. SEP .. F .. F .. F .. "(.*)$")
  elseif proto == "CL1" then
    id, tag, author, msg = rest:match("^(%x+)" .. SEP .. F .. F .. "(.*)$")
  else
    return nil
  end
  return proto, id, tag, author, class, flags, nick, msg
end

-- "O<rank name>" in the flags field -> the officer label to show, or nil.
local function OfficerLabel(flags)
  if NS.db.officer == false or not flags or flags:sub(1, 1) ~= "O" then return nil end
  local label = (flags:sub(2):gsub("[~|]", ""))
  return label ~= "" and label or "Officer"
end

-- Remember what the packet says about its author, for community lines that carry none of it.
local function NoteAuthor(author, class, label, nick)
  if class and class ~= "" then NS.authorClass[author] = class end
  NS.authorOfficer[author] = label                    -- nil clears a stale officer label
  NS.authorSeen[author] = true
  NS.authorNick[author] = nick ~= "" and nick or nil
end

-- A packet on the link channel: note it, pass it on to realms that lack it, show it once.
function NS.OnLinkMessage(text)
  if issecret(text) or not text then return end
  local proto, id, tag, author, class, flags, nick, msg = ParsePacket(text)
  if not proto or not id then return end
  local now = GetTime()
  seen[id] = now
  NS.heard[tag] = now
  NS.NoteHeard(tag, NS.MyRealm(), now)
  pending[id] = nil                  -- another client already relayed it
  if msg == "" then return end       -- presence beacon, nothing to display
  local bridged = NS.bridged
  if tag ~= GetTag() and not bridged[id] then NS.ForwardToGuild(id, text) end
  if not bridged[id] and not displayed[id] then NS.WhisperOut(id, tag, text) end
  if displayed[id] then return end
  displayed[id] = now
  if tag == GetTag() then Debug("ignored %s packet %s: own guild tag", proto, id) return end
  if NS.db.muted[tag:lower()] then Debug("ignored %s packet %s: tag %s muted", proto, id, tag) return end
  Debug("showing %s packet %s from %s <%s>", proto, id, author, tag)
  local label = OfficerLabel(flags)
  nick = NS.CleanNick(nick)
  NoteAuthor(author, class, label, nick)
  if NS.CrossSeen(author, "relay") then Debug("skipped %s packet %s: shown from the community", proto, id) return end
  NS.Display(tag, author, class, msg, label, nick ~= "" and nick or nil)
  NS.MaybeEcho(id, tag, author, msg, label, nick ~= "" and nick or nil)
end
