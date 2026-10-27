# Changelog

Patch notes for every version of the engine, newest first. Version numbers match the Android builds.
Everything listed here is code; the game's graphics, music and data are built from your own ROMs (see [SETUP.md](SETUP.md)).

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
