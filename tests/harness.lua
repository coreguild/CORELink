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
  { "Bob-Beta", "Officer", 1, "WARRIOR", "guid-bob" },
  { "Tanner-Beta", "Guild Master", 0, "PRIEST" },
  { "Dora-Beta", "Member", 3, "PRIEST", "guid-dora" },   -- never sends addon messages: no addon
}
GetNumGuildMembers = function() return #roster end
GetGuildRosterInfo = function(i) local r = roster[i]; if r then return r[1], r[2], r[3], 60, r[4], "Zone", "", "", true, 0, r[4], nil, nil, nil, nil, nil, r[5] end end
GetPlayerInfoByGUID = function(guid) local map = { ["guid-bob"] = "WARRIOR", ["guid-me"] = "MAGE" }; if map[guid] then return "", map[guid] end end
math.randomseed(7)
wipe = function(t) for k in pairs(t) do t[k] = nil end end
local sentAddon = {}
local addonSendResult = 0
-- chat edit box + secure hooks (for the community mirror)
local hooks = {}
hooksecurefunc = function(a, b, c) if type(a) == "table" then hooks[a] = hooks[a] or {}; hooks[a][b] = c else hooks[a] = b end end
local editAttrs, editText = { chatType = "GUILD" }, ""
ChatFrame1EditBox = { ParseText = function() end, GetAttribute = function(_, k) return editAttrs[k] end, GetText = function() return editText end }
ChatFrame2EditBox = ChatFrame1EditBox; ChatFrame3EditBox = ChatFrame1EditBox
local function typeLine(text, chatType)
  editText = text; editAttrs.chatType = chatType or "GUILD"
  local h = hooks[ChatFrame1EditBox] and hooks[ChatFrame1EditBox].ParseText
  if h then h(ChatFrame1EditBox, 1) end
end
-- Blizzard Communities
local clubMember, clubPosts = true, {}
local clubMessages = {}
local clubSendFails = false
local chatSends = {}
SendChatMessage = function(msg, kind) chatSends[#chatSends + 1] = { text = msg, kind = kind }
  local hk = hooks["SendChatMessage"]; if hk then hk(msg, kind) end end   -- hooksecurefunc runs the hook after the call
issecretvalue = function(v) return type(v) == "table" and rawget(v, "__sealed") == true end
local sealedMT = { __concat = function(a, b)
  if type(a) == "table" then a = a.t end
  if type(b) == "table" then b = b.t end
  return a .. b
end }
local function sealed(text) return setmetatable({ __sealed = true, t = text }, sealedMT) end
local clubs = {
  { clubId = 22703281, clubType = 2, name = "CORE Forever" },
  { clubId = 23112951, clubType = 0, name = "Core Test", shortName = "Guild" },
  { clubId = 23149801, clubType = 1, name = "Core Test 2", shortName = "Guild" },
}
local clubMembers = {}   -- memberId -> record
local clubStreams = { { streamId = 2, name = "Officers" }, { streamId = 1, name = "General" } }
C_Club = {
  GetClubInfo = function(id) if not clubMember then return nil end for _, c in ipairs(clubs) do if c.clubId == id then return c end end end,
  GetSubscribedClubs = function() if not clubMember then return {} end return clubs end,
  GetMemberInfo = function(id, mid) return clubMembers[mid] end,
  GetStreams = function(id) if id == 23112951 or id == 23149801 then return clubStreams end return {} end,
  SendMessage = function(id, stream, text) if clubSendFails then error("Couldn't send message") end clubPosts[#clubPosts + 1] = { club = id, stream = stream, text = text } end,
  FocusStream = function() return true end,
  GetMessageInfo = function(id, stream, mid) return clubMessages[mid] end,
}
local whoResults, whoSent = {}, {}
C_FriendList = {
  SetWhoToUi = function() end,
  SendWho = function(filter) whoSent[#whoSent + 1] = filter end,
  GetNumWhoResults = function() return #whoResults end,
  GetWhoInfo = function(i) return whoResults[i] end,
}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() end,
  SendChatMessage = function() end,
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

-- Community mirror: typed guild lines are posted into the club from the Guild Info "club=" token
do
  CORELinkDB = {}; joined = {}; joinCalls = {}; clubPosts = {}; clubMember = true
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1 club=23112951\n"
  JoinChannelByName = function(n, pw) joinCalls[#joinCalls + 1] = { n, pw }; joined[n] = 6 end
  H(nil, "ADDON_LOADED", "CORELink"); H(nil, "PLAYER_LOGIN"); advance(8)
  check("mirror: club id parsed from the Guild Info line", CORELinkDB.clubId == 23112951, CORELinkDB.clubId)
  lastSetText = nil; slash("report")
  check("mirror: stream is focused as soon as login connects", (lastSetText or ""):find("focused=true", 1, true) ~= nil, lastSetText)
  typeLine("hello everyone")
  check("mirror: a typed guild line is posted to the club's General stream as [TAG] Name: text",
    #clubPosts == 1 and clubPosts[1].club == 23112951 and clubPosts[1].stream == 1 and clubPosts[1].text:match("^%[MAIN%] Shockly[^:]*: hello everyone$") ~= nil, clubPosts[1] and clubPosts[1].text)
  typeLine("/cl report"); typeLine("in say", "SAY")
  check("mirror: slash commands and non-guild chat are not posted", #clubPosts == 1, #clubPosts)
  myRank = 0; lastSetText = nil; slash("publish"); myRank = 3
  check("mirror: /cl publish keeps the club token on the line", lastSetText == "CORELink: CORELink7100 pw1 MAIN 1 club=23112951", lastSetText)
  lastSetText = nil; slash("report")
  check("mirror: report shows club, membership, stream and counts", (lastSetText or ""):find("mirror post=on read=on club=23112951 id=23112951 type=0 member=true stream=1:General channels=1 posted=1 failed=0 shown=0 skipped=0 hidden=0 focused=true hooks=editbox+send", 1, true) ~= nil, lastSetText)
  -- SendChatMessage hook: "/g text" from another chat type, macros and other addons are mirrored too
  local sendHook = hooks["SendChatMessage"]
  check("mirror: SendChatMessage is hooked", type(sendHook) == "function" and type(hooks[C_ChatInfo] and hooks[C_ChatInfo].SendChatMessage) == "function")
  sendHook("from a macro", "GUILD")
  check("mirror: a guild send outside the edit box is posted", #clubPosts == 2 and clubPosts[2].text:match(": from a macro$") ~= nil, clubPosts[2] and clubPosts[2].text)
  sendHook("whisper text", "WHISPER", nil, "Bob"); sendHook("   ", "GUILD")
  check("mirror: non-guild and blank sends are not posted", #clubPosts == 2, #clubPosts)
  typeLine("same keypress"); sendHook("same keypress", "GUILD"); hooks[C_ChatInfo].SendChatMessage("same keypress", "GUILD")
  check("mirror: one typed line that fires every hook is posted once", #clubPosts == 3, #clubPosts)
  advance(2); sendHook("same keypress", "GUILD")
  check("mirror: the same text sent again later is posted again", #clubPosts == 4, #clubPosts)
  -- stream focus: lost on CLUB_ERROR or a failed post, re-done before the next post
  H(nil, "CLUB_ERROR", 3, 7)
  lastSetText = nil; slash("report")
  check("mirror: CLUB_ERROR drops the stream focus", (lastSetText or ""):find("focused=false", 1, true) ~= nil, lastSetText)
  advance(2); sendHook("after error", "GUILD")
  lastSetText = nil; slash("report")
  check("mirror: the stream is focused again before posting", #clubPosts == 5 and (lastSetText or ""):find("focused=true", 1, true) ~= nil, lastSetText)
  clubSendFails = true; advance(2); sendHook("will fail", "GUILD"); clubSendFails = false
  lastSetText = nil; slash("report")
  check("mirror: a failed post is counted and drops the focus", (lastSetText or ""):find("failed=1", 1, true) ~= nil and (lastSetText or ""):find("focused=false", 1, true) ~= nil, lastSetText)
  -- raw community channel lines are hidden while we show them in guild chat
  local cf = filters["CHAT_MSG_COMMUNITIES_CHANNEL"]
  check("mirror hide: community channel filter installed", type(cf) == "function")
  check("mirror hide: our community's raw line is hidden", cf and cf(nil, "CHAT_MSG_COMMUNITIES_CHANNEL", "[ALT] Zag Mathris: boink", "Zag", "", "Community:23112951:1") == true)
  check("mirror hide: other communities and unknown channels are left alone",
    cf and cf(nil, "CHAT_MSG_COMMUNITIES_CHANNEL", "x", "Zag", "", "Community:22703281:1") ~= true and cf(nil, "CHAT_MSG_COMMUNITIES_CHANNEL", "x", "Zag", "", "Community:23112951:9") ~= true)
  slash("mirror hide off")
  check("mirror hide: /cl mirror hide off shows raw lines again", cf and cf(nil, "CHAT_MSG_COMMUNITIES_CHANNEL", "x", "Zag", "", "Community:23112951:1") ~= true)
  slash("mirror hide on"); slash("mirror read off")
  check("mirror hide: raw lines are not hidden while read is off", cf and cf(nil, "CHAT_MSG_COMMUNITIES_CHANNEL", "x", "Zag", "", "Community:23112951:1") ~= true)
  slash("mirror read on")
  lastSetText = nil; slash("report")
  check("mirror hide: report counts hidden raw lines", (lastSetText or ""):find("hidden=1", 1, true) ~= nil, lastSetText)
  -- inbound: a formatted line from another guild in the club shows in guild chat; own guild's and own lines don't
  clubMessages[101] = { messageId = 101, content = "[ALT] Carol Smith (Cee): hi from the community", author = { name = "Carol Smith", isSelf = false } }
  clubMessages[102] = { messageId = 102, content = "[MAIN] Bob Jones: our own guild", author = { name = "Bob Jones", isSelf = false } }
  clubMessages[103] = { messageId = 103, content = "[MAIN] Shockly Stormgale: me", author = { name = "Shockly Stormgale", isSelf = true } }
  clubMessages[104] = { messageId = 104, content = "just chatting in the community", author = { name = "Dana Reed", isSelf = false } }
  n0 = #chatLines
  H(nil, "CLUB_MESSAGE_ADDED", 23112951, 1, 101)
  H(nil, "CLUB_MESSAGE_ADDED", 23112951, 1, 101)      -- duplicate delivery
  H(nil, "CLUB_MESSAGE_ADDED", 23112951, 1, 102)
  H(nil, "CLUB_MESSAGE_ADDED", 23112951, 1, 103)
  H(nil, "CLUB_MESSAGE_ADDED", 23112951, 2, 101)      -- other stream
  local clubShown = {}
  for i = n0 + 1, #chatLines do clubShown[#clubShown + 1] = chatLines[i].text end
  local clubJoined = table.concat(clubShown, "\n")
  check("mirror read: another guild's community line shows once as [ALT] with the nickname",
    clubJoined:find("[ALT]", 1, true) ~= nil and clubJoined:find("[Carol Smith]", 1, true) ~= nil and clubJoined:find("(Cee) hi from the community", 1, true) ~= nil
    and select(2, clubJoined:gsub("hi from the community", "")) == 2, clubJoined)   -- 2 = both GUILD windows, once each
  check("mirror read: own guild's and own lines from the community are not shown", clubJoined:find("our own guild", 1, true) == nil and clubJoined:find("Stormgale: me", 1, true) == nil)
  -- colours: class from the member record when given, else from what relay packets taught us; officer from the relay cache
  GetClassInfo = function(id) if id == 8 then return "Mage", "MAGE" end end
  clubMessages[110] = { messageId = 110, content = "[ALT] Fay Brook: classy", author = { name = "Fay Brook", isSelf = false, classID = 8 } }
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23112951, 1, 110)
  check("mirror read: class colour from the community member record", #chatLines > n0 and chatLines[#chatLines].text:find("|cff40c7eb[Fay Brook]|r", 1, true) ~= nil, chatLines[#chatLines] and chatLines[#chatLines].text)
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~c0000001~ALT~Gus Pine~WARRIOR~OCaptain~~via relay", "CHANNEL", "Gus Pine", nil, 0, 6, "CORELink7100")
  clubMessages[111] = { messageId = 111, content = "[ALT] Gus Pine: now via the community", author = { name = "Gus Pine", isSelf = false } }
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23112951, 1, 111)
  local last = chatLines[#chatLines]
  check("mirror read: class and officer colour learned from an earlier relay packet", #chatLines > n0 and last.text:find("|cffc79c6e[Gus Pine]|r", 1, true) ~= nil and last.text:find("(Captain) now via the community", 1, true) ~= nil and math.floor(last.r * 255 + 0.5) == 0xe8, last.text .. " r=" .. tostring(last.r))
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23112951, 1, 104); advance(2)
  check("mirror read: plain community chat shows under the author's name only", #chatLines > n0 and chatLines[#chatLines].text:find("[Dana Reed]|h: just chatting", 1, true) ~= nil and chatLines[#chatLines].text:find("Core Test", 1, true) == nil, chatLines[#chatLines] and chatLines[#chatLines].text)
  slash("mirror read off"); n0 = #chatLines
  clubMessages[105] = { messageId = 105, content = "[ALT] Carol Smith: while read off", author = { name = "Carol Smith", isSelf = false } }
  H(nil, "CLUB_MESSAGE_ADDED", 23112951, 1, 105)
  check("mirror read: /cl mirror read off stops showing", #chatLines == n0)
  slash("mirror on")
  slash("mirror off"); typeLine("while off")
  check("mirror: /cl mirror off stops posting", #clubPosts == 5, #clubPosts)
  slash("mirror on")
  -- not a member: nothing posted, one reminder after login
  clubMember = false
  CORELinkDB = {}; joined = {}; clubPosts = {}
  H(nil, "ADDON_LOADED", "CORELink"); H(nil, "PLAYER_LOGIN")
  n0 = #chatLines; advance(20)
  local reminders = 0
  for i = n0 + 1, #chatLines do if chatLines[i].text:find("this character is not a member", 1, true) then reminders = reminders + 1 end end
  typeLine("not a member line")
  check("mirror: non-member gets one reminder and nothing is posted", reminders == 1 and #clubPosts == 0, reminders .. "/" .. #clubPosts)
  clubMember = true
end

-- Community named by short name (or full name without spaces) instead of its number
do
  CORELinkDB = {}; joined = {}; clubPosts = {}; clubMember = true
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1 club=coretest\n"
  H(nil, "ADDON_LOADED", "CORELink"); H(nil, "PLAYER_LOGIN"); advance(8)
  check("club name: token kept as written and resolved to the club id", CORELinkDB.club == "coretest" and CORELinkDB.clubId == 23112951, tostring(CORELinkDB.club) .. "/" .. tostring(CORELinkDB.clubId))
  typeLine("by name")
  check("club name: typed line posted to the named community", #clubPosts == 1 and clubPosts[1].club == 23112951, #clubPosts)
  myRank = 0; lastSetText = nil; slash("publish"); myRank = 3
  check("club name: /cl publish keeps the name token", lastSetText == "CORELink: CORELink7100 pw1 MAIN 1 club=coretest", lastSetText)
  lastSetText = nil; slash("report")
  check("club name: report shows token and id", (lastSetText or ""):find("club=coretest id=23112951 type=0 member=true", 1, true) ~= nil, lastSetText)
  clubMessages[120] = { messageId = 120, content = "[ALT] Hal Moss: named club", author = { name = "Hal Moss", isSelf = false } }
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23112951, 1, 120)
  check("club name: inbound lines from the named community are shown", #chatLines > n0 and chatLines[#chatLines].text:find("named club", 1, true) ~= nil)
  -- a saved id from an older version keeps working and is written back as the token
  CORELinkDB = { clubId = 23112951 }; guildInfoText = ""; joined = {}
  H(nil, "ADDON_LOADED", "CORELink")
  check("club name: old saved clubId migrates to the club token", CORELinkDB.club == "23112951")
  -- unknown name: nothing resolves, nothing posts, reminder explains
  CORELinkDB = {}; joined = {}; clubPosts = {}
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1 club=NoSuchClub\n"
  H(nil, "ADDON_LOADED", "CORELink"); H(nil, "PLAYER_LOGIN"); n0 = #chatLines; advance(20)
  typeLine("nowhere")
  local explained = false
  for i = n0 + 1, #chatLines do if chatLines[i].text:find("no community you belong to has that name", 1, true) then explained = true end end
  check("club name: unknown name posts nothing and the reminder says so", CORELinkDB.clubId == nil and #clubPosts == 0 and explained)
  guildInfoText = savedTextForRestore
end

-- World of Warcraft (character) community: short name resolves to it, posts carry only the tag, sealed text
-- is shown under the character's name with class colour, guildmates and own lines are skipped, and a line
-- that also came over the relay is shown once.
do
  CORELinkDB = {}; joined = {}; clubPosts = {}; clubMember = true
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1 club=Guild\n"
  H(nil, "ADDON_LOADED", "CORELink"); H(nil, "PLAYER_LOGIN"); H(nil, "GUILD_ROSTER_UPDATE"); advance(8)
  check("wow club: a short name shared by two communities picks the WoW one", CORELinkDB.clubId == 23149801, CORELinkDB.clubId)
  typeLine("short post")
  check("wow club: posts carry only the tag, no character name", #clubPosts == 1 and clubPosts[1].club == 23149801 and clubPosts[1].text == "[MAIN] short post", clubPosts[1] and clubPosts[1].text)
  slash("nickname Jake"); myRank = 0; advance(2); typeLine("as the gm"); myRank = 3
  check("wow club: an officer's post carries (Rank Nick) in the text", #clubPosts == 2 and clubPosts[2].text == "[MAIN] (Member Jake) as the gm", clubPosts[2] and clubPosts[2].text)
  slash("nickname"); advance(2)
  lastSetText = nil; slash("report")
  check("wow club: report shows type=wow", (lastSetText or ""):find("club=Guild id=23149801 type=wow member=true", 1, true) ~= nil, lastSetText)
  clubMembers[7] = { memberId = 7, name = "Zag Mathris", guid = "guid-zag", classID = 8 }
  clubMembers[8] = { memberId = 8, name = "Bob", guid = "guid-bob", classID = 1 }
  clubMembers[9] = { memberId = 9, name = "Shockly Stormgale", guid = "guid-me", classID = 8 }
  clubMessages[201] = { messageId = 201, content = sealed("[Trois] I'm here!"), author = { memberId = 7 } }
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 201); advance(2)
  local last = chatLines[#chatLines]
  check("wow club: sealed text shows once per guild window under the class-coloured character name",
    #chatLines == n0 + 2 and last.text:find("|cff40c7eb[Zag Mathris]|r|h: [Trois] I'm here!", 1, true) ~= nil and last.text:find("Core Test", 1, true) == nil, last and last.text)
  clubMessages[202] = { messageId = 202, content = sealed("[MAIN] from bob"), author = { memberId = 8 } }
  clubMessages[203] = { messageId = 203, content = sealed("[MAIN] from me"), author = { memberId = 9 } }
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 202); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 203); advance(2)
  check("wow club: guildmates' and own sealed lines are not shown (roster guid, own guid)", #chatLines == n0, #chatLines - n0)
  -- author record lags the message: retried, then shown
  clubMessages[204] = { messageId = 204, content = sealed("[Trois] late author"), author = { memberId = 11 } }
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 204)
  check("wow club: a message without an author yet is not shown immediately", #chatLines == n0)
  clubMembers[11] = { memberId = 11, name = "Cosmo Vale", guid = "guid-cosmo", classID = 1, role = 3 }
  advance(4)
  check("wow club: it is shown once the member record loads", #chatLines == n0 + 2 and chatLines[#chatLines].text:find("[Cosmo Vale]", 1, true) ~= nil, chatLines[#chatLines] and chatLines[#chatLines].text)
  local cl = chatLines[#chatLines]
  check("wow club: a community Moderator never heard on the relay gets the officer colour, text prefix untouched",
    math.floor(cl.r * 255 + 0.5) == 0xe8 and cl.text:find("|h: [Trois] late author", 1, true) ~= nil, cl.text .. " r=" .. tostring(cl.r))
  clubMessages[212] = { messageId = 212, content = sealed("[Trois] (Captain Zaggy) ranked"), author = { memberId = 7 } }
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~00000b01~Trois~Zag Mathris~MAGE~~Zaggy~plain member", "CHANNEL", "Zag", nil, 0, 6, "CORELink7100")
  advance(10); n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 212); advance(2)
  cl = chatLines[#chatLines]
  check("wow club: relay knowledge wins: a non-officer's sealed line is not officer-coloured and the prefix is not doubled",
    #chatLines == n0 + 2 and math.floor(cl.r * 255 + 0.5) ~= 0xe8 and cl.text:find("|h: [Trois] (Captain Zaggy) ranked", 1, true) ~= nil, cl.text .. " r=" .. tostring(cl.r))
  -- relay first, community copy within 5 s: shown once
  advance(10); n0 = #chatLines
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~0000cafe~Trois~Zag Mathris~MAGE~~Zaggy~both ways", "CHANNEL", "Zag", nil, 0, 6, "CORELink7100")
  clubMessages[205] = { messageId = 205, content = sealed("[Trois] both ways"), author = { memberId = 7 } }
  advance(1); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 205); advance(2)
  check("wow club: a line heard on the relay is not shown again from the community", #chatLines == n0 + 2, #chatLines - n0)
  lastSetText = nil; slash("report")
  check("wow club: report counts the skipped copy", (lastSetText or ""):find("skipped=1", 1, true) ~= nil, lastSetText)
  -- community first, relay copy within 5 s: shown once, with the nickname learned from the relay earlier
  advance(10); n0 = #chatLines
  clubMessages[206] = { messageId = 206, content = sealed("[Trois] club first"), author = { memberId = 7 } }
  H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 206); advance(2)
  check("wow club: a sealed line is shown as posted, without a locally added prefix (the poster's client wrote it)", chatLines[#chatLines].text:find("|h: [Trois] club first", 1, true) ~= nil, chatLines[#chatLines].text)
  advance(1)
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~0000beef~Trois~Zag Mathris~MAGE~~Zaggy~club first", "CHANNEL", "Zag", nil, 0, 6, "CORELink7100")
  check("wow club: the relay copy of a line already shown from the community is dropped", #chatLines == n0 + 2, #chatLines - n0)
  -- two quick lines from the same person on both paths are both shown once
  advance(10); n0 = #chatLines
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~00000a01~Trois~Zag Mathris~MAGE~~Zaggy~one", "CHANNEL", "Zag", nil, 0, 6, "CORELink7100")
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~00000a02~Trois~Zag Mathris~MAGE~~Zaggy~two", "CHANNEL", "Zag", nil, 0, 6, "CORELink7100")
  clubMessages[207] = { messageId = 207, content = sealed("[Trois] one"), author = { memberId = 7 } }
  clubMessages[208] = { messageId = 208, content = sealed("[Trois] two"), author = { memberId = 7 } }
  H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 207); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 208); advance(2)
  check("wow club: two quick lines on both paths show exactly twice", #chatLines == n0 + 4, #chatLines - n0)
  -- readable "[TAG] text" lines still honour the tag: own guild skipped, muted skipped
  advance(10); n0 = #chatLines
  clubMessages[209] = { messageId = 209, content = "[MAIN] readable own guild", author = { memberId = 7 } }
  clubMessages[210] = { messageId = 210, content = "[QUIET] readable muted", author = { memberId = 7 } }
  clubMessages[211] = { messageId = 211, content = "[Trois] readable other", author = { memberId = 7 } }
  slash("mute QUIET"); n0 = #chatLines
  H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 209); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 210); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 211)
  check("wow club: readable [TAG] text lines keep tag filtering", #chatLines == n0 + 2 and chatLines[#chatLines].text:find("[Trois] |Hplayer:Zag Mathris|h", 1, true) ~= nil, chatLines[#chatLines] and chatLines[#chatLines].text)
  slash("unmute QUIET")
  guildInfoText = savedTextForRestore
end

-- Per-guild community channels: the channel named after the tag carries the guild's lines, so readers get the
-- tag from the channel and the name from the member record, and show "[TAG] [Name]: (Rank Nick) text".
do
  CORELinkDB = {}; joined = {}; clubPosts = {}; clubMember = true
  clubStreams = { { streamId = 2, name = "Officers" }, { streamId = 1, name = "General" } }
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1 club=Guild\n"
  H(nil, "ADDON_LOADED", "CORELink"); H(nil, "PLAYER_LOGIN"); H(nil, "GUILD_ROSTER_UPDATE"); advance(8)
  typeLine("before the channel")
  check("channels: without a channel for our tag, General gets [TAG] text", #clubPosts == 1 and clubPosts[1].stream == 1 and clubPosts[1].text == "[MAIN] before the channel", clubPosts[1] and clubPosts[1].text)
  clubStreams = { { streamId = 2, name = "Officers" }, { streamId = 1, name = "General" }, { streamId = 3, name = "Main" },
                  { streamId = 4, name = "Trois", subject = "CORELink guild channel" }, { streamId = 5, name = "Deux", subject = "nothing special" },
                  { streamId = 6, name = "Raids", subject = "CORELink", leadersAndModeratorsOnly = true } }
  H(nil, "CLUB_STREAM_ADDED", 23149801, 3); H(nil, "CLUB_STREAM_ADDED", 23149801, 4)
  advance(2); typeLine("in our channel")
  check("channels: a channel named after our tag (any case) takes our posts, without the tag in the text", #clubPosts == 2 and clubPosts[2].stream == 3 and clubPosts[2].text == "in our channel", clubPosts[2] and (clubPosts[2].stream .. " " .. clubPosts[2].text))
  lastSetText = nil; slash("report")
  check("channels: report names the post channel and counts only guild channels plus General", (lastSetText or ""):find("stream=3:Main channels=3", 1, true) ~= nil and (lastSetText or ""):find("focused=true", 1, true) ~= nil, lastSetText)
  clubMessages[405] = { messageId = 405, content = sealed("officer talk"), author = { memberId = 7 } }
  clubMessages[406] = { messageId = 406, content = sealed("deux without a description"), author = { memberId = 7 } }
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23149801, 2, 405); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 5, 406); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 6, 405); advance(2)
  check("channels: channels that are not guild channels (no CORELink description, unknown tag, leaders-only) are ignored", #chatLines == n0, #chatLines - n0)
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~0000d001~Deux~Dee Vale~MAGE~~~heard on the relay", "CHANNEL", "Dee", nil, 0, 6, "CORELink7100")
  H(nil, "CLUB_STREAM_ADDED", 23149801, 5); advance(1)
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23149801, 5, 406); advance(2)
  check("channels: a channel named after a tag heard on the relay becomes a guild channel", #chatLines == n0 + 2 and chatLines[#chatLines].text:find("[Deux] |Hplayer:Zag Mathris|h", 1, true) ~= nil, chatLines[#chatLines] and chatLines[#chatLines].text)
  slash("nickname Jake"); myRank = 0; advance(2); typeLine("ranked"); myRank = 3; slash("nickname"); advance(2)
  check("channels: rank and nickname still travel in the text", #clubPosts == 3 and clubPosts[3].text == "(Member Jake) ranked", clubPosts[3] and clubPosts[3].text)
  clubMembers[7] = { memberId = 7, name = "Zag Mathris", guid = "guid-zag", classID = 8 }
  clubMessages[401] = { messageId = 401, content = sealed("(Captain Zaggy) hello from the channel"), author = { memberId = 7 } }
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23149801, 4, 401); advance(2)
  local cl = chatLines[#chatLines]
  check("channels: a sealed line in another guild's channel shows as [TAG] [Name]: text",
    #chatLines == n0 + 2 and cl.text:find("[Trois] |Hplayer:Zag Mathris|h|cff40c7eb[Zag Mathris]|r|h: (Captain Zaggy) hello from the channel", 1, true) ~= nil, cl and cl.text)
  clubMessages[402] = { messageId = 402, content = sealed("posted in our own channel"), author = { memberId = 7 } }
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23149801, 3, 402); advance(2)
  check("channels: lines in our own guild's channel are not shown", #chatLines == n0, #chatLines - n0)
  slash("mute Trois"); n0 = #chatLines
  clubMessages[403] = { messageId = 403, content = sealed("muted"), author = { memberId = 7 } }
  H(nil, "CLUB_MESSAGE_ADDED", 23149801, 4, 403); advance(2)
  check("channels: a muted tag's channel is not shown", #chatLines == n0, #chatLines - n0)
  slash("unmute Trois")
  clubMessages[404] = { messageId = 404, content = sealed("[Deux] general line"), author = { memberId = 7 } }
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 404); advance(2)
  check("channels: General still shows under the name with the text as posted", #chatLines == n0 + 2 and chatLines[#chatLines].text:find("|Hplayer:Zag Mathris|h|cff40c7eb[Zag Mathris]|r|h: [Deux] general line", 1, true) ~= nil, chatLines[#chatLines] and chatLines[#chatLines].text)
  local cf = filters["CHAT_MSG_COMMUNITIES_CHANNEL"]
  check("channels: raw copies from General and the guild channels are hidden, other channels left alone",
    cf(nil, "CHAT_MSG_COMMUNITIES_CHANNEL", "x", "Zag", "", "Community:23149801:4") == true and cf(nil, "CHAT_MSG_COMMUNITIES_CHANNEL", "x", "Zag", "", "Community:23149801:1") == true
    and cf(nil, "CHAT_MSG_COMMUNITIES_CHANNEL", "x", "Zag", "", "Community:23149801:2") ~= true and cf(nil, "CHAT_MSG_COMMUNITIES_CHANNEL", "x", "Zag", "", "Community:23149801:9") ~= true)
  clubStreams = { { streamId = 2, name = "Officers" }, { streamId = 1, name = "General" } }
  guildInfoText = savedTextForRestore
end

-- Echo: with echo=on in Guild Info, one addon user per guild re-posts other guilds' readable lines as real
-- guild messages for members without the addon; addon users hide them and never relay or carry them.
do
  CORELinkDB = {}; joined = {}; clubPosts = {}; clubMember = true; chatSends = {}
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1 club=Guild echo=on\n"
  H(nil, "ADDON_LOADED", "CORELink"); H(nil, "PLAYER_LOGIN"); H(nil, "GUILD_ROSTER_UPDATE"); advance(8)
  lastSetText = nil; slash("report")
  check("echo: report shows the guild setting and this client's", (lastSetText or ""):find("echo on me=on sent=0 hidden=0", 1, true) ~= nil, lastSetText)
  myRank = 0; lastSetText = nil; slash("publish"); myRank = 3
  check("echo: /cl publish keeps echo=on on the line", lastSetText == "CORELink: CORELink7100 pw1 MAIN 1 club=Guild echo=on", lastSetText)
  local nSent, nPosts = #sentAddon, #clubPosts
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~0000e001~ALT~Carol~PRIEST~OCaptain~Cee~hi echo", "CHANNEL", "Carol", nil, 0, 6, "CORELink7100")
  advance(2)
  check("echo: another guild's relayed line is re-posted into real guild chat with name, rank and nickname",
    #chatSends == 1 and chatSends[1].kind == "GUILD" and chatSends[1].text == "[ALT] Carol (Captain Cee): hi echo", chatSends[1] and chatSends[1].text)
  local claimed = false
  for i = nSent + 1, #sentAddon do if sentAddon[i].kind == "GUILD" and sentAddon[i].text == "ECHO~0000e001" then claimed = true end end
  check("echo: the echo is claimed to guildmates first", claimed)
  check("echo: our own echo send is not mirrored into the community", #clubPosts == nPosts, #clubPosts - nPosts)
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~0000e002~ALT~Carol~PRIEST~~~claimed by tanner", "CHANNEL", "Carol", nil, 0, 6, "CORELink7100")
  H(nil, "CHAT_MSG_ADDON", "CORELink", "ECHO~0000e002", "GUILD", "Tanner-Beta")
  advance(2)
  check("echo: a line a guildmate already claimed is not echoed again", #chatSends == 1, #chatSends)
  local gf = filters["CHAT_MSG_GUILD"]
  check("echo: an echoed line from an addon user is hidden in our guild chat", gf(nil, "CHAT_MSG_GUILD", "[ALT] Carol (Captain Cee): hi echo", "Tanner-Beta") == true)
  check("echo: the same text from a member without the addon is not hidden", gf(nil, "CHAT_MSG_GUILD", "[ALT] Carol: hi echo", "Dora-Beta") ~= true)
  check("echo: our own guild's tag in brackets is not treated as an echo", gf(nil, "CHAT_MSG_GUILD", "[MAIN] Carol: not an echo", "Tanner-Beta") ~= true)
  nSent = #sentAddon
  H(nil, "CHAT_MSG_GUILD", "[ALT] Carol (Captain Cee): hi echo", "Tanner-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-tanner")
  advance(3)
  local relayed = false
  for i = nSent + 1, #sentAddon do if sentAddon[i].kind == "CHANNEL" and sentAddon[i].text:find("hi echo", 1, true) then relayed = true end end
  lastSetText = nil; slash("report")
  check("echo: an echoed line is not relayed and is counted as hidden", not relayed and (lastSetText or ""):find("echo on me=on sent=1 hidden=1", 1, true) ~= nil, lastSetText)
  slash("echo off")
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~0000e003~ALT~Carol~PRIEST~~~after opt out", "CHANNEL", "Carol", nil, 0, 6, "CORELink7100")
  advance(2)
  check("echo: /cl echo off stops this client echoing", #chatSends == 1, #chatSends)
  slash("echo on")
  CORELinkDB = {}; joined = {}; chatSends = {}
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1 club=Guild\n"
  H(nil, "ADDON_LOADED", "CORELink"); H(nil, "PLAYER_LOGIN"); advance(8)
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~0000e004~ALT~Carol~PRIEST~~~no echo", "CHANNEL", "Carol", nil, 0, 6, "CORELink7100")
  advance(2)
  check("echo: without echo=on nothing is re-posted", #chatSends == 0, #chatSends)
  guildInfoText = savedTextForRestore
end


-- Whisper bridge: guilds= names the collective; the courier asks who is online per guild, greets a few over
-- whisper addon messages, remembers who answers, and whispers lines to realms nothing else reaches.
do
  CORELinkDB = {}; joined = {}; clubPosts = {}; clubMember = true; whoSent = {}; whoResults = {}
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1 echo=on guilds=Trois Royaume, Deux\n"
  H(nil, "ADDON_LOADED", "CORELink"); H(nil, "PLAYER_LOGIN"); H(nil, "GUILD_ROSTER_UPDATE"); advance(8)
  check("whisper: guilds= parsed from the end of the line, other tokens intact", CORELinkDB.guilds and #CORELinkDB.guilds == 2 and CORELinkDB.guilds[1] == "Trois Royaume" and CORELinkDB.guilds[2] == "Deux" and CORELinkDB.echo == true, CORELinkDB.guilds and table.concat(CORELinkDB.guilds, "|"))
  myRank = 0; lastSetText = nil; slash("publish"); myRank = 3
  check("whisper: /cl publish writes guilds= last", lastSetText == "CORELink: CORELink7100 pw1 MAIN 1 echo=on guilds=Trois Royaume, Deux", lastSetText)
  lastSetText = nil; slash("report")
  check("whisper: we are the courier when no guildmate runs the addon on our realm", (lastSetText or ""):find("whisper on courier=true guilds=2 peers=0", 1, true) ~= nil, lastSetText)
  -- who round: one silent query per other guild, results give realms and online counts
  advance(60); whoSent = {}                                       -- earlier logins' 45 s rounds have come and gone
  slash("who")
  check("whisper: a who round queries the first other guild of the collective", #whoSent == 1 and whoSent[1] == 'g-"Trois Royaume"', tostring(whoSent[1]))
  whoResults = { { fullName = "Zag Mathris-ClassicBetaPvE2" }, { fullName = "Cosmo Vale-ClassicBetaPvE2" }, { fullName = "Pip Vale" }, { fullName = "Shockly" } }
  H(nil, "WHO_LIST_UPDATE"); advance(4)
  check("whisper: the next guild is queried after the results arrive", #whoSent == 2 and whoSent[2] == 'g-"Deux"', #whoSent .. " " .. tostring(whoSent[2]))
  whoResults = {}; H(nil, "WHO_LIST_UPDATE"); advance(4)
  local hellos = {}
  for _, m in ipairs(sentAddon) do if m.kind == "WHISPER" and m.text:match("^HELLO~MAIN~PvE~CORE Forever$") then hellos[m.target] = true end end
  check("whisper: who results are greeted over whisper addon messages (not ourselves)", hellos["Zag Mathris-ClassicBetaPvE2"] and hellos["Cosmo Vale-ClassicBetaPvE2"] and hellos["Pip Vale"] and not hellos["Shockly"])
  n0 = #chatLines; slash("guilds")
  local collectiveOut = {}
  for i = n0 + 1, #chatLines do collectiveOut[#collectiveOut + 1] = chatLines[i].text end
  check("whisper: /cl guilds lists online members per realm for each guild of the collective", table.concat(collectiveOut, "\n"):find("Trois Royaume - ClassicBetaPvE2: 2 online, PvE: 2 online", 1, true) ~= nil, table.concat(collectiveOut, "\n"))
  H(nil, "CHAT_MSG_ADDON", "CORELink", "HEARD~PvE~MAIN", "GUILD", "Aaron-Beta")
  lastSetText = nil; slash("report")
  check("whisper: the alphabetically first guildmate on our realm is the courier", (lastSetText or ""):find("courier=false", 1, true) ~= nil, lastSetText)
  advance(400)                                                   -- Aaron's report ages out
  lastSetText = nil; slash("report")
  check("whisper: courier role returns when that guildmate goes quiet", (lastSetText or ""):find("courier=true", 1, true) ~= nil, lastSetText)
  -- a player without the addon never answers; one with it answers PEER and becomes a peer
  H(nil, "CHAT_MSG_ADDON", "CORELink", "PEER~Trois~ClassicBetaPvE2~Trois Royaume", "WHISPER", "Zag Mathris-ClassicBetaPvE2")
  lastSetText = nil; slash("report")
  check("whisper: a PEER answer is remembered", (lastSetText or ""):find("peers=1", 1, true) ~= nil and CORELinkDB.peers["Zag Mathris-ClassicBetaPvE2"].tag == "Trois", lastSetText)
  -- someone greets us: we answer PEER and share our directory
  local nSent = #sentAddon
  H(nil, "CHAT_MSG_ADDON", "CORELink", "HELLO~Deux~ClassicBetaPvE2~Deux", "WHISPER", "Dee Vale-ClassicBetaPvE2"); advance(3)
  local gotPeer, gotDir = false, false
  for i = nSent + 1, #sentAddon do
    if sentAddon[i].kind == "WHISPER" and sentAddon[i].target == "Dee Vale-ClassicBetaPvE2" then
      if sentAddon[i].text == "PEER~MAIN~PvE~CORE Forever" then gotPeer = true end
      if sentAddon[i].text:find("^DIR~.*Zag Mathris%-ClassicBetaPvE2@ClassicBetaPvE2@Trois@Trois Royaume") then gotDir = true end
    end
  end
  check("whisper: a HELLO is answered with PEER and a directory of live peers", gotPeer and gotDir)
  -- routing: a line heard natively on our realm goes to one peer per realm that nothing else covers
  nSent = #sentAddon
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~0000f001~ALT~Carol~PRIEST~~~over the water", "CHANNEL", "Carol", nil, 0, 6, "CORELink7100")
  advance(3)
  local wb = {}
  for i = nSent + 1, #sentAddon do if sentAddon[i].kind == "WHISPER" and sentAddon[i].text == "WB~CL4~0000f001~ALT~Carol~PRIEST~~~over the water" then wb[#wb + 1] = sentAddon[i].target end end
  check("whisper: the line is whispered once to the far realm, to its freshest peer", #wb == 1 and (wb[1] == "Zag Mathris-ClassicBetaPvE2" or wb[1] == "Dee Vale-ClassicBetaPvE2"), #wb .. " " .. tostring(wb[1]))
  H(nil, "CHAT_MSG_ADDON", "CORELink", "HEARD~ClassicBetaPvE2~ALT,MAIN", "GUILD", "Tanner-Beta")   -- our guild now has someone there: the bridge covers it
  nSent = #sentAddon
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~0000f002~ALT~Carol~PRIEST~~~bridge covers", "CHANNEL", "Carol", nil, 0, 6, "CORELink7100")
  advance(3)
  local whispered = false
  for i = nSent + 1, #sentAddon do if sentAddon[i].kind == "WHISPER" and sentAddon[i].text:find("bridge covers", 1, true) then whispered = true end end
  check("whisper: realms a guildmate of ours already bridges to are not whispered", not whispered)
  -- inbound: a whispered line is dropped into our realm's channel and shown once
  nSent = #sentAddon; n0 = #chatLines
  H(nil, "CHAT_MSG_ADDON", "CORELink", "WB~CL4~0000f003~Trois~Zag Mathris~MAGE~~Zaggy~from across", "WHISPER", "Zag Mathris-ClassicBetaPvE2")
  advance(4)
  local resent = false
  for i = nSent + 1, #sentAddon do if sentAddon[i].kind == "CHANNEL" and sentAddon[i].text == "CL4~0000f003~Trois~Zag Mathris~MAGE~~Zaggy~from across" then resent = true; H(nil, "CHAT_MSG_ADDON", "CORELink", sentAddon[i].text, "CHANNEL", "Shockly", nil, 0, 6, "CORELink7100") end end
  check("whisper: a whispered line is re-sent into our channel and displayed once", resent and #chatLines == n0 + 2 and chatLines[#chatLines].text:find("[Trois] |Hplayer:Zag Mathris|h", 1, true) ~= nil, tostring(resent) .. " " .. (#chatLines - n0))
  nSent = #sentAddon
  advance(3)
  local bounced = false
  for i = nSent + 1, #sentAddon do if sentAddon[i].kind == "WHISPER" and sentAddon[i].text:find("from across", 1, true) then bounced = true end end
  check("whisper: a line that arrived by whisper is not whispered onward", not bounced)
  lastSetText = nil; slash("report")
  check("whisper: report counts who, hellos, answers, sent and received", (lastSetText or ""):find("hello=3 answered=2 sent=1 recv=1", 1, true) ~= nil, lastSetText)
  -- gossip: an unknown name in a directory gets a hello; the game's "not playing" reply is hidden
  nSent = #sentAddon
  H(nil, "CHAT_MSG_ADDON", "CORELink", "DIR~Rook Hale-ClassicBetaPvE2@ClassicBetaPvE2@Deux@Deux", "WHISPER", "Zag Mathris-ClassicBetaPvE2"); advance(2)
  local greeted = false
  for i = nSent + 1, #sentAddon do if sentAddon[i].kind == "WHISPER" and sentAddon[i].target == "Rook Hale-ClassicBetaPvE2" and sentAddon[i].text:find("^HELLO~") then greeted = true end end
  check("whisper: a name learned from gossip is greeted, not trusted", greeted and CORELinkDB.peers["Rook Hale-ClassicBetaPvE2"].seen == 0)
  local sf = filters["CHAT_MSG_SYSTEM"]
  check("whisper: the game's 'not playing' line for our own hello is hidden", sf(nil, "CHAT_MSG_SYSTEM", "No player named 'Rook Hale' is currently playing.") == true)
  check("whisper: other 'not playing' lines are left alone", sf(nil, "CHAT_MSG_SYSTEM", "No player named 'Someone Else' is currently playing.") ~= true)
  n0 = #chatLines; slash("peers")
  local peersOut = {}
  for i = n0 + 1, #chatLines do peersOut[#peersOut + 1] = chatLines[i].text end
  check("whisper: /cl peers lists peers with guild, realm and state", table.concat(peersOut, "\n"):find("Zag Mathris - Trois on ClassicBetaPvE2 (Trois Royaume) seen", 1, true) ~= nil and table.concat(peersOut, "\n"):find("Rook Hale - Deux on ClassicBetaPvE2 (Deux) not yet answered", 1, true) ~= nil, table.concat(peersOut, "\n"))
  slash("whisper off")
  nSent = #sentAddon
  H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~0000f004~ALT~Carol~PRIEST~~~while off", "CHANNEL", "Carol", nil, 0, 6, "CORELink7100"); advance(3)
  local offSent = false
  for i = nSent + 1, #sentAddon do if sentAddon[i].kind == "WHISPER" and sentAddon[i].text:find("while off", 1, true) then offSent = true end end
  check("whisper: /cl whisper off stops whispering lines", not offSent)
  slash("whisper on")
  guildInfoText = savedTextForRestore
end

print(string.format("\n%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
