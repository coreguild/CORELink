-- Cross-version compatibility test: a released CORELink and the working copy, each loaded into its own fake
-- game client, talk to each other. Released clients never change, so every format they read or write is frozen:
-- the CL4 channel line and its id, the whisper packets (HELLO, PEER, DIR, WB), the guild addon packets (PRESENT,
-- NICK, LINE, ECHO), the Guild Info line and the saved variables. docs/ARCHITECTURE.md, "Frozen formats".
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

  function w.addon(sender, text, kind, target)
    for _, c in ipairs(w.clients) do
      local reaches = (kind == "GUILD" and c.guild == sender.guild) or (kind == "WHISPER" and c.name == target)
      if reaches then w.deliver(c, "CHAT_MSG_ADDON", "CORELink", text, kind, sender.name) end
    end
  end

  -- The network delivers a recorded send a second time (two paths, a retry, a second courier).
  function w.replay(rec)
    if rec.kind == "CHANNEL" then w.channelText(rec.from.name, rec.channel, rec.text)
    else w.addon(rec.from, rec.text, rec.kind, rec.target) end
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
  env.C_FriendList = { SetWhoToUi = function() end, SendWho = function() end,
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
  local function record(kind, text, target, channel)
    local rec = { from = c, kind = kind, text = text, target = target, channel = channel, stamp = w.tick() }
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
    end
    if c.hooks.SendChatMessage then c.hooks.SendChatMessage(text, kind) end   -- a secure hook runs after the call
  end
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() end,
    SendChatMessage = function() end,
    GuildRoster = function() end,
    SendAddonMessage = function(_, text, kind, target)
      if record(kind, text, target) then w.addon(c, text, kind, target) end
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

-- Other guilds' lines drawn in this client's guild chat since the mark (each carries a player link).
function Client:bridged(mark)
  local out = {}
  for _, l in ipairs(self.chat) do
    if l.stamp > mark and l.text:find("|Hplayer:", 1, true) then out[#out + 1] = l.text end
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

-- spec: build (OLD or NEW), name, guild, optional realm, rand (what math.random() returns here) and db (the
-- saved variables from an earlier session).
local function join(w, spec)
  local c = setmetatable({ world = w, build = spec.build, name = spec.name, guild = spec.guild,
    realm = spec.realm or "CAMWOWUS1Realm1PvE", chat = {}, sent = {}, errors = {}, joined = {}, hooks = {},
    registered = {}, editText = "" }, Client)
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
  return c
end

---------------------------------------------------------------- helpers for the checks
local function all(text, ...)   -- text contains every one of the plain strings
  for _, needle in ipairs({ ... }) do if not text:find(needle, 1, true) then return false end end
  return true
end

local function shownOnce(c, mark, ...)
  local lines = c:bridged(mark)
  return #lines == 1 and all(lines[1], ...), #lines .. " line(s): " .. table.concat(lines, " || ")
end

local function count(clients, mark, kind, prefix)
  local n = 0
  for _, c in ipairs(clients) do n = n + #c:sends(mark, kind, prefix) end
  return n
end

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
local function frozen(pattern) return (pattern:gsub("%-", "%%-")) end

---------------------------------------------------------------- two guilds, each with a released and a new client
-- ALFA: Abe (release, the courier), Mia (working copy, officer), Dora (no addon).
-- BRAV: Bo (working copy, the courier), Ned (release, officer), Cora (no addon).
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

-- HELLO and PEER, before any line has made anyone a peer
local mark = w.tick()
abe:slash("hello Bo Birch"); w.advance(4)
local hello, peer = abe:sends(mark, "WHISPER", "HELLO~")[1], bo:sends(mark, "WHISPER", "PEER~")[1]
check("hello: the release greets with HELLO~tag~realm~guild",
  hello and hello.text == "HELLO~ALFA~CAMWOWUS1Realm1PvE~Alpha Guild", hello and hello.text)
check("hello: the working copy answers the release's HELLO with PEER~tag~realm~guild",
  peer and peer.target == "Abe Alder" and peer.text == "PEER~BRAV~CAMWOWUS2Realm5PvE~Bravo Guild", peer and peer.text)
local p = (bo:db().peers or {})["Abe Alder"]
check("hello: the working copy remembers the release's client as a peer", p and p.tag == "ALFA"
  and p.guild == "Alpha Guild" and p.seen > 0, p and p.tag)
p = (abe:db().peers or {})["Bo Birch"]
check("hello: the release remembers the working copy's client as a peer", p and p.tag == "BRAV"
  and p.guild == "Bravo Guild" and p.seen > 0, p and p.tag)
mark = w.tick()
mia:slash("hello Ned Nash"); w.advance(4)
hello, peer = mia:sends(mark, "WHISPER", "HELLO~")[1], ned:sends(mark, "WHISPER", "PEER~")[1]
check("hello: the working copy greets with HELLO~tag~realm~guild",
  hello and hello.text == "HELLO~ALFA~CAMWOWUS1Realm1PvE~Alpha Guild", hello and hello.text)
check("hello: the release answers the working copy's HELLO with PEER", peer and peer.target == "Mia Moss"
  and peer.text == "PEER~BRAV~CAMWOWUS2Realm5PvE~Bravo Guild", peer and peer.text)
p = (ned:db().peers or {})["Mia Moss"]
check("hello: the release remembers the working copy's client as a peer (from its HELLO)", p and p.tag == "ALFA"
  and p.guild == "Alpha Guild" and p.seen > 0, p and p.tag)
p = (mia:db().peers or {})["Ned Nash"]
check("hello: the working copy remembers the release's client as a peer (from its PEER)", p and p.tag == "BRAV"
  and p.guild == "Bravo Guild" and p.seen > 0, p and p.tag)

-- typed lines: channel text, read by every addon user of the other guild
mark = w.tick()
abe:type("hello from the release"); w.advance(1)
local line = abe:sends(mark, "CHANNEL")[1]
check("typed: the release posts CL4~id~tag~author~class~flags~nick~text into the channel",
  line and line.text:match(frozen(CL4 .. "ALFA~Abe Alder~MAGE~~~hello from the release$")), line and line.text)
check("typed: a line from the release is shown on the working copy, once",
  shownOnce(bo, mark, "[ALFA]", "[Abe Alder]", "hello from the release"))
check("typed: a line from the release is shown on a release client of the other guild, once",
  shownOnce(ned, mark, "[ALFA]", "[Abe Alder]", "hello from the release"))
check("typed: the author's own guild, either version, shows no bridged copy",
  #abe:bridged(mark) == 0 and #mia:bridged(mark) == 0)
w.replay(line)
check("typed: the release's line delivered twice is still shown once on the working copy",
  shownOnce(bo, mark, "hello from the release"))

mark = w.tick()
bo:type("hello from the working copy"); w.advance(1)
line = bo:sends(mark, "CHANNEL")[1]
check("typed: the working copy posts CL4~id~tag~author~class~flags~nick~text into the channel",
  line and line.text:match(frozen(CL4 .. "BRAV~Bo Birch~WARRIOR~~~hello from the working copy$")), line and line.text)
check("typed: a line from the working copy is shown on the release, once",
  shownOnce(abe, mark, "[BRAV]", "[Bo Birch]", "hello from the working copy"))
check("typed: a line from the working copy is shown on a working-copy client of the other guild, once",
  shownOnce(mia, mark, "[BRAV]", "[Bo Birch]", "hello from the working copy"))
w.replay(line)
check("typed: the working copy's line delivered twice is still shown once on the release",
  shownOnce(abe, mark, "hello from the working copy"))

-- nicknames travel to guildmates as NICK, and with the officer rank in the flags and nick fields of a line
mia:slash("nickname Em"); ned:slash("nickname Nn"); w.advance(1)
check("nick: the release stores a NICK~name sent by the working copy", abe:db().nicks["Mia Moss"] == "Em")
check("nick: the working copy stores a NICK~name sent by the release", bo:db().nicks["Ned Nash"] == "Nn")

-- The same line id on both sides. The author's client posts the line; the courier of the same guild runs the
-- other version, sees the line in guild chat and must recognise the channel copy as the same line. If the two
-- computed different ids the courier would carry a second copy and the other guild would see the line twice.
mark = w.tick()
mia:type("an officer on the working copy"); w.advance(5)
line = mia:sends(mark, "CHANNEL")[1]
check("typed: the working copy's officer line carries O<rank> and the nickname",
  line and line.text:match(frozen(CL4 .. "ALFA~Mia Moss~PRIEST~OOfficer~Em~an officer on the working copy$")),
  line and line.text)
check("typed: the release shows the working copy's officer rank and nickname",
  shownOnce(ned, mark, "[ALFA]", "[Mia Moss]", "(Officer Em) an officer on the working copy"))
check("same id: the release's courier does not carry a line the working copy already posted",
  count(everyone, mark, "WHISPER", "WB~") == 0, count(everyone, mark, "WHISPER", "WB~"))
check("same id: the other guild saw that line once on each version",
  #bo:bridged(mark) == 1 and #ned:bridged(mark) == 1, #bo:bridged(mark) .. " and " .. #ned:bridged(mark))

mark = w.tick()
ned:type("an officer on the release"); w.advance(5)
line = ned:sends(mark, "CHANNEL")[1]
check("typed: the release's officer line carries O<rank> and the nickname",
  line and line.text:match(frozen(CL4 .. "BRAV~Ned Nash~PRIEST~OOfficer~Nn~an officer on the release$")),
  line and line.text)
check("typed: the working copy shows the release's officer rank and nickname",
  shownOnce(mia, mark, "[BRAV]", "[Ned Nash]", "(Officer Nn) an officer on the release"))
check("same id: the working copy's courier does not carry a line the release already posted",
  count(everyone, mark, "WHISPER", "WB~") == 0, count(everyone, mark, "WHISPER", "WB~"))
check("same id: the other guild saw that line once on each version",
  #abe:bridged(mark) == 1 and #mia:bridged(mark) == 1, #abe:bridged(mark) .. " and " .. #mia:bridged(mark))

-- carried lines: a member without the addon speaks, the guild's courier whispers WB to the freshest peer of the
-- other guild, who shows it and fans it out to its guild as LINE
bo:type("bo is the freshest peer now"); w.advance(2)
mark = w.tick()
w.say("Alpha Guild", "Dora Dunn", "dora has no addon"); w.advance(5)
local carried = abe:sends(mark, "WHISPER", "WB~")[1]
check("carried: the release's courier whispers WB~<CL4 packet> to one peer", carried
  and count(everyone, mark, "WHISPER", "WB~") == 1 and carried.target == "Bo Birch"
  and carried.text:match(frozen("^WB~CL4~%x+~ALFA~Dora Dunn~WARRIOR~~~dora has no addon$")), carried and carried.text)
check("carried: the working copy accepts the release's WB and shows the line, once",
  shownOnce(bo, mark, "[ALFA]", "[Dora Dunn]", "dora has no addon"))
local fan = bo:sends(mark, "GUILD", "LINE~")
check("carried: the working copy fans it out to its guild as LINE~<the same packet>, once",
  carried and #fan == 1 and fan[1].text == "LINE~" .. carried.text:sub(4), fan[1] and fan[1].text)
check("carried: the release shows the working copy's LINE, once",
  shownOnce(ned, mark, "[ALFA]", "[Dora Dunn]", "dora has no addon"))
if carried then w.replay(carried) end
check("carried: the same WB delivered twice is shown once and fanned out once",
  #bo:bridged(mark) == 1 and #ned:bridged(mark) == 1 and #bo:sends(mark, "GUILD", "LINE~") == 1)

abe:type("abe is the freshest peer now"); w.advance(2)
mark = w.tick()
w.say("Bravo Guild", "Cora Cole", "cora has no addon"); w.advance(5)
carried = bo:sends(mark, "WHISPER", "WB~")[1]
check("carried: the working copy's courier whispers WB~<CL4 packet> to one peer", carried
  and count(everyone, mark, "WHISPER", "WB~") == 1 and carried.target == "Abe Alder"
  and carried.text:match(frozen("^WB~CL4~%x+~BRAV~Cora Cole~MAGE~~~cora has no addon$")), carried and carried.text)
check("carried: the release accepts the working copy's WB and shows the line, once",
  shownOnce(abe, mark, "[BRAV]", "[Cora Cole]", "cora has no addon"))
fan = abe:sends(mark, "GUILD", "LINE~")
check("carried: the release fans it out to its guild as LINE~<the same packet>, once",
  carried and #fan == 1 and fan[1].text == "LINE~" .. carried.text:sub(4), fan[1] and fan[1].text)
check("carried: the working copy shows the release's LINE, once",
  shownOnce(mia, mark, "[BRAV]", "[Cora Cole]", "cora has no addon"))
if carried then w.replay(carried) end
check("carried: the same WB delivered twice is shown once and fanned out once",
  #abe:bridged(mark) == 1 and #mia:bridged(mark) == 1 and #abe:sends(mark, "GUILD", "LINE~") == 1)

-- settings a player of the release would have saved by the end of a session; used further down
abe:slash("nickname Abby"); abe:slash("mute zulu"); abe:slash("officercolor aabbcc"); w.advance(120)
noErrors("two guilds", everyone)
local savedByRelease = copy(abe:db())

---------------------------------------------------------------- gossip: DIR needs three guilds
-- Ann and Ben know each other. Cy greets Ben, Ben answers with PEER and a DIR naming Ann, Cy greets Ann.
local function gossip(reader, writer)
  local g = newWorld()
  for _, name in ipairs({ "Alpha", "Bravo", "Gamma" }) do
    local member = ({ Alpha = "Ann Ash", Bravo = "Ben Bay", Gamma = "Cy Cole" })[name]
    g.guilds[name .. " Guild"] = { info = "CORELink: CompatLink pw1 " .. name:sub(1, 4):upper(),
      roster = roster({ member, MEMBER, "MAGE" }) }
  end
  local ann = join(g, { build = reader, name = "Ann Ash", guild = "Alpha Guild" })
  local ben = join(g, { build = writer, name = "Ben Bay", guild = "Bravo Guild" })
  local cy = join(g, { build = reader, name = "Cy Cole", guild = "Gamma Guild" })
  for _, c in ipairs({ ann, ben, cy }) do c:login() end
  g.advance(40)
  ann:slash("hello Ben Bay"); g.advance(4)
  local from = g.tick()
  cy:slash("hello Ben Bay"); g.advance(8)
  local what = string.format("gossip: DIR written by %s, read by %s", writer.label, reader.label)
  local dir = ben:sends(from, "WHISPER", "DIR~")[1]
  check(what .. ": name@realm@tag@guild", dir and dir.target == "Cy Cole" and all(";" .. dir.text:sub(5) .. ";",
    ";Ann Ash@CAMWOWUS1Realm1PvE@ALPH@Alpha Guild;"), dir and dir.text)
  local learned = (cy:db().peers or {})["Ann Ash"]
  check(what .. ": the reader greets the named player and gains a live peer", learned and learned.tag == "ALPH"
    and learned.guild == "Alpha Guild" and learned.seen > 0, learned and learned.seen)
  noErrors(what, { ann, ben, cy })
end
gossip(NEW, OLD)
gossip(OLD, NEW)

---------------------------------------------------------------- echo: one client per guild claims a line with ECHO~id
-- Mia draws the shorter back-off and claims the line; Abe, the courier, must stand down on her ECHO and must not
-- carry her echoed guild line back out as if a member had typed it.
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
  local from = e.tick()
  b:type("echo me"); e.advance(6)
  local what = string.format("echo: claimed by %s, heard by %s", claimer.label, other.label)
  local claim, posted = m:sends(from, "GUILD", "ECHO~"), m:sends(from, "GUILDCHAT")
  check(what .. ": ECHO~id, then the line as guild chat", #claim == 1 and claim[1].text:match("^ECHO~%x+$")
    and #posted == 1 and posted[1].text == "[BRAV] Bo Birch: echo me", posted[1] and posted[1].text)
  check(what .. ": the other client does not echo the line a second time",
    #a:sends(from, "GUILDCHAT") == 0 and #a:sends(from, "GUILD", "ECHO~") == 0)
  check(what .. ": the echoed guild line is not carried back out", count(three, from, "WHISPER", "WB~") == 0
    and #b:bridged(from) == 0)
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
    #kept == 0 and db.channel == "CompatLink" and db.nicks["Abe Alder"] == "Abby" and db.nicks["Mia Moss"] == "Em"
    and db.muted.zulu == true and db.officerColorHex == "aabbcc", "changed: " .. table.concat(kept, ", "))
  local lost = {}
  for name, saved in pairs(savedByRelease.peers or {}) do
    if not (db.peers and db.peers[name] and db.peers[name].tag == saved.tag) then lost[#lost + 1] = name end
  end
  check("saved variables: the peers the release saved are still known",
    #lost == 0 and db.peers and db.peers["Bo Birch"] ~= nil, "lost: " .. table.concat(lost, ", "))
  local from = u.tick()
  me:type("after the update"); u.advance(1)
  check("saved variables: a line typed after the update reaches the release with the saved nickname",
    shownOnce(far, from, "[ALFA]", "[Abe Alder]", "(Abby) after the update"))
  noErrors("saved variables", { me, far })
end
update()

print(string.format("\n%d compatibility checks against %s, %d failed", checks, baseline, failures))
os.exit(failures == 0 and 0 or 1)
