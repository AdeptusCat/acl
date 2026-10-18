@tool
extends EditorExportPlugin

const MANIFEST_PATH: String = "res://docs/faction_folder_refactor_manifest.json"


func _get_name() -> String:
	return "FactionResourceCompatibility"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary or not parsed.has("compatibility_resources"):
		push_error("Faction resource compatibility manifest is missing or invalid")
		return
	var resources: Dictionary = parsed["compatibility_resources"]
	for legacy_path: String in resources:
		var canonical_path: String = "res://" + resources[legacy_path]
		var content: PackedByteArray = FileAccess.get_file_as_bytes(canonical_path)
		if content.is_empty():
			push_error("Cannot export legacy faction resource: " + canonical_path)
			continue
		# Export omits manual .remap files and does not follow nested remaps to
		# binary-converted resources. Pack the current definition at the old path.
		add_file("res://" + legacy_path, content, false)
