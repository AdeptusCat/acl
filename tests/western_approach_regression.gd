extends Node

const OBJECTIVES: Array[Vector2i] = [Vector2i(13, 4), Vector2i(20, 9), Vector2i(16, 14)]

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(6049)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_node("WesternApproach") as Map
	var scenario: Scenario = map.get_scenario(0)
	_check(scenario.released and scenario.previous_scenario == null and scenario.campaign_id.is_empty(), "Standalone scenario is available without campaign progress")
	_check(world.start_screen.get_lock_reason(scenario).is_empty(), "Normal mission selection leaves the alternative unlocked")
	_check(scenario.get_save_id() == "alderbrook_western_approach", "Alternative has an independent stable save identifier")
	_check(world.maps.get_node("Alderbrook5").get_scenario(0).get_save_id() == "alderbrook_05_battle_for_alderbrook", "Original finale remains installed with its original identifier")
	_check(map.campaign_name.is_empty() and map.use_terrain_palette, "Standalone map uses the terrain palette independently of campaign grouping")
	world.start_screen._on_scenario_button_pressed(map, scenario)
	_check(is_equal_approx(world.start_screen.time, 15.0), "Selecting the scenario applies its authored fifteen-minute duration")
	_check(scenario.get_units().size() == 31, "Alternative deploys the full company against fourteen defenders")
	_check(scenario.ai_fallback_policies.is_empty(), "Defenders have no exit fallback")
	var occupied: Dictionary[Vector2i, bool] = {}
	var identities: Dictionary[int, bool] = {}
	for unit: Unit in scenario.get_units():
		var hex: Vector2i = map.get_ground_layer().local_to_map(unit.position)
		_check(map.get_ground_layer().get_cell_source_id(hex) >= 0 and not occupied.has(hex), "Units deploy on distinct playable hexes")
		occupied[hex] = true
		var identity: int = Globals.make_key(unit.team, unit.company, unit.platoon, unit.squad)
		_check(not identities.has(identity), "Company and platoon command identities remain distinct")
		identities[identity] = true
		_check(unit.squad_loadout != null and unit.squad_loadout.team == unit.team, "Each deployment uses its faction's loadout")
	_test_terrain(map)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_check(Globals.get_units().size() == 31, "Real match startup registers the complete standalone roster")
	_check(is_equal_approx(world.game_controller.time_left_seconds, 900.0), "Real match uses the authored duration")
	for condition: VictoryCondition in scenario.victory_conditions:
		_check(condition is OccupyObjectiveCondition and VictoryConditionProgress.read(condition).valid, "All live objectives initialize without destruction or exit quotas")
	_check(not VictoryConditionProgress.outcome_complete(scenario.victory_conditions, Globals.Team.ALLIES, VictoryCondition.OutcomeLevel.MAJOR, false), "Attackers cannot win on startup")
	for unit: Unit in Globals.get_units():
		unit.squad_fire.process_mode = Node.PROCESS_MODE_DISABLED
		unit.stress_system.process_mode = Node.PROCESS_MODE_DISABLED
		unit.combat_stats_timer.stop()
	var planner: PlatoonAI = world.game_controller.platoon_ai
	for frame: int in range(2400):
		await get_tree().process_frame
		if not planner.squad_assignments.is_empty():
			break
	_check(planner.active and not planner.squad_assignments.is_empty(), "Enemy defense publishes real tactical assignments")
	_check(planner.company_command.uses_hierarchy(), "Defenders use company and platoon command")
	var player_planner: PlatoonAI = world.game_controller.get_node("PlatoonAi2") as PlatoonAI
	_check(not player_planner.active, "Player company retains manual control")
	world.process_mode = Node.PROCESS_MODE_DISABLED
	_test_capture(scenario)
	world.fully_freed.disconnect(main._on_fully_freed)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Western Approach checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_terrain(map: Map) -> void:
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	_check(ground.get_used_cells().size() == map.grid_size.x * map.grid_size.y, "Every hex is playable; no river or bridge bottleneck remains")
	var water: HexagonTileMapLayer = map.tile_map_layers.get_node("WaterTileMapLayer") as HexagonTileMapLayer
	_check(water.get_used_cells().is_empty(), "Alternative contains no water barrier")
	var los: LosLookupData = load(map.los_resource_path) as LosLookupData
	_check(los != null and los.los_lookup.size() == ground.get_used_cells().size(), "Baked line of sight covers the complete new terrain")
	var buildings: HexagonTileMapLayer = map.get_building_layer()
	_check(str(buildings.get_cell_tile_data(OBJECTIVES[0]).get_custom_data("name")) == "Stone Building", "Orchard objective has estate cover")
	_check(buildings.get_cell_source_id(OBJECTIVES[1]) < 0, "Market objective remains an open square")
	_check(str(buildings.get_cell_tile_data(OBJECTIVES[2]).get_custom_data("name")) == "Wood Building", "Workshop objective has timber cover")
	var paving: TileData = ground.get_cell_tile_data(OBJECTIVES[1])
	_check(str(paving.get_custom_data("art_family")) == "stone" and int(paving.get_custom_data("elevation")) == 0 and paving.get_collision_polygons_count(0) == 0, "Town paving changes appearance while retaining open-ground movement rules")
	_check(paving.material == TerrainPalette.material_for_family("stone", ground.get_viewport().use_hdr_2d), "Standalone town paving receives the stone palette")
	var paving_atlas: TileSetAtlasSource = ground.tile_set.get_source(ground.get_cell_source_id(OBJECTIVES[1])) as TileSetAtlasSource
	_check(paving_atlas.texture.get_image().get_pixel(64, 64).a > 0.95, "Town paving rasterizes as solid terrain rather than an empty SVG pattern")
	var country_houses: int = 0
	var town_houses: int = 0
	for cell: Vector2i in buildings.get_used_cells():
		if str(buildings.get_cell_tile_data(cell).get_custom_data("name")) not in ["Stone Building", "Wood Building"]:
			continue
		if cell.x < 10:
			country_houses += 1
		elif cell.x >= 17:
			town_houses += 1
	_check(town_houses > country_houses * 4, "Building density increases from farmland to town")
	# Remove the entire central approach to prove the northern and southern flanks survive.
	var graph: AStar2D = ground.astar
	var disabled: Array[int] = []
	for cell: Vector2i in ground.get_used_cells():
		if cell.x >= 8 and cell.x <= 18 and cell.y >= 7 and cell.y <= 10:
			var id: int = ground.pathfinding_get_point_id(cell)
			graph.set_point_disabled(id, true)
			disabled.append(id)
	for row: int in [4, 14]:
		var from: int = ground.pathfinding_get_point_id(Vector2i(3, row))
		var to: int = ground.pathfinding_get_point_id(Vector2i(24, row))
		_check(not graph.get_id_path(from, to).is_empty(), "A flank still connects country to town when the center is unavailable")
	for id: int in disabled:
		graph.set_point_disabled(id, false)
	var terrain: HexagonTileMapLayer = map.get_terrain_layer()
	var roads: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in terrain.get_used_cells():
		if str(terrain.get_cell_tile_data(cell).get_custom_data("name")) == "Road":
			roads[cell] = true
			_check(buildings.get_cell_source_id(cell) < 0, "Roads never overlap hidden building or woodland cover")
	var reached: Dictionary[Vector2i, bool] = {}
	var frontier: Array[Vector2i] = []
	for cell: Vector2i in roads:
		frontier.append(cell)
		break
	var cursor: int = 0
	while cursor < frontier.size():
		var cell: Vector2i = frontier[cursor]
		cursor += 1
		if reached.has(cell):
			continue
		reached[cell] = true
		for neighbor: Vector2i in ground.get_surrounding_cells(cell):
			if roads.has(neighbor) and not reached.has(neighbor):
				frontier.append(neighbor)
	_check(reached.size() == roads.size(), "All three lanes and diagonal streets form one connected road network")


func _test_capture(scenario: Scenario) -> void:
	var allies: Array[Unit] = []
	for unit: Unit in Globals.get_units():
		if unit.team == Globals.Team.AXIS:
			unit.current_hex = Vector2i(27, 17)
		elif unit.squad_type == Globals.SquadType.Rifle:
			allies.append(unit)
	for index: int in range(3):
		allies[index].current_hex = OBJECTIVES[index]
	for condition: VictoryCondition in scenario.victory_conditions:
		condition.advance_time(29.0)
	_check(not VictoryConditionProgress.outcome_complete(scenario.victory_conditions, Globals.Team.ALLIES, VictoryCondition.OutcomeLevel.MAJOR, false), "Major victory requires the full occupation time")
	for condition: VictoryCondition in scenario.victory_conditions:
		condition.advance_time(1.0)
	_check(VictoryConditionProgress.outcome_complete(scenario.victory_conditions, Globals.Team.ALLIES, VictoryCondition.OutcomeLevel.MAJOR, false), "Holding all three districts wins before the deadline")
	allies[0].current_hex = Vector2i(4, 4)
	for condition: VictoryCondition in scenario.victory_conditions:
		condition.advance_time(0.1)
	_check(not VictoryConditionProgress.outcome_complete(scenario.victory_conditions, Globals.Team.ALLIES, VictoryCondition.OutcomeLevel.MAJOR, false), "Losing one district invalidates simultaneous major control")
	_check(not VictoryConditionProgress.outcome_complete(scenario.victory_conditions, Globals.Team.ALLIES, VictoryCondition.OutcomeLevel.MINOR, false), "Market-only control cannot award minor victory early")
	_check(VictoryConditionProgress.outcome_complete(scenario.victory_conditions, Globals.Team.ALLIES, VictoryCondition.OutcomeLevel.MINOR, true), "Holding the market earns minor victory at the deadline")
	for unit: Unit in Globals.get_units():
		if unit.team == Globals.Team.AXIS:
			unit.current_hex = OBJECTIVES[1]
			break
	for condition: VictoryCondition in scenario.victory_conditions:
		condition.advance_time(0.1)
	_check(not VictoryConditionProgress.outcome_complete(scenario.victory_conditions, Globals.Team.ALLIES, VictoryCondition.OutcomeLevel.MINOR, true), "Enemy presence contests the market and cancels minor control")


func _check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error(message)
