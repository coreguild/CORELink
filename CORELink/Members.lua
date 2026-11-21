-- CORELink/Members.lua: /cl members. Who is in the link channel right now, grouped by guild.
-- The game prints a channel's member list only in a chat window that shows the channel, and the addon keeps the
-- link channel out of every window, so /chatlist shows nothing. This asks for the list and reads the answer
-- (CHAT_MSG_CHANNEL_LIST) itself.
-- A member's guild is known for our own roster and for confirmed peers: addon users in other guilds who spoke
-- on the link or answered a hello. A name only gossiped to us (DIR) is not known. Members who are not known,
-- and peers not heard lately or known by tag only, are greeted, so the next run has what their addon answers.
-- A player without the addon stays under "guild not known".
-- Provides the members command.
local _, NS = ...
local Print, Debug = NS.Print, NS.Debug
local WAIT = 1.5              -- seconds to collect the list, which can arrive in more than one event
local GREET_MAX = 8           -- hellos per run: they share the whisper queue with carried lines (4 a second)
local pending                 -- { names = set, events = n, channel =, frame = reply window } while collecting

local function Text(v) return type(v) == "string" and not NS.issecret(v) and v ~= "" end

-- A channel member -> group key, guild name if known, and whether to greet them for fresher or fuller word.
local function GuildOf(name)
  if NS.IsMe(name) or NS.IsGuildmate(name) then return NS.GetTag() or "?", (GetGuildInfo("player")), false end
  local short, now = NS.PeerName(name), GetTime()
  for key, p in pairs(NS.peers) do
    if p.seen > 0 and NS.PeerName(key) == short then
      local named = p.guild ~= nil and p.guild ~= ""
      return p.tag, named and p.guild or nil, not named or not NS.LivePeer(p, now)
    end
  end
  return nil, nil, true
end

-- Sorted names -> group keys in order, key -> { label =, names }, the members of no known guild, who to greet.
local function Group(names)
  local order, groups, unknown, greet = {}, {}, {}, {}
  for _, name in ipairs(names) do
    local key, guild, ask = GuildOf(name)
    if ask then greet[#greet + 1] = name end
    if not key then
      unknown[#unknown + 1] = name
    else
      if not groups[key] then groups[key] = { label = "<" .. key .. ">" }; order[#order + 1] = key end
      if guild and guild ~= "" then groups[key].label = guild end
      table.insert(groups[key], name)
    end
  end
  table.sort(order, function(a, b) return groups[a].label < groups[b].label end)
  return order, groups, unknown, greet
end

-- Greet up to GREET_MAX of them (one hello per player per ten minutes). Returns how many, and why none.
local function Greet(names)
  if NS.db and NS.db.whisper == false then return 0, "whispers are off (/cl whisper on)" end
  if not NS.WhisperAvailable() then return 0, "whispers are not available right now" end
  local sent = 0
  for _, name in ipairs(names) do
    if sent >= GREET_MAX then break end
    if NS.Hello(name) then sent = sent + 1 end
  end
  return sent, "they were greeted in the last ten minutes"
end

local function Show(req, names)
  if #names == 0 then
    Print("no member list arrived for " .. req.channel .. " in " .. WAIT .. " seconds. The game holds it back in"
      .. " chat lockdown and can be slow; try again.")
    return
  end
  local order, groups, unknown, greet = Group(names)
  local lines = { string.format("%d in %s", #names, req.channel) }
  for _, key in ipairs(order) do
    local g = groups[key]
    lines[#lines + 1] = string.format("%s (%d): %s", g.label, #g, table.concat(g, ", "))
  end
  if #unknown > 0 then
    lines[#lines + 1] = string.format("guild not known (%d): %s", #unknown, table.concat(unknown, ", "))
  end
  for _, line in ipairs(lines) do Print(line) end
  if #greet > 0 then
    local sent, why = Greet(greet)
    Print(sent > 0 and string.format("greeted %d of %d member(s) to ask their guild; one who runs CORELink"
      .. " answers. Run /cl members again in a few seconds.", sent, #greet)
      or string.format("%d member(s) could be asked their guild, but %s.", #greet, why))
  end
  pcall(NS.ShowCopyBox, table.concat(lines, " | "), "CORELink: press Ctrl+C to copy the member list")
end

local function Finish()
  local req = pending
  pending = nil
  if not req then return end
  local names = {}
  for name in pairs(req.names) do names[#names + 1] = name end
  table.sort(names)
  Debug("members: %d name(s) in %d list event(s)", #names, req.events)
  NS.replyFrame = req.frame
  local ok, err = pcall(Show, req, names)
  NS.replyFrame = nil
  if not ok then error(err, 0) end
end

-- The list arrives as "Name One, *Name Two, ..." (marks in front of the owner and moderators), in one event or
-- several. Only read while /cl members waits for it. An event that names another channel is not ours.
NS.events.CHAT_MSG_CHANNEL_LIST = function(text, _, _, channelString, _, _, _, _, channelBaseName)
  if not pending or not Text(text) then return end
  local a, b = Text(channelString) and channelString or nil, Text(channelBaseName) and channelBaseName or nil
  if (a or b) and not (NS.IsLinkChannel(a) or NS.IsLinkChannel(b)) then return end
  pending.events = pending.events + 1
  if pending.events == 1 then Debug("members: first list event starts '%s'", text:sub(1, 40)) end
  for raw in text:gmatch("[^,]+") do
    local name = raw:match("^%s*%p*(.-)%s*$")
    if name ~= "" then pending.names[Ambiguate and Ambiguate(name, "none") or name] = true end
  end
end

NS.commands.members = function()
  local id = NS.ChannelId()
  if not id then Print("not in the link channel right now. /cl reload to retry, /cl for the status.") return end
  if not ListChannelByName then Print("this client cannot list a channel's members.") return end
  if pending then return end
  pending = { names = {}, events = 0, channel = NS.db.channel, frame = NS.replyFrame }
  C_Timer.After(WAIT, Finish)
  Debug("members: asked the game for the members of channel %d", id)
  if not pcall(ListChannelByName, id) then
    pending = nil
    Print("the game refused to list the channel's members.")
  end
end
