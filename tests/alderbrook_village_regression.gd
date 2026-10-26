extends Node

var checks: int = 0
var failures: int = 0
var map: Map
var main: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	map = main.world.maps.get_node("Alderbrook5") as Map
	await get_tree().process_frame
	_test_content()
	_test_routes()
	_test_footprints()
	_test_los()
	main.queue_free()
	await get_tree().process_frame
	print("Alderbrook village checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_content() -> void:
	var scenario: Scenario = map.get_scenario(0)
	_check(scenario.scenario_id == "alderbrook_05_battle_for_alderbrook" and scenario.campaign_mission == 6, "Campaign identity stays compatible with saved progress")
	_check(scenario.get_units().size() == 31 and scenario.victory_conditions.size() == 12, "Existing company forces and victory rules are retained")
	var used: Dictionary[Vector2i, bool] = {}
	for unit: Unit in scenario.get_units():
		var cell: Vector2i = map.get_ground_layer().local_to_map(unit.position)
		_check(map.get_ground_layer().get_cell_source_id(cell) >= 0 and not used.has(cell), "Every unit deploys on a distinct playable hex")
		used[cell] = true
	for marker: Array in AlderbrookVillageLayout.ALLIED_MARKERS:
		if marker[0] == 4:
			continue
		var cell: Vector2i = Vector2i(marker[1], marker[2])
		var data: TileData = map.get_building_layer().get_cell_tile_data(cell)
		_check(data != null and int(data.get_custom_data("building_hexes")) == 3, "Each objective occupies a complete three-hex landmark")
	var terrain_names: Dictionary[String, bool] = {}
	for cell: Vector2i in map.get_terrain_layer().get_used_cells():
		var label: String = str(map.get_terrain_layer().get_cell_tile_data(cell).get_custom_data("name"))
		_check(label in ["Woods", "Field", "Orchard"], "Vegetation terrain excludes the separate road layer")
		terrain_names[label] = true
	_check(terrain_names.size() == 3 and not map.get_road_layer().get_used_cells().is_empty(), "Roads, woodland, crops and orchards all appear")
	var kinds: Dictionary[int, int] = {0: 0, 1: 0}
	var walls: WallTileMapLayer = map.get_wall_layer() as WallTileMapLayer
	for cell: Vector2i in walls.get_used_cells():
		var data: TileData = walls.get_cell_tile_data(cell)
		var cover: int = int(data.get_custom_data("cover"))
		_check(ConnectedWalls.is_barrier(data) and cover in [1, 2], "Walls use the connected edge catalog")
		kinds[cover - 1] += 1
		var mask: int = walls.get_edge_mask(cell)
		for side: int in range(6):
			if (mask & (1 << side)) == 0:
				continue
			var neighbor: Vector2i = walls.get_neighbor_cell(cell, ConnectedWalls.SIDES[side])
			_check((walls.get_edge_mask(neighbor) & (1 << ((side + 3) % 6))) == 0, "A shared boundary has exactly one owner")
			_check(map.get_ground_layer().get_cell_source_id(cell) >= 0 and map.get_ground_layer().get_cell_source_id(neighbor) >= 0, "Barriers follow playable field and garden boundaries")
	_check(kinds[0] > 10 and kinds[1] >= 2, "Both hedgerows and stone garden walls provide cover")


func _test_routes() -> void:
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	var playable: Array[Vector2i] = ground.get_used_cells()
	var water: HexagonTileMapLayer = map.get_node("TileMapLayers/WaterTileMapLayer") as HexagonTileMapLayer
	_check(water.get_used_cells().size() == 4 and playable.size() == 464, "Only the four pond hexes are impassable")
	for cell: Vector2i in water.get_used_cells():
		_check(ground.get_cell_source_id(cell) < 0, "Pond cells have no movement point")
	var reached: Dictionary[Vector2i, bool] = {Vector2i(0, 8): true}
	var queue: Array[Vector2i] = [Vector2i(0, 8)]
	var cursor: int = 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for neighbor: Vector2i in ground.get_surrounding_cells(cell):
			if ground.get_cell_source_id(neighbor) >= 0 and not reached.has(neighbor):
				reached[neighbor] = true
				queue.append(neighbor)
	_check(reached.size() == playable.size(), "Country, all districts and the east exits remain connected")
	var roads: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in map.get_road_layer().get_used_cells():
		roads[cell] = true
		var building: TileData = map.get_building_layer().get_cell_tile_data(cell)
		_check(building == null or str(building.get_custom_data("name")) != "Woods", "Road verges have no hidden woodland footprint")
	var junctions: int = 0
	for cell: Vector2i in roads:
		var neighbors: int = 0
		for neighbor: Vector2i in ground.get_surrounding_cells(cell):
			if roads.has(neighbor):
				neighbors += 1
		if neighbors > 2:
			junctions += 1
	_check(junctions >= 6, "The streets branch and connect the three approaches")
	for cell: Vector2i in playable:
		_check(int(ground.get_cell_tile_data(cell).get_custom_data("elevation")) == 0, "Unsupported ASL elevation features are excluded")


func _test_footprints() -> void:
	var buildings: BuildingTileMapLayer = map.get_building_layer() as BuildingTileMapLayer
	var roots: Dictionary[String, bool] = {}
	var wood: int = 0
	var stone: int = 0
	var angles: Dictionary[int, bool] = {}
	for cell: Vector2i in buildings.get_used_cells():
		var data: TileData = buildings.get_cell_tile_data(cell)
		var label: String = str(data.get_custom_data("name"))
		if label == "Woods":
			continue
		_check(label in ["Stone Building", "Wood Building"], "Every house keeps its wood or stone defense category")
		var cover: int = 2
		if label == "Stone Building":
			cover = 3
			stone += 1
		else:
			wood += 1
		_check(int(data.get_custom_data("cover")) == cover, "Building cover matches its material")
		if int(data.get_custom_data("building_hexes")) < 2:
			angles[buildings.get_cell_atlas_coords(cell).x] = true
			continue
		var footprint: Array[Vector2i] = buildings.get_building_cells(cell)
		_check(footprint.size() == int(data.get_custom_data("building_hexes")), "Every multihex stamp has its full logical footprint")
		footprint.sort()
		roots[str(footprint)] = true
		for member: Vector2i in footprint:
			var part: TileData = buildings.get_cell_tile_data(member)
			_check(part != null and part.get_custom_data("building_id") == data.get_custom_data("building_id"), "Secondary footprint cells share the same building design")
			_check(map.get_ground_layer().get_cell_source_id(member) >= 0, "Every building part lies on playable ground")
	_check(roots.size() == 8, "All eight authored multihex landmarks and barns are present")
	_check(wood > stone and stone >= 12, "Timber houses predominate, with stone buildings in the town")
	_check(angles.size() == 6, "Single houses use all six orientations")


func _test_los() -> void:
	var data: LosLookupData = load(map.los_resource_path) as LosLookupData
	LOSHelper.ground_layer = map.get_ground_layer()
	LOSHelper.terrain_layer = map.get_terrain_layer()
	LOSHelper.building_layer = map.get_building_layer()
	LOSHelper.wall_layer = map.get_wall_layer()
	_check(data.building_layout_signature == LOSHelper.building_layout_signature(), "Baked LOS includes the complete building layout")
	_check(data.wall_layout_signature == LOSHelper.wall_layout_signature(), "Baked LOS includes the field and garden edges")
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	var cells: Array[Vector2i] = ground.get_used_cells()
	cells.sort()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 504131
	for index: int in range(1500):
		var origin: Vector2i = cells[random.randi_range(0, cells.size() - 1)]
		var target: Vector2i = cells[random.randi_range(0, cells.size() - 1)]
		if origin == target:
			continue
		var current: Dictionary = LOSHelper.check_los(ground.map_to_local(origin), ground.map_to_local(target), 1, 0, 1, 0)
		var saved: Dictionary = data.los_lookup[origin]
		_check(saved.has(target) == not bool(current["blocked"]), "Cached and live visibility agree on the redesigned terrain")
		if bool(current["blocked"]):
			continue
		for key: String in ["shooter_cover", "target_cover", "wall_cover", "hindrance", "target_concealment"]:
			_check(saved[target][key] == current[key], "Cached cover and hindrance match the authored layout")
	LOSHelper.unload_map()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
