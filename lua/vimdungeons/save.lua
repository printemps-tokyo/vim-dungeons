-- Suspend-save I/O (JSON under stdpath('data')).
local M = {}

-- While a replay plays or is verified, nothing is written.
M.paused = false

local function path()
  vim.fn.mkdir(vim.fn.stdpath('data'), 'p')
  return vim.fn.stdpath('data') .. '/vimdungeons_save.json'
end

function M.write(data)
  if M.paused then
    return
  end
  local f = io.open(path(), 'w')
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

function M.load()
  local f = io.open(path(), 'r')
  if not f then
    return nil
  end
  local content = f:read('*a')
  f:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if ok and type(decoded) == 'table' and decoded.version == 1 then
    return decoded
  end
  return nil
end

function M.clear()
  if M.paused then
    return
  end
  os.remove(path())
end

return M
