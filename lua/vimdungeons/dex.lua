-- Monster codex: persistent record of encounters and kills.
local M = {}

local cache = nil
local dirty = false

local function path()
  return vim.fn.stdpath('data') .. '/vimdungeons_dex.json'
end

function M.data()
  if not cache then
    cache = {}
    local f = io.open(path(), 'r')
    if f then
      local content = f:read('*a')
      f:close()
      local ok, decoded = pcall(vim.json.decode, content)
      if ok and type(decoded) == 'table' then
        cache = decoded
      end
    end
  end
  return cache
end

local function entry(name)
  local d = M.data()
  if not d[name] then
    d[name] = { seen = false, kills = 0 }
  end
  return d[name]
end

function M.mark_seen(name)
  local e = entry(name)
  if not e.seen then
    e.seen = true
    dirty = true
  end
end

function M.mark_kill(name)
  local e = entry(name)
  e.seen = true
  e.kills = (e.kills or 0) + 1
  dirty = true
end

-- Write to disk when dirty (called on floor change and game end).
function M.flush()
  if not dirty then
    return
  end
  local f = io.open(path(), 'w')
  if f then
    f:write(vim.json.encode(M.data()))
    f:close()
  end
  dirty = false
end

return M
