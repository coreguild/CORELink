-- Cross-version compatibility test: a released CORELink and the working copy, each loaded into its own fake
-- game client, talk to each other. Released clients never change, so every format they read or write is frozen:
-- the CL4 channel line and its id, the whisper packets (HELLO, PEER, DIR, WB), the guild addon packets (PRESENT,
-- NICK, LINE, ECHO), the Guild Info line and the saved variables. docs/ARCHITECTURE.md, "Frozen formats".
-- From 0.2.1 the working copy sends no whisper of any kind. It still reads a WB the release carries to it, and
-- it must take the release's HELLO, PEER and DIR without an error and without an answer.
--   lua tests/compat.lua <dir of the released addon> <dir of the working copy> [label of the release]
-- tests/compat.sh extracts the release from its tag and calls this. Runs on Lua 5.1 to 5.5.
-- Each check prints PASS/FAIL; the script exits non-zero if any check fails.
-- The fake client is a small copy of the one in tests/harness.lua, per instance instead of global.
local oldDir, newDir, baseline = arg[1], arg[2], arg[3] or "release"
assert(oldDir and newDir, "usage: lua tests/compat.lua <released addon dir> <working copy addon dir> [label]")
local unpack = unpack or table.unpack
local OLD = { dir = oldDir, label = baseline, version = (baseline:gsub("^v", "")) }
local NEW = { dir = newDir, label = "the working copy" }

local failures, checks = 0, 0
local function check(name, cond, detail)
  checks = checks + 1
  if cond then print("PASS " .. name) return end
  failures = failures + 1
  print("FAIL " .. name .. (detail ~= nil and ("  -- " .. tostring(detail)) or ""))
end

---------------------------------------------------------------- the world: one clock, one network, many clients
-- Whole-second clock like the harness (the addon formats times with %d). Timers due within a tick run in the
-- order of their exact times, and whatever a client sends is delivered before the next timer runs.
local function newWorld(startAt)
  local w = { now = startAt or 1000, timers = {}, clients = {}, guilds = {}, queue = {}, channelPw = {},
              stamp = 0, oversize = {} }

  function w.tick() w.stamp = w.stamp + 1; return w.stamp end

  function w.after(at, fn, client, every)
    w.timers[#w.timers + 1] = { at = at, seq = w.tick(), fn = fn, client = client, every = every }
  end

  function w.deliver(client, event, ...)
    w.queue[#w.queue + 1] = { client = client, event = event, args = { ... }, n = select("#", ...) }
  end

  function w.flush()
    while #w.queue > 0 do
      local d = table.remove(w.queue, 1)
      d.client:fire(d.event, unpack(d.args, 1, d.n))
    end
  end

  local function popDue()
    local best
    for i, t in ipairs(w.timers) do
      local b = best and w.timers[best]
      if t.at <= w.now and (not b or t.at < b.at or (t.at == b.at and t.seq < b.seq)) then best = i end
    end
    return best and table.remove(w.timers, best)
  end

  function w.advance(seconds)
    for _ = 1, seconds do
      w.now = w.now + 1
      local t = popDue()
      while t do
        if t.every then w.after(t.at + t.every, t.fn, t.client, t.every) end
        t.client:run(t.fn)
        w.flush()
        t = popDue()
      end
    end
  end

  -- A guild message as every online member's client receives it, the author's own included.
  function w.guildSay(guild, author, text)
    for _, c in ipairs(w.clients) do
      if c.guild == guild then
        w.deliver(c, "CHAT_MSG_GUILD", text, author, nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-" .. author)
      end
    end
  end

  -- A member without the addon speaks in guild chat.
  function w.say(guild, author, text) w.guildSay(guild, author, text); w.flush() end

  function w.channelText(sender, name, text)
    for _, c in ipairs(w.clients) do
      if c.joined[name] then
        w.deliver(c, "CHAT_MSG_CHANNEL", text, sender, "", c.joined[name] .. ". " .. name, sender, "", 0,
          c.joined[name], name)
      end
    end
  end

  -- An addon message reaches only clients that registered its prefix with the game.
  function w.addon(sender, prefix, text, kind, target)
    for _, c in ipairs(w.clients) do
      local reaches = (kind == "GUILD" and c.guild == sender.guild) or (kind == "WHISPER" and c.name == target)
      if reaches and c.prefixes[prefix] then w.deliver(c, "CHAT_MSG_ADDON", prefix, text, kind, sender.name) end
    end
  end

  -- The network delivers a recorded send a second time (two paths, a retry, a second courier).
  function w.replay(rec)
    if rec.kind == "CHANNEL" then w.channelText(rec.from.name, rec.channel, rec.text)
    else w.addon(rec.from, rec.prefix, rec.text, rec.kind, rec.target) end
    w.flush()
  end

  return w
end

---------------------------------------------------------------- one fake game client
local function widget(client)
  local f = setmetatable({}, { __index = function() return function() end end })
  f.SetScript = function(_, ev, fn) if ev == "OnEvent" then client.handler = fn end end
  f.RegisterEvent = function(_, ev) client.registered[ev] = true end
  f.CreateFontString = function() return widget(client) end
  return f
end

-- What the game tells a client about itself, its guild and its chat windows.
local function describeClient(w, c, env)
  local guild, me = w.guilds[c.guild], nil
  for _, m in ipairs(guild.roster) do if m[1] == c.name then me = m end end
  env.GetTime = function() return w.now end
  env.date = function(fmt) return os.date(fmt, 1759680000 + w.now) end
  env.NUM_CHAT_WINDOWS = 2
  for i = 1, 2 do
    env["ChatFrame" .. i] = { AddMessage = function(_, text)
      c.chat[#c.chat + 1] = { frame = i, text = text, stamp = w.tick() }
    end }
  end
  env.DEFAULT_CHAT_FRAME = env.ChatFrame1
  env.GetChatWindowMessages = function(i) if i == 1 then return "SAY", "GUILD" end end
  env.ChatTypeInfo = { GUILD = { r = .25, g = 1, b = .25 } }
  env.RAID_CLASS_COLORS = { MAGE = { r = .25, g = .78, b = .92 }, WARRIOR = { r = .78, g = .61, b = .43 },
                            PRIEST = { r = 1, g = 1, b = 1 } }
  env.ChatFrame_RemoveChannel = function() end
  env.ChatFrame_AddMessageEventFilter = function() end
  env.CreateFrame = function() return widget(c) end
  env.UIParent = {}
  env.UnitName = function() return (c.name:match("^%S+")) end      -- first name only, as on Forever
  env.UnitGUID = function() return "guid-" .. c.name end
  env.UnitClass = function() return me[4], me[4] end
  env.GetNormalizedRealmName = function() return c.realm end
  env.GetRealmName = function() return c.realm end
  env.Ambiguate = function(n) return (n:match("^[^-]+")) end
  env.IsInGuild = function() return true end
  env.GetGuildInfo = function() return c.guild, me[2], me[3] end
  env.GetGuildInfoText = function() return guild.info end
  env.GetNumGuildMembers = function() return #guild.roster end
  env.GetGuildRosterInfo = function(i)
    local m = guild.roster[i]
    if not m then return end
    return m[1], m[2], m[3], 60, m[4], "Zone", "", "", true, 0, m[4], nil, nil, nil, nil, nil, "guid-" .. m[1]
  end
  env.GetPlayerInfoByGUID = function(guid)
    for _, m in ipairs(guild.roster) do if "guid-" .. m[1] == guid then return "", m[4] end end
  end
  env.C_AddOns = { GetAddOnMetadata = function(_, key) if key == "Version" then return c.build.version end end }
  env.C_Club = { GetSubscribedClubs = function() return {} end }
  env.C_FriendList = { SetWhoToUi = function() end, SendWho = function() c.whoQueries = c.whoQueries + 1 end,
                       GetNumWhoResults = function() return 0 end, GetWhoInfo = function() end }
end

-- What a client can do: timers, channels, chat and addon sends, the chat edit box and its hooks.
local function wireClient(w, c, env)
  env.C_Timer = {
    After = function(d, fn) w.after(w.now + d, fn, c) end,
    NewTicker = function(d, fn) w.after(w.now + d, fn, c, d) end,
  }
  env.GetChannelName = function(n) return c.joined[n] or 0, c.joined[n] and n or nil end
  env.JoinChannelByName = function(n, pw)
    if w.channelPw[n] == nil then w.channelPw[n] = pw or "" end
    if w.channelPw[n] == (pw or "") then c.joined[n] = 6 end       -- a wrong password does not get in
  end
  env.LeaveChannelByName = function(n) c.joined[n] = nil end
  env.hooksecurefunc = function(a, b, fn)
    if type(a) == "table" then c.hooks[a] = c.hooks[a] or {}; c.hooks[a][b] = fn else c.hooks[a] = b end
  end
  c.editBox = { ParseText = function() end, GetAttribute = function() return "GUILD" end,
                GetText = function() return c.editText end }
  env.ChatFrame1EditBox = c.editBox
  local function record(kind, text, target, channel, prefix)
    local rec = { from = c, kind = kind, text = text, target = target, channel = channel, prefix = prefix,
                  stamp = w.tick() }
    c.sent[#c.sent + 1] = rec
    if #text > 255 then w.oversize[#w.oversize + 1] = c.name .. ": " .. text end   -- the game refuses these
    return #text <= 255
  end
  env.SendChatMessage = function(text, kind, _, target)
    if kind == "CHANNEL" then
      local name
      for n, id in pairs(c.joined) do if id == target then name = n end end
      if name and record("CHANNEL", text, nil, name) then w.channelText(c.name, name, text) end
    elseif kind == "GUILD" and record("GUILDCHAT", text) then
      w.guildSay(c.guild, c.name, text)
    elseif kind == "WHISPER" then
      record("WHISPERCHAT", text, target)
    end
    if c.hooks.SendChatMessage then c.hooks.SendChatMessage(text, kind) end   -- a secure hook runs after the call
  end
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) c.prefixes[prefix] = true end,
    SendChatMessage = function() end,
    GuildRoster = function() end,
    SendAddonMessage = function(prefix, text, kind, target)
      if record(kind, text, target, nil, prefix) then w.addon(c, prefix, text, kind, target) end
      return 0
    end,
  }
end

-- The addon's files in the order its own TOC lists them, each given the same private table, as the game does it.
-- Every global the files read or write resolves in env, so two instances share nothing but the Lua libraries.
local function loadAddon(dir, env)
  local NS = {}
  for line in io.lines(dir .. "/CORELink.toc") do
    local file = line:match("^([%w_]+%.lua)%s*$")
    if file then
      local chunk
      if setfenv then
        chunk = assert(loadfile(dir .. "/" .. file))
        setfenv(chunk, env)
      else
        chunk = assert(loadfile(dir .. "/" .. file, "t", env))
      end
      chunk("CORELink", NS)
    end
  end
end

local Client = {}
Client.__index = Client

-- Run addon code the way the game does: an error does not stop the game, it is reported. Here it is recorded.
function Client:run(fn, ...)
  local args, n = { ... }, select("#", ...)
  local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, debug.traceback)
  if not ok then self.errors[#self.errors + 1] = tostring(err) end
end

function Client:fire(event, ...)
  if self.registered[event] and self.handler then self:run(self.handler, nil, event, ...) end
end

function Client:login()
  self:fire("ADDON_LOADED", "CORELink")
  self:fire("PLAYER_LOGIN")
  self:fire("GUILD_ROSTER_UPDATE")
  self.world.flush()
end

function Client:slash(text)
  self:run(self.env.SlashCmdList["CORELINK"], text)
  self.world.flush()
end

-- The player types a guild line and presses Enter: the edit box hook fires, then the game sends the line.
function Client:type(text)
  self.editText = text
  local hook = self.hooks[self.editBox] and self.hooks[self.editBox].ParseText
  if hook then self:run(hook, self.editBox, 1) end
  self:run(self.env.SendChatMessage, text, "GUILD")
  self.world.flush()
end

-- The lines drawn in this client's chat windows since the mark that contain the text. How a line is dressed
-- (brackets, colours, links) is each version's own business; that it is there, once, is not.
function Client:drawn(mark, text)
  local out = {}
  for _, l in ipairs(self.chat) do
    if l.stamp > mark and l.text:find(text, 1, true) then out[#out + 1] = l.text end
  end
  return out
end

-- Sends of one kind since the mark whose text starts with the prefix.
function Client:sends(mark, kind, prefix)
  local out = {}
  for _, s in ipairs(self.sent) do
    if s.stamp > mark and s.kind == kind and s.text:find(prefix or "", 1, true) == 1 then out[#out + 1] = s end
  end
  return out
end

function Client:db() return self.env.CORELinkDB or {} end

-- A table inside the saved variables (nicks, peers, muted); empty when it is missing, so a check fails, not crashes.
function Client:saved(field)
  local t = self:db()[field]
  return type(t) == "table" and t or {}
end

local everyClient = {}   -- of every scenario, for the checks at the end

-- spec: build (OLD or NEW), name, guild, optional realm, rand (what math.random() returns here) and db (the
-- saved variables from an earlier session).
local function join(w, spec)
  local c = setmetatable({ world = w, build = spec.build, name = spec.name, guild = spec.guild,
    realm = spec.realm or "CAMWOWUS1Realm1PvE", chat = {}, sent = {}, errors = {}, joined = {}, hooks = {},
    registered = {}, prefixes = {}, editText = "", whoQueries = 0 }, Client)
  local env = setmetatable({}, { __index = _G })
  env._G, env.unpack, env.SlashCmdList, env.CORELinkDB = env, unpack, {}, spec.db
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end end
  -- a fixed "random" per client: back-offs are the same on every Lua version, and a test can make one client faster
  env.math = setmetatable({ random = function() return spec.rand or 0.5 end }, { __index = math })
  describeClient(w, c, env)
  wireClient(w, c, env)
  c.env = env
  local ok, err = pcall(loadAddon, spec.build.dir, env)
  if not ok then c.errors[#c.errors + 1] = "while loading: " .. tostring(err) end
  w.clients[#w.clients + 1] = c
  everyClient[#everyClient + 1] = c
  return c
end

---------------------------------------------------------------- helpers for the checks
local function all(text, ...)   -- text contains every one of the plain strings
  for _, needle in ipairs({ ... }) do if not text:find(needle, 1, true) then return false end end
  return true
end

-- The client drew the text exactly once since the mark, in a line that also names the other strings.
local function shownOnce(c, mark, text, ...)
  local lines = c:drawn(mark, text)
  return #lines == 1 and all(lines[1], ...), #lines .. " line(s): " .. table.concat(lines, " || ")
end

local function times(c, mark, text) return #c:drawn(mark, text) end

local function count(clients, mark, kind, prefix)
  local n = 0
  for _, c in ipairs(clients) do n = n + #c:sends(mark, kind, prefix) end
  return n
end

-- Whispers of any kind (addon message or chat) the client sent since the mark.
local function whispers(c, mark) return #c:sends(mark, "WHISPER") + #c:sends(mark, "WHISPERCHAT") end

local RETIRED = "whispering between guilds was retired in 0.2.1"

local function noErrors(what, clients)
  for _, c in ipairs(clients) do
    check(string.format("%s: no Lua error on %s (%s)", what, c.name, c.build.label), #c.errors == 0, c.errors[1])
  end
  local w = clients[1].world
  check(what .. ": nothing sent is over the game's 255 bytes", #w.oversize == 0, w.oversize[1])
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, x in pairs(a) do if not same(x, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local MEMBER, OFFICER = { "Member", 3 }, { "Officer", 1 }
local function roster(...)
  local out = {}
  for _, m in ipairs({ ... }) do out[#out + 1] = { m[1], m[2][1], m[2][2], m[3] } end
  return out
end

local CL4 = "^CL4~%x%x%x%x%x%x%x%x~"
local WAIT = 15   -- seconds given to a back-off before a check says "carried" or "not carried"
local function frozen(pattern) return (pattern:gsub("%-", "%%-")) end

---------------------------------------------------------------- two guilds, each with a released and a new client
-- ALFA: Abe (release, and its courier: the alphabetically first addon user), Mia (working copy, officer),
--       Dora (no addon).
-- BRAV: Bo (working copy), Ned (release, officer), Cora (no addon). Ned takes Bo for the courier, because Bo
--       comes first in the alphabet and announces himself with PRESENT; Bo carries nothing.
local function twoGuilds()
  local w = newWorld()
  w.guilds["Alpha Guild"] = { info = "Welcome!\nCORELink: CompatLink pw1 ALFA 1\n",
    roster = roster({ "Abe Alder", MEMBER, "MAGE" }, { "Mia Moss", OFFICER, "PRIEST" },
      { "Dora Dunn", MEMBER, "WARRIOR" }) }
  w.guilds["Bravo Guild"] = { info = "CORELink: CompatLink pw1 BRAV 1",
    roster = roster({ "Bo Birch", MEMBER, "WARRIOR" }, { "Ned Nash", OFFICER, "PRIEST" },
      { "Cora Cole", MEMBER, "MAGE" }) }
  local abe = join(w, { build = OLD, name = "Abe Alder", guild = "Alpha Guild" })
  local mia = join(w, { build = NEW, name = "Mia Moss", guild = "Alpha Guild" })
  local bo = join(w, { build = NEW, name = "Bo Birch", guild = "Bravo Guild", realm = "CAMWOWUS2Realm5PvE" })
  local ned = join(w, { build = OLD, name = "Ned Nash", guild = "Bravo Guild", realm = "CAMWOWUS2Realm5PvE" })
  local everyone = { abe, mia, bo, ned }
  for _, c in ipairs(everyone) do c:login() end
  w.advance(40)            -- Guild Info read (5 s), channel join, presence (25 s)
  return w, abe, mia, bo, ned, everyone
end

local w, abe, mia, bo, ned, everyone = twoGuilds()
for _, c in ipairs(everyone) do
  local db = c:db()
  check(string.format("login: %s (%s) is configured from Guild Info and in the channel", c.name, c.build.label),
    db.channel == "CompatLink" and db.password == "pw1" and c.joined.CompatLink ~= nil,
    tostring(db.channel) .. " " .. tostring(db.password) .. " " .. tostring(c.errors[1]))
end
check("presence: the release announces itself as PRESENT~version",
  #abe:sends(0, "GUILD", "PRESENT~" .. OLD.version) >= 1)
check("presence: the working copy announces itself as PRESENT~version", #mia:sends(0, "GUILD", "PRESENT~") >= 1)

-- greetings, before any line has made anyone a peer: the release still sends HELLO, the working copy never
-- answers and never greets
local mark = w.tick()
abe:slash("hello Bo Birch"); w.advance(4)
local hello = abe:sends(mark, "WHISPER", "HELLO~")[1]
check("hello: the release greets with HELLO~tag~realm~guild",
  hello and hello.target == "Bo Birch" and hello.text == "HELLO~ALFA~CAMWOWUS1Realm1PvE~Alpha Guild",
  hello and hello.text)
check("hello: the working copy does not answer the release's HELLO: no PEER, no DIR, nothing whispered",
  whispers(bo, mark) == 0, whispers(bo, mark))
check("hello: the release's HELLO draws no chat line on the working copy and teaches it no peer",
  #bo:drawn(mark, "") == 0 and bo:saved("peers")["Abe Alder"] == nil, bo:drawn(mark, "")[1])
check("hello: the release's HELLO causes no error on either side", #abe.errors == 0 and #bo.errors == 0,
  abe.errors[1] or bo.errors[1])
mark = w.tick()
mia:slash("hello Ned Nash"); mia:slash("who"); mia:slash("whisper on"); w.advance(4)
check("hello: /cl hello, /cl who and /cl whisper on the working copy each say whispering was retired",
  times(mia, mark, RETIRED) == 3, times(mia, mark, RETIRED))
check("hello: the working copy's retired commands send nothing, and the release hears nothing",
  whispers(mia, mark) == 0 and mia.whoQueries == 0 and ned:saved("peers")["Mia Moss"] == nil
  and #ned:drawn(mark, "") == 0, whispers(mia, mark))

-- typed lines: channel text, read by every addon user of the other guild
mark = w.tick()
local said = "hello from the release"
abe:type(said); w.advance(1)
local line = abe:sends(mark, "CHANNEL")[1]
check("typed: the release posts CL4~id~tag~author~class~flags~nick~text into the channel",
  line and line.text:match(frozen(CL4 .. "ALFA~Abe Alder~MAGE~~~hello from the release$")), line and line.text)
check("typed: a line from the release is shown on the working copy, once",
  shownOnce(bo, mark, said, "ALFA", "Abe Alder"))
check("typed: a line from the release is shown on a release client of the other guild, once",
  shownOnce(ned, mark, said, "ALFA", "Abe Alder"))
check("typed: the author's own guild, either version, shows no bridged copy",
  times(abe, mark, said) == 0 and times(mia, mark, said) == 0)
if line then w.replay(line) end
check("typed: the release's line delivered twice is still shown once on the working copy", shownOnce(bo, mark, said))

mark = w.tick()
said = "hello from the working copy"
bo:type(said); w.advance(1)
line = bo:sends(mark, "CHANNEL")[1]
check("typed: the working copy posts CL4~id~tag~author~class~flags~nick~text into the channel",
  line and line.text:match(frozen(CL4 .. "BRAV~Bo Birch~WARRIOR~~~hello from the working copy$")), line and line.text)
check("typed: a line from the working copy is shown on the release, once",
  shownOnce(abe, mark, said, "BRAV", "Bo Birch"))
check("typed: a line from the working copy is shown on a working-copy client of the other guild, once",
  shownOnce(mia, mark, said, "BRAV", "Bo Birch"))
if line then w.replay(line) end
check("typed: the working copy's line delivered twice is still shown once on the release", shownOnce(abe, mark, said))

-- nicknames travel to guildmates as NICK, and with the officer rank in the flags and nick fields of a line
mia:slash("nickname Emster"); ned:slash("nickname Nedder"); w.advance(1)
check("nick: the release stores a NICK~name sent by the working copy", abe:saved("nicks")["Mia Moss"] == "Emster")
check("nick: the working copy stores a NICK~name sent by the release", bo:saved("nicks")["Ned Nash"] == "Nedder")

-- The same line id on both sides. The author's client posts the line; the courier of the same guild runs the
-- other version, sees the line in guild chat and must recognise the channel copy as the same line. If the two
-- computed different ids the courier would carry a second copy and the other guild would see the line twice.
mark = w.tick()
said = "an officer on the working copy"
mia:type(said); w.advance(WAIT)
line = mia:sends(mark, "CHANNEL")[1]
check("typed: the working copy's officer line carries O<rank> and the nickname",
  line and line.text:match(frozen(CL4 .. "ALFA~Mia Moss~PRIEST~OOfficer~Emster~an officer on the working copy$")),
  line and line.text)
check("typed: the release shows the working copy's officer rank and nickname",
  shownOnce(ned, mark, said, "ALFA", "Mia Moss", "Officer", "Emster"))
check("same id: the release's courier does not carry a line the working copy already posted",
  count(everyone, mark, "WHISPER", "WB~") == 0, count(everyone, mark, "WHISPER", "WB~"))
check("same id: the other guild saw that line once on each version",
  times(bo, mark, said) == 1 and times(ned, mark, said) == 1,
  times(bo, mark, said) .. " and " .. times(ned, mark, said))

mark = w.tick()
said = "an officer on the release"
ned:type(said); w.advance(WAIT)
line = ned:sends(mark, "CHANNEL")[1]
check("typed: the release's officer line carries O<rank> and the nickname",
  line and line.text:match(frozen(CL4 .. "BRAV~Ned Nash~PRIEST~OOfficer~Nedder~an officer on the release$")),
  line and line.text)
check("typed: the working copy shows the release's officer rank and nickname",
  shownOnce(mia, mark, said, "BRAV", "Ned Nash", "Officer", "Nedder"))
check("same id: nobody carries a line the release already posted",
  count(everyone, mark, "WHISPER", "WB~") == 0, count(everyone, mark, "WHISPER", "WB~"))
check("same id: the other guild saw that line once on each version",
  times(abe, mark, said) == 1 and times(mia, mark, said) == 1,
  times(abe, mark, said) .. " and " .. times(mia, mark, said))

-- carried lines, from a guild still on 0.2.0: a member without the addon speaks, the release's courier whispers
-- WB to the freshest peer of the other guild, who shows it and fans it out to its guild as LINE
bo:type("bo is the freshest peer now"); w.advance(2)
mark = w.tick()
said = "dora has no addon"
w.say("Alpha Guild", "Dora Dunn", said); w.advance(WAIT)
local carried = abe:sends(mark, "WHISPER", "WB~")[1]
check("carried: the release's courier whispers WB~<CL4 packet> to one peer, a working-copy client", carried
  and count(everyone, mark, "WHISPER", "WB~") == 1 and carried.target == "Bo Birch"
  and carried.text:match(frozen("^WB~CL4~%x+~ALFA~Dora Dunn~WARRIOR~~~dora has no addon$")), carried and carried.text)
check("carried: the working copy accepts the release's WB and shows the line, once",
  shownOnce(bo, mark, said, "ALFA", "Dora Dunn"))
local fan = bo:sends(mark, "GUILD", "LINE~")
check("carried: the working copy fans it out to its guild as LINE~<the same packet>, once",
  carried and #fan == 1 and fan[1].text == "LINE~" .. carried.text:sub(4), fan[1] and fan[1].text)
check("carried: a release guildmate shows the working copy's LINE, once",
  shownOnce(ned, mark, said, "ALFA", "Dora Dunn"))
check("carried: the working copy whispers nothing while it takes the line and fans it out",
  whispers(bo, mark) == 0 and whispers(mia, mark) == 0)
if carried then w.replay(carried) end
check("carried: the same WB delivered twice is shown once and fanned out once",
  times(bo, mark, said) == 1 and times(ned, mark, said) == 1 and #bo:sends(mark, "GUILD", "LINE~") == 1)

-- the same, with a release client as the freshest peer: it fans the line out and its working-copy guildmate shows it
ned:type("ned is the freshest peer now"); w.advance(2)
mark = w.tick()
said = "dora speaks again"
w.say("Alpha Guild", "Dora Dunn", said); w.advance(WAIT)
carried = abe:sends(mark, "WHISPER", "WB~")[1]
check("carried: the release's courier whispers WB to a release client when that is the freshest peer",
  carried and count(everyone, mark, "WHISPER", "WB~") == 1 and carried.target == "Ned Nash", carried and carried.target)
fan = ned:sends(mark, "GUILD", "LINE~")
check("carried: the release fans it out to its guild as LINE~<the same packet>, once",
  carried and #fan == 1 and fan[1].text == "LINE~" .. carried.text:sub(4), fan[1] and fan[1].text)
check("carried: a working-copy guildmate shows the release's LINE, once",
  shownOnce(bo, mark, said, "ALFA", "Dora Dunn"))
check("carried: the working copy does not fan out or whisper on a line that reached it as LINE",
  #bo:sends(mark, "GUILD", "LINE~") == 0 and whispers(bo, mark) == 0)
if fan[1] then w.replay(fan[1]) end
check("carried: the same LINE delivered twice is shown once",
  times(bo, mark, said) == 1 and times(ned, mark, said) == 1)

-- A mixed guild. The release leaves carrying to the alphabetically first addon user of its guild. In BRAV that
-- is Bo, on the working copy, which carries nothing: Cora's line stays in her guild.
abe:type("abe is the freshest peer now"); w.advance(2)
mark = w.tick()
said = "cora has no addon"
w.say("Bravo Guild", "Cora Cole", said); w.advance(4 * WAIT)
check("0.2.1 as intended: a member without the addon is not bridged when the guild's first addon user runs"
  .. " the working copy (nobody whispers, the other guild does not see the line)",
  count(everyone, mark, "WHISPER") == 0 and times(abe, mark, said) == 0 and times(mia, mark, said) == 0,
  count(everyone, mark, "WHISPER") .. " whisper(s)")

-- The longest lines the game lets a player type. Every packet made from one must stay within the game's 255
-- bytes (noErrors below fails on any that does not) and still arrive, cut, on both versions of the other guild.
local function longLine(word) return (word:rep(50)) end   -- 250 bytes
local function arrives(readers, from, text)
  for _, c in ipairs(readers) do if times(c, from, text:sub(1, 150)) ~= 1 then return false, c.name end end
  return true
end
mark = w.tick()
mia:type(longLine("mia. ")); w.advance(WAIT)
check("long: a 250-byte line typed by an officer with a nickname on the working copy arrives once",
  arrives({ bo, ned }, mark, longLine("mia. ")))
ned:type(longLine("ned. ")); w.advance(WAIT)
check("long: a 250-byte line typed by an officer with a nickname on the release arrives once",
  arrives({ abe, mia }, mark, longLine("ned. ")))
bo:type("bo is the freshest peer again"); w.advance(2)
local longMark = w.tick()
w.say("Alpha Guild", "Dora Dunn", longLine("dora ")); w.advance(WAIT)
check("long: a 250-byte line carried by the release's courier arrives once, through the working copy's fan-out",
  arrives({ bo, ned }, longMark, longLine("dora ")))
check("long: the long lines went out as one copy each (two typed, one carried, one fanned out)",
  count(everyone, mark, "CHANNEL", "CL4~") == 3 and count(everyone, longMark, "WHISPER", "WB~") == 1
  and count(everyone, longMark, "GUILD", "LINE~") == 1 and #bo:sends(longMark, "GUILD", "LINE~") == 1)

-- New data travels in new packet kinds. A kind the release has never heard of (letters only) must leave it alone.
local before = { nicks = copy(abe:saved("nicks")), chat = #abe.chat }
w.addon(mia, "CORELink", "LATER~some~new~data", "GUILD")
w.addon(bo, "CORELink", "LATER~some~new~data", "WHISPER", "Abe Alder")
w.flush(); w.advance(1)
check("new kinds: the release ignores a guild or whisper packet of a kind it does not know",
  #abe.errors == 0 and #abe.chat == before.chat and same(before.nicks, abe:saved("nicks")), abe.errors[1])

-- settings a player of the release would have saved by the end of a session; used further down
abe:slash("nickname Abby"); abe:slash("mute zulu"); abe:slash("officercolor aabbcc"); w.advance(120)
noErrors("two guilds", everyone)
local savedByRelease = copy(abe:db())

---------------------------------------------------------------- 0.2.1: a guild with no 0.2.0 client
-- A member without the addon is not bridged from such a guild.
-- ALFA's addon users all run the working copy. Everyone has typed, so every client knows peers in the other
-- guild, which is all 0.2.0 needed to carry Dora's line.
local function unbridged()
  local u = newWorld()
  u.guilds["Alpha Guild"] = { info = "CORELink: CompatLink pw1 ALFA 1",
    roster = roster({ "Max Marsh", MEMBER, "MAGE" }, { "Mia Moss", MEMBER, "PRIEST" },
      { "Dora Dunn", MEMBER, "WARRIOR" }) }
  u.guilds["Bravo Guild"] = { info = "CORELink: CompatLink pw1 BRAV 1",
    roster = roster({ "Bo Birch", MEMBER, "WARRIOR" }, { "Ned Nash", MEMBER, "PRIEST" }) }
  local max = join(u, { build = NEW, name = "Max Marsh", guild = "Alpha Guild" })
  local mia2 = join(u, { build = NEW, name = "Mia Moss", guild = "Alpha Guild" })
  local bo2 = join(u, { build = NEW, name = "Bo Birch", guild = "Bravo Guild" })
  local ned2 = join(u, { build = OLD, name = "Ned Nash", guild = "Bravo Guild" })
  local four = { max, mia2, bo2, ned2 }
  for _, c in ipairs(four) do c:login() end
  u.advance(40)
  for _, c in ipairs(four) do c:type(c.name .. " is here"); u.advance(2) end
  check("0.2.1 as intended: typed lines still cross both ways before the member without the addon speaks",
    times(ned2, 0, "Max Marsh is here") == 1 and times(bo2, 0, "Mia Moss is here") == 1
    and times(max, 0, "Ned Nash is here") == 1 and times(mia2, 0, "Bo Birch is here") == 1)
  local from = u.tick()
  u.say("Alpha Guild", "Dora Dunn", "dora in a guild of working copies"); u.advance(4 * WAIT)
  check("0.2.1 as intended: a line from a member without the addon, in a guild whose only addon users run the"
    .. " working copy, does NOT reach the other guild",
    times(ned2, from, "dora in a guild") == 0 and times(bo2, from, "dora in a guild") == 0,
    times(ned2, from, "dora in a guild") + times(bo2, from, "dora in a guild"))
  check("0.2.1 as intended: nobody whispered that line, and nothing was fanned out",
    count(four, from, "WHISPER", "WB~") == 0 and count(four, from, "GUILD", "LINE~") == 0
    and whispers(max, 0) + whispers(mia2, 0) + whispers(bo2, 0) == 0)
  noErrors("a guild of working copies", four)
end
unbridged()

---------------------------------------------------------------- gossip: the release's PEER and DIR
-- Ann and Ben know each other. Cy greets Ben, and Ben answers with PEER and a DIR naming Ann: all three on the
-- release, which is the only way a DIR is ever written (it answers a HELLO, and the working copy sends none).
-- The same PEER and DIR are then delivered to Dee, on the working copy: it must take them without an error,
-- answer nothing, show nothing and learn nobody.
local function gossip()
  local g = newWorld()
  local members = { Alpha = "Ann Ash", Bravo = "Ben Bay", Gamma = "Cy Cole", Delta = "Dee Dale" }
  local c = {}
  for _, name in ipairs({ "Alpha", "Bravo", "Gamma", "Delta" }) do
    g.guilds[name .. " Guild"] = { info = "CORELink: CompatLink pw1 " .. name:sub(1, 4):upper(),
      roster = roster({ members[name], MEMBER, "MAGE" }) }
    c[name] = join(g, { build = name == "Delta" and NEW or OLD, name = members[name], guild = name .. " Guild" })
  end
  local ann, ben, cy, dee = c.Alpha, c.Bravo, c.Gamma, c.Delta
  for _, x in ipairs({ ann, ben, cy, dee }) do x:login() end
  g.advance(40)
  ann:slash("hello Ben Bay"); g.advance(4)
  local from = g.tick()
  cy:slash("hello Ben Bay"); g.advance(8)
  local answer, dir = ben:sends(from, "WHISPER", "PEER~")[1], ben:sends(from, "WHISPER", "DIR~")[1]
  check("gossip: the release still writes DIR~name@realm@tag@guild", dir and dir.target == "Cy Cole"
    and all(";" .. dir.text:sub(5) .. ";", ";Ann Ash@CAMWOWUS1Realm1PvE@ALPH@Alpha Guild;"), dir and dir.text)
  from = g.tick()
  if answer then g.addon(ben, answer.prefix, answer.text, "WHISPER", "Dee Dale") end
  if dir then g.addon(ben, dir.prefix, dir.text, "WHISPER", "Dee Dale") end
  g.addon(ben, "CORELink", "DIR~", "WHISPER", "Dee Dale")
  g.addon(ben, "CORELink", "DIR~Dee Dale@CAMWOWUS1Realm1PvE@DELT@Delta Guild;x@@@;;@", "WHISPER", "Dee Dale")
  g.flush(); g.advance(700)                -- past the release's ten-minute greeting throttle
  check("gossip: the release's PEER and DIR are ignored by the working copy without error",
    answer and dir and #dee.errors == 0, dee.errors[1])
  check("gossip: the working copy answers none of it and greets nobody it names", whispers(dee, 0) == 0
    and #dee:sends(from, "GUILD", "LINE~") == 0, whispers(dee, 0))
  check("gossip: the working copy shows nothing for it and learns no peer from it", #dee:drawn(from, "") == 0
    and dee:saved("peers")["Ann Ash"] == nil and dee:saved("peers")["Ben Bay"] == nil, dee:drawn(from, "")[1])
  noErrors("gossip", { ann, ben, cy, dee })
end
gossip()

---------------------------------------------------------------- echo: one client per guild claims a line with ECHO~id
-- Mia draws the shorter back-off and claims the line; Abe must stand down on her ECHO. Abe is also the one the
-- release takes for the courier: on the release he must not carry her echoed guild line back out as if a member
-- had typed it, and on the working copy he carries nothing at all.
local function echo(claimer, other)
  local e = newWorld()
  e.guilds["Alpha Guild"] = { info = "CORELink: CompatLink pw1 ALFA 1 echo=on",
    roster = roster({ "Abe Alder", MEMBER, "MAGE" }, { "Mia Moss", MEMBER, "PRIEST" }) }
  e.guilds["Bravo Guild"] = { info = "CORELink: CompatLink pw1 BRAV 1",
    roster = roster({ "Bo Birch", MEMBER, "WARRIOR" }) }
  local a = join(e, { build = other, name = "Abe Alder", guild = "Alpha Guild", rand = 0.9 })
  local m = join(e, { build = claimer, name = "Mia Moss", guild = "Alpha Guild", rand = 0.1 })
  local b = join(e, { build = claimer, name = "Bo Birch", guild = "Bravo Guild" })
  local three = { a, m, b }
  for _, c in ipairs(three) do c:login() end
  e.advance(40)
  b:slash("nickname Bobby")
  local from = e.tick()
  b:type("echo me"); e.advance(WAIT)
  local what = string.format("echo: claimed by %s, heard by %s", claimer.label, other.label)
  local claim, posted = m:sends(from, "GUILD", "ECHO~"), m:sends(from, "GUILDCHAT")
  check(what .. ": ECHO~id, then the line as guild chat", #claim == 1 and claim[1].text:match("^ECHO~%x+$")
    and #posted == 1 and posted[1].text == "[BRAV] Bo Birch (Bobby): echo me", posted[1] and posted[1].text)
  check(what .. ": the other client does not echo the line a second time",
    #a:sends(from, "GUILDCHAT") == 0 and #a:sends(from, "GUILD", "ECHO~") == 0)
  check(what .. ": the echoed guild line is not carried back out", count(three, from, "WHISPER", "WB~") == 0
    and times(b, from, "echo me") == 0)
  noErrors(what, three)
end
echo(NEW, OLD)
echo(OLD, NEW)

---------------------------------------------------------------- the Guild Info line
-- The same text in Guild Info must give a released client and a new client in that guild the same settings.
local function settings(db)
  return string.format("channel=%s password=%s tag=%s officerRank=%s club=%s echo=%s guilds=%s", tostring(db.channel),
    tostring(db.password), tostring(db.tag), tostring(db.officerRank), tostring(db.club), tostring(db.echo),
    table.concat(db.guilds or {}, "|"))
end

local function guildInfo(text, expected)
  local g = newWorld()
  g.guilds["Alpha Guild"] = { info = text,
    roster = roster({ "Abe Alder", MEMBER, "MAGE" }, { "Mia Moss", MEMBER, "PRIEST" }) }
  local old = join(g, { build = OLD, name = "Abe Alder", guild = "Alpha Guild" })
  local new = join(g, { build = NEW, name = "Mia Moss", guild = "Alpha Guild" })
  old:login(); new:login(); g.advance(60)
  local what = "guild info: " .. (text:match("[Cc][Oo][Rr][Ee][Ll]ink:[^\n]*") or text)
  check(what .. " -- the release reads it as expected", settings(old:db()) == expected, settings(old:db()))
  check(what .. " -- the working copy reads the same settings", settings(new:db()) == settings(old:db()),
    settings(new:db()))
  noErrors(what, { old, new })
end

guildInfo("CORELink: CompatLink pw1 ALFA 2 club=CoreTest echo=on guilds=Alpha Guild, Bravo Guild",
  "channel=CompatLink password=pw1 tag=ALFA officerRank=2 club=CoreTest echo=true guilds=Alpha Guild|Bravo Guild")
guildInfo("CORELink: CompatLink -",
  "channel=CompatLink password= tag=nil officerRank=1 club=nil echo=false guilds=")
guildInfo("Raids on Tuesday\nCORELink: CompatLink pw1 - 0 echo=on\nBe kind",
  "channel=CompatLink password=pw1 tag=nil officerRank=0 club=nil echo=true guilds=")
guildInfo("corelink: CompatLink pw1 ALFA guilds=Bravo Guild",
  "channel=CompatLink password=pw1 tag=ALFA officerRank=1 club=nil echo=false guilds=Bravo Guild")
-- the rule for new data: a key=value field the release does not know, placed before guilds=, changes nothing for it
guildInfo("CORELink: CompatLink pw1 ALFA 1 later=thing echo=on guilds=Bravo Guild",
  "channel=CompatLink password=pw1 tag=ALFA officerRank=1 club=nil echo=true guilds=Bravo Guild")

---------------------------------------------------------------- saved variables written by the release
-- The player updates: the working copy starts with the CORELinkDB that the release left behind (Abe's, above).
local function update()
  local u = newWorld(90000)
  u.guilds["Alpha Guild"] = w.guilds["Alpha Guild"]
  u.guilds["Bravo Guild"] = w.guilds["Bravo Guild"]
  local me = join(u, { build = NEW, name = "Abe Alder", guild = "Alpha Guild", db = copy(savedByRelease) })
  local far = join(u, { build = OLD, name = "Ned Nash", guild = "Bravo Guild" })
  me:login(); far:login(); u.advance(40)
  check("saved variables: the working copy logs in with the release's CORELinkDB without error",
    #me.errors == 0 and me.joined.CompatLink ~= nil, me.errors[1])
  local db, kept = me:db(), {}
  for k, v in pairs(savedByRelease) do
    local sessionOnly = k == "debug" or k == "lastGI" or k == "peers"
    if not sessionOnly and not same(v, db[k]) then kept[#kept + 1] = k end
  end
  check("saved variables: every setting the release saved is intact (channel, tag, nicknames, mutes, colours)",
    #kept == 0 and db.channel == "CompatLink" and me:saved("nicks")["Abe Alder"] == "Abby"
    and me:saved("nicks")["Mia Moss"] == "Emster" and me:saved("muted").zulu == true
    and db.officerColorHex == "aabbcc", "changed: " .. table.concat(kept, ", "))
  local lost = {}
  for name, saved in pairs(savedByRelease.peers or {}) do
    local now = me:saved("peers")[name]
    if not (now and now.tag == saved.tag) then lost[#lost + 1] = name end
  end
  check("saved variables: the peers the release saved are still known",
    #lost == 0 and me:saved("peers")["Bo Birch"] ~= nil, "lost: " .. table.concat(lost, ", "))
  local listed = u.tick()
  me:slash("peers")
  check("saved variables: /cl peers on the working copy lists a peer the release saved, with its tag",
    shownOnce(me, listed, "Bo Birch", "BRAV"))
  -- and that saved peer is still trusted: a line it carries is shown, for a guild not heard since the update
  local carriedAt = u.tick()
  u.addon({ name = "Bo Birch" }, "CORELink", "WB~CL4~0000abcd~BRAV~Cora Cole~MAGE~~~carried by a saved peer",
    "WHISPER", "Abe Alder")
  u.flush(); u.advance(2)
  check("saved variables: a line carried by a peer the release saved is shown on the working copy, once",
    shownOnce(me, carriedAt, "carried by a saved peer", "BRAV", "Cora Cole"))
  local from = u.tick()
  me:type("after the update"); u.advance(1)
  check("saved variables: a line typed after the update reaches the release with the saved nickname",
    shownOnce(far, from, "after the update", "ALFA", "Abe Alder", "Abby"))
  u.advance(1300)                          -- the release pinged its saved peers every ten minutes
  check("saved variables: the working copy whispers to none of the peers the release saved", whispers(me, 0) == 0,
    whispers(me, 0))
  noErrors("saved variables", { me, far })
end
update()

---------------------------------------------------------------- every scenario above: the working copy never whispers
local newClients, whispered, queried, oldWhispered = 0, 0, 0, 0
for _, c in ipairs(everyClient) do
  if c.build == NEW then
    newClients = newClients + 1
    whispered = whispered + whispers(c, 0)
    queried = queried + c.whoQueries
  else
    oldWhispered = oldWhispered + whispers(c, 0)
  end
end
check(string.format("no whispers: the %d working-copy clients of every scenario sent zero WHISPER addon messages"
  .. " and zero chat whispers", newClients), newClients >= 10 and whispered == 0, whispered)
check("no whispers: no working-copy client sent a /who query", queried == 0, queried)
check("no whispers: the count above can see a whisper (the release's clients sent some)", oldWhispered > 0,
  oldWhispered)

print(string.format("\n%d compatibility checks against %s, %d failed", checks, baseline, failures))
os.exit(failures == 0 and 0 or 1)
