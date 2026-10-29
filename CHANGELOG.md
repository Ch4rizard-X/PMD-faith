# Changelog

Patch notes for every version of the engine, newest first. Version numbers match the Android builds.
Everything listed here is code; the game's graphics, music and data are built from your own ROMs (see [SETUP.md](SETUP.md)).

## v0.8.14 (29 Oct 2026)

- **Weather in the 3D view:** rain soaks the floor and walls (darker, shinier, with highlights), splashes on the ground and rings on water; snow settles in drifts on wall tops, floors and grass tips; hail leaves a light coating; fog drifts over the floor in banks; sandstorms blow sand across it; sunny weather brightens and warms the light, cloudy and rainy weather dim and cool it. Wetness and snow build up and fade over a few seconds.
- **Shader packs:** Soft, Cinematic, Claymation and Dream no longer wash out on bright floors; distance fog now thickens toward the top of the screen (the far side of the view) instead of covering everything evenly.
- **Main menu: Check for Updates** asks the Releases page right away (also with Auto update switched off) and offers to restart into a new version.

## v0.8.13 (29 Oct 2026)

- **3D view (new, optional):** Game Options -> 3D View -> View: 3D plays the dungeons as voxel dioramas built from the floor's own tiles. Walls are stone faces in the tileset's cliff colours with rounded tops; the wall material is read from the tile colours (grass and flowers, rock, snow with icicles, puffy clouds, crystal clusters); water and lava sit below the floor, chasms drop deep; the map is extended with wall past its edges, so no black borders. Pokémon are rounded voxel figures made from their sprites, and animate with them. Items, traps, stairs, move animations, status icons, damage numbers and tapping the map work as in 2D. Works in Red and Explorers of Sky dungeons. Quick keys: V next shader pack, Shift+V 2D / 3D (controller: Select+R, Select+L).
- **Shaders for the 3D view:** glowing flowing lava, see-through water with waves, swaying grass and seaweed, torch light around the team on dark floors, Pokémon outlines, 3D rain / hail / snow / sandstorm, and a screen pass for colour and film effects.
- **Shader packs:** Off, Classic, Soft, Vibrant, Cinematic, Retro, Toon, Claymation, Miniature, Storybook, Neon Night, Golden Hour, Monochrome and Dream; 28 settings to adjust any pack (light, colour, outlines, grass, water, lava, torch, glow, fog, corner shading, depth of field, grain, vignette, scanlines, colour fringe, weather, resolution), a Performance preset (Battery / Balanced / Quality), Pack per dungeon (Auto) and Save as my pack. Custom packs (with their own shader code) load from the user folder: see [SHADERPACKS.md](SHADERPACKS.md).
- **Explorers of Sky boss arenas:** the team stands on the arena's marked spots (it was dropped next to the boss), and arenas use their dungeon's graphics instead of Tiny Woods' (the boss rooms' own graphics aren't converted yet). Each boss says a line before the fight.
- **Confusion** now affects the leader too: steps and attacks go in random directions, as in Red.
- **Autoplay modes:** Fight (explore, fight, fetch job items, as before) or Stairs (straight to the stairs; floors with a job are still played in full). In the dungeon Options (Autoplay: Off / Fight / Stairs) and Game Options -> Dungeon.
- **Makuhita Dojo mazes** match the team: wild Pokémon are 1 level above the team's level, on Normal and Hard.

## v0.8.12 (29 Oct 2026)

- **Auto update (script patches):** the game checks this repository's Releases page when it starts and downloads a small patch (the open-source scripts, scenes and shaders, about 600 KB) when there is a newer one. Its size and SHA-256 are checked, and it is used from the next start; at the main menu the game offers to restart into it. Saves are not touched. A patch never holds game data, graphics or music: changes that need those (or a new engine, plugin or project setting) need a new build, and older builds skip the patch. A patch that fails to reach the main menu twice is dropped. Game Options -> Others -> Auto update turns it off; forks set `pmd/update_url` in project.godot. The main menu shows the running version.
- **tools/release/make_patch.py** builds patch.zip and patch.json from the tracked files and refuses a patch that adds a `class_name` the build doesn't know.
- **Intro fixed:** after the Pelipper scene the intro flashed to white and waited for the intro music to end, but the music looped, so the screen stayed white for up to 3 minutes. Red's songs without a loop (the intro, the title screen and the other one-shot tracks) play once again. The black borders stay black during the boot screens' white flash.
- **Choose freely:** the character and partner list is a compact window with 8 rows that scrolls, with the Pokémon beside it, and asks "Is <name> OK?" before going on. The personality test's partner list asks too.

## v0.8.11 (29 Oct 2026)

- **Dungeons in several parts (second screen and Prepare screen):** the hover and the Prepare screen cover the whole trip: every Pokémon of every part, the level range, the floors and the recommended level.
- **Bosses on the dungeon hover,** marked "Boss Lv X" in red (Explorers of Sky's boss arenas and Red's boss rooms).

## v0.8.10 (29 Oct 2026)

- **Explorers of Sky dungeons in several parts are one trip,** as in Explorers of Sky: the dungeon list shows only the first part, clearing a part goes straight on into the next (HP, Belly, items and status carried over), and the last part (usually the boss) ends the trip. The parts follow EoS's own dungeon table (the parts that share a mappa group): Beach Cave, Mt. Bristle, Steam Cave, Amp Plains, Quicksand Cave, Crystal Crossing, Sealed Ruin, Brine Cave, Hidden Land, Temporal Tower, Mystifying Forest, Crevice Cave, Miracle Sea, Aegis Cave, Spacial Rift, Dark Crater, Concealed Ruins, Bottomless Sea, Shimmer Desert, Mt. Avalanche, Giant Volcano, World Abyss, Sky Stairway, Mystery Jungle, Sky Peak, Star Cave, Fortune Ravine, Barren Valley, Dark Ice Mountain, Vast Ice Mountain, Boulder Quarry, Limestone Cavern and Spring Cave. Each part counts as cleared as it is passed; a chain opens when the team is ready for its longest parts.
- **README** lists Move Growth, Hard mode, the Exp. Share, Auto bank, Autoplay and the second screen.
- **README:** the dungeon count counts a dungeon in several parts once (150, 86 from Explorers of Sky).

## v0.8.9 (29 Oct 2026)

- **Status moves fixed (checked against Red's move code):** Light Screen, Focus Energy and Leech Seed set a status nothing read, so they did nothing. Many status moves only said "Nothing happened"; these now work: Counter and Mirror Coat (an adjacent attacker takes the damage back), Endure, Magic Coat, Mirror Move, Mist, Safeguard, Destiny Bond, Rage, Vital Throw, Encore, Taunt (no status moves), Torment (seals a move), Nightmare, Uproar, Wrap, Ingrain, Lock-On / Mind Reader, Pain Split, Haze, Psych Up, Spite, Heal Bell / Aromatherapy / Refresh, Roar / Whirlwind, Teleport, Knock Off, Trick, Foresight / Odor Sleuth, Helping Hand, Perish Song, Spikes, Substitute, Conversion / Conversion 2 / Camouflage, Mimic / Sketch, Role Play, Skill Swap, Metronome and Sleep Talk. As in Red, Disable paralyzes and Assist fails; Flash lowers accuracy, Grasswhistle puts to sleep, Spider Web slows.
- **Protect / Detect** now block attacks (the status was set but never checked). Baneful Bunker, King's Shield, Spiky Shield, Silk Trap, Obstruct, Burning Bulwark and Laser Focus affect the user (they hit the foe in front); Aurora Veil covers the team. Proper messages ("is protecting itself!" instead of "was affected!").
- **Autoplay:** fetches the item of a find-item job on its floor; explores the floor and fights what it sees, then patrols the rooms for foes until about 400 turns have passed before going down (walking over the stairs no longer takes it down early; the wind still sends it to the stairs); linked moves fire as their whole chain, scored by the chain's power.
- **Linked moves in the Moves menu:** Red's double line over each move that starts a chain, so linked moves read as one group.
- **Healing shows the HP gained in green** over the Pokémon (moves, items, drain, abilities), like Red.

## v0.8.8 (29 Oct 2026)

- **Counter / Mirror Coat and several beam effects** no longer hang for 4 seconds: a flag in one frame's duration was read as 257 frames.
- **Recruiting:** the pause between the join fanfare and the nickname question is about 0.7 s (Red's 2.7 s).
- **Paralysis, Petrified and Shadow Hold** make the Pokémon shake, like Red (x += frame counter & 2).
- **Level ranges ignore boss arenas:** an Explorers of Sky arena floor (and Red's floor-wide boss rooms) never spawns its list, so it no longer counts in the level range, the Pokédex locations, the second-screen spawn list or Hard mode's spread (Labyrinth Cave: Lv 9-12 on Hard, was 9-70).

## v0.8.7 (28 Oct 2026)

- **Exp. Share** (new held item): the Pokémon holding it gains 50% more Exp. from KOs in dungeons. Town Kecleon stocks one on about 1 day in 50 (4000 Poké).
- **Explorers of Sky money:** EoS floors store the Poké cap divided by 5 (FloorProperties max_money_amount_div_5); they used Red's x40 and paid about 8 times too much.
- **Bulletin Board / Job List:** with a second screen the list is a small window in the corner (title, status, rank) so the map stays in view; the job details are on the second screen, which now uses the whole panel above the buttons.
- **Hard mode:** Makuhita Dojo's mazes follow the story level curve (they were treated as post-game, Lv 70+).

## v0.8.6 (28 Oct 2026)

- **Auto bank** (Game Options -> Others, on by default): the money carried goes into the Felicity Bank when a dungeon ends; in town, shops and services (Kecleon, Wigglytuff, Xatu, Croagunk, Gulpin, story NPCs) take the money on hand first, then the bank. Dungeons still need the money carried.
- **Kecleon wares** are no longer picked up by walking onto them: their name and price show in the log; the Ground menu picks one up (unpaid, as before).
- **Item descriptions on the second screen scroll** (drag, right stick, mouse wheel) when they don't fit.

## v0.8.5 (28 Oct 2026)

- **Second screen in town (story mode):** team, rank, location, play time, money, day and job count, with Menu / Job List buttons (only while walking freely).
- **Friend Area hover:** in the Friend Areas lists the second screen shows the Pokémon living there (portrait, name, level).
- **Back to the base's south exit** when the trip or the Prepare screen for an Explorers of Sky dungeon is cancelled (it went to the Friend Areas side).

## v0.8.4 (28 Oct 2026)

- **Menus remember the cursor** (each menu returns to the row used last; Yes/No prompts always start fresh).
- **Long lists scroll** with the cursor.
- **Recruiting:** "Summary" in the join prompts at the end of a dungeon.
- **Abilities:** a Pokémon listed more than once in Remixed's data takes the entry named after it; fixes Greninja / Frogadier (Torrent + Protean), Dialga / Palkia (Pressure + Anticipation), Rotom, Sneasler.

## v0.8.3 (28 Oct 2026)

- **Dungeon info on the second screen:** highlighting a dungeon in a dungeon list shows its wild Pokémon as portraits with names in the Pokédex colours (white = no Friend Area yet, green = Friend Area owned, cyan = recruited; unseen ones are silhouettes named ???), the level range and "No recruiting here" where it applies. Long lists scroll (drag on the second screen, right stick, or the mouse wheel in the PC window).
- **Hold A+B to keep waiting** (Red): after a short pause, turns keep passing while A+B, the Wait key or the on-screen Wait button is held.
- **Reviver Seed:** reviving shows Red's beam of light with its sound (sub_8042148), and a used Reviver Seed turns into a Plain Seed as in Red.
- **Inviting Orb / Rare Quality Orb** now work: defeated Pokémon are twice as likely to join for the rest of the floor.

## v0.8.1 (28 Oct 2026)

- **Recruiting in Explorers of Sky dungeons:** the story, Special Episode and post-game EoS dungeons now allow recruiting (EoS turned it off for story reasons that don't apply here). A boss floor (Pits, Peaks, Chambers, Summits ...) has no recruiting the first time; once its dungeon is cleared, recruiting works there and the boss itself can join (and be shiny-hunted). Lv 1 dungeons (Zero Isle East / West / South, Destiny Tower, Deep Concealed Ruins) still don't allow it; Red's own dungeons keep Red's rules.
- **Prepare screen on Hard:** "Rec. Lv" and "foes X-Y" follow the planned level curve, with a Hard tag.
- **Pokédex "Where it appears":** open Explorers of Sky dungeons are named instead of "???"; dungeons without recruiting are tagged; on Hard the levels follow the planned curve.

## v0.8.0 (28 Oct 2026): Move Growth, Hard mode level curve

- **Move Growth** from Explorers Remixed (SkyTemple's patch, the Gates to Infinity system), option Game Options -> Dungeon -> Move growth (on by default). Damaging moves level 1-25 with Remixed's table (tools/eos/gen_move_growth.py reads BALANCE/mgrowth.bin): up to +30 power, +30 PP and +12 accuracy. Each use gives the move 3 Exp.; a move's level is shared by every team member that knows it; enemies never benefit.
  - Ginseng gives 300 Move Exp. (1000 when lucky) to the leader's topmost growing move while the option is on; Red's Ginseng otherwise.
  - Moves list shows "Lv.X"; the move info page shows the power / accuracy bonus, Exp. to the next level and the PP bonus.
- **Red's Ginseng boost now counts in damage** (it was stored on the move but never added to its power).
- **Hard mode:** wild Pokémon keep arriving up to 20 per floor (was 10), one every 24 turns (was 36). Floors with a Monster House keep Red's cap.
- **Hard mode follows a planned level curve** instead of following the team: every story dungeon has its own wild range (first to last floor) and boss level, ending with Rayquaza at Lv 70 (Mt. Steel 8-11 / Skarmory 14, Sinister Woods 12-18 / Team Meanies 20, Mt. Thunder Peak / Zapdos 32, Mt. Blaze Peak / Moltres 46, Frosty Grotto / Articuno 50, Magma Cavern Pit / Groudon 65 ...). Red's spread between the species of a floor is kept.
  - Side dungeons and EoS dungeons that open during the story: Red's level mapped onto the curve.
  - Post-game dungeons: Lv 70 on the first floor, +1 every 3 floors, up to 100; bosses there at least Lv 75.
  - Backstop: a team 10+ levels above a floor raises its Pokémon by half of the difference past 10.
  - Lv 1 dungeons and Kecleon are unchanged; fixed boss HP grows with the boss's level.

## v0.7.0 (28 Oct 2026): Hard mode

- **Difficulty: Normal / Hard**, chosen when a new adventure starts and changeable any time in Game Options -> Dungeon -> Difficulty. Hard only changes levels; AI, items, hunger, rescues and recruiting stay Red's.
  - Wild Pokémon: when the team's average level is above the floor's usual level, every wild Pokémon rises by the difference (Red's spread between species is kept), plus 3 levels.
  - Bosses (story and EoS): the higher of their own level and the team's average, plus 3. Fixed boss HP (Rayquaza's 600, the EoS arenas) grows with the level. No extra moves.
  - Kecleon and other Lv 90 Pokémon, and Lv 1 dungeons, are not scaled.

## v0.6.44 (28 Oct 2026)

- **Silent Chasm entrance:** the mist layer is blended onto the cliff as on the GBA (BLDALPHA 16/16) instead of covering it in black, and drifts right 1 px every 4 frames (GroundMap action for MAP_SILENT_CHASM_ENTRY). The same blending fixes the Personality Test and Nightmare backdrops.

## v0.6.43 (28 Oct 2026)

- **No more cloned team members:** a team member that also lives in a Friend Area was written to the save twice and became two Pokémon after loading, so the Prepare screen could add it again. Every Pokémon now has an id; loading merges the copies and removes clones made by older builds (shinies and look-alikes with other moves are kept).
- **Kecleon Shop wares are picked up by walking onto them** (still unpaid, price shown in the Toolbox), with Red's messages, instead of "That's for sale."

## v0.6.42 (28 Oct 2026)

- **Job clients leave in Red's beam of light** (effect 318 with sound 850, dungeon_jobs.c sub_8042A34) after a rescue, delivery or escort; the game waits for it before asking to leave.
- **Mega Evolution** (Empowerment Seed) uses a DX-style glow: the Pokémon turns white in a burst of light and sparkles, changes form, and the glow fades.

## v0.6.41 (28 Oct 2026)

- Leaving a dungeon from the "mission completed, leave now?" prompt counts as leaving (Red's STARTMODE 10): no boss arena or "dungeon cleared" scripts.

## v0.6.34 - v0.6.40 (27-28 Oct 2026)

- **Partner AI:** partners no longer refuse swaps, ping-pong in corridors or take detours; better following with 3+ members.
- **Throwables** are given to a partner as a whole stack; exclusive items show their star rating; the item under the cursor is described on the second screen.
- **Croagunk's Swap Shop** (from Explorers Remixed): in front of the base next to Kecleon, Remixed's recipes, daily stock (tools/data/gen_swap_shop.py).
- **EoS jobs** get the job envelope marker in the dungeon list; **cleared marks** option (stars in dungeon lists, gold world-map markers, DX).
- **Boss floors:** Sinister Woods / Mt. Steel and other dungeons with a boss after the last normal floor go on to the boss instead of ending.
- **Options:** Auto save on/off, right-stick zoom in dungeons and on story maps, Debug NPC (Porygon at the base: flags, jump to a chapter, side stories).
- **Story fixes:** forming the team no longer jumps the story to the post-game (wrong base upgrade, Zero Isle / Destiny Tower showing up early); EoS unlocks use team levels only and post-game dungeons wait for the post-game; Friend Areas open again from the map; the base matches the hero's species.

## v0.6.33 (27 Oct 2026)

- **Leader statuses:** as in Red (sub_80701A4), the leader's turn passes by itself while asleep, frozen, wrapped, petrified, unable to move, infatuated or biding, with Red's message ("... is asleep!"). Before, you could still act.
- **Kecleon Shop floor** drawn with Red's shop carpet tile; attacks and moves ignore the shopkeeper (Red's TREATMENT_IGNORE) and A while facing Kecleon talks to it. After a theft Kecleon can be fought.
- **Partners:** a sleeping foe next to a partner is no longer picked as its target (it used to stand there without attacking); a partner idle away from the leader for 3 turns drops its target and follows, and after 6 Red's AI takes over for a turn.

## v0.6.32 (27 Oct 2026): Kecleon Shops

**Kecleon Shops in dungeons** (Red's dungeon_kecleon_shop.c, with Red's own lines)
- The shop rooms the floor generator makes now have their Kecleon (Lv. 90) standing in the middle. Wares are half from Red's Kecleon lists and half Explorers of Sky items (stronger ones on deeper floors).
- Pick wares up (they stay unpaid, shown in green with their price in the Toolbox); leave your own items on the shop floor to sell them.
- Stepping in: "Ah, welcome~♪" and the shop theme. Stepping out while owing: Kecleon comes over, offers for what you left, then asks you to pay. Talking to Kecleon does the same.
- Saying no, not having the money, or leaving while no Kecleon can stop you makes you a thief: "Help! Thief! I've been robbed!", the Stop Thief! theme, Kecleon turn hostile and more Kecleon (Lv. 90) arrive every 5 turns.

**Also**
- Wonder Tiles are always visible and stay after use, reset multiplier effects too, aren't stopped by a Trap Scarf, and use Red's lines ("...'s stats returned to normal." / "...appear unchanged.").
- Partners no longer give up on routes longer than 8 steps, and walk around a teammate who is fighting in the way instead of waiting behind it.

## v0.6.31 (27 Oct 2026)

- **Partners don't freeze at room entrances:** when the way to the leader is blocked by a known trap or an untriggered Monster House room, partners go through it; with no way at all they use Red's following for that turn instead of standing still.
- **Kangaskhan Storage order:** Explorers of Sky items now sort in proper order with Red's (as the Toolbox Sort).
- **Sort while selling or storing:** in Kecleon's sell list and Kangaskhan's store list, Select (or the Sort button) sorts the bag; L / R still mark several items.

## v0.6.30 (27 Oct 2026)

- **Saving on a boss floor:** a Quicksave or autosave made on a boss / fixed floor now saves the team as it arrived there. Loading it builds the floor again and plays the boss scene again, instead of resuming in the middle of it.
- **Red's moving animations:** take-offs, landings, jumps and fly-ins in story scenes now move the sprite as in Red (offsets and timing read from the decompilation; new build step `anim_offsets`). Skarmory now flies off the screen after the Mt. Steel fight instead of vanishing mid-scene.
- **Fainting:** Pokémon without a faint animation hold their hurt pose and, if they float (Skarmory, Zubat ...), come down to their shadow before fading; those with one play it to the end.
- **Explorers of Sky jobs:** cleared Explorers of Sky dungeons now get jobs on the board, with difficulty from each floor's Pokémon levels, no jobs on boss arena floors and rewards from the dungeon's own items.
- **Message size** (Game Options): Small / Normal / Large for the dungeon message box and the message log.
- **Portraits on wide screens:** story portraits keep their side of the screen (right-side ones keep their distance from the right edge, centre ones stay centred) instead of drifting toward the middle.
- **Item sprites** in Kecleon's shop, Kangaskhan Storage, the treasure-box list, the reward screen and the job board's reward line.

## v0.6.29 (27 Oct 2026)

- Recruiting doesn't start until Wigglytuff gives the team its first Friend Areas (Wild Plains and Mist-Rise Forest).
- DX recruiting also needs the Pokémon's own Friend Area, as in Red; the rest stays DX (2-tile range, temporary members up to 8, the choice when you leave).

## v0.6.28 (27 Oct 2026): DX recruiting, smarter partners

**Recruiting**
- New Game Options setting **Recruiting: DX / Red** (DX by default), from *Rescue Team DX*:
  - The leader can recruit with the final hit from up to 2 tiles away; the recruit rate is Red's.
  - A defeated Pokémon joins for this dungeon only, up to 8 team members, and doesn't need its Friend Area yet. Like in DX, temporary members use no PP, gain no Exp., hold no items and don't take tactics.
  - Leaving the dungeon, each temporary member whose Friend Area you have asks to join for good (nickname then). The others, and any you turn down, go home and leave some Poké, more the longer they stayed. If the team faints they're all lost.
- Recruiting follows Red's story gates: Skarmory, Gengar's gang, the legendary birds, the Regis, Mankey and others can only join after their story event. Latios and Latias never join from a dungeon; they join through the story, and Latios now brings his Friend Area. Mew doesn't join while you're on a friend rescue.
- Red's base visitor event: a Pokémon sometimes visits the team base and asks to join.

**Smarter "Let's go together!"**
- New Game Options setting **Partner AI: Smarter / Red** (Smarter by default). It only changes partners on "Let's go together!"; other tactics and wild Pokémon keep Red's AI.
- Partners attack foes within 3 tiles of you or them, staying within 4 tiles of you. They protect the leader first, then help with the foe you're fighting, then go for the weakest, and leave sleeping foes alone.
- Moves are picked by estimated damage: no moves the foe is immune to, no status move on a foe that already has it, the normal attack to finish weak foes (saves PP). Line and 2-tile moves are lined up from range.
- Real pathfinding around walls and teammates, following the leader out of sight, swapping places in corridors, walking around known traps. A partner below 1/4 HP stays back, and a foe the leader could recruit is left for the leader's last hit.

**Controls and screens**
- Controller: **L + A / B / X / Y** use moves 1-4 (a linked move fires its chain). Holding **L** shows which button uses which move, with PP. The message log moved to **L + Select**.
- A tap of **R** turns toward the nearest enemy without switching on the grid (Start still does).
- The HP bar's length follows the leader's max HP, like Red's, reaching the full width at 200 max HP.
- The set-move, partner-move and set / sticky item marks are the game's own icons from the ROM font.
- Items show their sprite in the dungeon bag, the Toolbox and the give-item list.

## v0.6.27 (27 Oct 2026): playable without a controller

Every screen and menu was checked for actions that needed a controller.
- **Tap outside a menu to close it** (Red's B), for the menus that didn't have this yet: Bulletin Board, Pokédex filters, shop and bank choices and many story choices. The finger that opened a menu doesn't close it on release; menus that can't be cancelled in Red still can't.
- **Wonder Mail maker:** Back button on the Pokémon / dungeon / item lists and a Done button on the finished-code page.
- **Number picker** (bank amounts and similar): a tap outside cancels.
- **Moves screen:** ▲ / ▼ buttons in the title bar move the selected move up or down (was Shift + Up/Down only).
- **Run by touch:** push the joystick past its ring (it turns gold) to run: Red's run in dungeons, faster walking in town and on story maps.
- **Turn in place by touch:** in dungeons, tap your own Pokémon to face the nearest enemy (again to cycle, or one step around with none near). On an item, stairs or a known trap the tap opens that tile's menu as before.
- **Windows:** new export option "Windows (exe + pck)": a small `PMDRed.exe` plus the game data in `PMDRed.pck` next to it (the single-file .exe is still there).

## v0.6.26 (27 Oct 2026): touch controls

- **Mark several items by touch:** in Kecleon's sell list and Kangaskhan's store / take lists, hold an item to mark it (Red's highlight bar). While anything is marked, a tap marks or unmarks more; **Done (N)** sells or stores them all and **Mark all** marks every item. Kangaskhan's "Mark" command now stays in marking mode.
- **Bag scrolling and sorting:** lists can be swiped (up/down scrolls, left/right turns the page), with scroll arrows in the title bar when items are hidden. A Toolbox page holds 10 items but shows 8, and the last two used to be reachable only with arrow keys. New **Sort** button (Red's item order) in dungeons and town.
- Menus act when the finger lifts, so a swipe never opens an item by accident.
- **Joystick on story maps:** Pokémon Square, the team base and the other story maps show the on-screen pad, A and Menu buttons, like dungeons. Hidden on the boot, title and quiz screens.
- **Back buttons:** the job board and the Pokédex list can be closed by touch. The Friend Area map works by touch: tap an area to walk toward it, tap the one you're on to choose it, Back to leave.

## v0.6.25 (27 Oct 2026)

- **Team base:** fixed the base showing another style's house or the wrong version of the room. Red keeps 6 maps per base style (3 outside, 3 inside); the engine counted 3.
- **Pokédex colours like Red:** white = you don't have its Friend Area yet, green = you have the Friend Area, cyan = recruited.
- Red's music loops from its loop point (tracks built by the new music renderer).
- Repository: one-command build (`build_all.py`) that makes all assets and data from your own ROMs and public resources; CREDITS.md and CREDITS_SPRITES.md.

## v0.6.24 (26 Oct 2026)

- **No more random pauses between steps:** Pokémon that only wait (asleep, idle, far away) no longer make the leader stop after each step, and fights off screen resolve without animation waits. Fights on screen still play out as in Red.

## v0.6.23 (26 Oct 2026)

- **Partners put what they pick up in the Toolbox** (Poké goes to your money); they only hold an item when the Toolbox is full, as in Red.

## v0.6.22 (26 Oct 2026)

- **Boss fights fixed:** bosses in fixed rooms can move and attack again (the unbreakable floor of boss rooms was treated as a wall), boss music plays, Team Meanies walk in and stand where they do in Red, and story bosses never start asleep. All Red story bosses and the 40 Explorers of Sky boss arenas checked.
- **Smoother on the AYN Thor:** the second screen is only redrawn when something on it changes, instead of being copied from the GPU 30 times a second.
- Wild Pokémon no longer stand on Poké forever trying to pick it up.

## v0.6.21 (26 Oct 2026): shiny hunting

- Bosses and story legendaries can be shiny: 1 in 50, 1 in 20 after the story.
- After the story a legendary keeps coming back until you have its shiny; only the shiny can join a second time.
- Newer legendaries met as wild Pokémon can be shiny.

## v0.6.20 (26 Oct 2026): items, abilities, Megas, shinies

**Items**
- Every Red item, orb, seed and food does what it does in Red (values from the decompilation).
- Held items such as Persim Band, Pecha Scarf, Insomniscope, Twist Band, Joy Ribbon, Sneak Scarf, Racket Band, Warp Scarf, Trap Scarf, X-Ray / Goggle Specs and the Pierce / Long Toss items.
- Orb moves (Escape, Trawl, Cleanse, One-Room, Fill-In, Pounce, Itemize, Hurl, the weather orbs and more).
- 1,051 *Explorers of Sky* / *Explorers Remixed* items: held items, seeds, orbs, TMs (taught from the base menu) and 909 exclusive items that boost the Pokémon or type they belong to.
- Exclusive items drop by floor level, rarer the more stars; recruit treasures (Golden Mask, Amber Tear, the seven instruments) help recruiting when the leader holds them.
- Gold Thorn, Rare Fossil and Golden Apple as rare deep-floor drops.
- Level-reset dungeons send your items to Storage with a message.

**Abilities**
- All of Red's abilities work, inside and outside the damage formula.
- *Explorers of Sky* abilities and *Explorers Remixed*'s custom abilities; 377 Pokémon outside Red got their Remixed abilities.
- Mega abilities: Tough Claws, Parental Bond, Strong Jaw, Mega Launcher, Sand Force, Fairy Aura, Berserk, Regenerator, Lightning Rod, Primordial Sea, Desolate Land, Delta Stream.

**Dungeons**
- *Explorers of Sky* dungeons use *Explorers Remixed*'s spawn and item lists (157 dungeons, including Deep Concealed Ruins).
- Pokémon that appeared nowhere were spread into dungeons that fit them (354 placements).

**Treasure boxes**
- 12 box types drop on floors of level 15 and up; the green Kecleon opens them for 150 Poké (usually an exclusive item for your team, sometimes a rare item).

**Mega Evolution (Empowerment Seed, from *Rescue Team DX*)**
- Awakened until the next floor: stats ×1.5, linked moves always crit, no type disadvantages.
- Mega-capable Pokémon take their Mega form, Kyogre and Groudon their Primal form; they change back on the next floor.
- 21 Megas added (Venusaur, Blastoise, Gyarados, Mewtwo X, Salamence, Metagross, the Primals and more), each with its real ability.
- Seeds drop after the story and in treasure boxes; partners get a prompt next to strong foes.

**Shinies**
- 1 in 200 wild Pokémon is shiny (961 Pokémon have SpriteCollab shiny colours), with a sparkle when it comes into view.
- Recruited shinies stay shiny in dungeons, towns and Friend Areas, with shiny portraits; shiny Megas use the shiny Mega colours.

**Status**
- Status durations follow Red's tables everywhere (traps, items, orbs, abilities).
- Water heals a burn; lava thaws and burns Pokémon that don't live in lava; the leader loses Belly moving inside walls.
- New option "Burn/poison wear off" (on by default): burn, poison and bad poison end after 5–7 turns.

**Shops**
- Multi-select in Kecleon's shop and Storage uses Red's highlight bar; the TM & Orb Kecleon is purple, as in Red.

## v0.6.19 (26 Oct 2026)

- Autoplay and partners throw throwable items (Item Master, held throwables).
- Partner item prompts: low HP offers an Oran / Sitrus Berry, a status offers the matching cure, fainting offers a Reviver Seed.
- Reviver Seed and Heal Seed effects fixed.

## v0.6.18 (26 Oct 2026)

- Tapping through text no longer skips script events or freezes cutscenes (the Pelipper mail scene).
- Double taps in the same frame are ignored in dialogue; the cutscene safety net only steps in when every script is really stuck.

## v0.6.17 (26 Oct 2026)

- Game Options work by touch: tap the left or right half of a value to change it.

## v0.6.16 (26 Oct 2026)

- The naming screen works by touch: letters, OK and Back.

## v0.6.10 – v0.6.15 (25–26 Oct 2026)

- Fixes to the ground script runner, the floor generator, rescue jobs, story progress and move data.

## v0.6.1 – v0.6.9 (25 Oct 2026)

- Menu-size slider, quicksave and town fixes (v0.6.1); story, ground, dialogue and theme fixes (v0.6.2); dungeon terrain rendering (v0.6.3); a story autopilot for testing and autoplay (v0.6.4); Friend Area and fixed-room data corrected (v0.6.7, v0.6.9).

## v0.6 (25 Oct 2026): Red's presentation

- Boot sequence and title screen, main menu, naming screen, Adventure Log, save messages, Trade Items, Wonder Mail entry.
- Dungeon presentation: status icons, results screen, floor banner, Red's dungeon map, weather and darkness, water and lava animation, boss arena tilesets.
- Ornaments, Luminous Cave and evolution, Makuhita Dojo, ending credits.
- Red's base menu, Game Options, shops and their text, Pokémon News, Post Office, Friend Rescue, dungeon list.
- Red's world map and Friend Area map, plus an *Explorers of Sky* world map.

## v0.5 – v0.5.2 (25 Oct 2026)

- Ground maps, music, every Pokémon's sprite sheets and portraits, move effects, tilesets and credits brought in; new audio, HUD and move-effect code.
- Dungeon view modes (grid / highlight) and Red's trap graphics.

## v0.4 (25 Oct 2026)

- Red's story ground scripts run in the engine.
- *Explorers of Sky* music (196 tracks) and move animations; every SpriteCollab animation for every Pokémon.

## v0.3 (24 Oct 2026)

- Red's 140 fixed rooms and the story boss fights with their original dialogue (Skarmory, Team Meanies, Zapdos, Moltres, Articuno, Groudon, Rayquaza and the post-game legendaries).
- Separate build for the AYN Thor.

## v0.2.1 (24 Oct 2026): first Android build

- Red's ground map backgrounds.
- Earlier internal builds ported the core from the pret/pmd-red decompilation: floor generator, combat, dungeon AI and turn rules, personality quiz, rescue jobs (Pelipper board, Job List), Wonder Mail (byte-compatible codes and a code maker), Red's dungeon menus, IQ skills, tactics and Gulpin's Link Shop; plus *Explorers of Sky* IQ skills, quality-of-life options and AYN Thor dual-screen support.
