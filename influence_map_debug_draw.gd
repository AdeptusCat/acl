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
	ORIGIN_INFLUENCE,
	#RETURN_FIRE_PENALTY,
	
	#FRIENDLY_SUPPORT,
	#OBJECTIVE_PRESSURE,
	#KNOWN_ENEMY_POSITION,
	#NO_GO
}

const DebugViewNames: Dictionary[DebugView, String] = {
	DebugView.COMPOSITE: "Composite",
	DebugView.TERRAIN_COVER: "TERRAIN_COVER",
	DebugView.TERRAIN_MOVE_COST: "TERRAIN_MOVE_COST",
	DebugView.VISIBILITY: "VISIBILITY",
	DebugView.FIRE_POWER: "FIRE_POWER",
	DebugView.COVER_VS_ENEMY_FIRE: "COVER_VS_ENEMY_FIRE",
	DebugView.VISIBILITY_HINDRANCE: "VISIBILITY_HINDRANCE",
	DebugView.THREAT: "THREAT",
	DebugView.ENEMY_VULNERABILITY: "ENEMY_VULNERABILITY",
	DebugView.ORIGIN_INFLUENCE: "ORIGIN_INFLUENCE",
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


func setup():
	refresh_cells()

	if influence_controller != null:
		if influence_controller.has_signal("influence_maps_updated"):
			var callable: Callable = Callable(self, "_on_influence_maps_updated")

			if not influence_controller.is_connected("influence_maps_updated", callable):
				influence_controller.connect("influence_maps_updated", callable)


func _process(_delta: float) -> void:
	if debug_view == DebugView.NONE:
		return

	queue_redraw()


func set_debug_view(p_debug_view: int) -> void:
	debug_view = p_debug_view as DebugView
	_cache_valid = false
	Debug.influence_map_name = DebugViewNames[p_debug_view]
	queue_redraw()


func set_team(p_team: int) -> void:
	team = p_team
	Debug.influence_map_team_name = Globals.TEAM_NAMES[team]
	_cache_valid = false
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
	queue_redraw()


func _draw() -> void:
	if debug_view == DebugView.NONE:
		return

	if tile_map_layer == null:
		return

	if influence_controller == null:
		return

	if not influence_controller.has_method("get_map_for_team"):
		return

	var influence_map_variant: Variant = influence_controller.call("get_map_for_team", team)

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


func _draw_cells(influence_map: InfluenceMap, min_value: float, max_value: float) -> void:
	var tile_size: Vector2i = tile_map_layer.tile_set.tile_size
	var radius_x: float = float(tile_size.x) * 0.5 * hex_draw_scale
	var radius_y: float = float(tile_size.y) * 0.5 * hex_draw_scale

	for cell: Vector2i in _cached_cells:
		if not influence_map.is_valid_cell(cell):
			continue

		var value: float = _get_debug_value(influence_map, cell)
		
		if selected_unit:
			var index: int = influence_map.cell_to_index(cell)
			if selected_unit.influence_map.size() > index:
				value = selected_unit.influence_map[index]

		if hide_zero_values:
			if abs(value) <= zero_epsilon:
				continue

		var center: Vector2 = _cell_to_local_position(cell)
		var color: Color = _value_to_color(value, min_value, max_value)
		var polygon: PackedVector2Array = _make_hex_polygon(center, radius_x, radius_y)

		draw_colored_polygon(polygon, color)

		if draw_cell_values:
			_draw_value_text(center, value)


func _recalculate_value_range(influence_map: InfluenceMap) -> void:
	var found_value: bool = false
	var min_value: float = 0.0
	var max_value: float = 0.0

	for cell: Vector2i in _cached_cells:
		if not influence_map.is_valid_cell(cell):
			continue

		var value: float = _get_debug_value(influence_map, cell)

		if hide_zero_values:
			if abs(value) <= zero_epsilon:
				continue

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


func _get_debug_value(influence_map: InfluenceMap, cell: Vector2i) -> float:
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
	
	if p_debug_view == DebugView.THREAT:
		return InfluenceMap.Layer.THREAT
	
	if p_debug_view == DebugView.ENEMY_VULNERABILITY:
		return InfluenceMap.Layer.ENEMY_VULNERABILITY
	
	if p_debug_view == DebugView.ORIGIN_INFLUENCE:
		return InfluenceMap.Layer.ORIGIN_INFLUENCE

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
		set_debug_view(DebugView.ORIGIN_INFLUENCE)
		return

	if key_event.keycode == KEY_3:
		set_debug_view(DebugView.TERRAIN_MOVE_COST)
		return

	if key_event.keycode == KEY_4:
		set_debug_view(DebugView.VISIBILITY)
		return

	if key_event.keycode == KEY_5:
		set_debug_view(DebugView.FIRE_POWER)
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

	if key_event.keycode == KEY_TAB:
		_cycle_team()
		return


func _cycle_team() -> void:
	if team == Globals.Team.ALLIES:
		set_team(Globals.Team.AXIS)
		return

	set_team(Globals.Team.ALLIES)
