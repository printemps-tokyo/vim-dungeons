-- Enemy subsystem: spawning, combat, and AI.
-- Uses C (shared internal API) injected from game.lua.
local dungeon = require('vimdungeons.dungeon')
local data = require('vimdungeons.data')
local T = require('vimdungeons.i18n').t
local dex = require('vimdungeons.dex')

local M = {}
local C = nil

function M.setup(core)
  C = core
end

local function sign(v)
  if v > 0 then
    return 1
  elseif v < 0 then
    return -1
  end
  return 0
end

local function pick_enemy_def(floor)
  local st = C.st()
  local cands = {}
  for _, d in ipairs(data.enemies) do
    if floor >= d.min_floor and (st.hard or floor <= d.max_floor) then
      cands[#cands + 1] = d
    end
  end
  if #cands == 0 then
    cands = { data.enemies[#data.enemies] }
  end
  return cands[math.random(#cands)]
end

function M.spawn(opts)
  local st = C.st()
  for _ = 1, 30 do
    local x, y
    if opts and opts.at then
      x, y = opts.at.x, opts.at.y
    elseif opts and opts.room then
      local r = opts.room
      x, y = math.random(r.x, r.x + r.w - 1), math.random(r.y, r.y + r.h - 1)
    else
      x, y = C.random_room_cell()
    end
    local hidden_ok = not (opts and opts.hidden and st.visible[C.key_of(x, y)])
    if not C.occupied(x, y) and hidden_ok
      and not (x == st.map.stairs.x and y == st.map.stairs.y) then
      local d = pick_enemy_def(st.floor)
      st.enemies[#st.enemies + 1] = {
        name = d.name,
        char = d.char,
        erratic = d.erratic,
        speed = d.speed,
        phase = d.phase,
        venom = d.venom,
        -- Monster-house spawns always sleep; regular spawns sleep 40% (awake forces wakeful).
        asleep = (not (opts and opts.awake))
          and (((opts and opts.room) and true) or (math.random(100) <= 40) or nil) or nil,
        hp = d.hp + st.floor * (st.hard and 2 or 1),
        atk = d.atk + math.floor(st.floor / (st.hard and 2 or 3)),
        def = d.def + math.floor(st.floor / 4),
        exp = d.exp + st.floor,
        x = x,
        y = y,
      }
      return
    end
  end
end

function M.kill(e)
  local st = C.st()
  C.msg(T('%sを倒した！'):format(T(e.name)))
  dex.mark_kill(e.name)
  C.unlock('first_kill')
  if e.boss then
    C.msg(T('聖典を守る者はもういない…！'))
    C.unlock('boss')
  end
  if e.char == 'K' then
    C.unlock('thief_hunter')
  end
  for i, x in ipairs(st.enemies) do
    if x == e then
      table.remove(st.enemies, i)
      break
    end
  end
  C.gain_exp(e.exp)
  -- 25% chance to drop gold.
  if math.random(4) == 1 and not (e.x == st.map.stairs.x and e.y == st.map.stairs.y) then
    local has = false
    for _, g in ipairs(st.golds) do
      if g.x == e.x and g.y == e.y then
        has = true
        break
      end
    end
    if not has then
      st.golds[#st.golds + 1] = { x = e.x, y = e.y, amount = math.random(5, 15) + st.floor * 2 }
      C.msg(T('%sは金貨を落とした'):format(T(e.name)))
    end
  end
end

function M.player_attack(e)
  local st = C.st()
  local sneak = e.asleep
  e.asleep = nil
  if not sneak and math.random(8) == 1 then
    C.msg(T('%sに攻撃をかわされた'):format(T(e.name)))
    return
  end
  local atk = st.player.atk + (st.player.weapon and C.equip_power(st.player.weapon) or 0)
    + (C.has_ring('ring_power') and 3 or 0)
  local dmg = math.max(1, atk - e.def + math.random(0, 2) - 1)
  if sneak then
    dmg = dmg * 2
    C.msg(T('不意打ち！'))
  end
  e.hp = e.hp - dmg
  if e.hp <= 0 then
    M.kill(e)
  else
    C.msg(T('%sに%dのダメージ'):format(T(e.name), dmg))
  end
end

local function enemy_attack(e)
  local st = C.st()
  if math.random(8) == 1 then
    C.msg(T('%sの攻撃をかわした'):format(T(e.name)))
    return
  end
  local def = st.player.def + (st.player.shield and C.equip_power(st.player.shield) or 0)
  local dmg = math.max(1, e.atk - def + math.random(0, 2) - 1)
  st.player.hp = st.player.hp - dmg
  st.cause = e.name
  C.msg(T('%sから%dのダメージを受けた'):format(T(e.name), dmg))
  if e.venom and math.random(4) == 1 then
    C.add_status('poison', 6)
    C.msg(T('毒が体に回った！'))
  end
end

-- Phasing enemies can move through walls (but not the map border).
local function enemy_can_step(e, dx, dy)
  local nx, ny = e.x + dx, e.y + dy
  if e.phase then
    return nx >= 2 and nx <= dungeon.W - 1 and ny >= 2 and ny <= dungeon.H - 1
      and not C.occupied(nx, ny)
  end
  return C.can_step(e.x, e.y, dx, dy) and not C.occupied(nx, ny)
end

function M.act(e)
  local st = C.st()
  local p = st.player
  local dist = math.max(math.abs(e.x - p.x), math.abs(e.y - p.y))
  if e.asleep then
    -- Always wakes when adjacent; chance to wake when in the same room.
    local wake = dist <= 1
    if not wake then
      local eroom = dungeon.room_at(st.map, e.x, e.y)
      local proom = dungeon.room_at(st.map, p.x, p.y)
      -- The sneaking bracelet prevents same-room wakes (adjacency still wakes).
      wake = eroom ~= nil and eroom == proom and not C.has_ring('ring_sneak')
        and math.random(100) <= 30
    end
    if wake then
      e.asleep = nil
      if st.visible[e.y * 1000 + e.x] then
        C.msg(T('%sが目を覚ました！'):format(T(e.name)))
      end
    end
    return
  end
  if e.boss then
    -- The guardian never leaves the tome. Claws when adjacent; breath within range 4 on straight lines.
    local bdx, bdy = sign(p.x - e.x), sign(p.y - e.y)
    if dist == 1 then
      enemy_attack(e)
      return
    end
    if dist <= 4 and (p.x == e.x or p.y == e.y or math.abs(p.x - e.x) == math.abs(p.y - e.y)) then
      local x, y = e.x, e.y
      local clear = true
      for _ = 1, dist - 1 do
        x, y = x + bdx, y + bdy
        if not C.walkable(x, y) then
          clear = false
          break
        end
      end
      if clear then
        local pdef = p.def + (p.shield and C.equip_power(p.shield) or 0)
        local dmg = math.max(3, math.random(10, 16) - pdef)
        p.hp = p.hp - dmg
        st.cause = e.name
        C.msg(T('守護竜の炎のブレス！%dのダメージを受けた'):format(dmg))
      end
    end
    return
  end
  local dx, dy = sign(p.x - e.x), sign(p.y - e.y)
  if dist == 1 then
    -- No diagonal attacks across corners (phasing enemies are exempt).
    if e.phase
      or not (dx ~= 0 and dy ~= 0 and not (C.walkable(e.x + dx, e.y) and C.walkable(e.x, e.y + dy))) then
      enemy_attack(e)
      return
    end
  end
  local eroom = dungeon.room_at(st.map, e.x, e.y)
  local proom = dungeon.room_at(st.map, p.x, p.y)
  local chasing = (eroom ~= nil and eroom == proom) or dist <= 3
  if e.erratic and math.random(2) == 1 then
    chasing = false
  end
  local cands
  if chasing then
    cands = { { dx, dy }, { dx, 0 }, { 0, dy } }
  else
    if math.random(3) == 1 then
      return
    end
    cands = { { math.random(-1, 1), math.random(-1, 1) } }
  end
  for _, c in ipairs(cands) do
    local cx, cy = c[1], c[2]
    if (cx ~= 0 or cy ~= 0) and enemy_can_step(e, cx, cy) then
      e.x, e.y = e.x + cx, e.y + cy
      return
    end
  end
end

return M
