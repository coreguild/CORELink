-- CORELink/Commands.lua: the /cl slash commands.
-- Each command is one function in NS.commands, keyed by its name; /cl report, guilds and peers live in Report.lua.
-- Only the guild master (rank 0) may change the shared configuration. Everything that affects only this client
-- (on, off, mute, unmute, reload, display toggles) is open to every member.
local _, NS = ...
local Print, Configured, Locked, Clean, GetTag = NS.Print, NS.Configured, NS.Locked, NS.Clean, NS.GetTag
local commands = NS.commands

SLASH_CORELINK1, SLASH_CORELINK2 = "/corelink", "/cl"

local GM_ONLY = {
  setup = true, channel = true, password = true, tag = true, publish = true,
  officerrank = true, clear = true,
}

local function IsGM()
  local _, _, rankIndex = GetGuildInfo("player")
  return rankIndex == 0
end

-- "/cl a | b | c" built from the command table, so it cannot drift from the commands that exist.
local function HelpLine(gm)
  local names = {}
  for name in pairs(commands) do if gm or not GM_ONLY[name] then names[#names + 1] = name end end
  table.sort(names)
  return "/cl " .. table.concat(names, " | ")
end

-- Plain /cl, or a command that needs an argument it did not get.
local function ShowStatus()
  Print(NS.StatusLine())
  local lastSend = NS.conn.lastSendResult
  if Configured() and lastSend then Print("last send result: " .. lastSend) end
  Print(HelpLine(IsGM()))
end

local function OnOff(flag) return flag and "on" or "off" end
local function IsOff(arg) return arg:lower() == "off" end

---------------------------------------------------------------- shared configuration (guild master)
commands.setup = function(arg)
  local ch, pw, tag = arg:match("^(%S+)%s+(%S+)%s*(%S*)")
  if not ch then
    Print("usage: /cl setup <channel> <password> [tag]   (use - for no password)")
    return
  end
  pw = (pw == "-") and "" or Clean(pw)
  tag = (tag ~= "" and tag ~= "-") and Clean(tag):sub(1, 8) or nil
  NS.SetConfig(Clean(ch), pw, tag, "local")
  Print("configured. Channel: " .. Clean(ch) .. ", tag: " .. tostring(tag or "auto"))
  NS.Publish()
end

commands.channel = function(arg)
  if arg == "" then return ShowStatus() end
  NS.SetConfig(Clean(arg), NS.db.password or "", NS.db.tag, "local")
  Print("channel set to " .. Clean(arg) .. ". Use /cl publish to get the Guild Info line for your guild.")
end

commands.password = function(arg)
  if not Configured() then Print("set a channel first: /cl channel <name>") return end
  local pw = (arg == "" or arg == "-") and "" or Clean(arg)
  NS.SetConfig(NS.db.channel, pw, NS.db.tag, "local")
  Print("password updated. Use /cl publish to get the Guild Info line for your guild.")
end

commands.tag = function(arg)
  local t = (arg ~= "" and arg:lower() ~= "auto") and Clean(arg):sub(1, 8) or nil
  NS.db.tag, NS.db.source = t, "local"
  Print("guild tag: " .. tostring(GetTag()) .. ". Use /cl publish to get the Guild Info line for your guild.")
end

commands.publish = function() NS.Publish() end

commands.officerrank = function(arg)
  local n = tonumber(arg)
  if n and n >= 0 then
    NS.db.officerRank = math.floor(n)
    Print("ranks 0 to " .. NS.db.officerRank .. " count as officers (0 = guild master)."
      .. " /cl publish to share via Guild Info.")
  else
    Print("officer rank cutoff: " .. (NS.db.officerRank or 1) .. " (usage: /cl officerrank <n>)")
  end
end

commands.clear = function()
  local db = NS.db
  NS.LeaveLink()
  db.channel, db.password, db.tag, db.source, db.lastGI = nil, nil, nil, nil, nil
  Print("settings cleared.")
end

---------------------------------------------------------------- officer colour
local function OpenColorPicker()
  local db = NS.db
  local r, g, b = NS.HexToRGB(db.officerColorHex)
  local prev = db.officerColorHex
  local function Save()
    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
    db.officerColorHex = string.format("%02x%02x%02x", nr * 255 + 0.5, ng * 255 + 0.5, nb * 255 + 0.5)
  end
  local function Cancel() db.officerColorHex = prev end
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({
      r = r, g = g, b = b, hasOpacity = false, swatchFunc = Save, cancelFunc = Cancel,
    })
  else
    ColorPickerFrame.func = Save
    ColorPickerFrame.cancelFunc = Cancel
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame:Hide(); ColorPickerFrame:Show()
  end
end

commands.officercolor = function(arg)
  local a = arg:lower():gsub("^#", "")
  if a:match("^%x%x%x%x%x%x$") then
    NS.db.officerColorHex = a; Print("officer colour set to #" .. a)
  elseif a == "reset" then
    NS.db.officerColorHex = nil; Print("officer colour reset to the default (#e8c63e).")
  elseif not pcall(OpenColorPicker) then
    Print("couldn't open the colour picker. Use /cl officercolor RRGGBB instead (e.g. e8c63e).")
  end
end

---------------------------------------------------------------- this client's display and toggles
commands.officer = function(arg)
  NS.db.officer = not IsOff(arg)
  Print("officer highlighting: " .. OnOff(NS.db.officer))
end

commands.nickname = function(arg)
  local db, me = NS.db, NS.MyName()
  if arg == "" then
    Print("your nickname: " .. (db.nicks[me] or "(none)") .. "  (usage: /cl nickname <name> | clear)")
  elseif arg:lower() == "clear" then
    db.nicks[me] = nil; NS.BroadcastNick(); Print("nickname cleared.")
  else
    local n = NS.CleanNick(arg)
    if n == "" then Print("that nickname isn't valid.") return end
    db.nicks[me] = n; NS.BroadcastNick()
    Print("nickname set to " .. n .. ". Your guild and linked guilds will see it.")
    if Locked() then Print("(sharing is paused right now; it will sync after you leave the instance.)") end
  end
end

commands.nicknames = function(arg)
  NS.db.showNick = not IsOff(arg)
  Print("showing nicknames: " .. OnOff(NS.db.showNick))
end

commands.mirror = function(arg)
  local db = NS.db
  local what, val = arg:lower():match("^(%a*)%s*(%a*)$")
  if what == "read" then db.mirrorRead = (val ~= "off")
  elseif what == "post" then db.mirror = (val ~= "off")
  elseif what == "hide" then db.hideClub = (val ~= "off")
  else db.mirror = (what ~= "off"); db.mirrorRead = (what ~= "off") end
  Print(string.format("community mirror: post %s, read %s, hide raw community lines %s%s", OnOff(db.mirror ~= false),
    OnOff(db.mirrorRead ~= false), OnOff(db.hideClub ~= false),
    db.club and (" (community " .. db.club .. ")") or " (no club= token in Guild Info)"))
  NS.FocusClubStream()
end

commands.whisper = function(arg)
  NS.db.whisper = not IsOff(arg)
  Print("whisper bridge: " .. OnOff(NS.db.whisper))
end

commands.who = function()
  local db = NS.db
  NS.ResetWhoTimer()
  if not db.guilds or #db.guilds == 0 then Print("no guilds= list on the CORELink line in Guild Info.")
  elseif not NS.IsCourier() then
    Print(NS.Courier() .. " is the courier for this guild; only the courier runs /cl who.")
  else NS.ScheduleWho(); Print("asking who is online in " .. #db.guilds .. " guild(s).") end
end

-- Greet one player by hand: the smallest in-game test of whisper addon messages crossing realms (they show up
-- in /cl peers once they answer).
commands.hello = function(arg)
  local target = arg:match("^%s*(.-)%s*$")
  if target == "" then
    Print("usage: /cl hello <First Surname>  (an addon user in another guild, any realm;"
      .. " /cl peers once they answer)")
  elseif not NS.WhisperAvailable() then
    Print("whispers are not available right now (chat lockdown or missing API).")
  else
    NS.ForgetHello(target)
    NS.Hello(target)
    Print("hello sent to " .. target .. "; run /cl peers in a few seconds.")
  end
end

commands.echo = function(arg)
  local db = NS.db
  db.echoer = not IsOff(arg)
  Print("this client " .. (db.echoer and "may echo" or "will not echo") .. " other guilds' lines into guild chat"
    .. (db.echo and "" or " (echo is off for this guild: the Guild Master adds echo=on to the CORELink line)"))
end

commands.classcolor = function(arg)
  NS.db.classColor = not IsOff(arg)
  Print("class-coloured names: " .. OnOff(NS.db.classColor))
end

commands.debug = function(arg)
  NS.db.debug = (arg:lower() == "on")
  Print("debug output: " .. (NS.db.debug and "on (also kept in /cl report)" or "off"))
end

commands.window = function(arg)
  local n = tonumber(arg)
  if n and _G["ChatFrame" .. n] then
    NS.db.window = n; Print("bridged messages will show in chat window " .. n .. ".")
  else
    NS.db.window = nil; Print("bridged messages will show in the window(s) that have Guild chat enabled.")
  end
end

commands.reload = function()
  local conn = NS.conn
  NS.db.lastGI = nil; conn.blockedUntil = 0; conn.blockedWhy = nil
  NS.ReadGuildInfo(); NS.EnsureChannel(); Print("re-read Guild Info and retried the channel.")
end

commands.on = function() NS.db.enabled = true; NS.EnsureChannel(); Print("enabled.") end
commands.off = function() NS.db.enabled = false; NS.LeaveLink(); Print("disabled.") end

commands.mute = function(arg)
  if arg == "" then return ShowStatus() end
  NS.db.muted[arg:lower()] = true; Print("muted guild tag " .. arg)
end

commands.unmute = function(arg)
  if arg == "" then return ShowStatus() end
  NS.db.muted[arg:lower()] = nil; Print("unmuted guild tag " .. arg)
end

---------------------------------------------------------------- dispatch
SlashCmdList["CORELINK"] = function(input)
  local cmd, arg = input:match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if GM_ONLY[cmd] and not IsGM() then
    Print("only the guild master can use /cl " .. cmd .. ".")
    return
  end
  local handler = commands[cmd]
  if handler then handler(arg) else ShowStatus() end
end
