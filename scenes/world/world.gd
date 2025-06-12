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
	LOSHelper.bake_and_save_los_data("res://scenes/game/los/los_data.tres")
	#LOSHelper.load_prebaked_los("res://scenes/game/los/los_data.tres")
	
	game_controller.mouse_event_position_changed.connect(_on_mouse_event_position_changed)
	start_screen.game_started.connect(_on_game_started)
	game_controller.update_timer_label.connect(ui._on_update_timer_label)
	game_controller.show_winner.connect(result_screen._on_show_winner)
	game_controller.set_objective_text.connect(start_screen._on_set_objective_text)
	
	game_controller.setup_game()
	
	game_controller.update_visible_hexes()
	game_controller.draw_fog()
	game_controller.show_visible_units()
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


func _on_mouse_event_position_changed(event_pos: Vector2):
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
	}
	result.cover_in_hex = LOSHelper.is_sample_point_in_building(event_pos)
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
	
	var units: Array
	for unit in game_controller.units:
		if unit.current_hex == map_hex: 
			units.append(unit)
	
	ui.show_unit_data(map_hex, units)


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


func _on_game_started(team : int):
	game_controller.start_game(team)
