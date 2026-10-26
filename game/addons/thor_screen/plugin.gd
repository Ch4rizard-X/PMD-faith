@tool
extends EditorPlugin
## Adds the ThorScreen AAR (built from /thor_plugin with Gradle, see build_thor.bat) to Android exports.
## Needs "Use Gradle Build" in the Android export preset (v2 Android plugins are Gradle-only).
## When the AAR hasn't been built, the export goes ahead without it (the game then simply has no second screen).

var _export: ThorScreenExport

func _enter_tree() -> void:
	_export = ThorScreenExport.new()
	add_export_plugin(_export)

func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class ThorScreenExport extends EditorExportPlugin:
	const PLUGIN_NAME := "ThorScreen"

	func _get_name() -> String:
		return PLUGIN_NAME

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		# paths are relative to res://addons/
		var rel := "thor_screen/bin/debug/ThorScreen-debug.aar" if debug else "thor_screen/bin/release/ThorScreen-release.aar"
		if not FileAccess.file_exists("res://addons/" + rel):
			push_warning("ThorScreen: %s not found - exporting without second-screen support (run build_thor.bat)." % rel)
			return PackedStringArray()
		return PackedStringArray([rel])
