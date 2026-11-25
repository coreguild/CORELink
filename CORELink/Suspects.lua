-- CORELink/Suspects.lua: a kept list of lines the addon did not believe, with who the game says delivered them.
-- An addon cannot write files of its own. The list lives in this character's saved variables
-- (CORELinkDB.suspects), which the game writes to disk at logout and /reload:
--   WTF/Account/<account>/<realm>/<character>/SavedVariables/CORELink.lua
-- /cl suspects shows it in chat and in the copy box; /cl suspects clear empties it.
-- "delivered by" is the one name the game vouches for. On the link channel that is whoever typed the line; on a
-- whisper or a guild fan-out it is the client that passed it on, which may only be carrying someone else's lie.
-- Provides NS.NoteSuspect.
local _, NS = ...

local MAX = 100           -- entries kept; the oldest go first

-- Text anyone can write: kept short, and with nothing that draws in chat.
local function Short(s, n) return (tostring(s or ""):gsub("[|%c]", ""):sub(1, n)) end

-- s: { kind=, via=, from=, tag=, author=, text=, why= }; called once per packet id (Relay.lua, Whisper.lua).
function NS.NoteSuspect(s)
  local db = NS.db
  if not db then return end
  local list = db.suspects or {}
  db.suspects = list
  list[#list + 1] = {
    when = (date and date("%Y-%m-%d %H:%M:%S")) or "", kind = Short(s.kind, 20), via = Short(s.via, 10),
    from = Short(s.from, 60), tag = Short(s.tag, 12), author = Short(s.author, 60), text = Short(s.text, 80),
    why = Short(s.why, 100),
  }
  while #list > MAX do table.remove(list, 1) end
end

local function Line(e)
  return string.format("%s %s via %s, delivered by %s: <%s> %s: \"%s\" (%s)", e.when or "", e.kind or "",
    e.via or "", e.from or "?", e.tag or "", e.author or "", e.text or "", e.why or "")
end

local SHOW_IN_CHAT = 10

NS.commands.suspects = function(arg)
  local db = NS.db
  if arg:lower() == "clear" then
    db.suspects = nil
    NS.Print("suspect list cleared.")
    return
  end
  local list = db.suspects or {}
  if #list == 0 then NS.Print("no suspect lines recorded on this character.") return end
  local lines = {}
  for i, e in ipairs(list) do lines[i] = Line(e) end
  NS.Print(#lines .. " suspect line(s) recorded on this character, oldest first"
    .. (#lines > SHOW_IN_CHAT and ("; the last " .. SHOW_IN_CHAT .. " here, all in the copy box") or "") .. ":")
  for i = math.max(1, #lines - SHOW_IN_CHAT + 1), #lines do NS.Print(lines[i]) end
  pcall(NS.ShowCopyBox, table.concat(lines, " / "), "CORELink: press Ctrl+C to copy the suspect list")
end
