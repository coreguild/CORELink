-- CORELink/Bridge.lua: the cross-realm bridge through our own guild.
-- A client that hears another guild's line on its realm forwards it to its guild over the guild addon channel
-- (which crosses realms); a guildmate on another realm re-sends it into that realm's channel. Our own guild's
-- lines are never bridged: our couriers on each realm already relay them.
-- Provides NS.ForwardToGuild, NS.OnBridgeReceived, NS.bridgeStats.
local _, NS = ...
local Debug, IsMe, SEP = NS.Debug, NS.IsMe, NS.SEP

local bridged = {}          -- packet id -> time it was forwarded (by us or a guildmate) on the guild channel
NS.bridged = bridged
NS.bridgeStats = { forwarded = 0, resent = 0, skipped = 0 }
local stats = NS.bridgeStats

local function BridgeEnabled()
  local db = NS.db
  return db and db.enabled and db.bridge ~= false and NS.Configured()
end

-- Heard a foreign guild's line on our realm's channel: forward it to our guild for other realms.
function NS.ForwardToGuild(id, text)
  if not BridgeEnabled() or not NS.HasGuildmatesElsewhere() then return end
  if #text + 7 > 255 then stats.skipped = stats.skipped + 1 return end
  C_Timer.After(0.3 + math.random() * 1.2, function()
    if bridged[id] then return end          -- a guildmate on our realm already forwarded it
    bridged[id] = GetTime()
    stats.forwarded = stats.forwarded + 1
    NS.SendGuildAddon("BRIDGE" .. SEP .. text)
    Debug("bridged %s to the guild for other realms", id)
  end)
end

-- A guildmate forwarded a foreign line it heard on its realm (or a peer whispered one): if it has not reached
-- ours, re-send it here after a random back-off, unless someone else did meanwhile.
function NS.OnBridgeReceived(text, sender)
  local id = text:match("^CL%d+" .. SEP .. "(%x+)" .. SEP)
  if not id then return end
  bridged[id] = GetTime()
  if IsMe(sender) then return end
  if not BridgeEnabled() then return end
  local seen, pending = NS.seen, NS.pending
  if seen[id] then return end              -- already on our realm's channel (same-realm guildmate forwarded it)
  pending[id] = true
  C_Timer.After(0.3 + math.random() * 1.2, function()
    if not pending[id] or seen[id] then pending[id] = nil return end   -- someone else re-sent it meanwhile
    pending[id] = nil
    seen[id] = GetTime()
    table.insert(NS.sendQueue, text)       -- verbatim packet; receivers display it as the original guild's line
    stats.resent = stats.resent + 1
    Debug("re-sent bridged %s from %s into %s", id, sender, tostring(NS.db.channel))
  end)
end

NS.guildPackets.BRIDGE = function(rest, sender) NS.OnBridgeReceived(rest, sender) end

-- Forget forwarded ids after a minute (housekeeping, once a minute).
function NS.BridgeHousekeeping(now)
  for k, v in pairs(bridged) do if now - v > 60 then bridged[k] = nil end end
end
