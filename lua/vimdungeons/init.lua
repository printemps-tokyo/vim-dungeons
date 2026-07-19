-- Entry point: window/keymap setup and game start.
local api = vim.api
local T = require('vimdungeons.i18n').t

local M = {}

local function set_hl()
  local defs = {
    VimDungeonsWall = 'Comment',
    VimDungeonsFloor = 'Normal',
    VimDungeonsDim = 'NonText',
    VimDungeonsPlayer = 'Function',
    VimDungeonsEnemy = 'DiagnosticError',
    VimDungeonsEnemySleep = 'Comment',
    VimDungeonsItem = 'DiagnosticWarn',
    VimDungeonsGold = 'DiagnosticWarn',
    VimDungeonsStairs = 'DiagnosticInfo',
    VimDungeonsTrap = 'Special',
    VimDungeonsGoal = 'Constant',
    VimDungeonsKeeper = 'DiagnosticOk',
    VimDungeonsStatus = 'Title',
    VimDungeonsStatusDanger = 'ErrorMsg',
  }
  for name, link in pairs(defs) do
    api.nvim_set_hl(0, name, { default = true, link = link })
  end
end

-- a-j select inventory slots; h j k l y u b n double as movement depending on the mode.
local KEYS = {
  'h', 'j', 'k', 'l', 'y', 'u', 'b', 'n',
  'H', 'J', 'K', 'L', 'Y', 'U', 'B', 'N',
  '.', '>', 'i', 't', 'M', 'S', '?', 'Q', 'q', 'r',
  'a', 'c', 'd', 'e', 'f', 'g',
  -- Characters usable as Scroll of f targets (enemy/item/gold glyphs).
  's', 'o', 'w', 'D', '$', '!', '%', ')', ']', '&', '2', 'G', '/', '=', ',',
}

function M.start(opts)
  set_hl()
  vim.cmd('tabnew')
  local buf = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(0, buf)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'vimdungeons'
  pcall(api.nvim_buf_set_name, buf, 'VimDungeons')

  local wo = vim.wo
  wo.number = false
  wo.relativenumber = false
  wo.cursorline = false
  wo.wrap = false
  wo.signcolumn = 'no'
  wo.list = false
  wo.spell = false

  local game = require('vimdungeons.game')
  local function map(lhs, token)
    vim.keymap.set('n', lhs, function()
      game.handle(token)
    end, { buffer = buf, nowait = true, silent = true })
  end
  for _, k in ipairs(KEYS) do
    map(k, k)
  end
  map('<Esc>', 'esc')
  map('<Left>', 'h')
  map('<Right>', 'l')
  map('<Up>', 'k')
  map('<Down>', 'j')

  api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = function()
      require('vimdungeons.render').close_float(game.state())
    end,
  })

  -- Resume a suspend save if present (skipped for hard/daily or bang-new starts).
  local savemod = require('vimdungeons.save')
  local resume_data = nil
  if not (opts and (opts.hard or opts.new or opts.daily)) then
    resume_data = savemod.load()
  end
  if opts and opts.new then
    savemod.clear()
  end
  if resume_data then
    savemod.clear()
    local ok = pcall(game.resume, buf, resume_data)
    if not ok then
      game.new_game(buf, opts)
    end
  else
    game.new_game(buf, opts)
  end
end

-- Show the achievement list in a floating window.
function M.achievements()
  local ach = require('vimdungeons.achievements')
  local unlocked = ach.load()
  local done = 0
  local lines = {}
  for _, d in ipairs(ach.defs) do
    local when = unlocked[d.id]
    if when then
      done = done + 1
      lines[#lines + 1] = (' [o] %s - %s (%s)'):format(T(d.name), T(d.desc), when)
    else
      lines[#lines + 1] = (' [ ] %s - %s'):format(T(d.name), T(d.desc))
    end
  end
  table.insert(lines, 1, (T(' == VimDungeons 実績 (%d/%d) ==')):format(done, #ach.defs))
  table.insert(lines, 2, '')
  lines[#lines + 1] = ''
  lines[#lines + 1] = T(' q:閉じる')

  local width = 20
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    style = 'minimal',
    border = 'rounded',
    width = width + 2,
    height = #lines,
    row = math.max(0, math.floor((vim.o.lines - #lines) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
  })
  for _, k in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', k, function()
      if api.nvim_win_is_valid(win) then
        api.nvim_win_close(win, true)
      end
    end, { buffer = buf, nowait = true, silent = true })
  end
end

-- Show the monster codex in a floating window.
function M.dex()
  local dex = require('vimdungeons.dex')
  local data = require('vimdungeons.data')
  local records = dex.data()
  local defs = {}
  for _, d in ipairs(data.enemies) do
    defs[#defs + 1] = d
  end
  defs[#defs + 1] = data.keeper
  defs[#defs + 1] = data.boss
  local seen_count = 0
  local lines = {}
  for _, d in ipairs(defs) do
    local rec = records[d.name]
    if rec and rec.seen then
      seen_count = seen_count + 1
      local traits = {}
      if d.speed then
        traits[#traits + 1] = T('倍速')
      end
      if d.phase then
        traits[#traits + 1] = T('壁抜け')
      end
      if d.venom then
        traits[#traits + 1] = T('毒')
      end
      if d.erratic then
        traits[#traits + 1] = T('気まぐれ')
      end
      local trait = #traits > 0 and (' [' .. table.concat(traits, '/') .. ']') or ''
      local range = d.min_floor and (T('  %d-%d階')):format(d.min_floor, math.min(d.max_floor or 99, 30)) or ''
      lines[#lines + 1] = (T(' %s %s%s  HP%d 攻%d 防%d%s  撃破:%d')):format(
        d.char, T(d.name), trait, d.hp, d.atk, d.def, range, rec.kills or 0)
    else
      lines[#lines + 1] = (T(' ? ？？？')):format()
    end
  end
  table.insert(lines, 1, (T(' == モンスター図鑑 (%d/%d) ==')):format(seen_count, #defs))
  table.insert(lines, 2, '')
  lines[#lines + 1] = ''
  lines[#lines + 1] = T(' q:閉じる')

  local width = 20
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    style = 'minimal',
    border = 'rounded',
    width = width + 2,
    height = #lines,
    row = math.max(0, math.floor((vim.o.lines - #lines) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
  })
  for _, k in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', k, function()
      if api.nvim_win_is_valid(win) then
        api.nvim_win_close(win, true)
      end
    end, { buffer = buf, nowait = true, silent = true })
  end
end

-- Show the high-score list in a floating window.
function M.scores()
  local list = require('vimdungeons.score').load()
  local lines = { T(' == VimDungeons 記録 =='), '' }
  if #list == 0 then
    lines[#lines + 1] = T(' まだ記録がない')
  end
  for i, s in ipairs(list) do
    local result
    if s.cleared then
      result = T('踏破！')
    else
      result = T('死因:') .. (s.cause and T(s.cause) or T('不明'))
    end
    lines[#lines + 1] = (T(' %2d. %s地下%d階  Lv%d  %dG  %s  (%s)')):format(
      i, (s.hard and T('【裏】') or '') .. (s.daily and T('【日替】') or ''), s.floor or 0, s.lv or 1, s.gold or 0, result, s.date or '-')
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = T(' q:閉じる')

  local width = 20
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    style = 'minimal',
    border = 'rounded',
    width = width + 2,
    height = #lines,
    row = math.max(0, math.floor((vim.o.lines - #lines) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
  })
  for _, k in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', k, function()
      if api.nvim_win_is_valid(win) then
        api.nvim_win_close(win, true)
      end
    end, { buffer = buf, nowait = true, silent = true })
  end
end

return M
