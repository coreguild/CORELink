--[[ CORELink - bridge guild chat between co-guilds on World of Warcraft: Forever.
     Members of linked guilds see each other's guild chat as "[GuildTag] [Author]: message".

     Configuration is done in game:
         /cl setup <channel> <password> [tag]     (use - for no password)
     Whoever can edit Guild Info pastes the line shown by /cl publish (setup
     shows it too) into Guild Info; every member's client then picks the
     settings up automatically. (Addons cannot write Guild Info themselves.)

     Transport, as live Forever allows it (measured 2026-11-08): a custom chat channel is shared by every
     realm and its text is readable by addons, but addon messages on it are refused, and chat text can only be
     sent from inside the player's own keypress. So an addon user's own guild line is posted into the hidden
     channel as text from the chat send hooks, where every other addon user reads it. A line from a member
     without the addon is whispered by the guild's courier to one addon user in every other guild (whisper
     addon messages need no keypress), who hands it to their guildmates over the guild addon channel.

     Midnight/Forever restriction: in M+, PvP and encounters chat arrives as secret values and addons cannot
     send chat; CORELink pauses there.

     The addon is split into files, loaded in the order the TOC lists them. Every file receives the same
     private table (NS, from the game's "..." vararg) and puts what later files need on it. A file copies
     off NS at load time only what earlier files defined (tests/load-order.lua checks it); anything else is
     reached as NS.Name() when called. NS.events, NS.guildPackets, NS.whisperPackets and NS.commands are
     registries any file fills in. docs/ARCHITECTURE.md walks a line through the files. ]]

local _, NS = ...

---------------------------------------------------------------- constants
NS.ADDON, NS.PROTO, NS.SEP = "CORELink", "CL4", "~"
NS.PREFIX = "CORELink"                 -- addon message prefix on the guild and whisper channels
NS.MAX_MSG, NS.DEDUPE_SECS = 200, 10
NS.HEARD_SECS = 600                    -- a guild or a player counts as present this long after it was last heard
NS.FORGET_SECS = 60                    -- packet ids are remembered this long
NS.DEFAULT_OFFICER_COLOR = "e8c63e"

---------------------------------------------------------------- shared state
-- NS.db is the saved-variables table (CORELinkDB, per character), set at ADDON_LOADED; nil before that.
NS.db = nil
NS.seen = {}        -- packet id -> time it was seen (relayed by us, read from the channel, whispered, fanned out)
NS.pending = {}     -- packet id -> true while a back-off decides whether the courier carries it
NS.displayed = {}   -- packet id -> time it was shown in guild chat
NS.heard = {}       -- guild tag -> last time one of its lines reached us by any path
NS.whisperQueue = {}   -- { target=, text= } waiting for the whisper addon channel
-- What we know about authors from relay packets: class token and officer label, keyed by chat name.
-- Community lines carry neither, so this is how they get class and officer colours.
NS.authorClass, NS.authorOfficer, NS.authorNick, NS.authorSeen = {}, {}, {}, {}
-- Registries later files fill in; the events file and the packet dispatchers read them.
NS.events = {}          -- game event -> handler(...)
NS.guildPackets = {}    -- "PRESENT", "NICK", "LINE", ... -> handler(rest, sender) for the guild addon channel
NS.whisperPackets = {}  -- "HELLO", "WB", ...  -> handler(rest, sender) for whisper addon messages
NS.commands = {}        -- "/cl <name>" -> handler(arg)

---------------------------------------------------------------- helpers
NS.issecret = issecretvalue or function() return false end
local issecret = NS.issecret

function NS.Locked()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local ok, res = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and res then return true end
  end
  return false
end

function NS.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CORELink:|r " .. tostring(msg))
end

-- Debug log: always recorded (last DEBUG_MAX lines, shown by /cl report), echoed to chat when /cl debug on.
local DEBUG_MAX = 20
NS.debugLog = {}
function NS.Debug(fmt, ...)
  local text = select("#", ...) > 0 and string.format(fmt, ...) or fmt
  local stamp = (date and date("%H:%M:%S")) or tostring(math.floor(GetTime()))
  local log = NS.debugLog
  log[#log + 1] = stamp .. " " .. text
  if #log > DEBUG_MAX then table.remove(log, 1) end
  if NS.db and NS.db.debug then NS.Print("|cff999999debug|r " .. text) end
end

function NS.Version()
  local v
  if C_AddOns and C_AddOns.GetAddOnMetadata then v = C_AddOns.GetAddOnMetadata(NS.ADDON, "Version")
  elseif GetAddOnMetadata then v = GetAddOnMetadata(NS.ADDON, "Version") end
  -- The repo's TOC holds "@project-version@"; releases stamp the real number. A symlinked dev checkout shows "dev".
  if not v or v == "" or v:find("@", 1, true) then return "dev" end
  return v
end

function NS.Clean(s) return (s:gsub("[%s~|]", "")) end

function NS.Hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  return string.format("%08x", h)
end

-- The short random wait before a client acts on something another client may act on first.
function NS.Backoff() return 0.3 + math.random() * 1.2 end

function NS.Configured() return NS.db and NS.db.channel and NS.db.channel ~= "" end

function NS.MyRealm()
  local r = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
  return (type(r) == "string" and not issecret(r)) and r:gsub("[%s~|,]", "") or ""
end

-- Who am I, in the format chat events and the roster use. On WoW: Forever that is "First Surname", while
-- UnitName("player") may return only the first name, so identify ourselves by GUID and learn the name from
-- the roster (Roster.lua looks it up on demand) or from our own guild messages. Nicknames are keyed by it.
NS.me = { guid = nil, name = nil }

function NS.LearnMyName(name)
  if not name or name == "" or NS.me.name == name then return end
  local old = NS.me.name or UnitName("player")
  NS.me.name = name
  local nicks = NS.db and NS.db.nicks
  if nicks and old ~= name and nicks[old] and not nicks[name] then
    nicks[name] = nicks[old]      -- re-key a nickname saved under the short name
    nicks[old] = nil
  end
end

function NS.MyName()
  if not NS.me.name and NS.LearnMyNameFromRoster then NS.LearnMyNameFromRoster() end
  return NS.me.name or UnitName("player")
end

function NS.IsMe(author, guid)
  if guid and NS.me.guid and not issecret(guid) and guid == NS.me.guid then
    NS.LearnMyName(author)
    return true
  end
  return author == NS.MyName() or author == UnitName("player")
end

function NS.GetTag()
  if NS.db.tag and NS.db.tag ~= "" then return NS.db.tag end
  local g = GetGuildInfo("player")
  if not g then return nil end
  return (g:gsub("[%s~|]", "")):sub(1, 6)
end

-- Cut to a byte limit without breaking links, colour codes or UTF-8 sequences; "..." marks the cut.
function NS.Truncate(msg, limit)
  limit = math.max(20, math.min(limit or NS.MAX_MSG, NS.MAX_MSG))
  if #msg <= limit then return msg end
  msg = msg:sub(1, limit - 3)
  local last = msg:byte(-1)
  if last and last >= 128 then msg = (msg:gsub("[\192-\255][\128-\191]*$", "")) end
  local _, o = msg:gsub("|c", "")
  local _, c = msg:gsub("|r", "")
  if o ~= c or msg:sub(-1) == "|" then
    msg = msg:sub(1, (msg:find("|c[^|]*$") or (#msg + 1)) - 1)
  end
  return msg .. "..."
end

-- Split a packet body into n fields on SEP; the last field takes the remainder (it may contain SEP).
function NS.Split(rest, n)
  local out, pos = {}, 1
  for i = 1, n - 1 do
    local e = rest:find(NS.SEP, pos, true)
    if not e then return nil end
    out[i] = rest:sub(pos, e - 1)
    pos = e + 1
  end
  out[n] = rest:sub(pos)
  return unpack(out, 1, n)
end

-- A value from the game, or nil when it is a secret value.
function NS.Plain(v)
  if v == nil or issecret(v) then return nil end
  return v
end

function NS.HexToRGB(hex)
  hex = (hex and hex:match("^%x%x%x%x%x%x$")) and hex or NS.DEFAULT_OFFICER_COLOR
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

function NS.CleanNick(str)
  str = (str or ""):gsub("[~|%c]", "")
  str = str:gsub("^%s+", ""):gsub("%s+$", "")
  return str:sub(1, 20)
end

-- "(Rank Nickname) " for officers with a nickname, "(Rank) " for officers without, "(Nickname) " for everyone
-- else, "" if neither applies. The prefix shown before a line's text.
function NS.RankNickPrefix(rank, nick)
  if nick and nick ~= "" then
    if rank then return "(" .. rank .. " " .. nick .. ") " end
    return "(" .. nick .. ") "
  end
  if rank then return "(" .. rank .. ") " end
  return ""
end
