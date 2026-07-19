-- Score persistence (JSON under stdpath('data')).
local M = {}

local function path()
  vim.fn.mkdir(vim.fn.stdpath('data'), 'p')
  return vim.fn.stdpath('data') .. '/vimdungeons_scores.json'
end

function M.load()
  local f = io.open(path(), 'r')
  if not f then
    return {}
  end
  local content = f:read('*a')
  f:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if ok and type(decoded) == 'table' then
    return decoded
  end
  return {}
end

-- Append entry = {floor, lv, gold, turns}, keep the top 10, and return the list.
function M.record(entry)
  entry.date = os.date('%Y-%m-%d %H:%M')
  local list = M.load()
  list[#list + 1] = entry
  table.sort(list, function(a, b)
    if (a.floor or 0) ~= (b.floor or 0) then
      return (a.floor or 0) > (b.floor or 0)
    end
    return (a.gold or 0) > (b.gold or 0)
  end)
  while #list > 10 do
    table.remove(list)
  end
  local f = io.open(path(), 'w')
  if f then
    f:write(vim.json.encode(list))
    f:close()
  end
  return list
end

return M
