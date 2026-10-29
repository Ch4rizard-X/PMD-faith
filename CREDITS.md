# Credits

PMD-faith stands on the work of many people. Thank you all.

## The original games

*Red Rescue Team*, *Explorers of Sky* and *Rescue Team DX* were made by Chunsoft (Spike Chunsoft) and published by Nintendo and The Pokémon Company. Pokémon belongs to Nintendo, Creatures and Game Freak. This is an unofficial fan project; please support the official games.

## Decompilation and research

- **[pret/pmd-red](https://github.com/pret/pmd-red)** and all its contributors: the decompilation of *Red Rescue Team*. The game logic, rules, AI, story scripts, maps, text, fixed rooms, IQ, quiz, missions, Wonder Mail tables, graphics formats and the sound sequences all come from or were ported from it.
- **[pret/pmd-sky](https://github.com/pret/pmd-sky)** and its contributors: the *Explorers of Sky* decompilation (IQ skill add-ons, data layouts).
- **[UsernameFodder/pmdsky-debug](https://github.com/UsernameFodder/pmdsky-debug)** and its contributors: *Explorers of Sky* symbols and research.
- **[SkyTemple](https://github.com/SkyTemple)** / [skytemple-files](https://github.com/SkyTemple/skytemple-files): *Explorers of Sky* file formats and `pmd2scriptdata.xml` (map names).
- **psy_commando** ([ppmdu](https://github.com/PsyCommando/ppmdu)): DSE sound format documentation, used to write the *Explorers of Sky* music renderer.
- **Kermalis** ([VGMusicStudio](https://github.com/Kermalis/VGMusicStudio)): reference for DSE playback.

## Sprites and portraits

- **[PMDCollab SpriteCollab](https://github.com/PMDCollab/SpriteCollab)**, licensed CC BY-NC 4.0: every Pokémon sprite and portrait the game uses, by CHUNSOFT (the original art) and 180+ community artists. The full list of artists, and who made each sprite and portrait, is in [CREDITS_SPRITES.md](CREDITS_SPRITES.md). The build writes an up-to-date copy of it to `build_work/tmp/CREDITS_sprites.md` from SpriteCollab's own `tracker.json` and `credit_names.txt`.

## Added content

- **The *Explorers Remixed* team**: move data, abilities, items and the dungeon spawn and item lists used for the content added on top of *Red Rescue Team*.
- **[PokeAPI](https://github.com/PokeAPI/pokeapi)** and its contributors: species, stats, types, abilities and names for Pokémon outside the original game.
- **[PokeAPI/sprites](https://github.com/PokeAPI/sprites)**: the Exp. Share item icon (optional, placed by hand in `game/assets/ui/item_extra/expshare.png`; not included here, the game falls back to Red's ribbon icon).

## Tools and libraries

- **[Godot Engine](https://godotengine.org)** (MIT) and its contributors.
- **xBRZ** by Zenju (GPL-3.0), through the [xbrz.py](https://github.com/ioistired/xbrz.py) binding by ioistired: the HD upscaling of tiles and maps.
- **Pillow**, **NumPy** and **FFmpeg**, used by the build tools.

## This project

Code by Ch4rizard-X, written with Claude (Anthropic).

If you find your work used here without credit, please open an issue and it will be added.
