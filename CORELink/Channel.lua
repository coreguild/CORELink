-- CORELink/Channel.lua: the hidden custom chat channel that carries relay packets on this realm.
-- Joining and hiding it, the game's notices about it, the one-per-second sender for both queues, and the
-- presence beacon. Provides NS.conn (connection diagnostics), NS.ChannelId, NS.EnsureChannel, NS.SetConfig.
local _, NS = ...
local Print, Debug, Configured, Locked = NS.Print, NS.Debug, NS.Configured, NS.Locked
local issecret = NS.issecret

-- Connection diagnostics: what the game told us about the link channel, and whether joining is on hold.
NS.conn = {
  giState = "not read yet", lastNotice = nil, lastNoticeAt = nil, joinAttempts = 0,
  blockedUntil = 0, blockedWhy = nil, lastSendResult = nil,
}
local conn = NS.conn
local JOIN_BLOCK_SECS = 600   -- after WRONG_PASSWORD / BANNED, stop retrying for this long (or until /cl reload)
local lastFailNotice = 0

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

function NS.EnsureChannel()
  local db = NS.db
  if not db.enabled or not Configured() or Locked() then return end
  if not ChannelId() then
    if GetTime() < conn.blockedUntil then
      Debug("join of %s on hold (%s); /cl reload to retry now", db.channel, tostring(conn.blockedWhy))
      return
    end
    conn.joinAttempts = conn.joinAttempts + 1
    Debug("joining channel %s (attempt %d, password %s)", db.channel, conn.joinAttempts,
      db.password ~= "" and "set" or "none")
    local ok, err = pcall(JoinChannelByName, db.channel, (db.password ~= "" and db.password) or nil)
    if not ok then Debug("JoinChannelByName errored: %s", tostring(err)) end
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

-- Notices the game sends about channels: joined, left, wrong password, banned, too many channels ...
local function OnChannelNotice(notice, channelName, channelBaseName)
  if issecret(notice) or type(notice) ~= "string" then return end
  if not (IsLinkChannel(channelName) or IsLinkChannel(channelBaseName)) then return end
  conn.lastNotice, conn.lastNoticeAt = notice, (date and date("%H:%M:%S")) or ""
  Debug("channel notice for %s: %s", tostring(NS.db.channel), notice)
  local why = JOIN_FAILURE_TEXT[notice]
  if why then
    conn.blockedUntil = GetTime() + JOIN_BLOCK_SECS
    conn.blockedWhy = notice
    Print("could not join " .. tostring(NS.db.channel) .. ": " .. why
      .. ". /cl reload to retry, /cl report for details.")
  end
end

function NS.SetConfig(channel, password, tag, source)
  NS.LeaveLink()
  local db = NS.db
  db.channel, db.password, db.tag, db.source = channel, password, tag, source
  C_Timer.After(1.5, NS.EnsureChannel)
end

---------------------------------------------------------------- events
NS.events.CHANNEL_UI_UPDATE = function()
  -- the channel system just became ready (or changed); make sure we are in the link channel
  if Configured() then NS.EnsureChannel() end
end

NS.events.CHAT_MSG_CHANNEL_NOTICE = function(notice, _, _, channelName, _, _, _, _, channelBaseName)
  OnChannelNotice(notice, channelName, channelBaseName)
end

---------------------------------------------------------------- chat filters
-- The link channel is for addon packets only: keep its raw lines and join/leave notices out of chat windows.
local function ChannelFilter(_, _, _, _, _, channelString)
  if IsLinkChannel(channelString) then return true end
end
for _, ev in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_NOTICE",
                      "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
  ChatFrame_AddMessageEventFilter(ev, ChannelFilter)
end

---------------------------------------------------------------- senders
local function SendOneWhisper()
  local w = table.remove(NS.whisperQueue, 1)
  if w and not Locked() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
    pcall(C_ChatInfo.SendAddonMessage, NS.PREFIX, w.text, "WHISPER", w.target)
  end
end

local function SendOnePacket()
  local text = table.remove(NS.sendQueue, 1)
  if not text then return end
  if Locked() then wipe(NS.sendQueue) return end   -- cannot send during lockdown
  local id = ChannelId()
  if not id or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, NS.PREFIX, text, "CHANNEL", tostring(id))
  local result = ok and tostring(res) or "error"
  conn.lastSendResult = result
  Debug("sent on channel %d -> result %s", id, result)
  local failed = result ~= "0" and result ~= "true" and result ~= "nil"
  if failed and GetTime() - lastFailNotice > 60 then        -- at most one notice a minute, never per packet
    lastFailNotice = GetTime()
    Print("relay send failed (result " .. result .. "). Run /cl report and share it.")
  end
end

-- One whisper and one channel packet per second.
C_Timer.NewTicker(1, function()
  if not NS.db then return end
  SendOneWhisper()
  SendOnePacket()
end)

-- Presence beacon: lets /cl guilds show which guilds are on the link even when nobody is chatting.
-- Skipped if a member of our own guild beaconed recently.
local function Beacon()
  local db = NS.db
  if not db or not db.enabled or not Configured() or Locked() or not ChannelId() then return end
  local tag = NS.GetTag()
  if not tag then return end
  local now = GetTime()
  if NS.heard[tag] and now - NS.heard[tag] < 120 then return end
  if math.random() > 0.34 then return end
  local id = NS.Hash(tag .. now)
  NS.seen[id] = now
  table.insert(NS.sendQueue, table.concat({ NS.PROTO, id, tag, "", "", "", "", "" }, NS.SEP))
end
C_Timer.NewTicker(30, Beacon)
