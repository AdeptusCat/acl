extends Node

signal ai_placement_visibility_changed(enabled: bool)
signal debug_text_visibility_changed(enabled: bool)
signal enemy_selection_changed(enabled: bool)

var show_ai_placement: bool = false:
	set(value):
		if show_ai_placement == value:
			return
		show_ai_placement = value
		ai_placement_visibility_changed.emit(value)
var show_debug_text: bool = false:
	set(value):
		if show_debug_text == value:
			return
		show_debug_text = value
		debug_text_visibility_changed.emit(value)

var enemy_selectable: bool = false:
	set(value):
		if enemy_selectable == value:
			return
		enemy_selectable = value
		enemy_selection_changed.emit(value)
var no_damage: bool = false
var draw_thread_map: bool = false
var draw_thread_map_enemy: bool = false
var showEnemyCmdConnectivity: bool = false
var dont_fire_wepaons: bool = false
var show_los_lines: bool = false
var show_movement_lines: bool = false
var hide_fog_of_war: bool = false
var show_enemies: bool = false

var units_to_kill: Array[Unit] = []
var units_soldier_to_kill: Array[Unit] = []
var units_to_surrender: Array[Unit] = []

var influence_map_name: String = ""
var influence_map_team_name: String = ""

var engagement_recorder: EngagementRecorder
var _capture_controller: WeakRef


func _ready() -> void:
	SessionSettings.log_capture_changed.connect(_on_log_capture_changed)


func _on_log_capture_changed(enabled: bool) -> void:
	if not enabled:
		if is_instance_valid(engagement_recorder):
			engagement_recorder.finish("capture_disabled")
		return
	if _capture_controller != null:
		var controller: Node = _capture_controller.get_ref() as Node
		if is_instance_valid(controller) and controller.is_inside_tree():
			start_engagement_capture(controller)


func start_engagement_capture(controller: Node) -> void:
	if not is_instance_valid(controller):
		return
	_capture_controller = weakref(controller)
	if not SessionSettings.capture_logs or Engine.is_editor_hint():
		return
	if not is_instance_valid(engagement_recorder):
		engagement_recorder = EngagementRecorder.new()
		add_child(engagement_recorder)
	engagement_recorder.start_capture(controller)


func finish_engagement_capture(reason: String) -> void:
	_capture_controller = null
	if is_instance_valid(engagement_recorder):
		engagement_recorder.finish(reason)
