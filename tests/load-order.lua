-- Load-order check: a file may copy something off NS at load time ("local X = NS.Y" at file level) only if an
-- earlier file in the TOC, or an earlier line of the same file, defined it. Anything else must be reached as
-- NS.Y at call time. Exit 1 listing every breach.
local files = {}
for line in io.lines("CORELink/CORELink.toc") do
  local file = line:match("^([%w_]+%.lua)%s*$")
  if file then files[#files + 1] = file end
end

local defined, breaches, checked = {}, {}, 0
for _, file in ipairs(files) do
  local n = 0
  for line in io.lines("CORELink/" .. file) do
    n = n + 1
    local lhs = line:match("^function NS%.([%w_]+)")
    if lhs then defined[lhs] = file end
    local assign = line:match("^(NS%.[%w_., ]+)=[^=]")
    if assign then
      for name in assign:gmatch("NS%.([%w_]+)") do defined[name] = defined[name] or file end
    end
    local rhs = line:match("^local [%w_, ]+= (.*)$")
    if rhs and rhs:find("NS%.") then
      for name in rhs:gmatch("NS%.([%w_]+)") do
        checked = checked + 1
        if not defined[name] then
          breaches[#breaches + 1] = string.format("%s:%d copies NS.%s before any file defines it: %s", file, n, name, line)
        end
      end
    end
  end
end

for _, b in ipairs(breaches) do print("LOAD ORDER  " .. b) end
if #breaches == 0 then
  print(string.format("load order ok: %d load-time copies from NS, every one defined by an earlier file", checked))
  os.exit(0)
end
os.exit(1)
