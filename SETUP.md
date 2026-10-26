# Setup: building the assets and data

The engine needs two folders that are **not** in this repository:

- `game/assets/` — sprites, portraits, tiles, ground maps, music, sound effects, move animations, UI graphics.
- `game/data/` — JSON tables: species, moves, items, dungeons, text, scripts and so on.

Everything in them comes from the original games and community resources, so you generate it yourself with the tools in `tools/`.

> **Status:** the tools were written while developing the game and still have their input/output paths set at the top of each file (they point at the original development folders). Before running a tool, edit those paths. There is no one-command build yet.

## What you need

| Input | Used for |
|---|---|
| Your own *Red Rescue Team* (GBA, US) ROM | Dungeon tiles, arena tilesets, status icons, UI graphics |
| Your own *Explorers of Sky* (NDS, US) ROM | *Explorers of Sky* dungeons, fixed rooms, move animations, music |
| Your own *Explorers Remixed* patched *Explorers of Sky* ROM | Move data, abilities, items, dungeon spawn/item lists for added content |
| [pret/pmd-red](https://github.com/pret/pmd-red) checkout (built `baserom` not required for the data tools) | Rules, text, ground scripts, map backgrounds, fixed rooms, IQ, quiz, missions, Wonder Mail tables, music sequences |
| [PMDCollab/SpriteCollab](https://github.com/PMDCollab/SpriteCollab) | Pokémon sprites, portraits, shiny colours |
| [PokeAPI](https://github.com/PokeAPI/pokeapi) CSV data (`data/v2/csv`) | Stats, types and abilities for species outside the original |
| Python 3.11+ with Pillow and numpy; ffmpeg | Running the tools; music rendering |

## Tools and what they produce

### Data tables (`tools/data/`)

| Tool | Writes (in `game/data/`) |
|---|---|
| `gen_data.py` | `species.json`, `growth.json`, `evo.json`, `types.json`, base `moves.json` / `items.json` |
| `gen_red_evo.py` | `red_evo.json` (Luminous Cave evolutions) |
| `gen_iq.py`, then `gen_iq_sky.py` | `iq.json` (original IQ skills + *Explorers of Sky* add-ons) |
| `gen_quiz.py` | `quiz.json` (personality test) |
| `gen_missions.py`, `gen_wondermail.py` | `missions.json`, `friend_areas.json`, Wonder Mail tables |
| `gen_dungeons.py` | `dungeons.json` (original dungeons) |
| `gen_fixed_rooms.py` | `fixed_rooms.json` (fixed rooms, boss scenes) |
| `gen_world_map.py` | `world_map.json` |
| `gen_town.py` | `town.json` |
| `extract_text.py`, `gen_menu_text.py` | `red_town_text.json`, `menu_text.json` |
| `kec_sets.py`, `icons.py` | `kecleon_sets.json`, `item_icons.json` |
| `ndsget.py`, `ndsx.py` | Extract files from an NDS ROM (used by the *Explorers* tools) |
| `gen_eos_items.py` | *Explorers of Sky* / Remixed items added to `items.json` |
| `convert_remix.py` | *Explorers Remixed* dungeons and abilities into `dungeons.json` / `species.json` |
| `gen_extra_spread.py` | Places added species into fitting dungeons |
| `gen_megas_dx.py` | Mega/Primal forms (species, sprites) |
| `gen_shiny.py` | `shiny.json` (shiny colour tables from SpriteCollab) |
| `prep_assets.py` | `sprites.json`, `marks.json`, `tilesets.json` and the sprite sheets in `game/assets/sp` |

Run order: `gen_data.py` → `gen_red_evo.py` → `gen_iq.py` → `gen_iq_sky.py` → `gen_quiz.py` → `gen_missions.py` → `gen_wondermail.py` → `gen_dungeons.py` → `gen_fixed_rooms.py` → `gen_world_map.py` → `gen_town.py` → text/icon tools → `tools/eos/*` → `gen_eos_items.py` → `convert_remix.py` → `gen_extra_spread.py` → `gen_megas_dx.py` → `gen_shiny.py`.

> **Known gap:** `gen_data.py` and `prep_assets.py` read base tables exported from the project's earlier prototype (`dump.py` / `dump2.py`). Rebuilding those base tables straight from the decompilation and PokeAPI is not automated yet.

### *Explorers of Sky* (`tools/eos/`)

`convert_dungeons.py` (dungeons and spawn tables), `fixed_rooms.py` (`eos_fixed.json`), `tilesets.py`, `eoslib.py` (shared readers).

### Ground maps and story (`tools/ground/`)

`gen_ground_bg.py` (map backgrounds from the decomp's `data/map_bg`), `gen_ground_scripts.py` and `gen_ground_extra.py` (story scripts → `game/data/ground/`), `gen_ground_assets.py`, `gen_ornaments.py`, `gen_front_assets.py` (boot/title screens), `gen_credits.py` (`red_credits.json`), `gen_maze_tiles.py`, `titlen.py`.

### Dungeon graphics (`tools/dungeon/`)

`gen_dungeon_gfx.py` (`dungeon_gfx.json`, `dungeon_talk.json`, `fx.json`, arena tilesets, status icons from the GBA ROM), with `redrom.py`, `dtiles.py`, `efbg.py`, `zmap.py`.

### Move animations (`tools/fx/`)

`export_fx.py`, `build_data.py`, `build_moves.py` (*Explorers of Sky* / Remixed move effects → `game/assets/fx`, `move_fx.json`), with helpers.

### Sprites (`tools/sprites/`)

`gen_allanims.py` packs every SpriteCollab animation per species; `mapkeys.py`, `verify.py`.

### Music (`tools/music/`)

- `red/render.py`: renders the original GBA soundtrack from the decomp's song data (MP2K/m4a).
- `eos/make.py` (+ `render.py`, `dse.py`, `samples.py`): renders *Explorers of Sky* music (DSE) to OGG.
- `loops/`: finds seamless loop points (`eos_loops.json`).

## Building the APK

See the comments at the top of `build_thor.bat`. It builds the ThorScreen plugin in `android/thor_plugin`, installs Godot's Android build template and exports `game/build/PMDRed-Thor.apk`.

## Don't commit assets

`.gitignore` keeps `game/assets/`, `game/data/` and builds out of git. Please keep it that way in forks: no ROM-derived files in the repository.
