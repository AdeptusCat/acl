extends CanvasLayer

@export var unit_stats_details_scene : PackedScene
@export var ground_layer : HexagonTileMapLayer

@onready var countdown_panel_container: PanelContainer = $Control/Countdown
@onready var retry_panel: PanelContainer = $Control/TryAgain
@onready var mission_objectives: MissionObjectivesPanel = $Control/MissionObjectives
@onready var squad_roster: SquadRosterPanel = $Control/SquadRoster


@onready var target_cover_distance: Control = $Control/TargetCoverDistance
@onready var hex_edge_hint: Control = $Control/HexEdgeHint
@onready var selection_wheel: Control = $Control/SelectionWheel
@onready var selection_wheel_alt: Control = $Control/SelectionWheelAlt

@onready var unit_details: PanelContainer = $Control/UnitDetails
@onready var tile_details: PanelContainer = $Control/TileDetails
@onready var debug_panel: PanelContainer = $Control/Debug

var _left_layout_queued: bool = false
var _top_layout_queued: bool = false
var _compact_layout: bool = false

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
	$Control.resized.connect(_queue_top_layout)
	$Control/Settings.item_rect_changed.connect(_queue_top_layout)
	squad_roster.visibility_changed.connect(_queue_top_layout)
	countdown_panel_container.minimum_size_changed.connect(_queue_top_layout)
	retry_panel.minimum_size_changed.connect(_queue_top_layout)
	$Control.resized.connect(_layout_mission_objectives)
	countdown_panel_container.item_rect_changed.connect(_layout_mission_objectives)
	$Control/Settings.item_rect_changed.connect(_layout_mission_objectives)
	$Control.resized.connect(_layout_order_feedback)
	countdown_panel_container.item_rect_changed.connect(_layout_order_feedback)
	$Control/OrderFeedback.minimum_size_changed.connect(_layout_order_feedback)
	mission_objectives.item_rect_changed.connect(_layout_order_feedback)
	$Control/OrderFeedback/HideTimer.timeout.connect($Control/OrderFeedback.hide)
	get_window().size_changed.connect(_layout_mission_objectives)
	$Control.resized.connect(_queue_left_layout)
	for panel: PanelContainer in [squad_roster, tile_details, debug_panel]:
		panel.layout_requested.connect(_queue_left_layout)
		panel.visibility_changed.connect(_queue_left_layout)
	$Control/TryAgain.item_rect_changed.connect(_queue_left_layout)
	tile_details.details.folding_changed.connect(_on_terrain_folding_changed)
	debug_panel.section.folding_changed.connect(_on_debug_folding_changed)
	_queue_top_layout()
	_queue_left_layout()


func _queue_top_layout() -> void:
	if _top_layout_queued:
		return
	_top_layout_queued = true
	_layout_top_bar.call_deferred()


func _layout_top_bar() -> void:
	_top_layout_queued = false
	if not is_node_ready() or is_queued_for_deletion():
		return
	var compact: bool = $Control.size.x < 1100.0 or $Control.size.y < 620.0
	if compact and not _compact_layout:
		mission_objectives.section.fold()
		tile_details.details.fold()
		debug_panel.section.fold()
		unit_details.details_section.fold()
		unit_details.roster_section.fold()
	_compact_layout = compact
	var retry_minimum: Vector2 = retry_panel.get_combined_minimum_size()
	var timer_minimum: Vector2 = countdown_panel_container.get_combined_minimum_size()
	var height: float = maxf(30.0, maxf(retry_minimum.y, timer_minimum.y))
	retry_panel.size = Vector2(maxf(112.0, retry_minimum.x), height)
	countdown_panel_container.size = Vector2(maxf(230.0, timer_minimum.x), height)
	var width: float = retry_panel.size.x + 8.0 + countdown_panel_container.size.x
	var left: float = ($Control.size.x - width) * 0.5
	if squad_roster.visible:
		left = maxf(left, 12.0 + SquadRosterPanel.PANEL_WIDTH + 6.0)
	left = minf(left, $Control.size.x - width - 12.0)
	var top: float = 6.0
	var toolbar_rect: Rect2 = $Control/Settings.get_rect()
	if left + width + 6.0 > toolbar_rect.position.x:
		top = toolbar_rect.end.y + 6.0
	retry_panel.position = Vector2(left, top)
	countdown_panel_container.position = Vector2(left + retry_panel.size.x + 8.0, top)
	_layout_mission_objectives()
	_layout_order_feedback()
	_queue_left_layout()


func show_squad_roster(player_team: Globals.Team) -> void:
	squad_roster.setup(player_team)
	_queue_left_layout()


func _queue_left_layout() -> void:
	if _left_layout_queued:
		return
	_left_layout_queued = true
	_layout_left_panels.call_deferred()


func _layout_left_panels() -> void:
	_left_layout_queued = false
	if not is_node_ready() or is_queued_for_deletion():
		return
	var top: float = 6.0
	for header: Control in [retry_panel, countdown_panel_container, $Control/Settings]:
		var rect: Rect2 = header.get_rect()
		if rect.position.x < 12.0 + SquadRosterPanel.PANEL_WIDTH and rect.end.x > 12.0:
			top = maxf(top, rect.end.y + 6.0)
	var bottom: float = $Control.size.y - 12.0
	# HUD coordinates compensate for UI scale. Whole pixels keep container
	# minimum sizes stable while the visible height stays one-third of the screen.
	var panel_height_limit: float = floorf($Control.size.y / 3.0)
	var terrain_height: float = 0.0
	var debug_height: float = 0.0
	var support_minimum: float = 0.0
	var panel_count: int = int(squad_roster.visible)
	if tile_details.visible:
		terrain_height = minf(tile_details.get_preferred_height(), panel_height_limit)
		support_minimum += tile_details.get_minimum_height()
		panel_count += 1
	if debug_panel.visible:
		debug_height = debug_panel.get_preferred_height()
		support_minimum += debug_panel.get_minimum_height()
		panel_count += 1
	var gaps: float = maxf(0.0, float(panel_count - 1) * 12.0)
	var available_height: float = maxf(0.0, bottom - top - gaps)
	var roster_height: float = 0.0
	if squad_roster.visible:
		roster_height = minf(minf(squad_roster.get_preferred_height(), panel_height_limit), maxf(squad_roster.get_minimum_height(), available_height - support_minimum))
	var support_height: float = maxf(0.0, available_height - roster_height)
	# Keep the roster in its column; only the expanded support content shrinks.
	if tile_details.visible and not tile_details.details.folded:
		terrain_height = minf(terrain_height, maxf(tile_details.get_minimum_height(), support_height - debug_height))
	if debug_panel.visible and not debug_panel.section.folded:
		debug_height = minf(debug_height, maxf(debug_panel.get_minimum_height(), support_height - terrain_height))
	if tile_details.visible:
		tile_details.fit_panel(Vector2(12.0, 0.0), terrain_height)
		tile_details.position.y = bottom - tile_details.size.y
		bottom = tile_details.position.y - 12.0
	if debug_panel.visible:
		debug_panel.fit_panel(Vector2(12.0, 0.0), debug_height)
		debug_panel.position.y = bottom - debug_panel.size.y
	if squad_roster.visible:
		squad_roster.fit_panel(Vector2(12.0, top), roster_height)


func _on_terrain_folding_changed(folded: bool) -> void:
	if not folded:
		debug_panel.section.fold()
	_queue_left_layout()


func _on_debug_folding_changed(folded: bool) -> void:
	if not folded:
		tile_details.details.fold()
	_queue_left_layout()


func show_mission_objectives(conditions: Array[VictoryCondition], player_team: Globals.Team, time_left_seconds: float) -> void:
	mission_objectives.setup(conditions, player_team, time_left_seconds)
	if _compact_layout:
		mission_objectives.section.fold()
	_layout_mission_objectives()


func _layout_mission_objectives() -> void:
	var viewport_width: float = $Control.size.x
	var panel_width: float = minf(320.0, maxf(0.0, viewport_width - 280.0 - 36.0))
	mission_objectives.custom_minimum_size.x = panel_width
	mission_objectives.size.x = panel_width
	var left: float = viewport_width - panel_width - 12.0
	var top: float = 6.0
	for header: Control in [retry_panel, countdown_panel_container, $Control/Settings]:
		var rect: Rect2 = header.get_rect()
		if rect.end.x > left and rect.position.x < left + panel_width:
			top = maxf(top, rect.end.y + 6.0)
	mission_objectives.position = Vector2(left, top)
	mission_objectives.fit_available_height(floorf(minf($Control.size.y / 3.0, maxf(0.0, $Control.size.y - top - 12.0))))


func setup() -> void:
	tile_details.set_ground_layer(ground_layer)
	unit_details.hide()

func show_tile_data(result: Dictionary) -> void:
	tile_details.show_tile_data(result)


func show_target_hex_cover_distance(point: Vector2, target_cover: int, distance: int, firepower: float, sight_clear: bool = true, indirect: bool = false, in_range: bool = true) -> void:
	var sight: String = "Line of sight clear"
	var cover: String = "Cover: %d" % target_cover
	var color: Color = Color(0.65, 0.85, 0.55)
	if indirect:
		sight = "Indirect fire"
		color = Color(0.86, 0.73, 0.5)
	elif not sight_clear:
		sight = "Line of sight blocked"
		cover = "Cover: unknown (blocked sight)"
		color = Color(0.96, 0.55, 0.4)
	if not in_range:
		sight = "Out of range"
		color = Color(0.96, 0.55, 0.4)
	var distance_text: String = "%d hexes" % distance
	if distance == 1:
		distance_text = "1 hex"
	target_cover_distance.show_hint(point, sight, "Distance: %s\n%s" % [distance_text, cover], "Effective firepower: %s" % String.num(firepower, 2), color)


func show_order_feedback(accepted: bool, command: String, explanation: String) -> void:
	var title: String = "Order rejected · " + command
	var color: Color = Color(0.96, 0.62, 0.43)
	if accepted:
		title = "Order accepted · " + command
		color = Color(0.65, 0.85, 0.55)
	_show_order_message(title, explanation, color)


func show_order_cancelled() -> void:
	_show_order_message("Order cancelled", "", Color(0.78, 0.79, 0.7))


func hide_order_feedback() -> void:
	$Control/OrderFeedback.hide()
	$Control/OrderFeedback/HideTimer.stop()


func _show_order_message(title: String, explanation: String, color: Color) -> void:
	$Control/OrderFeedback/Content/Title.text = title
	$Control/OrderFeedback/Content/Title.add_theme_color_override("font_color", color)
	$Control/OrderFeedback/Content/Explanation.text = explanation
	$Control/OrderFeedback/Content/Explanation.visible = not explanation.is_empty()
	$Control/OrderFeedback.show()
	$Control/OrderFeedback/HideTimer.start()
	_layout_order_feedback()


func _layout_order_feedback() -> void:
	var panel: PanelContainer = $Control/OrderFeedback
	panel.custom_minimum_size.x = 320.0
	panel.size = Vector2(320.0, panel.get_combined_minimum_size().y)
	var left: float = ($Control.size.x - panel.size.x) * 0.5
	if squad_roster.visible:
		left = maxf(left, squad_roster.get_rect().end.x + 12.0)
	left = minf(left, $Control.size.x - panel.size.x - 12.0)
	panel.position = Vector2(left, countdown_panel_container.get_rect().end.y + 12.0)
	if mission_objectives.visible and panel.get_rect().intersects(mission_objectives.get_rect()):
		panel.position.y = mission_objectives.get_rect().end.y + 12.0


func show_hex_edge_hint(direction: int, cover: int, point: Vector2) -> void:
	var names: Array[String] = ["North", "Northeast", "Southeast", "South", "Southwest", "Northwest"]
	hex_edge_hint.show_hint(point, "%s edge · Cover %d" % [names[direction], cover], "Protection applies from this side.")
	target_cover_distance.hide()


func hide_hex_edge_hint() -> void:
	hex_edge_hint.hide()


func hide_tile_data() -> void:
	tile_details.hide_inspection()
	hide_hex_edge_hint()


func hide_target_hex_cover_distance() -> void:
	target_cover_distance.hide()


func _on_game_started_through_moving_unit() -> void:
	countdown_panel_container.set_countdown(true)


func _on_update_timer_label(time_left_seconds : float) -> void:
	countdown_panel_container.update_timer_label(time_left_seconds)
	mission_objectives.update_time(time_left_seconds)


func _on_update_overtime_label(elapsed_seconds: float) -> void:
	countdown_panel_container.update_overtime_label(elapsed_seconds)


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
	squad_roster.focus_unit(unit)
	unit_details.show_unit_detail(unit)
	hide_target_hex_cover_distance()


func _on_hide_unit_details() -> void:
	unit_details.hide_unit_detail()
	hide_target_hex_cover_distance()


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
		
