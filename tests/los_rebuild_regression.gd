extends Node

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	for number: int in [1, 3, 5]:
		_test_rays(main.world.maps.get_node("Alderbrook" + str(number)) as Map)
	_test_disk_cache()
	main.queue_free()
	LOSHelper.unload_map()
	await get_tree().process_frame
	await get_tree().process_frame
	print("LOS rebuild checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_rays(map: Map) -> void:
	_bind(LOSHelper, map)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 9173
	var starts: Array[Vector2] = []
	var ends: Array[Vector2] = []
	var expected: Array[Dictionary] = []
	for index: int in range(2400):
		var from: Vector2i = Vector2i(random.randi_range(0, map.grid_size.x - 1), random.randi_range(0, map.grid_size.y - 1))
		var to: Vector2i = Vector2i(random.randi_range(0, map.grid_size.x - 1), random.randi_range(0, map.grid_size.y - 1))
		var offset: Vector2 = Vector2.ZERO
		if index % 2 == 0:
			offset = Vector2(random.randf_range(-24, 24), random.randf_range(-24, 24))
		starts.append(map.get_ground_layer().map_to_local(from) + offset)
		ends.append(map.get_ground_layer().map_to_local(to) - offset)
		expected.append(LOSHelper.check_los(starts[index], ends[index], 1, 0, 1, 0))
	LOSHelper.begin_los_bake()
	var first_signature: String = LOSHelper._bake_cache.fingerprint(map.grid_size, LOSHelper.STEP_SIZE_PIXELS)
	for index: int in range(expected.size()):
		var actual: Dictionary = LOSHelper.check_los(starts[index], ends[index], 1, 0, 1, 0)
		_check(actual == expected[index], "Optimized rays preserve every result field, including first-hit position and direction")
	LOSHelper.end_los_bake()
	_check(LOSHelper._bake_cache == null, "Temporary geometry and alpha masks are released after baking")
	LOSHelper.begin_los_bake()
	_check(LOSHelper._bake_cache.fingerprint(map.grid_size, LOSHelper.STEP_SIZE_PIXELS) == first_signature, "Fingerprint stays stable across fresh snapshots")
	LOSHelper.end_los_bake()
	LOSHelper.unload_map()


func _test_disk_cache() -> void:
	var map: Map = load("res://scenes/world/maps/map.tscn").instantiate() as Map
	map.map_name = "LOS Rebuild Regression"
	map.grid_size = Vector2i(6, 6)
	map.los_resource_path = "user://los_rebuild_regression.tres"
	var layers: Node2D = map.get_node("TileMapLayers") as Node2D
	var ground: HexagonTileMapLayer = _layer("GroundTileMapLayer")
	var building: HexagonTileMapLayer = _layer("BuildingTileMapLayer")
	var terrain: HexagonTileMapLayer = _layer("TerrainTileMapLayer")
	var wall: WallTileMapLayer = load(ConnectedWalls.LAYER_SCENE).instantiate() as WallTileMapLayer
	for layer: HexagonTileMapLayer in [ground, building, terrain, wall]:
		layers.add_child(layer)
	add_child(map)
	var image: Image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(128, 128)
	source.create_tile(Vector2i.ZERO)
	ground.tile_set.add_source(source.duplicate(true), 0)
	for x: int in range(6):
		for y: int in range(6):
			ground.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	terrain.tile_set.add_source(source, 0)
	var data: TileData = source.get_tile_data(Vector2i.ZERO, 0)
	data.set_custom_data("hindrance", true)
	terrain.set_cell(Vector2i(2, 3), 0, Vector2i.ZERO)
	wall.paint_edges([Vector2i(3, 2)], 0, 6)
	var path: String = "user://los_cache/" + map.los_resource_path.sha256_text() + ".res"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var stale: LosLookupData = LosLookupData.new()
	stale.los_lookup = {}
	stale.wall_layout_signature = wall.los_layout_signature()
	_check(ResourceSaver.save(stale, map.los_resource_path) == OK, "The stale fixture saves independently of project maps")
	var service: Node2D = load("res://tests/fixtures/los_rebuild_counting_service.gd").new() as Node2D
	add_child(service)
	service.load_prebaked_los(map)
	_check(service.baked_origins == 36 and FileAccess.file_exists(path), "A legacy lookup without a fingerprint rebuilds even when building and wall signatures match")
	var expected: Dictionary = service.los_lookup.duplicate(true)
	var authored: LosLookupData = load(map.los_resource_path) as LosLookupData
	_mark_stale(authored)
	service.unload_map()
	service.baked_origins = 0
	service.load_prebaked_los(map)
	_check(service.baked_origins == 0 and service.los_lookup == expected, "Stale authored data reuses the saved cache without recomputing any ray")
	var cached: LosLookupData = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LosLookupData
	var original_signature: String = cached.bake_layout_signature
	authored.bake_layout_signature = ""
	data.set_custom_data("hindrance", false)
	service.unload_map()
	service.baked_origins = 0
	service.load_prebaked_los(map)
	cached = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LosLookupData
	_check(service.baked_origins == 36 and cached.bake_layout_signature != original_signature, "Terrain edits invalidate legacy lookups and the disk cache without a building or wall edit")
	data.set_custom_data("hindrance", true)
	_mark_stale(authored)
	service.unload_map()
	service.load_prebaked_los(map)
	image.fill(Color.TRANSPARENT)
	# Replacing the texture also works with the headless renderer's image storage.
	source.texture = ImageTexture.create_from_image(image)
	service.unload_map()
	service.baked_origins = 0
	service.load_prebaked_los(map)
	_check(service.baked_origins == 36, "Changing sprite pixels invalidates the disk cache without a tile edit")
	_check(service.los_lookup[Vector2i(2, 1)][Vector2i(2, 5)]["hindrance"] == 0, "Transparent replacement pixels do not retain old hindrance")
	cached = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LosLookupData
	cached.bake_layout_signature = "incompatible version"
	_check(ResourceSaver.save(cached, path, ResourceSaver.FLAG_COMPRESS) == OK, "The incompatible cache fixture saves")
	_mark_stale(authored)
	service.unload_map()
	service.baked_origins = 0
	service.load_prebaked_los(map)
	_check(service.baked_origins == 36, "An incompatible cache rebuilds instead of returning stale sight")
	_test_editor_persistence(map, service, source)
	service.unload_map()
	service.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(map.los_resource_path))
	map.free()


func _test_editor_persistence(map: Map, service: Node2D, source: TileSetAtlasSource) -> void:
	var original_path: String = map.los_resource_path
	map.get_wall_layer().clear()
	map.los_resource_path = "res://.godot/los_auto_save_regression/lookup.res"
	var cache_path: String = "user://los_cache/" + map.los_resource_path.sha256_text() + ".res"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(map.los_resource_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_path))
	service.unload_map()
	service.baked_origins = 0
	service.load_prebaked_los(map)
	var saved: LosLookupData = ResourceLoader.load(map.los_resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LosLookupData
	_check(service.baked_origins == 36 and saved != null and saved.los_lookup == service.los_lookup, "Editor map loading creates missing project LOS for export")
	var first_signature: String = saved.bake_layout_signature
	var image: Image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	source.texture = ImageTexture.create_from_image(image)
	service.unload_map()
	service.baked_origins = 0
	service.load_prebaked_los(map)
	saved = ResourceLoader.load(map.los_resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LosLookupData
	_check(service.baked_origins == 36 and saved.bake_layout_signature != first_signature and saved.los_lookup == service.los_lookup, "A terrain edit automatically refreshes the project LOS file")
	var current_signature: String = saved.bake_layout_signature
	# A fresh installation must be able to load the project resource without a user cache.
	service.unload_map()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_path))
	service.baked_origins = 0
	service.load_prebaked_los(map)
	_check(service.baked_origins == 0 and not FileAccess.file_exists(cache_path), "Saved project LOS loads without recalculation or a local cache")
	# Also persist a compatible runtime cache when the authored file itself is stale.
	saved.bake_layout_signature = "stale"
	_check(ResourceSaver.save(saved, map.los_resource_path, ResourceSaver.FLAG_COMPRESS) == OK, "The stale project fixture saves")
	ResourceLoader.load(map.los_resource_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	service.unload_map()
	service.load_prebaked_los(map)
	saved.bake_layout_signature = "stale"
	ResourceSaver.save(saved, map.los_resource_path, ResourceSaver.FLAG_COMPRESS)
	ResourceLoader.load(map.los_resource_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	service.unload_map()
	service.baked_origins = 0
	service.load_prebaked_los(map)
	saved = ResourceLoader.load(map.los_resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LosLookupData
	_check(service.baked_origins == 0 and saved.bake_layout_signature == current_signature, "Reusing a runtime cache also updates stale project data")
	# Exercise the exported-game branch without writing into an actual export package.
	service.editor_bake_saving_enabled = false
	image.fill(Color.TRANSPARENT)
	source.texture = ImageTexture.create_from_image(image)
	service.unload_map()
	service.load_prebaked_los(map)
	saved = ResourceLoader.load(map.los_resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LosLookupData
	_check(saved.bake_layout_signature == current_signature and service.bake_layout_signature() != current_signature, "Exported-game mode leaves project data untouched while refreshing runtime LOS")
	service.editor_bake_saving_enabled = true
	service.unload_map()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(map.los_resource_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(map.los_resource_path.get_base_dir()))
	map.los_resource_path = original_path


func _mark_stale(data: LosLookupData) -> void:
	data.building_layout_signature = "stale"
	data.wall_layout_signature = "stale"
	data.los_lookup = {}


func _bind(service: Node2D, map: Map) -> void:
	service.ground_layer = map.get_ground_layer()
	service.building_layer = map.get_building_layer()
	service.terrain_layer = map.get_terrain_layer()
	service.wall_layer = map.get_wall_layer()
	service.grid_size = map.grid_size


func _layer(label: String) -> HexagonTileMapLayer:
	var layer: HexagonTileMapLayer = HexagonTileMapLayer.new()
	layer.name = label
	layer.tile_set = TileSet.new()
	layer.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	layer.tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	layer.tile_set.tile_size = Vector2i(128, 128)
	for property: String in ["cover", "hindrance", "blocking"]:
		var index: int = layer.tile_set.get_custom_data_layers_count()
		layer.tile_set.add_custom_data_layer()
		layer.tile_set.set_custom_data_layer_name(index, property)
		var type: Variant.Type = TYPE_BOOL
		if property == "cover":
			type = TYPE_INT
		layer.tile_set.set_custom_data_layer_type(index, type)
	return layer


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
