extends Node
## Autoload "Audio": background music and Red's sound effects.

const SFX := {"cursor": "301", "confirm": "302", "cancel": "303", "error": "303", "info": "304", "text": "305", "stairs": "341",
	"recruit": "463", "join": "204", "levelup": "200", "evolve": "210", "pickup": "333", "coin": "332", "heal": "606",
	"hit": "608", "hitsmall": "607", "hitbig": "610", "miss": "342", "missfoe": "343", "throw": "336"}

var music: AudioStreamPlayer
var current := ""
var _pool: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	music = AudioStreamPlayer.new()
	add_child(music)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

## Red songs whose sequence has no GOTO (sound/songs/seq_NNN.s): they play once and scripts wait for them to end
## (the intro's 0xE0 wait on MUS_INTRO, the title on MUS_TITLE_SCREEN). Looping them left the intro on a white
## screen for minutes.
const ONE_SHOT := ["040", "043", "045", "046", "050", "051", "052"]

func play_music(id: String) -> void:
	if id == current and music.playing:
		return
	current = id
	var path := "res://assets/music/%s.mp3" % id
	if not ResourceLoader.exists(path):
		path = "res://assets/music/%s.ogg" % id
	if not ResourceLoader.exists(path):
		music.stop()
		return
	var s: AudioStream = load(path)
	if s is AudioStreamMP3 or s is AudioStreamOggVorbis:
		s.loop = not (id in ONE_SHOT)
		if id.begins_with("eos_"):
			var L: Dictionary = _eos_loops().get(id.substr(4), {})
			if not L.is_empty():
				s.loop = L.get("loop_start") != null
				if s.loop:
					s.loop_offset = float(L.loop_start)
		elif s.loop:
			# Red tracks rendered by tools/music/red (intro + one loop): loop back to the loop start, not to 0
			var RL: Dictionary = _eos_loops().get("red_" + id, {})
			if RL.get("loop_start") != null:
				s.loop_offset = float(RL.loop_start)
			elif not RL.is_empty():
				s.loop = false
	music.stream = s
	music.volume_db = linear_to_db(maxf(0.001, float(Game.settings.music)))
	music.play()

var _eos_loop_tab = null
func _eos_loops() -> Dictionary:
	if _eos_loop_tab == null:
		_eos_loop_tab = {}
		var f := FileAccess.open("res://data/eos_loops.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_eos_loop_tab = d
	return _eos_loop_tab

func is_bgm_playing_id(id: int) -> bool:
	return music.playing and current == "%03d" % id

func fade_out_music(frames: int) -> void:
	if not music.playing:
		return
	var tw := create_tween()
	tw.tween_property(music, "volume_db", -60.0, maxf(frames / 60.0, 0.05))
	tw.tween_callback(stop_music)

func stop_music() -> void:
	current = ""
	music.stop()

func sfx(name: String) -> void:
	var id: String = SFX.get(name, name)
	var path := "res://assets/sfx/%s.mp3" % id
	if not ResourceLoader.exists(path):
		path = "res://assets/sfx/%s.ogg" % id
		if not ResourceLoader.exists(path):
			return
	for p in _pool:
		if not p.playing:
			p.stream = load(path)
			p.volume_db = linear_to_db(maxf(0.001, float(Game.settings.sfx)))
			p.play()
			return
