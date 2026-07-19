-- nvim -l tests/balance.lua で実行する自動プレイバランス計測
-- 環境変数 RUNS で試行回数を指定（既定20）
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
vim.opt.rtp:prepend(root)

-- Tests assert Japanese strings; pin the language to Japanese.
vim.g.vim_dungeons_lang = 'ja'

-- HARD=1 で裏ダンジョンを計測する
local N = tonumber(vim.env.RUNS or '20')
local HARD = vim.env.HARD ~= nil
require('vimdungeons').start(HARD and { hard = true } or { new = true })
local game = require('vimdungeons.game')
local dungeon = require('vimdungeons.dungeon')

-- プレイヤー位置から(tx,ty)への最短経路の最初の1歩をキーで返す
-- 店主のマスは通れない（ぶつかってもターンを消費せず無限ループになる）ため避ける
local function bfs_next(st, tx, ty)
  local keeper_x, keeper_y
  if st.shop and not st.shop.angry then
    keeper_x, keeper_y = st.shop.keeper.x, st.shop.keeper.y
  end
  local prev = {}
  local q = { { st.player.x, st.player.y } }
  local seen = { [st.player.y * 1000 + st.player.x] = true }
  local head = 1
  while q[head] do
    local c = q[head]
    head = head + 1
    if c[1] == tx and c[2] == ty then
      local k = ty * 1000 + tx
      local path = {}
      while prev[k] do
        path[#path + 1] = k
        k = prev[k]
      end
      local firstk = path[#path]
      if not firstk then
        return nil
      end
      local fx = firstk % 1000
      local fy = math.floor(firstk / 1000)
      local dx, dy = fx - st.player.x, fy - st.player.y
      if dx == -1 then
        return 'h'
      elseif dx == 1 then
        return 'l'
      elseif dy == -1 then
        return 'k'
      else
        return 'j'
      end
    end
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = c[1] + d[1], c[2] + d[2]
      local key = ny * 1000 + nx
      if nx >= 1 and nx <= dungeon.W and ny >= 1 and ny <= dungeon.H
        and not seen[key] and st.map.grid[ny][nx] == '.'
        and not (nx == keeper_x and ny == keeper_y) then
        seen[key] = true
        prev[key] = c[2] * 1000 + c[1]
        q[#q + 1] = { nx, ny }
      end
    end
  end
  return nil
end

local adj_key = {
  ['-1,-1'] = 'y', ['0,-1'] = 'k', ['1,-1'] = 'u',
  ['-1,0'] = 'h', ['1,0'] = 'l',
  ['-1,1'] = 'b', ['0,1'] = 'j', ['1,1'] = 'n',
}

local function effective(it)
  return it.power + (it.mod or 0)
end

local function bot_step()
  local st = game.state()
  local p = st.player

  -- 店のツケが所持金を超えていたら、店内で未精算でない持ち物を売って工面する
  if st.shop and not st.shop.angry and game.shop_debt() > 0 and p.gold < game.shop_debt() then
    local slot
    for i, it in ipairs(p.inv) do
      if not it.price then
        slot = i
        break
      end
    end
    if slot then
      game.handle('S')
      if game.state().mode == 'sell_select' then
        game.handle(string.char(96 + slot))
        game.handle('esc')
        return
      end
    end
  end

  -- 低HPで薬草、空腹でパン
  if p.hp < p.maxhp * 0.4 then
    for i, it in ipairs(p.inv) do
      if it.kind == 'heal' then
        game.handle('i')
        game.handle(string.char(96 + i))
        return
      end
    end
  end
  if p.hunger < 20 then
    for i, it in ipairs(p.inv) do
      if it.kind == 'food' then
        game.handle('i')
        game.handle(string.char(96 + i))
        return
      end
    end
  end

  -- より強い装備に更新（呪い装備中は諦める）
  for i, it in ipairs(p.inv) do
    if it.kind == 'weapon' and not (p.weapon and p.weapon.cursed)
      and (not p.weapon or effective(it) > effective(p.weapon)) then
      game.handle('i')
      game.handle(string.char(96 + i))
      return
    end
    if it.kind == 'shield' and not (p.shield and p.shield.cursed)
      and (not p.shield or effective(it) > effective(p.shield)) then
      game.handle('i')
      game.handle(string.char(96 + i))
      return
    end
  end

  -- 隣接する敵を攻撃（斜めは角抜け禁止ルールで無効な場合があるので確認する）
  local function grid_ok(x, y)
    return st.map.grid[y] and st.map.grid[y][x] == '.'
  end
  for _, e in ipairs(st.enemies) do
    local dx, dy = e.x - p.x, e.y - p.y
    if math.abs(dx) <= 1 and math.abs(dy) <= 1 and (dx ~= 0 or dy ~= 0) then
      local diagonal_blocked = dx ~= 0 and dy ~= 0
        and not (grid_ok(p.x + dx, p.y) and grid_ok(p.x, p.y + dy))
      if not diagonal_blocked then
        game.handle(adj_key[dx .. ',' .. dy])
        return
      end
    end
  end

  -- ボスがいればボスへ向かう
  for _, e in ipairs(st.enemies) do
    if e.boss then
      local k = bfs_next(st, e.x, e.y)
      if k then
        game.handle(k)
        return
      end
    end
  end
  -- 視界に敵がいれば最寄りの敵へ向かう（自動探索は敵が見えると動かないため）
  local vis
  for _, e in ipairs(st.enemies) do
    if st.visible[e.y * 1000 + e.x] then
      local d = math.abs(e.x - p.x) + math.abs(e.y - p.y)
      if not vis or d < vis.d then
        vis = { e = e, d = d }
      end
    end
  end
  if vis then
    local k = bfs_next(st, vis.e.x, vis.e.y)
    if k then
      game.handle(k)
      return
    end
  end
  -- 階段の上なら降りる
  if p.x == st.map.stairs.x and p.y == st.map.stairs.y then
    game.handle('>')
    return
  end
  -- あとは自動探索に任せる（進めなければ階段へ）
  local t0 = st.turn
  game.handle('o')
  if game.state().turn == t0 then
    local k = bfs_next(game.state(), st.map.stairs.x, st.map.stairs.y)
    if k then
      game.handle(k)
    else
      game.handle('.')
    end
  end
end

local results = {}
for _ = 1, N do
  local steps = 0
  while steps < 4000 do
    local st = game.state()
    if st.mode == 'dead' or st.mode == 'won' then
      break
    end
    if st.mode ~= 'play' then
      game.handle('esc')
    end
    bot_step()
    steps = steps + 1
  end
  local st = game.state()
  results[#results + 1] = {
    mode = st.mode, floor = st.floor, cause = st.cause, turn = st.turn, lv = st.player.lv,
  }
  if vim.env.VERBOSE then
    print(('run: mode=%s floor=%d lv=%d turn=%d hunger=%d cause=%s steps=%d'):format(
      st.mode, st.floor, st.player.lv, st.turn, st.player.hunger, tostring(st.cause), steps))
  end
  if st.mode == 'dead' or st.mode == 'won' then
    game.handle('r')
  else
    game.new_game(st.buf, { hard = HARD })
  end
end

-- 集計
local wins, floors, causes, lvs = 0, {}, {}, {}
for _, r in ipairs(results) do
  if r.mode == 'won' then
    wins = wins + 1
  else
    local c = r.mode == 'dead' and (r.cause or '不明') or 'stall'
    causes[c] = (causes[c] or 0) + 1
  end
  floors[#floors + 1] = r.floor
  lvs[#lvs + 1] = r.lv
end
table.sort(floors)
local fsum, lsum = 0, 0
for i = 1, #floors do
  fsum = fsum + floors[i]
  lsum = lsum + lvs[i]
end
print(('runs=%d  wins=%d (%.0f%%)'):format(N, wins, wins / N * 100))
print(('floor: avg=%.1f  median=%d  max=%d'):format(fsum / N, floors[math.ceil(N / 2)], floors[N]))
print(('lv: avg=%.1f'):format(lsum / N))
local clist = {}
for c, n in pairs(causes) do
  clist[#clist + 1] = ('%s:%d'):format(c, n)
end
table.sort(clist)
print('deaths: ' .. table.concat(clist, '  '))
