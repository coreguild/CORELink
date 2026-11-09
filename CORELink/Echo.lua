-- CORELink/Echo.lua: re-post other guilds' lines into real guild chat for members without the addon.
-- With "echo=on" on the Guild Info line, one addon user per guild re-posts other guilds' readable lines (relay
-- and bridge; community text cannot be read) as real guild messages. The first client to claim a line
-- (ECHO~id over the guild addon channel) posts it. Addon users hide the echoed line and never relay, carry or
-- mirror it, so nothing loops.
-- Provides NS.MaybeEcho, NS.IsEchoLine, NS.echoStats (sent, hidden, active).
local _, NS = ...
local Debug, Locked, IsMe, GetTag, SEP = NS.Debug, NS.Locked, NS.IsMe, NS.GetTag, NS.SEP

local echoed = {}           -- line id -> time it was claimed/echoed
NS.echoStats = { sent = 0, hidden = 0, active = false }   -- active: our own echo send is running
local stats = NS.echoStats

-- An echoed line in real guild chat: "[TAG] Name (Rank Nick): text" sent by a guildmate who runs the addon.
function NS.IsEchoLine(msg, sender)
  local db = NS.db
  if not db or not db.echo or type(msg) ~= "string" then return false end
  local seenAt = NS.addonUsers[sender]
  if not ((seenAt and GetTime() - seenAt < NS.ADDON_USER_SECS) or IsMe(sender)) then return false end
  local tag = msg:match("^%[([^%]]+)%] [^:]+: ")
  return tag ~= nil and tag ~= GetTag()
end

local function SendEcho(id, tag, author, msg, label, nick)
  local db = NS.db
  if echoed[id] or Locked() or not db.echo then return end
  local now = GetTime()
  echoed[id] = now
  for k, t in pairs(echoed) do if now - t > 600 then echoed[k] = nil end end
  NS.SendGuildAddon("ECHO" .. SEP .. id)
  local who = NS.RankNickPrefix(label, (db.showNick ~= false) and nick or nil)
  who = author .. (who ~= "" and (" " .. who:sub(1, -2)) or "")
  stats.active = true
  local ok = pcall(SendChatMessage, NS.Truncate("[" .. tag .. "] " .. who .. ": " .. msg, 250), "GUILD")
  stats.active = false
  if ok then stats.sent = stats.sent + 1; Debug("echoed %s into guild chat", id) end
end

-- One client per guild re-posts the line into real guild chat for members without the addon. Random back-off
-- then a claim, like the relay courier, so two addon users rarely echo the same line.
function NS.MaybeEcho(id, tag, author, msg, label, nick)
  local db = NS.db
  if not db.echo or db.echoer == false or not IsInGuild() or echoed[id] or not SendChatMessage then return end
  C_Timer.After(0.3 + math.random() * 1.2, function() SendEcho(id, tag, author, msg, label, nick) end)
end

-- ECHO~<id>: a guildmate is echoing this line, so we do not.
NS.guildPackets.ECHO = function(rest) echoed[rest] = GetTime() end
