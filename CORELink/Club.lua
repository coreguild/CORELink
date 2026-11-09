-- CORELink/Club.lua: the Blizzard Community named by "club=" on the Guild Info line.
-- Resolving the token to a club id, its channels (streams), keeping them subscribed, and reading a post's author.
-- Community text reaches addons sealed (a Kstring token), so a guild's tag travels in the channel name: each guild
-- posts into the channel named after its tag when the community has one, and readers take the tag from the
-- channel. Provides NS.club (state), NS.ResolveClubId, NS.ClubIsCharacter, NS.ClubMember, NS.ClubStreams,
-- NS.ClubStream, NS.StreamTag, NS.StreamKey, NS.FocusClubStream, NS.ClubAuthor, NS.ClubChanged.
local _, NS = ...
local Debug, GetTag, Plain, issecret = NS.Debug, NS.GetTag, NS.Plain, NS.issecret

NS.club = { streamId = nil, streams = nil, general = nil, clubType = nil, focused = false }
local club = NS.club

-- The club= token changed: resolve everything again when next needed.
function NS.ClubChanged()
  club.streamId, club.streams, club.focused, club.clubType = nil, nil, false, nil
end

-- "club=" names the community by numeric id, short name or full name (spaces dropped: Core Test -> CoreTest).
-- Names are looked up in the communities this character belongs to, so only members resolve them; that is
-- fine, since only members can post to or read the community anyway.
local function MatchingClub(clubs, want)
  local found
  for _, c in ipairs(clubs) do
    local short, name = c.shortName, c.name
    if type(short) == "string" and not issecret(short) and short:lower() == want
      or type(name) == "string" and not issecret(name) and (name:lower():gsub("%s", "")) == want then
      -- several communities can share a short name: prefer a World of Warcraft (character) community
      if not found or (c.clubType == 1 and found.clubType ~= 1) then found = c end
    end
  end
  return found
end

function NS.ResolveClubId()
  local db = NS.db
  if not db or not db.club then return nil end
  if db.clubId then return db.clubId end
  local n = tonumber(db.club)
  if n then db.clubId = n return n end
  if not C_Club or not C_Club.GetSubscribedClubs then return nil end
  local ok, clubs = pcall(C_Club.GetSubscribedClubs)
  if not ok or type(clubs) ~= "table" then return nil end
  local found = MatchingClub(clubs, db.club:lower())
  if not found then return nil end
  db.clubId = found.clubId
  Debug("community %s is club %s", db.club, tostring(found.clubId))
  return db.clubId
end
local ResolveClubId = NS.ResolveClubId

-- 1 = World of Warcraft (character) community: the community window already shows the character as the
-- author, so posted lines carry only the tag. 0 = Battle.net community: it shows account names, so the
-- character name goes into the text.
function NS.ClubIsCharacter()
  if club.clubType == nil then
    local id = ResolveClubId()
    if id and C_Club and C_Club.GetClubInfo then
      local ok, info = pcall(C_Club.GetClubInfo, id)
      if ok and type(info) == "table" and type(info.clubType) == "number" then club.clubType = info.clubType end
    end
  end
  return club.clubType == 1
end

function NS.ClubMember()
  local id = ResolveClubId()
  if not id or not C_Club or not C_Club.GetClubInfo then return false end
  local ok, info = pcall(C_Club.GetClubInfo, id)
  return ok and info ~= nil
end

function NS.StreamKey(name) return (name:lower():gsub("[%s%-_]", "")) end
local StreamKey = NS.StreamKey

-- A channel counts as a guild channel when its description mentions CORELink, or its name is our tag or a tag
-- we have heard; anything else in the community (an Officers or Raids channel, say) is left alone.
local function IsGuildStream(st, key)
  if not st.leadersAndModeratorsOnly then
    local subject = (type(st.subject) == "string" and not issecret(st.subject)) and st.subject:lower() or ""
    if subject:find("corelink", 1, true) then return true end
    local myTag = GetTag()
    if myTag and key == StreamKey(myTag) then return true end
  end
  for tag in pairs(NS.heard) do if StreamKey(tag) == key then return true end end
  return false
end

-- The community's channels (streams) we use: id -> name. Guilds without a channel use General with the tag
-- in the text.
function NS.ClubStreams()
  if club.streams then return club.streams end
  local id = ResolveClubId()
  if not id or not C_Club or not C_Club.GetStreams then return nil end
  local ok, streams = pcall(C_Club.GetStreams, id)
  if not ok or type(streams) ~= "table" then return nil end
  local map, general, lowest = {}, nil, nil
  for _, st in ipairs(streams) do
    if type(st.streamId) == "number" and type(st.name) == "string" and not issecret(st.name) then
      if st.name == "General" then
        general = st.streamId; map[st.streamId] = st.name
      elseif IsGuildStream(st, StreamKey(st.name)) then
        map[st.streamId] = st.name
      end
      if not lowest or st.streamId < lowest then lowest = st.streamId end
    end
  end
  if lowest then
    if not general then general = lowest; map[lowest] = map[lowest] or "General" end
    club.streams = map
    club.general = general
  end
  return club.streams
end
local ClubStreams = NS.ClubStreams

-- The channel this guild posts into: the one named after our tag, else General.
function NS.ClubStream()
  if club.streamId then return club.streamId end
  local streams = ClubStreams()
  if not streams then return nil end
  local tag = GetTag()
  local best = club.general
  if tag then
    local want = StreamKey(tag)
    for sid, name in pairs(streams) do
      if StreamKey(name) == want then best = sid break end
    end
  end
  club.streamId = best
  return best
end

-- The guild tag a community channel stands for, or nil for General.
function NS.StreamTag(streamId)
  local streams = ClubStreams()
  if not streams or streamId == club.general then return nil end
  return streams[streamId]
end

-- Subscribe to the club streams so CLUB_MESSAGE_ADDED fires for them.
function NS.FocusClubStream()
  if club.focused or not C_Club or not C_Club.FocusStream then return end
  local id = ResolveClubId()
  local streams = ClubStreams()
  if not id or not streams or not NS.ClubMember() then return end
  local all = true
  for sid in pairs(streams) do
    if not pcall(C_Club.FocusStream, id, sid) then all = false end
  end
  if C_Club.FocusCommunityStreams then pcall(C_Club.FocusCommunityStreams) end
  club.focused = all
end

-- The character behind a community post: the message's author record, completed from the member list.
-- WoW communities give the character name, guid and class; Battle.net communities give the account name.
function NS.ClubAuthor(clubId, author)
  local name, guid, classID, role = Plain(author.name), Plain(author.guid), Plain(author.classID), nil
  local mid = Plain(author.memberId)
  if mid and C_Club.GetMemberInfo then
    local ok, m = pcall(C_Club.GetMemberInfo, clubId, mid)
    if ok and type(m) == "table" then
      name = Plain(m.name) or name
      guid = Plain(m.guid) or guid
      classID = classID or Plain(m.classID)
      role = Plain(m.role)
    end
  end
  if name == "" then name = nil end
  return name, guid, classID, role
end

---------------------------------------------------------------- events
local function OnStreamsChanged(clubId)
  if clubId == ResolveClubId() then
    club.streams, club.streamId, club.focused = nil, nil, false
    NS.FocusClubStream()
  end
end
NS.events.CLUB_STREAMS_LOADED = OnStreamsChanged
NS.events.CLUB_STREAM_ADDED = OnStreamsChanged
NS.events.CLUB_STREAM_REMOVED = OnStreamsChanged

NS.events.CLUB_ERROR = function(action, err)
  Debug("community error: action=%s error=%s", tostring(action), tostring(err))
  club.focused = false            -- load the stream again before the next post
end
