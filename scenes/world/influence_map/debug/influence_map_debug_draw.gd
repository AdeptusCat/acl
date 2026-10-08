class_name InfluenceMapDebugDraw
extends Node2D

enum DebugView {
	NONE,
	COMPOSITE,
	
	TERRAIN_COVER,
	TERRAIN_MOVE_COST,
	
	ENEMY_VISIBILITY,
	VISIBILITY,
	FIRE_POWER,
	THREAT,
	ENEMY_VULNERABILITY,
	
	COVER_VS_ENEMY_FIRE,
	VISIBILITY_HINDRANCE,
	UNIT_INFLUENCE,
	
	HQ_SUPPORT_NEED,
	FORECAST_THREAT,
	POSITION_SCORE,
	#RETURN_FIRE_PENALTY,
	
	#FRIENDLY_SUPPORT,
	#OBJECTIVE_PRESSURE,
	#KNOWN_ENEMY_POSITION,
	#NO_GO
}

const DebugViewNames: Dictionary[DebugView, String] = {
	DebugView.NONE: "NONE",
	DebugView.COMPOSITE: "Composite",
	DebugView.TERRAIN_COVER: "TERRAIN_COVER",
	DebugView.TERRAIN_MOVE_COST: "TERRAIN_MOVE_COST",
	DebugView.VISIBILITY: "VISIBILITY",
	DebugView.FIRE_POWER: "FIRE_POWER",
	DebugView.COVER_VS_ENEMY_FIRE: "COVER_VS_ENEMY_FIRE",
	DebugView.VISIBILITY_HINDRANCE: "VISIBILITY_HINDRANCE",
	DebugView.THREAT: "THREAT",
	DebugView.ENEMY_VULNERABILITY: "ENEMY_VULNERABILITY",
	DebugView.UNIT_INFLUENCE: "UNIT_INFLUENCE",
	DebugView.HQ_SUPPORT_NEED: "HQ_SUPPORT_NEED",
	DebugView.FORECAST_THREAT: "FORECAST_THREAT",
	DebugView.POSITION_SCORE: "POSITION_SCORE",
	DebugView.ENEMY_VISIBILITY: "ENEMY_VISIBILITY",
}



@export var tile_map_layer: TileMapLayer = null
@export var influence_controller: Node = null

@export var team: int = 0
@export var debug_view: DebugView = DebugView.NONE

@export var draw_alpha: float = 0.55
@export var hex_draw_scale: float = 0.5
@export var flat_top_hexes: bool = false

@export var auto_scale_values: bool = true
@export var manual_min_value: float = 0.0
@export var manual_max_value: float = 5.0

@export var hide_zero_values: bool = true
@export var zero_epsilon: float = 0.001

@export var draw_cell_values: bool = false
@export var value_text_min_zoom: float = 0.75

var selected_unit: Unit
var position_advice: PositionResult
var position_advice_provider: Callable
var _view_before_selection: DebugView = DebugView.NONE
var _team_before_selection: int = 0
var _advice_refresh_time: float = 0.0
var _advice_origin: Vector2i = Vector2i.ZERO

#var low_color: Color = Color(0.1, 0.25, 1.0, 1.0)
#var mid_color: Color = Color(0.1, 1.0, 0.1, 1.0)
#var high_color: Color = Color(1.0, 0.1, 0.1, 1.0)

var low_color: Color = Color(0.65, 0.85, 1.0, 1.0)
var mid_color: Color = Color(0.1, 0.35, 0.85, 1.0)
var high_color: Color = Color(0.05, 0.12, 0.35, 1.0)

#var low_color: Color = Color(0.05, 0.12, 0.35, 1.0)
#var mid_color: Color = Color(0.1, 0.35, 0.85, 1.0)
#var high_color: Color = Color(0.65, 0.85, 1.0, 1.0)

#var influence_color: Color = Color(0.1, 0.35, 1.0, 1.0)

var _cached_cells: Array[Vector2i] = []
var _cached_min_value: float = 0.0
var _cached_max_value: float = 1.0
var _cache_valid: bool = false


#func _ready() -> void:
	#refresh_cells()
#
	#if influence_controller != null:
		#if influence_controller.has_signal("influence_maps_updated"):
			#var callable: Callable = Callable(self, "_on_influence_maps_updated")
#
			#if not influence_controller.is_connected("influence_maps_updated", callable):
				#influence_controller.connect("influence_maps_updated", callable)


func setup() -> void:
	refresh_cells()

	if influence_controller != null:
		if influence_controller.has_signal("influence_maps_updated"):
			var callable: Callable = Callable(self, "_on_influence_maps_updated")

			if not influence_controller.is_connected("influence_maps_updated", callable):
				influence_controller.connect("influence_maps_updated", callable)


func _process(delta: float) -> void:
	if debug_view == DebugView.NONE:
		return

	if debug_view == DebugView.POSITION_SCORE:
		_advice_refresh_time += delta
		if _advice_refresh_time >= 0.1 or (is_instance_valid(selected_unit) and selected_unit.current_hex != _advice_origin):
			_refresh_position_advice()
	queue_redraw()


func set_selected_unit(unit: Unit) -> void:
	if not is_instance_valid(selected_unit) and unit != null:
		_view_before_selection = debug_view
		_team_before_selection = team
	selected_unit = unit
	position_advice = null
	if unit == null:
		if debug_view == DebugView.POSITION_SCORE:
			set_team(_team_before_selection)
			set_debug_view(_view_before_selection)
		return
	set_team(unit.team)
	_refresh_position_advice()
	set_debug_view(DebugView.POSITION_SCORE)


func _refresh_position_advice() -> void:
	position_advice = null
	_advice_refresh_time = 0.0
	if is_instance_valid(selected_unit):
		_advice_origin = selected_unit.current_hex
		if position_advice_provider.is_valid():
			position_advice = position_advice_provider.call(selected_unit)
		else:
			position_advice = selected_unit.position_advice
	_cache_valid = false
	if debug_view == DebugView.POSITION_SCORE:
		_debug_report_layer_access("Advice refreshed")
	queue_redraw()


func _get_position_advice() -> PositionResult:
	if not is_instance_valid(selected_unit) or selected_unit.team != team:
		return null
	if position_advice != null and position_advice.unit == selected_unit:
		return position_advice
	return selected_unit.position_advice


func set_debug_view(p_debug_view: int) -> void:
	debug_view = p_debug_view as DebugView
	_cache_valid = false
	Debug.influence_map_name = DebugViewNames[p_debug_view]
	_debug_report_layer_access("View changed")
	queue_redraw()


func set_team(p_team: int) -> void:
	team = p_team
	Debug.influence_map_team_name = Globals.TEAM_NAMES[team]
	_cache_valid = false
	_debug_report_layer_access("View changed")
	queue_redraw()


func refresh_cells() -> void:
	_cached_cells.clear()

	if tile_map_layer == null:
		return

	var used_cells: Array[Vector2i] = tile_map_layer.get_used_cells()

	for cell: Vector2i in used_cells:
		_cached_cells.append(cell)

	_cache_valid = false
	queue_redraw()


func _on_influence_maps_updated() -> void:
	_cache_valid = false
	if is_instance_valid(selected_unit):
		_refresh_position_advice()
	queue_redraw()


func _draw() -> void:
	if debug_view == DebugView.NONE:
		return

	if tile_map_layer == null:
		return

	if influence_controller == null:
		return

	var influence_map_variant: Variant = influence_controller.get_map_for_team(team)

	if influence_map_variant == null:
		return


	var influence_map: InfluenceMap = influence_map_variant as InfluenceMap

	if influence_map == null:
		return

	if _cached_cells.is_empty():
		refresh_cells()

	if auto_scale_values:
		if not _cache_valid:
			_recalculate_value_range(influence_map)

	var min_value: float = manual_min_value
	var max_value: float = manual_max_value

	if auto_scale_values:
		min_value = _cached_min_value
		max_value = _cached_max_value

	_draw_cells(influence_map, min_value, max_value)
	
	if draw_layer_access_text:
		# Keep the diagnostic legend on screen while the world camera moves/zooms.
		draw_set_transform_matrix(get_global_transform_with_canvas().affine_inverse())
		var line_position: Vector2 = Vector2(20.0, 30.0)
		for line: String in _layer_access_text.split("\n"):
			draw_string(ThemeDB.fallback_font, line_position, line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
			line_position.y += 20.0
		draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_cells(influence_map: InfluenceMap, min_value: float, max_value: float) -> void:
	var tile_size: Vector2i = tile_map_layer.tile_set.tile_size
	var radius_x: float = float(tile_size.x) * 0.5 * hex_draw_scale
	var radius_y: float = float(tile_size.y) * 0.5 * hex_draw_scale
	if debug_view == DebugView.POSITION_SCORE:
		var advice: PositionResult = _get_position_advice()
		if advice != null:
			for cell: Vector2i in advice.approach_cells:
				if influence_map.is_playable_cell(cell):
					var polygon: PackedVector2Array = _make_hex_polygon(_cell_to_local_position(cell), radius_x, radius_y)
					polygon.append(polygon[0])
					draw_polyline(polygon, Color(1.0, 0.5, 0.1, 0.65), 1.5, true)

	for cell: Vector2i in _cached_cells:
		if not _should_draw_cell(influence_map, cell):
			continue

		var value: float = _get_debug_value(influence_map, cell)
		

		var center: Vector2 = _cell_to_local_position(cell)
		var color: Color = _value_to_color(value, min_value, max_value)
		var polygon: PackedVector2Array = _make_hex_polygon(center, radius_x, radius_y)

		draw_colored_polygon(polygon, color)
		if debug_view == DebugView.POSITION_SCORE:
			var outline_color: Color = Color(0.35, 1.0, 0.5, 0.9)
			var outline_width: float = 1.5
			var advice: PositionResult = _get_position_advice()
			if advice.is_valid() and cell == advice.target_hex:
				outline_color = Color(1.0, 0.8, 0.15, 1.0)
				outline_width = 3.0
			polygon.append(polygon[0])
			draw_polyline(polygon, outline_color, outline_width, true)

		if draw_cell_values:
			_draw_value_text(center, value)


func _recalculate_value_range(influence_map: InfluenceMap) -> void:
	var found_value: bool = false
	var min_value: float = 0.0
	var max_value: float = 0.0

	for cell: Vector2i in _cached_cells:
		if not _should_draw_cell(influence_map, cell):
			continue

		var value: float = _get_debug_value(influence_map, cell)

		if not found_value:
			min_value = value
			max_value = value
			found_value = true
		else:
			if value < min_value:
				min_value = value

			if value > max_value:
				max_value = value

	if not found_value:
		min_value = 0.0
		max_value = 1.0

	if abs(max_value - min_value) <= 0.0001:
		max_value = min_value + 1.0

	_cached_min_value = min_value
	_cached_max_value = max_value
	_cache_valid = true


func _should_draw_cell(influence_map: InfluenceMap, cell: Vector2i) -> bool:
	if not influence_map.is_valid_cell(cell):
		return false
	if debug_view == DebugView.POSITION_SCORE:
		var advice: PositionResult = _get_position_advice()
		return advice != null and advice.eligibility.size() == influence_map.cell_count and advice.eligibility[influence_map.cell_to_index(cell)] != 0
	return not hide_zero_values or absf(_get_debug_value(influence_map, cell)) > zero_epsilon


func _get_debug_value(influence_map: InfluenceMap, cell: Vector2i) -> float:
	if debug_view == DebugView.POSITION_SCORE:
		var advice: PositionResult = _get_position_advice()
		if advice != null and advice.score_map.size() == influence_map.cell_count:
			return advice.score_map[influence_map.cell_to_index(cell)]
		return 0.0
	if debug_view == DebugView.COMPOSITE:
		return influence_map.get_composite_value(cell, 0.0)

	var layer_id: int = _debug_view_to_layer_id(debug_view)

	if layer_id < 0:
		return 0.0

	return influence_map.get_layer_value_by_cell(layer_id, cell, 0.0)


func _debug_view_to_layer_id(p_debug_view: int) -> int:
	if p_debug_view == DebugView.TERRAIN_COVER:
		return InfluenceMap.Layer.TERRAIN_COVER

	if p_debug_view == DebugView.TERRAIN_MOVE_COST:
		return InfluenceMap.Layer.TERRAIN_MOVE_COST

	if p_debug_view == DebugView.VISIBILITY:
		return InfluenceMap.Layer.VISIBILITY

	if p_debug_view == DebugView.FIRE_POWER:
		return InfluenceMap.Layer.FIRE_POWER
	
	if p_debug_view == DebugView.COVER_VS_ENEMY_FIRE:
		return InfluenceMap.Layer.COVER_VS_ENEMY_FIRE
	
	if p_debug_view == DebugView.VISIBILITY_HINDRANCE:
		return InfluenceMap.Layer.VISIBILITY_HINDRANCE
	
	if p_debug_view == DebugView.FORECAST_THREAT:
		return InfluenceMap.Layer.FORECAST_THREAT

	if p_debug_view == DebugView.THREAT:
		return InfluenceMap.Layer.THREAT
	
	if p_debug_view == DebugView.ENEMY_VULNERABILITY:
		return InfluenceMap.Layer.ENEMY_VULNERABILITY
	
	if p_debug_view == DebugView.HQ_SUPPORT_NEED:
		return InfluenceMap.Layer.HQ_SUPPORT_NEED
	
	if p_debug_view == DebugView.UNIT_INFLUENCE:
		return InfluenceMap.Layer.UNIT_INFLUENCE
	
	if p_debug_view == DebugView.ENEMY_VISIBILITY:
		return InfluenceMap.Layer.ENEMY_VISIBILITY
	
	#if p_debug_view == DebugView.FRIENDLY_SUPPORT:
		#return InfluenceMap.Layer.FRIENDLY_SUPPORT

	#if p_debug_view == DebugView.OBJECTIVE_PRESSURE:
		#return InfluenceMap.Layer.OBJECTIVE_PRESSURE

	#if p_debug_view == DebugView.KNOWN_ENEMY_POSITION:
		#return InfluenceMap.Layer.KNOWN_ENEMY_POSITION

	#if p_debug_view == DebugView.NO_GO:
		#return InfluenceMap.Layer.NO_GO

	return -1


func _cell_to_local_position(cell: Vector2i) -> Vector2:
	var tile_local_position: Vector2 = tile_map_layer.map_to_local(cell)
	var global_position: Vector2 = tile_map_layer.to_global(tile_local_position)
	var local_position: Vector2 = to_local(global_position)

	return local_position


func _make_hex_polygon(center: Vector2, radius_x: float, radius_y: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()

	var start_degrees: float = 0.0 #-90.0

	if flat_top_hexes:
		start_degrees = 0.0

	var index: int = 0
	while index < 6:
		var degrees: float = start_degrees + float(index) * 60.0
		var radians: float = deg_to_rad(degrees)

		var point: Vector2 = Vector2(
			center.x + cos(radians) * radius_x,
			center.y + sin(radians) * radius_y
		)

		points.append(point)
		index += 1

	return points


#func _value_to_color(value: float, min_value: float, max_value: float) -> Color:
	#var t: float = 0.0
	#var value_range: float = max_value - min_value
#
	#if abs(value_range) > 0.0001:
		#t = (value - min_value) / value_range
#
	#t = clamp(t, 0.1, 1.0)
#
	#var alpha: float = draw_alpha * t
#
	#if alpha < 0.05:
		#alpha = 0.05
#
	#var color: Color = influence_color
	#color.a = alpha
#
	#return color


func _value_to_color(value: float, min_value: float, max_value: float) -> Color:
	var t: float = 0.0
	var value_range: float = max_value - min_value
	
	#if value > 0.0 and value < 0.5:
		#pass
	
	if abs(value_range) > 0.0001:
		t = (value - min_value) / value_range

	t = clamp(t, 0.0, 1.0)

	var color: Color = Color.WHITE
	
	
	if t < 0.5:
		var local_t: float = t / 0.5
		color = low_color.lerp(mid_color, local_t)
	else:
		var local_t: float = (t - 0.5) / 0.5
		color = mid_color.lerp(high_color, local_t)

	color.a = draw_alpha
	return color


func _draw_value_text(center: Vector2, value: float) -> void:
	var viewport_transform: Transform2D = get_viewport_transform()
	var zoom_x: float = abs(viewport_transform.x.x)

	if zoom_x < value_text_min_zoom:
		return

	var font: Font = ThemeDB.fallback_font
	var font_size: int = 10
	var text: String = str(snapped(value, 0.01))
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var draw_position: Vector2 = center - text_size * 0.5

	draw_string(font, draw_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	var key_event: InputEventKey = event as InputEventKey
	
	if not key_event.pressed:
		return

	if key_event.echo:
		return

	if key_event.keycode == KEY_0:
		set_debug_view(DebugView.NONE)
		return

	if key_event.keycode == KEY_1:
		set_debug_view(DebugView.COMPOSITE)
		return

	if key_event.keycode == KEY_2:
		set_debug_view(DebugView.UNIT_INFLUENCE)
		return

	if key_event.keycode == KEY_3:
		set_debug_view(DebugView.TERRAIN_MOVE_COST)
		return

	if key_event.keycode == KEY_4:
		set_debug_view(DebugView.VISIBILITY)
		return

	#if key_event.keycode == KEY_5:
		#set_debug_view(DebugView.FIRE_POWER)
		#return
	
	if key_event.keycode == KEY_5:
		set_debug_view(DebugView.HQ_SUPPORT_NEED)
		return
	
	if key_event.keycode == KEY_6:
		set_debug_view(DebugView.COVER_VS_ENEMY_FIRE)
		return

	if key_event.keycode == KEY_7:
		set_debug_view(DebugView.VISIBILITY_HINDRANCE)
		return
	
	#if key_event.keycode == KEY_6:
		#set_debug_view(DebugView.FRIENDLY_SUPPORT)
		#return

	#if key_event.keycode == KEY_7:
		#set_debug_view(DebugView.OBJECTIVE_PRESSURE)
		#return

	if key_event.keycode == KEY_8:
		set_debug_view(DebugView.THREAT)
		return

	if key_event.keycode == KEY_9:
		set_debug_view(DebugView.ENEMY_VULNERABILITY)
		return

	if key_event.keycode == KEY_F1:
		set_debug_view(DebugView.POSITION_SCORE)
		return
	if key_event.keycode == KEY_F2:
		set_debug_view(DebugView.FORECAST_THREAT)
		return

	if key_event.keycode == KEY_TAB:
		_cycle_team()
		return


func _cycle_team() -> void:
	if team == Globals.Team.ALLIES:
		set_team(Globals.Team.AXIS)
		return

	set_team(Globals.Team.ALLIES)









# DEBUG ###############

@export var debug_probe_cell: Vector2i
@export var draw_layer_access_text: bool = true

var _layer_access_text: String = ""

func _debug_report_layer_access(reason: String) -> void:
	if influence_controller == null:
		_layer_access_text = "Influence controller missing"
		print("[InfluenceMapDebug] ", _layer_access_text)
		return

	var influence_map_variant: Variant = influence_controller.get_map_for_team(team)

	if influence_map_variant == null:
		_layer_access_text = "Map missing for team %d" % team
		print("[InfluenceMapDebug] ", _layer_access_text)
		return

	var influence_map: InfluenceMap = influence_map_variant as InfluenceMap

	if influence_map == null:
		_layer_access_text = "Selected map is not an InfluenceMap"
		print("[InfluenceMapDebug] ", _layer_access_text)
		return

	var probe_cell: Vector2i = debug_probe_cell

	if not influence_map.is_valid_cell(probe_cell):
		probe_cell = influence_map.bounds.position

	if debug_view == DebugView.COMPOSITE:
		var composite_index: int = influence_map.cell_to_index(probe_cell)
		var composite_getter_value: float = influence_map.get_composite_value(probe_cell, -999.0)
		var composite_direct_value: float = influence_map._composite[composite_index]

		_layer_access_text = (
			"%s | team=%s | map=%d | COMPOSITE | cell=%s | index=%d | getter=%.3f | direct=%.3f"
			% [
				reason,
				Globals.TEAM_NAMES[team],
				influence_map.get_instance_id(),
				probe_cell,
				composite_index,
				composite_getter_value,
				composite_direct_value
			]
		)

		print("[InfluenceMapDebug] ", _layer_access_text)
		return

	if debug_view == DebugView.POSITION_SCORE:
		_layer_access_text = "Select a unit to inspect position candidates"
		var advice: PositionResult = _get_position_advice()
		if advice != null:
			var candidate_count: int = advice.eligibility.count(1)
			_layer_access_text = "Snapshot %d | %s | %d candidates\n%s" % [advice.snapshot_version, selected_unit.name, candidate_count, advice.reason]
			if not advice.approach_cells.is_empty():
				_layer_access_text += "\nOrange: predicted approach corridor"
			if advice.is_valid():
				_layer_access_text += "\nGreen: candidate | Gold: recommended | target=%s | score=%.3f" % [advice.target_hex, advice.score]
				if advice.features.has("assigned_sector"):
					_layer_access_text += "\nSector=%d | coverage=%.0f%% | interdiction=%.2f" % [advice.features["assigned_sector"], advice.features["assigned_coverage"] * 100.0, advice.features["interdiction"]]
					if advice.features.get("responsibility") == "reserve":
						_layer_access_text += " | readiness=%.2f" % advice.features["reserve_readiness"]
		return
	var layer_id: int = _debug_view_to_layer_id(debug_view)

	if layer_id < 0:
		_layer_access_text = "Debug view has no layer mapping"
		print("[InfluenceMapDebug] ", _layer_access_text)
		return

	if layer_id >= influence_map._layers.size():
		_layer_access_text = "Layer ID outside _layers array: %d" % layer_id
		print("[InfluenceMapDebug] ", _layer_access_text)
		return

	var index: int = influence_map.cell_to_index(probe_cell)
	var direct_layer: PackedFloat32Array = influence_map._layers[layer_id]
	var copied_layer: PackedFloat32Array = influence_map.get_layer_data_copy(layer_id)

	var getter_value: float = influence_map.get_layer_value_by_cell(
		layer_id,
		probe_cell,
		-999.0
	)

	var direct_value: float = direct_layer[index]
	var copied_value: float = copied_layer[index]

	var non_zero_count: int = 0
	var layer_index: int = 0

	while layer_index < direct_layer.size():
		if direct_layer[layer_index] != 0.0:
			non_zero_count += 1

		layer_index += 1

	var values_match: bool = is_equal_approx(getter_value, direct_value)
	values_match = values_match and is_equal_approx(direct_value, copied_value)

	var match_text: String = "NO"

	if values_match:
		match_text = "YES"

	_layer_access_text = (
		"%s | team=%s | map=%d | view=%d | layer=%d | cell=%s | index=%d | getter=%.3f | direct=%.3f | copy=%.3f | match=%s | non_zero=%d"
		% [
			reason,
			Globals.TEAM_NAMES[team],
			influence_map.get_instance_id(),
			debug_view,
			layer_id,
			probe_cell,
			index,
			getter_value,
			direct_value,
			copied_value,
			match_text,
			non_zero_count
		]
	)

	print("[InfluenceMapDebug] ", _layer_access_text)
