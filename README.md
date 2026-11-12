# vim-dungeons

A Mystery-Dungeon-style (Torneko / Shiren-like) roguelike that runs entirely
inside Neovim. Descend a procedurally generated dungeon with `hjkl`, fight
turn-based battles, identify mysterious scrolls, haggle with a shopkeeper, and
bring back the legendary Tome of Vim from floor B10.

```
B1F  Lv:1  HP:17/20  Hunger:95  G:0  Turn:35  Wpn:Club  Shd:-  Brc:-
#################.#######.......####%......!..##############
#################.#######.....................##############
#################.#######.....@.####..........##############
########...........##########.######..........##############
########......>.$.........................##################
```

## Features

- Procedurally generated floors: rooms and corridors, plus rare special floors
  (one vast hall, or a twisting maze with 1-cell visibility)
- Turn-based: enemies move when you move
- Mystery-Dungeon-style field of view (full room inside rooms, radius 1 in corridors)
- 9 enemy types with traits (double-speed, wall-phasing, venom, sleeping ambushes)
  and a stationary fire-breathing boss guarding the goal
- Items with per-run unidentified names (herbs, scrolls, wands, bracelets),
  price-based identification at shops, cursed gear, upgrade values, and stacking stones
- Vim-flavored items: the Scroll of f (leap to a character like the `f` motion),
  the Scroll of `:g//d` (smite enemies in sight), and the Scroll of `:w!`
  (write-upgrade your gear, overwriting curses)
- Shops with a running tab: buy, sell, put goods back, or run and face the keeper
- Traps (spikes, poison darts, confusion, warps, pitfalls, big-room collapse, summons)
- Quality of life: dash, auto-explore, throw/zap projectile animations,
  message log, suspend save
- Four classes: the balanced Wanderer, the sturdy Fighter, the sneaking
  Thief, and the Sage who knows every scroll and wand
- Meta progression: high scores, 13 achievements, a monster codex,
  a 25-floor hard mode, and a date-seeded daily challenge with a local ranking
- Replays: every finished run is recorded as its seed and keystrokes; export
  it, watch it, or send it to a friend, whose copy re-plays it to check the
  result before adding it to their daily ranking

## Requirements

- Neovim 0.10+ (tested on 0.11)

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'printemps-tokyo/vim-dungeons',
  cmd = {
    'VimDungeons', 'VimDungeonsHard', 'VimDungeonsDaily',
    'VimDungeonsScores', 'VimDungeonsAchievements', 'VimDungeonsDex',
    'VimDungeonsReplay', 'VimDungeonsRanking',
  },
}
```

Or try it without installing:

```sh
git clone https://github.com/printemps-tokyo/vim-dungeons
nvim --cmd 'set rtp+=vim-dungeons' +VimDungeons
```

## Language

Game text defaults to English. For Japanese:

```lua
vim.g.vim_dungeons_lang = 'ja'
```

## Commands

| Command | Description |
|---|---|
| `:VimDungeons [class]` | Start (resumes a suspend save if one exists; `:VimDungeons!` or a class starts fresh) |
| `:VimDungeonsHard [class]` | The Abyss: 25 floors, no starting supplies, steeper scaling |
| `:VimDungeonsDaily [class]` | Daily challenge: everyone gets the same dungeon that day |
| `:VimDungeonsRanking [YYYY-MM-DD]` | The local daily ranking (today by default) |
| `:VimDungeonsReplay export [file]` | Write the last finished run's replay to a file |
| `:VimDungeonsReplay play [file]` | Watch a replay (the last run by default): `q` stop, `Space` pause, `+`/`-` speed |
| `:VimDungeonsReplay verify file` | Re-play a replay without drawing and check the result it claims |
| `:VimDungeonsReplay import file` | Verify a replay and, for a daily run, add it to that day's ranking |
| `:VimDungeonsScores` | High scores (top 10) |
| `:VimDungeonsAchievements` | Achievement progress (13 total) |
| `:VimDungeonsDex` | Monster codex (encounters and kill counts) |

## Classes

Without a class argument (and without `vim.g.vim_dungeons_class`), a new run
starts with a class menu. `r` after a run starts again with the same class.

| Class | Start |
|---|---|
| `wanderer` | The original start: 20 HP, attack 6, bread and a herb |
| `fighter` | Max HP +8, attack +2, wielding a Club+1 |
| `thief` | Born sneaking: sleepers in your room stay asleep, as with the Sneaking bracelet. Carries 5 stones. Max HP -2 |
| `sage` | Every scroll and wand is identified from the start. Carries a Wand of Lightning with 3 charges. Max HP -4 |

Every class also gets the bread and herb (none in the Abyss).

```lua
vim.g.vim_dungeons_class = 'thief' -- skip the menu
vim.g.vim_dungeons_name = 'alice'  -- your name in replays and the daily ranking
```

## Controls

| Key | Action |
|---|---|
| `h j k l` / arrows | Move |
| `y u b n` | Move diagonally |
| `H J K L Y U B N` | Dash (stops on obstacles, items, or enemies in sight) |
| `o` | Auto-explore (walks toward unexplored areas, stops on events; heads to the stairs when done) |
| `.` | Rest one turn |
| `>` | Descend the stairs (while standing on them) |
| `i` | Inventory (`a`-`j` to use/equip, `q` to close) |
| `t` | Throw an item (choose, then a direction) |
| `d` | Drop an item at your feet (returns shop goods to the shelf) |
| `S` | Sell to the shopkeeper (inside a shop) |
| `M` | Message log |
| `?` | Help |
| `Q` | Suspend-save and quit |

## How to play

### Goal

- The Tome of Vim `&` lies on floor B10. Pick it up to win
- A guardian dragon `X` (HP 80) sits on the tome. It never moves, but breathes
  fire along straight lines within range 4 (shields reduce it). You cannot
  reach the tome until it falls
- Death shows your cause of death and records your run (top 10 kept)

### Exploring

- HP regenerates as you walk; hunger ticks down over time and starving drains HP
- The status line turns red as a warning below 25% HP
- Rare special floors: a hall (8%, the whole floor is one room) and a maze
  (8%, no rooms, permanent 1-cell visibility)
- Hidden traps lurk on the floor and appear as `^` once triggered:
  spikes, poison darts, confusion, warps, pitfalls, big-room collapse, summons

### Combat

- Walk into an enemy to attack. Kills have a 25% chance to drop gold
- Some enemies spawn asleep (dimmed). Attacking a sleeper is a guaranteed
  sneak attack for double damage, but they wake nearby
- Special enemies: the 2j Rabbit acts twice per turn, the gg Ghost phases
  through walls, Venom Snakes poison you, Bats move erratically
- Monster houses: rooms packed with enemies that all wake the moment you enter
- Ailments show in the status line: poison (HP drain, no regen) and confusion
  (movement veers off). They wear off with time, or drink a herb

### Items and identification

- Herbs, scrolls, wands, and bracelets drop unidentified ("Blue Scroll") with
  appearances shuffled every run; using one reveals its kind
- Healing Herb (heals + cures ailments; +1 max HP at full), Big Bread (hunger)
- Scrolls: Clairvoyance (reveal layout), `:g//d` (heavy damage to enemies in
  sight), f (leap to a typed character, Vim style), `:w!` (upgrade and uncurse gear)
- Wands `/` hold 3-5 charges: Lightning (20 damage bolt) and Swapping
  (switch places with the target). They shatter when spent
- Stones `,` stack and are for throwing (8 damage)

### Equipment

- Three slots: weapon `)`, shield `]`, bracelet `=`
- Gear rolls an upgrade value from -1 to +3 (shown as `Club+2`). Negative gear
  is cursed: it looks normal until worn, then cannot be removed. A `:w!`
  scroll overwrites the curse
- Bracelets are passive: Power (+3 attack), Antidote (poison immunity),
  Sneaking (sleepers in your room stay asleep), Satiety (hunger halved),
  Insight (see hidden traps)

### Shops

- 12% of normal floors host a shop run by keeper `K`. Taking goods puts them
  on your tab, settled automatically when you leave the room
- Leave without enough gold and the keeper turns into a fast, furious enemy.
  You cannot take the stairs with an open tab
- `d` puts goods back on the shelf; `S` sells your items at half price.
  Since prices differ by kind, you can price-identify unknown items

### Modes and records

- `Q` suspend-saves your run; the next `:VimDungeons` resumes it
  (the save is consumed on resume)
- The Abyss (`:VimDungeonsHard`): 25 floors, no supplies, mixed strong
  spawns, and a buffed guardian holding the Secrets of Neovim
- Daily challenge (`:VimDungeonsDaily`): the dungeon is seeded by the date
- Achievements and the monster codex persist across runs

### Replays and the daily ranking

- A replay is the run's seed, mode, class, and every key you pressed. The
  game reseeds its random numbers before each key from the seed and the key's
  position, so the same keys always give the same run, even if other plugins
  use `math.random` meanwhile
- When a run ends it becomes the last replay (kept on disk). Write it out with
  `:VimDungeonsReplay export` and share the file
- `:VimDungeonsReplay verify` and `import` play the keys back without drawing
  and compare the outcome, floor, level, gold, and turns with what the file
  claims. Watching or checking a replay never writes scores, saves,
  achievements, or the codex
- Your own daily runs enter that day's ranking when they end. Friends' daily
  runs enter it through `import`, only when they verify, marked as verified
  replays. The ranking puts clears first, then deeper floors, fewer turns, and
  more gold, and keeps the top 20 per day
- `import` adds a daily run only if its seed is that day's date seed and it
  is not the Abyss, and takes the class from the re-played run. Replay files
  over 1 MiB or 200,000 keys are refused
- Replays depend on the Lua that runs Neovim: one recorded under LuaJIT may not
  verify under a Neovim built with PUC Lua, and a run that was suspended and
  resumed may not play back exactly. `verify` says so instead of accepting it

## Development

Run the test suite (43 sections, headless). The tests write scores and
replays into Neovim's data directory, so point it somewhere disposable:

```sh
XDG_DATA_HOME=$(mktemp -d) nvim --headless --clean -l tests/smoke.lua
```

Balance measurement (a BFS-driven bot plays N runs and reports win rate,
depth reached, and causes of death):

```sh
RUNS=30 nvim --headless --clean -l tests/balance.lua
# HARD=1 for the Abyss, VERBOSE=1 for per-run results
```

Layout:

```
plugin/vim-dungeons.lua          user commands
lua/vimdungeons/init.lua         startup, keymaps, score/achievement/codex views
lua/vimdungeons/game.lua         game state, turn engine, input
lua/vimdungeons/items.lua        item use, throwing, wands, f-jump, pricing
lua/vimdungeons/enemies.lua      enemy spawning, combat, AI
lua/vimdungeons/dungeon.lua      floor generation (rooms, hall, maze)
lua/vimdungeons/render.lua       buffer rendering, floats, animations
lua/vimdungeons/data.lua         enemy/item/trap/boss definitions
lua/vimdungeons/i18n.lua         localization (English default, Japanese source)
lua/vimdungeons/score.lua        high-score persistence
lua/vimdungeons/achievements.lua achievement definitions and persistence
lua/vimdungeons/save.lua         suspend-save I/O
lua/vimdungeons/dex.lua          monster codex persistence
lua/vimdungeons/replay.lua       replay encoding, playback setup, verify, import
lua/vimdungeons/daily.lua        local daily ranking
tests/smoke.lua                  smoke tests
tests/balance.lua                autoplay balance measurement
```

Note: tests assert the Japanese source strings and therefore pin
`vim.g.vim_dungeons_lang = 'ja'`; a dedicated section verifies the English
translations.

## License

[MIT](LICENSE)
