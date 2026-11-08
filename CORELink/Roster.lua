-- CORELink/Roster.lua: our own guild's members and the guild addon channel.
-- The roster (ranks, guids, who runs the addon), officer rank labels, nickname sharing, and the dispatcher for
-- packets on the guild addon channel (NICK, NREQ, HEARD here; ECHO, BRIDGE register from their own files).
-- Guild addon messages cross realms, so HEARD reports are how guildmates on other realms tell us what they hear.
-- Provides NS.RefreshRoster, NS.IsGuildmate, NS.OfficerRank, NS.ClassOf, NS.SendGuildAddon, NS.BroadcastNick,
-- NS.BroadcastHeard, NS.HasGuildmatesElsewhere, NS.addonUsers, NS.courierSeen.
local _, NS = ...
local Print, Locked, IsMe, MyName, MyRealm, GetTag = NS.Print, NS.Locked, NS.IsMe, NS.MyName, NS.MyRealm, NS.GetTag
local issecret, SEP = NS.issecret, NS.SEP

local rankNameOf = {}   -- guild member name -> rank name
local rankOf = {}       -- guild member name -> rank index (0 = guild master)
local rosterGuid = {}   -- guild member guid -> name (to recognise guildmates' community posts)
NS.addonUsers = {}      -- guildmate -> last time a CORELink guild message came from them
NS.ADDON_USER_SECS = 900
NS.courierSeen = {}     -- guildmate -> { realm=, t= } from their HEARD reports (courier election)
local coverageWarned = {}   -- tag -> true once we warned that it is not reaching our realm
local lastHeardSent, lastHeardSig = 0, ""

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

function NS.RefreshRoster()
  if not IsInGuild() then return end
  wipe(rankOf); wipe(rankNameOf)
  for i = 1, (GetNumGuildMembers() or 0) do
    local name, rankName, rankIndex, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
    if not name then break end
    name = Ambiguate(name, "none")
    rankOf[name] = rankIndex
    rankNameOf[name] = rankName
    if guid and not issecret(guid) then rosterGuid[guid] = name end
    if NS.me.guid and guid and not issecret(guid) and guid == NS.me.guid then NS.LearnMyName(name) end
  end
end

function NS.IsGuildmate(name, guid)
  if guid and rosterGuid[guid] then return true end
  return name ~= nil and rankOf[name] ~= nil
end

-- The author's guild rank name if they are at or above the officer cutoff, otherwise nil.
function NS.OfficerRank(author)
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

-- HEARD~<realm>~tag1,tag2: a guildmate reports which guild tags it hears on its realm.
NS.guildPackets.HEARD = function(rest, sender)
  local realm, tags = rest:match("^([^" .. SEP .. "]*)" .. SEP .. "(.*)$")
  if not realm or realm == "" then return end
  local now = GetTime()
  NS.guildRealms[realm] = now
  NS.courierSeen[sender] = { realm = realm, t = now }
  for tag in (tags or ""):gmatch("[^,]+") do
    NS.NoteHeard(tag, realm, now)
    -- That guild reaches the guildmate's realm but has not reached ours in 10 minutes: no relay here.
    local reachesUs = NS.heard[tag] and now - NS.heard[tag] < 600
    if realm ~= MyRealm() and tag ~= GetTag() and not coverageWarned[tag] and not reachesUs and now > 600 then
      coverageWarned[tag] = true
      Print(string.format("guild %s is reaching %s but not %s: it has no member running CORELink on your realm."
        .. " /cl guilds for details.", tag, realm, MyRealm()))
    end
  end
end

-- A packet on the guild addon channel: note the sender as an addon user, then hand it to its handler.
function NS.OnGuildAddon(text, sender)
  if issecret(text) or issecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
  sender = Ambiguate(sender, "none")
  NS.addonUsers[sender] = GetTime()
  local cmd, rest = text:match("^(%a+)" .. SEP .. "?(.*)$")
  local handler = cmd and NS.guildPackets[cmd]
  if handler then handler(rest, sender) end
end

-- Tell our guild (across realms) which tags we hear on our realm; at most once a minute, only when it changed
-- or every 5 minutes.
function NS.BroadcastHeard()
  local db = NS.db
  if not db or not db.enabled or not NS.Configured() or not IsInGuild() then return end
  local now, tags = GetTime(), {}
  for tag, t in pairs(NS.heard) do if now - t <= 600 then tags[#tags + 1] = tag end end
  table.sort(tags)
  local sig = table.concat(tags, ",")
  if sig == lastHeardSig and now - lastHeardSent < 300 then return end
  lastHeardSent, lastHeardSig = now, sig
  SendGuildAddon("HEARD" .. SEP .. MyRealm() .. SEP .. sig:sub(1, 200))
end

-- Do we know of guildmates on a realm other than ours? (learned from HEARD reports)
function NS.HasGuildmatesElsewhere()
  local now, mine = GetTime(), MyRealm()
  for realm, t in pairs(NS.guildRealms) do
    if realm ~= mine and now - t <= 600 then return true end
  end
  return false
end

---------------------------------------------------------------- events
local lastRead = 0
NS.events.GUILD_ROSTER_UPDATE = function()
  if GetTime() - lastRead > 5 then
    lastRead = GetTime()
    NS.RefreshRoster()
    NS.ReadGuildInfo()
  end
end
