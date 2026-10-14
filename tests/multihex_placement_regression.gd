extends Node

const ORIGINS: Array[Vector2i] = [Vector2i(4, 4), Vector2i(5, 4), Vector2i(-4, -4), Vector2i(-5, -4)]

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var layer: BuildingTileMapLayer = load(BuildingVariations.LAYER_SCENE).instantiate() as BuildingTileMapLayer
	add_child(layer)
	LOSHelper.building_layer = layer
	var empty_layers: Array[HexagonTileMapLayer] = []
	for index: int in range(3):
		var empty_layer: HexagonTileMapLayer = HexagonTileMapLayer.new()
		empty_layer.tile_set = layer.tile_set
		add_child(empty_layer)
		empty_layers.append(empty_layer)
	LOSHelper.ground_layer = empty_layers[0]
	LOSHelper.terrain_layer = empty_layers[1]
	LOSHelper.wall_layer = empty_layers[2]
	for design: Dictionary in MultihexBuildings.catalog():
		for orientation: int in range(6):
			var pattern: TileMapPattern = MultihexBuildings.pattern_for(layer.tile_set, design["id"], orientation)
			for origin: Vector2i in ORIGINS:
				for selected: Vector2i in pattern.get_used_cells():
					await _test_stamp(layer, pattern, origin, selected)
	await _test_replacement(layer)
	await _test_history_and_loading(layer)
	LOSHelper.unload_map()
	layer.free()
	for empty_layer: HexagonTileMapLayer in empty_layers:
		empty_layer.free()
	_test_baked_sight()
	print("Multihex placement checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_stamp(layer: BuildingTileMapLayer, pattern: TileMapPattern, origin: Vector2i, selected: Vector2i) -> void:
	layer.clear()
	layer.synchronize_buildings()
	var cell: Vector2i = layer.map_pattern(origin, selected, pattern)
	layer.set_cell(cell, pattern.get_cell_source_id(selected), pattern.get_cell_atlas_coords(selected), 0)
	await _settle()
	_check_pattern(layer, pattern, origin)
	for occupied: Vector2i in layer.get_used_cells():
		var data: TileData = layer.get_cell_tile_data(occupied)
		_check(LOSHelper.is_sample_point_in_building(layer.map_to_local(occupied)) == int(data.get_custom_data("cover")), "Every automatically filled hex supplies gameplay defense")
		_check(layer.get_building_cells(occupied).size() == pattern.get_used_cells().size(), "Every fragment identifies the full footprint")
	if origin.x > 0 and pattern.get_cell_atlas_coords(selected).y == 0:
		_test_gameplay(layer)
	var before: PackedByteArray = layer.tile_map_data
	layer.synchronize_buildings()
	_check(layer.tile_map_data == before, "Repeated synchronization preserves tile data")
	layer.erase_cell(cell)
	await _settle()
	_check(layer.get_used_cells().is_empty(), "Erasing any visible or invisible member removes the complete building")


func _test_gameplay(layer: BuildingTileMapLayer) -> void:
	for cell: Vector2i in layer.get_used_cells():
		var cover: int = int(layer.get_cell_tile_data(cell).get_custom_data("cover"))
		var approaches: int = 0
		for neighbor: Vector2i in layer.get_surrounding_cells(cell):
			if layer.get_cell_source_id(neighbor) >= 0:
				continue
			var target: Dictionary = LOSHelper.check_los(layer.map_to_local(neighbor), layer.map_to_local(cell), 1, 0, 1, 0)
			var shooter: Dictionary = LOSHelper.check_los(layer.map_to_local(cell), layer.map_to_local(neighbor), 1, 0, 1, 0)
			_check(not target["blocked"] and not shooter["blocked"], "Each building member can see and be seen from its adjacent open hexes")
			_check(int(target["target_cover"]) >= cover and int(shooter["shooter_cover"]) >= cover, "Actual firing directions retain wood/stone defense on secondary hexes")
			approaches += 1
		_check(approaches > 0, "Each occupied member has an open defended approach")


func _check_pattern(layer: BuildingTileMapLayer, pattern: TileMapPattern, origin: Vector2i) -> void:
	_check(layer.get_used_cells().size() == pattern.get_used_cells().size(), "One native atlas stamp creates exactly the complete footprint")
	for part: Vector2i in pattern.get_used_cells():
		var occupied: Vector2i = layer.map_pattern(origin, part, pattern)
		_check(layer.get_cell_source_id(occupied) == pattern.get_cell_source_id(part) and layer.get_cell_atlas_coords(occupied) == pattern.get_cell_atlas_coords(part), "Automatic placement matches Godot's complete hex pattern")


func _test_replacement(layer: BuildingTileMapLayer) -> void:
	var origin: Vector2i = Vector2i(4, 4)
	var old: TileMapPattern = MultihexBuildings.pattern_for(layer.tile_set, "building_wood_01_3hex", 0)
	var replacement: TileMapPattern = MultihexBuildings.pattern_for(layer.tile_set, "building_stone_03_2hex_a", 1)
	layer.set_pattern(origin, old)
	await _settle()
	var previous: Array[Vector2i] = layer.get_used_cells()
	var overwritten: Vector2i = previous[1]
	layer.set_cell(overwritten, 0, Vector2i.ZERO, 0)
	await _settle()
	_check(layer.get_used_cells() == [overwritten] and layer.get_cell_source_id(overwritten) == 0, "A single house replaces the full multihex building without deleting the new house")
	layer.clear()
	layer.synchronize_buildings()
	layer.set_pattern(origin, old)
	await _settle()
	var edge: Vector2i = Vector2i(4, 6)
	layer.set_cell(edge, replacement.get_cell_source_id(replacement.get_used_cells()[0]), Vector2i(1, 0), 0)
	await _settle()
	_check(layer.get_used_cells().size() == 2, "An overlapping replacement clears every old fragment")
	for cell: Vector2i in layer.get_used_cells():
		_check(layer.get_cell_tile_data(cell).get_custom_data("building_id") == "building_stone_03_2hex_a", "Only the replacement building remains")
	# Place a new anchor outside the old footprint, with its second cell inside it.
	layer.clear()
	layer.synchronize_buildings()
	layer.set_pattern(origin, old)
	await _settle()
	layer.set_cell(Vector2i(4, 3), old.get_cell_source_id(Vector2i.ZERO), Vector2i.ZERO, 0)
	await _settle()
	_check_pattern(layer, old, Vector2i(4, 3))
	_check(layer.get_cell_source_id(Vector2i(4, 6)) == -1, "Footprint overlap removes old members beyond the new building")
	# A native brush can stamp several neighboring anchors in one deferred update.
	layer.clear()
	layer.synchronize_buildings()
	for y: int in range(4, 8):
		layer.set_cell(Vector2i(4, y), old.get_cell_source_id(Vector2i.ZERO), Vector2i.ZERO, 0)
	await _settle()
	for cell: Vector2i in layer.get_used_cells():
		for member: Vector2i in layer.get_building_cells(cell):
			_check(layer.get_cell_source_id(member) == layer.get_cell_source_id(cell), "Batched overlapping brush strokes leave complete buildings")


func _test_history_and_loading(layer: BuildingTileMapLayer) -> void:
	layer.clear()
	layer.synchronize_buildings()
	var empty: PackedByteArray = layer.tile_map_data
	var pattern: TileMapPattern = MultihexBuildings.pattern_for(layer.tile_set, "building_stone_02_3hex", 2)
	var part: Vector2i = pattern.get_used_cells()[0]
	var cell: Vector2i = layer.map_pattern(Vector2i(5, 4), part, pattern)
	layer.set_cell(cell, pattern.get_cell_source_id(part), pattern.get_cell_atlas_coords(part), 0)
	var partial: PackedByteArray = layer.tile_map_data
	await _settle()
	var complete: PackedByteArray = layer.tile_map_data
	layer.tile_map_data = empty
	await _settle()
	_check(layer.get_used_cells().is_empty(), "Undoing the native atlas stamp removes automatically added members")
	layer.tile_map_data = partial
	await _settle()
	_check_pattern(layer, pattern, Vector2i(5, 4))
	layer.tile_map_data = complete
	await _settle()
	_check(layer.tile_map_data == complete, "Restoring a complete saved footprint leaves it unchanged")
	var loaded: BuildingTileMapLayer = load(BuildingVariations.LAYER_SCENE).instantiate() as BuildingTileMapLayer
	loaded.tile_map_data = partial
	add_child(loaded)
	_check_pattern(loaded, pattern, Vector2i(5, 4))
	var packed: PackedScene = PackedScene.new()
	_check(packed.pack(loaded) == OK, "Automatically added cells can be saved with the scene")
	var restored: BuildingTileMapLayer = packed.instantiate() as BuildingTileMapLayer
	add_child(restored)
	_check_pattern(restored, pattern, Vector2i(5, 4))
	loaded.free()
	restored.free()


func _test_baked_sight() -> void:
	var map: Map = Map.new()
	map.map_name = "Multihex Placement Regression"
	map.grid_size = Vector2i(6, 6)
	map.los_resource_path = "user://multihex_placement_los.tres"
	var layers: Node2D = Node2D.new()
	layers.name = "TileMapLayers"
	map.add_child(layers)
	var scenarios: Node2D = Node2D.new()
	scenarios.name = "Scenarios"
	map.add_child(scenarios)
	for name_value: String in ["GroundTileMapLayer", "TerrainTileMapLayer", "WallTileMapLayer"]:
		var layer: HexagonTileMapLayer = HexagonTileMapLayer.new()
		layer.name = name_value
		layer.tile_set = load(BuildingVariations.SHARED_TILE_SET) as TileSet
		layers.add_child(layer)
	var buildings: BuildingTileMapLayer = load(BuildingVariations.LAYER_SCENE).instantiate() as BuildingTileMapLayer
	layers.add_child(buildings)
	add_child(map)
	var stale: LosLookupData = LosLookupData.new()
	stale.los_lookup = {}
	_check(ResourceSaver.save(stale, map.los_resource_path) == OK, "The stale-cache fixture saves successfully")
	var pattern: TileMapPattern = MultihexBuildings.pattern_for(buildings.tile_set, "building_stone_01_3hex", 0)
	buildings.set_cell(Vector2i(2, 1), pattern.get_cell_source_id(Vector2i.ZERO), Vector2i.ZERO, 0)
	# Load immediately, before the deferred painting update, as match startup can.
	LOSHelper.load_prebaked_los(map)
	_check(buildings.get_used_cells().size() == 3, "Match startup completes pending single-cell stamps before baking")
	_check(LOSHelper.los_lookup.size() == 36, "Stale baked sight is replaced with the complete current board")
	var blocked: Dictionary = LOSHelper.check_los(buildings.map_to_local(Vector2i(2, 0)), buildings.map_to_local(Vector2i(2, 5)), 1, 0, 1, 0)
	_check(blocked["blocked"] and not LOSHelper.los_lookup[Vector2i(2, 0)].has(Vector2i(2, 5)), "Live and cached LOS both block a ray through the whole building")
	for cell: Vector2i in buildings.get_used_cells():
		_check(LOSHelper.is_sample_point_in_building(buildings.map_to_local(cell)) == 3, "Every stone fragment supplies defense 3 after match startup")
		var visible: bool = false
		for neighbor: Vector2i in buildings.get_surrounding_cells(cell):
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= 6 or neighbor.y >= 6 or buildings.get_cell_source_id(neighbor) >= 0:
				continue
			var result: Dictionary = LOSHelper.check_los(buildings.map_to_local(neighbor), buildings.map_to_local(cell), 1, 0, 1, 0)
			var row: Dictionary = LOSHelper.los_lookup[neighbor]
			_check(row.has(cell) == not bool(result["blocked"]), "Baked visibility agrees with live LOS for every occupied hex")
			if row.has(cell):
				visible = true
				_check(int(row[cell]["target_cover"]) >= 3 and row[cell]["target_cover"] == result["target_cover"], "Cached directional defense includes each secondary hex")
		_check(visible, "Each occupied hex has a defended visible approach")
	var refreshed: LosLookupData = load(map.los_resource_path) as LosLookupData
	_check(refreshed.building_layout_signature == buildings.los_layout_signature(), "Refreshed sight records the complete footprint signature")
	var cached: Dictionary = LOSHelper.los_lookup
	LOSHelper.load_prebaked_los(map)
	_check(is_same(LOSHelper.los_lookup, cached), "Unchanged retry reuses the refreshed sight lookup")
	buildings.clear()
	LOSHelper.load_prebaked_los(map)
	_check(LOSHelper.los_lookup[Vector2i(2, 0)].has(Vector2i(2, 5)) and LOSHelper.los_lookup[Vector2i(2, 0)][Vector2i(2, 5)]["target_cover"] == 0, "Removing the building clears cached blockers and defense")
	map.los_resource_path = "user://multihex_placement_missing.tres"
	var wood: TileMapPattern = MultihexBuildings.pattern_for(buildings.tile_set, "building_wood_02_2hex_b", 0)
	buildings.set_cell(Vector2i(2, 1), wood.get_cell_source_id(Vector2i.ZERO), Vector2i.ZERO, 0)
	LOSHelper.load_prebaked_los(map)
	_check(buildings.get_used_cells().size() == 2 and LOSHelper.los_lookup.size() == 36, "A new multihex map without baked sight initializes its complete footprint and lookup")
	for cell: Vector2i in buildings.get_used_cells():
		_check(LOSHelper.is_sample_point_in_building(buildings.map_to_local(cell)) == 2, "A new map gives defense 2 to both wooden building hexes")
	LOSHelper.unload_map()
	map.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://multihex_placement_los.tres"))


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error(message)
