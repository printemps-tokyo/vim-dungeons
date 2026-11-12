-- Daily challenge ranking, kept locally (JSON under stdpath('data')).
-- Your own daily runs are added when they end; runs from other players
-- arrive as replay files and are added only after they verify.
local M = {}

local MAX_PER_DAY = 20
local MAX_DAYS = 400

local function path()
  vim.fn.mkdir(vim.fn.stdpath('data'), 'p')
  return vim.fn.stdpath('data') .. '/vimdungeons_daily.json'
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

-- Clears beat deaths; then deeper floors, fewer turns, more gold.
function M.better(a, b)
  local ac, bc = a.outcome == 'won', b.outcome == 'won'
  if ac ~= bc then
    return ac
  end
  if (a.floor or 0) ~= (b.floor or 0) then
    return (a.floor or 0) > (b.floor or 0)
  end
  if (a.turns or 0) ~= (b.turns or 0) then
    return (a.turns or 0) < (b.turns or 0)
  end
  return (a.gold or 0) > (b.gold or 0)
end

-- Add an entry to a day's ranking; returns that day's sorted list and the
-- entry's rank (nil when it did not make the list).
function M.record(date, entry)
  local all = M.load()
  local list = all[date] or {}
  entry.recorded = os.date('%Y-%m-%d %H:%M')
  list[#list + 1] = entry
  table.sort(list, M.better)
  while #list > MAX_PER_DAY do
    table.remove(list)
  end
  all[date] = list
  -- Drop the oldest days beyond the cap.
  local days = vim.tbl_keys(all)
  table.sort(days)
  while #days > MAX_DAYS do
    all[table.remove(days, 1)] = nil
  end
  local f = io.open(path(), 'w')
  if f then
    f:write(vim.json.encode(all))
    f:close()
  end
  for i, e in ipairs(list) do
    if e == entry then
      return list, i
    end
  end
  return list, nil
end

function M.list(date)
  return M.load()[date] or {}
end

return M
