-- CORELink/Channel.lua: the hidden custom chat channel that carries addon users' own lines, as text.
-- Joining and hiding it, the game's notices about it (including a refusal), the text send that the chat hooks
-- call from inside a keypress, and the drain of the whisper queue.
-- Provides NS.conn (connection diagnostics), NS.ChannelId, NS.EnsureChannel, NS.LeaveLink, NS.IsLinkChannel,
-- NS.SetConfig, NS.SendChannelText, NS.ClearJoinHold.
local _, NS = ...
local Print, Debug, Configured, Locked = NS.Print, NS.Debug, NS.Configured, NS.Locked
local issecret = NS.issecret

-- Connection diagnostics: what the game told us about the link channel, and whether joining is on hold.
NS.conn = {
  giState = "not read yet", lastNotice = nil, lastNoticeAt = nil, joinAttempts = 0,
  blockedUntil = 0, blockedWhy = nil, lastSendResult = nil, lastSendAt = -100, refusedAt = -1000,
  lastJoinAt = -100, passwordAnswers = 0, passwordCapTold = false,
}
local conn = NS.conn
local JOIN_BLOCK_SECS = 600   -- after WRONG_PASSWORD / BANNED, stop retrying for this long (or until /cl reload)
local PASSWORD_ANSWER_CAP = 3  -- password prompts answered from the config between two successful joins
local WHISPERS_PER_SECOND = 4

local function HideChannel()
  if not Configured() then return end
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local f = _G["ChatFrame" .. i]
    if f then ChatFrame_RemoveChannel(f, NS.db.channel) end
  end
end

function NS.ChannelId()
  if not Configured() then return nil end
  local id = GetChannelName(NS.db.channel)
  return (id and id > 0) and id or nil
end
local ChannelId = NS.ChannelId

local function JoinWithPassword()
  local db = NS.db
  conn.joinAttempts, conn.lastJoinAt = conn.joinAttempts + 1, GetTime()
  Debug("joining channel %s (attempt %d, password %s)", db.channel, conn.joinAttempts,
    db.password ~= "" and "set" or "none")
  local ok, err = pcall(JoinChannelByName, db.channel, (db.password ~= "" and db.password) or nil)
  if not ok then Debug("JoinChannelByName errored: %s", tostring(err)) end
end

function NS.EnsureChannel()
  local db = NS.db
  if not db.enabled or not Configured() or Locked() then return end
  if not ChannelId() then
    if GetTime() < conn.blockedUntil then
      Debug("join of %s on hold (%s); /cl reload to retry now", db.channel, tostring(conn.blockedWhy))
      return
    end
    JoinWithPassword()
  end
  C_Timer.After(1, HideChannel)
end

function NS.LeaveLink()
  if ChannelId() then LeaveChannelByName(NS.db.channel) end
end

function NS.IsLinkChannel(name)
  if not name or issecret(name) or not Configured() then return false end
  return name:lower():find(NS.db.channel:lower(), 1, true) ~= nil
end
local IsLinkChannel = NS.IsLinkChannel

local JOIN_FAILURE_TEXT = {
  WRONG_PASSWORD = "wrong channel password. Ask the Guild Master to check the CORELink line in Guild Info",
  BANNED = "you are banned from that channel",
  TOO_MANY_CHANNELS = "you are in too many chat channels; leave one",
}

-- The server refused something we sent on the channel a moment ago: say so, at most every 10 minutes.
local function OnRefusal()
  if GetTime() - conn.lastSendAt > 3 then return end
  conn.lastSendResult = "refused"
  if GetTime() - conn.refusedAt < 600 then return end
  conn.refusedAt = GetTime()
  Print("the server refused your line on " .. tostring(NS.db.channel) .. " (NOT_ALLOWED_IN_CHANNEL)."
    .. " Linked guilds did not get it. Run /cl report and share it.")
end

-- Stop joining for ten minutes and tell the player why; /cl reload or a successful join ends it.
local function HoldJoin(why, text)
  conn.blockedUntil, conn.blockedWhy = GetTime() + JOIN_BLOCK_SECS, why
  Print("could not join " .. tostring(NS.db.channel) .. ": " .. text
    .. ". /cl reload to retry, /cl report for details.")
end

-- The join works again or the player asked for a retry: no hold, and password prompts are answered again.
function NS.ClearJoinHold()
  conn.blockedUntil, conn.blockedWhy = 0, nil
  conn.passwordAnswers, conn.passwordCapTold = 0, false
end

-- Notices the game sends about channels: joined, left, wrong password, banned, refused ...
local function OnChannelNotice(notice, channelName, channelBaseName)
  if issecret(notice) or type(notice) ~= "string" then return end
  if not (IsLinkChannel(channelName) or IsLinkChannel(channelBaseName)) then return end
  conn.lastNotice, conn.lastNoticeAt = notice, (date and date("%H:%M:%S")) or ""
  Debug("channel notice for %s: %s", tostring(NS.db.channel), notice)
  if notice == "NOT_ALLOWED_IN_CHANNEL" then OnRefusal() return end
  if notice == "YOU_CHANGED" or notice == "YOU_JOINED" then NS.ClearJoinHold() return end
  if notice == "WRONG_PASSWORD" and GetTime() - conn.lastJoinAt > 5 and NS.db.password ~= "" then
    -- not an answer to our join: the client rejoined the remembered channel without the password
    Debug("the client rejoined %s without the password; joining with it", tostring(NS.db.channel))
    JoinWithPassword()
    return
  end
  local why = JOIN_FAILURE_TEXT[notice]
  if why then HoldJoin(notice, why) end
end

function NS.SetConfig(channel, password, tag, source)
  NS.LeaveLink()
  local db = NS.db
  db.channel, db.password, db.tag, db.source = channel, password, tag, source
  C_Timer.After(1.5, NS.EnsureChannel)
end

-- Text into the channel. Only works from inside the player's own keypress (the chat send hooks); from a
-- timer or an event handler the game drops it. True when the client accepted it.
function NS.SendChannelText(text)
  local id = ChannelId()
  if not id or Locked() or not SendChatMessage then return false end
  local ok, err = pcall(SendChatMessage, text, "CHANNEL", nil, id)
  conn.lastSendAt = GetTime()
  conn.lastSendResult = ok and "ok" or "error"
  if not ok then Debug("channel send errored: %s", tostring(err)) end
  return ok
end

---------------------------------------------------------------- events
NS.events.CHANNEL_UI_UPDATE = function()
  -- the channel system just became ready (or changed); make sure we are in the link channel
  if Configured() then NS.EnsureChannel() end
end

NS.events.CHAT_MSG_CHANNEL_NOTICE = function(notice, _, _, channelName, _, _, _, _, channelBaseName)
  OnChannelNotice(notice, channelName, channelBaseName)
end

-- Whether a password prompt may be answered now: the gate EnsureChannel applies to any join, plus a cap, so a
-- password the server keeps refusing is not sent again each time the client asks.
local function MayAnswerPassword()
  if not NS.db.enabled or Locked() then return false end
  if GetTime() < conn.blockedUntil then
    Debug("password prompt for %s not answered: join on hold (%s)", tostring(NS.db.channel), tostring(conn.blockedWhy))
    return false
  end
  if conn.passwordAnswers < PASSWORD_ANSWER_CAP then return true end
  if not conn.passwordCapTold then
    conn.passwordCapTold = true
    HoldJoin("PASSWORD_REQUESTS", "the game keeps asking for the channel password")
  end
  return false
end

-- The client remembers custom channels between logins and rejoins them without the password, then asks the
-- player for it. Answer from the config instead and close that prompt. An unanswered prompt stays open.
NS.events.CHANNEL_PASSWORD_REQUEST = function(channelName)
  if not Configured() or NS.db.password == "" or not IsLinkChannel(channelName) then return end
  if not MayAnswerPassword() then return end
  conn.passwordAnswers = conn.passwordAnswers + 1
  Debug("client asked for the %s password; answering from config", tostring(NS.db.channel))
  JoinWithPassword()
  -- Blizzard's prompt carries the channel name from this event as its data; passing it leaves other prompts open
  if StaticPopup_Hide then pcall(StaticPopup_Hide, "CHAT_CHANNEL_PASSWORD", channelName) end
end

---------------------------------------------------------------- chat filters
-- The link channel carries packed lines: keep its raw text and join/leave notices out of chat windows.
local function ChannelFilter(_, _, _, _, _, channelString)
  if IsLinkChannel(channelString) then return true end
end
for _, ev in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_NOTICE",
                      "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
  ChatFrame_AddMessageEventFilter(ev, ChannelFilter)
end

---------------------------------------------------------------- whisper sender
-- A few whispers per second, so one line for seven guilds goes out in two ticks.
C_Timer.NewTicker(1, function()
  if not NS.db or Locked() or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end
  for _ = 1, WHISPERS_PER_SECOND do
    local w = table.remove(NS.whisperQueue, 1)
    if not w then return end
    pcall(C_ChatInfo.SendAddonMessage, NS.PREFIX, w.text, "WHISPER", w.target)
  end
end)
