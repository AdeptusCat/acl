@tool
extends EditorPlugin

const INSPECTOR: Script = preload("res://addons/reinforcements/inspector.gd")
var _inspector: EditorInspectorPlugin
var _syncing: bool = false
var _elapsed: float = 0.0


func _enter_tree() -> void:
	_inspector = INSPECTOR.new()
	_inspector.plugin = self
	add_inspector_plugin(_inspector)


func _exit_tree() -> void:
	remove_inspector_plugin(_inspector)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.5:
		_elapsed = 0.0
		normalize_scene()


func _apply_changes() -> void:
	normalize_scene()


func normalize_scene() -> void:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null or _syncing:
		return
	_syncing = true
	var changes: Array[Dictionary] = []
	ReinforcementAuthoring.collect_changes(root, changes)
	if not changes.is_empty():
		var history: EditorUndoRedoManager = get_undo_redo()
		history.create_action("Update reinforcement references", UndoRedo.MERGE_DISABLE, root)
		for change: Dictionary in changes:
			var object: Object = change["object"]
			var property: String = change["property"]
			history.add_do_property(object, property, change["value"])
			history.add_undo_property(object, property, object.get(property))
		history.commit_action()
	_syncing = false


func add_reinforcement(scenario: Node) -> void:
	normalize_scene()
	var root: Node = EditorInterface.get_edited_scene_root()
	var branch: Node = scenario.get_node_or_null("Reinforcements")
	var history: EditorUndoRedoManager = get_undo_redo()
	history.create_action("Add reinforcement", UndoRedo.MERGE_DISABLE, scenario)
	if branch == null:
		branch = Node.new()
		branch.name = "Reinforcements"
		history.add_do_method(scenario, "add_child", branch, true)
		history.add_do_method(branch, "set_owner", root)
		history.add_undo_method(scenario, "remove_child", branch)
		history.add_do_reference(branch)
	var definition: ReinforcementDefinition = ReinforcementDefinition.new()
	definition.name = "Reinforcement"
	definition.reinforcement_id = ReinforcementAuthoring.new_id()
	history.add_do_method(branch, "add_child", definition, true)
	history.add_do_method(definition, "set_owner", root)
	history.add_undo_method(branch, "remove_child", definition)
	history.add_do_reference(definition)
	history.commit_action()
	EditorInterface.edit_node(definition)
