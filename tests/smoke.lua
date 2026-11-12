-- nvim -l tests/smoke.lua で実行するスモークテスト
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
vim.opt.rtp:prepend(root)

-- Tests assert Japanese strings; pin the language to Japanese.
vim.g.vim_dungeons_lang = 'ja'

-- The game reseeds math.random before every key from its run seed, and an
-- ordinary run takes that seed from the clock. Several sections below set up
-- a random dungeon and then assume something about it, so pin the clock the
-- seed is read from: every run of the suite then sees the same dungeons.
do
  local uv = vim.uv or vim.loop
  local tick = 1
  uv.hrtime = function()
    tick = tick + 104729
    return tick * 1000003
  end
end

local dungeon = require('vimdungeons.dungeon')

-- 1. 生成マップの検証（床の上にスポーン・階段、外周は壁、階段まで到達可能）
math.randomseed(1234)
for floor = 1, 15 do
  for _ = 1, 10 do
    local map = dungeon.generate(floor, 'normal')
    assert(#map.rooms >= 2, 'at least 2 rooms')
    assert(map.grid[map.spawn.y][map.spawn.x] == '.', 'spawn on floor')
    assert(map.grid[map.stairs.y][map.stairs.x] == '.', 'stairs on floor')
    for x = 1, dungeon.W do
      assert(map.grid[1][x] == '#' and map.grid[dungeon.H][x] == '#', 'border wall (h)')
    end
    for y = 1, dungeon.H do
      assert(map.grid[y][1] == '#' and map.grid[y][dungeon.W] == '#', 'border wall (v)')
    end
    local seen = {}
    local stack = { { map.spawn.x, map.spawn.y } }
    seen[map.spawn.y * 1000 + map.spawn.x] = true
    while #stack > 0 do
      local c = table.remove(stack)
      local deltas = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
      for _, d in ipairs(deltas) do
        local nx, ny = c[1] + d[1], c[2] + d[2]
        local k = ny * 1000 + nx
        if nx >= 1 and nx <= dungeon.W and ny >= 1 and ny <= dungeon.H
          and not seen[k] and map.grid[ny][nx] == '.' then
          seen[k] = true
          stack[#stack + 1] = { nx, ny }
        end
      end
    end
    assert(seen[map.stairs.y * 1000 + map.stairs.x], 'stairs reachable from spawn')
  end
end
print('dungeon: OK')

-- 2. ゲームプレイのファズテスト（ランダム操作でエラー・不正状態が出ないこと）
require('vimdungeons').start({ new = true })
local game = require('vimdungeons.game')
local data = require('vimdungeons.data')

-- アイテム使用経路も通すため消費系を持たせておく（所持上限10を超えないように）
for _, d in ipairs(data.items) do
  if d.kind ~= 'weapon' and d.kind ~= 'shield' and #game.state().player.inv < 8 then
    table.insert(game.state().player.inv, d)
  end
end

math.randomseed(42)
local keys = { 'h', 'j', 'k', 'l', 'y', 'u', 'b', 'n', 'H', 'J', 'K', 'L', '.', '.', '>', 'i', 't', 'a', 'b', 'c', '?', 'esc' }
local deaths, max_floor = 0, 1
for i = 1, 5000 do
  local k = keys[math.random(#keys)]
  local ok, err = pcall(game.handle, k)
  assert(ok, ('step %d key %s: %s'):format(i, k, tostring(err)))
  local st = game.state()
  assert(st, 'state alive')
  if st.mode == 'dead' then
    deaths = deaths + 1
    game.handle('r')
    st = game.state()
  end
  max_floor = math.max(max_floor, st.floor)
  local p = st.player
  assert(st.map.grid[p.y][p.x] == '.', ('player on floor cell (step %d)'):format(i))
  assert(p.hp <= p.maxhp, 'hp <= maxhp')
  assert(#p.inv <= 10, 'inventory cap')
  for _, e in ipairs(st.enemies) do
    assert(st.map.grid[e.y][e.x] == '.', 'enemy on floor cell')
    assert(not (e.x == p.x and e.y == p.y), 'enemy not on player')
  end
end
print(('gameplay: OK (deaths=%d, max floor=%d)'):format(deaths, max_floor))

-- 以降のテストは部屋の存在を前提にするため、特殊フロア生成を無効化して通常フロアで再開する
local orig_generate = dungeon.generate
dungeon.generate = function(floor, kind)
  return orig_generate(floor, kind or 'normal')
end
game.new_game(game.state().buf)

-- 3. 階段降下（プレイヤーを階段に置いて>で次の階へ進めること）
game.handle('esc')
local st = game.state()
local before = st.floor
st.player.x, st.player.y = st.map.stairs.x, st.map.stairs.y
game.handle('>')
st = game.state()
assert(st.floor == before + 1, 'floor advanced by stairs')
assert(st.map.grid[st.player.y][st.player.x] == '.', 'player respawned on floor')
print('descend: OK')

-- 4. アイテム使用（薬草でHPが回復すること）
st.player.hp = 1
st.player.inv = { require('vimdungeons.data').items[1] }
game.handle('i')
game.handle('a')
st = game.state()
assert(st.player.hp > 1, 'herb healed hp')
assert(#st.player.inv == 0, 'herb consumed')
assert(st.mode == 'play', 'inventory closed after use')
print('item: OK')

-- 5. 装備（武器を装備でき、付け替えると古い装備が持ち物に戻ること）
local weapons = {}
for _, d in ipairs(require('vimdungeons.data').items) do
  if d.kind == 'weapon' then
    weapons[#weapons + 1] = d
  end
end
assert(#weapons >= 2, 'weapon defs exist')
st = game.state()
st.player.inv = { weapons[1] }
game.handle('i')
game.handle('a')
st = game.state()
assert(st.player.weapon == weapons[1], 'weapon equipped')
assert(#st.player.inv == 0, 'weapon moved out of inventory')
st.player.inv = { weapons[2] }
game.handle('i')
game.handle('a')
st = game.state()
assert(st.player.weapon == weapons[2], 'weapon swapped')
assert(st.player.inv[1] == weapons[1], 'old weapon returned to inventory')
print('equip: OK')

-- 6. 罠（踏むと発動して可視化される、落とし穴で階が進む）
st = game.state()
local traps_def = {}
for _, d in ipairs(require('vimdungeons.data').traps) do
  traps_def[d.kind] = d
end

local function find_pair()
  for y = 2, dungeon.H - 1 do
    for x = 2, dungeon.W - 2 do
      if st.map.grid[y][x] == '.' and st.map.grid[y][x + 1] == '.' then
        local free = true
        for _, e in ipairs(st.enemies) do
          if (e.x == x or e.x == x + 1) and e.y == y then
            free = false
          end
        end
        if free then
          return x, y
        end
      end
    end
  end
end

local tx, ty = find_pair()
assert(tx, 'found adjacent floor cells')
st.player.x, st.player.y = tx, ty
st.player.hp = st.player.maxhp
st.traps = { { x = tx + 1, y = ty, def = traps_def.spike, revealed = false } }
game.handle('l')
st = game.state()
assert(st.traps[1].revealed, 'trap revealed after trigger')
assert(st.player.hp < st.player.maxhp, 'spike trap damaged player')
if st.mode == 'dead' then
  game.handle('r')
  st = game.state()
end

local before_floor = st.floor
tx, ty = find_pair()
assert(tx, 'found adjacent floor cells for pit')
st.player.x, st.player.y = tx, ty
st.player.hp = st.player.maxhp
st.traps = { { x = tx + 1, y = ty, def = traps_def.pit, revealed = false } }
game.handle('l')
st = game.state()
assert(st.floor == before_floor + 1, 'pit dropped to next floor')
print('trap: OK')

-- 7. ダッシュ（大文字キーで部屋の端まで一直線に走る）
st = game.state()
st.player.hp = st.player.maxhp
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
local wide
for _, r in ipairs(st.map.rooms) do
  if r.w >= 4 then
    wide = r
    break
  end
end
assert(wide, 'wide room exists')
st.player.x, st.player.y = wide.x, wide.y
st.map.stairs = { x = wide.x, y = wide.y }  -- 進路上で停止しないよう足元へ退避
local turn_before = st.turn
game.handle('L')
st = game.state()
assert(st.player.x >= wide.x + wide.w - 1, 'dash ran to room edge')
assert(st.turn - turn_before >= 2, 'dash consumed multiple turns')
print('dash: OK')

-- 8. モンスターハウス（入室時に告知されること）
st = game.state()
st.player.hp = st.player.maxhp
st.mhouse = st.map.rooms[1]
st.mhouse_announced = false
st.player.x, st.player.y = st.mhouse.x, st.mhouse.y
game.handle('.')
st = game.state()
assert(st.mhouse_announced, 'monster house announced')
local announced = false
for _, m in ipairs(st.messages) do
  if m:find('モンスターハウス') then
    announced = true
  end
end
assert(announced, 'announce message exists')
print('mhouse: OK')

-- 9. 金貨ドロップ（撃破した敵が確率で金貨を落とすこと）
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
st.player.maxhp = 999
st.player.hp = 999
local dx2, dy2 = find_pair()
assert(dx2, 'found cells for drop test')
st.player.x, st.player.y = dx2, dy2
local drops = 0
for _ = 1, 60 do
  -- ターン経過の隠しスポーンに惑わされないよう、対象の敵だけを追跡する
  st.player.x, st.player.y = dx2, dy2
  local target = { name = 'テスト', char = 't', hp = 1, atk = 0, def = 0, exp = 0, x = dx2 + 1, y = dy2 }
  st.enemies = { target }
  st.golds = {}
  local guard = 0
  while target.hp > 0 and st.mode == 'play' and guard < 10 do
    game.handle('l')
    st = game.state()
    guard = guard + 1
  end
  if st.mode ~= 'play' then
    break
  end
  if #st.golds > 0 then
    drops = drops + 1
  end
end
assert(drops > 0, 'enemies sometimes drop gold')
print(('drop: OK (%d/60)'):format(drops))

-- 10. クリア判定（地下10階に聖典が配置され、拾うと勝利になること）
st = game.state()
st.floor = 9
st.player.x, st.player.y = st.map.stairs.x, st.map.stairs.y
game.handle('>')
st = game.state()
assert(st.floor == 10, 'reached goal floor')
local has_goal = false
for _, it in ipairs(st.items) do
  if it.def.kind == 'goal' then
    has_goal = true
  end
end
assert(has_goal, 'goal item placed on floor 10')
st.enemies, st.golds, st.traps = {}, {}, {}
st.player.hp = st.player.maxhp
local gx, gy = find_pair()
st.player.x, st.player.y = gx, gy
st.items = { { x = gx + 1, y = gy, def = require('vimdungeons.data').goal } }
game.handle('l')
st = game.state()
assert(st.mode == 'won', 'picking up goal wins the game')
game.handle('r')
st = game.state()
assert(st.mode == 'play' and st.floor == 1, 'restart after win')
print('goal: OK')

-- 11. fの巻物（視界内の対象へ跳ぶ、対象なし・escでは巻物が戻る）
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
st.player.maxhp = 999
st.player.hp = 999
local fdef
for _, d in ipairs(require('vimdungeons.data').items) do
  if d.id == 'scroll_f' then
    fdef = d
  end
end
assert(fdef, 'scroll_f def exists')
local froom
for _, r in ipairs(st.map.rooms) do
  if r.w >= 5 then
    froom = r
    break
  end
end
assert(froom, 'room for f test')
st.player.x, st.player.y = froom.x, froom.y
st.enemies = { { name = 'スライム', char = 's', hp = 99, atk = 0, def = 0, exp = 0, x = froom.x + 4, y = froom.y } }
game.handle('.')  -- 視界を更新
st = game.state()
st.player.inv = { fdef }
game.handle('i')
game.handle('a')
st = game.state()
assert(st.mode == 'fmotion', 'entered fmotion mode')
game.handle('s')
st = game.state()
assert(st.mode == 'play', 'back to play after jump')
local e1 = st.enemies[1]
local dist = math.max(math.abs(e1.x - st.player.x), math.abs(e1.y - st.player.y))
assert(dist == 1, 'jumped adjacent to enemy, dist=' .. dist)
assert(#st.player.inv == 0, 'scroll consumed on success')

st.player.inv = { fdef }
game.handle('i')
game.handle('a')
game.handle('esc')
st = game.state()
assert(st.mode == 'play' and #st.player.inv == 1, 'esc cancels and returns scroll')

game.handle('i')
game.handle('a')
game.handle('D')  -- ドラゴンは視界にいない
st = game.state()
assert(st.mode == 'play' and #st.player.inv == 1, 'no target returns scroll')
print('fmotion: OK')

-- 12. 未識別アイテム（見た目名で表示され、使うと識別されること）
st = game.state()
local herb_def = require('vimdungeons.data').items[1]
assert(herb_def.id == 'herb', 'items[1] is herb')
st.identified = {}
assert(st.appearance.herb, 'appearance assigned to herb')
local shown = game.display_name(herb_def)
assert(shown ~= '薬草', 'unidentified herb shows appearance name: ' .. shown)
st.player.inv = { herb_def }
st.player.hp = 1
game.handle('i')
game.handle('a')
st = game.state()
assert(st.identified.herb, 'herb identified after use')
assert(game.display_name(herb_def) == '薬草', 'real name shown after identify')
local id_msg = false
for _, m in ipairs(st.messages) do
  if m:find('薬草だった') then
    id_msg = true
  end
end
assert(id_msg, 'identify message shown')
print('identify: OK')

-- 13. 倍速モンスター（1ターンに2マス詰めてくること）
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
st.player.maxhp = 999
st.player.hp = 999
local sroom
for _, r in ipairs(st.map.rooms) do
  if r.w >= 5 then
    sroom = r
    break
  end
end
assert(sroom, 'room for speed test')
st.player.x, st.player.y = sroom.x, sroom.y
st.enemies = { { name = '2jうさぎ', char = '2', hp = 99, atk = 0, def = 0, exp = 0, speed = 2, x = sroom.x + 4, y = sroom.y } }
game.handle('.')
st = game.state()
local rb = st.enemies[1]
local rdist = math.max(math.abs(rb.x - st.player.x), math.abs(rb.y - st.player.y))
assert(rdist == 2, 'speed-2 enemy closed 2 cells, dist=' .. rdist)
print('speed: OK')

-- 14. 壁抜けモンスター（壁の中へ移動できること）
-- 「床-壁-床」の並び（縦横どちらでも）を探し、壁越しの追跡で敵が壁セルへ入ることを確認する
st = game.state()
local ppx, ppy, pdx, pdy
for _ = 1, 30 do
  for _, d in ipairs({ { 1, 0 }, { 0, 1 } }) do
    for y = 2, dungeon.H - 1 - d[2] * 2 do
      for x = 2, dungeon.W - 1 - d[1] * 2 do
        if st.map.grid[y][x] == '.'
          and st.map.grid[y + d[2]][x + d[1]] == '#'
          and st.map.grid[y + d[2] * 2][x + d[1] * 2] == '.' then
          ppx, ppy, pdx, pdy = x, y, d[1], d[2]
        end
      end
      if ppx then
        break
      end
    end
    if ppx then
      break
    end
  end
  if ppx then
    break
  end
  game.new_game(st.buf)
  st = game.state()
end
assert(ppx, 'found floor-wall-floor pattern')
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
st.player.maxhp = 999
st.player.hp = 999
st.player.x, st.player.y = ppx, ppy
local wallx, wally = ppx + pdx, ppy + pdy
st.enemies = { { name = 'ggゴースト', char = 'G', hp = 99, atk = 0, def = 0, exp = 0, phase = true, x = ppx + pdx * 2, y = ppy + pdy * 2 } }
game.handle('.')
st = game.state()
local gh = st.enemies[1]
assert(gh.x == wallx and gh.y == wally, 'ghost stepped into the wall, at ' .. gh.x .. ',' .. gh.y)
assert(st.map.grid[gh.y][gh.x] == '#', 'ghost is inside a wall cell')
print('phase: OK')

-- 15. 投擲（敵に当たればダメージ、外れれば床に落ちる、escで中止できる）
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
st.player.maxhp = 999
st.player.hp = 999
local troom
for _, r in ipairs(st.map.rooms) do
  if r.w >= 5 then
    troom = r
    break
  end
end
assert(troom, 'room for throw test')
st.player.x, st.player.y = troom.x, troom.y
st.map.stairs = { x = troom.x, y = troom.y }
local herb2 = require('vimdungeons.data').items[1]

-- 命中: 3マス先の敵に当たる
st.enemies = { { name = 'まと', char = 'm', hp = 99, atk = 0, def = 0, exp = 0, x = troom.x + 3, y = troom.y } }
st.player.inv = { herb2 }
game.handle('t')
st = game.state()
assert(st.mode == 'throw_select', 'entered throw select')
game.handle('a')
st = game.state()
assert(st.mode == 'throw_dir', 'entered throw direction')
game.handle('l')
st = game.state()
assert(st.mode == 'play', 'back to play after throw')
assert(st.enemies[1].hp == 94, 'thrown item dealt 5 damage, hp=' .. st.enemies[1].hp)
assert(#st.player.inv == 0, 'thrown item consumed')

-- 外れ: 敵を消して投げると床に落ちる
st.enemies = {}
st.player.inv = { herb2 }
game.handle('t')
game.handle('a')
game.handle('l')
st = game.state()
assert(#st.items == 1 and st.items[1].y == st.player.y and st.items[1].x > st.player.x,
  'missed item landed on floor ahead')

-- 中止: escで巻き戻る
st.player.inv = { herb2 }
game.handle('t')
game.handle('esc')
st = game.state()
assert(st.mode == 'play' and #st.player.inv == 1, 'cancel keeps item')
print('throw: OK')

-- 16. 杖（いかずちで20ダメージ、場所替えで位置交換、使い切ると砕ける）
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
st.player.maxhp = 999
st.player.hp = 999
local zroom
for _, r in ipairs(st.map.rooms) do
  if r.w >= 5 then
    zroom = r
    break
  end
end
assert(zroom, 'room for zap test')
st.player.x, st.player.y = zroom.x, zroom.y
st.map.stairs = { x = zroom.x, y = zroom.y }
local wand_defs = {}
for _, d in ipairs(require('vimdungeons.data').items) do
  if d.kind == 'wand' then
    wand_defs[d.id] = d
  end
end

-- いかずちの杖: 2回分で使い切りまで確認
local bolt = vim.tbl_extend('force', {}, wand_defs.wand_bolt, { charges = 2 })
st.enemies = { { name = 'まと', char = 'm', hp = 99, atk = 0, def = 0, exp = 0, x = zroom.x + 3, y = zroom.y } }
st.player.inv = { bolt }
game.handle('i')
game.handle('a')
st = game.state()
assert(st.mode == 'zap_dir', 'entered zap direction mode')
game.handle('l')
st = game.state()
assert(st.enemies[1].hp == 79, 'bolt dealt 20 damage, hp=' .. st.enemies[1].hp)
assert(#st.player.inv == 1 and st.player.inv[1].charges == 1, 'wand back with 1 charge')
game.handle('i')
game.handle('a')
game.handle('l')
st = game.state()
assert(#st.player.inv == 0, 'wand shattered after last charge')

-- 場所替えの杖: 位置が入れ替わる
st.enemies = { { name = 'まと', char = 'm', hp = 99, atk = 0, def = 0, exp = 0, x = zroom.x + 3, y = zroom.y } }
st.player.x, st.player.y = zroom.x, zroom.y
local swap = vim.tbl_extend('force', {}, wand_defs.wand_swap, { charges = 3 })
st.player.inv = { swap }
game.handle('i')
game.handle('a')
game.handle('l')
st = game.state()
assert(st.player.x == zroom.x + 3, 'player moved to enemy position, x=' .. st.player.x)
-- 入れ替え後に敵のターンが回って1マス追ってくるため、旧プレイヤー位置の周辺にいればよい
assert(st.enemies[1].x <= zroom.x + 1, 'enemy swapped to old player side, x=' .. st.enemies[1].x)
print('zap: OK')

-- 17. 状態異常（毒罠で毒、毎ターン減少、薬草で治療、混乱で移動がそれる、毒ヘビの付与）
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
st.player.maxhp = 999
st.player.hp = 999
st.player.status = {}
local ptx, pty = find_pair()
st.player.x, st.player.y = ptx, pty
st.traps = { { x = ptx + 1, y = pty, def = traps_def.poison, revealed = false } }
game.handle('l')
st = game.state()
assert(st.player.status.poison, 'poison trap inflicts poison')
local hp_before2 = st.player.hp
game.handle('.')
st = game.state()
assert(st.player.hp < hp_before2, 'poison drains hp each turn')

st.player.inv = { require('vimdungeons.data').items[1] }
game.handle('i')
game.handle('a')
st = game.state()
assert(not st.player.status.poison, 'herb cures poison')

-- 混乱: 右入力が確率でそれる
st.enemies, st.traps = {}, {}
st.player.status = { confusion = 1000 }
local wroom2
for _, r in ipairs(st.map.rooms) do
  if r.w >= 5 and r.h >= 3 then
    wroom2 = r
    break
  end
end
assert(wroom2, 'room for confusion test')
local cx = wroom2.x + 2
local cy = wroom2.y + 1
local strayed = 0
for _ = 1, 20 do
  st.player.x, st.player.y = cx, cy
  game.handle('l')
  st = game.state()
  if not (st.player.x == cx + 1 and st.player.y == cy) then
    strayed = strayed + 1
  end
end
assert(strayed > 0, 'confusion makes movement stray')
st.player.status = {}

-- 毒ヘビ: 隣接攻撃で毒が付与される
local vx, vy = find_pair()
st.player.x, st.player.y = vx, vy
st.enemies = { { name = '毒ヘビ', char = 'v', hp = 999, atk = 5, def = 0, exp = 0, venom = true, x = vx + 1, y = vy } }
local poisoned = false
for _ = 1, 60 do
  game.handle('.')
  st = game.state()
  if st.player.status.poison then
    poisoned = true
    break
  end
end
assert(poisoned, 'venom enemy inflicts poison')
st.player.status = {}
st.enemies = {}
print('status: OK')

-- 18. 装備強化値と:w!の巻物、HP警告
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
st.player.maxhp = 100
st.player.hp = 100
local club2 = vim.tbl_extend('force', {}, weapons[1], { mod = 2 })
st.player.inv = { club2 }
game.handle('i')
game.handle('a')
st = game.state()
assert(st.player.weapon == club2, 'modified weapon equipped')
assert(game.display_name(club2) == 'こん棒+2', 'mod shown in name: ' .. game.display_name(club2))

local up_def
for _, d in ipairs(require('vimdungeons.data').items) do
  if d.id == 'scroll_upgrade' then
    up_def = d
  end
end
assert(up_def, 'upgrade scroll exists')
st.player.inv = { up_def }
game.handle('i')
game.handle('a')
st = game.state()
assert(st.player.weapon.mod == 3, 'upgrade scroll raised mod to +3')
assert(game.display_name(st.player.weapon) == 'こん棒+3', 'upgraded name shown')

-- HP警告: 1/4以下に落ちた瞬間にメッセージが出る
st.player.hp = 20
game.handle('.')
st = game.state()
local warned = false
for _, m in ipairs(st.messages) do
  if m:find('危険だ') then
    warned = true
  end
end
assert(warned, 'low hp warning shown')
print('upgrade: OK')

-- 19. 呪われた装備（発覚まで見えない、外せない、:w!で解呪）と死因表示
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
st.player.weapon = nil
local cursed_club = vim.tbl_extend('force', {}, weapons[1], { mod = -1, cursed = true })
assert(game.display_name(cursed_club) == 'こん棒', 'curse hidden before equip')
st.player.inv = { cursed_club }
game.handle('i')
game.handle('a')
st = game.state()
assert(st.player.weapon == cursed_club, 'cursed weapon equipped')
assert(cursed_club.curse_known, 'curse revealed on equip')
assert(game.display_name(cursed_club) == 'こん棒-1(呪)', 'cursed name shown: ' .. game.display_name(cursed_club))

-- 呪い中は付け替え不可
local club3 = vim.tbl_extend('force', {}, weapons[1], { mod = 0 })
st.player.inv = { club3 }
game.handle('i')
game.handle('a')
st = game.state()
assert(st.player.weapon == cursed_club, 'cursed weapon cannot be swapped')
assert(#st.player.inv == 1, 'new weapon returned to inventory')

-- :w!で解呪
st.player.inv = { up_def }
game.handle('i')
game.handle('a')
st = game.state()
assert(not cursed_club.cursed, 'upgrade scroll removed curse')
assert(game.display_name(cursed_club) == 'こん棒', 'name back to normal (mod 0)')

-- 死因: 敵に倒されると名前が記録される
st.player.maxhp = 10
st.player.hp = 1
st.player.status = {}
local kx, ky = find_pair()
st.player.x, st.player.y = kx, ky
st.enemies = { { name = 'しかくいの', char = 'x', hp = 999, atk = 50, def = 0, exp = 0, x = kx + 1, y = ky } }
local guard2 = 0
while game.state().mode == 'play' and guard2 < 20 do
  game.handle('.')
  guard2 = guard2 + 1
end
st = game.state()
assert(st.mode == 'dead', 'player died')
assert(st.cause == 'しかくいの', 'death cause recorded: ' .. tostring(st.cause))
game.handle('r')
st = game.state()
assert(st.mode == 'play', 'restarted')
print('curse: OK')

-- 20. 眠りと不意打ち（眠る敵は動かない、攻撃で必中2倍、隣接で起きる）
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
st.player.maxhp = 999
st.player.hp = 999
st.player.status = {}
st.player.weapon = nil
local zx, zy = find_pair()
st.player.x, st.player.y = zx, zy
local sleeper = { name = 'ねぼすけ', char = 'z', hp = 999, atk = 50, def = 0, exp = 0, asleep = true, x = zx + 1, y = zy }
st.enemies = { sleeper }
-- 眠っている間は攻撃してこない（隣接で起きるが、起きたターンは行動しない）
local hp_b = st.player.hp
game.handle('.')
st = game.state()
assert(st.player.hp == hp_b, 'sleeping enemy does not attack on wake turn')
-- 不意打ち: 改めて眠らせて攻撃すると必中2倍
sleeper.asleep = true
local ehp = sleeper.hp
game.handle('l')
st = game.state()
assert(not sleeper.asleep, 'sneak attack wakes enemy')
assert(sleeper.hp < ehp, 'sneak attack always hits')
local sneak_msg = false
for _, m in ipairs(st.messages) do
  if m:find('不意打ち') then
    sneak_msg = true
  end
end
assert(sneak_msg, 'sneak message shown')
st.enemies = {}
print('sleep: OK')

-- 21. ハイスコア画面（コマンドでフロートが開き内容が表示される）
require('vimdungeons').scores()
local found_scores = false
for _, w in ipairs(vim.api.nvim_list_wins()) do
  local b = vim.api.nvim_win_get_buf(w)
  local l1 = vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or ''
  if l1:find('VimDungeons 記録') then
    found_scores = true
    vim.api.nvim_win_close(w, true)
  end
end
assert(found_scores, 'scores float opened')
print('scores: OK')

-- 22. ボス（聖典の上に立ち、動かず、ブレスを吐き、倒すと聖典に届く）
st = game.state()
st.floor = 9
st.player.x, st.player.y = st.map.stairs.x, st.map.stairs.y
game.handle('>')
st = game.state()
assert(st.floor == 10, 'on goal floor for boss test')
local boss
for _, e in ipairs(st.enemies) do
  if e.boss then
    boss = e
  end
end
assert(boss, 'boss spawned on goal floor')
local on_tome = false
for _, it in ipairs(st.items) do
  if it.def.kind == 'goal' and it.x == boss.x and it.y == boss.y then
    on_tome = true
  end
end
assert(on_tome, 'boss stands on the tome')

st.enemies = { boss }
st.traps = {}
st.mhouse = nil
st.player.maxhp = 999
st.player.hp = 999
st.player.status = {}
local bx, by = boss.x, boss.y

-- ブレス: 直線2マス先の床に立って待機すると焼かれる
local dirs4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local pos
for _, d in ipairs(dirs4) do
  local ok = true
  for i = 1, 2 do
    local cx2, cy2 = bx + d[1] * i, by + d[2] * i
    if not st.map.grid[cy2] or st.map.grid[cy2][cx2] ~= '.' then
      ok = false
      break
    end
  end
  if ok then
    pos = { bx + d[1] * 2, by + d[2] * 2 }
    break
  end
end
if pos then
  st.player.x, st.player.y = pos[1], pos[2]
  local hpb3 = st.player.hp
  game.handle('.')
  st = game.state()
  assert(st.player.hp < hpb3, 'boss breath damaged player')
else
  print('  (breath position not found, skipped)')
end
assert(boss.x == bx and boss.y == by, 'boss never moves')

-- 討伐して聖典を取るとクリア
boss.hp = 1
local adj
for _, d in ipairs(dirs4) do
  local ax, ay = bx + d[1], by + d[2]
  if st.map.grid[ay] and st.map.grid[ay][ax] == '.' then
    adj = { ax, ay, d }
  end
end
assert(adj, 'adjacent cell to boss exists')
st.player.x, st.player.y = adj[1], adj[2]
local delta_key = { ['-1,0'] = 'h', ['1,0'] = 'l', ['0,-1'] = 'k', ['0,1'] = 'j' }
local atk_key = delta_key[(bx - adj[1]) .. ',' .. (by - adj[2])]
assert(atk_key, 'attack direction resolved')
local guard4 = 0
local function boss_alive()
  for _, e in ipairs(game.state().enemies) do
    if e.boss then
      return true
    end
  end
  return false
end
while boss_alive() and game.state().mode == 'play' and guard4 < 15 do
  game.handle(atk_key)
  guard4 = guard4 + 1
end
assert(not boss_alive(), 'boss defeated')
game.handle(atk_key)
st = game.state()
assert(st.mode == 'won', 'picked up tome after boss defeat -> won')
game.handle('r')
print('boss: OK')

-- 23. 裏ダンジョン（支給品なし、地下25階に強化ボスと奥義書、クリアでhard記録）
game.new_game(game.state().buf, { hard = true })
st = game.state()
assert(st.hard, 'hard mode flag set')
assert(#st.player.inv == 0, 'no starting items in hard mode')
st.floor = 24
st.player.x, st.player.y = st.map.stairs.x, st.map.stairs.y
game.handle('>')
st = game.state()
assert(st.floor == 25, 'reached hard goal floor')
local hboss, htome
for _, e in ipairs(st.enemies) do
  if e.boss then
    hboss = e
  end
end
for _, it in ipairs(st.items) do
  if it.def.kind == 'goal' then
    htome = it
  end
end
assert(hboss and hboss.hp >= 160, 'hard boss doubled hp, hp=' .. tostring(hboss and hboss.hp))
assert(htome and htome.def.id == 'tome_hard', 'hard goal item placed')

-- 合成の奥義書を拾ってクリア -> hardフラグ付きで記録される
st.enemies, st.golds, st.traps = {}, {}, {}
st.player.maxhp = 999
st.player.hp = 999
local hx, hy = find_pair()
st.player.x, st.player.y = hx, hy
st.items = { { x = hx + 1, y = hy, def = require('vimdungeons.data').goal_hard } }
game.handle('l')
st = game.state()
assert(st.mode == 'won', 'hard clear')
local hard_recorded = false
for _, s2 in ipairs(require('vimdungeons.score').load()) do
  if s2.hard and s2.cleared then
    hard_recorded = true
  end
end
assert(hard_recorded, 'hard clear recorded in scores')
-- 通常モードに戻してから終了テストへ
game.new_game(st.buf)
st = game.state()
assert(not st.hard and st.floor == 1, 'back to normal mode')
print('hard: OK')

-- 24. メッセージ履歴（Mで開いてescで閉じる）
game.handle('M')
st = game.state()
assert(st.mode == 'log', 'log mode opened')
game.handle('esc')
st = game.state()
assert(st.mode == 'play', 'log mode closed')
print('log: OK')

-- 25. 特殊フロア（大広間・迷路の連結性と、部屋なしフロアでの配置フォールバック）
for _, fkind in ipairs({ 'hall', 'maze' }) do
  for _ = 1, 5 do
    local map = orig_generate(3, fkind)
    assert(map.kind == fkind, fkind .. ' generated')
    assert(map.grid[map.spawn.y][map.spawn.x] == '.', fkind .. ': spawn on floor')
    assert(map.grid[map.stairs.y][map.stairs.x] == '.', fkind .. ': stairs on floor')
    local seen2 = {}
    local stack2 = { { map.spawn.x, map.spawn.y } }
    seen2[map.spawn.y * 1000 + map.spawn.x] = true
    while #stack2 > 0 do
      local c = table.remove(stack2)
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = c[1] + d[1], c[2] + d[2]
        local kk = ny * 1000 + nx
        if nx >= 1 and nx <= dungeon.W and ny >= 1 and ny <= dungeon.H
          and not seen2[kk] and map.grid[ny][nx] == '.' then
          seen2[kk] = true
          stack2[#stack2 + 1] = { nx, ny }
        end
      end
    end
    assert(seen2[map.stairs.y * 1000 + map.stairs.x], fkind .. ': stairs reachable')
    if fkind == 'maze' then
      assert(#map.rooms == 0, 'maze has no rooms')
    else
      assert(#map.rooms == 1, 'hall has single room')
    end
  end
end

-- ゲーム内で迷路フロアに降り、部屋なしでも敵・アイテムが配置されること
dungeon.generate = function(floor, kind)
  return orig_generate(floor, kind or 'maze')
end
st = game.state()
st.player.hp = st.player.maxhp
st.player.x, st.player.y = st.map.stairs.x, st.map.stairs.y
game.handle('>')
st = game.state()
assert(st.map.kind == 'maze', 'descended into maze floor')
assert(#st.enemies > 0, 'enemies placed via floor_cells fallback')
assert(st.map.grid[st.player.y][st.player.x] == '.', 'player on maze floor')
game.handle('.')
dungeon.generate = function(floor, kind)
  return orig_generate(floor, kind or 'normal')
end
print('special floors: OK')

-- 26. ショップ（生成、購入と自動精算、持ち逃げで店主が敵対、店主は通れない）
-- 生成率12%なので十分な回数試行する
local found_shop = false
for _ = 1, 80 do
  game.new_game(game.state().buf)
  if game.state().shop then
    found_shop = true
    break
  end
end
assert(found_shop, 'shop generated within 80 attempts')
st = game.state()
local shop = st.shop
st.enemies, st.traps = {}, {}
st.mhouse = nil
st.player.maxhp = 999
st.player.hp = 999

-- 店主のマスへは移動できない
local kx2, ky2 = shop.keeper.x, shop.keeper.y
st.player.x, st.player.y = kx2 - 1, ky2
local t_before = st.turn
game.handle('l')
st = game.state()
assert(st.player.x == kx2 - 1, 'cannot walk onto keeper')
assert(st.turn == t_before, 'bumping keeper consumes no turn')

-- 購入: 商品を拾うとツケが積まれ、部屋を出ると自動精算される
local goods
for _, it in ipairs(st.items) do
  if it.def.price then
    goods = it
  end
end
assert(goods, 'priced goods exist')
st.player.x, st.player.y = goods.x, goods.y
st.player.gold = 9999
st.player.inv = {}
game.handle('.')  -- その場で1ターン（拾うのはpickup経由なので移動で乗る必要がある）
-- 商品の上に立っただけでは拾わないため、1マスずらして踏み直す
local step_from
for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
  local ax, ay = goods.x + d[1], goods.y + d[2]
  if st.map.grid[ay] and st.map.grid[ay][ax] == '.' and not (ax == kx2 and ay == ky2) then
    step_from = d
    break
  end
end
assert(step_from, 'cell adjacent to goods exists')
st.player.x, st.player.y = goods.x + step_from[1], goods.y + step_from[2]
local back_key = ({ ['-1,0'] = 'h', ['1,0'] = 'l', ['0,-1'] = 'k', ['0,1'] = 'j' })[string.format('%d,%d', -step_from[1], -step_from[2])]
game.handle(back_key)
st = game.state()
assert(game.shop_debt() > 0, 'debt accumulated after taking goods, debt=' .. game.shop_debt())
local debt = game.shop_debt()
local gold_before = st.player.gold
-- 部屋の外へテレポートして精算を発火
st.player.x, st.player.y = st.map.spawn.x, st.map.spawn.y
game.handle('.')
st = game.state()
assert(game.shop_debt() == 0, 'debt settled after leaving shop room')
assert(st.player.gold == gold_before - debt, 'gold paid')
assert(not st.shop.angry, 'keeper stays calm when paid')

-- 持ち逃げ: 所持金不足で部屋を出ると店主が敵対する
st.player.inv = { vim.tbl_extend('force', {}, require('vimdungeons.data').items[1], { price = 500 }) }
st.player.gold = 0
st.player.x, st.player.y = st.map.spawn.x, st.map.spawn.y
game.handle('.')
st = game.state()
assert(st.shop.angry, 'keeper angered by theft')
local keeper_enemy = false
for _, e in ipairs(st.enemies) do
  if e.char == 'K' then
    keeper_enemy = true
  end
end
assert(keeper_enemy, 'keeper joined enemies')
print('shop: OK')

-- 27. 売却（店内でSで売れる、半額買い取り、売った品は店頭に並ぶ、店外では売れない）
st = game.state()
-- 直前のショップテストの状態を利用（店主は敵対済みなので新しい店を作り直す）
local sroom2
for _, r in ipairs(st.map.rooms) do
  if r ~= dungeon.room_at(st.map, st.map.spawn.x, st.map.spawn.y) then
    sroom2 = r
    break
  end
end
assert(sroom2, 'room for sell test')
st.shop = {
  room = sroom2,
  keeper = { x = math.floor(sroom2.x + sroom2.w / 2), y = math.floor(sroom2.y + sroom2.h / 2) },
  angry = false,
}
st.consumed_debt = 0
st.enemies, st.items, st.traps = {}, {}, {}
st.player.maxhp = 999
st.player.hp = 999
-- 店外では売れない
st.player.x, st.player.y = st.map.spawn.x, st.map.spawn.y
st.player.inv = { require('vimdungeons.data').items[1] }
game.handle('S')
st = game.state()
assert(st.mode == 'play', 'cannot sell outside shop')
-- 店内で売る
local sx2, sy2 = sroom2.x, sroom2.y
if sx2 == st.shop.keeper.x and sy2 == st.shop.keeper.y then
  sx2 = sx2 + 1
end
st.player.x, st.player.y = sx2, sy2
local gold_b = st.player.gold
game.handle('S')
st = game.state()
assert(st.mode == 'sell_select', 'sell menu opened in shop')
game.handle('a')
st = game.state()
assert(#st.player.inv == 0, 'item sold')
assert(st.player.gold == gold_b + 20, 'got half price (herb 40G -> 20G), gold=' .. st.player.gold)
local restocked = false
for _, it in ipairs(st.items) do
  if it.def.price and it.def.id == 'herb' then
    restocked = true
  end
end
assert(restocked, 'sold item restocked with price')
game.handle('esc')
st = game.state()
assert(st.mode == 'play', 'sell menu closed')
print('sell: OK')

-- 28. 実績（撃破・大金・レベル10で解除され、一覧画面が開く）
local ach = require('vimdungeons.achievements')
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.shop = nil
st.mhouse = nil
st.player.maxhp = 999
st.player.hp = 999
-- 撃破
local ax2, ay2 = find_pair()
st.player.x, st.player.y = ax2, ay2
st.enemies = { { name = 'まと', char = 'm', hp = 1, atk = 0, def = 0, exp = 0, x = ax2 + 1, y = ay2 } }
local g4 = 0
while #st.enemies > 0 and g4 < 10 do
  game.handle('l')
  st = game.state()
  g4 = g4 + 1
end
assert(ach.unlocked('first_kill'), 'first_kill unlocked')
-- 大金
st.player.gold = 1500
game.handle('.')
assert(ach.unlocked('rich'), 'rich unlocked')
-- レベル10
st = game.state()
st.player.lv = 9
st.player.exp = 0
st.player.next_exp = 1
st.enemies = { { name = 'まと', char = 'm', hp = 1, atk = 0, def = 0, exp = 5, x = ax2 + 1, y = ay2 } }
st.player.x, st.player.y = ax2, ay2
g4 = 0
while #st.enemies > 0 and g4 < 10 do
  game.handle('l')
  st = game.state()
  g4 = g4 + 1
end
assert(st.player.lv >= 10, 'reached lv10, lv=' .. st.player.lv)
assert(ach.unlocked('lv10'), 'lv10 unlocked')
-- 一覧画面
require('vimdungeons').achievements()
local found_ach = false
for _, w in ipairs(vim.api.nvim_list_wins()) do
  local b = vim.api.nvim_win_get_buf(w)
  local l1 = vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or ''
  if l1:find('VimDungeons 実績') then
    found_ach = true
    vim.api.nvim_win_close(w, true)
  end
end
assert(found_ach, 'achievements float opened')
print('achievements: OK')

-- 29. 中断セーブ（Qで保存、再開で状態復元、セーブは再開時に消費される）
local savemod = require('vimdungeons.save')
game.new_game(game.state().buf)
st = game.state()
st.player.gold = 777
st.player.inv = { require('vimdungeons.data').items[1] }
game.handle('.')
st = game.state()
local sus_floor = st.floor
local sus_turn = st.turn
local sus_x, sus_y = st.player.x, st.player.y
game.handle('Q')
assert(game.state() == nil, 'quit after suspend')
assert(savemod.load() ~= nil, 'suspend save written')
require('vimdungeons').start()
st = game.state()
assert(st, 'resumed')
assert(st.player.gold == 777, 'gold restored')
assert(st.floor == sus_floor and st.turn == sus_turn, 'floor and turn restored')
assert(st.player.x == sus_x and st.player.y == sus_y, 'position restored')
assert(#st.player.inv == 1 and st.player.inv[1].id == 'herb', 'inventory restored')
assert(savemod.load() == nil, 'save consumed on resume')
local resumed_msg = false
for _, m in ipairs(st.messages) do
  if m:find('再開した') then
    resumed_msg = true
  end
end
assert(resumed_msg, 'resume message shown')
-- 復元後も普通に遊べる
game.handle('.')
st = game.state()
assert(st.turn == sus_turn + 1, 'game continues after resume')
print('suspend: OK')

-- 30. 腕輪（装備できる、ちからで攻撃力+3、毒消しで毒無効）
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.shop = nil
st.mhouse = nil
st.player.maxhp = 999
st.player.hp = 999
st.player.status = {}
st.player.weapon = nil
st.player.ring = nil
st.player.atk = 6
local ring_defs = {}
for _, d in ipairs(require('vimdungeons.data').items) do
  if d.kind == 'ring' then
    ring_defs[d.id] = d
  end
end
assert(ring_defs.ring_power and ring_defs.ring_antidote, 'ring defs exist')

-- 装備
st.player.inv = { ring_defs.ring_power }
game.handle('i')
game.handle('a')
st = game.state()
assert(st.player.ring == ring_defs.ring_power, 'ring equipped')
assert(#st.player.inv == 0, 'ring moved out of inventory')

-- ちからの腕輪: 眠っている敵への不意打ち（必中2倍）で最低(6+3-1)*2=16ダメージ
local rx, ry = find_pair()
st.player.x, st.player.y = rx, ry
local dummy = { name = 'まと', char = 'm', hp = 999, atk = 0, def = 0, exp = 0, asleep = true, x = rx + 1, y = ry }
st.enemies = { dummy }
game.handle('l')
st = game.state()
local dealt = 999 - dummy.hp
assert(dealt >= 16, 'power ring boosted damage, dealt=' .. dealt)

-- 毒消しの腕輪: 毒罠を踏んでも毒にならない
st.player.ring = ring_defs.ring_antidote
st.enemies = {}
local px3, py3 = find_pair()
st.player.x, st.player.y = px3, py3
st.traps = { { x = px3 + 1, y = py3, def = traps_def.poison, revealed = false } }
game.handle('l')
st = game.state()
assert(not st.player.status.poison, 'antidote ring blocked poison')
local blocked = false
for _, m in ipairs(st.messages) do
  if m:find('毒を防いだ') then
    blocked = true
  end
end
assert(blocked, 'block message shown')
st.player.ring = nil
print('ring: OK')

-- 31. モンスター図鑑（撃破で記録が増え、フラッシュで永続化され、一覧が開く）
local dexmod = require('vimdungeons.dex')
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
st.player.maxhp = 999
st.player.hp = 999
local before_kills = (dexmod.data()['スライム'] or { kills = 0 }).kills or 0
local dxx, dyy = find_pair()
st.player.x, st.player.y = dxx, dyy
local slime2 = { name = 'スライム', char = 's', hp = 1, atk = 0, def = 0, exp = 0, x = dxx + 1, y = dyy }
st.enemies = { slime2 }
local g5 = 0
while slime2.hp > 0 and g5 < 10 do
  game.handle('l')
  st = game.state()
  g5 = g5 + 1
end
local rec = dexmod.data()['スライム']
assert(rec and rec.kills == before_kills + 1, 'dex kill count incremented')
assert(rec.seen, 'dex seen flag set')
dexmod.flush()
local df = io.open(vim.fn.stdpath('data') .. '/vimdungeons_dex.json', 'r')
assert(df, 'dex file written')
local dcontent = df:read('*a')
df:close()
assert(dcontent:find('スライム'), 'dex file contains slime record')
require('vimdungeons').dex()
local found_dex = false
for _, w in ipairs(vim.api.nvim_list_wins()) do
  local b = vim.api.nvim_win_get_buf(w)
  local l1 = vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or ''
  if l1:find('モンスター図鑑') then
    found_dex = true
    vim.api.nvim_win_close(w, true)
  end
end
assert(found_dex, 'dex float opened')
print('dex: OK')

-- 32. 自動探索（oで未探索方向へ複数ターン歩く）と図鑑コンプ実績
game.new_game(game.state().buf)
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
st.shop = nil
local explored_before = 0
for _ in pairs(st.explored) do
  explored_before = explored_before + 1
end
local turn_before2 = st.turn
local pos_before = st.player.x * 1000 + st.player.y
game.handle('o')
st = game.state()
assert(st.turn > turn_before2, 'auto explore consumed turns')
local explored_after = 0
for _ in pairs(st.explored) do
  explored_after = explored_after + 1
end
assert(explored_after > explored_before, 'auto explore expanded known area')

-- 図鑑コンプ実績: 全種を遭遇済みにして1ターン経過
for _, d in ipairs(require('vimdungeons.data').enemies) do
  dexmod.mark_seen(d.name)
end
dexmod.mark_seen(require('vimdungeons.data').keeper.name)
dexmod.mark_seen(require('vimdungeons.data').boss.name)
game.handle('.')
assert(ach.unlocked('dex_complete'), 'dex_complete unlocked')
print('explore: OK')

-- 33. 新罠（大部屋の罠でフロアが大広間化、召喚の罠で敵が湧く）
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
st.shop = nil
st.player.maxhp = 999
st.player.hp = 999
st.player.status = {}
local traps_def2 = {}
for _, d in ipairs(require('vimdungeons.data').traps) do
  traps_def2[d.kind] = d
end
assert(traps_def2.bigroom and traps_def2.summon, 'new trap defs exist')

-- 大部屋の罠
local bx2, by2 = find_pair()
st.player.x, st.player.y = bx2, by2
st.traps = { { x = bx2 + 1, y = by2, def = traps_def2.bigroom, revealed = false } }
game.handle('l')
st = game.state()
assert(st.map.kind == 'hall', 'floor turned into a hall')
assert(#st.map.rooms == 1, 'single big room')
assert(st.map.grid[3][3] == '.', 'walls collapsed to floor')
local all_visible = st.visible[3 * 1000 + 3]
assert(all_visible, 'whole floor visible after bigroom trap')

-- 召喚の罠
st.enemies, st.traps = {}, {}
local sx3, sy3 = find_pair()
st.player.x, st.player.y = sx3, sy3
st.traps = { { x = sx3 + 1, y = sy3, def = traps_def2.summon, revealed = false } }
game.handle('l')
st = game.state()
assert(#st.enemies >= 2, 'summon trap spawned enemies, n=' .. #st.enemies)
local near = 0
for _, e in ipairs(st.enemies) do
  if math.abs(e.x - st.player.x) <= 3 and math.abs(e.y - st.player.y) <= 3 then
    near = near + 1
  end
end
assert(near >= 2, 'summoned enemies are near the player')
print('traps2: OK')

-- 34. 置く（dで足元に置ける、店の商品を置くとツケが消える、足元に物があると置けない）
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
st.player.maxhp = 999
st.player.hp = 999
local dpx, dpy = find_pair()
st.player.x, st.player.y = dpx, dpy
st.map.stairs = { x = dpx - 1, y = dpy }
local herb_plain = require('vimdungeons.data').items[1]
st.player.inv = { herb_plain }
game.handle('d')
st = game.state()
assert(st.mode == 'drop_select', 'drop menu opened')
game.handle('a')
st = game.state()
assert(#st.player.inv == 0, 'item dropped from inventory')
assert(#st.items == 1 and st.items[1].x == dpx and st.items[1].y == dpy, 'item placed at feet')
assert(st.mode == 'play', 'back to play after drop')

-- 足元に物がある場合は置けない
st.player.inv = { herb_plain }
game.handle('d')
game.handle('a')
st = game.state()
assert(#st.player.inv == 1, 'cannot drop onto occupied cell')

-- 店の商品を店内で置くとツケが消える
local droom
for _, r in ipairs(st.map.rooms) do
  droom = r
  break
end
st.shop = {
  room = droom,
  keeper = { x = droom.x + 90, y = droom.y },  -- 干渉しない遠方扱い
  angry = false,
}
st.consumed_debt = 0
st.items = {}
st.player.x, st.player.y = droom.x, droom.y
st.player.inv = { vim.tbl_extend('force', {}, herb_plain, { price = 40 }) }
assert(game.shop_debt() == 40, 'carrying priced goods counts as debt')
game.handle('d')
game.handle('a')
st = game.state()
assert(game.shop_debt() == 0, 'debt cleared after returning goods')
local returned = false
for _, m in ipairs(st.messages) do
  if m:find('棚に戻した') then
    returned = true
  end
end
assert(returned, 'return message shown')
st.shop = nil
print('drop: OK')

-- 35. 日替わりチャレンジ（同じ日は同じダンジョン、スコアにdailyフラグ）
game.new_game(game.state().buf, { daily = true })
st = game.state()
assert(st.daily, 'daily flag set')
local rows1 = {}
for y = 1, dungeon.H do
  rows1[y] = table.concat(st.map.grid[y])
end
local stairs1 = st.map.stairs.x .. ',' .. st.map.stairs.y
local items1 = {}
for _, it in ipairs(st.items) do
  items1[#items1 + 1] = it.x .. ',' .. it.y .. ':' .. it.def.id
end
game.new_game(st.buf, { daily = true })
st = game.state()
for y = 1, dungeon.H do
  assert(table.concat(st.map.grid[y]) == rows1[y], 'daily dungeon deterministic (row ' .. y .. ')')
end
assert(stairs1 == st.map.stairs.x .. ',' .. st.map.stairs.y, 'stairs deterministic')
local items2 = {}
for _, it in ipairs(st.items) do
  items2[#items2 + 1] = it.x .. ',' .. it.y .. ':' .. it.def.id
end
assert(table.concat(items1, '|') == table.concat(items2, '|'), 'item placement deterministic')
-- 死亡記録にdailyが付く（上位10件のトリムに残るよう階数を上げておく）
st.floor = 99
st.player.hp = 1
st.enemies = { { name = 'まと', char = 'm', hp = 999, atk = 99, def = 0, exp = 0, x = st.player.x, y = st.player.y - 1 } }
if st.map.grid[st.player.y - 1][st.player.x] ~= '.' then
  st.enemies[1].y = st.player.y + 1
end
local g6 = 0
while game.state().mode == 'play' and g6 < 20 do
  game.handle('.')
  g6 = g6 + 1
end
st = game.state()
assert(st.mode == 'dead', 'daily run ended')
local daily_recorded = false
for _, s3 in ipairs(require('vimdungeons.score').load()) do
  if s3.daily then
    daily_recorded = true
  end
end
assert(daily_recorded, 'daily flag recorded in scores')
game.new_game(st.buf)
print('daily: OK')

-- 36. 裏ダンジョン実績（地下15階到達で「深淵を覗くもの」）
game.new_game(game.state().buf, { hard = true })
st = game.state()
st.floor = 14
st.player.x, st.player.y = st.map.stairs.x, st.map.stairs.y
st.player.maxhp = 999
st.player.hp = 999
game.handle('>')
st = game.state()
assert(st.floor == 15, 'reached hard floor 15')
assert(ach.unlocked('abyss'), 'abyss achievement unlocked')
game.new_game(st.buf)
print('abyss: OK')

-- 37. 石（スタック合流、1個ずつ投げて8ダメージ）とよくみえの腕輪（罠が見える）
st = game.state()
st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
st.mhouse = nil
st.shop = nil
st.player.maxhp = 999
st.player.hp = 999
st.player.ring = nil
local stone_def
for _, dd in ipairs(require('vimdungeons.data').items) do
  if dd.id == 'stone' then
    stone_def = dd
  end
end
assert(stone_def, 'stone def exists')
-- スタック合流: 2個持ち+床の3個 -> 5個
local spx, spy = find_pair()
st.player.x, st.player.y = spx + 1, spy
st.player.inv = { vim.tbl_extend('force', {}, stone_def, { count = 2 }) }
st.items = { { x = spx, y = spy, def = vim.tbl_extend('force', {}, stone_def, { count = 3 }) } }
game.handle('h')
st = game.state()
assert(#st.player.inv == 1 and st.player.inv[1].count == 5, 'stones merged into stack')
-- 投擲: 1個消費で8ダメージ
local ste = { name = 'まと', char = 'm', hp = 99, atk = 0, def = 0, exp = 0, x = st.player.x + 1, y = st.player.y }
if st.map.grid[ste.y][ste.x] ~= '.' then
  ste.x = st.player.x - 1
end
st.enemies = { ste }
game.handle('t')
game.handle('a')
game.handle(ste.x > st.player.x and 'l' or 'h')
st = game.state()
assert(ste.hp == 91, 'stone dealt 8 damage, hp=' .. ste.hp)
assert(st.player.inv[1] and st.player.inv[1].count == 4, 'one stone consumed from stack')
-- よくみえの腕輪: 未発動の罠が描画される
st.enemies = {}
local ring_sight_def
for _, dd in ipairs(require('vimdungeons.data').items) do
  if dd.id == 'ring_sight' then
    ring_sight_def = dd
  end
end
local trx, try2 = find_pair()
st.traps = { { x = trx, y = try2, def = traps_def.spike, revealed = false } }
st.player.x, st.player.y = trx + 1, try2
game.handle('.')
st = game.state()
local render_mod = require('vimdungeons.render')
render_mod.draw(st)
local line_no_ring = vim.api.nvim_buf_get_lines(st.buf, try2, try2 + 1, false)[1]
assert(line_no_ring:sub(trx, trx) ~= '^', 'trap hidden without ring')
st.player.ring = ring_sight_def
render_mod.draw(st)
local line_ring = vim.api.nvim_buf_get_lines(st.buf, try2, try2 + 1, false)[1]
assert(line_ring:sub(trx, trx) == '^', 'trap visible with sight ring')
st.player.ring = nil
print('stone/sightring: OK')

-- 38. 英語表示（デフォルトenでメッセージ・ステータス行・名前が翻訳される）
vim.g.vim_dungeons_lang = 'en'
game.new_game(game.state().buf)
st = game.state()
local en_msg = false
for _, m in ipairs(st.messages) do
  if m:find('You step into floor B1') then
    en_msg = true
  end
end
assert(en_msg, 'intro message translated to English')
local render_mod2 = require('vimdungeons.render')
render_mod2.draw(st)
local status_line = vim.api.nvim_buf_get_lines(st.buf, 0, 1, false)[1]
assert(status_line:find('Hunger'), 'status line translated: ' .. status_line)
assert(game.display_name(require('vimdungeons.data').items[1]) ~= '薬草', 'item name translated')
-- 未翻訳キーは日本語にフォールバックする
assert(require('vimdungeons.i18n').t('存在しないキー') == '存在しないキー', 'fallback to Japanese')
vim.g.vim_dungeons_lang = 'ja'
game.new_game(st.buf)
print('i18n: OK')

-- 39. 終了処理（Qはプレイ画面でのみ有効なので、先にescでモードを戻す）
game.handle('esc')
game.handle('Q')
assert(game.state() == nil, 'state cleared after quit')
-- テストが中断セーブを残さないよう掃除する
require('vimdungeons.save').clear()
print('quit: OK')

-- 40. 職業（初期能力・持ち物・識別・忍び足）
do
  local buf40 = vim.api.nvim_create_buf(false, true)
  local cls = require('vimdungeons.data')
  game.new_game(buf40, { class = 'fighter', seed = 7 })
  local s40 = game.state()
  assert(s40.class == 'fighter' and s40.player.maxhp == 28 and s40.player.hp == 28, 'fighter hp')
  assert(s40.player.atk == 8 and s40.player.weapon and s40.player.weapon.id == 'club' and s40.player.weapon.mod == 1, 'fighter kit')
  game.new_game(buf40, { class = 'thief', seed = 7 })
  s40 = game.state()
  local stones = 0
  for _, it in ipairs(s40.player.inv) do
    if it.id == 'stone' then
      stones = it.count
    end
  end
  assert(stones == 5 and s40.player.maxhp == 18, 'thief kit')
  game.new_game(buf40, { class = 'sage', seed = 7 })
  s40 = game.state()
  assert(s40.identified.scroll_f and s40.identified.wand_swap and not s40.identified.herb, 'sage knows scrolls and wands')
  local wand
  for _, it in ipairs(s40.player.inv) do
    if it.id == 'wand_bolt' then
      wand = it
    end
  end
  assert(wand and wand.charges == 3 and s40.player.maxhp == 16, 'sage kit')
  -- 職業選択画面: c で盗賊
  game.new_game(buf40, { choose_class = true, seed = 7 })
  s40 = game.state()
  assert(s40.mode == 'class_select', 'class menu first')
  game.handle('c')
  s40 = game.state()
  assert(s40.mode == 'play' and s40.class == 'thief' and s40.replay.class == 'thief' and s40.replay.choose, 'class chosen')
  assert(#cls.classes == 4, 'four classes')
  pcall(vim.api.nvim_buf_delete, buf40, { force = true })
end
print('classes: OK')

-- 41. キーごとの再シード: 途中で他のコードが math.random を呼んでも同じ結果になる
do
  local buf41 = vim.api.nvim_create_buf(false, true)
  local seq = {}
  local cycle = { 'o', 'o', 'l', 'j', '.', 'h', 'k', '>', 'o', 'y', 'n' }
  for i = 1, 400 do
    seq[i] = cycle[(i % #cycle) + 1]
  end
  local function run(noise)
    game.new_game(buf41, { seed = 4242, class = 'fighter', headless = true })
    for _, k in ipairs(seq) do
      if noise then
        for _ = 1, 3 do
          math.random()
        end
      end
      game.handle(k)
      if game.state().mode ~= 'play' and game.state().mode ~= 'inventory' then
        break
      end
    end
    local s = game.state()
    return table.concat({ s.floor, s.turn, s.player.x, s.player.y, s.player.hp, s.player.gold, s.mode }, ',')
  end
  local a, b = run(false), run(true)
  assert(a == b, 'same keys, same run despite outside math.random: ' .. a .. ' vs ' .. b)
  pcall(vim.api.nvim_buf_delete, buf41, { force = true })
end
print('reseed: OK')

-- 42. リプレイ: 記録・エンコード・検証・改ざん検知・永続化の停止
do
  local rp = require('vimdungeons.replay')
  local daily = require('vimdungeons.daily')
  local buf42 = vim.api.nvim_create_buf(false, true)
  -- 休み続ければ空腹でいずれ倒れる（敵にやられてもよい）。確実に終わる操作列。
  game.new_game(buf42, { daily = true, daily_date = '2026-11-12', seed = 20261112, choose_class = true, headless = true })
  game.handle('b') -- 戦士
  local cycle = { 'o', 'o', '.', '.', '.', '.', '.', '.', '>' }
  local i = 0
  while game.state().mode ~= 'dead' and game.state().mode ~= 'won' and i < 20000 do
    i = i + 1
    game.handle(cycle[(i % #cycle) + 1])
  end
  local s42 = game.state()
  assert(s42.mode == 'dead' or s42.mode == 'won', 'run ended')
  local replay = s42.replay
  assert(replay.result and replay.result.turns == s42.turn and replay.class == 'fighter', 'replay sealed')
  assert(rp.last() and rp.last().seed == 20261112, 'last replay kept')

  -- 自分の日替わり記録がランキングに入っている
  local mine = daily.list('2026-11-12')
  local has_mine = false
  for _, e in ipairs(mine) do
    if e.class == 'fighter' and e.source == 'local' and e.turns == s42.turn then
      has_mine = true
    end
  end
  assert(has_mine, 'daily ranking has the run')

  -- エンコード/デコードの往復
  local decoded = assert(rp.decode(rp.encode(replay)))
  assert(#decoded.keys == #replay.keys and decoded.keys[1] == 'b', 'roundtrip keys')
  assert(rp.decode('{}') == nil and rp.decode('nope') == nil, 'bad files rejected')

  -- 検証: 現在のゲーム状態は退避・復元され、スコアは書かれない
  local before_state = game.state()
  local scores_before = vim.json.encode(require('vimdungeons.score').load())
  local report = rp.verify(decoded)
  assert(report.ok, 'replay verifies: ' .. tostring(report.err))
  assert(game.state() == before_state, 'current state restored')
  assert(vim.json.encode(require('vimdungeons.score').load()) == scores_before, 'verify writes no scores')
  assert(not require('vimdungeons.score').paused, 'persistence resumed')

  -- 改ざん: 最後のキーを削ると結果が合わない
  local tampered = vim.deepcopy(decoded)
  tampered.result.gold = tampered.result.gold + 1
  assert(not rp.verify(tampered).ok, 'tampered result rejected')
  local short = vim.deepcopy(decoded)
  for _ = 1, math.min(50, #short.keys - 1) do
    table.remove(short.keys)
  end
  local r2 = rp.verify(short)
  assert(not r2.ok, 'truncated keys rejected')

  -- インポート: 他人のリプレイとしてランキングへ
  decoded.name = 'friend'
  local imported = rp.import(decoded)
  assert(imported.ok and imported.rank, 'imported into the ranking')
  local found = false
  for _, e in ipairs(daily.list('2026-11-12')) do
    if e.name == 'friend' and e.source == 'replay' then
      found = true
    end
  end
  assert(found, 'friend listed')

  -- ランキングの並び: 踏破 > 深い階 > 少ないターン
  local list = {
    { outcome = 'dead', floor = 3, turns = 100 },
    { outcome = 'won', floor = 10, turns = 900 },
    { outcome = 'dead', floor = 5, turns = 300 },
    { outcome = 'dead', floor = 5, turns = 200 },
  }
  table.sort(list, daily.better)
  assert(list[1].outcome == 'won' and list[2].turns == 200 and list[4].floor == 3, 'ranking order')
  pcall(vim.api.nvim_buf_delete, buf42, { force = true })
end
print('replay: OK')

-- 43. リプレイの信頼性: Q・不正ファイル・日替わりの照合・フラグ復元
do
  local rp = require('vimdungeons.replay')
  local buf43 = vim.api.nvim_create_buf(false, true)
  -- play モードの Q はリプレイ中は無視され、タブは閉じない
  local tabs = #vim.api.nvim_list_tabpages()
  local r = rp.verify({ version = 1, seed = 5, keys = { 'Q', 'l', 'Q' } })
  assert(#vim.api.nvim_list_tabpages() == tabs, 'Q in a replay closes nothing')
  assert(not r.ok, 'unfinished replay is not ok')
  -- メニュー中の Q は記録される
  game.new_game(buf43, { seed = 9, headless = true })
  local s43 = game.state()
  s43.mode = 'fmotion'
  s43.pending_f = require('vimdungeons.data').items[1]
  local n = #s43.replay.keys
  game.handle('Q')
  assert(#game.state().replay.keys == n + 1, 'Q outside play mode is recorded')
  -- 不正なファイル
  for _, bad in ipairs({
    '{"version":1,"seed":1,"keys":"l","result":true}',
    '{"version":1,"seed":-1,"keys":"l"}',
    '{"version":1,"seed":1,"keys":"l","name":{"x":1}}',
    '{"version":1,"seed":1,"keys":"l\\u0001"}',
    '{"version":1,"seed":1,"keys":"l","result":{"outcome":"won","floor":"x","lv":1,"gold":0,"turns":1}}',
    '{"version":1,"seed":1,"keys":"l","hard":"yes"}',
  }) do
    assert(rp.decode(bad) == nil, 'rejected: ' .. bad)
  end
  assert(rp.decode(string.rep(' ', rp.MAX_BYTES + 1)) == nil, 'too large rejected')
  -- 日替わりは日付由来のシードでなければ登録しない
  local fake = { version = 1, seed = 42, daily = '1999-01-01', keys = { 'l' }, result = { outcome = 'dead', floor = 1, lv = 1, gold = 0, turns = 1 } }
  local rep = rp.import(fake)
  assert(not rep.ok and rep.err:find('daily dungeon'), 'daily seed checked')
  -- フラグは元の値に戻る
  require('vimdungeons.score').paused = true
  rp.verify({ version = 1, seed = 5, keys = { 'l' } })
  assert(require('vimdungeons.score').paused == true, 'flags restored to their previous values')
  rp.pause(false)
  pcall(vim.api.nvim_buf_delete, buf43, { force = true })
end
print('replay trust: OK')
