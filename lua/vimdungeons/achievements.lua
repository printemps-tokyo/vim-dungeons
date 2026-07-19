-- Achievement definitions and persistence (JSON under stdpath('data')).
local M = {}

M.defs = {
  { id = 'first_kill', name = 'はじめての一撃', desc = '敵を1体倒す' },
  { id = 'floor5', name = '中層探索者', desc = '地下5階に到達する' },
  { id = 'lv10', name = 'ベテラン冒険者', desc = 'レベル10に到達する' },
  { id = 'rich', name = '大金持ち', desc = '1000G以上を所持する' },
  { id = 'shopper', name = '上客', desc = '店で買い物をして精算する' },
  { id = 'thief_hunter', name = '武装商人返り討ち', desc = '怒った店主を倒す' },
  { id = 'mhouse', name = 'モンスターハウス生還', desc = 'モンスターハウスに遭遇した階から階段で生還する' },
  { id = 'boss', name = '竜殺し', desc = '聖典の守護竜を倒す' },
  { id = 'clear', name = 'Vimの聖典', desc = 'ダンジョンを踏破する' },
  { id = 'hard_clear', name = '真のVimmer', desc = '裏ダンジョン『無限ヤンクの奈落』を踏破する' },
  { id = 'identify_all', name = '目利き', desc = '1回の冒険で全種の未識別アイテムを識別する' },
  { id = 'dex_complete', name = 'モンスター博士', desc = '図鑑を完成させる(全11種と遭遇)' },
  { id = 'abyss', name = '深淵を覗くもの', desc = '裏ダンジョンで地下15階に到達する' },
}

local function path()
  return vim.fn.stdpath('data') .. '/vimdungeons_achievements.json'
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

function M.unlocked(id)
  return M.load()[id] ~= nil
end

function M.def_of(id)
  for _, d in ipairs(M.defs) do
    if d.id == id then
      return d
    end
  end
end

-- Returns true when newly unlocked, and stores the unlock timestamp.
function M.unlock(id)
  local list = M.load()
  if list[id] then
    return false
  end
  list[id] = os.date('%Y-%m-%d %H:%M')
  local f = io.open(path(), 'w')
  if f then
    f:write(vim.json.encode(list))
    f:close()
  end
  return true
end

return M
