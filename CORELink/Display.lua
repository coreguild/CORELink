-- CORELink/Display.lua: how another guild's line is drawn in guild chat, and the dedupe between the two paths
-- a line can arrive by (relay channel and community). Also the guild chat filter that colours officers.
-- Provides NS.Display, NS.CrossSeen, NS.GuildFrames.
local _, NS = ...
local BuildTag, HexToRGB = NS.BuildTag, NS.HexToRGB
local issecret = NS.issecret

-- A line can reach us twice: on the relay channel (readable) and in the community (text sealed, so it cannot
-- be hashed). Each displayed line is remembered by author and time; the other path's copy within a few
-- seconds is dropped.
local recentFrom = {}   -- author -> { { t = time, via = "relay"|"club" }, ... }
local CROSS_SECS = 5

-- Did the other delivery path show a line from this author in the last few seconds? Consumes the match.
function NS.CrossSeen(author, via)
  local list = recentFrom[author]
  local t = GetTime()
  if list then
    for i = #list, 1, -1 do
      local e = list[i]
      if t - e.t > CROSS_SECS then table.remove(list, i)
      elseif e.via ~= via and not e.used then e.used = true return true end
    end
  else
    list = {}; recentFrom[author] = list
  end
  list[#list + 1] = { t = t, via = via }
  return false
end

-- Chat windows that have Guild messages enabled (so bridged lines appear in the same tab as /g).
-- Override with /cl window <n>.
function NS.GuildFrames()
  if NS.db.window then
    local f = _G["ChatFrame" .. NS.db.window]
    if f then return { f } end
  end
  local frames = {}
  local get = GetChatWindowMessages or (C_ChatInfo and C_ChatInfo.GetChatWindowMessages)
  if get then
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
      local f = _G["ChatFrame" .. i]
      if f then
        local ok, groups = pcall(function() return { get(i) } end)
        if ok and type(groups) == "table" then
          for _, g in ipairs(groups) do
            if g == "GUILD" then frames[#frames + 1] = f break end
          end
        end
      end
    end
  end
  if #frames == 0 then frames[1] = DEFAULT_CHAT_FRAME end
  return frames
end

local function ClassColoured(name, class)
  if NS.db.classColor == false or not class or class == "" then return name end
  local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if not cc then return name end
  return string.format("|cff%02x%02x%02x%s|r", math.floor(cc.r * 255 + 0.5), math.floor(cc.g * 255 + 0.5),
    math.floor(cc.b * 255 + 0.5), name)
end

-- "[TAG] [Author]: (Rank Nick) text" in guild colour, officer colour when the author is an officer.
-- textHasPrefix: the text already carries "(Rank Nick)" (community lines), so none is added.
function NS.Display(tag, author, class, msg, officerLabel, nick, textHasPrefix)
  local db = NS.db
  local c = ChatTypeInfo["GUILD"] or { r = .25, g = 1, b = .25 }
  local prefix = textHasPrefix and "" or BuildTag(officerLabel, (db.showNick ~= false) and nick or nil)
  if officerLabel then
    local r, g, b = HexToRGB(db.officerColorHex)
    c = { r = r, g = g, b = b }
  end
  local name = ClassColoured("[" .. author .. "]", class)
  -- msg may be sealed community text: it can be concatenated and drawn, but not formatted or inspected
  local line = (tag and ("[" .. tag .. "] ") or "") .. "|Hplayer:" .. author .. "|h" .. name .. "|h: " .. prefix .. msg
  for _, f in ipairs(NS.GuildFrames()) do
    f:AddMessage(line, c.r, c.g, c.b)
  end
end

---------------------------------------------------------------- guild chat filter
-- Recolour officers' messages in real guild chat (this client only), add nicknames, hide echoed copies.
ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", function(_, _, msg, author, ...)
  local db = NS.db
  if not db or issecret(msg) or issecret(author) or type(msg) ~= "string" or type(author) ~= "string" then
    return false
  end
  local who = Ambiguate(author, "none")
  if NS.IsEchoLine(msg, who) then NS.echoStats.hidden = NS.echoStats.hidden + 1 return true end
  local nick = (db.showNick ~= false) and db.nicks[who] or nil
  local rn = NS.OfficerRank(who)
  local tagText = BuildTag(rn, nick)
  if rn then
    return false, "|cff" .. (db.officerColorHex or NS.DEFAULT_OFFICER_COLOR) .. tagText .. msg .. "|r", author, ...
  end
  if tagText ~= "" then return false, tagText .. msg, author, ... end
  return false
end)
