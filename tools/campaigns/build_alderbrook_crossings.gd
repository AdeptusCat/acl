extends "res://tools/campaigns/build_alderbrook_prologue.gd"

const CROSSINGS_ID: String = "04_two_crossings"
const CROSSINGS_SCENE: String = MAP_DIRECTORY + CROSSINGS_ID + ".tscn"

var river: AlderbrookCrossingsRiver = AlderbrookCrossingsRiver.new()
var river_layout: Dictionary = {}
var landscape_valid: bool = false


func _run() -> void:
	var layout: Dictionary = _roads.layout_for_routes(AlderbrookCrossingsLayout.ROUTES, AlderbrookCrossingsLayout.SIZE)
	_road_layouts.resize(MISSIONS.size() + 1)
	_road_layouts.fill(layout)
	if OS.get_cmdline_user_args().has("--roads-only"):
		_roads.write_assets(CROSSINGS_ID, layout)
		river.write_assets(river.layout(layout), layout)
		get_tree().quit()
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.world.fully_freed.disconnect(main._on_fully_freed)
	if OS.get_cmdline_user_args().has("--los-only"):
		await get_tree().process_frame
		await get_tree().process_frame
		var runtime_map: Map = main.world.maps.get_node("Alderbrook4") as Map
		_export_layout(runtime_map, MISSIONS[3])
		await _bake_los(runtime_map)
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit()
		return
	var header: String = FileAccess.get_file_as_string(CROSSINGS_SCENE).get_slice("\n", 0)
	var uid: int = ResourceUID.text_to_id(header.get_slice('uid="', 1).get_slice('"', 0))
	var map: Map = load(CROSSINGS_SCENE).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Map
	map.campaign_name = ""
	map.use_terrain_palette = false
	add_child(map)
	map.campaign_name = "Road to Alderbrook"
	if not create_crossings(map, layout):
		get_tree().quit(1)
		return
	bake_crossings_art(map)
	map.process_mode = Node.PROCESS_MODE_INHERIT
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(map) == OK)
	assert(ResourceSaver.save(packed, CROSSINGS_SCENE) == OK)
	assert(ResourceSaver.set_uid(CROSSINGS_SCENE, uid) == OK)
	map.process_mode = Node.PROCESS_MODE_DISABLED
	_export_layout(map, MISSIONS[3])
	if not OS.get_cmdline_user_args().has("--skip-los"):
		await _bake_los(map)
	map.queue_free()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Built Two Crossings: winding river, bridge hamlet and timber crossing.")
	get_tree().quit()


func create_crossings(map: Map, layout: Dictionary) -> bool:
	_road_layouts.resize(MISSIONS.size() + 1)
	_road_layouts.fill(layout)
	river_layout = river.layout(layout)
	map.grid_size = AlderbrookCrossingsLayout.SIZE
	for layer: HexagonTileMapLayer in map.get_tilemap_layers():
		layer.clear()
	_terrain_set = map.get_terrain_layer().tile_set.duplicate(true) as TileSet
	_building_set = map.get_building_layer().tile_set.duplicate(true) as TileSet
	_road_set = map.get_road_layer().tile_set.duplicate(true) as TileSet
	for tiles: TileSet in [_terrain_set, _building_set, _road_set]:
		_prune_generated_sources(tiles)
	map.get_terrain_layer().tile_set = _terrain_set
	map.get_building_layer().tile_set = _building_set
	map.get_road_layer().tile_set = _road_set
	(map.get_node("TileMapLayers/WaterTileMapLayer") as HexagonTileMapLayer).tile_set = river.tile_set(river_layout)
	_woods_sources = _sources_for_images(_terrain_set, WOODS_IMAGES)
	_wood_building_sources = _sources_for_images(_building_set, WOODS_IMAGES)
	_orchard_sources = _sources_for_images(_terrain_set, ORCHARD_IMAGES)
	_wheat_sources = _sources_for_images(_terrain_set, WHEAT_IMAGES)
	_crop_sources = _sources_for_images(_terrain_set, CROP_IMAGES)
	_road_sources = [RoadTiles.install_curve(_road_set, AlderbrookRoads.ASSET_DIRECTORY + "road_" + CROSSINGS_ID + ".svg", "Road - Two Crossings bank lanes", layout["cells"])]
	_create_landscape(map)
	if not landscape_valid:
		return false
	var scenario: Scenario = map.get_scenario(0)
	scenario.scenario_description = AlderbrookCrossingsLayout.BRIEFING
	_position_roster(map, scenario, AlderbrookCrossingsLayout.PLAYER, Globals.Team.ALLIES)
	_position_roster(map, scenario, AlderbrookCrossingsLayout.ENEMY, Globals.Team.AXIS)
	_set_markers(scenario.get_objectives_layer(Globals.Team.ALLIES), AlderbrookCrossingsLayout.ALLIED_MARKERS, true)
	_set_markers(scenario.get_objectives_layer(Globals.Team.AXIS), AlderbrookCrossingsLayout.AXIS_MARKERS, false)
	(map.get_building_layer() as BuildingTileMapLayer).synchronize_buildings()
	for unit: Unit in scenario.get_units():
		var cell: Vector2i = map.get_ground_layer().local_to_map(unit.position)
		if map.get_ground_layer().get_cell_source_id(cell) < 0:
			push_error("Deployment lies in the channel: " + str(cell))
			return false
	return true


func _create_landscape(map: Map) -> void:
	landscape_valid = false
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	var grasses: Array[int] = _sources_for_images(ground.tile_set, OPEN_GROUND_IMAGES)
	_grass_noise.seed = 74008
	_grass_noise.frequency = 0.16
	for x: int in range(map.grid_size.x):
		for y: int in range(map.grid_size.y):
			var variant: int = clampi(floori((_grass_noise.get_noise_2d(x, y) + 1.0) * 1.5), 0, 2)
			ground.set_cell(Vector2i(x, y), grasses[variant], Vector2i.ZERO)
	for cell: Vector2i in _road_layouts[0]["cells"]:
		map.get_road_layer().set_cell(cell, _road_sources[0], _road_layouts[0]["cells"][cell])
	_patch(map, "woods", [Vector2(0, 0), Vector2(4, 0), Vector2(5, 1), Vector2(3, 3), Vector2(0, 2)])
	_patch(map, "woods", [Vector2(1, 4), Vector2(4, 3), Vector2(6, 5), Vector2(6, 8), Vector2(3, 9), Vector2(1, 7)])
	_patch(map, "woods", [Vector2(1, 10), Vector2(3, 9), Vector2(4, 10), Vector2(3, 12), Vector2(1, 12)])
	_patch(map, "woods", [Vector2(2, 13), Vector2(5, 12), Vector2(7, 14), Vector2(6, 17), Vector2(3, 18), Vector2(1, 16)])
	_patch(map, "woods", [Vector2(8, 6), Vector2(10, 6), Vector2(11, 8), Vector2(10, 10), Vector2(8, 9)])
	_patch(map, "woods", [Vector2(12, 8), Vector2(14, 8), Vector2(16, 10), Vector2(15, 12), Vector2(13, 12), Vector2(11, 10)])
	_patch(map, "woods", [Vector2(16, 0), Vector2(19, 0), Vector2(19, 2), Vector2(17, 3), Vector2(15, 2)])
	_patch(map, "woods", [Vector2(19, 10), Vector2(22, 9), Vector2(25, 11), Vector2(25, 15), Vector2(23, 17), Vector2(20, 16), Vector2(19, 13)])
	_patch(map, "woods", [Vector2(12, 17), Vector2(14, 16), Vector2(16, 18), Vector2(15, 20), Vector2(12, 20)])
	_patch(map, "orchard", [Vector2(6, 0), Vector2(10, 0), Vector2(11, 2), Vector2(9, 4), Vector2(6, 3)])
	_patch(map, "orchard", [Vector2(7, 10), Vector2(10, 10), Vector2(12, 12), Vector2(11, 15), Vector2(8, 15), Vector2(7, 13)])
	_patch(map, "orchard", [Vector2(20, 0), Vector2(24, 0), Vector2(25, 2), Vector2(23, 4), Vector2(20, 3)])
	_patch(map, "orchard", [Vector2(24, 7), Vector2(27, 7), Vector2(28, 9), Vector2(26, 11), Vector2(24, 10)])
	_patch(map, "wheat", [Vector2(6, 5), Vector2(8, 4), Vector2(9, 5), Vector2(8, 7), Vector2(6, 8)])
	_patch(map, "wheat", [Vector2(6, 17), Vector2(9, 16), Vector2(12, 18), Vector2(11, 20), Vector2(6, 20)])
	_patch(map, "crops", [Vector2(19, 6), Vector2(22, 6), Vector2(23, 8), Vector2(21, 10), Vector2(19, 9)])
	_patch(map, "wheat", [Vector2(24, 17), Vector2(28, 16), Vector2(28, 20), Vector2(23, 20)])
	_place_water(map)
	# The stone hamlet and timber yards give the bridgeheads different cover.
	var houses: Array[Array] = [
		[Vector2i(7, 4), "building_wood_02"], [Vector2i(15, 4), "building_stone_03"], [Vector2i(17, 3), "building_stone_01"],
		[Vector2i(18, 3), "building_stone_02"], [Vector2i(16, 2), "building_wood_03"], [Vector2i(16, 7), "building_wood_01"],
		[Vector2i(21, 13), "building_wood_03"], [Vector2i(22, 14), "building_wood_02"], [Vector2i(21, 16), "building_wood_01"],
		[Vector2i(25, 13), "building_wood_02"], [Vector2i(25, 9), "building_stone_01"],
	]
	var conflict: bool = false
	for house: Array in houses:
		var cell: Vector2i = house[0]
		if ground.get_cell_source_id(cell) < 0 or map.get_road_layer().get_cell_source_id(cell) >= 0 or river_layout["cells"].has(cell):
			push_error("Building intersects the channel or road: " + str(cell))
			conflict = true
	if conflict:
		return
	for house: Array in houses:
		var cell: Vector2i = house[0]
		var source: int = _sources_for_images(_building_set, [BuildingVariations.texture_path(str(house[1]))])[0]
		map.get_building_layer().set_cell(cell, source, Vector2i.ZERO)
		map.get_terrain_layer().erase_cell(cell)
	BuildingVariations.apply(map.get_building_layer(), "alderbrook_04_two_crossings")
	_enclose(map, Rect2i(14, 2, 5, 5), 0, [Vector2i(15, 6), Vector2i(18, 4)])
	_enclose(map, Rect2i(20, 12, 5, 5), 1, [Vector2i(20, 14), Vector2i(24, 15)])
	_enclose(map, Rect2i(6, 0, 4, 4), 1, [Vector2i(7, 3), Vector2i(9, 2)])
	_enclose(map, Rect2i(7, 10, 5, 5), 1, [Vector2i(8, 10), Vector2i(10, 14)])
	_enclose(map, Rect2i(20, 0, 5, 4), 1, [Vector2i(21, 3), Vector2i(24, 2)])
	landscape_valid = true


func _place_water(map: Map) -> void:
	var water: HexagonTileMapLayer = map.get_node("TileMapLayers/WaterTileMapLayer") as HexagonTileMapLayer
	for cell: Vector2i in river_layout["cells"]:
		var kind: int = 0
		if river_layout["bridges"].has(cell):
			kind = 1
		else:
			map.get_ground_layer().erase_cell(cell)
		water.set_cell(cell, kind, river_layout["cells"][cell])
		map.get_road_layer().erase_cell(cell)
		map.get_terrain_layer().erase_cell(cell)
		map.get_building_layer().erase_cell(cell)


func _prune_generated_sources(tiles: TileSet) -> void:
	var remove: Array[int] = []
	for index: int in range(tiles.get_source_count()):
		var id: int = tiles.get_source_id(index)
		var label: String = tiles.get_source(id).resource_name
		if label.begins_with("Connected terrain") or label.begins_with("Road -"):
			remove.append(id)
	for id: int in remove:
		tiles.remove_source(id)


func bake_crossings_art(map: Map) -> void:
	ConnectedTerrainBaker.bake(map.get_terrain_layer(), CROSSINGS_ID + "_river_terrain")
	ConnectedTerrainBaker.bake(map.get_building_layer(), CROSSINGS_ID + "_river_woods")
	var resources: Dictionary[String, TileSet] = {
		"terrain": map.get_terrain_layer().tile_set,
		"buildings": map.get_building_layer().tile_set,
		"roads": map.get_road_layer().tile_set,
		"water": (map.get_node("TileMapLayers/WaterTileMapLayer") as HexagonTileMapLayer).tile_set,
	}
	for kind: String in resources:
		var path: String = RESOURCE_DIRECTORY + "alderbrook_crossings_" + kind + ".tres"
		assert(ResourceSaver.save(resources[kind], path) == OK)
		resources[kind].take_over_path(path)
