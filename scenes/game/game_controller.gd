extends Node2D

@onready var input_mgr      = $InputManager
@onready var unit_container = $UnitContainer
@onready var move_sys       = $MovementSystem
@onready var combat_sys     = $CombatSystem
@onready var los_renderer   = $LOSRenderer
@onready var camera 		= $Camera2D

@export var allies_objective_tilemap : TileMapLayer
@export var axis_objective_tilemap : TileMapLayer
@export var ground_layer : HexagonTileMapLayer
@export var fog_of_war_layer : HexagonTileMapLayer
@export var glow_maker_scene: PackedScene

var objective_hex : Vector2i = Vector2.ZERO
@export var time_left_seconds: float = 120.0  
var timer_running := false

var selected_unit: Node2D = null
var units: Array[Node2D] = []
var unit_visible_enemies: Dictionary


signal update_timer_label(time_left_seconds: float)
signal show_winner(team: int)
signal set_objective_text(hex: String)
signal mouse_event_position_changed(event_pos)


var point_array: Array[Vector2]
var threat_weights = {}

func draw_points(_point_array):
	point_array = _point_array
	queue_redraw()
func _draw():
	#for point in point_array:
		##draw_line(point, point, Color(1, 0, 0), 2.0)
		#draw_circle(point, 5.0, Color.RED)
	if threat_weights.is_empty():
		return
		
	var weights = threat_weights.values()
	var min_weight = weights.min()
	var max_weight = weights.max()

	for hex in threat_weights:
		var norm = _normalize_weight(threat_weights[hex], min_weight, max_weight)
		var color = Color(1, 1 - norm, 0)  # Red to Green
		var pos = ground_layer.map_to_local(hex) #+ Vector2(32, 32)
		draw_circle(pos, 4, color)
		
func _normalize_weight(w, min_w, max_w):
	if max_w == min_w:
		return 0.0
	return clamp((w - min_w) / (max_w - min_w), 0.0, 1.0)
	
func draw_threat(_threat_weights: Dictionary[int, Dictionary]):
	return #debug
	threat_weights = _threat_weights[Globals.team_player]
	queue_redraw()

func _ready():
	input_mgr.mouse_button_left_pressed.connect(_on_mouse_button_left_pressed)
	input_mgr.mouse_button_right_pressed.connect(_on_mouse_button_right_pressed)
	input_mgr.key_space_pressed.connect(_on_key_space_pressed)
	input_mgr.zoom_in.connect(_on_zoom_in)
	input_mgr.zoom_out.connect(_on_zoom_out)
	#camera.camera_moved.connect(_on_camera_moved)
	#combat_sys.visibility_changed.connect(los_renderer._on_visibility_changed)
	#for child in $"../UnitManager".get_children():
		#child.unit_arrived_at_hex.connect(move_sys._on_arrived)
	for unit in get_tree().get_nodes_in_group("units"):
		if unit is Node2D:
			units.append(unit)
			unit.units = units
			unit.unit_died.connect(_on_unit_died)
			unit.moved_to_hex.connect(combat_sys._on_unit_moved)
			unit.moved_to_hex.connect(_on_unit_moved)
			unit.unit_arrived_at_hex.connect(move_sys._on_arrived)
			unit.current_hex = ground_layer.local_to_map(unit.global_position)
			unit.current_cube = ground_layer.map_to_cube(unit.current_hex)
			unit.deselect_unit.connect(_deselect_unit)
			unit.started_moving.connect(_on_started_moving)
			unit.unit_surrendered.connect(_on_unit_surrendered)
			unit.squad_fire.unit_visible_enemies = unit_visible_enemies
			
	combat_sys.unit_visible_enemies = unit_visible_enemies
	combat_sys.units = units
	move_sys.unit_visible_enemies = unit_visible_enemies
	move_sys.units = units
	combat_sys.draw_los_to_enemy.connect(los_renderer._on_draw_los_to_enemy)
	update_timer_label.emit(time_left_seconds)
	input_mgr.mouse_event_position_changed.connect(_on_mouse_event_position_changed)
	input_mgr.set_input(false)
	
	var map_size : Vector2 = Vector2(ground_layer.tile_set.tile_size) * Vector2(LOSHelper.GRID_SIZE_X, LOSHelper.GRID_SIZE_Y)
	camera.set_camera_limit(map_size) 
	
	#for x in range(LOSHelper.GRID_SIZE_X):
		#for y in range(LOSHelper.GRID_SIZE_Y):
			#fog_of_war_layer.set_cell(Vector2i(x, y), 0)
	
	#fog_of_war_layer.set_cell(Vector2i(1, 1), 0)
	#fog_of_war_layer.set_cell(tile_map_layer, new_tile_map_cell_position, tile_map_cell_source_id, tile_map_cell_atlas_coords, tile_map_cell_alternative)
	
	
	
func draw_fog():
	var used_cells := fog_of_war_layer.get_used_cells()
	for cell in used_cells:
		if LOSHelper.visible_hexes[Globals.team_player].has(cell):
			fog_of_war_layer.set_cell(cell, -1, Vector2i(0, 0))  # Clear fog
		else:
			fog_of_war_layer.set_cell(cell, 0, Vector2i(0, 0))  # Set fog tile with ID 1
	for x in LOSHelper.GRID_SIZE_X:
		for y in LOSHelper.GRID_SIZE_Y:
			if not LOSHelper.visible_hexes[Globals.team_player].has(Vector2i(x, y)):
				fog_of_war_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0)) 


func show_visible_units():
	for u in units:
		if not u.team == Globals.team_player:
			if LOSHelper.visible_hexes[Globals.team_player].has(u.current_hex):
				u.visible = true
			else:
				u.visible = false 


func update_visible_hexes():
	for array in LOSHelper.visible_hexes.values():
		array.clear()
	for u in units:
		var unit_visible = LOSHelper.los_lookup.get(u.current_hex, [])
		for hex in unit_visible:
			if not LOSHelper.visible_hexes[u.team].has(hex):
				LOSHelper.visible_hexes[u.team].append(hex)
		if not LOSHelper.visible_hexes[u.team].has(u.current_hex):
			LOSHelper.visible_hexes[u.team].append(u.current_hex)


func _on_unit_moved(unit, vector: Vector2i):
	update_visible_hexes()
	show_visible_units()
	draw_fog()
	
	var map_hex: Vector2i = ground_layer.local_to_map(get_local_mouse_position())
	var _units: Array
	for _unit in units:
		if _unit.current_hex == map_hex: 
			_units.append(_unit)
	get_parent().ui.show_unit_data(map_hex, _units)
	#for x in range(LOSHelper.GRID_SIZE_X):
		#for y in range(LOSHelper.GRID_SIZE_Y):
			#fog_of_war_layer.set_cell(Vector2(x, y), -1)
	
	#
	#LOSHelper.GRID_SIZE_Y
	#var visible_hexes: Array
	#for u in units:
		#if u.team == current_team:
			#var visible_hexes_from_unit = LOSHelper.los_lookup.get(unit.current_hex, [])
			

func setup_game():
	
	set_objective_text.emit("")
	for unit in unit_container.get_children():
		unit.visible = false


func set_objective_cells(team: int): 
	var objective_tilemap: TileMapLayer
	if team == 0:
		objective_tilemap = axis_objective_tilemap
		axis_objective_tilemap.visible = true
		allies_objective_tilemap.visible = false
	else:
		objective_tilemap = allies_objective_tilemap
		axis_objective_tilemap.visible = false
		allies_objective_tilemap.visible = true
	var cells = objective_tilemap.get_used_cells() 
	if cells.size() > 0:
		objective_hex = cells[0]
	else:
		push_error("ObjectiveTileMapLayer has no tiles placed!")


func _on_mouse_button_right_pressed(event_pos: Vector2):
	event_pos = get_local_mouse_position()
	var map_hex = ground_layer.local_to_map(event_pos)
	
	if selected_unit:
		var units: Array[Node2D] = _find_units_at(map_hex)
		for unit in units:
			if not unit.team == Globals.team_player:
				selected_unit.combat.set_target_unit(unit)
				var local_pos = ground_layer.map_to_local(map_hex)
				hex_glow(local_pos)
				return
		move_sys._on_move_requested(selected_unit, map_hex)
		#_deselect_unit(selected_unit)
		var local_pos = ground_layer.map_to_local(map_hex)
		hex_glow(local_pos)
	


var previous_selected_hex: Vector2i = Vector2i(-1, -1)
var selected_hex_index: int = 0


func _on_mouse_button_left_pressed(event_pos: Vector2):
	event_pos = get_local_mouse_position()
	var map_hex = ground_layer.local_to_map(event_pos)
	if previous_selected_hex == map_hex:
		selected_hex_index += 1
	else:
		previous_selected_hex = map_hex
		selected_hex_index = 0
	var units: Array[Node2D] = _find_units_at(map_hex)
	if units.is_empty():
		if not selected_unit == null:
			_deselect_unit(selected_unit)
		return
	if selected_hex_index >= units.size():
		selected_hex_index = 0
	var unit = units[selected_hex_index]
	if unit and unit.team == Globals.team_player and not unit.broken and not unit.surrendered:
		if unit == selected_unit:
			_deselect_unit(unit)
		else:
			_select_unit(unit)
			LOSHelper.clear_los()


var origin_hex 
var target_hex
var targetCover
var distance
var firepower
func _on_mouse_event_position_changed(event_pos: Vector2):
	return
	mouse_event_position_changed.emit(event_pos)
	if selected_unit:
		var unit_pos = selected_unit.position
		var local_event_pos = get_local_mouse_position()
		LOSHelper.draw_los(unit_pos, local_event_pos)
		
		var screen_pos = get_viewport().get_mouse_position()
		if (target_hex == LOSHelper.ground_layer.local_to_map(local_event_pos) and origin_hex == selected_unit.current_hex):
			get_parent().ui.show_target_hex_cover_distance(screen_pos, targetCover, distance, firepower)
		else:
			origin_hex = selected_unit.current_hex
			target_hex = LOSHelper.ground_layer.local_to_map(local_event_pos)
			distance = int(origin_hex.distance_to(target_hex))
			# safely grab the inner dict for this shooter-hex
			var cover_map = LOSHelper.los_lookup.get(origin_hex, null)
			if cover_map and cover_map.has(target_hex):
				var data        = cover_map[target_hex]
				targetCover 	= data["target_cover"]
			else:
				targetCover = 0  # no LOS or no cover entry
				get_parent().ui.hide_target_hex_cover_distance()
				target_hex = null
				origin_hex = null
				return
			# now display it
			firepower = selected_unit.firepower
			if distance > selected_unit.range:
				if distance <= selected_unit.range * 2:
					firepower = firepower / 2
				else:
					firepower = 0
			
			get_parent().ui.show_target_hex_cover_distance(screen_pos, targetCover, distance, firepower)
			#selected_unit.set_cover(targetCover)
			#enemy_unit.fire_at(unit, distance, targetCover, unit_visible_enemies)
	else:
		get_parent().ui.hide_target_hex_cover_distance()


func handle_mouse_event_position_changed(event_pos: Vector2):
	mouse_event_position_changed.emit(event_pos)
	if selected_unit:
		var unit_pos = selected_unit.position
		var local_event_pos = get_local_mouse_position()
		LOSHelper.draw_los(unit_pos, local_event_pos)
		
		var screen_pos = get_viewport().get_mouse_position()
		if (target_hex == LOSHelper.ground_layer.local_to_map(local_event_pos) and origin_hex == selected_unit.current_hex):
			get_parent().ui.show_target_hex_cover_distance(screen_pos, targetCover, distance, firepower)
		else:
			origin_hex = selected_unit.current_hex
			target_hex = LOSHelper.ground_layer.local_to_map(local_event_pos)
			distance = int(origin_hex.distance_to(target_hex))
			# safely grab the inner dict for this shooter-hex
			var cover_map = LOSHelper.los_lookup.get(origin_hex, null)
			if cover_map and cover_map.has(target_hex):
				var data        = cover_map[target_hex]
				targetCover 	= data["target_cover"]
			else:
				targetCover = 0  # no LOS or no cover entry
				get_parent().ui.hide_target_hex_cover_distance()
				target_hex = null
				origin_hex = null
				return
			# now display it
			firepower = selected_unit.firepower
			if distance > selected_unit.range:
				if distance <= selected_unit.range * 2:
					firepower = firepower / 2
				else:
					firepower = 0
			
			get_parent().ui.show_target_hex_cover_distance(screen_pos, targetCover, distance, firepower)
			#selected_unit.set_cover(targetCover)
			#enemy_unit.fire_at(unit, distance, targetCover, unit_visible_enemies)
	else:
		get_parent().ui.hide_target_hex_cover_distance()


#var last_mouse_position: Vector2
#func _on_camera_moved():
	#var pos = get_local_mouse_position()
	#if abs(pos.x - last_mouse_position.x) > 1 or abs(pos.y - last_mouse_position.y) > 1:
		#handle_mouse_event_position_changed(pos)
		#last_mouse_position = pos


func hex_glow(pos: Vector2):
	var glow = glow_maker_scene.instantiate()
	glow.position = pos
	add_child(glow)


func _on_key_space_pressed(event_pos: Vector2):
	pass


func _select_unit(unit):
	if selected_unit:
		selected_unit.deselect()
	selected_unit = unit
	unit.select()


func _deselect_unit(unit):
	if selected_unit == unit:
		selected_unit.deselect()
		selected_unit = null
		LOSHelper.clear_los()


func _find_units_at(hex: Vector2i) -> Array[Node2D]:
	var units: Array[Node2D]
	for u in unit_container.get_children():
		if u.current_hex == hex:
			units.append(u)
	return units


func _on_unit_surrendered(unit):
	pass


func _on_unit_died(unit):
	units.erase(unit)
	unit_visible_enemies.erase(unit)
	update_visible_hexes()
	show_visible_units()
	draw_fog()
	#unit.queue_free()


func start_game(team: int, time: float):
	time_left_seconds = time * 60.0
	set_objective_cells(team)
	#timer_running = true
	Globals.team_player = team
	input_mgr.set_input(true)
	
	var i_team_0: int = 0
	var i_team_1: int = 0
	for unit in unit_container.get_children():
		if unit.team == Globals.team_player:
			unit.visible = true
		if unit.team == Globals.team_player:
			unit.ui.set_unit_designation(index_to_char(i_team_0))
			i_team_0 += 1
		else:
			unit.ui.set_unit_designation(index_to_char(i_team_1))
			i_team_1 += 1
			
	update_visible_hexes()
	draw_fog()
	show_visible_units()


func index_to_char(i: int) -> String:
	var char_code: int = ord("A") + i
	return String.chr(char_code)


func _on_started_moving():
	timer_running = true

var last_unit_hex: Vector2i
var last_mouse_position: Vector2
func _process(delta):
	if timer_running:
		time_left_seconds -= delta
		if time_left_seconds <= 0:
			time_left_seconds = 0
			timer_running = false
			end_game_check()
		update_timer_label.emit(time_left_seconds)
	
	var mouse_or_unit_position_changed: bool = false
	var pos = get_local_mouse_position()
	if abs(pos.x - last_mouse_position.x) > 1 or abs(pos.y - last_mouse_position.y) > 1:
		mouse_or_unit_position_changed = true
		last_mouse_position = pos
	if selected_unit:
		if not selected_unit.current_hex == last_unit_hex:
			mouse_or_unit_position_changed = true
			last_unit_hex = selected_unit.current_hex
	if mouse_or_unit_position_changed:
		handle_mouse_event_position_changed(pos)


func end_game_check():
	var occupying_units : Array
	for unit in unit_container.get_children():
		if unit.current_hex == objective_hex:
			occupying_units.append(unit)
	for unit in occupying_units:
		if not unit.broken:
			show_winner.emit(unit.team)
			return
	show_winner.emit(-1)


func _on_zoom_in():
	camera.zoom_in()


func _on_zoom_out():
	camera.zoom_out()
