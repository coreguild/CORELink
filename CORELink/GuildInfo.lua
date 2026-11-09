-- CORELink/GuildInfo.lua: the shared configuration line in Guild Info.
-- "CORELink: <channel> <password|-> [tag|-] [officerRank] [club=..] [echo=on] [guilds=a, b]" is written by the
-- guild master (by hand: addons cannot write Guild Info) and read by every member's client.
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
    .. ((db.guilds and #db.guilds > 0) and (" guilds=" .. table.concat(db.guilds, ", ")) or "")
end

local function GIState(state)
  if conn.giState ~= state then
    conn.giState = state
    Debug("guild info: %s", state)
  end
end

-- The CORELink line out of the Guild Info text, or nil with the reason recorded in conn.giState.
local function FindLine()
  if not IsInGuild() then GIState("not in a guild") return nil end
  local ok, text = pcall(GetGuildInfoText)
  if not ok or type(text) ~= "string" or issecret(text) then GIState("not readable") return nil end
  if text == "" then GIState("empty (not received yet, or nothing written)") return nil end
  local i = text:lower():find("corelink:", 1, true)
  if not i then
    GIState("no CORELink: line")
    -- A character that changed guild would otherwise keep the old guild's channel and tag.
    if NS.db.source == "Guild Info" and Configured() then
      NS.LeaveLink()
      NS.db.channel, NS.db.password, NS.db.tag, NS.db.source, NS.db.lastGI = nil, nil, nil, nil, nil
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

local function ReadFlag(value)
  if value == nil then return false end
  return value:lower() == "on" or value == "1" or value:lower() == "yes"
end

-- Members: pick up the "CORELink: <channel> <password> [tag]" line if it changed.
function NS.ReadGuildInfo()
  local db = NS.db
  if not db then return end
  local line = FindLine()
  if not line then return end
  if line == db.lastGI then GIState("line unchanged") return end   -- keep any local override
  local ch, pw, tag, orank = line:sub(10):match("^[ \t]*([^%s]+)[ \t]+([^%s]+)[ \t]*([^%s]*)[ \t]*([^%s]*)")
  if not ch then GIState("line present but could not be parsed: " .. line:sub(1, 60)) return end
  GIState("line read")
  db.officerRank = tonumber(orank) or 1
  db.guilds, line = TakeGuildList(line)
  db.echo = ReadFlag(line:match("[%s]echo=(%w+)"))
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
