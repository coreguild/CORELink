-- Mock WoW API harness for CORELink. Runs under plain Lua 5.1-5.5, no game needed.
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
local registered = {}                 -- events the addon registered with the game
CreateFrame = function(kind, name, parent, template)
  local f = widget()
  rawset(f, "SetScript", function(_, ev, fn) if ev == "OnEvent" then events.handler = fn end end)
  rawset(f, "RegisterEvent", function(_, ev) registered[ev] = true end)
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
-- chat edit box + secure hooks (for the relay and the community mirror)
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
-- every chat send: guild lines (echo), channel text (relay)
local chatSends = {}
SendChatMessage = function(msg, kind, lang, target) chatSends[#chatSends + 1] = { text = msg, kind = kind, target = target }
  local hk = hooks["SendChatMessage"]; if hk then hk(msg, kind) end end   -- hooksecurefunc runs the hook after the call
local function channelSends(from) local t = {} for i = (from or 0) + 1, #chatSends do if chatSends[i].kind == "CHANNEL" then t[#t + 1] = chatSends[i].text end end return t end
local function guildSends(from, prefix) local t = {} for i = (from or 0) + 1, #sentAddon do if sentAddon[i].kind == "GUILD" and sentAddon[i].text:find(prefix, 1, true) == 1 then t[#t + 1] = sentAddon[i].text end end return t end
local function whisperSends(from, prefix) local t = {} for i = (from or 0) + 1, #sentAddon do if sentAddon[i].kind == "WHISPER" and sentAddon[i].text:find(prefix, 1, true) == 1 then t[#t + 1] = sentAddon[i] end end return t end
-- the same hash the addon uses for a line id
local function hash(s) local h = 5381 for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end return string.format("%08x", h) end
-- Blizzard Communities
local clubMember, clubPosts = true, {}
local clubMessages = {}
local clubSendFails = false
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
  SendAddonMessage = function(prefix, text, kind, target) sentAddon[#sentAddon + 1] = { prefix = prefix, text = text, kind = kind, target = target }; return 0 end,
  GuildRoster = function() end,
}
C_AddOns = { GetAddOnMetadata = function(_, key) if key == "Version" then return "0.2.0-test" end end }
SlashCmdList = {}
ColorPickerFrame = nil

---------------------------------------------------------------- load addon
-- The files in TOC order, each given the same private table, exactly as the game does it.
local NS = {}
for line in io.lines("CORELink/CORELink.toc") do
  local file = line:match("^([%w_]+%.lua)%s*$")
  if file then assert(loadfile("CORELink/" .. file))("CORELink", NS) end
end
-- Fire a game event the way the game would: only if the addon registered it.
local function H(_, event, ...)
  assert(registered[event], "the addon never registered " .. tostring(event) .. " with the game")
  return events.handler(nil, event, ...)
end
local nRegistered = 0
for _ in pairs(registered) do nRegistered = nRegistered + 1 end
check("events: every handler is registered with the game", nRegistered == 15, nRegistered)
local function slash(s) SlashCmdList["CORELINK"](s) end
-- text on the link channel, as the game delivers it
local function channelLine(text, author, channel)
  local base = channel and channel:match("^%d+%. (.*)$") or "CORELink7100"
  H(nil, "CHAT_MSG_CHANNEL", text, author, "", channel or "6. CORELink7100", author, "", 0, 6, base)
end
local function lines(fn) local start = #chatLines; fn(); local out = {}; for i = start + 1, #chatLines do out[#out + 1] = chatLines[i].text end; return table.concat(out, "\n") end
local function last() return chatLines[#chatLines] and chatLines[#chatLines].text or "" end
local function report() lastSetText = nil; slash("report"); return lastSetText or "" end

---------------------------------------------------------------- login
CORELinkDB = { debug = true,             -- left on by a previous session: must be off after login
  peers = { ["Old Friend"] = { tag = "OLD", realm = "CAMWOWUS2Realm3PvE", guild = "Old Guild", seen = 0 } } }
H(nil, "ADDON_LOADED", "CORELink")
check("debug echo is off at login even if saved on", CORELinkDB.debug == false)
H(nil, "PLAYER_LOGIN")
H(nil, "GUILD_ROSTER_UPDATE")
advance(8)                                   -- ReadGuildInfo (5s) then EnsureChannel (1.5s)
check("config read from Guild Info line", CORELinkDB.channel == "CORELink7100" and CORELinkDB.password == "pw1" and CORELinkDB.tag == "MAIN")
check("joined the link channel with the password", #joinCalls >= 1 and joinCalls[1][1] == "CORELink7100" and joinCalls[1][2] == "pw1")
local out = lines(function() slash("peers") end)
check("peers saved by a previous session are listed after login", out:find("Old Friend - OLD (Old Guild) not yet answered", 1, true) ~= nil, out)
check("a saved peer that never answered is not counted as live, even minutes after the game started", report():find("peers=0", 1, true) ~= nil)
advance(20)
check("presence is announced to the guild shortly after login", #guildSends(0, "PRESENT~0.2.0-test") == 1, #guildSends(0, "PRESENT~"))

---------------------------------------------------------------- relay: our own typed line goes into the channel as text
local mark = #chatSends
typeLine("hello co-guilds")
local cs = channelSends(mark)
check("own typed line is posted into the link channel as a CL4 packet, from the keypress", #cs == 1 and cs[1]:match("^CL4~%x+~MAIN~Shockly~MAGE~~~hello co%-guilds$") ~= nil, cs[1])
check("the channel send names the channel id", chatSends[#chatSends].target == 6, tostring(chatSends[#chatSends].target))
local ownPacket = cs[1]
typeLine("hello co-guilds")
check("the second hook firing for the same line does not post it twice", #channelSends(mark) == 1)
mark = #chatSends; local amark = #sentAddon
H(nil, "CHAT_MSG_GUILD", "hello co-guilds", "Shockly-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-me")
advance(3)
check("our own line arriving as a guild event is not relayed again or carried", #channelSends(mark) == 0 and #whisperSends(amark, "WB~") == 0)
check("report counts the typed relay", report():find("relay typed=1 carried=0", 1, true) ~= nil, report())

-- incoming: another guild's line on the channel shows in every GUILD-enabled window, class coloured, officer labelled
local n0 = #chatLines
channelLine("CL4~deadbeef~ALT~Carol~PRIEST~OCaptain~Cee~hi from alts", "Carol")
local shown = {}
for i = n0 + 1, #chatLines do shown[#shown + 1] = chatLines[i] end
check("incoming packet displayed in both GUILD windows (1 and 3)", #shown == 2 and shown[1].frame == 1 and shown[2].frame == 3, #shown)
check("display has tag, class colour, officer label and nickname", shown[1] and shown[1].text:find("[ALT]", 1, true) and shown[1].text:find("|cffffffff[Carol]|r", 1, true) and shown[1].text:find("(Captain Cee)", 1, true), shown[1] and shown[1].text)
channelLine("CL4~deadbeef~ALT~Carol~PRIEST~OCaptain~Cee~hi from alts", "Carol")
check("the same packet delivered twice is shown once", #chatLines == n0 + 2, #chatLines - n0)
out = lines(function() slash("peers") end)
check("the author of another guild's line becomes a live peer of that guild", out:find("Carol - ALT (?) seen 0s ago", 1, true) ~= nil, out)
n0 = #chatLines
channelLine(ownPacket, "Shockly")
check("our own guild's packet on the channel produces no chat line", #chatLines == n0)
channelLine("CL4~0badf00e~ALT~Carol~PRIEST~~~wrong channel", "Carol", "2. Trade")
check("packet on another channel ignored", #chatLines == n0)
channelLine("just some chat", "Someone")
check("plain text on the link channel is ignored", #chatLines == n0)
-- hostile packet on the channel (#24): | and control characters in tag, author, class and rank never reach the chat frame
n0 = #chatLines
channelLine("CL4~0000ba01~A|LT~Eve|cffff0000~PRI|EST~OCap\ntain~~hostile one", "Carol")
check("channel: a packet with | in tag, author and class is displayed with them cleaned, the line intact",
  #chatLines == n0 + 2 and last() == "[ALT] |Hplayer:Evecffff0000|h|cffffffff[Evecffff0000]|r|h: (Captain) hostile one", last())
out = lines(function() slash("guilds") end)
check("channel: the cleaned tag is the guild already known, not a new one", out:find("A|LT", 1, true) == nil and select(2, out:gsub("ALT %- heard", "")) == 1, out)
n0 = #chatLines; channelLine("CL4~0000ba04~|~Eve~PRIEST~~~no tag left", "Carol"); channelLine("CL4~0000ba05~ALT~|\1~PRIEST~~~no author left", "Carol")
check("channel: a packet whose tag or author is nothing but | and control characters is dropped", #chatLines == n0, #chatLines - n0)
channelLine("CL4~0000ba0a~ALT~Zo\195\169 Brul\195\169~PRIEST~OCapitaine~Z\195\169~accents stay", "Carol")
check("channel: a well-formed packet with accented letters in name, rank and nickname is displayed exactly as before",
  last() == "[ALT] |Hplayer:Zo\195\169 Brul\195\169|h|cffffffff[Zo\195\169 Brul\195\169]|r|h: (Capitaine Z\195\169) accents stay", last())
n0 = #chatLines
channelLine("CL4~0000ba0b~MA IN~Eve~PRIEST~~~own tag with a space", "Tanner"); channelLine("CL4~0000ba0c~MAIN\127~Eve~PRIEST~~~own tag with a delete", "Tanner")
check("channel: a space or control character in the tag does not turn our own guild's tag into another guild's", #chatLines == n0 and lines(function() slash("guilds") end):find("MA IN", 1, true) == nil, #chatLines - n0)
n0 = #chatLines
channelLine("CL4~0000ba0d~ALT~Eve~PRIEST~~~hi\n[Guild] [Boss]: forged\rline", "Carol")
check("channel: a line break in the text does not draw a second, forged line", #chatLines == n0 + 2 and last() == "[ALT] |Hplayer:Eve|h|cffffffff[Eve]|r|h: hi[Guild] [Boss]: forgedline", last())
channelLine("CL4~0000ba0e~ALT~\195\137lodie \208\144\208\159~PRIEST~~~\195\137t\195\169 |cffff0000red|r |Hitem:1|h[Thing]|h", "Carol")
check("channel: UTF-8 bytes in the 0x80-0x9F range, colours and links in a well-formed packet are displayed exactly as before",
  last() == "[ALT] |Hplayer:\195\137lodie \208\144\208\159|h|cffffffff[\195\137lodie \208\144\208\159]|r|h: \195\137t\195\169 |cffff0000red|r |Hitem:1|h[Thing]|h", last())
out = lines(function() slash("guilds") end)
check("/cl guilds lists the guilds heard, their peers, and the courier", out:find("ALT - heard", 1, true) and out:find("1 peer(s) to whisper to", 1, true) and out:find("MAIN (your guild) - heard", 1, true) and out:find("courier for your guild: you", 1, true), out)

-- the courier carries a line from a guildmate without the addon: whispered to one peer per other guild
amark = #sentAddon
H(nil, "CHAT_MSG_GUILD", "officer speaking", "Bob-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-bob")
advance(3)
local wb = whisperSends(amark, "WB~")
check("a guildmate's line is carried by whisper to the other guild's peer, with class and officer flag", #wb == 1 and wb[1].target == "Carol" and wb[1].text:match("^WB~CL4~%x+~MAIN~Bob~WARRIOR~OOfficer~~officer speaking$") ~= nil, wb[1] and (wb[1].target .. " " .. wb[1].text))
check("report counts the carried line", report():find("relay typed=1 carried=1", 1, true) ~= nil and report():find("sent=1", 1, true) ~= nil, report())
amark = #sentAddon
H(nil, "CHAT_MSG_GUILD", "officer speaking", "Bob-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-bob")
advance(3)
check("the same guild line within the dedupe window is not carried twice", #whisperSends(amark, "WB~") == 0)
-- a guildmate who runs the addon but whose copy never shows up (addon switched off) is carried all the same
-- (Tanner sorts after Shockly, so we stay the courier)
H(nil, "CHAT_MSG_ADDON", "CORELink", "PRESENT~0.2.0-test", "GUILD", "Tanner-Beta")
amark = #sentAddon
H(nil, "CHAT_MSG_GUILD", "tanner switched it off", "Tanner-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-tanner")
advance(1)
check("the courier waits at least a second for the author's own copy", #whisperSends(amark, "WB~") == 0)
advance(3)
check("a line from an addon user whose own copy never arrives is carried after the wait", #whisperSends(amark, "WB~") == 1)
-- a copy arrives on the channel during the back-off: the courier stands down
amark = #sentAddon
H(nil, "CHAT_MSG_GUILD", "dora types", "Dora-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-dora")
channelLine("CL4~" .. hash("MAINDoradora types") .. "~MAIN~Dora~PRIEST~~~dora types", "Dora")
advance(3)
check("a line that shows up on the channel during the back-off is not carried", #whisperSends(amark, "WB~") == 0)
-- the courier is the alphabetically first guildmate running the addon
H(nil, "CHAT_MSG_ADDON", "CORELink", "PRESENT~0.2.0-test", "GUILD", "Aaron-Beta")
check("a guildmate earlier in the alphabet becomes the courier", report():find("courier=Aaron", 1, true) ~= nil, report())
amark = #sentAddon
H(nil, "CHAT_MSG_GUILD", "not ours to carry", "Dora-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-dora")
advance(3)
check("a client that is not the courier carries nothing", #whisperSends(amark, "WB~") == 0)
advance(400)
check("the courier role returns when that guildmate goes quiet", report():find("courier=me", 1, true) ~= nil, report())

-- inbound carried lines: shown once, fanned out to our guild once, never carried onward
amark = #sentAddon; n0 = #chatLines
H(nil, "CHAT_MSG_ADDON", "CORELink", "WB~CL4~0000f003~Trois~Zag Mathris~MAGE~~Zaggy~from a stranger", "WHISPER", "Zag Mathris")
advance(3)
check("a carried line from an unknown sender for a guild never heard is dropped", #chatLines == n0 and #guildSends(amark, "LINE~") == 0, #chatLines - n0)
channelLine("CL4~0000f002~Trois~Pip Vale~MAGE~~~trois is on the link", "Pip Vale")
n0 = #chatLines; amark = #sentAddon
H(nil, "CHAT_MSG_ADDON", "CORELink", "WB~CL4~0000f003~Trois~Zag Mathris~MAGE~~Zaggy~from across", "WHISPER", "Zag Mathris")
H(nil, "CHAT_MSG_ADDON", "CORELink", "WB~CL4~0000f003~Trois~Zag Mathris~MAGE~~Zaggy~from across", "WHISPER", "Cosmo Vale")   -- a second courier's copy
advance(3)
local fan = guildSends(amark, "LINE~")
check("a carried line for a guild we have heard is shown once and fanned out to our guild once", #chatLines == n0 + 2 and last():find("[Trois] |Hplayer:Zag Mathris|h", 1, true) ~= nil and #fan == 1 and fan[1] == "LINE~CL4~0000f003~Trois~Zag Mathris~MAGE~~Zaggy~from across", (#chatLines - n0) .. " " .. #fan)
check("a carried line is never whispered onward", #whisperSends(amark, "WB~") == 0)
check("report counts both received copies and the one fan-out", report():find("recv=2 fanned=1", 1, true) ~= nil, report())
n0 = #chatLines; amark = #sentAddon
H(nil, "CHAT_MSG_ADDON", "CORELink", "LINE~CL4~0000f004~Deux~Dee Vale~PRIEST~~~fanned by tanner", "GUILD", "Tanner-Beta")
advance(3)
check("a line fanned out by a guildmate is shown and goes no further", #chatLines == n0 + 2 and last():find("[Deux]", 1, true) ~= nil and #guildSends(amark, "LINE~") == 0 and #whisperSends(amark, "WB~") == 0, #chatLines - n0)
H(nil, "CHAT_MSG_ADDON", "CORELink", "LINE~CL4~0000f003~Trois~Zag Mathris~MAGE~~Zaggy~from across", "GUILD", "Tanner-Beta")
check("our own fan-out coming back from the guild channel is not shown again", #chatLines == n0 + 2)
-- hostile packets by whisper and by guild fan-out (#24)
n0 = #chatLines; amark = #sentAddon
H(nil, "CHAT_MSG_ADDON", "CORELink", "WB~CL4~0000ba02~Tr|ois~Zed|Hitem:1|h~MA|GE~~~hostile two", "WHISPER", "Zag Mathris")
advance(3)
check("whisper: a carried packet with | in tag, author and class is displayed with them cleaned, the line intact",
  #chatLines == n0 + 2 and last() == "[Trois] |Hplayer:ZedHitem:1h|h|cff40c7eb[ZedHitem:1h]|r|h: hostile two", last())
check("whisper: the packet is fanned out as it came, the wire format untouched", guildSends(amark, "LINE~")[1] == "LINE~CL4~0000ba02~Tr|ois~Zed|Hitem:1|h~MA|GE~~~hostile two", guildSends(amark, "LINE~")[1])
n0 = #chatLines
H(nil, "CHAT_MSG_ADDON", "CORELink", "LINE~CL4~0000ba03~De|ux~Dee|r Vale~PRI\1EST~O|cff00ff00Lead~|cff00ff00Dee~hostile three", "GUILD", "Tanner-Beta")
check("guild fan-out: a packet with | in tag, author, class, rank and nickname is displayed with them cleaned",
  #chatLines == n0 + 2 and last() == "[Deux] |Hplayer:Deer Vale|h|cffffffff[Deer Vale]|r|h: (cff00ff00Lead cff00ff00Dee) hostile three", last())
-- secret values in the addon-message event (#26 item 1): prefix and chat type go through NS.Plain before any compare
do
  local realPlain, asked = NS.Plain, {}
  NS.Plain = function(v) asked[v or false] = true; return realPlain(v) end
  local sp, st = sealed("CORELink"), sealed("GUILD")
  n0 = #chatLines
  local okSecret = pcall(H, nil, "CHAT_MSG_ADDON", sp, "LINE~CL4~0000ba06~Deux~Dee Vale~PRIEST~~~sealed prefix", "GUILD", "Tanner-Beta")
  okSecret = pcall(H, nil, "CHAT_MSG_ADDON", "CORELink", "LINE~CL4~0000ba07~Deux~Dee Vale~PRIEST~~~sealed type", st, "Tanner-Beta") and okSecret
  NS.Plain = realPlain
  check("an addon message whose prefix or chat type is a secret value is unwrapped before it is compared, and ignored", okSecret and asked[sp] == true and asked[st] == true and #chatLines == n0, #chatLines - n0)
end
-- events before the saved variables are loaded (#26 item 2): the chat handlers do nothing instead of erroring
do
  local savedDb = NS.db; NS.db = nil
  local ok1, e1 = pcall(H, nil, "CHAT_MSG_GUILD", "too early", "Dora-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-dora")
  local ok2, e2 = pcall(H, nil, "CHAT_MSG_ADDON", "CORELink", "NICK~Early", "GUILD", "Bob-Beta")
  local ok3, e3 = pcall(H, nil, "CHAT_MSG_ADDON", "CORELink", "HELLO~ALT~PvE~Alt Guild", "WHISPER", "Carol")
  local ok4, e4 = pcall(H, nil, "CHAT_MSG_ADDON", "CORELink", "LINE~CL4~0000ba08~Deux~Dee Vale~PRIEST~~~too early", "GUILD", "Tanner-Beta")
  NS.db = savedDb
  check("a guild line before the settings are loaded is ignored without an error", ok1, e1)
  check("guild and whisper addon messages before the settings are loaded are ignored without an error", ok2 and ok3 and ok4, tostring(e2) .. " / " .. tostring(e3) .. " / " .. tostring(e4))
end

-- the server refuses our channel text: said once, counted
n0 = #chatLines
typeLine("refused line")
H(nil, "CHAT_MSG_CHANNEL_NOTICE", "NOT_ALLOWED_IN_CHANNEL", nil, nil, "CORELink7100", nil, nil, nil, 6, "CORELink7100")
local refusals = 0
for i = n0 + 1, #chatLines do if chatLines[i].text:find("the server refused your line on CORELink7100", 1, true) then refusals = refusals + 1 end end
check("a refusal right after our send is reported to the player and the report says refused", refusals == 1 and report():find("lastSend refused", 1, true) ~= nil, refusals)
n0 = #chatLines; advance(2); typeLine("refused again")
H(nil, "CHAT_MSG_CHANNEL_NOTICE", "NOT_ALLOWED_IN_CHANNEL", nil, nil, "CORELink7100", nil, nil, nil, 6, "CORELink7100")
refusals = 0
for i = n0 + 1, #chatLines do if chatLines[i].text:find("the server refused", 1, true) then refusals = refusals + 1 end end
check("a second refusal within ten minutes is not repeated to the player", refusals == 0)
H(nil, "CHAT_MSG_CHANNEL_NOTICE", "NOT_ALLOWED_IN_CHANNEL", nil, nil, "CORELink7100", nil, nil, nil, 6, "CORELink7100")
advance(30); typeLine("fine again")
check("a send with no refusal reads ok in the report", report():find("lastSend ok", 1, true) ~= nil, report())

-- nickname sync over the guild addon channel, then shown as a prefix in real guild chat via the filter
H(nil, "CHAT_MSG_ADDON", "CORELink", "NICK~Bobby", "GUILD", "Bob-Beta")
local _, newMsg = filters.CHAT_MSG_GUILD(nil, "CHAT_MSG_GUILD", "yo", "Bob-Beta")
check("nickname + officer rank prefix in guild chat filter", type(newMsg) == "string" and newMsg:find("(Officer Bobby) yo", 1, true) ~= nil, newMsg)
-- nicknames of members who left are forgotten on a complete roster read, and only then (#26 item 5)
do
  H(nil, "CHAT_MSG_ADDON", "CORELink", "NICK~Lefty", "GUILD", "Gone-Beta")      -- not on the roster: left the guild
  CORELinkDB.nicks["Shock"] = "Shocks"                                          -- ours, saved under the short name
  local realNum, realInfo, realUnitName, realGetTime = GetNumGuildMembers, GetGuildRosterInfo, UnitName, GetTime
  UnitName = function() return "Shock" end
  GetNumGuildMembers = function() return 0 end
  local refreshed = NS.RefreshRoster()
  check("an empty roster read forgets no nickname", refreshed == false and CORELinkDB.nicks["Gone"] == "Lefty" and CORELinkDB.nicks["Bob"] == "Bobby")
  GetNumGuildMembers = realNum
  GetGuildRosterInfo = function(i) if i == 1 then return realInfo(i) end end   -- the roster stops after one of four
  NS.RefreshRoster()
  check("a roster read that stops short forgets no nickname", CORELinkDB.nicks["Gone"] == "Lefty" and CORELinkDB.nicks["Bob"] == "Bobby", tostring(CORELinkDB.nicks["Bob"]))
  GetGuildRosterInfo = realInfo
  NS.RefreshRoster()
  check("a complete roster read does not forget a missing member's nickname at once (the roster may lag)", CORELinkDB.nicks["Gone"] == "Lefty", CORELinkDB.nicks["Gone"])
  GetTime = function() return now + 601 end
  GetGuildRosterInfo = function(i) if i == 1 then return realInfo(i) end end
  NS.RefreshRoster()
  check("a roster read that stops short forgets no nickname, however long the member has been missing", CORELinkDB.nicks["Gone"] == "Lefty" and CORELinkDB.nicks["Bob"] == "Bobby")
  GetGuildRosterInfo = realInfo
  NS.RefreshRoster()
  check("a member still missing from a complete roster read ten minutes later has their nickname forgotten", CORELinkDB.nicks["Gone"] == nil, CORELinkDB.nicks["Gone"])
  check("guildmates' nicknames and our own under the short name are kept", CORELinkDB.nicks["Bob"] == "Bobby" and CORELinkDB.nicks["Shock"] == "Shocks", tostring(CORELinkDB.nicks["Shock"]))
  GetTime = realGetTime; UnitName = realUnitName
  CORELinkDB.nicks["Shock"] = nil
end

-- link channel text is hidden from chat windows by the filter
check("raw channel text hidden", filters.CHAT_MSG_CHANNEL(nil, "CHAT_MSG_CHANNEL", "anything", "x", "", "6. CORELink7100") == true)
check("other channel text not hidden", filters.CHAT_MSG_CHANNEL(nil, "CHAT_MSG_CHANNEL", "anything", "x", "", "2. Trade") ~= true)

-- GM-only commands refused for a member, allowed for the GM; per-client commands open to members
slash("setup Other pw2 X")
check("member cannot run /cl setup", last():find("only the guild master", 1, true) ~= nil and CORELinkDB.channel == "CORELink7100")
slash("off"); check("member can run /cl off", CORELinkDB.enabled == false)
slash("on");  check("member can run /cl on", CORELinkDB.enabled == true)
slash("mute alt"); check("member can mute a guild tag", CORELinkDB.muted["alt"] == true)
n0 = #chatLines; channelLine("CL4~0badf00f~ALT~Carol~PRIEST~~~muted line", "Carol")
check("a muted guild's line is not shown", #chatLines == n0)
slash("unmute alt"); check("member can unmute a guild tag", CORELinkDB.muted["alt"] == nil)
slash("reload")
check("member can run /cl reload", last():find("re-read Guild Info", 1, true) ~= nil, last())
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

-- long message truncated without breaking UTF-8
local long = string.rep("\195\169", 150)  -- 300 bytes of 'é'
mark = #chatSends; advance(11); typeLine(long)
local p = channelSends(mark)[1]
local body = p and p:match("^CL4~%x+~MAIN~Shockly~MAGE~~~(.*)$")
check("long message truncated on a UTF-8 boundary with ellipsis", body and #p <= 255 and body:sub(-3) == "..." and (#body - 3) % 2 == 0, p and #p)

-- /cl report: one pasteable line with version, channel, last send result and the debug log
n0 = #chatLines; local rep = report()
check("/cl report fills the copy box", rep ~= "")
check("report has version, channel id, last send result and log", rep:find("CORELink 0.2.0-test", 1, true) and rep:find("channel CORELink7100 id 6", 1, true) and rep:find("lastSend ok", 1, true) and rep:find("log: ", 1, true), rep)
check("report is also printed to chat", #chatLines > n0 and chatLines[#chatLines].text == "|cff33ff99CORELink:|r " .. rep)
-- an unstamped (dev) checkout reports "dev" instead of the placeholder
local realMeta = C_AddOns.GetAddOnMetadata
C_AddOns.GetAddOnMetadata = function() return "@project-version@" end
check("placeholder version shows as dev", report():find("CORELink dev |", 1, true) ~= nil)
C_AddOns.GetAddOnMetadata = realMeta

-- /cl debug on echoes debug lines to chat; off silences them but the report still keeps the log
slash("debug on"); n0 = #chatLines; advance(11)
typeLine("debug me")
check("debug on echoes the relay line", #chatLines > n0 and last():find("debug|r relayed own line", 1, true) ~= nil, last())
slash("debug off"); n0 = #chatLines; advance(11)
typeLine("quiet now")
check("debug off prints nothing for a relayed line", #chatLines == n0)
rep = report()
check("report log keeps entries recorded while debug was off", rep:find("quiet now", 1, true) == nil and rep:find("relayed own line", 1, true) ~= nil)

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
  -- the client rejoined the remembered channel without its password and asks the player for it
  local hidden = {}
  StaticPopup_Hide = function(which) hidden[#hidden + 1] = which end
  jc = #joinCalls
  H(nil, "CHANNEL_PASSWORD_REQUEST", "CORELink7100")
  check("a password request for the link channel is answered from the config",
    #joinCalls == jc + 1 and joinCalls[#joinCalls][1] == "CORELink7100" and joinCalls[#joinCalls][2] == "pw1")
  check("the password prompt is closed", hidden[1] == "CHAT_CHANNEL_PASSWORD")
  H(nil, "CHANNEL_PASSWORD_REQUEST", "SomeOtherChannel")
  check("a password request for another channel is left alone", #joinCalls == jc + 1 and #hidden == 1)
  StaticPopup_Hide = nil
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
  H(nil, "CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", nil, nil, "CORELink7100", nil, nil, nil, 0, "CORELink7100")
  check("a successful join clears the hold", report():find("joinHold no", 1, true) ~= nil, report())
  H(nil, "CHANNEL_UI_UPDATE")                           -- our own attempt, answered with WRONG_PASSWORD
  H(nil, "CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", nil, nil, "CORELink7100", nil, nil, nil, 0, "CORELink7100")
  rep = report()
  check("report shows guild info state, join attempts and the last notice",
    rep:find("guildInfo line ", 1, true) and rep:find("joinAttempts ", 1, true) and rep:find("lastNotice WRONG_PASSWORD at ", 1, true) and rep:find("joinHold WRONG_PASSWORD", 1, true), rep)
  check("debug log uses wall-clock timestamps", rep:match("log: %d%d:%d%d:%d%d ") ~= nil)
  slash("reload")                                   -- a member may reload (#23)
  check("/cl reload clears the hold and retries the join", #joinCalls == jc + 2, #joinCalls - jc)
end

-- The client rejoins the remembered channel without its password at login, before the addon's first attempt;
-- the server's WRONG_PASSWORD for that is not ours: join with the password instead of pausing for ten minutes.
do
  -- config saved by the previous session, so the addon is configured from the first frame
  CORELinkDB = { channel = "CORELink7100", password = "pw1", tag = "MAIN", source = "Guild Info" }
  joined = {}; joinCalls = {}
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1\n"
  JoinChannelByName = function(n, pw) joinCalls[#joinCalls + 1] = { n, pw }; joined[n] = 6 end
  H(nil, "ADDON_LOADED", "CORELink")
  H(nil, "PLAYER_LOGIN")
  advance(80)                                          -- login sync joined at +5s; nothing tried since
  local jc = #joinCalls
  n0 = #chatLines
  H(nil, "CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", nil, nil, "CORELink7100", nil, nil, nil, 0, "CORELink7100")
  check("client's password-less rejoin: the addon joins with the password",
    #joinCalls == jc + 1 and joinCalls[#joinCalls][2] == "pw1", #joinCalls - jc)
  local quiet = #chatLines == n0                       -- before report(), which prints a line itself
  check("client's password-less rejoin: no hold, no complaint",
    quiet and report():find("joinHold no", 1, true) ~= nil, quiet and report() or chatLines[#chatLines].text)
  H(nil, "CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", nil, nil, "CORELink7100", nil, nil, nil, 0, "CORELink7100")
  check("a wrong password right after our own attempt still pauses the join",
    report():find("joinHold WRONG_PASSWORD", 1, true) ~= nil and #joinCalls == jc + 1, report())
  slash("reload")                                      -- clear the hold for the blocks that follow
end

-- Login gives up with a reason when Guild Info never has a line
do
  CORELinkDB = {}; joined = {}; joinCalls = {}
  guildInfoText = "Welcome, no link configured here\n"
  H(nil, "ADDON_LOADED", "CORELink")
  H(nil, "PLAYER_LOGIN")
  n0 = #chatLines
  advance(90)
  local found, late = 0, 0
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
  for i = n0 + 1, #chatLines do if chatLines[i].text:find("not connected after login: ", 1, true) and chatLines[i].text:find("CORELink7100", 1, true) then late = late + 1 end end
  check("configured client whose join never lands gets one explanation after the retries", late == 1, late)
  JoinChannelByName = function(n, pw) joinCalls[#joinCalls + 1] = { n, pw }; joined[n] = 6 end
end

-- A character that moves to a guild without a CORELink line does not keep the old guild's settings
do
  CORELinkDB = {}; joined = {}; joinCalls = {}
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1\n"
  H(nil, "ADDON_LOADED", "CORELink"); H(nil, "PLAYER_LOGIN"); advance(8)
  check("settings came from Guild Info", CORELinkDB.channel == "CORELink7100" and CORELinkDB.source == "Guild Info")
  guildInfoText = "A different guild, no link here\n"
  advance(60)
  check("a guild with no CORELink line clears settings inherited from Guild Info and leaves the channel",
    CORELinkDB.channel == nil and joined["CORELink7100"] == nil and last():find("settings from the previous guild were cleared", 1, true) ~= nil, last())
  guildInfoText = savedTextForRestore
end

-- WoW: Forever reports "First Surname" in chat and the roster while UnitName gives the first name only.
do
  CORELinkDB = {}; joined = {}; joinCalls = {}
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1\n"
  roster[1][1] = "Shockly Stormgale-Beta"
  H(nil, "ADDON_LOADED", "CORELink")
  H(nil, "PLAYER_LOGIN")
  advance(8)
  check("forever names: our full name is learned from the roster before any roster event", report():find("| me Shockly Stormgale |", 1, true) ~= nil, report())
  myRank = 0
  slash("nickname Jake")
  check("nickname is stored under the roster/chat name", CORELinkDB.nicks["Shockly Stormgale"] == "Jake" and CORELinkDB.nicks["Shockly"] == nil, CORELinkDB.nicks["Shockly"])
  local _, ownLine = filters.CHAT_MSG_GUILD(nil, "CHAT_MSG_GUILD", "hi all", "Shockly Stormgale-Beta")
  check("own guild line shows rank and nickname with the surname name format", type(ownLine) == "string" and ownLine:find("Jake) hi all", 1, true) ~= nil and ownLine:find("(Member", 1, true) ~= nil, ownLine)
  mark = #chatSends; typeLine("my own line")
  local own = channelSends(mark)[1]
  check("own typed line is relayed under the full name with the nickname", own ~= nil and own:find("~MAIN~Shockly Stormgale~MAGE~OMember~Jake~my own line", 1, true) ~= nil, own)
  local am = #sentAddon
  H(nil, "CHAT_MSG_GUILD", "my own line", "Shockly Stormgale-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-me")
  advance(3)
  check("our own line arriving as a guild event under the full name is recognised as ours and not carried", #whisperSends(am, "WB~") == 0)
  -- gossip naming ourselves is not greeted
  am = #sentAddon
  H(nil, "CHAT_MSG_ADDON", "CORELink", "DIR~Shockly Stormgale@PvE@MAIN@CORE Forever", "WHISPER", "Zag Mathris")
  advance(2)
  check("gossip that names ourselves does not make us greet ourselves", #whisperSends(am, "HELLO~") == 0 and lines(function() slash("peers") end):find("Shockly Stormgale", 1, true) == nil)
  myRank = 3; roster[1][1] = "Shockly-Beta"; slash("nickname clear")
end

-- Community mirror: typed guild lines are posted into the club from the Guild Info "club=" token
do
  CORELinkDB = {}; joined = {}; joinCalls = {}; clubPosts = {}; clubMember = true
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1 club=23112951\n"
  JoinChannelByName = function(n, pw) joinCalls[#joinCalls + 1] = { n, pw }; joined[n] = 6 end
  H(nil, "ADDON_LOADED", "CORELink"); H(nil, "PLAYER_LOGIN"); advance(8)
  check("mirror: club id parsed from the Guild Info line", CORELinkDB.clubId == 23112951, CORELinkDB.clubId)
  check("mirror: stream is focused as soon as login connects", report():find("focused=true", 1, true) ~= nil)
  typeLine("hello everyone")
  check("mirror: a typed guild line is posted to the club's General stream as [TAG] Name: text",
    #clubPosts == 1 and clubPosts[1].club == 23112951 and clubPosts[1].stream == 1 and clubPosts[1].text:match("^%[MAIN%] Shockly[^:]*: hello everyone$") ~= nil, clubPosts[1] and clubPosts[1].text)
  typeLine("/cl report"); typeLine("in say", "SAY")
  check("mirror: slash commands and non-guild chat are not posted", #clubPosts == 1, #clubPosts)
  myRank = 0; lastSetText = nil; slash("publish"); myRank = 3
  check("mirror: /cl publish keeps the club token on the line", lastSetText == "CORELink: CORELink7100 pw1 MAIN 1 club=23112951", lastSetText)
  check("mirror: report shows club, membership, stream and counts", report():find("mirror post=on read=on club=23112951 id=23112951 type=0 member=true stream=1:General channels=1 posted=1 failed=0 shown=0 skipped=0 hidden=0 focused=true hooks=editbox+send", 1, true) ~= nil, report())
  -- SendChatMessage hook: "/g text" from another chat type, macros and other addons are mirrored too
  local sendHook = hooks["SendChatMessage"]
  check("mirror: SendChatMessage is hooked", type(sendHook) == "function" and type(hooks[C_ChatInfo] and hooks[C_ChatInfo].SendChatMessage) == "function")
  sendHook("from a macro", "GUILD")
  check("mirror: a guild send outside the edit box is posted", #clubPosts == 2 and clubPosts[2].text:match(": from a macro$") ~= nil, clubPosts[2] and clubPosts[2].text)
  sendHook("whisper text", "WHISPER", nil, "Bob"); sendHook("   ", "GUILD")
  check("mirror: non-guild and blank sends are not posted", #clubPosts == 2, #clubPosts)
  mark = #chatSends
  typeLine("same keypress"); sendHook("same keypress", "GUILD"); hooks[C_ChatInfo].SendChatMessage("same keypress", "GUILD")
  check("mirror: one typed line that fires every hook is posted once", #clubPosts == 3, #clubPosts)
  check("relay: one typed line that fires every hook is relayed once", #channelSends(mark) == 1, #channelSends(mark))
  advance(2); sendHook("same keypress", "GUILD")
  check("mirror: the same text sent again later is posted again", #clubPosts == 4, #clubPosts)
  -- stream focus: lost on CLUB_ERROR or a failed post, re-done before the next post
  H(nil, "CLUB_ERROR", 3, 7)
  check("mirror: CLUB_ERROR drops the stream focus", report():find("focused=false", 1, true) ~= nil)
  advance(2); sendHook("after error", "GUILD")
  check("mirror: the stream is focused again before posting", #clubPosts == 5 and report():find("focused=true", 1, true) ~= nil)
  clubSendFails = true; advance(2); sendHook("will fail", "GUILD"); clubSendFails = false
  rep = report()
  check("mirror: a failed post is counted and drops the focus", rep:find("failed=1", 1, true) ~= nil and rep:find("focused=false", 1, true) ~= nil, rep)
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
  check("mirror hide: report counts hidden raw lines", report():find("hidden=1", 1, true) ~= nil)
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
  check("mirror read: class colour from the community member record", #chatLines > n0 and last():find("|cff40c7eb[Fay Brook]|r", 1, true) ~= nil, last())
  channelLine("CL4~c0000001~ALT~Gus Pine~WARRIOR~OCaptain~~via relay", "Gus Pine")
  clubMessages[111] = { messageId = 111, content = "[ALT] Gus Pine: now via the community", author = { name = "Gus Pine", isSelf = false } }
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23112951, 1, 111)
  local cl = chatLines[#chatLines]
  check("mirror read: class and officer colour learned from an earlier relay packet", #chatLines > n0 and cl.text:find("|cffc79c6e[Gus Pine]|r", 1, true) ~= nil and cl.text:find("(Captain) now via the community", 1, true) ~= nil and math.floor(cl.r * 255 + 0.5) == 0xe8, cl.text .. " r=" .. tostring(cl.r))
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23112951, 1, 104); advance(2)
  check("mirror read: plain community chat shows under the author's name only", #chatLines > n0 and last():find("[Dana Reed]|h: just chatting", 1, true) ~= nil and last():find("Core Test", 1, true) == nil, last())
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
  check("club name: report shows token and id", report():find("club=coretest id=23112951 type=0 member=true", 1, true) ~= nil)
  clubMessages[120] = { messageId = 120, content = "[ALT] Hal Moss: named club", author = { name = "Hal Moss", isSelf = false } }
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23112951, 1, 120)
  check("club name: inbound lines from the named community are shown", #chatLines > n0 and last():find("named club", 1, true) ~= nil)
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
  check("wow club: report shows type=wow", report():find("club=Guild id=23149801 type=wow member=true", 1, true) ~= nil)
  clubMembers[7] = { memberId = 7, name = "Zag Mathris", guid = "guid-zag", classID = 8 }
  clubMembers[8] = { memberId = 8, name = "Bob", guid = "guid-bob", classID = 1 }
  clubMembers[9] = { memberId = 9, name = "Shockly Stormgale", guid = "guid-me", classID = 8 }
  clubMessages[201] = { messageId = 201, content = sealed("[Trois] I'm here!"), author = { memberId = 7 } }
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 201); advance(2)
  check("wow club: sealed text shows once per guild window under the class-coloured character name",
    #chatLines == n0 + 2 and last():find("|cff40c7eb[Zag Mathris]|r|h: [Trois] I'm here!", 1, true) ~= nil and last():find("Core Test", 1, true) == nil, last())
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
  check("wow club: it is shown once the member record loads", #chatLines == n0 + 2 and last():find("[Cosmo Vale]", 1, true) ~= nil, last())
  local cl = chatLines[#chatLines]
  check("wow club: a community Moderator never heard on the relay gets the officer colour, text prefix untouched",
    math.floor(cl.r * 255 + 0.5) == 0xe8 and cl.text:find("|h: [Trois] late author", 1, true) ~= nil, cl.text .. " r=" .. tostring(cl.r))
  clubMessages[212] = { messageId = 212, content = sealed("[Trois] (Captain Zaggy) ranked"), author = { memberId = 7 } }
  channelLine("CL4~00000b01~Trois~Zag Mathris~MAGE~~Zaggy~plain member", "Zag Mathris")
  advance(10); n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 212); advance(2)
  cl = chatLines[#chatLines]
  check("wow club: relay knowledge wins: a non-officer's sealed line is not officer-coloured and the prefix is not doubled",
    #chatLines == n0 + 2 and math.floor(cl.r * 255 + 0.5) ~= 0xe8 and cl.text:find("|h: [Trois] (Captain Zaggy) ranked", 1, true) ~= nil, cl.text .. " r=" .. tostring(cl.r))
  -- relay first, community copy within 5 s: shown once
  advance(10); n0 = #chatLines
  channelLine("CL4~0000cafe~Trois~Zag Mathris~MAGE~~Zaggy~both ways", "Zag Mathris")
  clubMessages[205] = { messageId = 205, content = sealed("[Trois] both ways"), author = { memberId = 7 } }
  advance(1); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 205); advance(2)
  check("wow club: a line heard on the relay is not shown again from the community", #chatLines == n0 + 2, #chatLines - n0)
  check("wow club: report counts the skipped copy", report():find("skipped=1", 1, true) ~= nil)
  -- community first, relay copy within 5 s: shown once
  advance(10); n0 = #chatLines
  clubMessages[206] = { messageId = 206, content = sealed("[Trois] club first"), author = { memberId = 7 } }
  H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 206); advance(2)
  check("wow club: a sealed line is shown as posted, without a locally added prefix (the poster's client wrote it)", last():find("|h: [Trois] club first", 1, true) ~= nil, last())
  advance(1)
  channelLine("CL4~0000beef~Trois~Zag Mathris~MAGE~~Zaggy~club first", "Zag Mathris")
  check("wow club: the relay copy of a line already shown from the community is dropped", #chatLines == n0 + 2, #chatLines - n0)
  -- two quick lines from the same person on both paths are both shown once
  advance(10); n0 = #chatLines
  channelLine("CL4~00000a01~Trois~Zag Mathris~MAGE~~Zaggy~one", "Zag Mathris")
  channelLine("CL4~00000a02~Trois~Zag Mathris~MAGE~~Zaggy~two", "Zag Mathris")
  clubMessages[207] = { messageId = 207, content = sealed("[Trois] one"), author = { memberId = 7 } }
  clubMessages[208] = { messageId = 208, content = sealed("[Trois] two"), author = { memberId = 7 } }
  H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 207); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 208); advance(2)
  check("wow club: two quick lines on both paths show exactly twice", #chatLines == n0 + 4, #chatLines - n0)
  -- readable "[TAG] text" lines still honour the tag: own guild skipped, muted skipped
  advance(10)
  clubMessages[209] = { messageId = 209, content = "[MAIN] readable own guild", author = { memberId = 7 } }
  clubMessages[210] = { messageId = 210, content = "[QUIET] readable muted", author = { memberId = 7 } }
  clubMessages[211] = { messageId = 211, content = "[Trois] readable other", author = { memberId = 7 } }
  slash("mute QUIET"); n0 = #chatLines
  H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 209); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 210); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 211)
  check("wow club: readable [TAG] text lines keep tag filtering", #chatLines == n0 + 2 and last():find("[Trois] |Hplayer:Zag Mathris|h", 1, true) ~= nil, last())
  -- a readable post with | in its tag, name and nickname (#24): cleaned like a packet's fields
  clubMessages[213] = { messageId = 213, content = "[Tr|ois] Zed|cffff0000 (Z|red): readable hostile", author = { memberId = 7 } }
  clubMessages[214] = { messageId = 214, content = "[QU|IET] Zed: readable hostile muted", author = { memberId = 7 } }
  advance(10); n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 213); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 214)
  check("wow club: a readable post with | in tag, name and nickname is displayed with them cleaned, and a muted tag stays muted",
    #chatLines == n0 + 2 and last() == "[Trois] |Hplayer:Zedcffff0000|h|cff40c7eb[Zedcffff0000]|r|h: (Zred) readable hostile", last())
  check("wow club: the cleaned tag is the guild already known, not a new one", lines(function() slash("guilds") end):find("Tr|ois", 1, true) == nil)
  clubMessages[215] = { messageId = 215, content = "[Trois] |: nothing left of the name", author = { memberId = 7 } }
  advance(10); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 215)
  check("wow club: a readable post whose name is nothing but | shows under the community member's name", last():find("[Trois] |Hplayer:Zag Mathris|h", 1, true) ~= nil, last())
  clubMembers[12] = { memberId = 12, name = "|Kq12|k", guid = "guid-kay", classID = 8 }
  clubMessages[216] = { messageId = 216, content = sealed("[Trois] from a sealed name"), author = { memberId = 12 } }
  advance(10); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 1, 216)
  check("wow club: a member name the game gives as a |K token is drawn as given", last():find("|Hplayer:|Kq12|k|h|cff40c7eb[|Kq12|k]|r|h: [Trois] from a sealed name", 1, true) ~= nil, last())
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
  rep = report()
  check("channels: report names the post channel and counts only guild channels plus General", rep:find("stream=3:Main channels=3", 1, true) ~= nil and rep:find("focused=true", 1, true) ~= nil, rep)
  clubMessages[405] = { messageId = 405, content = sealed("officer talk"), author = { memberId = 7 } }
  clubMessages[406] = { messageId = 406, content = sealed("deux without a description"), author = { memberId = 7 } }
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23149801, 2, 405); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 5, 406); H(nil, "CLUB_MESSAGE_ADDED", 23149801, 6, 405); advance(2)
  check("channels: channels that are not guild channels (no CORELink description, unknown tag, leaders-only) are ignored", #chatLines == n0, #chatLines - n0)
  channelLine("CL4~0000d001~Deux~Dee Vale~MAGE~~~heard on the relay", "Dee Vale")
  H(nil, "CLUB_STREAM_ADDED", 23149801, 5); advance(1)
  n0 = #chatLines; H(nil, "CLUB_MESSAGE_ADDED", 23149801, 5, 406); advance(2)
  check("channels: a channel named after a tag heard on the relay becomes a guild channel", #chatLines == n0 + 2 and last():find("[Deux] |Hplayer:Zag Mathris|h", 1, true) ~= nil, last())
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
  check("channels: General still shows under the name with the text as posted", #chatLines == n0 + 2 and last():find("|Hplayer:Zag Mathris|h|cff40c7eb[Zag Mathris]|r|h: [Deux] general line", 1, true) ~= nil, last())
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
  check("echo: report shows the guild setting and this client's", report():find("echo on me=on sent=0 hidden=0", 1, true) ~= nil, report())
  myRank = 0; lastSetText = nil; slash("publish"); myRank = 3
  check("echo: /cl publish keeps echo=on on the line", lastSetText == "CORELink: CORELink7100 pw1 MAIN 1 club=Guild echo=on", lastSetText)
  local nSent, nPosts = #sentAddon, #clubPosts
  channelLine("CL4~0000e001~ALT~Carol~PRIEST~OCaptain~Cee~hi echo", "Carol")
  advance(2)
  check("echo: another guild's relayed line is re-posted into real guild chat with name, rank and nickname",
    #chatSends == 1 and chatSends[1].kind == "GUILD" and chatSends[1].text == "[ALT] Carol (Captain Cee): hi echo", chatSends[1] and chatSends[1].text)
  check("echo: the echo is claimed to guildmates first", #guildSends(nSent, "ECHO~0000e001") == 1)
  check("echo: our own echo send is not mirrored into the community or relayed", #clubPosts == nPosts and #channelSends(0) == 0, #clubPosts - nPosts)
  channelLine("CL4~0000e002~ALT~Carol~PRIEST~~~claimed by tanner", "Carol")
  H(nil, "CHAT_MSG_ADDON", "CORELink", "ECHO~0000e002", "GUILD", "Tanner-Beta")
  advance(2)
  check("echo: a line a guildmate already claimed is not echoed again", #chatSends == 1, #chatSends)
  local gf = filters["CHAT_MSG_GUILD"]
  check("echo: an echoed line from an addon user is hidden in our guild chat", gf(nil, "CHAT_MSG_GUILD", "[ALT] Carol (Captain Cee): hi echo", "Tanner-Beta") == true)
  check("echo: the same text from a member without the addon is not hidden", gf(nil, "CHAT_MSG_GUILD", "[ALT] Carol: hi echo", "Dora-Beta") ~= true)
  check("echo: our own guild's tag in brackets is not treated as an echo", gf(nil, "CHAT_MSG_GUILD", "[MAIN] Carol: not an echo", "Tanner-Beta") ~= true)
  nSent = #sentAddon; mark = #chatSends
  H(nil, "CHAT_MSG_GUILD", "[ALT] Carol (Captain Cee): hi echo", "Tanner-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-tanner")
  advance(3)
  check("echo: an echoed line is not carried and is counted as hidden", #whisperSends(nSent, "WB~") == 0 and #channelSends(mark) == 0 and report():find("echo on me=on sent=1 hidden=1", 1, true) ~= nil, report())
  slash("echo off")
  channelLine("CL4~0000e003~ALT~Carol~PRIEST~~~after opt out", "Carol")
  advance(2)
  check("echo: /cl echo off stops this client echoing", #chatSends == 1, #chatSends)
  slash("echo on")
  channelLine("CL4~0000ba09~A|LT~Eve|cffff0000~PRIEST~OCap\ntain~~echo hostile", "Carol")
  advance(2)
  check("echo: a packet with | and control characters in its fields is echoed into guild chat without them (#24)",
    #chatSends == 2 and chatSends[2].text == "[ALT] Evecffff0000 (Captain): echo hostile", chatSends[2] and chatSends[2].text)
  CORELinkDB = {}; joined = {}; chatSends = {}
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1 club=Guild\n"
  H(nil, "ADDON_LOADED", "CORELink"); H(nil, "PLAYER_LOGIN"); advance(8)
  channelLine("CL4~0000e004~ALT~Carol~PRIEST~~~no echo", "Carol")
  advance(2)
  check("echo: nothing is echoed when the Guild Info line has no echo=on", #chatSends == 0, #chatSends)
  guildInfoText = savedTextForRestore
end

-- Whisper bridge: the courier's peers, greetings, the optional who round, routing to every other guild
do
  CORELinkDB = { peers = {} }; joined = {}; clubPosts = {}; clubMember = true; whoSent = {}; whoResults = {}; sentAddon = {}
  guildInfoText = "CORELink: CORELink7100 pw1 MAIN 1 echo=on guilds=Trois Royaume, Deux\n"
  H(nil, "ADDON_LOADED", "CORELink"); H(nil, "PLAYER_LOGIN"); H(nil, "GUILD_ROSTER_UPDATE"); advance(8)
  check("whisper: guilds= parsed from the end of the line, other tokens intact", CORELinkDB.guilds and #CORELinkDB.guilds == 2 and CORELinkDB.guilds[1] == "Trois Royaume" and CORELinkDB.guilds[2] == "Deux" and CORELinkDB.echo == true, CORELinkDB.guilds and table.concat(CORELinkDB.guilds, "|"))
  myRank = 0; lastSetText = nil; slash("publish"); myRank = 3
  check("whisper: /cl publish writes guilds= last", lastSetText == "CORELink: CORELink7100 pw1 MAIN 1 echo=on guilds=Trois Royaume, Deux", lastSetText)
  advance(400)                                                   -- earlier blocks' guildmates age out of the election
  check("whisper: we are the courier when no guildmate runs the addon", report():find("courier=me guilds=2", 1, true) ~= nil, report())
  -- who round: one silent query per listed guild; results are names without realms; exact guild only
  advance(60); whoSent = {}
  slash("who")
  check("whisper: a who round queries the first listed guild", #whoSent == 1 and whoSent[1] == 'g-"Trois Royaume"', tostring(whoSent[1]))
  whoResults = { { fullName = "Nia Thorn", fullGuildName = "Trois Royaume" }, { fullName = "Cosmo Vale", fullGuildName = "Trois Royaume" },
                 { fullName = "Sgt Mayo", fullGuildName = "Molten Trois Royaume" }, { fullName = "Orla Finch", fullGuildName = "Trois Royaume" },
                 { fullName = "Shockly", fullGuildName = "Trois Royaume" }, { fullName = "Ash Vale", fullGuildName = "Trois Royaume" } }
  H(nil, "WHO_LIST_UPDATE"); advance(4)
  check("whisper: the next guild is queried after the results arrive", #whoSent == 2 and whoSent[2] == 'g-"Deux"', #whoSent .. " " .. tostring(whoSent[2]))
  whoResults = {}; H(nil, "WHO_LIST_UPDATE"); advance(4)
  local hellos = {}
  for _, m in ipairs(sentAddon) do if m.kind == "WHISPER" and m.text:match("^HELLO~MAIN~PvE~CORE Forever$") then hellos[m.target] = true end end
  check("whisper: who results are greeted over whisper addon messages, three per guild, exact guild only, not ourselves",
    hellos["Nia Thorn"] and hellos["Cosmo Vale"] and hellos["Orla Finch"] and not hellos["Shockly"] and not hellos["Sgt Mayo"] and not hellos["Ash Vale"])
  out = lines(function() slash("guilds") end)
  check("whisper: /cl guilds counts the exact guild's online members from the last round", out:find("Trois Royaume - 5 online (asked", 1, true) ~= nil, out)
  advance(616); whoSent = {}                                     -- the automatic round at +600 runs and times out
  slash("who")
  whoResults = { { fullName = "Nia Thorn", fullGuildName = "Trois Royaume" }, { fullName = "Cosmo Vale", fullGuildName = "Trois Royaume" },
                 { fullName = "Orla Finch", fullGuildName = "Trois Royaume" }, { fullName = "Ash Vale", fullGuildName = "Trois Royaume" } }
  local nSent0 = #sentAddon
  H(nil, "WHO_LIST_UPDATE"); advance(4)
  whoResults = {}; H(nil, "WHO_LIST_UPDATE"); advance(4)
  local round2 = whisperSends(nSent0, "HELLO~")
  check("whisper: the next round greets the names not tried yet, not the same three again", #round2 == 1 and round2[1].target == "Ash Vale", #round2)
  -- a player without the addon never answers; one with it answers PEER and becomes a peer
  H(nil, "CHAT_MSG_ADDON", "CORELink", "PEER~Trois~CAMWOWUS2Realm1PvE~Trois Royaume", "WHISPER", "Zag Mathris")
  check("whisper: a PEER answer is remembered with its guild", CORELinkDB.peers["Zag Mathris"] and CORELinkDB.peers["Zag Mathris"].tag == "Trois" and CORELinkDB.peers["Zag Mathris"].guild == "Trois Royaume" and report():find("peers=1", 1, true) ~= nil, report())
  -- someone greets us: we answer PEER and share our directory
  local nSent = #sentAddon
  H(nil, "CHAT_MSG_ADDON", "CORELink", "HELLO~Deux~CAMWOWUS2Realm1PvE~Deux", "WHISPER", "Dee Vale"); advance(3)
  local gotPeer, gotDir = false, false
  for i = nSent + 1, #sentAddon do
    if sentAddon[i].kind == "WHISPER" and sentAddon[i].target == "Dee Vale" then
      if sentAddon[i].text == "PEER~MAIN~PvE~CORE Forever" then gotPeer = true end
      if sentAddon[i].text:find("^DIR~.*Zag Mathris@CAMWOWUS2Realm1PvE@Trois@Trois Royaume") then gotDir = true end
    end
  end
  check("whisper: a HELLO is answered with PEER and a directory of live peers", gotPeer and gotDir)
  -- routing: a guildmate without the addon types; the courier whispers the line once to every other guild
  nSent = #sentAddon
  H(nil, "CHAT_MSG_GUILD", "over the water", "Dora-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-dora")
  advance(3)
  local carried = whisperSends(nSent, "WB~")
  local targets = {}
  for _, w in ipairs(carried) do targets[w.target] = w.text end
  check("whisper: the line is carried once to each other guild, to its freshest peer",
    #carried == 2 and targets["Zag Mathris"] and targets["Dee Vale"] and targets["Zag Mathris"]:match("^WB~CL4~%x+~MAIN~Dora~~~~over the water$") ~= nil, #carried)
  check("whisper: report counts the carried line per guild", report():find("sent=4", 1, true) ~= nil, report())
  -- inbound: a carried line from a peer is shown once and fanned out to our guild once; never carried onward
  nSent = #sentAddon; n0 = #chatLines
  H(nil, "CHAT_MSG_ADDON", "CORELink", "WB~CL4~0000f003~Trois~Zag Mathris~MAGE~~Zaggy~from across", "WHISPER", "Zag Mathris")
  advance(4)
  local fanned = guildSends(nSent, "LINE~")
  check("whisper: a carried line from a peer is shown once, fanned out once, and echoed for members without the addon",
    #chatLines >= n0 + 2 and chatLines[n0 + 1].text:find("[Trois] |Hplayer:Zag Mathris|h", 1, true) ~= nil and #fanned == 1 and #whisperSends(nSent, "WB~") == 0, (#chatLines - n0) .. " " .. #fanned)
  check("whisper: report counts answers, carried, received and fanned lines", report():find("answered=2 sent=4 recv=4 fanned=3", 1, true) ~= nil, report())
  -- gossip: an unknown name in a directory gets a hello; the game's "not playing" reply is hidden
  nSent = #sentAddon
  H(nil, "CHAT_MSG_ADDON", "CORELink", "DIR~Rook Hale@CAMWOWUS2Realm1PvE@Deux@Deux", "WHISPER", "Zag Mathris"); advance(2)
  local greeted = whisperSends(nSent, "HELLO~")
  check("whisper: a name learned from gossip is greeted, not trusted", #greeted == 1 and greeted[1].target == "Rook Hale" and CORELinkDB.peers["Rook Hale"].seen == 0 and CORELinkDB.peers["Rook Hale"].tag == "Deux")
  local sf = filters["CHAT_MSG_SYSTEM"]
  check("whisper: the game's 'not playing' line for our own hello is hidden", sf(nil, "CHAT_MSG_SYSTEM", "No player named 'Rook Hale' is currently playing.") == true)
  check("whisper: other 'not playing' lines are left alone", sf(nil, "CHAT_MSG_SYSTEM", "No player named 'Someone Else' is currently playing.") ~= true)
  out = lines(function() slash("peers") end)
  check("whisper: /cl peers lists peers with tag, guild and state", out:find("Zag Mathris - Trois (Trois Royaume) seen", 1, true) ~= nil and out:find("Rook Hale - Deux (Deux) not yet answered", 1, true) ~= nil, out)
  slash("whisper off")
  nSent = #sentAddon
  H(nil, "CHAT_MSG_GUILD", "while off", "Dora-Beta", nil, nil, nil, nil, nil, nil, nil, nil, nil, "guid-dora"); advance(3)
  check("whisper: /cl whisper off stops carrying lines", #whisperSends(nSent, "WB~") == 0)
  slash("whisper on")
  -- /cl hello: greet one player by hand
  nSent = #sentAddon
  slash("hello Ivy Marsh"); advance(2)
  local manual = whisperSends(nSent, "HELLO~")
  check("whisper: /cl hello <name> whispers a HELLO to that player", #manual == 1 and manual[1].target == "Ivy Marsh" and manual[1].text == "HELLO~MAIN~PvE~CORE Forever" and last():find("hello sent to Ivy Marsh", 1, true) ~= nil, #manual)
  H(nil, "CHAT_MSG_ADDON", "CORELink", "PEER~Quat~CAMWOWUS2Realm3PvE~Quatre", "WHISPER", "Ivy Marsh")
  check("whisper: the answer to a manual hello becomes a peer", CORELinkDB.peers["Ivy Marsh"] and CORELinkDB.peers["Ivy Marsh"].tag == "Quat")
  nSent = #sentAddon
  slash("hello Ivy Marsh"); advance(2)
  check("whisper: a repeated /cl hello is sent again despite the 10 min throttle", #whisperSends(nSent, "HELLO~") == 1)
  slash("hello")
  check("whisper: /cl hello without a name prints usage", last():find("usage: /cl hello", 1, true) ~= nil, last())
  -- a peer's card and gossip (HELLO, DIR) are saved and printed by /cl peers: cleaned like a packet's fields
  H(nil, "CHAT_MSG_ADDON", "CORELink", "HELLO~Ci|nq~Realm|cffff00005~Cinq| Royaume", "WHISPER", "Mal Vex")
  H(nil, "CHAT_MSG_ADDON", "CORELink", "DIR~Rae| Moss@Realm|5@Ci|nq@Cinq|cffff0000 Royaume", "WHISPER", "Mal Vex")
  local hostilePeers, mal, rae = lines(function() slash("peers") end), CORELinkDB.peers["Mal Vex"], CORELinkDB.peers["Rae Moss"]
  check("whisper: a card and gossip with | in tag, realm, guild and name are saved and listed without it",
    hostilePeers:find("Mal Vex - Cinq (Cinq Royaume)", 1, true) ~= nil and mal ~= nil and mal.realm == "Realmcffff00005"
    and rae ~= nil and rae.tag == "Cinq" and rae.guild == "Cinqcffff0000 Royaume" and rae.realm == "Realm5", hostilePeers)
  guildInfoText = savedTextForRestore
end

-- Commands that only change this client's settings, and the guild master's configuration commands.
do
  CORELinkDB = {}; joined = {}; joinCalls = {}
  guildInfoText = "nothing here\n"
  H(nil, "ADDON_LOADED", "CORELink"); H(nil, "PLAYER_LOGIN"); H(nil, "GUILD_ROSTER_UPDATE"); advance(8)
  out = lines(function() slash("") end)
  check("commands: plain /cl prints the status line and the member command list", out:find("NOT CONFIGURED", 1, true) and out:find("/cl classcolor | debug | echo", 1, true) and not out:find("| channel |", 1, true), out)
  slash("setup chan pw TAG")
  check("commands: /cl setup is refused for a member", last():find("only the guild master", 1, true) ~= nil, last())
  myRank = 0
  slash("setup chan pw TAG"); advance(2)
  check("commands: /cl setup configures and joins", CORELinkDB.channel == "chan" and CORELinkDB.password == "pw" and CORELinkDB.tag == "TAG" and joined.chan == 6, tostring(joined.chan))
  out = lines(function() slash("") end)
  check("commands: plain /cl for the guild master lists the setup commands too", out:find("/cl channel | classcolor |", 1, true) ~= nil, out)
  out = lines(function() slash("channel") end)
  check("commands: /cl channel without a name shows the status", out:find("tag: TAG", 1, true) ~= nil, out)
  slash("channel other"); advance(2)
  check("commands: /cl channel <name> moves to that channel", CORELinkDB.channel == "other" and joined.other == 6 and not joined.chan)
  slash("password -")
  check("commands: /cl password - clears the password", CORELinkDB.password == "")
  slash("tag auto")
  check("commands: /cl tag auto derives the tag from the guild name", CORELinkDB.tag == nil and last():find("guild tag: COREFo", 1, true) ~= nil, last())
  slash("officer off"); check("commands: /cl officer off", CORELinkDB.officer == false and last():find("officer highlighting: off", 1, true) ~= nil)
  slash("nicknames off"); check("commands: /cl nicknames off", CORELinkDB.showNick == false)
  slash("classcolor off"); check("commands: /cl classcolor off", CORELinkDB.classColor == false)
  slash("window 3"); check("commands: /cl window 3 pins the window", CORELinkDB.window == 3 and last():find("window 3", 1, true) ~= nil)
  slash("window"); check("commands: /cl window alone unpins it", CORELinkDB.window == nil)
  slash("officercolor e8c63e"); check("commands: /cl officercolor RRGGBB sets the colour", CORELinkDB.officerColorHex == "e8c63e")
  slash("officercolor reset"); check("commands: /cl officercolor reset clears it", CORELinkDB.officerColorHex == nil)
  slash("officercolor"); check("commands: /cl officercolor without a picker explains the fallback", last():find("couldn't open the colour picker", 1, true) ~= nil, last())
  CORELinkDB.nicks[UnitName("player")] = "Shocky"; sentAddon = {}
  H(nil, "CHAT_MSG_ADDON", "CORELink", "NREQ", "GUILD", "Bob-Beta"); advance(8)
  check("commands: an NREQ from a guildmate makes us re-send our nickname", #guildSends(0, "NICK~Shocky") == 1)
  slash("clear"); check("commands: /cl clear forgets the configuration", CORELinkDB.channel == nil and joined.other == nil)
  myRank = 3
end

print(string.format("\n%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
