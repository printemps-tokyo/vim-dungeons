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

-- Open a tab with an empty game buffer and the window options the game
-- needs. Returns the buffer.
local function open_game_buffer(name)
  set_hl()
  vim.cmd('tabnew')
  local buf = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(0, buf)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'vimdungeons'
  pcall(api.nvim_buf_set_name, buf, name)

  local wo = vim.wo
  wo.number = false
  wo.relativenumber = false
  wo.cursorline = false
  wo.wrap = false
  wo.signcolumn = 'no'
  wo.list = false
  wo.spell = false
  return buf
end

-- Whether a run is in progress in an open game buffer.
local function run_in_progress()
  local st = require('vimdungeons.game').state()
  return st ~= nil and not st.replaying and st.buf and api.nvim_buf_is_valid(st.buf)
    and st.mode ~= 'dead' and st.mode ~= 'won'
end

-- The replay being played, if any; a new game or another replay stops it.
local playback = nil

local function stop_playback()
  if playback then
    playback.stop()
  end
end

function M.start(opts)
  opts = opts or {}
  stop_playback()
  local buf = open_game_buffer('VimDungeons')
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

  -- A class from the command (or vim.g.vim_dungeons_class) skips the menu.
  local class = opts.class or vim.g.vim_dungeons_class
  local game_opts = {
    hard = opts.hard,
    daily = opts.daily,
    class = class,
    choose_class = (class == nil) and opts.choose or nil,
  }

  -- Resume a suspend save if present (skipped for hard/daily or bang-new starts).
  local savemod = require('vimdungeons.save')
  local resume_data = nil
  if not (opts.hard or opts.new or opts.daily) then
    resume_data = savemod.load()
  end
  if opts.new then
    savemod.clear()
  end
  if resume_data then
    savemod.clear()
    local ok = pcall(game.resume, buf, resume_data)
    if not ok then
      game.new_game(buf, game_opts)
    end
  else
    game.new_game(buf, game_opts)
  end
end

local function notify(text, level)
  vim.notify('VimDungeons: ' .. text, level or vim.log.levels.INFO)
end

local function result_text(r)
  if type(r) ~= 'table' then
    return '?'
  end
  if r.outcome == 'won' then
    return (T('踏破 B%dF Lv%d %dG %dターン')):format(r.floor or 0, r.lv or 1, r.gold or 0, r.turns or 0)
  end
  return (T('B%dFで力尽きた Lv%d %dG %dターン')):format(r.floor or 0, r.lv or 1, r.gold or 0, r.turns or 0)
end

-- Play a replay in its own tab. q stops, space pauses, + and - change speed.
function M.play_replay(replay)
  if run_in_progress() then
    notify(T('進行中の冒険がある。終えるか Q で中断してから再生しよう'), vim.log.levels.WARN)
    return
  end
  stop_playback()
  local game = require('vimdungeons.game')
  local rp = require('vimdungeons.replay')
  local buf = open_game_buffer('VimDungeons Replay')
  local state = { i = 0, delay = 80, paused = false, stopped = false, game = nil }
  local flags = rp.pause(true)
  local function stop()
    if state.stopped then
      return
    end
    state.stopped = true
    rp.pause(flags)
    if playback and playback.state == state then
      playback = nil
    end
  end
  playback = { stop = stop, state = state }
  local function step()
    -- Stop when the tab is gone or another game has taken over.
    if state.stopped or not api.nvim_buf_is_valid(buf) or game.state() ~= state.game then
      stop()
      return
    end
    local st = state.game
    if not state.paused then
      state.i = state.i + 1
      local k = replay.keys[state.i]
      if not k or st.mode == 'dead' or st.mode == 'won' then
        stop()
        notify((T('リプレイ終了: %s')):format(result_text(replay.result)))
        return
      end
      local ok, err = pcall(game.handle, k)
      if not ok then
        stop()
        notify(tostring(err), vim.log.levels.ERROR)
        return
      end
    end
    vim.defer_fn(step, state.delay)
  end
  local function key(lhs, fn)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  key('q', function()
    stop()
    if api.nvim_buf_is_valid(buf) then
      vim.cmd('tabclose')
    end
  end)
  key('<Space>', function()
    state.paused = not state.paused
  end)
  key('+', function()
    state.delay = math.max(5, math.floor(state.delay / 2))
  end)
  key('-', function()
    state.delay = math.min(1000, state.delay * 2)
  end)
  api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = function()
      stop()
      require('vimdungeons.render').close_float(game.state())
    end,
  })
  local ok, err = pcall(game.new_game, buf, rp.game_opts(replay))
  if not ok then
    stop()
    notify(tostring(err), vim.log.levels.ERROR)
    return
  end
  state.game = game.state()
  notify((T('%sのリプレイを再生中 (q:停止 Space:一時停止 +/-:速さ)')):format(replay.name or '?'))
  vim.defer_fn(step, state.delay)
end

-- :VimDungeonsReplay {export|play|verify|import} [file]
function M.replay_command(args)
  local rp = require('vimdungeons.replay')
  local sub, file = args[1], args[2]
  if sub == 'export' then
    local last = rp.last()
    if not last then
      notify(T('保存できるリプレイがない(冒険を最後まで終えると記録される)'), vim.log.levels.WARN)
      return
    end
    file = file or rp.default_name(last)
    if rp.write_file(last, file) then
      notify((T('リプレイを書き出した: %s')):format(vim.fn.fnamemodify(file, ':p')))
    else
      notify((T('書き出せなかった: %s')):format(file), vim.log.levels.ERROR)
    end
    return
  end
  if sub == 'play' or sub == 'verify' or sub == 'import' then
    local replay, err
    if file then
      replay, err = rp.read_file(file)
    else
      replay = rp.last()
      err = T('リプレイがない')
    end
    if not replay then
      notify(err or '?', vim.log.levels.ERROR)
      return
    end
    if sub == 'play' then
      M.play_replay(replay)
      return
    end
    local report = sub == 'import' and rp.import(replay) or rp.verify(replay)
    if report.ok then
      local msg = (T('検証OK: %s')):format(result_text(report.result))
      if report.rank then
        msg = msg .. (T(' / %sの日替わり %d位に登録')):format(replay.daily, report.rank)
      elseif sub == 'import' and replay.daily then
        msg = msg .. T(' / ランキング圏外')
      elseif sub == 'import' then
        msg = msg .. T(' / 日替わりではないのでランキングには載らない')
      end
      notify(msg)
    else
      notify((T('検証NG: %s (主張: %s / 再現: %s)')):format(
        report.err or '?', result_text(report.claimed), result_text(report.result)), vim.log.levels.WARN)
    end
    return
  end
  notify(T('使い方: :VimDungeonsReplay export [ファイル] | play [ファイル] | verify ファイル | import ファイル'), vim.log.levels.WARN)
end

local function show_float(lines)
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

-- Show a day's local ranking (today by default).
function M.ranking(date)
  date = date or os.date('%Y-%m-%d')
  local data = require('vimdungeons.data')
  local list = require('vimdungeons.daily').list(date)
  local lines = { (T(' == 日替わりランキング %s ==')):format(date), '' }
  if #list == 0 then
    lines[#lines + 1] = T(' まだ記録がない (:VimDungeonsDaily で挑戦)')
  end
  for i, e in ipairs(list) do
    local c = data.class_by_id(e.class or 'wanderer')
    lines[#lines + 1] = (' %2d. %-12s %-6s %s%s'):format(
      i, e.name or '?', c and T(c.name) or '?', result_text(e),
      e.source == 'replay' and T(' [リプレイ検証済]') or '')
  end
  lines[#lines + 1] = ''
  lines[#lines + 1] = T(' 他の人のリプレイは :VimDungeonsReplay import ファイル で追加')
  lines[#lines + 1] = T(' q:閉じる')
  show_float(lines)
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
