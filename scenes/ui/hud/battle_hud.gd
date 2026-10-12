extends CanvasLayer

@export var unit_stats_details_scene : PackedScene
@export var ground_layer : HexagonTileMapLayer

@onready var countdown_panel_container: PanelContainer = $Control/Countdown
@onready var mission_objectives: MissionObjectivesPanel = $Control/MissionObjectives
@onready var squad_roster: SquadRosterPanel = $Control/SquadRoster


@onready var cover_icon_scene: PackedScene = preload("res://scenes/ui/effects/cover_icon.tscn")

@onready var target_cover_distance: Control = $Control/TargetCoverDistance
@onready var cover_container: HBoxContainer = $Control/TargetCoverDistance/VBoxContainer/Cover
@onready var firepower_label: Label = $Control/TargetCoverDistance/VBoxContainer/HBoxContainer/FirepowerLabel
@onready var distance_label: Label = $Control/TargetCoverDistance/VBoxContainer/HBoxContainer2/DistanceLabel
@onready var selection_wheel: Control = $Control/SelectionWheel
@onready var selection_wheel_alt: Control = $Control/SelectionWheelAlt

@onready var unit_details: PanelContainer = $Control/UnitDetails
@onready var tile_details: PanelContainer = $Control/TileDetails

signal try_again

# Configuration
const HEX_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]


#func _process(delta: float) -> void:
	#if Input.is_action_just_pressed("RIGHT"):
		#selection_wheel.show()
	#elif Input.is_action_just_released("RIGHT"):
		#var option: WheelOption.Option = selection_wheel.close()
		#print(option)

func _ready() -> void:
	$Control.resized.connect(_layout_mission_objectives)
	countdown_panel_container.item_rect_changed.connect(_layout_mission_objectives)
	get_window().size_changed.connect(_layout_mission_objectives)
	$Control.resized.connect(_queue_roster_layout)
	squad_roster.layout_requested.connect(_queue_roster_layout)
	for panel: Control in [mission_objectives, tile_details, $Control/Debug, $Control/TryAgain]:
		panel.item_rect_changed.connect(_queue_roster_layout)
		panel.visibility_changed.connect(_queue_roster_layout)


func show_squad_roster(player_team: Globals.Team) -> void:
	squad_roster.setup(player_team)
	_queue_roster_layout()


func _queue_roster_layout() -> void:
	_layout_squad_roster.call_deferred()


func _layout_squad_roster() -> void:
	if not is_node_ready() or is_queued_for_deletion():
		return
	var hud_size: Vector2 = $Control.size
	var area: Rect2 = _squad_roster_area(12.0, hud_size)
	var debug_panel: Control = $Control/Debug
	# Visible development controls may fill the left edge; use the next column.
	if area.size.y < 160.0 and debug_panel.visible:
		var alternate_left: float = debug_panel.get_rect().end.x + 12.0
		if alternate_left + SquadRosterPanel.PANEL_WIDTH <= hud_size.x - 12.0:
			area = _squad_roster_area(alternate_left, hud_size)
	squad_roster.fit_panel(area.position, area.size.y)


func _squad_roster_area(left: float, hud_size: Vector2) -> Rect2:
	var top: float = $Control/TryAgain.get_rect().end.y + 12.0
	var bottom: float = hud_size.y - 12.0
	var column: Rect2 = Rect2(left, 0.0, SquadRosterPanel.PANEL_WIDTH, hud_size.y)
	if mission_objectives.visible and column.intersects(mission_objectives.get_rect()):
		top = maxf(top, mission_objectives.get_rect().end.y + 12.0)
	for panel: Control in [$Control/Debug, tile_details]:
		if panel.visible and column.intersects(panel.get_rect()):
			bottom = minf(bottom, panel.position.y - 12.0)
	return Rect2(left, top, SquadRosterPanel.PANEL_WIDTH, maxf(88.0, bottom - top))


func show_mission_objectives(conditions: Array[VictoryCondition], player_team: Globals.Team, time_left_seconds: float) -> void:
	mission_objectives.setup(conditions, player_team, time_left_seconds)
	_layout_mission_objectives()


func _layout_mission_objectives() -> void:
	var viewport_width: float = $Control.size.x
	var panel_width: float = minf(320.0, maxf(0.0, viewport_width - 24.0))
	var timer_rect: Rect2 = countdown_panel_container.get_rect()
	var available_width: float = minf(viewport_width, float(get_window().size.x))
	var retry_panel: Control = $Control/TryAgain
	var space_beside_timer: float = timer_rect.position.x - retry_panel.get_rect().end.x - 24.0
	var beside_timer: bool = space_beside_timer >= 280.0 and (available_width - timer_rect.size.x) * 0.5 >= panel_width + 24.0
	if beside_timer:
		panel_width = minf(panel_width, space_beside_timer)
	mission_objectives.custom_minimum_size.x = panel_width
	mission_objectives.size.x = panel_width
	if beside_timer:
		mission_objectives.position = Vector2(timer_rect.position.x - panel_width - 12.0, timer_rect.position.y)
	else:
		mission_objectives.position = Vector2(maxf(12.0, (viewport_width - panel_width) * 0.5), timer_rect.end.y + 12.0)


func setup() -> void:
	tile_details.set_ground_layer(ground_layer)
	unit_details.hide()

func show_tile_data(result: Dictionary) -> void:
	tile_details.show_tile_data(result)


func show_target_hex_cover_distance(local_event_pos: Vector2, targetCover: int, distance: int, firepower: float) -> void:
	target_cover_distance.show()
	target_cover_distance.position = local_event_pos
	for child: Control in cover_container.get_children():
		child.queue_free()
	for cover: int in targetCover:
		var cover_icon: TextureRect = cover_icon_scene.instantiate()
		cover_icon.expand_mode = TextureRect.ExpandMode.EXPAND_FIT_WIDTH_PROPORTIONAL
		cover_container.add_child(cover_icon)
	firepower_label.text = str(firepower)
	distance_label.text = str(distance)
	#if detail_ui:
		#detail_ui.set_cover(targetCover)


func hide_target_hex_cover_distance() -> void:
	target_cover_distance.hide()


func _on_game_started_through_moving_unit() -> void:
	countdown_panel_container.set_countdown(true)


func _on_update_timer_label(time_left_seconds : float) -> void:
	countdown_panel_container.update_timer_label(time_left_seconds)
	mission_objectives.update_time(time_left_seconds)


func mouse_event_position_changed(_event_pos: Vector2) -> void:
	pass

# legacy code that shows unit details
#func show_unit_data(map_hex: Vector2i, units: Array):
	#unit_stats.visible = true
	#var unit_detail_counter: int = 0
	#for child in unit_stats_container.get_children():
		#if "detail_ui" in child:
			#child.detail_ui = null
		#child.queue_free()
	#for unit in units:
		#if not LOSHelper.visible_hexes[Globals.team_player].has(unit.current_hex):
			#continue
		##var unit_ui = unit.ui.duplicate(Node.DuplicateFlags.DUPLICATE_SIGNALS | Node.DuplicateFlags.DUPLICATE_GROUPS | Node.DuplicateFlags.DUPLICATE_SCRIPTS)
		##unit_stats_container.add_child(unit_ui)
		##var unit_detail_container = unit_ui.soldiers_detail_container.duplicate()
		##unit_stats_container.add_child(unit_detail_container)
		##var unit_stats_details = unit_stats_details_scene.instantiate()
		##unit_stats_details.set_details(unit)
		##unit_stats_container.add_child(unit_stats_details)
		#
		##unit.ui.detail_ui = unit_ui
		##unit_ui._set_loadout(unit.squad_fire.soldiers)
		##unit_detail_counter += 1
	#if unit_detail_counter == 0:
		#unit_stats.visible = false


func _on_show_unit_details(unit: Unit) -> void:
	unit_details.show_unit_detail(unit)


func _on_hide_unit_details() -> void:
	unit_details.hide_unit_detail()


func _on_try_again_button_pressed() -> void:
	try_again.emit()


func _db_to_ratio(db: float) -> float:
	# Convert dB (-80..0) to 0–1 range for slider
	return pow(10.0, db / 20.0)

func _ratio_to_db(ratio: float) -> float:
	# Convert slider ratio (0–1) back to dB
	var db: float
	if ratio <= 0.0001:
		db = -80.0
	else:
		db = 20.0 * log(ratio)
	return db


func _on_start_screen_time_changed(_time: float) -> void:
	if countdown_panel_container:
		countdown_panel_container.update_timer_label(_time * 60.0)
		
