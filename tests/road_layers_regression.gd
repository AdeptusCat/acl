extends Node

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var maps: Node = main.world.maps
	for map: Map in maps.get_children():
		_test_layer(map)
	_test_village(maps.get_node("Alderbrook5") as Map)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Road layer checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_layer(map: Map) -> void:
	var roads: HexagonTileMapLayer = map.get_road_layer()
	var terrain: HexagonTileMapLayer = map.get_terrain_layer()
	_check(roads != null and roads.scene_file_path == RoadTiles.LAYER_SCENE, "Every map reuses the shared road layer scene")
	if roads == null:
		return
	_check(roads.tile_set.tile_size == Vector2i(128, 128) and roads.tile_set.tile_shape == terrain.tile_set.tile_shape and roads.tile_set.tile_offset_axis == terrain.tile_set.tile_offset_axis, "Roads align with the terrain hex grid")
	_check(roads.get_index() > terrain.get_index() and roads.get_index() < map.get_wall_layer().get_index() and roads.get_index() < map.get_building_layer().get_index(), "Roads draw over terrain and beneath walls and buildings")
	_check(not roads.get_used_cells().is_empty(), "Existing roads remain editable on their separate layer")
	for cell: Vector2i in terrain.get_used_cells():
		_check(not RoadTiles.is_road(terrain.get_cell_tile_data(cell)), "No placed roads remain in the terrain layer")
	for index: int in range(terrain.tile_set.get_source_count()):
		var source: TileSetAtlasSource = terrain.tile_set.get_source(terrain.tile_set.get_source_id(index)) as TileSetAtlasSource
		for tile: int in range(source.get_tiles_count()):
			_check(not RoadTiles.is_road(source.get_tile_data(source.get_tile_id(tile), 0)), "Terrain paint palettes exclude road sources")
	for cell: Vector2i in roads.get_used_cells():
		var data: TileData = roads.get_cell_tile_data(cell)
		_check(RoadTiles.is_road(data) and not bool(data.get_custom_data("hindrance")) and not bool(data.get_custom_data("blocking")), "Road art retains neutral LOS rules")


func _test_village(map: Map) -> void:
	var roads: HexagonTileMapLayer = map.get_road_layer()
	var expected: Dictionary = AlderbrookRoads.new().layout_for_routes(AlderbrookVillageLayout.ROUTES, map.grid_size)["cells"]
	_check(roads.get_used_cells().size() == expected.size(), "The complete Alderbrook street network is restored")
	for cell: Vector2i in expected:
		_check(roads.get_cell_source_id(cell) >= 0 and roads.get_cell_atlas_coords(cell) == expected[cell], "Every village road uses its correct position-specific atlas region")
	LOSHelper.ground_layer = map.get_ground_layer()
	LOSHelper.building_layer = map.get_building_layer()
	LOSHelper.wall_layer = map.get_wall_layer()
	LOSHelper.terrain_layer = map.get_terrain_layer()
	LOSHelper.road_layer = roads
	for cell: Vector2i in [Vector2i(20, 5), Vector2i(23, 10)]:
		var data: TileData = map.get_terrain_layer().get_cell_tile_data(cell)
		_check(data != null and str(data.get_custom_data("name")) == "Orchard" and roads.get_cell_source_id(cell) >= 0, "Restoring the missing road pieces preserves the existing orchard")
		_check(LOSHelper.is_hex_hindrance(cell), "Roads do not erase vegetation hindrance")
	for cell: Vector2i in roads.get_used_cells():
		if map.get_terrain_layer().get_cell_source_id(cell) < 0 and map.get_building_layer().get_cell_source_id(cell) < 0:
			_check(LOSHelper.get_tile_name(roads.map_to_local(cell)) == "Road" and not LOSHelper.is_hex_hindrance(cell), "Inspection recognizes a road on the separate layer without adding cover")
			var builder: Node = load("res://tools/campaigns/build_alderbrook_campaign.gd").new()
			_check(not builder._can_plant(map.get_ground_layer(), map.get_terrain_layer(), map.get_building_layer(), cell), "Map generators reserve road corridors when planting fields and orchards")
			builder.free()
			break


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
