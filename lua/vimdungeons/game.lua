-- Game state and turn-based logic.
local dungeon = require('vimdungeons.dungeon')
local data = require('vimdungeons.data')
local render = require('vimdungeons.render')
local score = require('vimdungeons.score')
local ach = require('vimdungeons.achievements')
local savemod = require('vimdungeons.save')
local items = require('vimdungeons.items')
local enemies_mod = require('vimdungeons.enemies')
local dex = require('vimdungeons.dex')
local T = require('vimdungeons.i18n').t

-- Session cache for the codex-complete achievement (avoids per-turn file IO).
local dex_complete_done = nil

local M = {}
local st = nil

local INV_MAX = 10
local GOAL_FLOOR = 10
local HARD_GOAL_FLOOR = 25

local function goal_floor()
  return st.hard and HARD_GOAL_FLOOR or GOAL_FLOOR
end

local function key_of(x, y)
  return y * 1000 + x
end

local function msg(text)
  table.insert(st.messages, text)
  if #st.messages > 60 then
    table.remove(st.messages, 1)
  end
end

-- Unlock an achievement (message only on first unlock).
local function unlock(id)
  if ach.unlock(id) then
    local d = ach.def_of(id)
    msg(T('実績解除『%s』！'):format(T(d and d.name or id)))
  end
end

-- Unidentified items are shown by their appearance name.
local function disp(def)
  local name
  if def.unidentified and not st.identified[def.id] then
    name = T(st.appearance[def.id] or def.name)
  else
    name = T(def.name)
  end
  if (def.kind == 'weapon' or def.kind == 'shield') and (def.mod or 0) ~= 0 then
    if def.cursed and not def.curse_known then
      -- Curse not yet revealed, so it looks like normal gear.
      return name
    end
    name = name .. ('%+d'):format(def.mod)
  end
  if def.cursed and def.curse_known then
    name = name .. T('(呪)')
  end
  return name
end

-- Equipment power including the upgrade modifier.
local function equip_power(it)
  return it.power + (it.mod or 0)
end

function M.display_name(def)
  return disp(def)
end

-- For rendering: whether the insight bracelet is worn.
function M.player_sees_traps()
  return st ~= nil and st.player.ring ~= nil and st.player.ring.id == 'ring_sight'
end

local function walkable(x, y)
  return x >= 1 and x <= dungeon.W and y >= 1 and y <= dungeon.H and st.map.grid[y][x] == '.'
end

local function enemy_at(x, y)
  for _, e in ipairs(st.enemies) do
    if e.x == x and e.y == y then
      return e
    end
  end
end

local function trap_at(x, y)
  for _, t in ipairs(st.traps or {}) do
    if t.x == x and t.y == y then
      return t
    end
  end
end

-- Cell occupied by the (not yet hostile) shopkeeper.
local function keeper_at(x, y)
  return st.shop ~= nil and not st.shop.angry
    and st.shop.keeper.x == x and st.shop.keeper.y == y
end

local function occupied(x, y)
  if st.player.x == x and st.player.y == y then
    return true
  end
  if keeper_at(x, y) then
    return true
  end
  return enemy_at(x, y) ~= nil
end

-- Diagonal moves require both adjacent cells to be floor (no corner cutting).
local function can_step(x, y, dx, dy)
  if not walkable(x + dx, y + dy) then
    return false
  end
  if dx ~= 0 and dy ~= 0 then
    if not walkable(x + dx, y) or not walkable(x, y + dy) then
      return false
    end
  end
  return true
end

local function sign(v)
  if v > 0 then
    return 1
  elseif v < 0 then
    return -1
  end
  return 0
end

-- Mystery-Dungeon-style vision: whole room plus border inside rooms, radius 1 in corridors.
local function compute_fov()
  st.visible = {}
  local p = st.player
  local function mark(x, y)
    if x >= 1 and x <= dungeon.W and y >= 1 and y <= dungeon.H then
      local k = key_of(x, y)
      st.visible[k] = true
      st.explored[k] = true
    end
  end
  local room = dungeon.room_at(st.map, p.x, p.y)
  if room then
    for y = room.y - 1, room.y + room.h do
      for x = room.x - 1, room.x + room.w do
        mark(x, y)
      end
    end
  end
  for dy = -1, 1 do
    for dx = -1, 1 do
      mark(p.x + dx, p.y + dy)
    end
  end
end

local function random_room_cell()
  -- On roomless floors (mazes) pick from floor cells instead.
  if #st.map.rooms == 0 then
    local c = st.map.floor_cells[math.random(#st.map.floor_cells)]
    return c[1], c[2]
  end
  local r = st.map.rooms[math.random(#st.map.rooms)]
  return math.random(r.x, r.x + r.w - 1), math.random(r.y, r.y + r.h - 1)
end

local function pick_item_def()
  local cands = {}
  local total = 0
  for _, d in ipairs(data.items) do
    if st.floor >= (d.min_floor or 1) then
      cands[#cands + 1] = d
      total = total + d.weight
    end
  end
  local r = math.random(total)
  local picked = cands[1]
  for _, d in ipairs(cands) do
    r = r - d.weight
    if r <= 0 then
      picked = d
      break
    end
  end
  -- Wands carry charges, gear carries modifiers, stones carry counts, so return per-instance copies.
  if picked.kind == 'stone' then
    picked = vim.tbl_extend('force', {}, picked, { count = math.random(2, 4) })
  elseif picked.kind == 'wand' then
    picked = vim.tbl_extend('force', {}, picked, { charges = math.random(3, 5) })
  elseif picked.kind == 'weapon' or picked.kind == 'shield' then
    local roll = math.random(100)
    local mod = 0
    if roll <= 15 then
      mod = -1
    elseif roll <= 70 then
      mod = 0
    elseif roll <= 90 then
      mod = 1
    elseif roll <= 98 then
      mod = 2
    else
      mod = 3
    end
    -- Negative gear is cursed (unnoticeable until equipped).
    picked = vim.tbl_extend('force', {}, picked, { mod = mod, cursed = mod < 0 or nil })
  end
  return picked
end

function M.sell_price_of(def)
  return items.sell_price(def)
end

local function setup_floor()
  st.map = dungeon.generate(st.floor)
  if st.map.kind == 'hall' then
    st.floor_note = 'だだっ広い大広間のフロアだ'
  elseif st.map.kind == 'maze' then
    st.floor_note = '入り組んだ迷路のフロアだ…'
  else
    st.floor_note = nil
  end
  st.player.x, st.player.y = st.map.spawn.x, st.map.spawn.y
  st.enemies, st.items, st.golds, st.traps = {}, {}, {}, {}
  st.shop, st.consumed_debt = nil, 0
  st.visible, st.explored = {}, {}
  compute_fov()
  for _ = 1, math.min(10, 4 + math.floor(st.floor / 2)) do
    enemies_mod.spawn()
  end
  for _ = 1, 3 + math.random(0, 2) do
    local x, y = random_room_cell()
    st.items[#st.items + 1] = { x = x, y = y, def = pick_item_def() }
  end
  for _ = 1, math.random(1, 3) do
    local x, y = random_room_cell()
    st.golds[#st.golds + 1] = { x = x, y = y, amount = math.random(10, 30) + st.floor * 5 }
  end
  for _ = 1, 2 + math.random(0, 2) do
    for _ = 1, 30 do
      local x, y = random_room_cell()
      if not (x == st.map.stairs.x and y == st.map.stairs.y)
        and not (x == st.player.x and y == st.player.y)
        and not trap_at(x, y) then
        st.traps[#st.traps + 1] = {
          x = x,
          y = y,
          def = data.traps[math.random(#data.traps)],
          revealed = false,
        }
        break
      end
    end
  end
  -- 25% chance of a monster house (one non-starting room packed with enemies and items).
  -- On hall floors, 20% chance of a big-room monster house (the room is the whole floor).
  st.mhouse, st.mhouse_announced = nil, false
  if st.map.kind == 'hall' then
    if math.random(5) == 1 then
      st.mhouse = st.map.rooms[1]
    end
  elseif #st.map.rooms >= 3 and math.random(4) == 1 then
    local spawn_room = dungeon.room_at(st.map, st.player.x, st.player.y)
    for _ = 1, 20 do
      local r = st.map.rooms[math.random(#st.map.rooms)]
      if r ~= spawn_room then
        st.mhouse = r
        break
      end
    end
  end
  do
    if st.mhouse then
      for _ = 1, 5 + math.floor(st.floor / 2) do
        enemies_mod.spawn({ room = st.mhouse })
      end
      for _ = 1, 3 do
        local r = st.mhouse
        local x, y = math.random(r.x, r.x + r.w - 1), math.random(r.y, r.y + r.h - 1)
        st.items[#st.items + 1] = { x = x, y = y, def = pick_item_def() }
      end
    end
  end
  -- 12% chance of a shop (normal floors only) with a keeper and priced goods.
  if st.map.kind == 'normal' and #st.map.rooms >= 3 and math.random(100) <= 12 then
    local spawn_room = dungeon.room_at(st.map, st.player.x, st.player.y)
    for _ = 1, 20 do
      local r = st.map.rooms[math.random(#st.map.rooms)]
      if r ~= spawn_room and r ~= st.mhouse then
        local kx, ky = math.floor(r.x + r.w / 2), math.floor(r.y + r.h / 2)
        if not occupied(kx, ky) and not (kx == st.map.stairs.x and ky == st.map.stairs.y) then
          st.shop = { room = r, keeper = { x = kx, y = ky }, angry = false }
          for _ = 1, 3 do
            for _ = 1, 20 do
              local x, y = math.random(r.x, r.x + r.w - 1), math.random(r.y, r.y + r.h - 1)
              if not (x == kx and y == ky)
                and not (x == st.map.stairs.x and y == st.map.stairs.y) then
                local def = pick_item_def()
                def = vim.tbl_extend('force', {}, def, { price = items.price(def) })
                st.items[#st.items + 1] = { x = x, y = y, def = def }
                break
              end
            end
          end
          break
        end
      end
    end
  end

  -- On the goal floor, place the tome with the guardian dragon standing on it.
  if st.floor >= goal_floor() then
    for _ = 1, 30 do
      local x, y = random_room_cell()
      if not (x == st.player.x and y == st.player.y)
        and not (x == st.map.stairs.x and y == st.map.stairs.y)
        and not occupied(x, y) then
        st.items[#st.items + 1] = { x = x, y = y, def = st.hard and data.goal_hard or data.goal }
        local b = data.boss
        local mul = st.hard and 2 or 1
        st.enemies[#st.enemies + 1] = {
          name = b.name, char = b.char, hp = b.hp * mul, atk = b.atk + (st.hard and 8 or 0),
          def = b.def + (st.hard and 2 or 0), exp = b.exp * mul,
          boss = true, x = x, y = y,
        }
        msg(T('空気が張り詰めている…聖典の守護者の気配がする'))
        break
      end
    end
  end
end

local STATUS_LABEL = { poison = '毒', confusion = '混乱' }

-- Forward declaration; also called from trigger_trap (pitfalls).
local check_mhouse

-- Whether the bracelet with the given id is worn.
local function has_ring(id)
  if id == 'ring_sneak' and st.class == 'thief' then
    return true -- the thief sneaks without the bracelet
  end
  return st.player.ring ~= nil and st.player.ring.id == id
end

local function add_status(name, turns)
  if name == 'poison' and has_ring('ring_antidote') then
    msg(T('毒消しの腕輪が毒を防いだ！'))
    return
  end
  local p = st.player
  if not p.status[name] or p.status[name] < turns then
    p.status[name] = turns
  end
end

local function trigger_trap()
  if st.mode ~= 'play' then
    return
  end
  local p = st.player
  local t = trap_at(p.x, p.y)
  if not t then
    return
  end
  t.revealed = true
  local kind = t.def.kind
  if kind ~= 'warp' and kind ~= 'confuse' and kind ~= 'bigroom' and kind ~= 'summon' then
    st.cause = t.def.name
  end
  if kind == 'spike' then
    local dmg = 4 + st.floor
    p.hp = p.hp - dmg
    msg(T('とげの罠だ！%dのダメージを受けた'):format(dmg))
  elseif kind == 'poison' then
    p.hp = p.hp - 2
    add_status('poison', 8)
    msg(T('毒矢の罠だ！体に毒が回った'))
  elseif kind == 'confuse' then
    add_status('confusion', 8)
    msg(T('混乱の罠だ！足元がおぼつかない…'))
  elseif kind == 'bigroom' then
    -- The walls collapse, turning the whole floor into one big room.
    for y = 2, dungeon.H - 1 do
      for x = 2, dungeon.W - 1 do
        st.map.grid[y][x] = '.'
      end
    end
    st.map.rooms = { { x = 2, y = 2, w = dungeon.W - 2, h = dungeon.H - 2 } }
    st.map.kind = 'hall'
    local cells = {}
    for y = 1, dungeon.H do
      for x = 1, dungeon.W do
        if st.map.grid[y][x] == '.' then
          cells[#cells + 1] = { x, y }
        end
      end
    end
    st.map.floor_cells = cells
    if st.shop then
      st.shop.room = st.map.rooms[1]
    end
    st.mhouse = nil
    for _, e in ipairs(st.enemies) do
      e.asleep = nil
    end
    msg(T('大部屋の罠だ！壁が崩れ落ち、魔物たちが一斉に目を覚ました！'))
    compute_fov()
  elseif kind == 'summon' then
    msg(T('召喚の罠だ！魔物が湧き出した！'))
    local spawned = 0
    for _ = 1, 20 do
      if spawned >= 3 then
        break
      end
      local dx, dy = math.random(-2, 2), math.random(-2, 2)
      local x, y = p.x + dx, p.y + dy
      if (dx ~= 0 or dy ~= 0) and walkable(x, y) and not occupied(x, y) then
        enemies_mod.spawn({ at = { x = x, y = y }, awake = true })
        spawned = spawned + 1
      end
    end
  elseif kind == 'warp' then
    msg(T('ワープの罠だ！飛ばされた'))
    for _ = 1, 50 do
      local x, y = random_room_cell()
      if not occupied(x, y) then
        p.x, p.y = x, y
        break
      end
    end
  elseif kind == 'pit' then
    p.hp = p.hp - 2
    st.floor = st.floor + 1
    setup_floor()
    msg(T('落とし穴だ！地下%d階に落ちた'):format(st.floor))
    if st.floor_note then
      msg(T(st.floor_note))
    end
    check_mhouse()
  end
end

local function gain_exp(amount)
  local p = st.player
  p.exp = p.exp + amount
  while p.exp >= p.next_exp do
    p.exp = p.exp - p.next_exp
    p.lv = p.lv + 1
    p.next_exp = math.floor(6 * p.lv ^ 1.5)
    p.maxhp = p.maxhp + 6
    p.hp = math.min(p.maxhp, p.hp + 6)
    p.atk = p.atk + 2
    if p.lv % 3 == 0 then
      p.def = p.def + 1
    end
    msg(T('レベルが%dに上がった！'):format(p.lv))
    if p.lv >= 10 then
      unlock('lv10')
    end
  end
end

-- Monster-house announcement: entering (or arriving in) the room wakes every enemy at once.
function check_mhouse()
  local p = st.player
  if st.mhouse and not st.mhouse_announced
    and dungeon.room_at(st.map, p.x, p.y) == st.mhouse then
    st.mhouse_announced = true
    msg(T('モンスターハウスだ！'))
    for _, e in ipairs(st.enemies) do
      if dungeon.room_at(st.map, e.x, e.y) == st.mhouse then
        e.asleep = nil
      end
    end
  end
end

-- Tab = total price of carried unpaid goods plus consumed unpaid amounts.
local function shop_debt()
  if not st.shop then
    return 0
  end
  local total = st.consumed_debt or 0
  local p = st.player
  for _, it in ipairs(p.inv) do
    total = total + (it.price or 0)
  end
  for _, slot in ipairs({ 'weapon', 'shield', 'ring' }) do
    if p[slot] and p[slot].price then
      total = total + p[slot].price
    end
  end
  return total
end

function M.shop_debt()
  return shop_debt()
end

-- Settlement done: strip all unpaid tags.
local function clear_shop_debt()
  st.consumed_debt = 0
  local p = st.player
  for _, it in ipairs(p.inv) do
    it.price = nil
  end
  for _, slot in ipairs({ 'weapon', 'shield', 'ring' }) do
    if p[slot] then
      p[slot].price = nil
    end
  end
end

-- Consuming unpaid goods (use, throw, wand breakage) leaves only the debt.
local function consume_price(it)
  if it.price then
    st.consumed_debt = (st.consumed_debt or 0) + it.price
    it.price = nil
  end
end

-- Whether the player is inside the (not yet hostile) shop room.
local function in_shop()
  return st.shop ~= nil and not st.shop.angry
    and dungeon.room_at(st.map, st.player.x, st.player.y) == st.shop.room
end

-- Settlement check: leaving the shop with a tab pays it, or angers the keeper if unaffordable.
local function settle_shop()
  local p = st.player
  local debt = shop_debt()
  if not (st.shop and debt > 0) then
    return
  end
  if dungeon.room_at(st.map, p.x, p.y) == st.shop.room then
    return
  end
  if p.gold >= debt then
    p.gold = p.gold - debt
    msg(T('店主に%dGを支払った。「まいどあり！」'):format(debt))
    clear_shop_debt()
    unlock('shopper')
  else
    msg(T('店主「泥棒だーっ！！」'))
    st.shop.angry = true
    local kd = data.keeper
    st.enemies[#st.enemies + 1] = {
      name = kd.name, char = kd.char, hp = kd.hp, atk = kd.atk, def = kd.def,
      exp = kd.exp, speed = kd.speed, x = st.shop.keeper.x, y = st.shop.keeper.y,
    }
    clear_shop_debt()
  end
end

local function advance_turn()
  if st.mode ~= 'play' then
    return
  end
  local p = st.player
  st.turn = st.turn + 1
  settle_shop()
  if p.gold >= 1000 then
    unlock('rich')
  end
  if st.turn % (has_ring('ring_stomach') and 24 or 12) == 0 and p.hunger > 0 then
    p.hunger = p.hunger - 1
    if p.hunger == 0 then
      msg(T('空腹で力が出ない…何か食べないと！'))
    end
  end
  if p.status.poison then
    p.hp = p.hp - 1
    st.cause = '毒'
    if st.turn % 5 == 0 then
      msg(T('毒が体を蝕んでいる…'))
    end
  end
  if p.hunger == 0 then
    if st.turn % 2 == 0 then
      p.hp = p.hp - 1
      st.cause = '空腹'
    end
  elseif st.turn % 2 == 0 and p.hp < p.maxhp and not p.status.poison then
    p.hp = p.hp + 1
  end
  -- Advance status-ailment timers.
  for name, t in pairs(p.status) do
    if t <= 1 then
      p.status[name] = nil
      msg(T('%sが抜けた'):format(T(STATUS_LABEL[name] or name)))
    else
      p.status[name] = t - 1
    end
  end
  for _, e in ipairs(st.enemies) do
    -- Double-speed enemies act multiple times per turn.
    for _ = 1, e.speed or 1 do
      enemies_mod.act(e)
    end
  end
  if st.turn % 60 == 0 then
    enemies_mod.spawn({ hidden = true })
  end
  -- Warn the moment HP drops to a quarter of max.
  if p.hp > 0 and p.hp <= math.floor(p.maxhp / 4) then
    if not st.low_warned then
      st.low_warned = true
      msg(T('危険だ！HPが残りわずか…'))
    end
  else
    st.low_warned = false
  end
  if p.hp <= 0 then
    p.hp = 0
    st.mode = 'dead'
    msg(T('力尽きた…'))
    savemod.clear()
    dex.flush()
    st.best = score.record({
      floor = st.floor, lv = p.lv, gold = p.gold, turns = st.turn, cause = st.cause,
      hard = st.hard or nil,
      daily = st.daily,
      class = st.class,
    })
    M.finish_run()
  end
  compute_fov()
  for _, e in ipairs(st.enemies) do
    if st.visible[key_of(e.x, e.y)] then
      dex.mark_seen(e.name)
    end
  end
  if dex_complete_done == nil then
    dex_complete_done = ach.unlocked('dex_complete')
  end
  if not dex_complete_done then
    local drecs = dex.data()
    local all_seen = true
    for _, d in ipairs(data.enemies) do
      if not (drecs[d.name] and drecs[d.name].seen) then
        all_seen = false
        break
      end
    end
    if all_seen then
      for _, d in ipairs({ data.keeper, data.boss }) do
        if not (drecs[d.name] and drecs[d.name].seen) then
          all_seen = false
        end
      end
    end
    if all_seen then
      unlock('dex_complete')
      dex_complete_done = true
    end
  end
  check_mhouse()
end

local function pickup()
  local p = st.player
  for i, g in ipairs(st.golds) do
    if g.x == p.x and g.y == p.y then
      p.gold = p.gold + g.amount
      msg(T('%dゴールドを手に入れた'):format(g.amount))
      table.remove(st.golds, i)
      break
    end
  end
  for i, it in ipairs(st.items) do
    if it.x == p.x and it.y == p.y then
      if it.def.kind == 'stone' then
        local picked = false
        for _, held in ipairs(p.inv) do
          if held.kind == 'stone' then
            held.count = (held.count or 1) + (it.def.count or 1)
            picked = true
            msg(T('石を%d個拾った(計%d個)'):format(it.def.count or 1, held.count))
            break
          end
        end
        if not picked then
          if #p.inv >= INV_MAX then
            msg(T('持ち物がいっぱいで石を拾えない'))
          else
            table.insert(p.inv, it.def)
            picked = true
            msg(T('石を%d個拾った'):format(it.def.count or 1))
          end
        end
        if picked then
          table.remove(st.items, i)
        end
        break
      elseif it.def.kind == 'goal' then
        table.remove(st.items, i)
        msg(T('Vimの聖典を手に入れた！ダンジョン踏破だ！'))
        st.mode = 'won'
        savemod.clear()
        dex.flush()
        unlock('clear')
        if st.hard then
          unlock('hard_clear')
        end
        st.best = score.record({
          floor = st.floor, lv = p.lv, gold = p.gold, turns = st.turn, cleared = true,
          hard = st.hard or nil,
          daily = st.daily,
          class = st.class,
        })
        M.finish_run()
      elseif #p.inv >= INV_MAX then
        msg(T('持ち物がいっぱいで%sを拾えない'):format(disp(it.def)))
      else
        table.insert(p.inv, it.def)
        if it.def.price then
          msg(T('%s(%dG)を手に取った。店を出る前に精算だ'):format(disp(it.def), it.def.price))
        else
          msg(T('%sを拾った'):format(disp(it.def)))
        end
        table.remove(st.items, i)
      end
      break
    end
  end
  if st.map.stairs.x == p.x and st.map.stairs.y == p.y then
    msg(T('階段だ。>で降りられる'))
  end
end

local function move_player(dx, dy)
  local p = st.player
  -- While confused, movement usually veers off course.
  if p.status.confusion and math.random(4) > 1 then
    dx, dy = math.random(-1, 1), math.random(-1, 1)
    if dx == 0 and dy == 0 then
      dx = math.random(2) == 1 and 1 or -1
    end
  end
  local nx, ny = p.x + dx, p.y + dy
  if keeper_at(nx, ny) then
    msg(T('店主「いらっしゃい。品物は店を出る前に精算だよ」'))
    return
  end
  local e = enemy_at(nx, ny)
  if e then
    if dx ~= 0 and dy ~= 0 and not (walkable(nx, p.y) and walkable(p.x, ny)) then
      return
    end
    enemies_mod.player_attack(e)
    advance_turn()
  elseif can_step(p.x, p.y, dx, dy) then
    p.x, p.y = nx, ny
    pickup()
    trigger_trap()
    advance_turn()
  end
end

-- Run straight until hitting an obstacle or event (Mystery Dungeon dash).
local function dash(dx, dy)
  -- Cannot dash while confused.
  if st.player.status.confusion then
    move_player(dx, dy)
    return
  end
  for _ = 1, 60 do
    if not st or st.mode ~= 'play' then
      return
    end
    local p = st.player
    local nx, ny = p.x + dx, p.y + dy
    if enemy_at(nx, ny) or not can_step(p.x, p.y, dx, dy) then
      return
    end
    -- If the next cell holds something, step onto it and stop.
    local special = trap_at(nx, ny) ~= nil
      or (st.map.stairs.x == nx and st.map.stairs.y == ny)
    if not special then
      for _, it in ipairs(st.items) do
        if it.x == nx and it.y == ny then
          special = true
          break
        end
      end
    end
    if not special then
      for _, g in ipairs(st.golds) do
        if g.x == nx and g.y == ny then
          special = true
          break
        end
      end
    end
    local prev_room = dungeon.room_at(st.map, p.x, p.y)
    move_player(dx, dy)
    if not st or st.mode ~= 'play' then
      return
    end
    p = st.player
    if special then
      return
    end
    -- Stop when entering or leaving a room.
    if dungeon.room_at(st.map, p.x, p.y) ~= prev_room then
      return
    end
    -- Stop when an enemy comes into view.
    for _, e in ipairs(st.enemies) do
      if st.visible[e.y * 1000 + e.x] then
        return
      end
    end
    -- Stop at corridor junctions.
    if not dungeon.room_at(st.map, p.x, p.y) then
      local exits = 0
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if walkable(p.x + d[1], p.y + d[2]) then
          exits = exits + 1
        end
      end
      if exits > 2 then
        return
      end
    end
    render.draw(st)
    if not st.headless then
      vim.cmd('redraw')
    end
  end
end

-- Auto-explore: keep walking toward unexplored cells until something happens.
local function auto_explore()
  if st.player.status.confusion then
    msg(T('混乱していてまっすぐ歩けない'))
    return
  end
  for _, e in ipairs(st.enemies) do
    if st.visible[key_of(e.x, e.y)] then
      msg(T('敵から目を離せない'))
      return
    end
  end
  local moved = false
  for _ = 1, 150 do
    if st.mode ~= 'play' then
      return
    end
    local msg_count = #st.messages
    local p = st.player
    -- BFS over known floor toward a frontier cell (or the stairs when fully explored).
    local prev = {}
    local start_key = key_of(p.x, p.y)
    local q = { { p.x, p.y } }
    local seen = { [start_key] = true }
    local head, goal = 1, nil
    local stairs_key = key_of(st.map.stairs.x, st.map.stairs.y)
    while q[head] do
      local c = q[head]
      head = head + 1
      local ck = key_of(c[1], c[2])
      if ck ~= start_key then
        local frontier = false
        for dy = -1, 1 do
          for dx = -1, 1 do
            local nx, ny = c[1] + dx, c[2] + dy
            if (dx ~= 0 or dy ~= 0) and nx >= 1 and nx <= dungeon.W
              and ny >= 1 and ny <= dungeon.H and not st.explored[key_of(nx, ny)] then
              frontier = true
            end
          end
        end
        if frontier then
          goal = c
          break
        end
      end
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = c[1] + d[1], c[2] + d[2]
        local nk = key_of(nx, ny)
        if not seen[nk] and st.explored[nk] and walkable(nx, ny) then
          seen[nk] = true
          prev[nk] = ck
          q[#q + 1] = { nx, ny }
        end
      end
    end
    if not goal then
      if start_key == stairs_key then
        if not moved then
          msg(T('探索し尽くした。ここが階段だ'))
        end
        return
      elseif st.explored[stairs_key] and seen[stairs_key] then
        goal = { st.map.stairs.x, st.map.stairs.y }
      else
        if not moved then
          msg(T('これ以上進める場所がない'))
        end
        return
      end
    end
    local k = key_of(goal[1], goal[2])
    local path_first = nil
    while prev[k] do
      path_first = k
      k = prev[k]
    end
    if not path_first then
      return
    end
    local fx = path_first % 1000
    local fy = math.floor(path_first / 1000)
    move_player(fx - p.x, fy - p.y)
    moved = true
    render.draw(st)
    if not st.headless then
      vim.cmd('redraw')
    end
    if st.mode ~= 'play' or #st.messages > msg_count then
      return
    end
    for _, e in ipairs(st.enemies) do
      if st.visible[key_of(e.x, e.y)] then
        return
      end
    end
  end
end

local function descend()
  local p = st.player
  local stairs_debt = shop_debt()
  if p.x == st.map.stairs.x and p.y == st.map.stairs.y and st.shop and stairs_debt > 0 then
    if p.gold >= stairs_debt then
      p.gold = p.gold - stairs_debt
      msg(T('店主に%dGを支払った。「まいどあり！」'):format(stairs_debt))
      unlock('shopper')
      clear_shop_debt()
    else
      msg(T('店主「精算がまだだよ！」(所持金が足りない)'))
      return
    end
  end
  if p.x == st.map.stairs.x and p.y == st.map.stairs.y then
    local escaped_mhouse = st.mhouse_announced
    st.floor = st.floor + 1
    st.turn = st.turn + 1
    if st.floor >= 5 then
      unlock('floor5')
    end
    if st.hard and st.floor >= 15 then
      unlock('abyss')
    end
    if escaped_mhouse then
      unlock('mhouse')
    end
    setup_floor()
    msg(T('地下%d階に降りた'):format(st.floor))
    if st.floor_note then
      msg(T(st.floor_note))
    end
    check_mhouse()
    dex.flush()
  else
    msg(T('ここに階段はない'))
  end
end

-- Derives the seed used for the n-th key of a run. Reseeding before every
-- key makes each turn depend only on (run seed, key number), so a replay is
-- not thrown off by other plugins calling math.random between keys. All
-- arithmetic stays below 2^53, so it is exact.
local function key_seed(seed, n)
  local h = (seed % 2147483647 * 31 + n) % 2147483647
  h = h * 48271 % 2147483647
  h = h * 48271 % 2147483647
  return h
end
M.key_seed = key_seed

-- Apply a class: stats, starting kit, passives, and known item kinds.
local function apply_class(id)
  local c = data.class_by_id(id) or data.classes[1]
  st.class = c.id
  local p = st.player
  p.maxhp = p.maxhp + (c.maxhp or 0)
  p.hp = p.maxhp
  p.atk = p.atk + (c.atk or 0)
  for _, d in ipairs(data.items) do
    if c.weapon and d.id == c.weapon then
      p.weapon = vim.tbl_extend('force', {}, d, { mod = c.weapon_mod or 0 })
    end
    if c.stones and d.id == 'stone' then
      table.insert(p.inv, vim.tbl_extend('force', {}, d, { count = c.stones }))
    end
    if c.wand and d.id == c.wand then
      table.insert(p.inv, vim.tbl_extend('force', {}, d, { charges = c.charges or 3 }))
    end
    if c.know and d.unidentified then
      local kind = d.id:match('^(%a+)_')
      if c.know[kind] then
        st.identified[d.id] = true
      end
    end
  end
end

-- The run's replay: everything needed to play it back.
local function new_replay()
  return {
    version = 1,
    seed = st.seed,
    class = st.class,
    hard = st.hard or nil,
    daily = st.daily,
    lua = jit and jit.version or _VERSION,
    keys = {},
  }
end

function M.new_game(buf, opts)
  opts = opts or {}
  local seed = opts.seed
  if not seed then
    if opts.daily then
      -- Date seed: the same day always yields the same dungeon.
      seed = tonumber(os.date('%Y%m%d'))
    else
      seed = math.floor((vim.uv or vim.loop).hrtime() % 2 ^ 31)
    end
  end
  math.randomseed(seed)
  st = {
    buf = buf,
    seed = seed,
    keyn = 0,
    replaying = opts.replaying or nil,
    headless = opts.headless or nil,
    hard = opts.hard or false,
    daily = opts.daily and (opts.daily_date or os.date('%Y-%m-%d')) or nil,
    floor = 1,
    turn = 0,
    mode = 'play',
    messages = {},
    player = {
      x = 0,
      y = 0,
      hp = 20,
      maxhp = 20,
      atk = 6,
      def = 1,
      lv = 1,
      exp = 0,
      next_exp = 6,
      gold = 0,
      hunger = 100,
      maxhunger = 100,
      inv = {},
      status = {},
    },
    visible = {},
    explored = {},
    identified = {},
    appearance = {},
  }
  -- Randomly assign appearance names to unidentified items.
  local grass = vim.list_extend({}, data.grass_names)
  local scrolls = vim.list_extend({}, data.scroll_names)
  local wands = vim.list_extend({}, data.wand_names)
  local rings = vim.list_extend({}, data.ring_names)
  for _, d in ipairs(data.items) do
    if d.unidentified then
      if d.kind == 'heal' then
        st.appearance[d.id] = table.remove(grass, math.random(#grass))
      elseif d.kind == 'wand' then
        st.appearance[d.id] = table.remove(wands, math.random(#wands))
      elseif d.kind == 'ring' then
        st.appearance[d.id] = table.remove(rings, math.random(#rings))
      else
        st.appearance[d.id] = table.remove(scrolls, math.random(#scrolls))
      end
    end
  end
  -- Starting supplies (bread and a herb). None in the Abyss.
  if not st.hard then
    for _, d in ipairs(data.items) do
      if d.id == 'bread' or d.id == 'herb' then
        table.insert(st.player.inv, d)
      end
    end
  end
  setup_floor()
  st.class = 'wanderer'
  if opts.choose_class then
    st.mode = 'class_select'
  else
    apply_class(opts.class or 'wanderer')
  end
  st.replay = new_replay()
  st.replay.choose = opts.choose_class or nil
  if st.hard then
    msg(T('裏ダンジョン『無限ヤンクの奈落』に足を踏み入れた…'))
    msg(T('Neovimの奥義書が地下%d階に眠るという。支給品はない'):format(HARD_GOAL_FLOOR))
  else
    msg(T('地下1階に足を踏み入れた。(?でヘルプ)'))
    msg(T('伝説のVimの聖典が地下%d階に眠っているという…'):format(GOAL_FLOOR))
  end
  if st.floor_note then
    msg(T(st.floor_note))
  end
  check_mhouse()
  render.draw(st)
end

local dirs = {
  h = { -1, 0 },
  l = { 1, 0 },
  k = { 0, -1 },
  j = { 0, 1 },
  y = { -1, -1 },
  u = { 1, -1 },
  b = { -1, 1 },
  n = { 1, 1 },
}

local dash_dirs = {
  H = { -1, 0 },
  L = { 1, 0 },
  K = { 0, -1 },
  J = { 0, 1 },
  Y = { -1, -1 },
  U = { 1, -1 },
  B = { -1, 1 },
  N = { 1, 1 },
}

function M.handle(key)
  if not st then
    return
  end
  -- Q quits only in play mode; in menus it is an ordinary key (a Scroll of
  -- f target, a cancel), so it is recorded there like any other.
  local quitting = key == 'Q' and st.mode == 'play'
  if quitting and st.replaying then
    return -- a replay never suspends the game or closes windows
  end
  if st.mode ~= 'dead' and st.mode ~= 'won' and not quitting then
    st.keyn = (st.keyn or 0) + 1
    math.randomseed(key_seed(st.seed or 0, st.keyn))
    if st.replay then
      st.replay.keys[#st.replay.keys + 1] = key
    end
  end
  if st.mode == 'class_select' then
    local idx = #key == 1 and (key:byte() - 96) or 0
    if data.classes[idx] then
      st.mode = 'play'
      apply_class(data.classes[idx].id)
      st.replay.class = st.class
      msg(T('%sとして冒険を始める'):format(T(data.classes[idx].name)))
    end
    render.draw(st)
    return
  end
  if st.mode == 'dead' or st.mode == 'won' then
    if key == 'r' then
      -- Play again with the same class.
      M.new_game(st.buf, { hard = st.hard, daily = st.daily and true or nil, class = st.class })
    elseif key == 'h' and st.mode == 'won' and not st.hard then
      M.new_game(st.buf, { hard = true, class = st.class })
    elseif key == 'q' then
      M.quit()
    end
    return
  end
  if st.mode == 'inventory' then
    -- 'i' selects slot i, so only q/esc close the menu.
    if key == 'q' or key == 'esc' then
      st.mode = 'play'
    elseif #key == 1 then
      local idx = key:byte() - 96
      if idx >= 1 and idx <= #st.player.inv then
        items.use_item(idx)
      end
    end
  elseif st.mode == 'fmotion' then
    local scroll = st.pending_f
    st.pending_f = nil
    st.mode = 'play'
    if key == 'esc' then
      table.insert(st.player.inv, scroll)
      msg(T('やめておいた'))
    elseif not items.f_jump(key) then
      table.insert(st.player.inv, scroll)
      msg(T('その文字は視界に見当たらない'))
    else
      consume_price(scroll)
    end
  elseif st.mode == 'throw_select' then
    if key == 'q' or key == 'esc' or key == 't' then
      st.mode = 'play'
    elseif #key == 1 then
      local idx = key:byte() - 96
      if idx >= 1 and idx <= #st.player.inv then
        st.throw_idx = idx
        st.mode = 'throw_dir'
        msg(T('どの方向に投げる？(hjklyubn / escで中止)'))
      end
    end
  elseif st.mode == 'throw_dir' then
    if key == 'esc' then
      st.throw_idx = nil
      st.mode = 'play'
      msg(T('やめておいた'))
    elseif dirs[key] then
      items.do_throw(dirs[key][1], dirs[key][2])
    end
  elseif st.mode == 'drop_select' then
    if key == 'q' or key == 'esc' or key == 'd' then
      st.mode = 'play'
    elseif #key == 1 then
      local idx = key:byte() - 96
      if idx >= 1 and idx <= #st.player.inv then
        items.drop_item(idx)
      end
    end
  elseif st.mode == 'sell_select' then
    if key == 'q' or key == 'esc' or key == 'S' then
      st.mode = 'play'
    elseif #key == 1 then
      local idx = key:byte() - 96
      if idx >= 1 and idx <= #st.player.inv then
        items.sell_item(idx)
      end
    end
  elseif st.mode == 'zap_dir' then
    if key == 'esc' then
      table.insert(st.player.inv, st.zap_item)
      st.zap_item = nil
      st.mode = 'play'
      msg(T('やめておいた'))
    elseif dirs[key] then
      items.do_zap(dirs[key][1], dirs[key][2])
    end
  elseif st.mode == 'log' then
    if key == 'q' or key == 'esc' or key == 'M' then
      st.mode = 'play'
    end
  elseif st.mode == 'help' then
    if key == 'q' or key == 'esc' or key == '?' then
      st.mode = 'play'
    end
  else
    if dirs[key] then
      move_player(dirs[key][1], dirs[key][2])
    elseif dash_dirs[key] then
      dash(dash_dirs[key][1], dash_dirs[key][2])
    elseif key == '.' then
      advance_turn()
    elseif key == '>' then
      descend()
    elseif key == 'i' then
      st.mode = 'inventory'
    elseif key == 't' then
      if #st.player.inv == 0 then
        msg(T('投げられるものを持っていない'))
      else
        st.mode = 'throw_select'
      end
    elseif key == 'S' then
      if st.shop and not st.shop.angry
        and dungeon.room_at(st.map, st.player.x, st.player.y) == st.shop.room then
        if #st.player.inv == 0 then
          msg(T('売れるものを持っていない'))
        else
          st.mode = 'sell_select'
        end
      else
        msg(T('ここでは売れない(店の中でSを押す)'))
      end
    elseif key == 'o' then
      auto_explore()
    elseif key == 'd' then
      if #st.player.inv == 0 then
        msg(T('置けるものを持っていない'))
      else
        st.mode = 'drop_select'
      end
    elseif key == 'M' then
      st.mode = 'log'
    elseif key == '?' then
      st.mode = 'help'
    elseif key == 'Q' then
      M.quit()
      return
    end
  end
  render.draw(st)
end

function M.quit()
  render.close_float(st)
  if st.mode ~= 'dead' and st.mode ~= 'won' then
    -- Return items held by menus to the pack before saving.
    if st.pending_f then
      table.insert(st.player.inv, st.pending_f)
      st.pending_f = nil
    end
    if st.zap_item then
      table.insert(st.player.inv, st.zap_item)
      st.zap_item = nil
    end
    st.mode = 'play'
    savemod.write(M.serialize())
    vim.notify(T('冒険を中断した。次回の:VimDungeonsで再開できる'))
  end
  dex.flush()
  local buf = st.buf
  st = nil
  if not pcall(vim.cmd, 'tabclose') then
    vim.cmd('enew')
  end
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

-- Serialize the current state to plain data for the suspend save.
function M.serialize()
  local rooms_index = {}
  for i, r in ipairs(st.map.rooms) do
    rooms_index[r] = i
  end
  local explored_list = {}
  for k in pairs(st.explored) do
    explored_list[#explored_list + 1] = k
  end
  local grid_rows = {}
  for y = 1, dungeon.H do
    grid_rows[y] = table.concat(st.map.grid[y])
  end
  return {
    version = 1,
    hard = st.hard or false,
    daily = st.daily,
    floor = st.floor,
    turn = st.turn,
    cause = st.cause,
    messages = st.messages,
    identified = st.identified,
    appearance = st.appearance,
    player = st.player,
    enemies = st.enemies,
    items = st.items,
    golds = st.golds,
    traps = st.traps,
    explored = explored_list,
    map = {
      grid = grid_rows,
      kind = st.map.kind,
      rooms = st.map.rooms,
      spawn = st.map.spawn,
      stairs = st.map.stairs,
    },
    mhouse = st.mhouse and rooms_index[st.mhouse] or nil,
    mhouse_announced = st.mhouse_announced or false,
    shop = st.shop and {
      room = rooms_index[st.shop.room],
      keeper = st.shop.keeper,
      angry = st.shop.angry or false,
    } or nil,
    consumed_debt = st.consumed_debt or 0,
    seed = st.seed,
    keyn = st.keyn,
    class = st.class,
    replay = st.replay,
  }
end

-- Restore state from suspend-save data.
function M.resume(buf, s)
  local grid = {}
  local floor_cells = {}
  for y = 1, dungeon.H do
    local row = s.map.grid[y]
    grid[y] = {}
    for x = 1, dungeon.W do
      grid[y][x] = row:sub(x, x)
      if grid[y][x] == '.' then
        floor_cells[#floor_cells + 1] = { x, y }
      end
    end
  end
  st = {
    buf = buf,
    mode = 'play',
    hard = s.hard or false,
    daily = s.daily,
    floor = s.floor,
    turn = s.turn or 0,
    cause = s.cause,
    messages = s.messages or {},
    identified = s.identified or {},
    appearance = s.appearance or {},
    player = s.player,
    enemies = s.enemies or {},
    items = s.items or {},
    golds = s.golds or {},
    traps = s.traps or {},
    visible = {},
    explored = {},
    consumed_debt = s.consumed_debt or 0,
    map = {
      grid = grid,
      kind = s.map.kind,
      rooms = s.map.rooms or {},
      spawn = s.map.spawn,
      stairs = s.map.stairs,
      floor_cells = floor_cells,
    },
  }
  st.seed = s.seed
  st.keyn = s.keyn or 0
  st.class = s.class or 'wanderer'
  st.replay = s.replay
  if st.replay then
    -- A suspend and resume restores only what the save holds, so playing
    -- this run back may not match; the replay says so.
    st.replay.suspended = true
    st.replay.keys = st.replay.keys or {}
  end
  st.player.status = st.player.status or {}
  st.player.inv = st.player.inv or {}
  for _, k in ipairs(s.explored or {}) do
    st.explored[k] = true
  end
  st.mhouse = s.mhouse and st.map.rooms[s.mhouse] or nil
  st.mhouse_announced = s.mhouse_announced or false
  if s.shop and s.shop.room and st.map.rooms[s.shop.room] then
    st.shop = {
      room = st.map.rooms[s.shop.room],
      keeper = s.shop.keeper,
      angry = s.shop.angry or false,
    }
  end
  compute_fov()
  msg(T('冒険を再開した'))
  render.draw(st)
end

-- Expose internal state for tests.
function M.state()
  return st
end

-- Called when a run ends (death or victory): seal the replay with its
-- result, keep it as the last replay, and add daily runs to the ranking.
-- Swap the game state (to check a replay without losing the current run).
function M.swap_state(s)
  local old = st
  st = s
  return old
end

function M.finish_run()
  if not st.replay then
    return
  end
  local p = st.player
  st.replay.result = {
    outcome = st.mode,
    floor = st.floor,
    lv = p.lv,
    gold = p.gold,
    turns = st.turn,
    cause = st.cause,
  }
  if st.replaying then
    return
  end
  local replay = require('vimdungeons.replay')
  replay.remember(st.replay)
  if st.daily then
    require('vimdungeons.daily').record(st.daily, {
      name = replay.player_name(),
      class = st.class,
      outcome = st.mode,
      floor = st.floor,
      lv = p.lv,
      gold = p.gold,
      turns = st.turn,
      source = 'local',
    })
  end
end

-- Inject the internal API into the enemies/items subsystems.
enemies_mod.setup({
  st = function()
    return st
  end,
  key_of = key_of,
  msg = msg,
  unlock = unlock,
  gain_exp = gain_exp,
  equip_power = equip_power,
  add_status = add_status,
  walkable = walkable,
  can_step = can_step,
  occupied = occupied,
  random_room_cell = random_room_cell,
  has_ring = has_ring,
})

items.setup({
  st = function()
    return st
  end,
  key_of = key_of,
  msg = msg,
  disp = disp,
  unlock = unlock,
  gain_exp = gain_exp,
  kill_enemy = enemies_mod.kill,
  enemy_at = enemy_at,
  walkable = walkable,
  occupied = occupied,
  pickup = pickup,
  trigger_trap = trigger_trap,
  advance_turn = advance_turn,
  equip_power = equip_power,
  has_ring = has_ring,
  consume_price = consume_price,
  in_shop = in_shop,
  animate = function(path, ch, hl)
    render.animate(st, path, ch, hl)
  end,
})

return M
