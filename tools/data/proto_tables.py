"""Design tables of the old HTML prototype of this remake (choices the project made, not data from any ROM).
proto.py combines them with PokeAPI and the pmd-red decomp to rebuild the prototype's tables.
Generated residuals (overrides) are the prototype's hand-made exceptions to the general rules in proto.py."""

# Abilities the prototype implements (PokeAPI identifiers)
ABILITIES = ["hyper-cutter", "competitive", "pixilate", "lightning-rod", "rain-dish", "poison-point", "snow-cloak", "full-metal-body", "earth-eater", "effect-spore", "no-guard", "hustle", "magic-guard", "multiscale", "sand-stream", "serene-grace", "overcoat", "iron-barbs", "volt-absorb", "sweet-veil", "drizzle", "tinted-lens", "skill-link", "sniper", "sand-veil", "static", "magma-armor", "sap-sipper", "shield-dust", "white-smoke", "oblivious", "own-tempo", "ice-body", "dry-skin", "reckless", "pure-power", "super-luck", "limber", "early-bird", "cute-charm", "simple", "comatose", "solid-rock", "shed-skin", "heatproof", "water-absorb", "strong-jaw", "clear-body", "water-bubble", "intimidate", "refrigerate", "vital-spirit", "pressure", "defiant", "insomnia", "guts", "poison-heal", "battle-armor", "water-veil", "rock-head", "blaze", "flame-body", "snow-warning", "overgrow", "scrappy", "keen-eye", "sheer-force", "storm-drain", "rough-skin", "immunity", "tough-claws", "swarm", "ice-scales", "wonder-guard", "shell-armor", "huge-power", "motor-drive", "compound-eyes", "flash-fire", "sturdy", "big-pecks", "iron-fist", "shadow-shield", "normalize", "poison-touch", "prism-armor", "contrary", "adaptability", "torrent", "moxie", "drought", "levitate", "filter", "thick-fat", "technician", "fur-coat", "hydration", "mega-launcher", "marvel-scale"]

# Main-series games' learnsets, newest first (PokeAPI version_group ids): Scarlet/Violet, Sword/Shield,
# Brilliant Diamond/Shining Pearl, Ultra Sun/Moon, Sun/Moon, ORAS, X/Y, B2W2, BW, HGSS, Pt, DP, FRLG, E, RS, GS, RB; Legends Arceus last
VG_PRIORITY = [25, 20, 23, 18, 17, 16, 15, 14, 11, 10, 9, 8, 7, 6, 5, 3, 1, 24]

# SpriteCollab sprites added after the prototype was made (left out so the species list stays the same)
LATER_SPRITES = {"0837"}
EXTRA_SPECIES = set()

# Hand-made move descriptors of the prototype that differ from the PokeAPI-derived ones (None = field removed)
MOVE_OVERRIDE = {
    'Armor Cannon': {"eff": [{"tgt": "def", "st": -1}, {"tgt": "spd", "st": -1}]},
    'Aurora Veil': {"eff": [{"status": "reflect"}, {"status": "lightscreen"}]},
    'Baneful Bunker': {"eff": {"status": "protect"}},
    'Belly Drum': {"eff": {"self": "atk", "st": 12}},
    'Block': {"eff": {"status": "slow"}},
    'Burning Bulwark': {"eff": {"status": "protect"}},
    'Curse': {"eff": [{"self": "atk", "st": 1}, {"self": "def", "st": 1}], "r": "self"},
    'Detect': {"eff": {"status": "protect"}},
    'Electro Shot': {"eff": {"tgt": "spa", "st": 1}},
    'Endure': {"eff": {"status": "protect"}},
    'Fillet Away': {"eff": [{"self": "atk", "st": 2}, {"self": "spa", "st": 2}, {"fast": 8}]},
    'Floral Healing': {"r": "self"},
    'Focus Energy': {"eff": {"status": "focus"}},
    'Haze': {"r": "room"},
    'Heal Pulse': {"r": "self"},
    'King’s Shield': {"eff": {"status": "protect"}},
    'Laser Focus': {"eff": {"status": "focus"}},
    'Light Screen': {"eff": {"status": "lightscreen"}},
    'Make It Rain': {"eff": {"tgt": "spa", "st": -1}},
    'Mean Look': {"eff": {"status": "slow"}},
    'Obstruct': {"eff": {"status": "protect"}},
    'Protect': {"eff": {"status": "protect"}},
    'Purify': {"r": "self"},
    'Reflect': {"eff": {"status": "reflect"}},
    'Rest': {"heal": 1, "eff": {"status": "sleep"}},
    'Ruination': {"fixed": "half"},
    'Silk Trap': {"eff": {"status": "protect"}},
    'Snowscape': {"weather": "hail"},
    'Spicy Extract': {"eff": [{"tgt": "atk", "st": 2}, {"tgt": "def", "st": -2}]},
    'Spiky Shield': {"eff": {"status": "protect"}},
    'Spin Out': {"eff": {"status": "slow"}},
    'Sticky Web': {"eff": {"status": "slow"}},
    'Tailwind': {"eff": {"fast": 8}},
    'Tidy Up': {"eff": [{"self": "atk", "st": 1}, {"fast": 8}]},
    'Torch Song': {"eff": {"tgt": "spa", "st": 1}},
    'Wish': {"heal": 0.5},
    'Yawn': {"eff": {"status": "sleep"}},
}

# Substitute for an ability the prototype does not implement (used when none of the species' abilities is implemented)
ABILITY_SUB = {
    'air-lock': 'clear-body', 'aura-break': 'rough-skin', 'bad-dreams': 'defiant', 'ball-fetch': 'static',
    'battery': 'swarm', 'beads-of-ruin': 'intimidate', 'beast-boost': 'moxie', 'cheek-pouch': 'scrappy',
    'chilling-neigh': 'moxie', 'chlorophyll': 'overgrow', 'color-change': 'adaptability', 'cursed-body': 'rough-skin',
    'dancer': 'blaze', 'dark-aura': 'defiant', 'dauntless-shield': 'sturdy', 'defeatist': 'sturdy',
    'disguise': 'multiscale', 'download': 'technician', 'dragons-maw': 'adaptability', 'electric-surge': 'static',
    'emergency-exit': 'swarm', 'fairy-aura': 'cute-charm', 'flower-gift': 'overgrow', 'flower-veil': 'clear-body',
    'forecast': 'scrappy', 'good-as-gold': 'magic-guard', 'grassy-surge': 'overgrow', 'grim-neigh': 'moxie',
    'gulp-missile': 'keen-eye', 'healer': 'cute-charm', 'hunger-switch': 'static', 'ice-face': 'multiscale',
    'illusion': 'defiant', 'innards-out': 'rough-skin', 'inner-focus': 'own-tempo', 'intrepid-sword': 'moxie',
    'justified': 'defiant', 'leaf-guard': 'overgrow', 'magician': 'magic-guard', 'magnet-pull': 'pressure',
    'misty-surge': 'torrent', 'mold-breaker': 'scrappy', 'multitype': 'scrappy', 'mummy': 'rough-skin',
    'mycelium-might': 'effect-spore', 'natural-cure': 'magic-guard', 'orichalcum-pulse': 'drought', 'pickup': 'levitate',
    'poison-puppeteer': 'poison-touch', 'power-spot': 'sturdy', 'prankster': 'serene-grace', 'protosynthesis': 'adaptability',
    'psychic-surge': 'magic-guard', 'quark-drive': 'adaptability', 'rks-system': 'scrappy', 'sand-rush': 'sand-veil',
    'schooling': 'torrent', 'seed-sower': 'overgrow', 'shadow-tag': 'pressure', 'shields-down': 'sturdy',
    'slow-start': 'scrappy', 'soul-heart': 'moxie', 'soundproof': 'filter', 'speed-boost': 'moxie',
    'stance-change': 'clear-body', 'steelworker': 'adaptability', 'swift-swim': 'hydration', 'synchronize': 'magic-guard',
    'tera-shift': 'multiscale', 'teravolt': 'scrappy', 'toxic-chain': 'poison-touch', 'toxic-debris': 'poison-point',
    'transistor': 'adaptability', 'truant': 'scrappy', 'turboblaze': 'scrappy', 'unaware': 'thick-fat',
    'unnerve': 'intimidate', 'unseen-fist': 'scrappy', 'vessel-of-ruin': 'intimidate', 'victory-star': 'magic-guard',
    'wandering-spirit': 'rough-skin', 'weak-armor': 'defiant', 'well-baked-body': 'flash-fire', 'wimp-out': 'swarm',
    'wind-rider': 'keen-eye', 'zero-to-hero': 'moxie',
}

# Species whose prototype abilities differ from the rule above
ABILITY_OVERRIDE = {
    '0054': ['water-absorb', 'clear-body'], '0055': ['water-absorb', 'clear-body'], '0120': ['torrent'], '0121': ['torrent'],
    '0137': ['adaptability', 'technician'], '0216': ['guts'], '0233': ['adaptability', 'technician'], '0261': ['guts'],
    '0263': ['scrappy'], '0264': ['scrappy'], '0280': ['magic-guard', 'adaptability'], '0281': ['magic-guard', 'adaptability'],
    '0282': ['magic-guard', 'adaptability'], '0316': ['rough-skin', 'sturdy'], '0317': ['rough-skin', 'sturdy'], '0333': ['scrappy'],
    '0334': ['rough-skin'], '0357': ['overgrow', 'blaze'], '0425': ['rough-skin'], '0426': ['rough-skin'],
    '0475': ['own-tempo', 'tough-claws'], '0492': ['overgrow'], '0517': ['keen-eye', 'magic-guard'], '0518': ['keen-eye', 'magic-guard'],
    '0531': ['scrappy'], '0568': ['poison-point', 'sturdy'], '0569': ['poison-point', 'defiant'], '0702': ['static'],
    '0708': ['keen-eye'], '0709': ['keen-eye'], '0714': ['keen-eye'], '0715': ['keen-eye'],
    '0760': ['fur-coat'], '0827': ['defiant'], '0828': ['defiant'], '0831': ['fur-coat'],
    '0832': ['fur-coat', 'own-tempo'], '0840': ['overgrow'], '0856': ['keen-eye'], '0857': ['keen-eye'],
    '0858': ['keen-eye'], '0859': ['serene-grace', 'keen-eye'], '0860': ['serene-grace', 'keen-eye'], '0861': ['serene-grace', 'keen-eye'],
    '0884': ['sturdy'], '0955': ['keen-eye'], '1011': ['intimidate'], '1019': ['intimidate'],
}

# Smeargle learns Sketch every 10 levels (the prototype kept every Sketch)
LEARN_OVERRIDE = {"0235": [[lv, "Sketch"] for lv in range(1, 100, 10)]}

# The prototype's first hand-written moves (they come first in its move table; the rest follow in PokeAPI order)
MOVE_ORDER_HEAD = ['Tackle', 'Scratch', 'Quick Attack', 'Metal Claw', 'Ember', 'Flame Wheel', 'Water Gun', 'Vine Whip', 'Razor Leaf',
                   'Gust', 'Poison Sting', 'Mud-Slap', 'Growl', 'Tail Whip', 'Leer', 'Smokescreen', 'String Shot', 'Defense Curl',
                   'Withdraw', 'Thunder Wave', 'Poison Powder', 'Bug Bite', 'Absorb', 'Mega Drain', 'Acid', 'Stun Spore', 'Sleep Powder',
                   'Headbutt', 'Harden', 'Swords Dance', 'Brick Break', 'Supersonic', 'Spark', 'Screech', 'Shock Wave', 'Bite',
                   'Thunder Punch', 'Low Kick', 'Thunderbolt', 'Rock Throw', 'Rock Slide', 'Peck', 'Drill Peck', 'Cross Chop',
                   'Aerial Ace', 'Iron Tail', 'Steel Wing', 'Powder Snow', 'Icy Wind', 'Earthquake', 'Crunch', 'Ice Beam', 'Aurora Beam',
                   'Body Slam', 'Surf', 'Flamethrower', 'Confuse Ray', 'Will-O-Wisp', 'Wing Attack', 'Sludge', 'Water Pulse',
                   'Hydro Pump', 'Scary Face', 'Lick', 'Hypnosis', 'Night Shade', 'Shadow Ball', 'Confusion', 'Psybeam', 'Psychic',
                   'Astonish']

# The prototype's first hand-written species (starters, town residents, its first dungeons' Pokemon); '0352p' is the purple Kecleon (a copy of Kecleon)
SPECIES_ORDER_HEAD = ['0001', '0004', '0007', '0025', '0155', '0258', '0010', '0016', '0019', '0161', '0265', '0352', '0115', '0279',
                      '0352p', '0340', '0316', '0040', '0296', '0053', '0013', '0043', '0285', '0127', '0081', '0100', '0309', '0239',
                      '0074', '0179', '0145', '0066', '0056', '0021', '0304', '0095', '0227', '0220', '0361', '0215', '0363', '0225',
                      '0087', '0144', '0218', '0322', '0324', '0037', '0058', '0077', '0146', '0072', '0090', '0116', '0278', '0183',
                      '0341', '0130', '0092', '0063', '0177', '0200', '0302', '0355', '0094', '0123', '0015', '0286', '0243', '0310',
                      '0181', '0208', '0306', '0068', '0362', '0365', '0131', '0244', '0059', '0323', '0230', '0073', '0319', '0065',
                      '0356', '0178', '0002', '0003', '0005', '0006', '0008', '0009', '0011', '0012', '0014', '0017', '0018', '0020',
                      '0022', '0023', '0024', '0026', '0027', '0028', '0029', '0030']

# Mega Evolutions the prototype had (key, PokeAPI pokemon identifier); more are added later by gen_megas_dx.py (stage 2)
MEGAS = [('0006MX', 'charizard-mega-x'), ('0065M', 'alakazam-mega'), ('0094M', 'gengar-mega'), ('0115M', 'kangaskhan-mega'),
         ('0142M', 'aerodactyl-mega'), ('0150MY', 'mewtwo-mega-y'), ('0208M', 'steelix-mega'), ('0227M', 'skarmory-mega'),
         ('0229M', 'houndoom-mega'), ('0248M', 'tyranitar-mega'), ('0282M', 'gardevoir-mega'), ('0302M', 'sableye-mega'),
         ('0303M', 'mawile-mega'), ('0308M', 'medicham-mega'), ('0310M', 'manectric-mega'), ('0323M', 'camerupt-mega'),
         ('0334M', 'altaria-mega'), ('0354M', 'banette-mega'), ('0359M', 'absol-mega'), ('0362M', 'glalie-mega'),
         ('0380M', 'latias-mega'), ('0381M', 'latios-mega'), ('0384M', 'rayquaza-mega'), ('0428M', 'lopunny-mega'),
         ('0448M', 'lucario-mega'), ('0475M', 'gallade-mega'), ('0491M', 'darkrai-mega'), ('0530M', 'excadrill-mega'),
         ('0604M', 'eelektross-mega'), ('0670M', 'floette-mega'), ('0691M', 'dragalge-mega'), ('0718M', 'zygarde-mega'),
         ('0719M', 'diancie-mega'), ('0780M', 'drampa-mega'), ('0807M', 'zeraora-mega'), ('0978M', 'tatsugiri-curly-mega')]

# Item icons of the prototype's own items (not in Red), drawn with Red's item sprites (data/dungeon/itempat.inc):
# (sprite, Red palette)
ICON_ROM = {
    'tinyapple': (3, 3), 'perfectapple': (3, 3), 'tinyreviver': (14, 4), 'decoyseed': (14, 4), 'banseed': (14, 4),
    'energyseed': (14, 4), 'pureseed': (14, 4), 'trainingseed': (14, 4), 'violentseed': (14, 4), 'empowerseed': (14, 4),
    'maxether': (12, 8), 'carbos': (12, 8), 'powerdrink': (12, 8), 'ppupdrink': (12, 8), 'accuracydrink': (12, 8),
    'rainbowgummi': (17, 2), 'dxgummi': (17, 3), 'alldodgeorb': (15, 0), 'allpowerorb': (15, 0), 'allprotectorb': (15, 0),
    'bankorb': (15, 0), 'foeholdorb': (15, 0), 'foesealorb': (15, 0), 'weatherlockorb': (15, 0), 'healthorb': (15, 0),
    'helperorb': (15, 0), 'invitingorb': (15, 0), 'rarequalityorb': (15, 0), 'lassoorb': (15, 0), 'monsterorb': (15, 0),
    'nullifyorb': (15, 0), 'resetorb': (15, 0), 'reviveallorb': (15, 0), 'spurnorb': (15, 0), 'storageorb': (15, 0),
    'wigglytufforb': (15, 0), 'goldenfossil': (5, 1), 'ironspike': (0, 2), 'goldenspike': (0, 3), 'bigeaterbelt': (4, 4),
    'coverband': (4, 4), 'defensescarf': (4, 4), 'efficientbandanna': (4, 4), 'explosiveband': (4, 4), 'ficklespecs': (13, 9),
    'fiercebandanna': (4, 10), 'heavyrotationspecs': (13, 9), 'luckyribbon': (4, 4), 'machribbon': (4, 3), 'nullifybandanna': (4, 4),
    'phaseribbon': (4, 0), 'prosperribbon': (4, 4), 'recoveryscarf': (4, 4), 'reunioncape': (4, 4), 'bronzeticket': (16, 5),
    'silverticket': (16, 5), 'goldticket': (16, 5), 'prettybox': (10, 0), 'deluxebox': (10, 0), 'deluxeribbon': (4, 4),
    'evolutioncrystal': (1, 3), 'invitation': (16, 5),
}
# (sprite, {colour index: colour}) - Red sprites recoloured by the prototype
ICON_RECOLOUR = {
    'tmfocuspunch': (8, {1: '#000000', 4: '#843d34', 7: '#f07060', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#c0594c', 14: '#f6b0a7', 15: '#ffffff'}),
    'tmdragonclaw': (8, {1: '#000000', 4: '#463d84', 7: '#8070f0', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#6659c0', 14: '#b9b0f6', 15: '#ffffff'}),
    'tmwaterpulse': (8, {1: '#000000', 4: '#425c8c', 7: '#78a8ff', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#6086cc', 14: '#b4cfff', 15: '#ffffff'}),
    'tmcalmmind': (8, {1: '#000000', 4: '#8c4660', 7: '#ff80b0', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#cc668c', 14: '#ffb9d3', 15: '#ffffff'}),
    'tmroar': (8, {1: '#000000', 4: '#6e6e5c', 7: '#c8c8a8', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#a0a086', 14: '#e0e0cf', 15: '#ffffff'}),
    'tmtoxic': (8, {1: '#000000', 4: '#724672', 7: '#d080d0', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#a666a6', 14: '#e5b9e5', 15: '#ffffff'}),
    'tmbulkup': (8, {1: '#000000', 4: '#843d34', 7: '#f07060', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#c0594c', 14: '#f6b0a7', 15: '#ffffff'}),
    'tmbulletseed': (8, {1: '#000000', 4: '#4a7b3d', 7: '#88e070', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#6cb359', 14: '#bdedb0', 15: '#ffffff'}),
    'tmhiddenpower': (8, {1: '#000000', 4: '#6e6e5c', 7: '#c8c8a8', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#a0a086', 14: '#e0e0cf', 15: '#ffffff'}),
    'tmicebeam': (8, {1: '#000000', 4: '#588484', 7: '#a0f0f0', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#80c0c0', 14: '#caf6f6', 15: '#ffffff'}),
    'tmblizzard': (8, {1: '#000000', 4: '#588484', 7: '#a0f0f0', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#80c0c0', 14: '#caf6f6', 15: '#ffffff'}),
    'tmhyperbeam': (8, {1: '#000000', 4: '#6e6e5c', 7: '#c8c8a8', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#a0a086', 14: '#e0e0cf', 15: '#ffffff'}),
    'tmlightscreen': (8, {1: '#000000', 4: '#8c4660', 7: '#ff80b0', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#cc668c', 14: '#ffb9d3', 15: '#ffffff'}),
    'tmprotect': (8, {1: '#000000', 4: '#6e6e5c', 7: '#c8c8a8', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#a0a086', 14: '#e0e0cf', 15: '#ffffff'}),
    'tmgigadrain': (8, {1: '#000000', 4: '#4a7b3d', 7: '#88e070', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#6cb359', 14: '#bdedb0', 15: '#ffffff'}),
    'tmsafeguard': (8, {1: '#000000', 4: '#6e6e5c', 7: '#c8c8a8', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#a0a086', 14: '#e0e0cf', 15: '#ffffff'}),
    'tmsolarbeam': (8, {1: '#000000', 4: '#4a7b3d', 7: '#88e070', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#6cb359', 14: '#bdedb0', 15: '#ffffff'}),
    'tmirontail': (8, {1: '#000000', 4: '#656972', 7: '#b8c0d0', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#9399a6', 14: '#d7dce5', 15: '#ffffff'}),
    'tmthunderbolt': (8, {1: '#000000', 4: '#8c7b2c', 7: '#ffe050', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#ccb340', 14: '#ffed9e', 15: '#ffffff'}),
    'tmthunder': (8, {1: '#000000', 4: '#8c7b2c', 7: '#ffe050', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#ccb340', 14: '#ffed9e', 15: '#ffffff'}),
    'tmearthquake': (8, {1: '#000000', 4: '#7f6e42', 7: '#e8c878', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#b9a060', 14: '#f2e0b4', 15: '#ffffff'}),
    'tmdig': (8, {1: '#000000', 4: '#7f6e42', 7: '#e8c878', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#b9a060', 14: '#f2e0b4', 15: '#ffffff'}),
    'tmpsychic': (8, {1: '#000000', 4: '#8c4660', 7: '#ff80b0', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#cc668c', 14: '#ffb9d3', 15: '#ffffff'}),
    'tmshadowball': (8, {1: '#000000', 4: '#584f72', 7: '#a090d0', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#8073a6', 14: '#cac1e5', 15: '#ffffff'}),
    'tmbrickbreak': (8, {1: '#000000', 4: '#843d34', 7: '#f07060', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#c0594c', 14: '#f6b0a7', 15: '#ffffff'}),
    'tmreflect': (8, {1: '#000000', 4: '#8c4660', 7: '#ff80b0', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#cc668c', 14: '#ffb9d3', 15: '#ffffff'}),
    'tmshockwave': (8, {1: '#000000', 4: '#8c7b2c', 7: '#ffe050', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#ccb340', 14: '#ffed9e', 15: '#ffffff'}),
    'tmflamethrower': (8, {1: '#000000', 4: '#8c4f30', 7: '#ff9058', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#cc7346', 14: '#ffc1a3', 15: '#ffffff'}),
    'tmsludgebomb': (8, {1: '#000000', 4: '#724672', 7: '#d080d0', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#a666a6', 14: '#e5b9e5', 15: '#ffffff'}),
    'tmfireblast': (8, {1: '#000000', 4: '#8c4f30', 7: '#ff9058', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#cc7346', 14: '#ffc1a3', 15: '#ffffff'}),
    'tmaerialace': (8, {1: '#000000', 4: '#655c8c', 7: '#b8a8ff', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#9386cc', 14: '#d7cfff', 15: '#ffffff'}),
    'tmfacade': (8, {1: '#000000', 4: '#6e6e5c', 7: '#c8c8a8', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#a0a086', 14: '#e0e0cf', 15: '#ffffff'}),
    'tmrest': (8, {1: '#000000', 4: '#8c4660', 7: '#ff80b0', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#cc668c', 14: '#ffb9d3', 15: '#ffffff'}),
    'tmattract': (8, {1: '#000000', 4: '#6e6e5c', 7: '#c8c8a8', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#a0a086', 14: '#e0e0cf', 15: '#ffffff'}),
    'tmthief': (8, {1: '#000000', 4: '#54463d', 7: '#9a8070', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#7b6659', 14: '#c7b9b0', 15: '#ffffff'}),
    'tmsteelwing': (8, {1: '#000000', 4: '#656972', 7: '#b8c0d0', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#9399a6', 14: '#d7dce5', 15: '#ffffff'}),
    'tmoverheat': (8, {1: '#000000', 4: '#8c4f30', 7: '#ff9058', 8: '#7f8f97', 9: '#afb7bf', 10: '#d7dfdf', 12: '#cc7346', 14: '#ffc1a3', 15: '#ffffff'}),
}
# The prototype drew these evolution items with PokeAPI item art (PokeAPI/sprites, not downloaded by fetch.py);
# stand-ins: the Red sprite closest in shape, in the Red palette closest in colour
ICON_STANDIN = {
    'auspiciousarmor': (23, 9), 'berrysweet': (20, 9), 'blackaugurite': (1, 2), 'chippedpot': (2, 11), 'cloversweet': (20, 2),
    'crackedpot': (2, 11), 'dawnstone': (3, 7), 'dubiousdisc': (1, 7), 'duskstone': (14, 11), 'electirizer': (15, 1),
    'flowersweet': (20, 3), 'icestone': (15, 11), 'kingsrock': (18, 9), 'leaderscrest': (14, 6), 'linkingcord': (14, 13),
    'lovesweet': (20, 7), 'magmarizer': (15, 1), 'maliciousarmor': (23, 13), 'masterpieceteacup': (23, 9), 'metalalloy': (3, 7),
    'ovalstone': (1, 11), 'peatblock': (2, 2), 'prismscale': (1, 11), 'protector': (18, 9), 'razorclaw': (1, 11),
    'razorfang': (17, 11), 'reapercloth': (2, 2), 'ribbonsweet': (2, 7), 'sachet': (12, 2), 'scrollofdarkness': (7, 2),
    'scrollofwaters': (7, 2), 'shinystone': (14, 7), 'starsweet': (20, 4), 'strawberrysweet': (20, 3), 'sweetapple': (20, 6),
    'syrupyapple': (3, 12), 'tartapple': (20, 3), 'unremarkableteacup': (23, 9), 'whippeddream': (18, 1),
}
