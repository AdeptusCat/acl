extends Node2D

# --- SETUP ---
@onready var ground_layer : HexagonTileMapLayer = $TileMapLayers/GroundTileMapLayer
@onready var building_layer : HexagonTileMapLayer = $TileMapLayers/BuildingTileMapLayer
@onready var wall_layer : HexagonTileMapLayer = $TileMapLayers/WallTileMapLayer
@onready var terrain_layer : HexagonTileMapLayer = $TileMapLayers/TerrainTileMapLayer
@onready var result_screen := $ResultScreen
@onready var start_screen := $StartScreen
@onready var ui := $Ui
@onready var game_controller := $GameController


func _ready():
	LOSHelper.ground_layer = ground_layer  # <-- inject the TileMap
	LOSHelper.building_layer = building_layer  # <-- inject the TileMap
	LOSHelper.wall_layer = wall_layer  # <-- inject the TileMap
	LOSHelper.terrain_layer = terrain_layer
	await get_tree().process_frame
	#LOSHelper.prebake_los()
	#LOSHelper.bake_and_save_los_data("res://scenes/game/los/los_data.tres")
	LOSHelper.load_prebaked_los("res://scenes/game/los/los_data.tres")
	
	game_controller.mouse_event_position_changed.connect(_on_mouse_event_position_changed)
	start_screen.game_started.connect(_on_game_started)
	game_controller.update_timer_label.connect(ui._on_update_timer_label)
	game_controller.show_winner.connect(result_screen._on_show_winner)
	game_controller.set_objective_text.connect(start_screen._on_set_objective_text)
	
	game_controller.setup_game()
	
	
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
	
	var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(1,1))
	var pos_b : Vector2 = ground_layer.map_to_local(Vector2i(1,0))
	var res = LOSHelper.check_los(pos_a, pos_b, 0, 0, 0, 0)
	print(res)
	pass
	#var pos_a : Vector2 = ground_layer.map_to_local(Vector2i(0,1))
	#LOSHelper.get_tile_local_pixel_coords(pos_a, building_layer)


func _on_mouse_event_position_changed(event_pos: Vector2):
	var result = {
		"cover": 0,
		"blocking" : false,
		"cover_in_hex" : 0,
		"cover_n" : 0,
		"cover_ne" : 0,
		"cover_se" : 0,
		"cover_s" : 0,
		"cover_sw" : 0,
		"cover_nw" : 0,
		"hindrance": 0,
	}
	var hex_cube = building_layer.local_to_cube(event_pos)
	
	result.cover_in_hex = LOSHelper.is_sample_point_in_building(event_pos)
	
	var top_cube = ground_layer.cube_direction(TileSet.CellNeighbor.CELL_NEIGHBOR_TOP_SIDE)
	var hex_cube_top = hex_cube + top_cube
	
	var top_pos = ground_layer.cube_to_local(hex_cube_top)
	var res = LOSHelper.check_los(event_pos, top_pos, 0, 0, 0, 0)
	result.cover_n = res.wall_cover
	print(res)
	
	var top_right = ground_layer.cube_direction(TileSet.CellNeighbor.CELL_NEIGHBOR_TOP_RIGHT_SIDE)
	#print(top_right)  # Output: Vector3i(1, -1, 0)



	# Corner directions (diagonal hexes, two steps)
	var top_right_corner = ground_layer.cube_direction(TileSet.CellNeighbor.CELL_NEIGHBOR_TOP_RIGHT_CORNER)
	#print(top_right_corner)  # Output: Vector3i(2, -1, -1)  # Note the magnitude is 2 
	# Movement examples
	var current_pos = Vector3i(0, 0, 0)

	# Compare side vs corner movement
	#var side_move = current_pos + top_right + right # One step diagonally and one right


	#LOSHelper.get_tile_local_pixel_coords(pos_a, building_layer)
	#ui.mouse_event_position_changed.emit(event_pos)



func _on_game_started(team : int):
	game_controller.start_game(team)
