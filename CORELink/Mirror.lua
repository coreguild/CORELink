-- CORELink/Mirror.lua: guild chat to and from the Blizzard Community.
-- Out: the player's own typed guild lines are posted into the community from inside the keypress (Hooks.lua
-- calls MirrorTypedLine), because community sends only work there. In: a post by another guild's member is
-- shown in guild chat like a relayed line, deduplicated against the relay channel.
-- Provides NS.mirror (counters and hook state), NS.MirrorTypedLine, NS.RemindAboutClub.
local _, NS = ...
local Print, Debug, Configured, IsMe, GetTag, MyName = NS.Print, NS.Debug, NS.Configured, NS.IsMe, NS.GetTag, NS.MyName
local issecret, club = NS.issecret, NS.club
local ResolveClubId, ClubStreams, StreamTag, StreamKey = NS.ResolveClubId, NS.ClubStreams, NS.StreamTag, NS.StreamKey

NS.mirror = {
  hooks = "not installed", posted = 0, failed = 0, shown = 0, skipped = 0, hidden = 0,
  reminded = false, lastText = nil, lastAt = 0,
}
local mirror = NS.mirror

---------------------------------------------------------------- posting
local function ClubLine(text, stream)
  local db = NS.db
  local tag = GetTag() or "?"
  local me = MyName()
  local nick = (db.showNick ~= false) and db.nicks[me] or nil
  local tagChannel = StreamTag(stream) ~= nil      -- our own channel: the tag is the channel name
  if NS.ClubIsCharacter() then
    -- the rank and nickname travel in the text: readers cannot inspect community text, but they can draw it
    return (tagChannel and "" or ("[" .. tag .. "] ")) .. NS.RankNickPrefix(NS.OfficerRankName(me), nick) .. text
  end
  return string.format("[%s] %s%s: %s", tag, me, nick and (" (" .. nick .. ")") or "", text)
end

-- Called from the chat hooks, i.e. inside the keypress that sent the guild line. Two hooks can fire for
-- one line (edit box and SendChatMessage), so the same text within a second is posted once.
function NS.MirrorTypedLine(text)
  local db = NS.db
  if not db or db.mirror == false or not Configured() then return end
  if text == mirror.lastText and GetTime() - mirror.lastAt < 1 then return end
  mirror.lastText, mirror.lastAt = text, GetTime()
  local id = ResolveClubId()
  if not id or not C_Club or not C_Club.SendMessage or not NS.ClubMember() then return end
  local stream = NS.ClubStream()
  if not stream then return end
  NS.FocusClubStream()              -- posting fails with "Couldn't send message" until the stream is loaded
  local ok, err = pcall(C_Club.SendMessage, id, stream, ClubLine(text, stream):sub(1, 250))
  if ok then mirror.posted = mirror.posted + 1 return end
  mirror.failed = mirror.failed + 1
  club.focused = false
  Debug("mirror failed: %s", tostring(err))
end

function NS.RemindAboutClub()
  local db = NS.db
  if mirror.reminded or not db or not db.club or db.mirror == false then return end
  if not C_Club then return end
  mirror.reminded = true
  NS.FocusClubStream()
  if not NS.ClubMember() then
    Print("your guild mirrors chat into community " .. db.club .. " but this character is not a member"
      .. (ResolveClubId() and "" or " (or no community you belong to has that name)")
      .. ". Ask the Guild Master for the invite link; linked guilds' lines then show in your guild chat.")
  end
end

---------------------------------------------------------------- reading
-- Officer colour for a community author. The relay packet is authoritative when we have heard one from this
-- character; otherwise (community only) a community role of Owner, Leader or Moderator counts.
local function ClubOfficerLabel(who, role)
  if not NS.db or NS.db.officer == false then return nil end
  if NS.authorSeen[who] then return NS.authorOfficer[who] end
  if type(role) == "number" and role >= 1 and role <= 3 then return "Officer" end
  return nil
end

local CLUB_LINE_FULL = "^%[([^%]]+)%] ([^:(]+)%s?%(?([^):]*)%)?: (.*)$"   -- [TAG] Name (nick): text
local CLUB_LINE_TAG = "^%[([^%]]+)%] (.*)$"                                -- [TAG] text

-- tag, name, nick, text and channelTag read from a post. Community text may be sealed (drawable, not
-- readable): then only the channel can say which guild it is. Community text reaches addons as a Kstring
-- placeholder ("|Kw158|k", measured 2026-10-13 on Forever): the chat frame draws the real text, the addon holds
-- only this client-local token. Not a secret value, but unreadable all the same, and meaningless on any other
-- client, so it cannot be forwarded.
local function ParseClubLine(content, streamId)
  local sealed = type(content) ~= "string" or issecret(content) or content:match("^|K.*|k$") ~= nil
  local channelTag = StreamTag(streamId)
  if channelTag then return channelTag, nil, nil, nil, channelTag end   -- the channel is the guild
  if sealed then return nil, nil, nil, nil, nil end
  local okp, t, a, b, c = pcall(string.match, content, CLUB_LINE_FULL)
  if okp and t then return t, (a:gsub("%s+$", "")), b, c, nil end
  okp, t, a = pcall(string.match, content, CLUB_LINE_TAG)
  if okp and t then return t, nil, nil, a, nil end
  return nil, nil, nil, nil, nil
end

local function ClassToken(classID)
  if classID and GetClassInfo then
    local okc, _, token = pcall(GetClassInfo, classID)
    if okc and type(token) == "string" then return token end
  end
  return nil
end

-- A post in a guild's own community channel: the channel names the guild, the text stays as posted.
local function ShowChannelPost(line)
  local now = GetTime()
  NS.heard[line.tag] = now
  if NS.CrossSeen(line.who, "club") then mirror.skipped = mirror.skipped + 1 return end
  mirror.shown = mirror.shown + 1
  NS.Display(line.tag, line.who, line.class, line.content, line.label, line.nick, true)
end

-- A readable "[TAG] ..." post in General: deduplicated against the relay by hash. A post with no tag at all
-- shows under the author's name only.
local function ShowGeneralPost(line)
  local now = GetTime()
  if not line.tag then
    if NS.CrossSeen(line.who, "club") then mirror.skipped = mirror.skipped + 1 return end
    mirror.shown = mirror.shown + 1
    NS.Display(nil, line.who, line.class, line.content, line.label, line.nick, true)
    return
  end
  local id = NS.Hash(line.tag .. line.who .. line.msg)
  if NS.displayed[id] then return end                         -- already shown from the relay channel
  NS.displayed[id] = now; NS.seen[id] = now
  NS.heard[line.tag] = now
  NS.CrossSeen(line.who, "club")
  mirror.shown = mirror.shown + 1
  -- "[TAG] text" lines (WoW community) already carry "(Rank Nick)" in the text; the full format does not
  NS.Display(line.tag, line.who, line.class, line.msg, line.label, line.nick, line.pname == nil)
end

-- The post's record, or nil when it is not one we read (wrong club or channel, deleted, our own).
local function FetchClubMessage(clubId, streamId, messageId)
  if not NS.db or NS.db.mirrorRead == false or clubId ~= ResolveClubId() then return nil end
  local streams = ClubStreams()
  if not streams or not streams[streamId] then return nil end
  if not C_Club or not C_Club.GetMessageInfo then return nil end
  local ok, info = pcall(C_Club.GetMessageInfo, clubId, streamId, messageId)
  if not ok or type(info) ~= "table" or info.content == nil or info.destroyed then return nil end
  if (info.author or {}).isSelf == true then return nil end
  return info
end

-- A message arrived in the club: show it in guild chat unless it is ours, our own guild's, muted, or already
-- shown from the relay channel. The author record can lag the message by a moment, so an authorless message
-- is retried a few times.
local CLUB_RETRY = { 0.5, 1, 2 }
local function OnClubMessage(clubId, streamId, messageId, attempt)
  local info = FetchClubMessage(clubId, streamId, messageId)
  if not info then return end
  local name, guid, classID, role = NS.ClubAuthor(clubId, info.author or {})
  if not name and not guid then
    attempt = (attempt or 0) + 1
    if CLUB_RETRY[attempt] then
      C_Timer.After(CLUB_RETRY[attempt], function() OnClubMessage(clubId, streamId, messageId, attempt) end)
      return
    end
  end
  if (guid and NS.me.guid and guid == NS.me.guid) or (name and IsMe(name, guid)) then return end
  if NS.IsGuildmate(name, guid) then return end          -- our own guild: already in our guild chat
  local tag, pname, nick, msg, channelTag = ParseClubLine(info.content, streamId)
  local who = pname or name or "?"
  local line = {
    tag = tag, who = who, content = info.content, msg = msg, pname = pname,
    class = ClassToken(classID) or NS.authorClass[who] or "",
    label = ClubOfficerLabel(who, role),
    nick = (nick and nick ~= "" and nick) or NS.authorNick[who],
  }
  local myTag = GetTag()
  if tag and ((myTag and StreamKey(tag) == StreamKey(myTag)) or NS.db.muted[tag:lower()]) then return end
  if channelTag then ShowChannelPost(line) else ShowGeneralPost(line) end
end
NS.events.CLUB_MESSAGE_ADDED = function(clubId, streamId, messageId) OnClubMessage(clubId, streamId, messageId) end

---------------------------------------------------------------- chat filter
-- The community also appears as a normal chat channel ("Community:<club>:<stream>") when it is checked in a
-- chat window. While we show its lines in guild chat, hide the raw copies so nobody reads everything twice.
local function IsClubChannel(name)
  if type(name) ~= "string" or issecret(name) then return false end
  local c, st = name:match("^[Cc]ommunity:(%d+):(%d+)")
  if not c then return false end
  local id, streams = ResolveClubId(), ClubStreams()
  return id ~= nil and tonumber(c) == id and (streams == nil or streams[tonumber(st)] ~= nil)
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_COMMUNITIES_CHANNEL",
  function(_, _, _, _, _, channelString, _, _, _, _, channelBaseName)
    local db = NS.db
    if not db or db.mirrorRead == false or db.hideClub == false then return false end
    if IsClubChannel(channelString) or IsClubChannel(channelBaseName) then
      mirror.hidden = mirror.hidden + 1
      return true
    end
    return false
  end)
