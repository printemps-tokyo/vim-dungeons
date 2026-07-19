-- Item subsystem: use, throw, wands, f-jump, and pricing.
-- Uses C (shared internal API) injected from game.lua.
local dungeon = require('vimdungeons.dungeon')
local data = require('vimdungeons.data')
local T = require('vimdungeons.i18n').t

local M = {}
local C = nil

function M.setup(core)
  C = core
end

-- Shop price of an item.
function M.price(def)
  if def.kind == 'wand' then
    return 250
  end
  if def.kind == 'ring' then
    return 300
  end
  if def.kind == 'stone' then
    return 10
  end
  if def.kind == 'weapon' or def.kind == 'shield' then
    return (def.power + (def.mod or 0)) * 80 + 40
  end
  local base = { heal = 40, food = 60, sight = 120, banish = 150, fmotion = 150, upgrade = 200 }
  return base[def.kind] or 100
end

function M.sell_price(def)
  return math.max(5, math.floor(M.price(def) / 2))
end

-- Restock the item in the shop room (give up if no free cell).
local function restock_item(def)
  local st = C.st()
  local r = st.shop.room
  for _ = 1, 30 do
    local x, y = math.random(r.x, r.x + r.w - 1), math.random(r.y, r.y + r.h - 1)
    local free = not C.occupied(x, y) and not (x == st.map.stairs.x and y == st.map.stairs.y)
      and not (x == st.player.x and y == st.player.y)
    if free then
      for _, it in ipairs(st.items) do
        if it.x == x and it.y == y then
          free = false
          break
        end
      end
    end
    if free then
      local goods = vim.tbl_extend('force', {}, def, { price = M.price(def) })
      st.items[#st.items + 1] = { x = x, y = y, def = goods }
      return
    end
  end
end

-- Sell: keeper pays half price and the item goes back on display.
function M.sell_item(idx)
  local st = C.st()
  local p = st.player
  local it = p.inv[idx]
  if not it then
    return
  end
  if it.price then
    C.msg(T('店主「それはまだウチの商品だよ」'))
    return
  end
  table.remove(p.inv, idx)
  local price = M.sell_price(it)
  p.gold = p.gold + price
  C.msg(T('%sを%dGで売った'):format(C.disp(it), price))
  restock_item(it)
end

-- Drop an item at your feet. Shop goods count as returned, clearing the tab.
function M.drop_item(idx)
  local st = C.st()
  local p = st.player
  local it = p.inv[idx]
  if not it then
    return
  end
  for _, x in ipairs(st.items) do
    if x.x == p.x and x.y == p.y then
      C.msg(T('足元には既に物がある'))
      st.mode = 'play'
      return
    end
  end
  if p.x == st.map.stairs.x and p.y == st.map.stairs.y then
    C.msg(T('階段の上には置けない'))
    st.mode = 'play'
    return
  end
  table.remove(p.inv, idx)
  st.items[#st.items + 1] = { x = p.x, y = p.y, def = it }
  if it.price and C.in_shop() then
    C.msg(T('%sを棚に戻した'):format(C.disp(it)))
  else
    C.msg(T('%sを足元に置いた'):format(C.disp(it)))
  end
  st.mode = 'play'
  C.advance_turn()
end

-- f{char}: leap to the nearest visible matching character. Consumes a turn on success.
function M.f_jump(ch)
  local st = C.st()
  local p = st.player
  local best, bestd
  local function consider(x, y, char, kind, name)
    if char ~= ch or not st.visible[y * 1000 + x] then
      return
    end
    local d = math.max(math.abs(x - p.x), math.abs(y - p.y))
    if d == 0 then
      return
    end
    if not best or d < bestd then
      best, bestd = { x = x, y = y, kind = kind, name = name }, d
    end
  end
  for _, e in ipairs(st.enemies) do
    consider(e.x, e.y, e.char, 'enemy', e.name)
  end
  for _, it in ipairs(st.items) do
    consider(it.x, it.y, it.def.char, 'cell', it.def.name)
  end
  for _, g in ipairs(st.golds) do
    consider(g.x, g.y, '$', 'cell')
  end
  consider(st.map.stairs.x, st.map.stairs.y, '>', 'cell')
  if not best then
    return false
  end
  local ox, oy = p.x, p.y
  local function jump_trail()
    local dx, dy = p.x - ox, p.y - oy
    local steps = math.max(math.abs(dx), math.abs(dy))
    if steps < 2 then
      return
    end
    local path = {}
    for i = 1, steps do
      path[#path + 1] = {
        ox + math.floor(dx * i / steps + 0.5),
        oy + math.floor(dy * i / steps + 0.5),
      }
    end
    C.animate(path, '@', 'VimDungeonsPlayer')
  end
  if best.kind == 'enemy' then
    -- Land on the free cell adjacent to the enemy that is closest to the player.
    local landing, landd
    for dy = -1, 1 do
      for dx = -1, 1 do
        local x, y = best.x + dx, best.y + dy
        if (dx ~= 0 or dy ~= 0) and C.walkable(x, y) and not C.occupied(x, y) then
          local d = math.max(math.abs(x - p.x), math.abs(y - p.y))
          if not landing or d < landd then
            landing, landd = { x = x, y = y }, d
          end
        end
      end
    end
    if not landing then
      return false
    end
    p.x, p.y = landing.x, landing.y
    jump_trail()
    C.msg(T('f%s: %sの眼前へ跳んだ！'):format(ch, T(best.name)))
  else
    if C.occupied(best.x, best.y) then
      return false
    end
    p.x, p.y = best.x, best.y
    jump_trail()
    C.msg(T('f%s: 一気に跳んだ！'):format(ch))
  end
  C.pickup()
  C.trigger_trap()
  C.advance_turn()
  return true
end

function M.use_item(idx)
  local st = C.st()
  local p = st.player
  local it = p.inv[idx]
  if not it then
    return
  end
  table.remove(p.inv, idx)
  if it.unidentified and not st.identified[it.id] then
    st.identified[it.id] = true
    C.msg(T('%sは%sだった！'):format(T(st.appearance[it.id] or it.name), T(it.name)))
    local all = true
    for _, d in ipairs(data.items) do
      if d.unidentified and not st.identified[d.id] then
        all = false
        break
      end
    end
    if all then
      C.unlock('identify_all')
    end
  end
  if it.price and (it.kind == 'heal' or it.kind == 'food' or it.kind == 'sight'
    or it.kind == 'banish' or it.kind == 'upgrade') then
    C.consume_price(it)
  end
  if it.kind == 'stone' then
    table.insert(p.inv, it)
    st.mode = 'play'
    C.msg(T('石は投げて使うものだ(tで投げる)'))
    return
  end
  if it.kind == 'heal' then
    if p.hp >= p.maxhp then
      p.maxhp = p.maxhp + 1
      p.hp = p.maxhp
      C.msg(T('%sを飲んだ。最大HPが1上がった'):format(T(it.name)))
    else
      p.hp = math.min(p.maxhp, p.hp + it.amount)
      C.msg(T('%sを飲んだ。HPが回復した'):format(T(it.name)))
    end
    if next(p.status) then
      p.status = {}
      C.msg(T('体の異常もすっかり治った'))
    end
  elseif it.kind == 'fmotion' then
    -- The next key is read as the jump target character (turn spent only on a jump).
    st.mode = 'fmotion'
    st.pending_f = it
    C.msg(T('fの巻物: 跳び先の文字を入力(escで中止)'))
    return
  elseif it.kind == 'upgrade' then
    local target = p.weapon or p.shield
    if target then
      target.mod = (target.mod or 0) + 1
      if target.cursed then
        target.cursed = nil
        target.curse_known = nil
        C.msg(T(':w! 呪いを上書き保存した！%sになった'):format(C.disp(target)))
      else
        C.msg(T(':w! 保存完了。%sに強化された！'):format(C.disp(target)))
      end
    else
      C.msg(T('しかし何も装備していなかった…'))
    end
  elseif it.kind == 'wand' then
    st.mode = 'zap_dir'
    st.zap_item = it
    C.msg(T('杖をどの方向に振る？(hjklyubn / escで中止)'))
    return
  elseif it.kind == 'weapon' or it.kind == 'shield' then
    local prev = p[it.kind]
    if prev and prev.cursed then
      table.insert(p.inv, it)
      st.mode = 'play'
      C.msg(T('%sが呪われていて外せない！'):format(C.disp(prev)))
      return
    end
    p[it.kind] = it
    if prev then
      table.insert(p.inv, prev)
      C.msg(T('%sを装備した(%sは持ち物に戻した)'):format(C.disp(it), C.disp(prev)))
    else
      C.msg(T('%sを装備した'):format(C.disp(it)))
    end
    if it.cursed then
      it.curse_known = true
      C.msg(T('なんと%sは呪われていた！外せない！'):format(C.disp(it)))
    end
  elseif it.kind == 'ring' then
    local prev = p.ring
    p.ring = it
    if prev then
      table.insert(p.inv, prev)
      C.msg(T('%sを腕にはめた(%sは外した)'):format(C.disp(it), C.disp(prev)))
    else
      C.msg(T('%sを腕にはめた'):format(C.disp(it)))
    end
  elseif it.kind == 'food' then
    p.hunger = math.min(p.maxhunger, p.hunger + it.amount)
    C.msg(T('%sを食べた。おなかがふくれた'):format(T(it.name)))
  elseif it.kind == 'sight' then
    for y = 1, dungeon.H do
      for x = 1, dungeon.W do
        st.explored[C.key_of(x, y)] = true
      end
    end
    C.msg(T('%sを読んだ。フロアの地形が頭に流れ込んだ！'):format(T(it.name)))
  elseif it.kind == 'banish' then
    C.msg(T('%sを読んだ。視界の敵に裁きが下る！'):format(T(it.name)))
    local hit = 0
    for i = #st.enemies, 1, -1 do
      local e = st.enemies[i]
      if st.visible[C.key_of(e.x, e.y)] then
        hit = hit + 1
        e.hp = e.hp - 30
        if e.hp <= 0 then
          C.msg(T('%sは消し去られた'):format(T(e.name)))
          C.gain_exp(e.exp)
          table.remove(st.enemies, i)
        end
      end
    end
    if hit == 0 then
      C.msg(T('しかし何も起きなかった'))
    end
  end
  st.mode = 'play'
  C.advance_turn()
end

-- Throw the selected item in a direction. Hits damage the enemy; misses land on the floor.
function M.do_throw(dx, dy)
  local st = C.st()
  local p = st.player
  local it = table.remove(p.inv, st.throw_idx)
  st.throw_idx = nil
  st.mode = 'play'
  if not it then
    return
  end
  C.consume_price(it)
  -- Stones are thrown one at a time from the stack.
  if it.kind == 'stone' and (it.count or 1) > 1 then
    it.count = it.count - 1
    table.insert(p.inv, it)
    it = vim.tbl_extend('force', {}, it, { count = 1 })
  end
  local x, y = p.x, p.y
  local path = {}
  local hit_enemy = nil
  for _ = 1, 12 do
    local nx, ny = x + dx, y + dy
    if not C.walkable(nx, ny) then
      break
    end
    x, y = nx, ny
    path[#path + 1] = { x, y }
    local e = C.enemy_at(x, y)
    if e then
      hit_enemy = e
      break
    end
  end
  C.animate(path, it.char, 'VimDungeonsItem')
  if hit_enemy then
    local e = hit_enemy
    local dmg
    if it.kind == 'weapon' or it.kind == 'shield' then
      dmg = C.equip_power(it) * 2 + 4
    elseif it.kind == 'stone' then
      dmg = 8
    else
      dmg = 5
    end
    C.msg(T('%sを投げつけた！%sに%dのダメージ'):format(C.disp(it), T(e.name), dmg))
    e.asleep = nil
    e.hp = e.hp - dmg
    if e.hp <= 0 then
      C.kill_enemy(e)
    end
    C.advance_turn()
    return
  end
  if x == p.x and y == p.y then
    C.msg(T('%sは壁に当たって足元に落ちた'):format(C.disp(it)))
  else
    C.msg(T('%sを投げた。床に落ちた'):format(C.disp(it)))
  end
  st.items[#st.items + 1] = { x = x, y = y, def = it }
  C.advance_turn()
end

-- Zap the wand. The bolt flies straight and affects the first enemy hit.
function M.do_zap(dx, dy)
  local st = C.st()
  local it = st.zap_item
  st.zap_item = nil
  st.mode = 'play'
  if not it then
    return
  end
  it.charges = (it.charges or 3) - 1
  local p = st.player
  local x, y = p.x, p.y
  local hit
  local path = {}
  for _ = 1, 15 do
    local nx, ny = x + dx, y + dy
    if not C.walkable(nx, ny) then
      break
    end
    x, y = nx, ny
    path[#path + 1] = { x, y }
    local e = C.enemy_at(x, y)
    if e then
      hit = e
      break
    end
  end
  C.animate(path, '*', 'VimDungeonsGold')
  if hit then
    hit.asleep = nil
  end
  if it.id == 'wand_bolt' then
    if hit then
      C.msg(T('稲妻が%sを撃った！20のダメージ'):format(T(hit.name)))
      hit.hp = hit.hp - 20
      if hit.hp <= 0 then
        C.kill_enemy(hit)
      end
    else
      C.msg(T('稲妻は壁に当たって消えた'))
    end
  elseif it.id == 'wand_swap' then
    if hit then
      p.x, p.y, hit.x, hit.y = hit.x, hit.y, p.x, p.y
      C.msg(T('%sと場所が入れ替わった！'):format(T(hit.name)))
      C.pickup()
      C.trigger_trap()
    else
      C.msg(T('魔法弾は壁に当たって消えた'))
    end
  end
  if it.charges <= 0 then
    C.consume_price(it)
    C.msg(T('%sは砕け散った'):format(C.disp(it)))
  else
    table.insert(p.inv, it)
  end
  C.advance_turn()
end

return M
