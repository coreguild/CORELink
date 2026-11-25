-- CORELink/Suspects.lua: a kept list of lines the addon did not believe, with who the game says delivered them.
-- An addon cannot write files of its own. The list lives in this character's saved variables
-- (CORELinkDB.suspects), which the game writes to disk at logout and /reload:
--   WTF/Account/<account>/<realm>/<character>/SavedVariables/CORELink.lua
-- /cl suspects shows it in chat and in the copy box; /cl suspects clear empties it.
-- "delivered by" is the one name the game vouches for. On the link channel that is whoever typed the line; on a
-- whisper or a guild fan-out it is the client that passed it on, which may only be carrying someone else's lie.
-- Packet ids are the sender's to choose, so entries are told apart by what they say, and one deliverer keeps at
-- most PER_SENDER of them: nobody can push everyone else's entries out by sending many lines.
-- Provides NS.NoteSuspect.
local _, NS = ...

local MAX, PER_SENDER = 100, 10

-- Text anyone can write, kept short: a link keeps its shown words, colour codes go, nothing left can draw in
-- chat, and a cut never splits a character.
local function Short(s, n)
  s = tostring(s or ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  s = s:gsub("[|%c]", ""):sub(1, n)
  if (s:byte(-1) or 0) >= 128 then s = s:gsub("[\192-\255][\128-\191]*$", "") end
  return s
end

-- The kept list, whatever the saved file holds: anything that is not an entry is dropped.
local function List(db)
  local list = type(db.suspects) == "table" and db.suspects or {}
  for i = #list, 1, -1 do if type(list[i]) ~= "table" then table.remove(list, i) end end
  db.suspects = list
  return list
end

local function Same(a, b)
  return a.from == b.from and a.kind == b.kind and a.tag == b.tag and a.author == b.author and a.text == b.text
end

-- s: { kind=, via=, from=, tag=, author=, text=, why= }. A line already kept from the same deliverer is not
-- kept again; a deliverer's oldest entry makes room for their newest.
function NS.NoteSuspect(s)
  local db = NS.db
  if not db or type(s) ~= "table" then return end
  local e = {
    when = (date and date("%Y-%m-%d %H:%M:%S")) or "", kind = Short(s.kind, 20), via = Short(s.via, 10),
    from = Short(s.from, 60), tag = Short(s.tag, 12), author = Short(s.author, 60), text = Short(s.text, 80),
    why = Short(s.why, 100),
  }
  if e.from == "" then e.from = "?" end
  if e.tag ~= "" and db.muted and db.muted[e.tag:lower()] then return end
  local list, mine, first = List(db), 0, nil
  for i, old in ipairs(list) do
    if Same(old, e) then return end
    if old.from == e.from then mine, first = mine + 1, first or i end
  end
  if mine >= PER_SENDER then table.remove(list, first) end
  list[#list + 1] = e
  while #list > MAX do table.remove(list, 1) end
end

local function Line(e)
  return string.format("%s %s via %s, delivered by %s: <%s> %s: \"%s\" (%s)", tostring(e.when), tostring(e.kind),
    tostring(e.via), tostring(e.from), tostring(e.tag), tostring(e.author), tostring(e.text), tostring(e.why))
end

local SHOW_IN_CHAT = 10

NS.commands.suspects = function(arg)
  local db = NS.db
  if arg:lower() == "clear" then
    db.suspects = nil
    NS.Print("suspect list cleared.")
    return
  end
  local list = List(db)
  if #list == 0 then NS.Print("no suspect lines recorded on this character.") return end
  local lines = {}
  for i, e in ipairs(list) do lines[i] = Line(e) end
  NS.Print(#lines .. " suspect line(s) recorded on this character, oldest first"
    .. (#lines > SHOW_IN_CHAT and ("; the last " .. SHOW_IN_CHAT .. " here, all in the copy box") or "") .. ":")
  for i = math.max(1, #lines - SHOW_IN_CHAT + 1), #lines do NS.Print(lines[i]) end
  pcall(NS.ShowCopyBox, table.concat(lines, " / "), "CORELink: press Ctrl+C to copy the suspect list")
end
