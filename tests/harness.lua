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
UnitClass = function() return "Mage", "MAGE" end
Ambiguate = function(n) return (n:match("^[^-]+")) end
IsInGuild = function() return true end
local myRank = 3
GetGuildInfo = function() return "CORE Forever", "Member", myRank end
local guildInfoText = "Welcome!\nCORELink: CORELink7100 pw1 MAIN 1\n"
GetGuildInfoText = function() return guildInfoText end
local roster = {
  { "Shockly-Beta", "Member", 3, "MAGE" },
  { "Bob-Beta", "Officer", 1, "WARRIOR" },
  { "Tanner-Beta", "Guild Master", 0, "PRIEST" },
}
GetNumGuildMembers = function() return #roster end
GetGuildRosterInfo = function(i) local r = roster[i]; if r then return r[1], r[2], r[3], 60, r[4], "Zone", "", "", true, 0, r[4] end end
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
H(nil, "ADDON_LOADED", "CORELink")
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
check("display has tag, class colour, officer label and nickname", shown[1] and shown[1].text:find("[ALT]", 1, true) and shown[1].text:find("|cffffffff[Carol]|r", 1, true) and shown[1].text:find("(Captain - Cee)", 1, true), shown[1] and shown[1].text)

-- own tag echo is ignored; beacon (empty message) is not displayed but counts as heard
n0 = #chatLines
H(nil, "CHAT_MSG_ADDON", "CORELink", sentAddon[1].text, "CHANNEL", "Shockly", nil, 0, 6, "CORELink7100")
H(nil, "CHAT_MSG_ADDON", "CORELink", "CL4~00000001~RAID~~~~~", "CHANNEL", "Zed", nil, 0, 6, "CORELink7100")
check("own-tag echo and presence beacon produce no chat lines", #chatLines == n0)
n0 = #chatLines; slash("guilds")
local guildsOut = table.concat((function() local t = {} for i = n0 + 1, #chatLines do t[#t + 1] = chatLines[i].text end return t end)(), "\n")
check("/cl guilds lists the beaconing guild", guildsOut:find("RAID", 1, true) ~= nil, guildsOut)

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
check("nickname + officer rank prefix in guild chat filter", type(newMsg) == "string" and newMsg:find("(Officer - Bobby) yo", 1, true) ~= nil, newMsg)

-- link channel packets are hidden from chat windows by the filter
check("raw channel text hidden", filters.CHAT_MSG_CHANNEL(nil, "CHAT_MSG_CHANNEL", "anything", "x", "", "6. CORELink7100") == true)
check("other channel text not hidden", filters.CHAT_MSG_CHANNEL(nil, "CHAT_MSG_CHANNEL", "anything", "x", "", "2. Trade") ~= true)

-- GM-only commands refused for a member, allowed for the GM
n0 = #chatLines; slash("setup Other pw2 X")
check("member cannot run /cl setup", chatLines[#chatLines].text:find("only the guild master", 1, true) ~= nil and CORELinkDB.channel == "CORELink7100")
myRank = 0; slash("officerrank 2"); myRank = 3
check("GM can change officer rank cutoff", CORELinkDB.officerRank == 2)

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

print(string.format("\n%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
