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
	map = main.world.maps.get_node("Alderbrook2") as Map
	await get_tree().process_frame
	await get_tree().process_frame
	_test_deployments()
	_test_landscape()
	_test_los()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Alderbrook orchard checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_deployments() -> void:
	var scenario: Scenario = map.get_scenario(0)
	_check(scenario.scenario_id == "alderbrook_02_orchard_outpost" and scenario.campaign_mission == 3, "Orchard retains its campaign progress identity")
	_check(map.process_mode == Node.PROCESS_MODE_INHERIT, "The authored map retains normal processing in game")
	_check(scenario.get_units().size() == 9 and scenario.victory_conditions.size() == 6 and scenario.duration_s == 600.0, "The existing force, rules and time limit survive the redesign")
	var used: Dictionary[Vector2i, bool] = {}
	for unit: Unit in scenario.get_units():
		var cell: Vector2i = map.get_ground_layer().local_to_map(unit.position)
		_check(map.get_ground_layer().get_cell_source_id(cell) >= 0 and not used.has(cell), "Deployments occupy distinct playable ground")
		used[cell] = true
		var cover: TileData = map.get_building_layer().get_cell_tile_data(cell)
		_check(cover != null, "Each starting unit has a building or woodland position")
	var allied: HexagonTileMapLayer = scenario.get_objectives_layer(Globals.Team.ALLIES)
	var axis: HexagonTileMapLayer = scenario.get_objectives_layer(Globals.Team.AXIS)
	for marker: Vector2i in [Vector2i(15, 3), Vector2i(10, 8)]:
		var building: TileData = map.get_building_layer().get_cell_tile_data(marker)
		_check(building != null and str(building.get_custom_data("name")) in ["Stone Building", "Wood Building"], "Both objectives occupy actual covered farm buildings")
		_check(allied.get_cell_tile_data(marker) != null and axis.get_cell_tile_data(marker) != null, "Both sides can plan around the farmhouse and barn")


func _test_landscape() -> void:
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	_check(map.grid_size == Vector2i(22, 16) and ground.get_used_cells().size() == 352, "The expanded orchard offers room for separate approaches")
	var orchards: int = 0
	for cell: Vector2i in map.get_terrain_layer().get_used_cells():
		if str(map.get_terrain_layer().get_cell_tile_data(cell).get_custom_data("name")) == "Orchard":
			orchards += 1
	_check(orchards >= 70, "Orchards form the principal terrain feature")
	var roads: HexagonTileMapLayer = map.get_road_layer()
	var north: bool = false
	var east: bool = false
	var west: bool = false
	for cell: Vector2i in roads.get_used_cells():
		north = north or cell.y == 0
		east = east or cell.x == map.grid_size.x - 1
		west = west or cell.x == 0
		_check(map.get_building_layer().get_cell_source_id(cell) < 0, "Road lanes stay free of woodland and buildings")
	_check(north and east and not west, "The estate road turns from the north to the east instead of crossing west to east")
	var walls: WallTileMapLayer = map.get_wall_layer() as WallTileMapLayer
	var kinds: Dictionary[int, int] = {1: 0, 2: 0}
	for cell: Vector2i in walls.get_used_cells():
		var data: TileData = walls.get_cell_tile_data(cell)
		var cover: int = int(data.get_custom_data("cover"))
		_check(ConnectedWalls.is_barrier(data) and kinds.has(cover), "Estate boundaries supply directional hedge or stone cover")
		kinds[cover] += 1
		for side: int in range(6):
			if (walls.get_edge_mask(cell) & (1 << side)) == 0:
				continue
			var neighbor: Vector2i = walls.get_neighbor_cell(cell, ConnectedWalls.SIDES[side])
			_check(roads.get_cell_source_id(cell) < 0 and roads.get_cell_source_id(neighbor) < 0, "Boundary gaps keep the farm lanes open")
			_check((walls.get_edge_mask(neighbor) & (1 << ((side + 3) % 6))) == 0, "Each hedge or wall edge has one owner")
	_check(kinds[1] >= 40 and kinds[2] >= 6, "Orchard hedges and the stone farmhouse court both provide cover")


func _test_los() -> void:
	var data: LosLookupData = load(map.los_resource_path) as LosLookupData
	LOSHelper.ground_layer = map.get_ground_layer()
	LOSHelper.terrain_layer = map.get_terrain_layer()
	LOSHelper.building_layer = map.get_building_layer()
	LOSHelper.wall_layer = map.get_wall_layer()
	LOSHelper.road_layer = map.get_road_layer()
	LOSHelper.grid_size = map.grid_size
	_check(data.building_layout_signature == LOSHelper.building_layout_signature(), "Baked visibility uses the redesigned building and woodland positions")
	_check(data.wall_layout_signature == LOSHelper.wall_layout_signature(), "Baked visibility includes the new orchard hedges and courtyard walls")
	LOSHelper.begin_los_bake()
	_check(data.bake_layout_signature == LOSHelper.bake_layout_signature(), "The complete visibility fingerprint matches the imported battlefield")
	LOSHelper.end_los_bake()
	var cells: Array[Vector2i] = map.get_ground_layer().get_used_cells()
	for cell: Vector2i in cells:
		_check(data.los_lookup.has(cell), "Every playable orchard cell has baked visibility")
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 1754
	for index: int in range(300):
		var origin: Vector2i = cells[random.randi_range(0, cells.size() - 1)]
		var target: Vector2i = cells[random.randi_range(0, cells.size() - 1)]
		if origin == target:
			continue
		var current: Dictionary = LOSHelper.check_los(map.get_ground_layer().map_to_local(origin), map.get_ground_layer().map_to_local(target), 1, 0, 1, 0)
		var saved: Dictionary = data.los_lookup.get(origin, {})
		_check(saved.has(target) == not bool(current["blocked"]), "Saved and live visibility agree across the new orchard compartments")
	LOSHelper.unload_map()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
