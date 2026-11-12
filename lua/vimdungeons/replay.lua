-- Replays: a run is its seed, class, mode, and the keys pressed. Playing
-- the keys back through the same game code reproduces the run, so a replay
-- file is both something to watch and proof of a result.
local M = {}

local LAST_FILE = 'vimdungeons_last_replay.json'
local ESC = string.char(27)

-- Limits for replay files from elsewhere: a long real run is a few thousand
-- keys, so these leave plenty of room while refusing absurd files.
M.MAX_BYTES = 1024 * 1024
M.MAX_KEYS = 200000

local last = nil

function M.player_name()
  local name = vim.g.vim_dungeons_name
  if type(name) == 'string' and name ~= '' then
    return name
  end
  return 'you'
end

local function data_path(name)
  vim.fn.mkdir(vim.fn.stdpath('data'), 'p')
  return vim.fn.stdpath('data') .. '/' .. name
end

-- Keys as one string: single characters as they are, 'esc' as ESC.
local function pack_keys(keys)
  local out = {}
  for i, k in ipairs(keys) do
    out[i] = k == 'esc' and ESC or k
  end
  return table.concat(out)
end

local function unpack_keys(s)
  local out = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    out[i] = c == ESC and 'esc' or c
  end
  return out
end

function M.encode(replay)
  local copy = vim.deepcopy(replay)
  copy.keys = pack_keys(replay.keys or {})
  return vim.json.encode(copy)
end

-- Returns the replay, or nil and an error message.
local function count(v)
  return type(v) == 'number' and v >= 0 and v == math.floor(v) and v < 2 ^ 31
end

-- Checks every field a replay file may carry; returns an error or nil.
local function invalid(r)
  if r.version ~= 1 then
    return 'unsupported replay version ' .. tostring(r.version)
  end
  if not count(r.seed) or type(r.keys) ~= 'string' then
    return 'not a replay file (seed or keys missing)'
  end
  if #r.keys > M.MAX_KEYS then
    return ('too many keys (%d, at most %d)'):format(#r.keys, M.MAX_KEYS)
  end
  if r.keys:find('[^%g ' .. ESC .. ']') then
    return 'keys hold characters the game never receives'
  end
  if r.class ~= nil and (type(r.class) ~= 'string' or not require('vimdungeons.data').class_by_id(r.class)) then
    return 'unknown class ' .. tostring(r.class)
  end
  if r.daily ~= nil and (type(r.daily) ~= 'string' or not r.daily:match('^%d%d%d%d%-%d%d%-%d%d$')) then
    return 'bad daily date'
  end
  for _, k in ipairs({ 'hard', 'choose', 'suspended' }) do
    if r[k] ~= nil and type(r[k]) ~= 'boolean' then
      return 'bad ' .. k
    end
  end
  if r.name ~= nil and (type(r.name) ~= 'string' or #r.name > 40 or r.name:find('%c')) then
    return 'bad name'
  end
  local res = r.result
  if res ~= nil then
    if type(res) ~= 'table' or (res.outcome ~= 'dead' and res.outcome ~= 'won') then
      return 'bad result'
    end
    for _, k in ipairs({ 'floor', 'lv', 'gold', 'turns' }) do
      if not count(res[k]) then
        return 'bad result ' .. k
      end
    end
    if res.cause ~= nil and type(res.cause) ~= 'string' then
      return 'bad result cause'
    end
  end
  return nil
end

function M.decode(text)
  if type(text) ~= 'string' or #text > M.MAX_BYTES then
    return nil, 'replay file too large'
  end
  local ok, r = pcall(vim.json.decode, text)
  if not ok or type(r) ~= 'table' then
    return nil, 'not a replay file (invalid JSON)'
  end
  local err = invalid(r)
  if err then
    return nil, err
  end
  r.keys = unpack_keys(r.keys)
  return r
end

-- Keep a finished run as the last replay (also on disk, for export later).
function M.remember(replay)
  replay.name = M.player_name()
  replay.recorded = os.date('%Y-%m-%d %H:%M')
  last = vim.deepcopy(replay)
  local f = io.open(data_path(LAST_FILE), 'w')
  if f then
    f:write(M.encode(replay))
    f:close()
  end
end

function M.last()
  if last then
    return last
  end
  local f = io.open(data_path(LAST_FILE), 'r')
  if not f then
    return nil
  end
  local text = f:read('*a')
  f:close()
  return (M.decode(text))
end

function M.read_file(path)
  local f = io.open(vim.fn.expand(path), 'r')
  if not f then
    return nil, 'cannot read ' .. path
  end
  local size = f:seek('end')
  if size and size > M.MAX_BYTES then
    f:close()
    return nil, 'replay file too large'
  end
  f:seek('set')
  local text = f:read('*a')
  f:close()
  return M.decode(text)
end

-- A default export file name, like vimdungeons-daily-2026-11-12-sage.json.
function M.default_name(replay)
  local kind = replay.daily and ('daily-' .. replay.daily) or (replay.hard and 'abyss' or 'run')
  local when = (replay.recorded or os.date('%Y-%m-%d %H:%M')):gsub('[^%d]', '')
  return ('vimdungeons-%s-%s-%s.json'):format(kind, replay.class or 'wanderer', when)
end

function M.write_file(replay, path)
  local f = io.open(vim.fn.expand(path), 'w')
  if not f then
    return false
  end
  f:write(M.encode(replay))
  f:close()
  return true
end

-- Pause or resume every kind of persistence (scores, saves, codex,
-- achievements), so watching or checking a replay changes nothing.
-- Returns the previous flags, which pause() also accepts to restore them.
local PERSIST = { 'score', 'save', 'dex', 'achievements' }

function M.pause(on)
  local before = {}
  for _, name in ipairs(PERSIST) do
    local mod = require('vimdungeons.' .. name)
    before[name] = mod.paused
    if type(on) == 'table' then
      mod.paused = on[name] or false
    else
      mod.paused = on
    end
  end
  return before
end

-- Options for new_game that recreate a replay's start.
function M.game_opts(replay)
  return {
    seed = replay.seed,
    hard = replay.hard or false,
    daily = replay.daily and true or nil,
    daily_date = replay.daily,
    choose_class = replay.choose or nil,
    class = (not replay.choose) and replay.class or nil,
    replaying = true,
  }
end

local function same_result(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' then
    return false
  end
  for _, k in ipairs({ 'outcome', 'floor', 'lv', 'gold', 'turns' }) do
    if a[k] ~= b[k] then
      return false
    end
  end
  return true
end

-- Re-simulate a replay without drawing and compare the result with the one
-- it claims. The current game, if any, is set aside and restored.
-- Returns { ok = bool, result = {...}, claimed = {...}, err = string? }.
function M.verify(replay)
  local game = require('vimdungeons.game')
  local saved = game.swap_state(nil)
  local flags = M.pause(true)
  local buf
  local result
  local ran, err = pcall(function()
    buf = vim.api.nvim_create_buf(false, true)
    local opts = M.game_opts(replay)
    opts.headless = true
    game.new_game(buf, opts)
    for _, k in ipairs(replay.keys) do
      local st = game.state()
      if st.mode == 'dead' or st.mode == 'won' then
        break
      end
      game.handle(k)
    end
    local st = game.state()
    result = {
      outcome = st.mode,
      floor = st.floor,
      lv = st.player.lv,
      gold = st.player.gold,
      turns = st.turn,
      cause = st.cause,
      class = st.class,
    }
  end)
  -- Whatever happened, give the caller back its game and its flags.
  M.pause(flags)
  game.swap_state(saved)
  if buf then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  if not ran then
    return { ok = false, result = result, claimed = replay.result, err = tostring(err) }
  end
  local finished = result and (result.outcome == 'dead' or result.outcome == 'won')
  local ok = finished and same_result(result, replay.result)
  local why
  if not finished then
    why = 'the keys run out before the run ends'
  elseif not ok then
    why = 'the replay does not reproduce the result it claims'
    if replay.suspended then
      why = why .. ' (the run was suspended and resumed, which replays cannot always follow)'
    end
  end
  return { ok = ok, result = result, claimed = replay.result, err = why }
end

-- Verify a replay and, for a daily run, add it to that day's ranking.
-- Returns the verify report plus rank (when ranked).
function M.import(replay)
  if replay.daily then
    -- A daily run must be that day's dungeon: its seed is the date, and the
    -- daily challenge is never the Abyss.
    local want = tonumber((replay.daily:gsub('-', '')))
    if replay.seed ~= want or replay.hard then
      return { ok = false, claimed = replay.result, err = 'not the ' .. replay.daily .. ' daily dungeon (seed or mode differs)' }
    end
  end
  local report = M.verify(replay)
  if report.ok and replay.daily then
    local r = report.result
    local _, rank = require('vimdungeons.daily').record(replay.daily, {
      name = replay.name or 'someone',
      class = r.class or 'wanderer',
      outcome = r.outcome,
      floor = r.floor,
      lv = r.lv,
      gold = r.gold,
      turns = r.turns,
      source = 'replay',
    })
    report.rank = rank
  end
  return report
end

return M
