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

Added or changed (54 in total), among them:

- **Content from *Explorers of Sky* / *Explorers Remixed*:** dungeons, items, exclusive items, treasure boxes, abilities, IQ skills, move animations, music, an extra world map.
- **From *Rescue Team DX*:** Empowerment Seed (Awakened state with Mega Evolution) and shiny Pokémon, including shiny hunting for legendaries.
- **Quality of life (each can be switched off):** run mode, tap to walk, damage preview, info on long-press, map markers and corner minimap, auto-pickup filter, low-HP warning, team item prompts, burn/poison wear-off, hunger off, prepare screen, menu size.
- **Town:** store/take all, sell all, bulk job accept, a Pokédex and recruit tracker.
- **Wonder Mail:** byte-compatible with the original codes, plus an in-game code maker.
- **Platforms:** Android and Windows, touch controls, controller support with rebinding, autoplay, and AYN Thor dual-screen support with an *Explorers of Sky*-style second screen.

## Layout

```
game/        Godot project (scripts, scenes, shaders, tests). Assets and data go in game/assets and game/data (not included).
tools/       Python tools that build game/assets and game/data from your own ROMs and community resources.
android/     Source of the ThorScreen Android plugin (second-screen support).
build_thor.bat, build_thor_debug.bat, set_godot_java.ps1   Windows build scripts for the Android APK.
```

## Building

1. Create the assets and data with the tools (see [SETUP.md](SETUP.md)).
2. Open `game/project.godot` in Godot 4.7.2.
3. Android: run `build_thor.bat` (needs the Android SDK and Godot's export templates). Windows/desktop: export from the Godot editor.

## Credits

- [pret/pmd-red](https://github.com/pret/pmd-red): the decompilation the game logic, rules and story scripts are ported from.
- [pret/pmd-sky](https://github.com/pret/pmd-sky) and [UsernameFodder/pmdsky-debug](https://github.com/UsernameFodder/pmdsky-debug): *Explorers of Sky* research.
- [SkyTemple](https://github.com/SkyTemple): file format references for *Explorers of Sky*.
- [PMDCollab SpriteCollab](https://github.com/PMDCollab/SpriteCollab): the sprites and portraits the engine is built for (CC BY-NC 4.0; credits per sprite in SpriteCollab).
- [PokeAPI](https://github.com/PokeAPI/pokeapi): species, stats and ability data for Pokémon outside the original.
- *Explorers Remixed* by its authors: move data, abilities, items and dungeon lists used for the added content.

## License

The code in this repository is licensed under the GNU General Public License v3.0 (see [LICENSE](LICENSE)). The license covers only the original code here; it grants no rights to any game, its assets or third-party resources.
