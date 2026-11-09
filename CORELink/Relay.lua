-- CORELink/Relay.lua: guild lines out to other guilds, and other guilds' lines in to guild chat.
-- Out, two ways: an addon user's own typed line goes into the hidden channel as text from the chat send hooks
-- (RelayTyped), which every addon user in every guild reads. A line from a member without the addon is carried
-- by the guild's courier: whispered to one peer per other guild (Whisper.lua), who fans it out to their
-- guildmates over the guild addon channel (LINE). In: whatever path a packet arrives by, ShowPacket displays
-- it once.
-- Packet: CL4~id~tag~author~class~flags~nick~text (flags "O<rank>" for officers).
-- Provides NS.RelayTyped, NS.OnGuildMessage, NS.OnLinkMessage, NS.ShowPacket, NS.relayStats.
local _, NS = ...
local Debug, Configured, Locked, IsMe, GetTag = NS.Debug, NS.Configured, NS.Locked, NS.IsMe, NS.GetTag
local issecret, SEP, PROTO = NS.issecret, NS.SEP, NS.PROTO
local seen, pending, displayed = NS.seen, NS.pending, NS.displayed

NS.relayStats = { typed = 0, carried = 0, shown = 0 }
local COURIER_WAIT = 1          -- seconds the courier gives the author's own client before carrying a line
local stats = NS.relayStats

local function Packet(id, tag, author, msg, class, flags, nick)
  local head = table.concat({ PROTO, id, tag, author, class or "", flags or "", nick or "" }, SEP) .. SEP
  return head .. NS.Truncate(msg, 250 - #head)
end

local function LineId(tag, author, msg) return NS.Hash(tag .. author .. msg) end

---------------------------------------------------------------- out: our own typed line
-- From the chat send hooks, inside the keypress that sent the guild line: post it into the channel as text.
function NS.RelayTyped(text)
  local db = NS.db
  if not db or not db.enabled or not Configured() or Locked() then return end
  local tag = GetTag()
  if not tag then return end
  local author = NS.MyName()
  local id = LineId(tag, author, text)
  local now = GetTime()
  if seen[id] and now - seen[id] < NS.DEDUPE_SECS then return end   -- two hooks fire for one line
  seen[id] = now
  local rn = NS.OfficerRankName(author)
  local class = NS.ClassOf(author, NS.me.guid)
  local packet = Packet(id, tag, author, text, class, rn and ("O" .. rn) or "", db.nicks[author])
  if NS.SendChannelText(packet) then
    stats.typed = stats.typed + 1
    Debug("relayed own line %s into %s (%d bytes)", id, db.channel, #packet)
  end
end

---------------------------------------------------------------- out: the courier carries a guildmate's line
-- A line in our guild chat by someone else: if the author runs the addon, their own keypress posts it into the
-- channel and the copy arrives within a moment. The courier waits for that, and carries the line by whisper
-- when no copy came, whoever the author is (no addon, addon switched off, addon broken). A late copy costs
-- one redundant whisper; receivers drop the duplicate by id.
function NS.OnGuildMessage(msg, author, _, _, _, _, _, _, _, _, _, guid)
  local db = NS.db
  if not db.enabled or not Configured() or Locked() then return end
  if issecret(msg) or issecret(author) or not msg or msg == "" then return end
  local tag = GetTag()
  if not tag then return end
  author = Ambiguate(author, "none")
  if IsMe(author, guid) then return end           -- RelayTyped did it (and learned our chat-format name)
  if NS.IsEchoLine(msg, author) then return end   -- a guildmate's echo of another guild's line: not ours
  if not NS.IsCourier() then return end
  local id = LineId(tag, author, msg)
  if (seen[id] and GetTime() - seen[id] < NS.DEDUPE_SECS) or pending[id] then return end
  pending[id] = true
  local rn = NS.OfficerRankName(author)
  local packet = Packet(id, tag, author, msg, NS.ClassOf(author, guid), rn and ("O" .. rn) or "", db.nicks[author])
  C_Timer.After(COURIER_WAIT + math.random() * 1.5, function()
    pending[id] = nil
    if seen[id] then return end                   -- their own client relayed it
    seen[id] = GetTime()
    stats.carried = stats.carried + 1
    NS.WhisperOut(id, tag, packet)
  end)
end
NS.events.CHAT_MSG_GUILD = function(...) NS.OnGuildMessage(...) end

---------------------------------------------------------------- in
-- id, tag, author, class, flags, nick, msg from a CL4 packet; nil when the text is not one.
local function ParsePacket(text)
  local proto, rest = text:match("^(%w+)" .. SEP .. "(.*)$")
  if proto ~= PROTO or not rest then return nil end
  local id, tag, author, class, flags, nick, msg = NS.Split(rest, 7)
  if not id or not id:match("^%x+$") or not tag or tag == "" or not author or author == "" then return nil end
  return id, tag, author, class, flags, nick, msg
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

-- A packet that reached us by any path: note it, show it once. Returns the parsed tag (nil if not a packet).
function NS.ShowPacket(text, via)
  if issecret(text) or type(text) ~= "string" then return nil end
  local id, tag, author, class, flags, nick, msg = ParsePacket(text)
  if not id then return nil end
  local now = GetTime()
  seen[id] = now
  NS.heard[tag] = now
  if displayed[id] then return tag end
  displayed[id] = now
  if tag == GetTag() then Debug("ignored packet %s via %s: own guild tag", id, via) return tag end
  if NS.db.muted[tag:lower()] then Debug("ignored packet %s via %s: tag %s muted", id, via, tag) return tag end
  Debug("showing packet %s via %s from %s <%s>", id, via, author, tag)
  local label = OfficerLabel(flags)
  nick = NS.CleanNick(nick)
  NoteAuthor(author, class, label, nick)
  if NS.CrossSeen(author, "relay") then Debug("skipped packet %s: shown from the community", id) return tag end
  stats.shown = stats.shown + 1
  NS.Display(tag, author, class, msg, label, nick ~= "" and nick or nil)
  NS.MaybeEcho(id, tag, author, msg, label, nick ~= "" and nick or nil)
  return tag
end

-- Text on the link channel (CHAT_MSG_CHANNEL): an addon user's own line. Its author is, by definition, an
-- addon user of that guild: a guildmate's line tells us they relay their own, another guild's gives us a peer.
function NS.OnLinkMessage(text, author)
  if issecret(text) or issecret(author) or type(text) ~= "string" or type(author) ~= "string" then return end
  local tag = NS.ShowPacket(text, "channel")
  if not tag then return end
  author = Ambiguate(author, "none")
  if tag == GetTag() then NS.addonUsers[author] = GetTime() else NS.NotePeer(author, tag) end
end

-- LINE~<packet>: a guildmate fans out a line it received by whisper from another guild's courier.
NS.guildPackets.LINE = function(rest) NS.ShowPacket(rest, "guild") end
