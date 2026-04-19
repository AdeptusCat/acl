extends Node2D

# --- SETUP ---
@onready var tile_map_layers: Node2D = $TileMapLayers

#@onready var ground_layer : HexagonTileMapLayer = $TileMapLayers/GroundTileMapLayer
#@onready var building_layer : HexagonTileMapLayer = $TileMapLayers/BuildingTileMapLayer
#@onready var wall_layer : HexagonTileMapLayer = $TileMapLayers/WallTileMapLayer
#@onready var terrain_layer : HexagonTileMapLayer = $TileMapLayers/TerrainTileMapLayer
@onready var selected_hex_layer : HexagonTileMapLayer = $TileMapLayers/SelectedTileMapLayer
@onready var result_screen := $ResultScreen
@onready var start_screen := $StartScreen
@onready var ui := $Ui
@onready var game_controller := $GameController
@onready var target_area := $TargetArea
@onready var input_manager := $InputManager

@onready var map_1: Map = $Map1

signal try_again
signal fully_freed

var ground_layer: HexagonTileMapLayer
var terrain_layer : HexagonTileMapLayer 
var wall_layer : HexagonTileMapLayer
var building_layer : HexagonTileMapLayer
var mouse_hover_hex: Vector2i

var scenario: Scenario

func _exit_tree():
	fully_freed.emit()

func _ready():
	ground_layer = map_1.get_ground_layer()
	terrain_layer = map_1.get_terrain_layer()
	wall_layer = map_1.get_wall_layer()
	building_layer = map_1.get_building_layer()
	scenario = map_1.get_scenario(0)
	
	LOSHelper.ground_layer = map_1.get_ground_layer()
	LOSHelper.building_layer = map_1.get_building_layer()
	LOSHelper.wall_layer = map_1.get_wall_layer()
	LOSHelper.terrain_layer = map_1.get_terrain_layer()
	game_controller.ground_layer = map_1.get_ground_layer()
	ui.ground_layer = map_1.get_ground_layer()
	ui.setup()
	ui.show()
	
	var layers: Array[Node] = map_1.get_tilemap_layers()
	for layer in layers:
		layer.reparent(tile_map_layers)
	
	var units: Array[Node] = scenario.get_units()
	for unit in units:
		unit.setup()
		unit.add_to_group("units")
		unit.reparent(game_controller.unit_container)
	
	game_controller.setup()
	
	#LOSHelper.ground_layer = ground_layer  # <-- inject the TileMap
	#LOSHelper.building_layer = building_layer  # <-- inject the TileMap
	#LOSHelper.wall_layer = wall_layer  # <-- inject the TileMap
	#LOSHelper.terrain_layer = terrain_layer
	Globals.astars[Globals.Team.AXIS] = copy_astar(LOSHelper.ground_layer.astar)
	Globals.astars[Globals.Team.ALLIES] = copy_astar(LOSHelper.ground_layer.astar)
	await get_tree().process_frame
	#LOSHelper.prebake_los()
	#LOSHelper.bake_and_save_los_data("res://scenes/game/los/los_data.tres")
	LOSHelper.load_prebaked_los("res://scenes/game/los/los_data.tres")
	
	game_controller.mouse_event_position_changed.connect(_on_mouse_event_position_changed)
	start_screen.game_started.connect(_on_game_started)
	game_controller.update_timer_label.connect(ui._on_update_timer_label)
	game_controller.game_started_through_moving_unit.connect(ui._on_game_started_through_moving_unit)
	game_controller.show_unit_details_in_ui.connect(ui._on_show_unit_details)
	game_controller.hide_unit_details_in_ui.connect(ui._on_hide_unit_details)
	game_controller.show_winner.connect(result_screen._on_show_winner)
	game_controller.set_objective_text.connect(start_screen._on_set_objective_text)
	game_controller.hex_selected.connect(_on_hex_selected)
	
	game_controller.setup_game()
	
	#var origin_pos = ground_layer.map_to_local(Vector2i(3, 4))
	#var target_pos = ground_layer.map_to_local(Vector2i(7, 4))
	#var res = LOSHelper.check_los(origin_pos, target_pos, 0, 0, 0, 0)
	#pass
	
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(0,0))
	#var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(2,3))
	#14,2 10,2
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(1,1))
	#var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(3,4))

	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(2,3))
	#var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(0,0))
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(11,0))
	#var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(8,2))
	
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(0,0))
	#var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(2,3))
	#LOSHelper.check_los(pos_a, pos_b, 0, 0, 0, 0)
	
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(4,4))
	#var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(6,3))
	#var res = LOSHelper.check_los(pos_a, pos_b, 0, 0, 0, 0)
	#print(res)
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(0,1))
	#LOSHelper.get_tile_local_pixel_coords(pos_a, building_layer)

var selected_hex: Vector2i 

func _on_hex_selected(map_hex: Vector2i, event_pos: Vector2):
	if map_hex == selected_hex:
		return
	selected_hex_layer.set_cell(selected_hex, -1, Vector2i(0, 0))  # Clear selected cell
	selected_hex = map_hex
	selected_hex_layer.set_cell(selected_hex, 0, Vector2i(0, 0))  # Set selected tile with ID 1
	calc_unit_data_for_ui(event_pos)


func copy_astar(source: AStar2D) -> AStar2D:
	var copy := AStar2D.new()

	# Step 1: Copy all points
	for id in source.get_point_ids():
		var pos = source.get_point_position(id)
		var weight = source.get_point_weight_scale(id)
		var disabled = source.is_point_disabled(id)
		copy.add_point(id, pos, weight)
		copy.set_point_disabled(id, disabled)

	# Step 2: Copy connections
	for id in source.get_point_ids():
		for neighbor in source.get_point_connections(id):
			# Avoid duplicate connections (only add if id < neighbor)
			if id < neighbor:
				copy.connect_points(id, neighbor)

	return copy


func _on_mouse_event_position_changed(_event_pos: Vector2):
	return
	#event_pos = get_local_mouse_position()
	#var map_hex = ground_layer.local_to_map(event_pos)
	#if not map_hex == mouse_hover_hex:
		#mouse_hover_hex = map_hex
		#calc_unit_data_for_ui(event_pos)


func calc_unit_data_for_ui(event_pos: Vector2):
	event_pos = get_local_mouse_position()
	var result = {
		"blocking" : false,
		"hindrance": false,
		"cover_in_hex" : 0,
		"cover_n" : 0,
		"cover_ne" : 0,
		"cover_se" : 0,
		"cover_s" : 0,
		"cover_sw" : 0,
		"cover_nw" : 0,
		"ground_texture": null,
		"wall_texture": null,
		"building_texture": null,
		"terrain_texture": null,
		"ground_texture_transform": null,
		"wall_texture_transform": null,
		"building_texture_transform": null,
		"terrain_texture_transform": null,
		"wall_n_texture": null,
		"wall_n_texture_transform": null,
		"wall_ne_texture": null,
		"wall_ne_texture_transform": null,
		"wall_se_texture": null,
		"wall_se_texture_transform": null,
		"wall_s_texture": null,
		"wall_s_texture_transform": null,
		"wall_sw_texture": null,
		"wall_sw_texture_transform": null,
		"wall_nw_texture": null,
		"wall_nw_texture_transform": null,
		"tile_name": "",
		"hex_wall_name": "",
	}
	result.cover_in_hex = LOSHelper.is_sample_point_in_building(event_pos)
	result.tile_name = LOSHelper.get_tile_name(event_pos)
	if result.cover_in_hex > 0:
		result.blocking = true
	result.cover_n = get_wall_cover(event_pos, TileSet.CellNeighbor.CELL_NEIGHBOR_TOP_SIDE)
	result.cover_ne = get_wall_cover(event_pos, TileSet.CellNeighbor.CELL_NEIGHBOR_TOP_RIGHT_SIDE)
	result.cover_se = get_wall_cover(event_pos, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE)
	result.cover_s = get_wall_cover(event_pos, TileSet.CellNeighbor.CELL_NEIGHBOR_BOTTOM_SIDE)
	result.cover_sw = get_wall_cover(event_pos, TileSet.CellNeighbor.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE)
	result.cover_nw = get_wall_cover(event_pos, TileSet.CellNeighbor.CELL_NEIGHBOR_TOP_LEFT_SIDE)
	
	var map_hex: Vector2i = ground_layer.local_to_map(event_pos)
	
	var tile_data_hindrance: TileData = terrain_layer.get_cell_tile_data(map_hex)
	if tile_data_hindrance and tile_data_hindrance.has_custom_data("hindrance") \
	   and tile_data_hindrance.get_custom_data("hindrance"):
		result["hindrance"] = true
	
	
	
	result.ground_texture = get_tilemaplayer_texture(map_hex, ground_layer)
	result.ground_texture_transform = get_tilemaplayer_texture_transform(map_hex, ground_layer)
	result.wall_texture = get_tilemaplayer_texture(map_hex, wall_layer)
	result.wall_texture_transform = get_tilemaplayer_texture_transform(map_hex, wall_layer)
	
	var map_cube : Vector3i = ground_layer.map_to_cube(map_hex)
	var map_n_cube : Vector3i = map_cube + ground_layer.cube_direction(TileSet.CellNeighbor.CELL_NEIGHBOR_TOP_SIDE)
	var map_n_hex : Vector2i = ground_layer.cube_to_map(map_n_cube)
	result.wall_n_texture = get_tilemaplayer_texture(map_n_hex, wall_layer)
	result.wall_n_texture_transform = get_tilemaplayer_texture_transform(map_n_hex, wall_layer)
	var map_ne_cube : Vector3i = map_cube + ground_layer.cube_direction(TileSet.CellNeighbor.CELL_NEIGHBOR_TOP_RIGHT_SIDE)
	var map_ne_hex : Vector2i = ground_layer.cube_to_map(map_ne_cube)
	result.wall_ne_texture = get_tilemaplayer_texture(map_ne_hex, wall_layer)
	result.wall_ne_texture_transform = get_tilemaplayer_texture_transform(map_ne_hex, wall_layer)
	var map_se_cube : Vector3i = map_cube + ground_layer.cube_direction(TileSet.CellNeighbor.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE)
	var map_se_hex : Vector2i = ground_layer.cube_to_map(map_se_cube)
	result.wall_se_texture = get_tilemaplayer_texture(map_se_hex, wall_layer)
	result.wall_se_texture_transform = get_tilemaplayer_texture_transform(map_se_hex, wall_layer)
	var map_s_cube : Vector3i = map_cube + ground_layer.cube_direction(TileSet.CellNeighbor.CELL_NEIGHBOR_BOTTOM_SIDE)
	var map_s_hex : Vector2i = ground_layer.cube_to_map(map_s_cube)
	result.wall_s_texture = get_tilemaplayer_texture(map_s_hex, wall_layer)
	result.wall_s_texture_transform = get_tilemaplayer_texture_transform(map_s_hex, wall_layer)
	var map_sw_cube : Vector3i = map_cube + ground_layer.cube_direction(TileSet.CellNeighbor.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE)
	var map_sw_hex : Vector2i = ground_layer.cube_to_map(map_sw_cube)
	result.wall_sw_texture = get_tilemaplayer_texture(map_sw_hex, wall_layer)
	result.wall_sw_texture_transform = get_tilemaplayer_texture_transform(map_sw_hex, wall_layer)
	var map_nw_cube : Vector3i = map_cube + ground_layer.cube_direction(TileSet.CellNeighbor.CELL_NEIGHBOR_TOP_LEFT_SIDE)
	var map_nw_hex : Vector2i = ground_layer.cube_to_map(map_nw_cube)
	result.wall_nw_texture = get_tilemaplayer_texture(map_nw_hex, wall_layer)
	result.wall_nw_texture_transform = get_tilemaplayer_texture_transform(map_nw_hex, wall_layer)
	
	result.building_texture = get_tilemaplayer_texture(map_hex, building_layer)
	result.building_texture_transform = get_tilemaplayer_texture_transform(map_hex, building_layer)
	result.terrain_texture = get_tilemaplayer_texture(map_hex, terrain_layer)
	result.terrain_texture_transform = get_tilemaplayer_texture_transform(map_hex, terrain_layer)
	ui.show_tile_data(result)
	
	# legacy code that shows unit details
	#var units: Array
	#for unit in game_controller.units:
		#if unit.current_hex == map_hex: 
			#units.append(unit)
	#ui.show_unit_data(map_hex, units)

func get_tilemaplayer_texture_transform(map_hex: Vector2i, tilemaplayer):
	var tile_data: TileData = tilemaplayer.get_cell_tile_data(map_hex)
	if not tile_data:
		return Transform2D.IDENTITY

	var flip_h = tile_data.get_flip_h()
	var flip_v = tile_data.get_flip_v()
	var transpose = tile_data.get_transpose()

	var basis_x = Vector2(1, 0)
	var basis_y = Vector2(0, 1)

	# Apply transpose: swap axes
	if transpose:
		var temp = basis_x
		basis_x = basis_y
		basis_y = temp
		# Also swap meaning of flip_h and flip_v
		var temp_flip = flip_h
		flip_h = flip_v
		flip_v = temp_flip

	# Apply flips in the correct (possibly transposed) axes
	if flip_h:
		basis_x *= -1
	if flip_v:
		basis_y *= -1

	return Transform2D(basis_x, basis_y, Vector2.ZERO)

func get_tilemaplayer_texture(map_hex: Vector2i, tilemaplayer):
	var tile_id = tilemaplayer.get_cell_source_id(map_hex)
	var texture: Texture
	if not tile_id == -1:
		var tileset = tilemaplayer.tile_set
		texture = tileset.get_source(tile_id).texture
	return texture


func get_wall_cover(event_pos: Vector2, direction_index: int):
	var hex_cube = building_layer.local_to_cube(event_pos)
	var top_cube = ground_layer.cube_direction(direction_index)
	var hex_cube_top = hex_cube + top_cube
	var top_pos = ground_layer.cube_to_local(hex_cube_top)
	var res = LOSHelper.check_los(event_pos, top_pos, 0, 0, 0, 0)
	return res.wall_cover


func _on_game_started(team : int, game_mode: Globals.GameMode):
	Globals.game_mode = game_mode
	target_area.hide()
	var objectives: Array[Node] = scenario.get_objectives(team)
	game_controller.set_objective_layer(team, objectives[0])
	map_1.remove_scenarios()
	Globals.reset()
	game_controller.start_game(team, start_screen.time)
	input_manager.set_process(true)


func _process(delta: float) -> void:
	for node in Globals.unit_enemy_los_time_s:
		if not is_instance_valid(node):
			pass


func _on_ui_try_again() -> void:
	try_again.emit()


func _on_start_screen_hover_start_button(team: int) -> void:
	target_area.show_target(team)


func _on_result_screen_try_again() -> void:
	try_again.emit()

var selected_map_hex: Vector2i

func _on_input_manager_right_button_pressed() -> void:
	var mouse_screen_pos: Vector2 = get_viewport().get_mouse_position()
	var event_pos: Vector2 = get_local_mouse_position()
	selected_map_hex = ground_layer.local_to_map(event_pos)
	if selected_map_hex and game_controller.selected_unit:
		#ui.selection_wheel.open(mouse_screen_pos)
		ui.selection_wheel_alt.open(mouse_screen_pos)


func _on_input_manager_right_button_released() -> void:
	#var option: WheelOption.Option = ui.selection_wheel.close()
	var option: WheelOption.Option = ui.selection_wheel_alt.close()
	game_controller.order_via_option_wheel(selected_map_hex, option)
