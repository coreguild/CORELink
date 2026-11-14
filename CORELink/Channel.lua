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

-- Stop joining for ten minutes and tell the player why, unless quiet. /cl reload, a new config or a
-- successful join ends it.
local function HoldJoin(why, text, quiet)
  conn.blockedUntil, conn.blockedWhy = GetTime() + JOIN_BLOCK_SECS, why
  if quiet then return end
  Print("could not join " .. tostring(NS.db.channel) .. ": " .. text
    .. ". /cl reload to retry, /cl report for details.")
end

-- The join works again, the config changed or the player asked for a retry: no hold, and password prompts
-- are answered again.
function NS.ClearJoinHold()
  conn.blockedUntil, conn.blockedWhy = 0, nil
  conn.passwordAnswers, conn.passwordCapTold = 0, false
end

-- Why an answer to the game (a password prompt, its password-less rejoin) may not join now, or nil.
-- The same gate EnsureChannel applies to its own joins.
local function JoinBlocked()
  if not NS.db.enabled then return "the addon is off" end
  if Locked() then return "chat lockdown" end
  if GetTime() < conn.blockedUntil then return "join on hold (" .. tostring(conn.blockedWhy) .. ")" end
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
    local blocked = JoinBlocked()
    Debug("the client rejoined %s without the password; %s", tostring(NS.db.channel),
      blocked and ("not joining: " .. blocked) or "joining with it")
    if not blocked then JoinWithPassword() end
    return
  end
  local why = JOIN_FAILURE_TEXT[notice]
  if why then HoldJoin(notice, why) end
end

function NS.SetConfig(channel, password, tag, source)
  NS.LeaveLink()
  NS.ClearJoinHold()
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

-- The cap on answered password prompts is reached: hold the join (again, each time a hold has run out, so
-- EnsureChannel does not keep causing prompts nobody answers) and tell the player the first time.
local function PasswordCapped()
  if conn.passwordAnswers < PASSWORD_ANSWER_CAP then return nil end
  HoldJoin("PASSWORD_REQUESTS", "the game keeps asking for the channel password", conn.passwordCapTold)
  conn.passwordCapTold = true
  return "answered " .. PASSWORD_ANSWER_CAP .. " times already"
end

-- Close the game's password prompt, unless it names another channel. Blizzard's prompt carries the channel
-- name as its data; when that cannot be read, close it as before.
local function ClosePasswordPrompt()
  if not StaticPopup_Hide then return end
  local name = StaticPopup_Visible and select(2, pcall(StaticPopup_Visible, "CHAT_CHANNEL_PASSWORD"))
  local prompt = type(name) == "string" and _G[name]
  local data = type(prompt) == "table" and prompt.data
  if type(data) == "string" and not issecret(data) and not IsLinkChannel(data) then return end
  pcall(StaticPopup_Hide, "CHAT_CHANNEL_PASSWORD")
end

-- The client remembers custom channels between logins and rejoins them without the password, then asks the
-- player for it. Answer from the config instead and close the prompt. An unanswered prompt stays open.
NS.events.CHANNEL_PASSWORD_REQUEST = function(channelName)
  if not Configured() or NS.db.password == "" or not IsLinkChannel(channelName) then return end
  local why = JoinBlocked() or PasswordCapped()
  if why then
    Debug("password prompt for %s not answered: %s", tostring(NS.db.channel), why)
    return
  end
  conn.passwordAnswers = conn.passwordAnswers + 1
  Debug("client asked for the %s password; answering from config (%d of %d)", tostring(NS.db.channel),
    conn.passwordAnswers, PASSWORD_ANSWER_CAP)
  JoinWithPassword()
  ClosePasswordPrompt()
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
