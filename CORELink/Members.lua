-- CORELink/Members.lua: /cl members. Who is in the link channel right now, grouped by guild.
-- The game prints a channel's member list only in a chat window that shows the channel, and the addon keeps the
-- link channel out of every window, so /chatlist shows nothing. This asks for the list and reads the answer
-- (CHAT_MSG_CHANNEL_LIST) itself.
-- A member's guild is known for our own roster and for peers: addon users in other guilds who spoke on the link
-- or answered a hello. Anyone else is greeted, so an addon user among them is known on the next run. A player
-- without the addon stays under "guild not known".
-- Provides the members command.
local _, NS = ...
local Print, Debug = NS.Print, NS.Debug
local WAIT = 1.5              -- seconds to collect the list, which can arrive in more than one event
local GREET_MAX = 20          -- hellos sent per run to members whose guild is not known
local pending                 -- { names = set, frame = the window the command was typed in } while collecting

-- The guild a channel member is in, as far as this client knows; nil when it does not.
local function GuildOf(name)
  if NS.IsMe(name) or NS.IsGuildmate(name) then return (GetGuildInfo("player")) or "your guild" end
  local short = NS.PeerName(name)
  for key, p in pairs(NS.peers) do
    if NS.PeerName(key) == short then return (p.guild and p.guild ~= "") and p.guild or ("<" .. p.tag .. ">") end
  end
  return nil
end

-- Sorted names -> guild names in order of first appearance, guild -> its members, and the members left over.
local function Group(names)
  local order, groups, unknown = {}, {}, {}
  for _, name in ipairs(names) do
    local guild = GuildOf(name)
    if not guild then
      unknown[#unknown + 1] = name
    else
      if not groups[guild] then groups[guild] = {}; order[#order + 1] = guild end
      table.insert(groups[guild], name)
    end
  end
  table.sort(order)
  return order, groups, unknown
end

-- Greet members whose guild is not known; an addon user among them answers with their guild. Returns how many.
local function Greet(unknown)
  local sent = 0
  if not NS.WhisperAvailable() or (NS.db and NS.db.whisper == false) then return 0 end
  for _, name in ipairs(unknown) do
    if sent >= GREET_MAX then break end
    if NS.Hello(name) then sent = sent + 1 end
  end
  return sent
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
  if #names == 0 then
    Print("the game sent no member list for " .. tostring(NS.db.channel) .. ". Try again in a few seconds.")
    NS.replyFrame = nil
    return
  end
  local order, groups, unknown = Group(names)
  local lines = { string.format("%d in %s", #names, NS.db.channel) }
  for _, guild in ipairs(order) do
    lines[#lines + 1] = string.format("%s (%d): %s", guild, #groups[guild], table.concat(groups[guild], ", "))
  end
  if #unknown > 0 then
    lines[#lines + 1] = string.format("guild not known (%d): %s", #unknown, table.concat(unknown, ", "))
  end
  for _, line in ipairs(lines) do Print(line) end
  local greeted = Greet(unknown)
  if greeted > 0 then
    Print(greeted .. " of them greeted: one who runs CORELink answers with their guild. Run /cl members again"
      .. " in a few seconds; whoever is still not known has no addon or did not answer.")
  end
  NS.replyFrame = nil
  pcall(NS.ShowCopyBox, table.concat(lines, " | "))
end

-- The list arrives as "Name One, *Name Two, ..." (marks in front of the owner and moderators), in one event or
-- several. Only read while /cl members waits for it.
NS.events.CHAT_MSG_CHANNEL_LIST = function(text, _, _, channelString, _, _, _, _, channelBaseName)
  if not pending or NS.issecret(text) or type(text) ~= "string" then return end
  local named = (channelString and channelString ~= "") or (channelBaseName and channelBaseName ~= "")
  if named and not (NS.IsLinkChannel(channelString) or NS.IsLinkChannel(channelBaseName)) then return end
  pending.events = pending.events + 1
  if pending.events == 1 then Debug("members: first list event starts '%s'", text:sub(1, 40)) end
  for raw in text:gmatch("[^,]+") do
    local name = raw:match("^%s*%p*(.-)%s*$")
    if name ~= "" then pending.names[name] = true end
  end
end

NS.commands.members = function()
  local id = NS.ChannelId()
  if not id then Print("not in the link channel right now. /cl reload to retry, /cl for the status.") return end
  if not ListChannelByName then Print("this client cannot list a channel's members.") return end
  if pending then return end
  pending = { names = {}, events = 0, frame = NS.replyFrame }
  Debug("members: asked the game for the members of channel %d", id)
  ListChannelByName(id)
  C_Timer.After(WAIT, Finish)
end
