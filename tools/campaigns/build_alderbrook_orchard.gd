extends "res://tools/campaigns/build_alderbrook_prologue.gd"

# Reuse the prologue's polygon, boundary and deployment authoring helpers.
# Only Orchard Outpost is saved; existing identities, loadouts and rules survive.
const ORCHARD_ID: String = "02_orchard_outpost"
const ORCHARD_SCENE: String = MAP_DIRECTORY + ORCHARD_ID + ".tscn"


func _run() -> void:
	var layout: Dictionary = _roads.layout_for_routes(AlderbrookOrchardLayout.ROUTES, AlderbrookOrchardLayout.SIZE)
	if OS.get_cmdline_user_args().has("--roads-only"):
		_roads.write_assets(ORCHARD_ID, layout)
		get_tree().quit()
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.world.fully_freed.disconnect(main._on_fully_freed)
	if OS.get_cmdline_user_args().has("--los-only"):
		# Bake imported textures and the same palette-initialized layers used in battle.
		await get_tree().process_frame
		await get_tree().process_frame
		var runtime_map: Map = main.world.maps.get_node("Alderbrook2") as Map
		_road_layouts = [layout, layout, layout]
		_export_layout(runtime_map, MISSIONS[1])
		await _bake_los(runtime_map)
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit()
		return
	var scene_uid: int = ResourceLoader.get_resource_uid(ORCHARD_SCENE)
	var header: String = FileAccess.get_file_as_string(ORCHARD_SCENE).get_slice("\n", 0)
	if header.contains('uid="'):
		scene_uid = ResourceUID.text_to_id(header.get_slice('uid="', 1).get_slice('"', 0))
	var map: Map = load(ORCHARD_SCENE).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Map
	for layer_name: String in ["GroundTileMapLayer", "TerrainTileMapLayer", "BuildingTileMapLayer", "RoadTileMapLayer"]:
		var layer: HexagonTileMapLayer = map.get_node("TileMapLayers/" + layer_name) as HexagonTileMapLayer
		if layer.tile_set == null:
			push_error("Import the generated road and terrain textures before rebuilding Orchard Outpost.")
			get_tree().quit(1)
			return
	map.campaign_name = ""
	map.use_terrain_palette = false
	add_child(map)
	map.campaign_name = "Road to Alderbrook"
	create_orchard(map, layout)
	bake_orchard_art(map)
	map.process_mode = Node.PROCESS_MODE_INHERIT
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(map) == OK)
	assert(ResourceSaver.save(packed, ORCHARD_SCENE) == OK)
	if scene_uid != ResourceUID.INVALID_ID:
		assert(ResourceSaver.set_uid(ORCHARD_SCENE, scene_uid) == OK)
	map.process_mode = Node.PROCESS_MODE_DISABLED
	# Polygon helpers use entry zero; the manifest uses authored mission index two.
	_road_layouts = [layout, layout]
	_export_layout(map, MISSIONS[1])
	if not OS.get_cmdline_user_args().has("--skip-los"):
		await _bake_los(map)
	map.queue_free()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Built Orchard Outpost: hedged orchards, barn lane and walled farmhouse.")
	get_tree().quit()


func create_orchard(map: Map, layout: Dictionary) -> void:
	_road_layouts = [layout, layout]
	map.grid_size = AlderbrookOrchardLayout.SIZE
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
	_woods_sources = _sources_for_images(_terrain_set, WOODS_IMAGES)
	_wood_building_sources = _sources_for_images(_building_set, WOODS_IMAGES)
	_orchard_sources = _sources_for_images(_terrain_set, ORCHARD_IMAGES)
	_wheat_sources = _sources_for_images(_terrain_set, WHEAT_IMAGES)
	_crop_sources = _sources_for_images(_terrain_set, CROP_IMAGES)
	for label: String in ["Stone Building", "Wood Building"]:
		_building_sources[label] = _source_for(_building_set, label)
	_road_sources = [RoadTiles.install_curve(_road_set, AlderbrookRoads.ASSET_DIRECTORY + "road_" + ORCHARD_ID + ".svg", "Road - Orchard estate lanes", layout["cells"])]
	_create_landscape(map)
	var scenario: Scenario = map.get_scenario(0)
	scenario.scenario_description = AlderbrookOrchardLayout.BRIEFING
	_position_roster(map, scenario, AlderbrookOrchardLayout.PLAYER, Globals.Team.ALLIES)
	_position_roster(map, scenario, AlderbrookOrchardLayout.ENEMY, Globals.Team.AXIS)
	_set_markers(scenario.get_objectives_layer(Globals.Team.ALLIES), AlderbrookOrchardLayout.ALLIED_MARKERS, true)
	_set_markers(scenario.get_objectives_layer(Globals.Team.AXIS), AlderbrookOrchardLayout.AXIS_MARKERS, false)
	(map.get_building_layer() as BuildingTileMapLayer).synchronize_buildings()
	for unit: Unit in scenario.get_units():
		assert(map.get_ground_layer().get_cell_source_id(map.get_ground_layer().local_to_map(unit.position)) >= 0, "Every deployment must be playable")


func _create_landscape(map: Map) -> void:
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	var grasses: Array[int] = _sources_for_images(ground.tile_set, OPEN_GROUND_IMAGES)
	_grass_noise.seed = 21754
	_grass_noise.frequency = 0.19
	for x: int in range(map.grid_size.x):
		for y: int in range(map.grid_size.y):
			var variation: int = clampi(floori((_grass_noise.get_noise_2d(x, y) + 1.0) * 1.5), 0, 2)
			ground.set_cell(Vector2i(x, y), grasses[variation], Vector2i.ZERO)
	for cell: Vector2i in _road_layouts[0]["cells"]:
		map.get_road_layer().set_cell(cell, _road_sources[0], _road_layouts[0]["cells"][cell])
	# Small copses replace the continuous north/south woodland belts of Quiet Approach.
	_patch(map, "woods", [Vector2(0, 0), Vector2(3, 0), Vector2(4, 1), Vector2(2, 3), Vector2(0, 2)])
	_patch(map, "woods", [Vector2(0, 8), Vector2(2, 8), Vector2(3, 10), Vector2(1, 11), Vector2(0, 11)])
	_patch(map, "woods", [Vector2(2, 12), Vector2(4, 10), Vector2(6, 11), Vector2(8, 13), Vector2(6, 15), Vector2(3, 15)])
	_patch(map, "woods", [Vector2(6, 7), Vector2(8, 6), Vector2(9, 8), Vector2(8, 10), Vector2(6, 10)])
	_patch(map, "woods", [Vector2(19, 0), Vector2(22, 0), Vector2(22, 4), Vector2(20, 3)])
	_patch(map, "woods", [Vector2(15, 13), Vector2(17, 12), Vector2(18, 14), Vector2(17, 16), Vector2(15, 16)])
	var orchards: Array[Dictionary] = [
		{"shape": [Vector2(1, 4), Vector2(3, 3), Vector2(6, 4), Vector2(6, 7), Vector2(4, 9), Vector2(1, 8)], "gates": [Vector2i(4, 8), Vector2i(5, 4)]},
		{"shape": [Vector2(5, 1), Vector2(7, 0), Vector2(10, 2), Vector2(10, 5), Vector2(8, 6), Vector2(5, 4)], "gates": [Vector2i(6, 4), Vector2i(9, 3)]},
		{"shape": [Vector2(9, 5), Vector2(12, 5), Vector2(13, 7), Vector2(12, 9), Vector2(9, 9), Vector2(8, 7)], "gates": [Vector2i(9, 8), Vector2i(12, 6)]},
		{"shape": [Vector2(9, 12), Vector2(11, 11), Vector2(14, 12), Vector2(14, 15), Vector2(12, 16), Vector2(9, 15)], "gates": [Vector2i(9, 13), Vector2i(12, 11)]},
		{"shape": [Vector2(15, 7), Vector2(17, 7), Vector2(19, 9), Vector2(18, 12), Vector2(15, 11), Vector2(14, 9)], "gates": [Vector2i(15, 8), Vector2i(17, 11)]},
		{"shape": [Vector2(11, 0), Vector2(14, 0), Vector2(15, 1), Vector2(13, 3), Vector2(11, 2)], "gates": [Vector2i(13, 2), Vector2i(11, 1)]},
	]
	for orchard: Dictionary in orchards:
		var polygon: Array[Vector2] = []
		polygon.assign(orchard["shape"])
		var gates: Array[Vector2i] = []
		gates.assign(orchard["gates"])
		_patch(map, "orchard", polygon)
		_enclose_polygon(map, polygon, gates)
	_patch(map, "wheat", [Vector2(0, 12), Vector2(2, 11), Vector2(3, 14), Vector2(2, 16), Vector2(0, 16)])
	_patch(map, "wheat", [Vector2(18, 5), Vector2(22, 5), Vector2(22, 10), Vector2(20, 10), Vector2(18, 8)])
	_patch(map, "crops", [Vector2(18, 12), Vector2(20, 11), Vector2(22, 12), Vector2(22, 16), Vector2(18, 16)])
	# Separate building groups give B its own defensive position before the estate.
	for cell: Vector2i in [Vector2i(15, 3), Vector2i(17, 2), Vector2i(16, 1), Vector2i(13, 5), Vector2i(10, 8), Vector2i(12, 8)]:
		assert(map.get_road_layer().get_cell_source_id(cell) < 0, "Estate buildings must leave the lanes clear")
		_house(map.get_building_layer(), map.get_terrain_layer(), cell, cell.y < 6)
	BuildingVariations.apply(map.get_building_layer(), "alderbrook_02_orchard_outpost")
	_enclose(map, Rect2i(14, 1, 4, 4), 0, [Vector2i(15, 4), Vector2i(17, 3)])
	_enclose(map, Rect2i(9, 7, 4, 3), 1, [Vector2i(10, 9), Vector2i(12, 7)])


func _prune_generated_sources(tiles: TileSet) -> void:
	var remove: Array[int] = []
	for index: int in range(tiles.get_source_count()):
		var id: int = tiles.get_source_id(index)
		var label: String = tiles.get_source(id).resource_name
		if label.begins_with("Connected terrain") or label.begins_with("Road -"):
			remove.append(id)
	for id: int in remove:
		tiles.remove_source(id)


func bake_orchard_art(map: Map) -> void:
	ConnectedTerrainBaker.bake(map.get_terrain_layer(), ORCHARD_ID + "_estate_terrain")
	ConnectedTerrainBaker.bake(map.get_building_layer(), ORCHARD_ID + "_estate_woods")
	var resources: Dictionary[String, TileSet] = {
		"terrain": map.get_terrain_layer().tile_set,
		"buildings": map.get_building_layer().tile_set,
		"roads": map.get_road_layer().tile_set,
	}
	for kind: String in resources:
		var path: String = RESOURCE_DIRECTORY + "alderbrook_orchard_" + kind + ".tres"
		assert(ResourceSaver.save(resources[kind], path) == OK)
		resources[kind].take_over_path(path)
