-- CORELink/Relay.lua: guild lines out to other guilds, and other guilds' lines in to guild chat.
-- Out: an addon user's own typed line goes into the hidden channel as text from the chat send hooks
-- (RelayTyped), which every addon user in every guild reads. Nothing else goes out: a line from a member
-- without the addon is not bridged (up to 0.2.0 a courier whispered it; Whisper.lua has the story).
-- In: whatever path a packet arrives by (the channel, a 0.2.0 courier's whisper, a guildmate's LINE),
-- ShowPacket displays it once.
-- Packet: CL4~id~tag~author~class~flags~nick~text (flags "O<rank>" for officers).
-- Provides NS.RelayTyped, NS.OnGuildMessage, NS.OnLinkMessage, NS.ShowPacket, NS.relayStats.
local _, NS = ...
local Debug, Configured, Locked, IsMe, GetTag = NS.Debug, NS.Configured, NS.Locked, NS.IsMe, NS.GetTag
local issecret, SEP, PROTO = NS.issecret, NS.SEP, NS.PROTO
local seen, displayed = NS.seen, NS.displayed

NS.relayStats = { typed = 0, shown = 0 }
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

---------------------------------------------------------------- our guild's chat
-- A line in our guild chat. Nobody's line is carried for them, so the only thing to take from it is our own
-- name: on our own line the guid is ours, and the author is the name chat and the roster use for us.
function NS.OnGuildMessage(_, author, _, _, _, _, _, _, _, _, _, guid)
  if issecret(author) or type(author) ~= "string" then return end
  IsMe(Ambiguate(author, "none"), guid)
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

-- LINE~<packet>: a guildmate fans out a line it received by whisper from a 0.2.0 courier of another guild.
NS.guildPackets.LINE = function(rest) NS.ShowPacket(rest, "guild") end
