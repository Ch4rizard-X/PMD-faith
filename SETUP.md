# Setup

The game needs two folders that are **not** in this repository: `game/assets/` (sprites, portraits, tiles, maps, music, sound effects, move animations, UI graphics) and `game/data/` (species, moves, items, dungeons, text, story scripts…). You build both yourself, from your own ROMs and free community resources, with one command.

## What you need

- Your own ROMs (dumped from cartridges you own):
  - *Red Rescue Team* (GBA, US)
  - *Explorers of Sky* (NDS, US)
  - *Explorers Remixed* (the *Explorers of Sky* ROM with the Remixed patch applied)
- Python 3.11 or newer, with **Pillow** and **NumPy** (`pip install pillow numpy`)
- **git**, **FFmpeg** (on your PATH), a **C compiler** (gcc or clang; for one fixed-room step) and a **C++ compiler** (g++ or clang++; to build the xBRZ scaler, unless you `pip install xbrz.py`)
- About 4 GB of free disk space
- [Godot 4.7.2](https://godotengine.org/download) to run the game

## Build in three steps

1. **Point the build at your ROMs.** Copy `build_config.example.json` to `build_config.json` and fill in the three paths:

   ```json
   {
     "red_rom": "roms/red.gba",
     "eos_rom": "roms/sky.nds",
     "remix_rom": "roms/remixed.nds"
   }
   ```

   Relative paths are relative to this folder. A `roms/` folder here is ignored by git. You can also set `RED_ROM`, `EOS_ROM`, `REMIX_ROM` (and `WORK_DIR`) as environment variables instead.

2. **Build everything:**

   ```
   python build_all.py
   ```

   This downloads the public resources (pret/pmd-red, pret/pmd-sky, SpriteCollab, PokeAPI, SkyTemple's script data, xbrz.py) into `build_work/`, extracts your ROMs there, and writes `game/assets/`, `game/data/` and `game/icon.png`. It takes one to two hours, mostly music rendering and sprite packing. If it stops, fix the problem and continue where it left off with `python build_all.py --from <step>`.

3. **Open `game/project.godot` in Godot 4.7.2** and press Play. The first import takes a few minutes.

## Build steps

| Step | Tool | Makes |
|---|---|---|
| `fetch` | `tools/fetch.py` | Downloads and ROM extraction (into `build_work/`) |
| `data` | `tools/data/build.py` | Base tables from the decompilation and PokeAPI: species, moves, items, Red's dungeons, fixed rooms, IQ, quiz, missions, text, Wonder Mail tables |
| `eos` | `tools/eos/build.py` | *Explorers of Sky* / *Remixed* content on top: dungeons, boss arenas, items, abilities, Mega forms, move animations |
| `sprites` | `tools/sprites/build.py` | Pokémon sprites, portraits, shiny colours, shadow markers, the app icon (from SpriteCollab) |
| `dungeon` | `tools/dungeon/build.py` | Dungeon tilesets and dungeon graphics (from the ROMs) |
| `ground` | `tools/ground/build.py` | Story maps and scripts, the town, UI graphics and font, world maps, music and sound effects |

Run a single step with `python build_all.py --only <step>`. Each area also has a `compare.py` for checking its output against another build.

## Android APK (optional)

`build_thor.bat` (Windows) builds the ThorScreen second-screen plugin in `android/thor_plugin`, installs Godot's Android build template and exports `game/build/PMDRed-Thor.apk`. It needs the Android SDK (set `ANDROID_HOME`), JDK 21 and Godot's export templates; see the comments at the top of the file. The debug variant is `build_thor_debug.bat`.

## Please don't share the built files

Everything in `game/assets/`, `game/data/` and `build_work/` comes from the original games. `.gitignore` keeps them out of git; keep it that way in forks, and don't upload or share builds that contain them.
