-- Mock WoW API harness for CORELink. Runs under plain Lua 5.1-5.4, no game needed.
-- Each check prints PASS/FAIL; the script exits non-zero if any check fails.
unpack = unpack or table.unpack
local failures, checks = 0, 0
local function check(name, cond, detail)
  checks = checks + 1
  if cond then print("PASS " .. name) else failures = failures + 1; print("FAIL " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

---------------------------------------------------------------- fake client
local now = 1000
GetTime = function() return now end
date = function(fmt) return os.date(fmt, 1759680000 + now) end  -- fixed wall clock for reproducible logs
local chatLines = {}                  -- what the player would see in chat windows
local function frame(id)
  return { id = id, AddMessage = function(_, m, r, g, b) chatLines[#chatLines + 1] = { frame = id, text = m, r = r, g = g, b = b } end }
end
NUM_CHAT_WINDOWS = 3
for i = 1, 3 do _G["ChatFrame" .. i] = frame(i) end
DEFAULT_CHAT_FRAME = ChatFrame1
GetChatWindowMessages = function(i) if i == 1 then return "SAY", "GUILD" elseif i == 3 then return "GUILD" end end
ChatTypeInfo = { GUILD = { r = .25, g = 1, b = .25 } }
RAID_CLASS_COLORS = { MAGE = { r = .25, g = .78, b = .92 }, WARRIOR = { r = .78, g = .61, b = .43 }, PRIEST = { r = 1, g = 1, b = 1 } }
ChatFrame_RemoveChannel = function() end
local filters = {}
ChatFrame_AddMessageEventFilter = function(ev, fn) filters[ev] = fn end
local joined = {}
GetChannelName = function(n) return joined[n] or 0, joined[n] and n or nil end
local joinCalls = {}
JoinChannelByName = function(n, pw) joinCalls[#joinCalls + 1] = { n, pw }; joined[n] = 6 end
LeaveChannelByName = function(n) joined[n] = nil end
local timers, tickers = {}, {}
C_Timer = {
  After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end,
  NewTicker = function(d, fn) tickers[#tickers + 1] = { every = d, fn = fn } end,
}
local function advance(seconds)
  for _ = 1, seconds do
    now = now + 1
    local due = timers; timers = {}
    for _, t in ipairs(due) do if t.at <= now then t.fn() else timers[#timers + 1] = t end end
    for _, tk in ipairs(tickers) do if now % tk.every == 0 then tk.fn() end end
  end
end
local events = {}
local lastSetText
local function widget()
  return setmetatable({}, { __index = function(_, k)
    if k == "SetText" then return function(_, t) lastSetText = t end end
    if k == "CreateFontString" then return function() return widget() end end
    return function() end
  end })
end
CreateFrame = function(kind, name, parent, template)
  local f = widget()
  rawset(f, "SetScript", function(_, ev, fn) if ev == "OnEvent" then events.handler = fn end end)
  return f
end
UIParent = {}
UnitName = function() return "Shockly" end
UnitGUID = function() return "guid-me" end
GetNormalizedRealmName = function() return "PvE" end
GetRealmName = function() return "Classic Beta PvE" end
UnitClass = function() return "Mage", "MAGE" end
Ambiguate = function(n) return (n:match("^[^-]+")) end
IsInGuild = function() return true end
local myRank = 3
GetGuildInfo = function() return "CORE Forever", "Member", myRank end
local guildInfoText = "Welcome!\nCORELink: CORELink7100 pw1 MAIN 1\n"
local savedTextForRestore = guildInfoText
GetGuildInfoText = function() return guildInfoText end
local roster = {
  { "Shockly-Beta", "Member", 3, "MAGE", "guid-me" },
  { "Bob-Beta", "Officer", 1, "WARRIOR" },
  { "Tanner-Beta", "Guild Master", 0, "PRIEST" },
}
GetNumGuildMembers = function() return #roster end
GetGuildRosterInfo = function(i) local r = roster[i]; if r then return r[1], r[2], r[3], 60, r[4], "Zone", "", "", true, 0, r[4], nil, nil, nil, nil, nil, r[5] end end
GetPlayerInfoByGUID = function(guid) local map = { ["guid-bob"] = "WARRIOR", ["guid-me"] = "MAGE" }; if map[guid] then return "", map[guid] end end
math.randomseed(7)
wipe = function(t) for k in pairs(t) do t[k] = nil end end
local sentAddon = {}
local addonSendResult = 0
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() end,
  SendAddonMessage = function(prefix, text, kind, target) sentAddon[#sentAddon + 1] = { prefix = prefix, text = text, kind = kind, target = target }; return addonSendResult end,
  GuildRoster = function() end,
}
C_AddOns = { GetAddOnMetadata = function(_, key) if key == "Version" then return "0.1.1-test" end end }
SlashCmdList = {}
ColorPickerFrame = nil

---------------------------------------------------------------- load addon
assert(loadfile("CORELink/CORELink.lua"))("CORELink")
local H = events.handler
local function slash(s) SlashCmdList["CORELINK"](s) end
CORELinkDB = { debug = true }            -- left on by a previous session: must be off after login
H(nil, "ADDON_LOADED", "CORELink")
check("debug echo is off at login even if saved on", CORELinkDB.debug == false)
H(nil, "PLAYER_LOGIN")
H(nil, "GUILD_ROSTER_UPDATE")
advance(8)                                   -- ReadGuildInfo (5s) then EnsureChannel (1.5s)

check("config read from Guild Info line", CORELinkDB.channel == "CORELink7100" and CORELinkDB.password == "pw1" and CORELinkDB.tag == "MAIN")
check("joined the link channel with the password", #joinCalls >= 1 and joinCalls[1][1] == "CORELink7100" and joinCalls[1][2] == "pw1")

-- own guild message -> one CL4 addon message on the channel
H(nil, "CHAT_MSG_GUILD", "hello co-guilds", "Shockly-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-me")
advance(2)
local p = sentAddon[#sentAddon]
check("own message relayed as CL4 addon message on channel 6", p and p.kind == "CHANNEL" and p.target == "6" and p.text:match("^CL4~%x+~MAIN~Shockly~MAGE~~~hello co%-guilds$") ~= nil, p and p.text)

-- guild event echo of the same message within the de-dupe window is not sent twice
local before = #sentAddon
H(nil, "CHAT_MSG_GUILD", "hello co-guilds", "Shockly-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-me")
advance(2)
check("duplicate guild message not relayed twice", #sentAddon == before)

-- officer's message (Bob, rank 1) carries the O<rank name> flag and class from GUID
H(nil, "CHAT_MSG_GUILD", "officer speaking", "Bob-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-bob")
advance(3)
p = sentAddon[#sentAddon]
check("guildmate's message relayed with class and officer flag", p and p.text:match("^CL4~%x+~MAIN~Bob~WARRIOR~OOfficer~~officer speaking$") ~= nil, p and p.text)

-- incoming CL4 from another guild shows in every GUILD-enabled window, class coloured, officer labelled
local n0 = #chatLines
H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~deadbeef~ALT~Carol~PRIEST~OCaptain~Cee~hi from alts", "CHANNEL", "Carol", nil, 0, 6, "CORELink7100")
local shown = {}
for i = n0 + 1, #chatLines do shown[#shown + 1] = chatLines[i] end
check("incoming packet displayed in both GUILD windows (1 and 3)", #shown == 2 and shown[1].frame == 1 and shown[2].frame == 3, #shown)
check("display has tag, class colour, officer label and nickname", shown[1] and shown[1].text:find("[ALT]", 1, true) and shown[1].text:find("|cffffffff[Carol]|r", 1, true) and shown[1].text:find("(Captain Cee)", 1, true), shown[1] and shown[1].text)

-- own tag echo is ignored; beacon (empty message) is not displayed but counts as heard
n0 = #chatLines
H(nil, "CHAT_MSG_ADDON", "CORELink", sentAddon[1].text, "CHANNEL", "Shockly", nil, 0, 6, "CORELink7100")
H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~00000001~RAID~~~~~", "CHANNEL", "Zed", nil, 0, 6, "CORELink7100")
check("own-tag echo and presence beacon produce no chat lines", #chatLines == n0)
n0 = #chatLines; slash("guilds")
local guildsOut = table.concat((function() local t = {} for i = n0 + 1, #chatLines do t[#t + 1] = chatLines[i].text end return t end)(), "\n")
check("/cl guilds lists the beaconing guild with our realm", guildsOut:find("RAID", 1, true) ~= nil and guildsOut:find("RAID - PvE (", 1, true) ~= nil, guildsOut)

-- realm coverage (#37): a guildmate on another realm reports what it hears there
n0 = #chatLines
H(nil, "CHAT_MSG_ADDON", "CORELink", "HEARD~PvE2~Trois,RAID", "GUILD", "Tanner-Beta")
local warn = 0
for i = n0 + 1, #chatLines do if chatLines[i].text:find("guild Trois is reaching PvE2 but not PvE: it has no member running CORELink on your realm", 1, true) then warn = warn + 1 end end
check("warns once when a guild reaches a guildmate's realm but not ours", warn == 1, warn)
H(nil, "CHAT_MSG_ADDON", "CORELink", "HEARD~PvE2~Trois,RAID", "GUILD", "Tanner-Beta")
local warn2 = 0
for i = n0 + 1, #chatLines do if chatLines[i].text:find("guild Trois is reaching", 1, true) then warn2 = warn2 + 1 end end
check("the coverage warning is not repeated", warn2 == 1, warn2)
n0 = #chatLines; slash("guilds")
guildsOut = table.concat((function() local t = {} for i = n0 + 1, #chatLines do t[#t + 1] = chatLines[i].text end return t end)(), "\n")
check("/cl guilds shows realms per guild and flags the one not reaching us",
  guildsOut:find("Trois - PvE2 (", 1, true) and guildsOut:find("NOT reaching PvE", 1, true)
  and guildsOut:find("RAID - PvE (", 1, true) and guildsOut:find("PvE2 (", 1, true)
  and guildsOut:find("your realm: PvE | your guild runs CORELink on: PvE, PvE2", 1, true), guildsOut)
lastSetText = nil; slash("report")
check("report has realm and reach fields", (lastSetText or ""):find("| realm PvE |", 1, true) and (lastSetText or ""):find("Trois@PvE2", 1, true) and (lastSetText or ""):find("RAID@PvE+PvE2", 1, true), lastSetText)
-- the housekeeping tick tells our guild what we hear on our realm
local sentMark = #sentAddon
advance(60)
local heardMsg
for i = sentMark + 1, #sentAddon do if sentAddon[i].kind == "GUILD" and sentAddon[i].text:find("^HEARD~PvE~") then heardMsg = sentAddon[i].text end end
check("HEARD report sent to the guild with our realm and heard tags", heardMsg ~= nil and heardMsg:find("RAID", 1, true) ~= nil, heardMsg)

-- legacy CL1 packet still parses
n0 = #chatLines
H(nil, "CHAT_MSG_ADDON", "CORELink", "CL1~0badf00d~OLD~Eve~old client says hi", "CHANNEL", "Eve", nil, 0, 6, "CORELink7100")
check("legacy CL1 packet displayed", #chatLines > n0 and chatLines[#chatLines].text:find("old client says hi", 1, true) ~= nil)

-- packets on some other channel are ignored
n0 = #chatLines
H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~0badf00e~ALT~Carol~PRIEST~~~wrong channel", "CHANNEL", "Carol", nil, 0, 2, "Trade")
check("packet on another channel ignored", #chatLines == n0)

-- nickname sync over the guild addon channel, then shown as a prefix in real guild chat via the filter
H(nil, "CHAT_MSG_ADDON", "CORELink", "NICK~Bobby", "GUILD", "Bob-Beta")
local _, newMsg = filters.CHAT_MSG_GUILD(nil, "CHAT_MSG_GUILD", "yo", "Bob-Beta")
check("nickname + officer rank prefix in guild chat filter", type(newMsg) == "string" and newMsg:find("(Officer Bobby) yo", 1, true) ~= nil, newMsg)

-- link channel packets are hidden from chat windows by the filter
check("raw channel text hidden", filters.CHAT_MSG_CHANNEL(nil, "CHAT_MSG_CHANNEL", "anything", "x", "", "6. CORELink7100") == true)
check("other channel text not hidden", filters.CHAT_MSG_CHANNEL(nil, "CHAT_MSG_CHANNEL", "anything", "x", "", "2. Trade") ~= true)

-- GM-only commands refused for a member, allowed for the GM; per-client commands open to members
n0 = #chatLines; slash("setup Other pw2 X")
check("member cannot run /cl setup", chatLines[#chatLines].text:find("only the guild master", 1, true) ~= nil and CORELinkDB.channel == "CORELink7100")
slash("off"); check("member can run /cl off", CORELinkDB.enabled == false)
slash("on");  check("member can run /cl on", CORELinkDB.enabled == true)
slash("mute alt"); check("member can mute a guild tag", CORELinkDB.muted["alt"] == true)
slash("unmute alt"); check("member can unmute a guild tag", CORELinkDB.muted["alt"] == nil)
n0 = #chatLines; slash("reload")
check("member can run /cl reload", chatLines[#chatLines].text:find("re-read Guild Info", 1, true) ~= nil, chatLines[#chatLines].text)
myRank = 0; slash("officerrank 2"); myRank = 3
check("GM can change officer rank cutoff", CORELinkDB.officerRank == 2)
-- /cl publish always writes all four fields, including the default officer rank 1 (#16)
myRank = 0
slash("officerrank 1"); lastSetText = nil; slash("publish")
check("publish line includes officer rank 1", lastSetText == "CORELink: CORELink7100 pw1 MAIN 1", lastSetText)
slash("officerrank 2"); lastSetText = nil; slash("publish")
check("publish line includes officer rank 2", lastSetText == "CORELink: CORELink7100 pw1 MAIN 2", lastSetText)
local savedTag = CORELinkDB.tag; CORELinkDB.tag = nil; lastSetText = nil; slash("publish")
check("publish line writes - for an empty tag so the rank stays in place", lastSetText == "CORELink: CORELink7100 pw1 - 2", lastSetText)
CORELinkDB.tag = savedTag; slash("officerrank 1"); myRank = 3

-- long message trimmed without breaking UTF-8
local long = string.rep("\195\169", 150)  -- 300 bytes of 'é'
H(nil, "CHAT_MSG_GUILD", long, "Shockly-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-me")
advance(2)
p = sentAddon[#sentAddon]
local body = p and p.text:match("^CL4~%x+~MAIN~Shockly~MAGE~~~(.*)$")
check("long message trimmed on a UTF-8 boundary with ellipsis", body and #p.text <= 255 and body:sub(-3) == "..." and (#body - 3) % 2 == 0, p and #p.text)

-- /cl report: one pasteable line with version, channel, last send result and the debug log
n0 = #chatLines; lastSetText = nil; slash("report")
local report = lastSetText or ""
check("/cl report fills the copy box", report ~= "")
check("report has version, channel id, last send result and log", report:find("CORELink 0.1.1-test", 1, true) and report:find("channel CORELink7100 id 6", 1, true) and report:find("lastSend 0", 1, true) and report:find("log: ", 1, true), report)
check("report is also printed to chat", #chatLines > n0 and chatLines[#chatLines].text == "|cff33ff99CORELink:|r " .. report)
-- an unstamped (dev) checkout reports "dev" instead of the placeholder
local realMeta = C_AddOns.GetAddOnMetadata
C_AddOns.GetAddOnMetadata = function() return "@project-version@" end
lastSetText = nil; slash("report")
check("placeholder version shows as dev", (lastSetText or ""):find("CORELink dev |", 1, true) ~= nil, lastSetText)
C_AddOns.GetAddOnMetadata = realMeta

-- /cl debug on echoes debug lines to chat; off silences them but the report still keeps the log
slash("debug on"); n0 = #chatLines
H(nil, "CHAT_MSG_GUILD", "debug me", "Shockly-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-me")
check("debug on echoes the relay queue line", #chatLines > n0 and chatLines[#chatLines].text:find("debug|r queued relay", 1, true) ~= nil, chatLines[#chatLines] and chatLines[#chatLines].text)
slash("debug off"); n0 = #chatLines
H(nil, "CHAT_MSG_GUILD", "quiet now", "Shockly-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-me")
check("debug off prints nothing for a relayed message", #chatLines == n0)
advance(3)
lastSetText = nil; slash("report")
check("report log keeps entries recorded while debug was off", (lastSetText or ""):find("quiet now", 1, true) == nil and (lastSetText or ""):find("queued relay", 1, true) ~= nil)

-- a failing send result is surfaced to the player once per send and in the report
addonSendResult = 4
H(nil, "CHAT_MSG_GUILD", "will fail", "Shockly-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-me")
n0 = #chatLines; advance(2)
local failLine
for i = n0 + 1, #chatLines do if chatLines[i].text:find("relay send failed (result 4)", 1, true) then failLine = chatLines[i].text end end
check("failed send result 4 is reported to the player", failLine ~= nil)
addonSendResult = 0

-- Login sync: Guild Info text arrives late and the channel list is not ready at +5s; the addon must still
-- configure and join on its own, then print the status line exactly once.
do
  local savedText, savedJoin = guildInfoText, JoinChannelByName
  CORELinkDB = {}; joined = {}; joinCalls = {}
  guildInfoText = ""                                   -- not delivered yet
  local joinReady = false
  JoinChannelByName = function(n, pw) joinCalls[#joinCalls + 1] = { n, pw }; if joinReady then joined[n] = 6 end end
  H(nil, "ADDON_LOADED", "CORELink")
  H(nil, "PLAYER_LOGIN")
  advance(6)                                           -- attempt 1 at +5s: no text yet
  check("login sync: nothing configured while Guild Info is empty", CORELinkDB.channel == nil)
  guildInfoText = savedText                            -- text arrives; channel system still not ready
  advance(10)                                          -- attempt 2 at +15s: reads config, join requested but fails
  check("login sync: config read without /cl reload", CORELinkDB.channel == "CORELink7100")
  joinReady = true
  n0 = #chatLines
  advance(16)                                          -- attempt 3 at +30s joins; attempt 4 at +50s sees joined
  advance(21)
  local status = 0
  for i = n0 + 1, #chatLines do if chatLines[i].text:find("ON | tag: MAIN | channel: CORELink7100 (joined)", 1, true) then status = status + 1 end end
  check("login sync: joined and status line printed once", joined["CORELink7100"] == 6 and status == 1, status)
  n0 = #chatLines; advance(60)
  local extra = 0
  for i = n0 + 1, #chatLines do if chatLines[i].text:find("ON | tag:", 1, true) then extra = extra + 1 end end
  check("login sync: no further status lines after it connected", extra == 0)
  -- CHANNEL_UI_UPDATE re-joins if the channel dropped
  joined["CORELink7100"] = nil; local jc = #joinCalls
  H(nil, "CHANNEL_UI_UPDATE")
  check("CHANNEL_UI_UPDATE triggers a rejoin when not in the channel", #joinCalls == jc + 1)
  JoinChannelByName = savedJoin
end

-- Connection diagnostics (#17 / #22): wrong password is reported once, retries pause, /cl reload clears it
do
  CORELinkDB = {}; joined = {}; joinCalls = {}
  guildInfoText = "CORELink: CORELink7100 wrongpw MAIN 1\n"
  JoinChannelByName = function(n, pw) joinCalls[#joinCalls + 1] = { n, pw } end   -- never succeeds
  H(nil, "ADDON_LOADED", "CORELink")
  H(nil, "PLAYER_LOGIN")
  advance(6)
  local jc = #joinCalls
  n0 = #chatLines
  H(nil, "CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", nil, nil, "CORELink7100", nil, nil, nil, 0, "CORELink7100")
  local notices = 0
  for i = n0 + 1, #chatLines do if chatLines[i].text:find("could not join CORELink7100: wrong channel password", 1, true) then notices = notices + 1 end end
  check("wrong password is reported to the player once", notices == 1)
  advance(130)                                           -- login retries + two housekeeping ticks
  check("join retries pause after a wrong-password notice", #joinCalls == jc, #joinCalls - jc)
  lastSetText = nil; slash("report")
  check("report shows guild info state, join attempts and the last notice",
    (lastSetText or ""):find("guildInfo line ", 1, true) and (lastSetText or ""):find("joinAttempts ", 1, true) and (lastSetText or ""):find("lastNotice WRONG_PASSWORD at ", 1, true) and (lastSetText or ""):find("joinHold WRONG_PASSWORD", 1, true), lastSetText)
  check("debug log uses wall-clock timestamps", (lastSetText or ""):match("log: %d%d:%d%d:%d%d ") ~= nil)
  slash("reload")                                   -- a member may reload (#23)
  check("/cl reload clears the hold and retries the join", #joinCalls == jc + 1, #joinCalls - jc)
end

-- Login gives up with a reason when Guild Info never has a line
do
  CORELinkDB = {}; joined = {}; joinCalls = {}
  guildInfoText = "Welcome, no link configured here\n"
  H(nil, "ADDON_LOADED", "CORELink")
  H(nil, "PLAYER_LOGIN")
  n0 = #chatLines
  advance(90)
  local found = 0
  local late = 0
  for i = n0 + 1, #chatLines do
    if chatLines[i].text:find("not configured: no CORELink: line. Guild leaders:", 1, true) then found = found + 1 end
    if chatLines[i].text:find("not connected after login", 1, true) then late = late + 1 end
  end
  check("unconfigured login reports what Guild Info held, once, with no second message", found == 1 and late == 0, found .. "/" .. late)
  guildInfoText = savedTextForRestore or "CORELink: CORELink7100 pw1 MAIN 1\n"
end

-- Configured but the join never lands: the login sync explains after its last attempt
do
  CORELinkDB = {}; joined = {}; joinCalls = {}
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1\n"
  JoinChannelByName = function(n, pw) joinCalls[#joinCalls + 1] = { n, pw } end   -- never succeeds, no notice
  H(nil, "ADDON_LOADED", "CORELink")
  H(nil, "PLAYER_LOGIN")
  n0 = #chatLines
  advance(90)
  local late = 0
  -- earlier blocks may have left a WRONG_PASSWORD notice in the module state, so accept either reason
  for i = n0 + 1, #chatLines do if chatLines[i].text:find("not connected after login: ", 1, true) and chatLines[i].text:find("CORELink7100", 1, true) then late = late + 1 end end
  check("configured client whose join never lands gets one explanation after the retries", late == 1, late)
  JoinChannelByName = function(n, pw) joinCalls[#joinCalls + 1] = { n, pw }; joined[n] = 6 end
end

-- WoW: Forever reports "First Surname" in chat and the roster while UnitName gives the first name only.
-- The nickname must still apply to our own guild lines, and our own lines must be recognised as ours.
do
  -- self-contained: a configured, joined client regardless of what earlier blocks left behind
  CORELinkDB = {}; joined = {}; joinCalls = {}
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1\n"
  JoinChannelByName = function(n, pw) joinCalls[#joinCalls + 1] = { n, pw }; joined[n] = 6 end
  H(nil, "ADDON_LOADED", "CORELink")
  H(nil, "PLAYER_LOGIN")
  advance(8)
  roster[1][1] = "Shockly Stormgale-Beta"
  now = now + 10; H(nil, "GUILD_ROSTER_UPDATE")            -- roster refresh learns our full name via GUID
  myRank = 0
  slash("nickname Jake")
  check("nickname is stored under the roster/chat name", CORELinkDB.nicks["Shockly Stormgale"] == "Jake" and CORELinkDB.nicks["Shockly"] == nil, CORELinkDB.nicks["Shockly"])
  local _, ownLine = filters.CHAT_MSG_GUILD(nil, "CHAT_MSG_GUILD", "hi all", "Shockly Stormgale-Beta")
  check("own guild line shows rank and nickname with the surname name format", type(ownLine) == "string" and ownLine:find("Jake) hi all", 1, true) ~= nil and ownLine:find("(Member", 1, true) ~= nil, ownLine)
  local sentBefore = #sentAddon
  H(nil, "CHAT_MSG_GUILD", "my own line", "Shockly Stormgale-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-me")
  advance(2)
  local ownSent
  for i = sentBefore + 1, #sentAddon do if sentAddon[i].kind == "CHANNEL" and sentAddon[i].text:find("~Jake~my own line", 1, true) then ownSent = sentAddon[i].text end end
  check("own line is relayed immediately (recognised by GUID) with the nickname", ownSent ~= nil, sentAddon[#sentAddon] and sentAddon[#sentAddon].text)
  myRank = 3; roster[1][1] = "Shockly-Beta"; slash("nickname clear")
end

-- Cross-realm bridge (#38): foreign lines heard on our realm are forwarded to the guild; forwards from
-- guildmates on other realms are re-sent into our realm's channel; nothing loops or duplicates.
do
  CORELinkDB = {}; joined = {}; joinCalls = {}
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1\n"
  JoinChannelByName = function(n, pw) joinCalls[#joinCalls + 1] = { n, pw }; joined[n] = 6 end
  H(nil, "ADDON_LOADED", "CORELink"); H(nil, "PLAYER_LOGIN"); advance(8)
  advance(601)                                   -- let earlier blocks' realm knowledge expire (10 min TTL)
  local function guildSends(from) local t = {} for i = from + 1, #sentAddon do if sentAddon[i].kind == "GUILD" and sentAddon[i].text:find("^BRIDGE~") then t[#t + 1] = sentAddon[i].text end end return t end
  local function channelSends(from) local t = {} for i = from + 1, #sentAddon do if sentAddon[i].kind == "CHANNEL" then t[#t + 1] = sentAddon[i].text end end return t end
  -- no guildmates known elsewhere: a foreign line is NOT forwarded
  local mark = #sentAddon
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~b0000001~ALT~Carol~PRIEST~~~first line", "CHANNEL", "Carol", nil, 0, 6, "CORELink7100")
  advance(3)
  check("bridge: nothing forwarded while no guildmate is known on another realm", #guildSends(mark) == 0, table.concat(guildSends(mark), " / "))
  -- a guildmate on PvE2 reports in; now foreign lines are forwarded once
  H(nil, "CHAT_MSG_ADDON", "CORELink", "HEARD~PvE2~", "GUILD", "Tanner-Beta")
  mark = #sentAddon
  local pkt = "CL4~b0000002~ALT~Carol~PRIEST~~~second line"
  H(nil, "CHAT_MSG_ADDON", "CORELink", pkt, "CHANNEL", "Carol", nil, 0, 6, "CORELink7100")
  H(nil, "CHAT_MSG_ADDON", "CORELink", pkt, "CHANNEL", "Dave", nil, 0, 6, "CORELink7100")   -- a second relayer's copy
  advance(3)
  local fw = guildSends(mark)
  check("bridge: a foreign line heard on our realm is forwarded to the guild exactly once", #fw == 1 and fw[1] == "BRIDGE~" .. pkt, table.concat(fw, " / "))
  -- our own guild's line is not forwarded (our couriers on each realm already relay it)
  mark = #sentAddon
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~b0000003~MAIN~Bob~WARRIOR~~~ours", "CHANNEL", "Bob", nil, 0, 6, "CORELink7100")
  advance(3)
  check("bridge: our own guild's lines are not forwarded", #guildSends(mark) == 0)
  -- a guildmate on the other realm saw a foreign line we have not: we re-send it into our channel, once
  mark = #sentAddon
  local far = "CL4~b0000004~ALT~Erin~MAGE~~~from the other realm"
  H(nil, "CHAT_MSG_ADDON", "CORELink", "BRIDGE~" .. far, "GUILD", "Tanner-Beta")
  H(nil, "CHAT_MSG_ADDON", "CORELink", "BRIDGE~" .. far, "GUILD", "Frank-Beta")   -- a second forwarder
  advance(3)
  local rs = channelSends(mark)
  check("bridge: a forward for a line not on our realm is re-sent into our channel exactly once", #rs == 1 and rs[1] == far, table.concat(rs, " / "))
  -- its echo on our channel shows the line as the original guild's and is not forwarded back
  mark = #sentAddon; n0 = #chatLines
  H(nil, "CHAT_MSG_ADDON", "CORELink", far, "CHANNEL", "Shockly", nil, 0, 6, "CORELink7100")
  advance(3)
  check("bridge: the re-sent line displays as <ALT> and does not bounce back to the guild",
    #chatLines > n0 and chatLines[#chatLines].text:find("[ALT]", 1, true) ~= nil and chatLines[#chatLines].text:find("from the other realm", 1, true) ~= nil and #guildSends(mark) == 0, chatLines[#chatLines] and chatLines[#chatLines].text)
  -- a forward for a line we already heard on our realm is ignored
  mark = #sentAddon
  H(nil, "CHAT_MSG_ADDON", "CORELink", "BRIDGE~" .. pkt, "GUILD", "Tanner-Beta")
  advance(3)
  check("bridge: forwards for lines already on our realm are not re-sent", #channelSends(mark) == 0)
  -- /cl bridge off stops forwarding; report shows it
  slash("bridge off"); mark = #sentAddon
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~b0000005~ALT~Carol~PRIEST~~~while off", "CHANNEL", "Carol", nil, 0, 6, "CORELink7100")
  advance(3)
  lastSetText = nil; slash("report")
  check("bridge: /cl bridge off stops forwarding and the report says so", #guildSends(mark) == 0 and (lastSetText or ""):match("bridge off fwd=%d+ resent=1 ") ~= nil, lastSetText)
  slash("bridge on")
end

print(string.format("\n%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
