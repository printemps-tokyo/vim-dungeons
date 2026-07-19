-- Definition tables for enemies and items.
local M = {}

-- Each enemy appears only on floors within min_floor..max_floor.
M.enemies = {
  { name = 'スライム', char = 's', hp = 6, atk = 3, def = 0, exp = 2, min_floor = 1, max_floor = 4 },
  { name = 'コウモリ', char = 'b', hp = 8, atk = 4, def = 0, exp = 4, min_floor = 2, max_floor = 6, erratic = true },
  { name = 'ゴブリン', char = 'g', hp = 14, atk = 7, def = 1, exp = 8, min_floor = 3, max_floor = 8 },
  { name = '毒ヘビ', char = 'v', hp = 10, atk = 5, def = 0, exp = 8, min_floor = 3, max_floor = 8, venom = true },
  { name = '2jうさぎ', char = '2', hp = 12, atk = 6, def = 1, exp = 12, min_floor = 4, max_floor = 9, speed = 2 },
  { name = 'ggゴースト', char = 'G', hp = 18, atk = 9, def = 1, exp = 16, min_floor = 5, max_floor = 11, phase = true },
  { name = 'オーク', char = 'o', hp = 22, atk = 11, def = 2, exp = 15, min_floor = 6, max_floor = 12 },
  { name = 'ワイト', char = 'w', hp = 30, atk = 15, def = 3, exp = 25, min_floor = 9, max_floor = 15 },
  { name = 'ドラゴン', char = 'D', hp = 60, atk = 24, def = 5, exp = 80, min_floor = 13, max_floor = 99 },
}

-- weight is the spawn weight; min_floor gates the earliest floor.
M.items = {
  { id = 'herb', name = '薬草', char = '!', kind = 'heal', amount = 40, weight = 5, min_floor = 1, unidentified = true },
  { id = 'bread', name = '大きなパン', char = '%', kind = 'food', amount = 80, weight = 4, min_floor = 1 },
  { id = 'scroll_sight', name = '千里眼の巻物', char = '?', kind = 'sight', weight = 2, min_floor = 1, unidentified = true },
  { id = 'scroll_banish', name = ':g//dの巻物', char = '?', kind = 'banish', weight = 2, min_floor = 1, unidentified = true },
  { id = 'scroll_f', name = 'fの巻物', char = '?', kind = 'fmotion', weight = 2, min_floor = 2, unidentified = true },
  { id = 'scroll_upgrade', name = ':w!の巻物', char = '?', kind = 'upgrade', weight = 2, min_floor = 1, unidentified = true },
  { id = 'wand_bolt', name = 'いかずちの杖', char = '/', kind = 'wand', weight = 2, min_floor = 2, unidentified = true },
  { id = 'wand_swap', name = '場所替えの杖', char = '/', kind = 'wand', weight = 2, min_floor = 3, unidentified = true },
  { id = 'club', name = 'こん棒', char = ')', kind = 'weapon', power = 2, weight = 3, min_floor = 1 },
  { id = 'sword_bronze', name = '銅の剣', char = ')', kind = 'weapon', power = 4, weight = 2, min_floor = 3 },
  { id = 'sword_steel', name = '鋼鉄の剣', char = ')', kind = 'weapon', power = 7, weight = 1, min_floor = 7 },
  { id = 'ring_power', name = 'ちからの腕輪', char = '=', kind = 'ring', weight = 1, min_floor = 2, unidentified = true },
  { id = 'ring_antidote', name = '毒消しの腕輪', char = '=', kind = 'ring', weight = 1, min_floor = 3, unidentified = true },
  { id = 'ring_sneak', name = '忍び足の腕輪', char = '=', kind = 'ring', weight = 1, min_floor = 3, unidentified = true },
  { id = 'ring_stomach', name = '腹持ちの腕輪', char = '=', kind = 'ring', weight = 1, min_floor = 4, unidentified = true },
  { id = 'ring_sight', name = 'よくみえの腕輪', char = '=', kind = 'ring', weight = 1, min_floor = 2, unidentified = true },
  { id = 'stone', name = '石', char = ',', kind = 'stone', weight = 4, min_floor = 1 },
  { id = 'shield_leather', name = '皮の盾', char = ']', kind = 'shield', power = 2, weight = 3, min_floor = 2 },
  { id = 'shield_bronze', name = '青銅の盾', char = ']', kind = 'shield', power = 4, weight = 1, min_floor = 5 },
}

-- Appearance names for unidentified items (shuffled per run).
M.grass_names = { '赤い草', '青い草', '黄色い草' }
M.scroll_names = { '青い巻物', '赤い巻物', '古びた巻物', '光る巻物' }
M.wand_names = { 'ひのきの杖', 'ねじれた杖', '鉄の杖' }
M.ring_names = { '金の腕輪', '銀の腕輪', '銅の腕輪', '翡翠の腕輪', '黒曜石の腕輪' }

-- Goal items. Picking one up wins the game.
M.goal = { id = 'tome', name = 'Vimの聖典', char = '&', kind = 'goal' }
M.goal_hard = { id = 'tome_hard', name = 'Neovimの奥義書', char = '&', kind = 'goal' }

-- Shopkeeper. Turns hostile if you run off with goods.
M.keeper = { name = 'ダンジョンの店主', char = 'K', hp = 120, atk = 25, def = 5, exp = 100, speed = 2 }

-- Boss guarding the tome. Never moves off it; breathes fire in straight lines.
M.boss = { name = '聖典の守護竜', char = 'X', hp = 80, atk = 18, def = 4, exp = 200 }

-- Traps. Invisible until triggered, then shown as ^.
M.traps = {
  { id = 'spike', name = 'とげの罠', kind = 'spike' },
  { id = 'poison', name = '毒矢の罠', kind = 'poison' },
  { id = 'confuse', name = '混乱の罠', kind = 'confuse' },
  { id = 'bigroom', name = '大部屋の罠', kind = 'bigroom' },
  { id = 'summon', name = '召喚の罠', kind = 'summon' },
  { id = 'warp', name = 'ワープの罠', kind = 'warp' },
  { id = 'pit', name = '落とし穴', kind = 'pit' },
}

return M
