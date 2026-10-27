extends Node

var checks: int = 0
var failures: int = 0
var map: Map


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.world.fully_freed.disconnect(main._on_fully_freed)
	map = main.world.maps.get_node("Alderbrook4") as Map
	await get_tree().process_frame
	await get_tree().process_frame
	_test_mission()
	_test_river()
	_test_boundaries()
	if not OS.get_cmdline_user_args().has("--layout-only"):
		_test_los()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Alderbrook crossings checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_mission() -> void:
	var scenario: Scenario = map.get_scenario(0)
	_check(scenario.scenario_id == "alderbrook_04_two_crossings" and scenario.campaign_mission == 5, "Two Crossings retains its campaign progress identity")
	_check(scenario.get_units().size() == 20 and scenario.victory_conditions.size() == 6 and scenario.duration_s == 720.0, "The existing forces, victory rules and duration are retained")
	var used: Dictionary[Vector2i, bool] = {}
	for unit: Unit in scenario.get_units():
		var cell: Vector2i = map.get_ground_layer().local_to_map(unit.position)
		_check(map.get_ground_layer().get_cell_source_id(cell) >= 0 and not used.has(cell), "Every unit deploys on distinct dry ground")
		_check(map.get_building_layer().get_cell_tile_data(cell) != null, "Each starting unit has woodland or building cover")
		used[cell] = true
	for cell: Vector2i in [Vector2i(15, 4), Vector2i(21, 13)]:
		var building: TileData = map.get_building_layer().get_cell_tile_data(cell)
		_check(building != null and int(building.get_custom_data("cover")) >= 2, "Each bridgehead objective occupies a covered building")
		for team: Globals.Team in [Globals.Team.ALLIES, Globals.Team.AXIS]:
			_check(scenario.get_objectives_layer(team).get_cell_source_id(cell) >= 0, "Both sides can plan around each bridgehead")
	_check(map.process_mode == Node.PROCESS_MODE_INHERIT, "The authored map retains normal processing")


func _test_river() -> void:
	var water: HexagonTileMapLayer = map.get_node("TileMapLayers/WaterTileMapLayer") as HexagonTileMapLayer
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	var graph: AStar2D = ground.astar
	var bridges: Array[int] = []
	var endpoints: int = 0
	for cell: Vector2i in water.get_used_cells():
		var neighbors: int = 0
		for neighbor: Vector2i in ground.get_surrounding_cells(cell):
			if water.get_cell_source_id(neighbor) >= 0:
				neighbors += 1
		if cell.y == 0 or cell.y == map.grid_size.y - 1:
			endpoints += 1
			_check(neighbors == 1, "The single-file channel enters and leaves the map at its ends")
		else:
			_check(neighbors == 2, "The river stays one hex wide through every bend, with no broad or branching section")
		if water.get_cell_source_id(cell) == 1:
			_check(ground.get_cell_source_id(cell) >= 0, "Each bridge retains a movement point")
			bridges.append(graph.get_closest_point(ground.map_to_local(cell)))
		else:
			_check(ground.get_cell_source_id(cell) < 0, "Unbridged river hexes remain impassable")
		_check(map.get_terrain_layer().get_cell_source_id(cell) < 0 and map.get_building_layer().get_cell_source_id(cell) < 0, "Vegetation and buildings cannot occupy the channel")
	_check(endpoints == 2 and bridges.size() == 2, "Exactly two single-hex bridges cross one continuous river")
	var start: int = graph.get_closest_point(ground.map_to_local(Vector2i(3, 5)))
	var target: int = graph.get_closest_point(ground.map_to_local(Vector2i(26, 5)))
	_check(not graph.get_id_path(start, target).is_empty(), "The bridge roads connect the two banks")
	for bridge: int in bridges:
		graph.set_point_disabled(bridge, true)
	_check(graph.get_id_path(start, target).is_empty(), "No diagonal gap or edge route bypasses the bridges")
	for bridge: int in bridges:
		graph.set_point_disabled(bridge, false)
		_check(not graph.get_id_path(start, target).is_empty(), "Either crossing alone provides a usable route between banks")
		graph.set_point_disabled(bridge, true)
	for bridge: int in bridges:
		graph.set_point_disabled(bridge, false)
	for unit: Unit in map.get_scenario(0).get_units():
		var cell: Vector2i = ground.local_to_map(unit.position)
		var origin: int = graph.get_closest_point(ground.map_to_local(cell))
		_check(not graph.get_id_path(origin, target).is_empty(), "Every deployment can reach the eastern exits")


func _test_boundaries() -> void:
	var roads: HexagonTileMapLayer = map.get_road_layer()
	var walls: WallTileMapLayer = map.get_wall_layer() as WallTileMapLayer
	var kinds: Dictionary[int, int] = {1: 0, 2: 0}
	for cell: Vector2i in roads.get_used_cells():
		_check(map.get_ground_layer().get_cell_source_id(cell) >= 0 and map.get_building_layer().get_cell_source_id(cell) < 0, "Road approaches remain clear and passable")
	for cell: Vector2i in walls.get_used_cells():
		var data: TileData = walls.get_cell_tile_data(cell)
		kinds[int(data.get_custom_data("cover"))] += 1
		for side: int in range(6):
			if (walls.get_edge_mask(cell) & (1 << side)) == 0:
				continue
			var neighbor: Vector2i = walls.get_neighbor_cell(cell, ConnectedWalls.SIDES[side])
			_check(map.get_ground_layer().get_cell_source_id(neighbor) >= 0, "Field boundaries stop before unbridged water")
			_check((walls.get_edge_mask(neighbor) & (1 << ((side + 3) % 6))) == 0, "Each wall or hedge edge has a single owner")
	_check(kinds[1] > 20 and kinds[2] > 5, "Hedges and stone bridgehead walls both provide directional cover")


func _test_los() -> void:
	var saved: LosLookupData = load(map.los_resource_path) as LosLookupData
	LOSHelper.ground_layer = map.get_ground_layer()
	LOSHelper.terrain_layer = map.get_terrain_layer()
	LOSHelper.building_layer = map.get_building_layer()
	LOSHelper.wall_layer = map.get_wall_layer()
	LOSHelper.road_layer = map.get_road_layer()
	LOSHelper.grid_size = map.grid_size
	_check(saved.building_layout_signature == LOSHelper.building_layout_signature(), "Baked visibility includes the new bridgehead buildings and bank woods")
	_check(saved.wall_layout_signature == LOSHelper.wall_layout_signature(), "Baked visibility includes the new field and hamlet boundaries")
	LOSHelper.begin_los_bake()
	_check(saved.bake_layout_signature == LOSHelper.bake_layout_signature(), "The full visibility fingerprint matches the imported battlefield")
	LOSHelper.end_los_bake()
	var cells: Array[Vector2i] = map.get_ground_layer().get_used_cells()
	for cell: Vector2i in cells:
		_check(saved.los_lookup.has(cell), "Every playable hex has baked visibility")
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 4104
	for index: int in range(300):
		var origin: Vector2i = cells[random.randi_range(0, cells.size() - 1)]
		var target: Vector2i = cells[random.randi_range(0, cells.size() - 1)]
		if origin == target:
			continue
		var live: Dictionary = LOSHelper.check_los(map.get_ground_layer().map_to_local(origin), map.get_ground_layer().map_to_local(target), 1, 0, 1, 0)
		_check(saved.los_lookup[origin].has(target) == not bool(live["blocked"]), "Saved and live visibility agree across the redesigned banks")
	LOSHelper.unload_map()


func _check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error(message)
