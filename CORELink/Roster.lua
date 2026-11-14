-- CORELink/Roster.lua: our own guild's members and the guild addon channel.
-- The roster (ranks, guids, our own full name), officer rank labels, nickname sharing, presence (who in the
-- guild runs the addon, which elects the courier), and the dispatcher for packets on the guild addon channel
-- (NICK, NREQ, PRESENT here; LINE registers from Relay.lua). Guild addon messages cross realms.
-- Provides NS.RefreshRoster, NS.LearnMyNameFromRoster, NS.IsGuildmate, NS.OfficerRankName, NS.ClassOf,
-- NS.SendGuildAddon, NS.BroadcastNick, NS.SendPresence, NS.IsAddonUser, NS.OnGuildAddon, NS.addonUsers.
local _, NS = ...
local Locked, IsMe, MyName, SEP = NS.Locked, NS.IsMe, NS.MyName, NS.SEP
local issecret = NS.issecret

local rankNameOf = {}   -- guild member name -> rank name
local rankOf = {}       -- guild member name -> rank index (0 = guild master)
local rosterGuid = {}   -- guild member guid -> name (to recognise guildmates' community posts)
NS.addonUsers = {}      -- guildmate -> last time a CORELink guild message came from them
NS.ADDON_USER_SECS = 900
local lastNameLookup = -100

function NS.ClassOf(author, guid)
  if guid and not issecret(guid) and GetPlayerInfoByGUID then
    local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
    if ok and type(class) == "string" then return class end
  end
  if IsMe(author, guid) then
    local _, class = UnitClass("player")
    return class or ""
  end
  return ""
end

-- Forget the saved nicknames of members who left the guild. Only called after a complete roster read; our own
-- nickname stays whatever the roster says (it may be saved under the short name until the full one is known).
local function PruneNicks()
  local nicks = NS.db and NS.db.nicks
  if not nicks then return end
  local short = UnitName("player")
  for name in pairs(nicks) do
    if rankOf[name] == nil and name ~= NS.me.name and name ~= short then nicks[name] = nil end
  end
end

-- Read the roster: ranks, guids, and our own full name when our GUID is in it. False when it was empty.
function NS.RefreshRoster()
  if not IsInGuild() then return false end
  local n = GetNumGuildMembers() or 0
  if n == 0 then return false end
  wipe(rankOf); wipe(rankNameOf)
  local read = 0
  for i = 1, n do
    local name, rankName, rankIndex, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
    if not name then break end
    read = read + 1
    name = Ambiguate(name, "none")
    rankOf[name] = rankIndex
    rankNameOf[name] = rankName
    if guid and not issecret(guid) then rosterGuid[guid] = name end
    if NS.me.guid and guid and not issecret(guid) and guid == NS.me.guid then NS.LearnMyName(name) end
  end
  if read == n then PruneNicks() end   -- a roster that stopped short says nothing about who left
  return true
end

-- Called by NS.MyName while our full name is unknown: look ourselves up by GUID, at most every 5 seconds.
function NS.LearnMyNameFromRoster()
  if GetTime() - lastNameLookup < 5 then return end
  lastNameLookup = GetTime()
  NS.RefreshRoster()
end

function NS.IsGuildmate(name, guid)
  if guid and rosterGuid[guid] then return true end
  return name ~= nil and rankOf[name] ~= nil
end

-- The author's guild rank name if they are at or above the officer cutoff, otherwise nil.
function NS.OfficerRankName(author)
  local db = NS.db
  if not db or db.officer == false then return nil end
  local rank, rankName
  if IsMe(author) then
    local _, rn, r = GetGuildInfo("player")
    rank, rankName = r, rn
  else
    rank, rankName = rankOf[author], rankNameOf[author]
  end
  if rank == nil or rank > (db.officerRank or 1) then return nil end
  rankName = (type(rankName) == "string" and rankName ~= "") and rankName or "Officer"
  return (rankName:gsub("[~|]", "")):sub(1, 20)
end

---------------------------------------------------------------- guild addon channel
function NS.SendGuildAddon(text)
  if not IsInGuild() or Locked() then return end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    pcall(C_ChatInfo.SendAddonMessage, NS.PREFIX, text, "GUILD")
  end
end
local SendGuildAddon = NS.SendGuildAddon

function NS.BroadcastNick()
  SendGuildAddon("NICK" .. SEP .. (NS.db.nicks[MyName()] or ""))
end

-- PRESENT~<version>: I run the addon. Sent at login and every two minutes; it is what elects the courier.
function NS.SendPresence()
  if not NS.db or not NS.db.enabled then return end
  SendGuildAddon("PRESENT" .. SEP .. NS.Version())
end

-- A guildmate who sent a CORELink guild message within the window (or ourselves).
function NS.IsAddonUser(name, withinSecs)
  if IsMe(name) then return true end
  local t = NS.addonUsers[name]
  return t ~= nil and GetTime() - t <= (withinSecs or NS.ADDON_USER_SECS)
end

NS.guildPackets.PRESENT = function() end   -- the sender was noted as an addon user by the dispatcher

-- NICK~<name>: a guildmate's nickname (empty clears it).
NS.guildPackets.NICK = function(rest, sender)
  local n = NS.CleanNick(rest)
  NS.db.nicks[sender] = (n ~= "") and n or nil
end

-- NREQ: a guildmate asks everyone to re-send their nickname.
NS.guildPackets.NREQ = function(_, sender)
  if not IsMe(sender) and NS.db.nicks[MyName()] then
    C_Timer.After(1 + math.random() * 6, NS.BroadcastNick)
  end
end

-- A packet on the guild addon channel: note the sender as an addon user, then hand it to its handler.
function NS.OnGuildAddon(text, sender)
  if issecret(text) or issecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
  if not NS.db then return end               -- the handlers read settings
  sender = Ambiguate(sender, "none")
  NS.addonUsers[sender] = GetTime()
  local cmd, rest = text:match("^(%a+)" .. SEP .. "?(.*)$")
  local handler = cmd and NS.guildPackets[cmd]
  if handler then handler(rest, sender) end
end

---------------------------------------------------------------- events
local lastRead = 0
NS.events.GUILD_ROSTER_UPDATE = function()
  if GetTime() - lastRead > 5 then
    if NS.RefreshRoster() then lastRead = GetTime() end   -- an empty roster does not use up the throttle
    NS.ReadGuildInfo()
  end
end

C_Timer.NewTicker(120, NS.SendPresence)
