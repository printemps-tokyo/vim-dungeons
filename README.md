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
- Meta progression: high scores, 13 achievements, a monster codex,
  a 25-floor hard mode, and a date-seeded daily challenge

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
| `:VimDungeons` | Start (resumes a suspend save if one exists; `:VimDungeons!` starts fresh) |
| `:VimDungeonsHard` | The Abyss: 25 floors, no starting supplies, steeper scaling |
| `:VimDungeonsDaily` | Daily challenge: everyone gets the same dungeon that day |
| `:VimDungeonsScores` | High scores (top 10) |
| `:VimDungeonsAchievements` | Achievement progress (13 total) |
| `:VimDungeonsDex` | Monster codex (encounters and kill counts) |

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

## Development

Run the test suite (39 sections, headless):

```sh
nvim --headless --clean -l tests/smoke.lua
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
tests/smoke.lua                  smoke tests
tests/balance.lua                autoplay balance measurement
```

Note: tests assert the Japanese source strings and therefore pin
`vim.g.vim_dungeons_lang = 'ja'`; a dedicated section verifies the English
translations.

## License

[MIT](LICENSE)
