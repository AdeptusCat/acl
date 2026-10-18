extends Node

const EXCLUDED_DIRECTORIES: Array[String] = [".git", ".godot", "addons", "sources"]
const PHASE_CONTROLLER: String = "res://ai/platoon/phased/platoon_phase_controller.gd"


func _ready() -> void:
	var paths: Array[String] = []
	_collect_scripts("res://", paths)
	paths.sort()
	var failures: int = 0
	for path: String in paths:
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate():
			failures += 1
			push_error("Cannot parse project script: " + path)
	print("Project parsed scripts: ", paths.size(), "; failures: ", failures)
	get_tree().quit(failures)


func _collect_scripts(path: String, paths: Array[String]) -> void:
	var directory: DirAccess = DirAccess.open(path)
	for child: String in directory.get_directories():
		if not EXCLUDED_DIRECTORIES.has(child):
			_collect_scripts(path.path_join(child), paths)
	for file: String in directory.get_files():
		var script_path: String = path.path_join(file)
		if file.ends_with(".gd") and script_path != PHASE_CONTROLLER:
			paths.append(script_path)
