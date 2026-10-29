# PMD-faith

A from-scratch, 1:1 remake engine for the GBA dungeon crawler *Red Rescue Team* (2005), written in Godot 4.7 (GDScript), with content and features from the later games in the series added on top.

**This repository contains code and tools only.** It ships no game assets: no graphics, music, sound, text or data tables. You build those yourself from your own legally obtained copies of the games (see [SETUP.md](SETUP.md)). Without them the project will not run.

This is an unofficial fan project. It is not affiliated with, endorsed or sponsored by Nintendo, The Pokémon Company, Creatures, Game Freak, Spike Chunsoft or any of their partners. All names and trademarks belong to their owners.

## What it does

The game logic is ported from the community decompilation of the original game, so dungeons, combat, AI, IQ, items, rescue jobs and story scripts behave like the GBA game. On top of that:

| | Original | This engine |
|---|---|---|
| Species | 386 | 981 + 57 Mega/Primal forms |
| Moves | 430 | 737 |
| Abilities | 76 | 170 |
| IQ skills | 23 | 62 |
| Items | 240 | 1,428 (909 exclusive items) |
| Dungeons | 64 | 221 (157 from *Explorers of Sky*) |

Added or changed, among them:

- **Content from *Explorers of Sky* / *Explorers Remixed*:** dungeons, items, exclusive items, treasure boxes, abilities, IQ skills, move animations, music, an extra world map. Dungeons in several parts are played in one trip as in *Explorers of Sky* (Steam Cave, Upper Steam Cave, Steam Cave Peak ...). Recruiting works in the *Explorers of Sky* dungeons too (boss floors once the dungeon is cleared).
- **Move Growth** from *Explorers Remixed*: damaging moves level up with use (up to Lv 25: more power, PP and accuracy). Optional.
- **Hard mode:** a planned level curve through the story (ending with Rayquaza at Lv 70), a post-game from Lv 70 to 100, more wild Pokémon per floor. Normal or Hard, switchable any time.
- **From *Rescue Team DX*:** Empowerment Seed (Awakened state with Mega Evolution), shiny Pokémon (including shiny hunting for legendaries), temporary recruits.
- **New items:** Exp. Share (its holder gains 50% more Exp.; very rare in Kecleon's shop).
- **Quality of life (each can be switched off):** run mode, tap to walk, damage preview, info on long-press, map markers and corner minimap, auto-pickup filter, low-HP warning, team item prompts, burn/poison wear-off, hunger off, prepare screen, menu size, Auto bank (money goes to the bank after a dungeon and town shops pay from it). Menus remember the cursor.
- **Town:** store/take all, sell all, bulk job accept, a Pokédex and recruit tracker.
- **Autoplay:** explores each floor, fights to level up, fetches job items, uses linked moves, eats and heals; stops when HP is low.
- **Wonder Mail:** byte-compatible with the original codes, plus an in-game code maker.
- **Second screen** (AYN Thor and other dual-screen devices, or a second window on PC), *Explorers of Sky*-style: the dungeon map, team and log; in town the team, location and jobs; item, job and dungeon info (what lives in a dungeon, in the Pokédex colours) and Friend Area residents while you browse.
- **Platforms:** Android and Windows, touch controls, controller support with rebinding.

## Layout

```
game/        Godot project (scripts, scenes, shaders, tests). Assets and data go in game/assets and game/data (not included).
tools/       Python tools that build game/assets and game/data from your own ROMs and community resources.
build_all.py One command that runs every tool in order (see SETUP.md).
android/     Source of the ThorScreen Android plugin (second-screen support).
build_thor.bat, build_thor_debug.bat, set_godot_java.ps1   Windows build scripts for the Android APK.
```

## Building

**Windows (no programming needed):** download the ZIP, then double-click `SETUP_STEP1_install_tools.bat`, close it, and double-click `SETUP_STEP2_build_game_files.bat`. It asks for your three ROM files and builds everything. Then open `game/project.godot` in Godot 4.7.2 and press Play.

**Mac / Linux:** set your ROM paths in `build_config.json` (copy `build_config.example.json`), run `python3 build_all.py`, then open the project in Godot 4.7.2.

The step-by-step guide, with what to expect at each step and fixes for common problems, is [SETUP.md](SETUP.md).

## Patch notes

What changed in each version is in [CHANGELOG.md](CHANGELOG.md) and on the Releases page.

## Credits

This project would not exist without the [pret](https://github.com/pret) decompilations, SkyTemple, the PMDCollab SpriteCollab artists, PokeAPI and the *Explorers Remixed* team, among others. The full list is in [CREDITS.md](CREDITS.md), and every sprite and portrait artist is in [CREDITS_SPRITES.md](CREDITS_SPRITES.md).

## License

The code in this repository is licensed under the GNU General Public License v3.0 (see [LICENSE](LICENSE)). The license covers only the original code here; it grants no rights to any game, its assets or third-party resources.
