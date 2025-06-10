extends Node2D

@onready var input_mgr      = $InputManager
@onready var unit_container = $UnitContainer
@onready var move_sys       = $MovementSystem
@onready var combat_sys     = $CombatSystem
@onready var los_renderer   = $LOSRenderer

@export var objective_tilemap : TileMapLayer
@export var ground_layer : HexagonTileMapLayer
@export var fog_of_war_layer : HexagonTileMapLayer

var objective_hex : Vector2i = Vector2.ZERO
@export var time_left_seconds: float = 120.0  
var timer_running := false

var current_team: int = 0
var selected_unit: Node2D = null
var units: Array[Node2D] = []
var unit_visible_enemies: Dictionary
var mouse_hover_hex: Vector2i

signal update_timer_label(time_left_seconds: float)
signal show_winner(team: int)
signal set_objective_text(hex: String)
signal mouse_event_position_changed(event_pos)


func _ready():
	input_mgr.mouse_button_left_pressed.connect(_on_mouse_button_left_pressed)
	input_mgr.key_space_pressed.connect(_on_key_space_pressed)
	#combat_sys.visibility_changed.connect(los_renderer._on_visibility_changed)
	#for child in $"../UnitManager".get_children():
		#child.unit_arrived_at_hex.connect(move_sys._on_arrived)
	for unit in get_tree().get_nodes_in_group("units"):
		if unit is Node2D:
			units.append(unit)
			unit.unit_died.connect(_on_unit_died)
			unit.moved_to_hex.connect(combat_sys._on_unit_moved)
			unit.moved_to_hex.connect(_on_unit_moved)
			unit.unit_arrived_at_hex.connect(move_sys._on_arrived)
			unit.current_hex = ground_layer.local_to_map(unit.global_position)
			unit.deselect_unit.connect(_deselect_unit)
			
	combat_sys.unit_visible_enemies = unit_visible_enemies
	combat_sys.units = units
	move_sys.unit_visible_enemies = unit_visible_enemies
	move_sys.units = units
	combat_sys.draw_los_to_enemy.connect(los_renderer._on_draw_los_to_enemy)
	update_timer_label.emit(time_left_seconds)
	input_mgr.mouse_event_position_changed.connect(_on_mouse_event_position_changed)
	input_mgr.set_input(false)
	
	#for x in range(LOSHelper.GRID_SIZE_X):
		#for y in range(LOSHelper.GRID_SIZE_Y):
			#fog_of_war_layer.set_cell(Vector2i(x, y), 0)
	
	#fog_of_war_layer.set_cell(Vector2i(1, 1), 0)
	#fog_of_war_layer.set_cell(tile_map_layer, new_tile_map_cell_position, tile_map_cell_source_id, tile_map_cell_atlas_coords, tile_map_cell_alternative)
	
	
	
func draw_fog():
	var used_cells := fog_of_war_layer.get_used_cells()
	for cell in used_cells:
		if LOSHelper.visible_hexes.has(cell):
			fog_of_war_layer.set_cell(cell, -1, Vector2i(0, 0))  # Clear fog
		else:
			fog_of_war_layer.set_cell(cell, 0, Vector2i(0, 0))  # Set fog tile with ID 1
	for x in LOSHelper.GRID_SIZE_X:
		for y in LOSHelper.GRID_SIZE_Y:
			if not LOSHelper.visible_hexes.has(Vector2i(x, y)):
				fog_of_war_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0)) 


func show_visible_units():
	for u in units:
		if not u.team == current_team:
			if LOSHelper.visible_hexes.has(u.current_hex):
				u.visible = true
			else:
				u.visible = false 


func update_visible_hexes():
	LOSHelper.visible_hexes.clear()
	for u in units:
		if u.team == current_team:
			var unit_visible = LOSHelper.los_lookup.get(u.current_hex, [])
			for hex in unit_visible:
				if not LOSHelper.visible_hexes.has(hex):
					LOSHelper.visible_hexes.append(hex)
			if not LOSHelper.visible_hexes.has(u.current_hex):
				LOSHelper.visible_hexes.append(u.current_hex)

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
	set_objective_cells()
	set_objective_text.emit(str(objective_hex))


func set_objective_cells(): 
	var cells = objective_tilemap.get_used_cells()  # 0 = layer index
	if cells.size() > 0:
		objective_hex = cells[0]
	else:
		push_error("ObjectiveTileMapLayer has no tiles placed!")


func _on_mouse_button_left_pressed(event_pos: Vector2):
	var map_hex = ground_layer.local_to_map(event_pos)
	var unit = _find_unit_at(map_hex)
	if unit and unit.team == current_team and not unit.broken:
		if selected_unit == unit:
			_deselect_unit(unit)
		else:
			_select_unit(unit)
	elif selected_unit:
		move_sys._on_move_requested(selected_unit, map_hex)
		_deselect_unit(selected_unit)


func _on_mouse_event_position_changed(event_pos: Vector2):
	var map_hex = ground_layer.local_to_map(event_pos)
	if not map_hex == mouse_hover_hex:
		mouse_hover_hex = map_hex
		mouse_event_position_changed.emit(event_pos)


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


func _find_unit_at(hex: Vector2i) -> Node2D:
	for u in unit_container.get_children():
		if u.current_hex == hex:
			return u
	return null


func _on_unit_died(unit):
	units.erase(unit)
	unit_visible_enemies.erase(unit)
	#unit.queue_free()


func start_game(team: int):
	timer_running = true
	current_team = team
	input_mgr.set_input(true)


func _process(delta):
	if timer_running:
		time_left_seconds -= delta
		if time_left_seconds <= 0:
			time_left_seconds = 0
			timer_running = false
			end_game_check()
		update_timer_label.emit(time_left_seconds)


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
