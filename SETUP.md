# Setup guide

This guide takes you from nothing to playing, step by step. You don't need to know anything about programming: on Windows you double-click two files and answer a few questions.

**What happens:** this repository only contains the game's *code*. The pictures, music, text and data come from the original games, so the setup builds them on your PC **from your own copies of the games** (your ROM files). Nothing from the games is downloaded from here.

| | |
|---|---|
| Time | about 15 minutes of your time, then 1–3 hours of waiting while the PC works |
| Disk space | about 4 GB free |
| Internet | needed for the first build (about 2 GB of community resources are downloaded) |
| PC | Windows 10 or 11 for the easy way below; Mac and Linux further down |

---

## Part 0: Get your three ROM files ready

You need these three files. They must come from games you own (for example dumped from your own cartridges); this project can't give them to you.

1. **Pokémon Mystery Dungeon: Red Rescue Team** for Game Boy Advance, **US version**. A file ending in `.gba`, about 32 MB.
2. **Pokémon Mystery Dungeon: Explorers of Sky** for Nintendo DS, **US version**, the normal unchanged game. A file ending in `.nds`, exactly 128 MB.
3. **Explorers Remixed**: a *second copy* of Explorers of Sky with the fan patch *Explorers Remixed* applied. Get the patch from its official release and apply it to a copy of your Explorers of Sky file, following the patch's own instructions. Keep the normal file too: you need both.

Put the three files together in one folder you can find again, for example `C:\Games\ROMs`. Their names don't matter.

> If a file is wrong (another region, the wrong game, or the two Explorers of Sky files mixed up), the build notices it at the start and tells you which one.

---

## Part 1 (Windows): Download PMD-faith

1. On the PMD-faith page on GitHub, click the green **Code** button, then **Download ZIP**.
2. Open your Downloads folder, right-click the ZIP and choose **Extract All…**
3. Extract it to a short path **without spaces**, for example `C:\PMD-faith`. Avoid the Desktop and OneDrive folders.
4. Open that folder. You should see files like `SETUP_STEP1_install_tools.bat`, `SETUP.md` and a folder called `game`.

---

## Part 2 (Windows): Install the tools (once)

Double-click **`SETUP_STEP1_install_tools.bat`**.

A black window opens and installs four free programs with Windows' own installer:

- **Python** runs the build scripts.
- **Git** downloads the community resources (sprites, decompiled game data).
- **FFmpeg** converts the music.
- **GCC** compiles a few small helper programs during the build.

It also installs two small Python add-ons (Pillow and NumPy).

- Windows may ask *"Do you want to allow this app to make changes to your device?"* for each one. Click **Yes**.
- If Windows shows a blue *"Windows protected your PC"* box when you double-click the file, click **More info**, then **Run anyway**. It's a plain text script; you can open it in Notepad to see exactly what it does.
- Tools you already have are skipped.

When it says **"Step 1 is done"**, **close the window**. This matters: Windows only finds newly installed programs in *new* windows.

> If it says the Python add-ons couldn't be installed yet, close the window and run Step 1 once more. That's normal straight after Python is installed.

---

## Part 3 (Windows): Build the game files

Double-click **`SETUP_STEP2_build_game_files.bat`**.

1. It checks that the tools from Part 2 are there.
2. A file window opens **three times**. Pick, in this order:
   1. your **Red Rescue Team** `.gba` file,
   2. your **normal Explorers of Sky** `.nds` file,
   3. your **Explorers Remixed** `.nds` file.

   Your choices are saved in `build_config.json`, so you only do this once.
3. The build starts. You'll see lines like `[4/6] sprites: packing the Pokémon sprites and portraits (slow) ...`. There are six steps; the last two take the longest. Leave the window open. You can keep using your PC, and it's fine if the window looks busy or quiet for a while.

When it says **"All done!"**, the game is ready to open. It has created `game\assets`, `game\data` and `game\icon.png`.

**If the build stops** with a message: read it (most problems are a wrong ROM or a missing tool; see Troubleshooting below), fix it, and double-click Step 2 again. **It continues where it stopped**; finished steps are skipped. Everything it printed is also saved in `build_work\build_log.txt`, which is handy if you need to ask someone for help.

---

## Part 4: Play

1. Download **Godot 4.7.2** from godotengine.org: the normal **Windows** version, *not* the ".NET" one. It's a ZIP; extract it anywhere. Godot doesn't need installing; just run the extracted `Godot_v4.7.2-stable_win64.exe`.
2. In Godot's Project Manager, click **Import**, browse to your PMD-faith folder, open the `game` folder and choose **`project.godot`**, then **Import & Edit**.
3. The first time, Godot imports all the game files. This takes a few minutes; wait until the progress bar is gone.
4. Press the **▶ Play** button at the top right (or the **F5** key). The game starts.

### Optional: make a normal Windows program (.exe)

So you can start the game without opening Godot:

1. In Godot: **Editor → Manage Export Templates… → Download and Install**. Wait for it to finish.
2. **Project → Export…** → **Add…** → **Windows Desktop**.
3. Click **Export Project…**, pick a folder **outside** the PMD-faith folder (for example `C:\Games\PMD-faith-game`), and save.
4. Double-click the `.exe` it made to play.

### Optional: Android / AYN Thor

Building the Android version needs extra tools (the Android SDK and Java 21). The script `build_thor.bat` does the work; its first lines explain what to install. This is the most technical part, so leave it until the Windows version runs.

---

## Updating to a newer version

1. Download the new ZIP (Part 1) and extract it **over** your existing PMD-faith folder, replacing the files. Your built game files, ROM choices and downloads stay.
2. Check [CHANGELOG.md](CHANGELOG.md). If the new version's notes say the game files must be rebuilt, delete the file `build_work\progress.json` and run Step 2 again. Otherwise just open the game in Godot as before.

---

## Troubleshooting

**"There is a problem with your ROM files"**
The build tells you which file is wrong:
- *"not the US Red Rescue Team ROM"*: that file is another game or another region. You need the US version.
- *"look swapped"*: you picked the Explorers of Sky files the wrong way round. Run Step 2, answer **N** to "Keep them?", and pick them again in the right order.
- *"are the same file"*: you picked the normal Explorers of Sky file twice. The third file must be the *patched* (Remixed) copy.

**"These tools are missing: …"**
Run Step 1 again, close its window, then run Step 2. If a tool still can't be found, install it by hand and restart the PC:
- Python: python.org/downloads (tick **"Add python.exe to PATH"** in the installer)
- Git: git-scm.com/download/win
- FFmpeg and GCC: run Step 1 again and watch for a red message about them.

**"winget was not found"**
Open the **Microsoft Store**, search for **App Installer**, install or update it, and run Step 1 again.

**The build stopped while downloading (git / network errors)**
Usually a short internet hiccup. Run Step 2 again; downloads that already finished are kept.

**"No space left on device" or a disk error**
Free up some space (about 4 GB is needed) and run Step 2 again.

**Godot shows errors about missing files when opening the project**
The build hasn't finished. Run Step 2 until it says "All done!", then open the project again.

**Something else**
Look at the last lines of `build_work\build_log.txt` and ask for help with that text.

---

## Mac and Linux

You need the same four tools; then three commands in a terminal.

1. Install the tools:
   - **Mac:** install Homebrew (brew.sh), then `brew install python git ffmpeg gcc` and `xcode-select --install`.
   - **Ubuntu / Debian:** `sudo apt install python3 python3-pip git ffmpeg build-essential`.
2. Install the Python add-ons: `python3 -m pip install --user pillow numpy`.
3. In the PMD-faith folder, copy `build_config.example.json` to `build_config.json` and put the paths of your three ROM files in it (Part 0 explains which is which).
4. Run `python3 build_all.py` and wait for "All done!". If it stops, fix the problem and run it again: it continues where it stopped.
5. Open `game/project.godot` with Godot 4.7.2 (Part 4).

---

## For the curious: what the build does

| Step | Makes |
|---|---|
| `fetch` | Downloads the community resources into `build_work` (the pret decompilations, SpriteCollab, PokeAPI data, SkyTemple's script data) and reads your ROMs |
| `data` | The game's tables: Pokémon, moves, items, Red's dungeons, IQ, the personality quiz, rescue jobs, text, Wonder Mail |
| `eos` | The Explorers of Sky / Remixed content: dungeons, boss arenas, items, abilities, Mega forms, move animations |
| `sprites` | Every Pokémon's sprites, portraits and shiny colours, and the app icon |
| `dungeon` | Dungeon tiles and graphics |
| `ground` | Story maps and scripts, the town, menus, the font, world maps, music and sound effects |

Advanced options: `python build_all.py --fresh` rebuilds everything from scratch, `--only sprites` runs a single step, and `--from dungeon` starts at a step. Each area also has a `compare.py` for comparing two builds.

---

## Please don't share the built files

Everything in `game/assets`, `game/data` and `build_work` comes from the original games. Keep it on your own PC: don't upload it or share builds that contain it. `.gitignore` keeps it out of git; please keep it that way in forks.
