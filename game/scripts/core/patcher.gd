extends Node
## Autoload "Patcher" (must stay the FIRST autoload): script patches without reinstalling.
##
## A patch is a .zip of the game's open-source files (scripts, scenes, shaders) published on the repo's
## Releases page together with patch.json. Nothing ROM-derived is ever in a patch: data, graphics, music and
## anything else that needs a new APK raise BASE_REV, and older installs then skip the patch.
##
## Startup (_init, before the other autoloads load their scripts): the newest downloaded patch is mounted
## over res:// with ProjectSettings.load_resource_pack, so every script after this one comes from it.
## In the background (check(), called from main.gd's boot): patch.json is fetched, a newer patch is downloaded
## to user://patch/, its size and SHA-256 are checked, and it is used from the next start.
## A patch that fails to reach the main menu twice in a row is dropped.
##
## This file is never patched (it is already running when the patch is mounted): bump BASE_CODE with the
## version, and BASE_REV whenever a change can't ship as a patch.

const BASE_CODE := 79                 # = export_presets version/code of the build this file ships in
const BASE_NAME := "0.8.23"
const BASE_REV := 1                   # APK compatibility revision (data / assets / engine / project settings)
## Forks: set "pmd/update_url" in project.godot to your own patch.json ("" turns updates off).
const DEFAULT_URL := "https://github.com/Ch4rizard-X/PMD-faith/releases/latest/download/patch.json"
const DIR := "user://patch/"
const MAX_FAILS := 2

signal update_ready(version: String)

var mounted := {}          # patch.json of the mounted patch ({} = running the APK as built)
var pending := ""          # version name of a downloaded patch waiting for the next start
var status := ""           # last check's result, for the options screen
var _checking := false
var romdata_mounted := false
const ROMDATA := preload("res://scripts/core/romdata.gd")

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not exported():
		return                                     # running from the project: the files are already current
	# the game's assets built from the player's ROMs (public builds); not while the player is changing ROMs (the
	# setup screen builds a new pack and the old one must not be held open)
	romdata_mounted = ROMDATA.mount() if not ROMDATA.change_wanted() else false
	var info := _read_json(DIR + "patch.json")
	if info.is_empty():
		return
	if not _usable(info):
		_drop("old or incompatible")
		return
	var fails := int(_read_json(DIR + "boot.json").get("fails", 0))
	if fails >= MAX_FAILS:
		_drop("did not start %d times" % fails)
		return
	var path := DIR + str(info.get("file", ""))
	if not FileAccess.file_exists(path) or FileAccess.get_file_as_bytes(path).size() != int(info.get("size", -1)):
		_drop("missing")
		return
	_write_json(DIR + "boot.json", {"fails": fails + 1, "code": int(info.code)})
	if ProjectSettings.load_resource_pack(path, true):
		mounted = info
		_clean(str(info.file), "")

## The main menu was reached with this patch: it works.
func boot_ok() -> void:
	if FileAccess.file_exists(DIR + "boot.json"):
		DirAccess.remove_absolute(DIR + "boot.json")

## An exported game (PMD_PATCH_TEST=1 lets the editor binary act like one with --main-pack, for testing).
static func exported() -> bool:
	return OS.has_feature("template") or OS.get_environment("PMD_PATCH_TEST") == "1"

func version_name() -> String:
	return str(mounted.get("name", BASE_NAME))

func version_code() -> int:
	return int(mounted.get("code", BASE_CODE))

func is_patched() -> bool:
	return not mounted.is_empty()

func url() -> String:
	if OS.get_environment("PMD_UPDATE_URL") != "":
		return OS.get_environment("PMD_UPDATE_URL")       # testing against a local server
	return str(ProjectSettings.get_setting("pmd/update_url", DEFAULT_URL))

func enabled() -> bool:
	if not exported() or url() == "":
		return false
	# no static reference to the Game autoload: analysing it here would load game.gd before the patch is mounted
	var g := get_node_or_null("/root/Game")
	var st = g.get("settings") if g else null
	return bool(st.get("qol_autoupdate", true)) if typeof(st) == TYPE_DICTIONARY else true

## A patch fits this install when it is newer and needs no newer APK.
func _usable(info: Dictionary) -> bool:
	return int(info.get("code", 0)) > BASE_CODE and BASE_REV >= int(info.get("needs_base_rev", 1 << 30))

func check() -> void:
	if _checking or not enabled():
		return
	_checking = true
	await _check()
	_checking = false

func _check() -> void:
	var r: Array = await _fetch(url(), "")
	if r[0] != OK:
		status = "Couldn't check for updates."
		return
	var info = JSON.parse_string((r[1] as PackedByteArray).get_string_from_utf8())
	if typeof(info) != TYPE_DICTIONARY or not info.has("code") or not info.has("url"):
		status = "Couldn't check for updates."
		return
	var newest := maxi(version_code(), int(_read_json(DIR + "patch.json").get("code", 0)))
	if int(info.code) <= newest:
		status = "Up to date."
		return
	if BASE_REV < int(info.get("needs_base_rev", 1 << 30)):
		status = "Version %s needs a full update (new APK / rebuild)." % str(info.get("name", "?"))
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := "patch_%d.zip" % int(info.code)
	var dl := DIR + file + ".part"
	r = await _fetch(str(info.url), dl)
	if r[0] != OK or not FileAccess.file_exists(dl):
		status = "Download failed."
		return
	var size := FileAccess.get_file_as_bytes(dl).size()
	if size != int(info.get("size", -1)) or FileAccess.get_sha256(dl) != str(info.get("sha256", "")).to_lower():
		DirAccess.remove_absolute(dl)
		status = "Download was damaged."
		return
	DirAccess.rename_absolute(dl, DIR + file)
	var keep := {"code": int(info.code), "name": str(info.get("name", "")), "needs_base_rev": int(info.needs_base_rev),
		"file": file, "size": size, "sha256": str(info.sha256).to_lower()}
	_write_json(DIR + "patch.json", keep)
	_write_json(DIR + "boot.json", {"fails": 0})
	_clean(file, str(mounted.get("file", "")))
	pending = keep.name
	status = "Version %s downloaded." % pending
	update_ready.emit(pending)

## GET url (to a file when dest != ""): [error, body]. Follows GitHub's redirect to its file host.
func _fetch(u: String, dest: String) -> Array:
	var http := HTTPRequest.new()
	http.timeout = 60.0 if dest != "" else 15.0
	http.max_redirects = 8
	http.download_file = dest
	add_child(http)
	if http.request(u, ["User-Agent: PMD-faith"]) != OK:
		http.queue_free()
		return [FAILED, PackedByteArray()]
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return [FAILED, PackedByteArray()]
	return [OK, res[3]]

## Restart into the downloaded patch (desktop); on Android the game closes and is opened again by the player.
func restart() -> void:
	if OS.get_name() in ["Windows", "Linux", "macOS"]:
		OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()

func _drop(why: String) -> void:
	push_warning("Patcher: patch dropped (%s)" % why)
	for f in ["patch.json", "boot.json"]:
		if FileAccess.file_exists(DIR + f):
			DirAccess.remove_absolute(DIR + f)
	_clean("", "")

## Delete downloaded patches except keep_a / keep_b (a mounted zip can't be deleted on Windows: tried next time).
func _clean(keep_a: String, keep_b: String) -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		if f.begins_with("patch_") and f != keep_a and f != keep_b:
			d.remove(f)

static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if typeof(v) == TYPE_DICTIONARY else {}

static func _write_json(path: String, v: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(v))
