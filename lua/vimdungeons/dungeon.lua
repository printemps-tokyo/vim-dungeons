-- Dungeon generation (rooms connected by L-shaped corridors).
local M = {}

M.W = 60
M.H = 20

-- Room r interior spans x..x+w-1, y..y+h-1.
function M.room_at(map, x, y)
  for _, r in ipairs(map.rooms) do
    if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
      return r
    end
  end
end

-- Carve a fully connected maze via DFS on an odd-cell lattice.
local function carve_maze(grid)
  local cw = math.floor((M.W - 2) / 2) - 1
  local ch = math.floor((M.H - 2) / 2) - 1
  local function cell(cx, cy)
    return 2 + cx * 2, 2 + cy * 2
  end
  local visited = { ['0,0'] = true }
  local stack = { { 0, 0 } }
  local sx, sy = cell(0, 0)
  grid[sy][sx] = '.'
  while #stack > 0 do
    local cur = stack[#stack]
    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    for i = #dirs, 2, -1 do
      local j = math.random(i)
      dirs[i], dirs[j] = dirs[j], dirs[i]
    end
    local moved = false
    for _, d in ipairs(dirs) do
      local nx, ny = cur[1] + d[1], cur[2] + d[2]
      if nx >= 0 and nx <= cw and ny >= 0 and ny <= ch and not visited[nx .. ',' .. ny] then
        visited[nx .. ',' .. ny] = true
        local ax, ay = cell(cur[1], cur[2])
        local bx, by = cell(nx, ny)
        grid[(ay + by) / 2][(ax + bx) / 2] = '.'
        grid[by][bx] = '.'
        stack[#stack + 1] = { nx, ny }
        moved = true
        break
      end
    end
    if not moved then
      table.remove(stack)
    end
  end
end

-- force_kind is for tests. Otherwise 8% hall, 8% maze.
function M.generate(floor, force_kind)
  local kind = force_kind
  if not kind then
    local r = math.random(100)
    if r <= 8 then
      kind = 'hall'
    elseif r <= 16 then
      kind = 'maze'
    else
      kind = 'normal'
    end
  end

  local grid = {}
  for y = 1, M.H do
    grid[y] = {}
    for x = 1, M.W do
      grid[y][x] = '#'
    end
  end

  local function collect_floor_cells()
    local cells = {}
    for y = 1, M.H do
      for x = 1, M.W do
        if grid[y][x] == '.' then
          cells[#cells + 1] = { x, y }
        end
      end
    end
    return cells
  end

  if kind == 'hall' then
    local r = { x = 2, y = 2, w = M.W - 2, h = M.H - 2 }
    for y = r.y, r.y + r.h - 1 do
      for x = r.x, r.x + r.w - 1 do
        grid[y][x] = '.'
      end
    end
    local spawn = { x = math.random(r.x, r.x + r.w - 1), y = math.random(r.y, r.y + r.h - 1) }
    local stairs = spawn
    while stairs.x == spawn.x and stairs.y == spawn.y do
      stairs = { x = math.random(r.x, r.x + r.w - 1), y = math.random(r.y, r.y + r.h - 1) }
    end
    return {
      grid = grid, rooms = { r }, spawn = spawn, stairs = stairs,
      kind = kind, floor_cells = collect_floor_cells(),
    }
  end

  if kind == 'maze' then
    carve_maze(grid)
    local cells = collect_floor_cells()
    local sp = cells[math.random(#cells)]
    local stc = sp
    while stc[1] == sp[1] and stc[2] == sp[2] do
      stc = cells[math.random(#cells)]
    end
    return {
      grid = grid, rooms = {}, spawn = { x = sp[1], y = sp[2] },
      stairs = { x = stc[1], y = stc[2] }, kind = kind, floor_cells = cells,
    }
  end

  local rooms = {}
  local target = 5 + math.min(3, math.floor(floor / 3))
  local attempts = 0
  while #rooms < target and attempts < 300 do
    attempts = attempts + 1
    local w = math.random(5, 11)
    local h = math.random(3, 6)
    local x = math.random(2, M.W - w - 1)
    local y = math.random(2, M.H - h - 1)
    local ok = true
    for _, o in ipairs(rooms) do
      -- Keep at least one wall cell between rooms.
      if not (x + w + 1 < o.x or o.x + o.w + 1 < x or y + h + 1 < o.y or o.y + o.h + 1 < y) then
        ok = false
        break
      end
    end
    if ok then
      rooms[#rooms + 1] = { x = x, y = y, w = w, h = h }
    end
  end

  for _, r in ipairs(rooms) do
    for y = r.y, r.y + r.h - 1 do
      for x = r.x, r.x + r.w - 1 do
        grid[y][x] = '.'
      end
    end
  end

  local function center(r)
    return math.floor(r.x + r.w / 2), math.floor(r.y + r.h / 2)
  end

  -- Connecting rooms in sequence guarantees full connectivity.
  for i = 2, #rooms do
    local x1, y1 = center(rooms[i - 1])
    local x2, y2 = center(rooms[i])
    if math.random(2) == 1 then
      for x = math.min(x1, x2), math.max(x1, x2) do
        grid[y1][x] = '.'
      end
      for y = math.min(y1, y2), math.max(y1, y2) do
        grid[y][x2] = '.'
      end
    else
      for y = math.min(y1, y2), math.max(y1, y2) do
        grid[y][x1] = '.'
      end
      for x = math.min(x1, x2), math.max(x1, x2) do
        grid[y2][x] = '.'
      end
    end
  end

  local sx, sy = center(rooms[1])
  local stair_room = rooms[#rooms > 1 and math.random(2, #rooms) or 1]
  local tx = math.random(stair_room.x, stair_room.x + stair_room.w - 1)
  local ty = math.random(stair_room.y, stair_room.y + stair_room.h - 1)

  return {
    grid = grid,
    rooms = rooms,
    spawn = { x = sx, y = sy },
    stairs = { x = tx, y = ty },
    kind = 'normal',
    floor_cells = collect_floor_cells(),
  }
end

return M
