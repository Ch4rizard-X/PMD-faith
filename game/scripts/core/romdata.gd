extends RefCounted
## The game's graphics, music and data, built on the player's device ("romdata").
##
## Public builds ship without game/assets and game/data (they come from the player's own ROMs). The setup screen
## turns a folder holding assets/ and data/ (made by build_all.py, or later by the in-app ROM import) into
## user://romdata/romdata.zip, which Patcher mounts over res:// at startup. Inside the zip every asset gets what
## the Godot editor's import would have made, so the game loads them exactly like bundled ones:
##   images  -> .romdata/<path>.ctex (CompressedTexture2D, lossless: the original PNG / WebP bytes, not re-encoded)
##   ogg/mp3 -> .romdata/<path>.res  (AudioStreamOggVorbis / AudioStreamMP3)
##   ttf     -> .romdata/<path>.res  (FontFile)
##   plus <path>.import pointing at it; JSON and every other file are stored as they are.
## Loaded by path (no class_name): preload("res://scripts/core/romdata.gd").

const DIR := "user://romdata/"
const ZIP := "user://romdata/romdata.zip"
const INFO := "user://romdata/romdata.json"
const VERSION := 1                   # bump when the pack layout changes (forces a rebuild)

## Bundled (dev / private builds) or mounted from romdata: is the game's data there?
static func present() -> bool:
	return FileAccess.file_exists("res://data/species.json")

static func installed() -> bool:
	return FileAccess.file_exists(ZIP) and int(_read_json(INFO).get("version", 0)) == VERSION

## Mounts the pack (Patcher._init calls this before mounting a script patch).
static func mount() -> bool:
	if not FileAccess.file_exists(ZIP):
		return false
	return ProjectSettings.load_resource_pack(ZIP, true)

static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if typeof(v) == TYPE_DICTIONARY else {}

## Checks a source folder: it must hold assets/ and data/ with the main tables.
static func check_source(src: String) -> String:
	src = src.rstrip("/\\")
	for need in ["data/species.json", "data/dungeons.json", "data/sprites.json", "assets/ui/pmd_red_text.ttf"]:
		if not FileAccess.file_exists(src + "/" + need):
			return "This folder has no %s. Pick the folder that holds assets and data (the game folder made by the setup tools)." % need
	return ""

## Every file under src/assets and src/data, as paths relative to src.
static func list_files(src: String) -> PackedStringArray:
	var out := PackedStringArray()
	for top in ["assets", "data"]:
		_walk(src.rstrip("/\\"), top, out)
	return out

static func _walk(root: String, rel: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(root + "/" + rel)
	if d == null:
		return
	d.include_hidden = false
	for f in d.get_files():
		if f.ends_with(".import") or f.ends_with(".uid"):
			continue
		out.append(rel + "/" + f)
	for sub in d.get_directories():
		_walk(root, rel + "/" + sub, out)

# ------------------------------------------------------------------ building the pack
## A builder that works through the files a slice at a time (call step() every frame; progress 0..1).
class Builder:
	var src := ""
	var files: PackedStringArray
	var i := 0
	var zip: ZIPPacker
	var error := ""
	var done := false
	var stats := {"img": 0, "audio": 0, "font": 0, "raw": 0, "bytes": 0}
	var _t0 := 0

	func start(source: String) -> String:
		src = source.rstrip("/\\")
		error = _check()
		if error != "":
			return error
		files = _list()
		DirAccess.make_dir_recursive_absolute(DIR)
		if FileAccess.file_exists(ZIP + ".part"):
			DirAccess.remove_absolute(ZIP + ".part")
		zip = ZIPPacker.new()
		zip.compression_level = 0          # textures / audio are compressed already: store
		if zip.open(ZIP + ".part") != OK:
			error = "Couldn't write to the game's storage."
			return error
		_t0 = Time.get_ticks_msec()
		return ""

	func _check() -> String:
		return load("res://scripts/core/romdata.gd").check_source(src)

	func _list() -> PackedStringArray:
		return load("res://scripts/core/romdata.gd").list_files(src)

	func progress() -> float:
		return float(i) / maxf(1.0, float(files.size()))

	func current() -> String:
		return files[mini(i, files.size() - 1)] if files.size() > 0 else ""

	## Converts files for about `budget_ms` milliseconds. Returns true when everything is done.
	func step(budget_ms := 30) -> bool:
		if done or error != "":
			return true
		var until := Time.get_ticks_msec() + budget_ms
		while i < files.size() and Time.get_ticks_msec() < until:
			var rel: String = files[i]
			var err := _add(rel)
			if err != "":
				error = "%s: %s" % [rel, err]
				zip.close()
				return true
			i += 1
		if i >= files.size():
			_finish()
		return done

	func _put(path: String, data: PackedByteArray) -> void:
		zip.start_file(path)
		zip.write_file(data)
		zip.close_file()
		stats.bytes += data.size()

	func _import(rel: String, importer: String, type: String, to: String) -> void:
		var t := "[remap]\n\nimporter=\"%s\"\ntype=\"%s\"\npath=\"res://%s\"\n" % [importer, type, to]
		_put(rel + ".import", t.to_utf8_buffer())

	func _add(rel: String) -> String:
		var abs := src + "/" + rel
		var ext := rel.get_extension().to_lower()
		var bytes := FileAccess.get_file_as_bytes(abs)
		if bytes.is_empty() and FileAccess.get_open_error() != OK:
			return "couldn't read"
		match ext:
			"png", "webp":
				var ctex := _ctex(bytes, ext == "webp")
				if ctex.is_empty():
					return "not a readable image"
				var to := ".romdata/%s.ctex" % rel
				_put(to, ctex)
				_import(rel, "texture", "CompressedTexture2D", to)
				stats.img += 1
			"ogg":
				var s := AudioStreamOggVorbis.load_from_buffer(bytes)
				if s == null:
					return "not a readable Ogg file"
				return _save_res(rel, s, "oggvorbisstr", "AudioStreamOggVorbis", "audio")
			"mp3":
				var m := AudioStreamMP3.new()
				m.data = bytes
				return _save_res(rel, m, "mp3", "AudioStreamMP3", "audio")
			"ttf", "otf":
				var fnt := FontFile.new()
				fnt.data = bytes
				fnt.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
				fnt.generate_mipmaps = false
				fnt.disable_embedded_bitmaps = true
				fnt.hinting = TextServer.HINTING_NORMAL
				fnt.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
				return _save_res(rel, fnt, "font_data_dynamic", "FontFile", "font")
			_:
				_put(rel, bytes)
				stats.raw += 1
		return ""

	func _save_res(rel: String, res: Resource, importer: String, type: String, kind: String) -> String:
		var tmp := DIR + "tmp_res.res"
		if ResourceSaver.save(res, tmp) != OK:
			return "couldn't convert"
		var to := ".romdata/%s.res" % rel
		_put(to, FileAccess.get_file_as_bytes(tmp))
		_import(rel, importer, type, to)
		stats[kind] += 1
		return ""

	## A lossless CompressedTexture2D holding the original PNG / WebP bytes (Godot's .ctex layout,
	## ResourceImporterTexture::_save_ctex + save_to_ctex_format, COMPRESS_LOSSLESS).
	func _ctex(bytes: PackedByteArray, webp: bool) -> PackedByteArray:
		var info := _png_info(bytes) if not webp else {}
		if info.is_empty():
			var img := Image.new()
			var e := img.load_webp_from_buffer(bytes) if webp else img.load_png_from_buffer(bytes)
			if e != OK:
				return PackedByteArray()
			info = {"w": img.get_width(), "h": img.get_height(), "fmt": img.get_format()}
		var f := StreamPeerBuffer.new()
		f.big_endian = false
		f.put_u8(0x47); f.put_u8(0x53); f.put_u8(0x54); f.put_u8(0x32)    # GST2
		f.put_u32(1)                      # FORMAT_VERSION
		f.put_u32(int(info.w))
		f.put_u32(int(info.h))
		f.put_u32(0)                      # flags: no mipmaps, not streamed
		f.put_u32(0xFFFFFFFF)             # mipmap limit (-1)
		f.put_u32(0); f.put_u32(0); f.put_u32(0)
		f.put_u32(2 if webp else 1)       # DATA_FORMAT_WEBP / DATA_FORMAT_PNG
		f.put_u16(int(info.w) & 0xFFFF)
		f.put_u16(int(info.h) & 0xFFFF)
		f.put_u32(0)                      # mipmap count
		f.put_u32(int(info.fmt))
		if webp:
			f.put_u32(bytes.size())           # WebP: the RIFF file as it is
		else:
			f.put_u32(bytes.size() + 4)       # PNG: Image::png_packer prefixes its data with "PNG "
			f.put_data("PNG ".to_ascii_buffer())
		f.put_data(bytes)
		return f.data_array

	## Size and decoded Image format of a PNG from its header (empty: decode it instead).
	func _png_info(b: PackedByteArray) -> Dictionary:
		if b.size() < 33 or b[0] != 0x89 or b[1] != 0x50 or b[2] != 0x4E or b[3] != 0x47:
			return {}
		var w := (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19]
		var h := (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23]
		var depth := b[24]
		var ctype := b[25]
		if depth == 16:
			return {}
		# a tRNS chunk before IDAT turns RGB / palette / grey into their alpha forms
		var trns := false
		var p := 8
		while p + 8 <= b.size():
			var ln := (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3]
			var ty := b.slice(p + 4, p + 8).get_string_from_ascii()
			if ty == "tRNS":
				trns = true
				break
			if ty == "IDAT" or ty == "IEND":
				break
			p += 12 + ln
		var fmt := Image.FORMAT_RGBA8
		match ctype:
			0: fmt = Image.FORMAT_LA8 if trns else Image.FORMAT_L8
			2: fmt = Image.FORMAT_RGBA8 if trns else Image.FORMAT_RGB8
			3: fmt = Image.FORMAT_RGBA8 if trns else Image.FORMAT_RGB8
			4: fmt = Image.FORMAT_LA8
			6: fmt = Image.FORMAT_RGBA8
		return {"w": w, "h": h, "fmt": fmt}

	func _finish() -> void:
		var info := {"version": VERSION, "files": files.size(), "made": Time.get_datetime_string_from_system(), "stats": stats}
		_put(".romdata/info.json", JSON.stringify(info).to_utf8_buffer())
		zip.close()
		if FileAccess.file_exists(ZIP):
			DirAccess.remove_absolute(ZIP)
		DirAccess.rename_absolute(ZIP + ".part", ZIP)
		if FileAccess.file_exists(DIR + "tmp_res.res"):
			DirAccess.remove_absolute(DIR + "tmp_res.res")
		var fw := FileAccess.open(INFO, FileAccess.WRITE)
		if fw:
			fw.store_string(JSON.stringify(info))
		done = true

	func seconds() -> float:
		return (Time.get_ticks_msec() - _t0) / 1000.0
