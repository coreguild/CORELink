-- CORELink/GuildInfo.lua: the shared configuration line in Guild Info.
-- "CORELink: <channel> <password|-> [tag|-] [officerRank] [club=..] [echo=on] [accept=TAG,TAG] [guilds=a, b]"
-- is written by the guild master (by hand: addons cannot write Guild Info) and read by every member's client.
-- Provides NS.ReadGuildInfo, NS.Publish, NS.ShowCopyBox, NS.BuildLine.
local _, NS = ...
local Print, Debug, Configured, Clean = NS.Print, NS.Debug, NS.Configured, NS.Clean
local issecret, conn = NS.issecret, NS.conn

-- Always writes all four fields ("-" for an empty tag) so the GM can see the officer rank cutoff.
function NS.BuildLine()
  local db = NS.db
  local hasTag = db.tag and db.tag ~= ""
  return "CORELink: " .. db.channel .. " " .. (db.password ~= "" and db.password or "-")
    .. " " .. (hasTag and db.tag or "-") .. " " .. (db.officerRank or 1)
    .. (db.club and (" club=" .. db.club) or "")
    .. (db.echo and " echo=on" or "")
    .. ((db.accept and #db.accept > 0) and (" accept=" .. table.concat(db.accept, ",")) or "")
    .. ((db.guilds and #db.guilds > 0) and (" guilds=" .. table.concat(db.guilds, ", ")) or "")
end

local function GIState(state)
  if conn.giState ~= state then
    conn.giState = state
    Debug("guild info: %s", state)
  end
end

-- The game blocks GetGuildInfoText for addons at times (seen in the live guild as ADDON_ACTION_BLOCKED, once
-- the moment a fight started, which the player gets as "Interface action failed because of an AddOn"; pcall
-- does not catch it). So the text is asked for rarely: at login, when the character's guild changes, when the
-- player types /cl reload, and otherwise every five minutes (sooner while the last read gave nothing). It is
-- never asked for in combat or chat lockdown: a read that was due then is remembered and done after the fight.
local READ_EVERY, RETRY_SOON, BLOCKED_WAIT = 300, 30, 1800
local nextRead, wanted, lastGuild = 0, false, nil
local reading, blocked = false, false   -- set around the call, so a block reported during it is known to be ours
local function InCombat()
  return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end

-- Is a read due? force: the player asked, or we are logging in.
local function Due(force)
  local guild = GetGuildInfo("player")
  if guild ~= lastGuild then lastGuild, wanted = guild, true end   -- another guild's settings must not linger
  return force or wanted or GetTime() >= nextRead
end

-- The game reports a blocked call with this event, while the call is still running.
NS.events.ADDON_ACTION_BLOCKED = function(addon)
  if reading and addon == NS.ADDON then blocked = true end
end

-- The fight is over: do the read that had to wait, a moment later.
NS.events.PLAYER_REGEN_ENABLED = function()
  if wanted then C_Timer.After(2, NS.ReadGuildInfo) end
end

-- The CORELink line out of the Guild Info text, or nil with the reason recorded in conn.giState.
local function FindLine()
  if not IsInGuild() then GIState("not in a guild") return nil end
  reading, blocked = true, false
  local ok, text = pcall(GetGuildInfoText)
  reading = false
  if blocked then
    -- what state the game refuses in is not known yet: keep what was true, and stay away for half an hour
    nextRead = GetTime() + BLOCKED_WAIT
    conn.giState = "blocked by the game"
    Debug("guild info read blocked: lockdown=%s fighting=%s instance=%s",
      tostring(InCombatLockdown and InCombatLockdown()),
      tostring(UnitAffectingCombat and UnitAffectingCombat("player")), tostring(IsInInstance and (IsInInstance())))
    return nil
  end
  if not ok or type(text) ~= "string" or issecret(text) then GIState("not readable") return nil end
  if text == "" then GIState("empty (not received yet, or nothing written)") return nil end
  local i = text:lower():find("corelink:", 1, true)
  if not i then
    GIState("no CORELink: line")
    -- A character that changed guild would otherwise keep the old guild's channel and tag.
    if NS.db.source == "Guild Info" and Configured() then
      NS.LeaveLink()
      NS.db.channel, NS.db.password, NS.db.tag, NS.db.source, NS.db.lastGI = nil, nil, nil, nil, nil
      NS.db.accept = nil
      Print("this guild's Guild Info has no CORELink line; the settings from the previous guild were cleared.")
    end
    return nil
  end
  return (text:sub(i):match("^[^\r\n]*") or ""):gsub("%s+$", "")
end

-- "guilds=" must be last on the line because guild names contain spaces: split it off and parse it.
local function TakeGuildList(line)
  local guildsText = line:match("[%s]guilds=(.*)$")
  local guilds = {}
  for raw in (guildsText or ""):gmatch("[^,]+") do
    local g = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if g ~= "" then guilds[#guilds + 1] = g end
  end
  if guildsText then line = line:sub(1, (line:find("[%s]guilds=") or 0)) end
  return guilds, line
end

-- The accept= list on a line that guilds= was already cut from: { "Eternal", "Deux" }, or nil without the field
-- (every guild is accepted). Written "accept=Eternal,Deux"; spaces, semicolons and brackets around the tags
-- are forgiven, and the list ends at the next key=value field.
local function ReadAccept(line, before)
  local text = line:match("[%s]accept=(.*)$")
  local tags = {}
  for tag in (text or ""):gsub("%s%a+=.*$", ""):gmatch("[^,;%s%[%]]+") do tags[#tags + 1] = tag end
  local now, was = table.concat(tags, ","), table.concat(before or {}, ",")
  if now ~= was then Debug("accept list: %s", now ~= "" and now or "none, every guild is accepted") end
  return #tags > 0 and tags or nil
end

local function ReadFlag(value)
  if value == nil then return false end
  return value:lower() == "on" or value == "1" or value:lower() == "yes"
end

-- Members: pick up the "CORELink: <channel> <password> [tag]" line if it changed.
-- Returns false when the read has to wait for the end of a fight or a lockdown.
function NS.ReadGuildInfo(force)
  local db = NS.db
  if not db or not Due(force) then return end
  if InCombat() or NS.Locked() then
    wanted = true
    GIState("waiting: not read in combat or chat lockdown")
    return false
  end
  wanted = false
  nextRead = GetTime() + RETRY_SOON      -- FindLine makes it longer when the game blocks the read
  local line = FindLine()
  if not line then return end
  nextRead = GetTime() + READ_EVERY
  if line == db.lastGI then GIState("line unchanged") return end   -- keep any local override
  local ch, pw, tag, orank = line:sub(10):match("^[ \t]*([^%s]+)[ \t]+([^%s]+)[ \t]*([^%s]*)[ \t]*([^%s]*)")
  if not ch then GIState("line present but could not be parsed: " .. line:sub(1, 60)) return end
  -- Every version reads the third and fourth words as tag and rank, whatever they are.
  local misplaced = tag:find("=", 1, true) or orank:find("=", 1, true)
  GIState(misplaced and "line read, but a key=value field stands where the tag or officer rank belongs:"
    .. " write the tag (or -) and the rank before it" or "line read")
  db.officerRank = tonumber(orank) or 1
  db.guilds, line = TakeGuildList(line)
  db.echo = ReadFlag(line:match("[%s]echo=(%w+)"))
  db.accept = ReadAccept(line, db.accept)
  local club = line:match("[%s]club=([^%s]+)")
  if club ~= db.club then
    db.club, db.clubId = club, nil          -- the id is resolved from the token when first needed
    NS.ClubChanged()
  end
  db.lastGI = line
  pw = (pw == "-") and "" or Clean(pw)
  tag = (tag ~= "" and tag ~= "-") and Clean(tag):sub(1, 8) or nil
  ch = Clean(ch)
  if ch ~= db.channel or pw ~= db.password or tag ~= db.tag then
    NS.SetConfig(ch, pw, tag, "Guild Info")
    Debug("config from Guild Info: channel=%s tag=%s officerRank=%d", ch, tostring(tag), db.officerRank or 1)
    Print("settings loaded from Guild Info (channel: " .. ch .. ").")
  end
end

---------------------------------------------------------------- copy box
-- Leaders: Blizzard blocks addons from writing Guild Info (protected function), so show the line in a copy
-- box for the leader to paste in by hand. Our own window, because Blizzard's StaticPopup is protected too.
local copyFrame

local function CreateCopyFrame()
  local fr = CreateFrame("Frame", "CORELinkCopyFrame", UIParent, "BackdropTemplate")
  fr:SetSize(440, 100)
  fr:SetPoint("CENTER", 0, 150)
  fr:SetFrameStrata("DIALOG")
  fr:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  fr:SetBackdropColor(0, 0, 0, 0.9)
  fr:EnableMouse(true)
  fr:SetMovable(true)
  fr:RegisterForDrag("LeftButton")
  fr:SetScript("OnDragStart", fr.StartMoving)
  fr:SetScript("OnDragStop", fr.StopMovingOrSizing)

  local t = fr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOP", 0, -14)
  t:SetWidth(400)
  t:SetText("CORELink: press Ctrl+C to copy, then paste into Guild Info")

  local eb = CreateFrame("EditBox", nil, fr, "InputBoxTemplate")
  eb:SetSize(390, 24)
  eb:SetPoint("TOP", 0, -50)
  eb:SetAutoFocus(false)
  eb:SetScript("OnEscapePressed", function() fr:Hide() end)
  eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

  local x = CreateFrame("Button", nil, fr, "UIPanelCloseButton")
  x:SetPoint("TOPRIGHT", -2, -2)

  fr.edit = eb
  return fr
end

function NS.ShowCopyBox(line)
  copyFrame = copyFrame or CreateCopyFrame()
  copyFrame:Show()
  copyFrame.edit:SetText(line)
  copyFrame.edit:SetFocus()
  copyFrame.edit:HighlightText()
end

function NS.Publish()
  if not Configured() then Print("nothing to share yet. Run /cl setup first.") return end
  local line = NS.BuildLine()
  NS.db.lastGI = line
  Print("Guild Info line (paste it into your Guild Info text):")
  Print(line)
  pcall(NS.ShowCopyBox, line)
end
