-- Buffer rendering and floating windows.
local api = vim.api
local dungeon = require('vimdungeons.dungeon')
local T = require('vimdungeons.i18n').t

local M = {}
local ns = api.nvim_create_namespace('vimdungeons')
local ns_anim = api.nvim_create_namespace('vimdungeons_anim')

-- Projectile animation: light up each path cell frame by frame (no-op without a UI).
function M.animate(st, path, ch, hl)
  if not st or st.headless then
    return
  end
  if #api.nvim_list_uis() == 0 or not st or not api.nvim_buf_is_valid(st.buf) then
    return
  end
  local uv = vim.uv or vim.loop
  for _, cell in ipairs(path) do
    M.draw(st)
    api.nvim_buf_set_extmark(st.buf, ns_anim, cell[2], cell[1] - 1, {
      virt_text = { { ch, hl } },
      virt_text_pos = 'overlay',
    })
    vim.cmd('redraw')
    uv.sleep(25)
    api.nvim_buf_clear_namespace(st.buf, ns_anim, 0, -1)
  end
end

local function key_of(x, y)
  return y * 1000 + x
end

function M.close_float(st)
  if st and st.float and api.nvim_win_is_valid(st.float) then
    api.nvim_win_close(st.float, true)
  end
  if st then
    st.float = nil
  end
end

local function open_float(st, lines)
  M.close_float(st)
  local width = 10
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  st.float = api.nvim_open_win(buf, false, {
    relative = 'editor',
    style = 'minimal',
    border = 'rounded',
    width = width + 2,
    height = #lines,
    row = math.max(0, math.floor((vim.o.lines - #lines) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    focusable = false,
    zindex = 60,
  })
end

function M.draw(st)
  if st.headless then
    return
  end
  if not st or not api.nvim_buf_is_valid(st.buf) then
    return
  end
  local game = require('vimdungeons.game')
  local p = st.player
  local lines = {}
  local ailment = ''
  if p.status and p.status.poison then
    ailment = ailment .. T(' [毒]')
  end
  if p.status and p.status.confusion then
    ailment = ailment .. T(' [混乱]')
  end
  lines[1] = string.format(
    T('%s地下%d階  Lv:%d  HP:%d/%d  満腹度:%d  G:%d  ターン:%d  武:%s  盾:%s  腕:%s%s'),
    st.hard and T('【裏】') or (st.daily and T('【日替】') or ''), st.floor, p.lv, p.hp, p.maxhp, p.hunger, p.gold, st.turn,
    p.weapon and game.display_name(p.weapon) or '-',
    p.shield and game.display_name(p.shield) or '-',
    p.ring and game.display_name(p.ring) or '-', ailment
  )

  -- overlay[cell] = {char, highlight, show-when-explored}
  local overlay = {}
  local sees_traps = game.player_sees_traps()
  for _, t in ipairs(st.traps or {}) do
    if t.revealed or sees_traps then
      overlay[key_of(t.x, t.y)] = { '^', 'VimDungeonsTrap', true }
    end
  end
  overlay[key_of(st.map.stairs.x, st.map.stairs.y)] = { '>', 'VimDungeonsStairs', true }
  for _, g in ipairs(st.golds) do
    overlay[key_of(g.x, g.y)] = { '$', 'VimDungeonsGold', true }
  end
  for _, it in ipairs(st.items) do
    local hl = it.def.kind == 'goal' and 'VimDungeonsGoal' or 'VimDungeonsItem'
    overlay[key_of(it.x, it.y)] = { it.def.char, hl, true }
  end
  for _, e in ipairs(st.enemies) do
    local k = key_of(e.x, e.y)
    if st.visible[k] then
      overlay[k] = { e.char, e.asleep and 'VimDungeonsEnemySleep' or 'VimDungeonsEnemy', false }
    end
  end
  if st.shop and not st.shop.angry then
    local kk = key_of(st.shop.keeper.x, st.shop.keeper.y)
    if st.visible[kk] then
      overlay[kk] = { 'K', 'VimDungeonsKeeper', false }
    end
  end
  overlay[key_of(p.x, p.y)] = { '@', 'VimDungeonsPlayer', false }

  local marks = {}
  for y = 1, dungeon.H do
    local chars = {}
    local hls = {}
    for x = 1, dungeon.W do
      local k = key_of(x, y)
      local vis = st.visible[k]
      local c, hl = ' ', nil
      if st.explored[k] then
        c = st.map.grid[y][x]
        hl = vis and (c == '#' and 'VimDungeonsWall' or 'VimDungeonsFloor') or 'VimDungeonsDim'
        local o = overlay[k]
        if o and (vis or o[3]) then
          c = o[1]
          hl = vis and o[2] or 'VimDungeonsDim'
        end
      end
      chars[x] = c
      hls[x] = hl
    end
    lines[1 + y] = table.concat(chars)
    local runstart, runhl = nil, nil
    for x = 1, dungeon.W + 1 do
      local hl = hls[x]
      if hl ~= runhl then
        if runhl then
          marks[#marks + 1] = { y, runstart - 1, x - 1, runhl }
        end
        runstart, runhl = x, hl
      end
    end
  end
  lines[dungeon.H + 2] = string.rep('-', dungeon.W)
  local mstart = #st.messages - 3
  for i = 0, 3 do
    lines[dungeon.H + 3 + i] = st.messages[mstart + i] or ''
  end

  vim.bo[st.buf].modifiable = true
  api.nvim_buf_set_lines(st.buf, 0, -1, false, lines)
  vim.bo[st.buf].modifiable = false

  api.nvim_buf_clear_namespace(st.buf, ns, 0, -1)
  local status_hl = p.hp <= math.floor(p.maxhp / 4) and 'VimDungeonsStatusDanger' or 'VimDungeonsStatus'
  api.nvim_buf_set_extmark(st.buf, ns, 0, 0, { end_col = #lines[1], hl_group = status_hl })
  for _, m in ipairs(marks) do
    api.nvim_buf_set_extmark(st.buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
  api.nvim_buf_set_extmark(st.buf, ns, dungeon.H + 1, 0, { end_col = dungeon.W, hl_group = 'VimDungeonsDim' })

  -- Keep the cursor on the player.
  local win = api.nvim_get_current_win()
  if api.nvim_win_get_buf(win) == st.buf then
    pcall(api.nvim_win_set_cursor, win, { 1 + p.y, p.x - 1 })
  end

  if st.mode == 'inventory' or st.mode == 'throw_select' or st.mode == 'sell_select'
    or st.mode == 'drop_select' then
    local titles = {
      inventory = T(' == 持ち物 =='),
      throw_select = T(' == 何を投げる？ =='),
      sell_select = T(' == 何を売る？ =='),
      drop_select = T(' == 何を置く？ =='),
    }
    local ls = { titles[st.mode] }
    if #p.inv == 0 then
      ls[#ls + 1] = T(' (何も持っていない)')
    else
      for i, it in ipairs(p.inv) do
        local extra = ''
        -- Hide the modifier of unrevealed cursed gear so it looks normal.
        local shown_mod = (it.cursed and not it.curse_known) and 0 or (it.mod or 0)
        if it.kind == 'weapon' then
          extra = (T('(攻+%d)')):format(it.power + shown_mod)
        elseif it.kind == 'shield' then
          extra = (T('(守+%d)')):format(it.power + shown_mod)
        elseif it.kind == 'wand' then
          extra = ('[%d]'):format(it.charges or 0)
        elseif it.kind == 'stone' then
          extra = (' x%d'):format(it.count or 1)
        end
        if st.mode == 'sell_select' then
          extra = extra .. (' <%dG>'):format(game.sell_price_of(it))
        end
        ls[#ls + 1] = (' %s) %s%s'):format(string.char(96 + i), game.display_name(it), extra)
      end
    end
    ls[#ls + 1] = ''
    if st.mode == 'inventory' then
      ls[#ls + 1] = T(' a-j:使う/装備する  q:閉じる')
    elseif st.mode == 'sell_select' then
      ls[#ls + 1] = T(' a-j:売る  q:やめる')
    elseif st.mode == 'drop_select' then
      ls[#ls + 1] = T(' a-j:置く  q:やめる')
    else
      ls[#ls + 1] = T(' a-j:選ぶ  q:やめる')
    end
    open_float(st, ls)
  elseif st.mode == 'log' then
    local ls = { T(' == メッセージ履歴 ==') }
    local max_rows = math.max(5, vim.o.lines - 8)
    local from = math.max(1, #st.messages - max_rows + 1)
    for i = from, #st.messages do
      ls[#ls + 1] = ' ' .. st.messages[i]
    end
    ls[#ls + 1] = ''
    ls[#ls + 1] = T(' q:閉じる')
    open_float(st, ls)
  elseif st.mode == 'help' then
    open_float(st, {
      T(' == 操作方法 =='),
      T(' 【移動】'),
      T('  h j k l / 矢印 :上下左右   y u b n :斜め'),
      T('  H J K L Y U B N:同方向へダッシュ(イベントで停止)'),
      T('  o :自動探索     . :その場で休む   > :階段を降りる'),
      T(' 【アイテム】'),
      T('  i :持ち物(a-jで使用/装備)   t :投げる'),
      T('  d :足元に置く               S :店で売る(店内)'),
      T(' 【情報】'),
      T('  M :メッセージ履歴   ? :このヘルプ   Q :中断して終了'),
      '',
      T(' 敵にぶつかると攻撃。眠る敵への攻撃は不意打ち2倍。'),
      T(' HPは歩くと回復し、満腹度0でじわじわ減る。'),
      T(' 武器)盾]腕輪=は装備、草!巻物?杖/は使用、&が目標。'),
      T(' 見えない罠^に注意。呪い装備は:w!の巻物で解呪。'),
      T(' 店Kの商品は精算制。dで棚に戻せる。'),
      '',
      T(' q:閉じる'),
    })
  elseif st.mode == 'class_select' then
    local data = require('vimdungeons.data')
    local ls = { T(' == 職業を選ぶ =='), '' }
    for i, c in ipairs(data.classes) do
      ls[#ls + 1] = (' %s) %s - %s'):format(string.char(96 + i), T(c.name), T(c.desc))
    end
    ls[#ls + 1] = ''
    ls[#ls + 1] = (T(' a-%s:選ぶ')):format(string.char(96 + #data.classes))
    open_float(st, ls)
  elseif st.mode == 'dead' or st.mode == 'won' then
    local ls
    if st.mode == 'won' then
      if st.hard then
        ls = {
          T('  Neovimの奥義書を手に入れた！'),
          T('   裏ダンジョン踏破…完全制覇だ！'),
          '',
          (T('  記録: Lv%d / %dG / %dターン')):format(p.lv, p.gold, st.turn),
        }
      else
        ls = {
          T('  Vimの聖典を手に入れた！'),
          T('   ダンジョン踏破、おめでとう！'),
          '',
          (T('  記録: Lv%d / %dG / %dターン')):format(p.lv, p.gold, st.turn),
        }
      end
    else
      ls = {
        T('     力尽きた…'),
        '',
        (T('  死因: %s')):format(st.cause and T(st.cause) or T('不明')),
        (T('  記録: 地下%d階 / Lv%d')):format(st.floor, p.lv),
        (T('        %dG / %dターン')):format(p.gold, st.turn),
      }
    end
    if st.best and st.best[1] then
      ls[#ls + 1] = (T('  最高記録: 地下%d階%s')):format(
        st.best[1].floor, st.best[1].cleared and T('(踏破)') or '')
    end
    local ach = require('vimdungeons.achievements')
    local unlocked_map = ach.load()
    local done = 0
    for _, d in ipairs(ach.defs) do
      if unlocked_map[d.id] then
        done = done + 1
      end
    end
    ls[#ls + 1] = (T('  実績: %d/%d (:VimDungeonsAchievements)')):format(done, #ach.defs)
    if st.daily and not st.replaying then
      ls[#ls + 1] = (T('  日替わり順位: :VimDungeonsRanking %s')):format(st.daily)
    end
    if not st.replaying then
      ls[#ls + 1] = T('  リプレイ保存: :VimDungeonsReplay export')
    end
    ls[#ls + 1] = ''
    if st.mode == 'won' and not st.hard then
      ls[#ls + 1] = T('  r:もう一度  h:裏ダンジョンへ  q:やめる')
    else
      ls[#ls + 1] = T('  r:もう一度  q:やめる')
    end
    open_float(st, ls)
  else
    M.close_float(st)
  end
end

return M
