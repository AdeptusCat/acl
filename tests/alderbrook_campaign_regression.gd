extends Node

var checks: int = 0
var failures: int = 0
var main: Node
var world: Node
var campaign_maps: Array[Map] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(6049)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	world = main.world
	for map: Map in world.maps.get_children():
		if map.campaign_name == "Road to Alderbrook":
			campaign_maps.append(map)
	_check(campaign_maps.size() == 5, "The normal mission menu installs all five campaign maps")
	var mission: int = 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mission="):
			mission = argument.trim_prefix("--mission=").to_int()
	if mission > 0:
		await _test_match(mission - 1)
	else:
		_test_content()
		_test_progression()
		_test_bridges()
		_test_visual_variants()
		_test_roads()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Alderbrook campaign checks: ", checks, "; failures: ", failures, "; mission: ", mission)
	get_tree().quit(failures)


func _test_content() -> void:
	var kinds: Dictionary[String, bool] = {}
	var previous: Scenario
	var last_combat_count: int = 0
	var ids: Dictionary[String, bool] = {}
	var headings: int = 0
	for child: Node in world.start_screen.maps_v_box_container.get_children():
		var label: Label = child as Label
		if label != null and label.text == "Road to Alderbrook":
			headings += 1
	_check(headings == 1, "The five missions share one campaign heading")
	for index: int in range(campaign_maps.size()):
		var map: Map = campaign_maps[index]
		var scenario: Scenario = map.get_scenario(0)
		_check(scenario.campaign_mission == index + 1 and scenario.previous_scenario == previous, "Mission prerequisites form one ordered campaign")
		_check(scenario.player_team == Globals.Team.ALLIES and scenario.released, "Every campaign mission is released for the same player faction")
		_check(not ids.has(scenario.get_save_id()) and scenario.get_save_id().begins_with("alderbrook_"), "Campaign result identifiers are unique and stable")
		ids[scenario.get_save_id()] = true
		world.start_screen._on_scenario_button_pressed(map, scenario)
		_check(is_equal_approx(world.start_screen.time, scenario.duration_s / 60.0), "Mission selection applies its authored planning time")
		var combat: int = 0
		var keys: Dictionary[int, bool] = {}
		var cells: Dictionary[Vector2i, bool] = {}
		var counts: Dictionary[Globals.Team, int] = {Globals.Team.ALLIES: 0, Globals.Team.AXIS: 0}
		for node: Node in scenario.get_units():
			var unit: Unit = node as Unit
			if unit == null:
				continue
			var hex: Vector2i = map.get_ground_layer().local_to_map(unit.position)
			_check(map.get_ground_layer().get_cell_source_id(hex) >= 0 and not cells.has(hex), "Every unit starts on a distinct playable hex")
			cells[hex] = true
			var key: int = Globals.make_key(unit.team, unit.company, unit.platoon, unit.squad)
			_check(not keys.has(key), "Campaign command identities never overwrite another unit")
			keys[key] = true
			counts[unit.team] += 1
			_check(unit.squad_loadout != null and unit.squad_loadout.team == unit.team, "Deployment uses the correct faction loadout")
			if unit.team == scenario.player_team and not HqSupportPositionPolicy.is_headquarters(unit):
				combat += 1
		_check(combat > last_combat_count, "Player force size increases with each mission")
		last_combat_count = combat
		var los: LosLookupData = load(map.los_resource_path) as LosLookupData
		_check(los != null, "Every new map ships its baked line of sight resource")
		for cell: Vector2i in map.get_ground_layer().get_used_cells():
			_check(los.los_lookup.has(cell), "Baked line of sight covers every playable hex")
		for condition: VictoryCondition in scenario.victory_conditions:
			var team: Globals.Team = condition.team
			var objective: int = -1
			if condition is OccupyObjectiveCondition:
				kinds["occupation"] = true
				objective = int((condition as OccupyObjectiveCondition).objective_id)
			elif condition is DestroyUnitsCondition:
				kinds["destruction"] = true
				_check((condition as DestroyUnitsCondition).required_unit_count <= counts[Globals.get_enemy_team(team)], "Destruction quotas can be met by the deployed enemy force")
			elif condition is ExitUnitsCondition:
				kinds["exit"] = true
				objective = int((condition as ExitUnitsCondition).objective_id)
				_check((condition as ExitUnitsCondition).required_unit_count <= counts[team], "Exit quotas can be met by the deployed force")
			elif condition is PreventEnemyExitCondition:
				kinds["prevention"] = true
				objective = int((condition as PreventEnemyExitCondition).objective_id)
				team = Globals.get_enemy_team(team)
				_check(condition.test_at_scenario_end, "Exit prevention cannot win a mission at startup")
			if objective >= 0:
				var markers: Array[Vector2i] = _markers(scenario, team, objective)
				_check(not markers.is_empty(), "Each objective condition resolves to real markers for the correct side")
				for marker: Vector2i in markers:
					_check(map.get_ground_layer().get_cell_source_id(marker) >= 0, "Objectives never lie on impassable river cells")
		for policy: HoldToExitFallbackPolicy in scenario.ai_fallback_policies:
			_check(policy.configuration_error(scenario.victory_conditions).is_empty(), "Enemy withdrawal references valid campaign victory conditions")
		previous = scenario
	_check(kinds.size() == 4, "The campaign uses all four implemented victory-condition types")
	_test_quiet_start()


func _markers(scenario: Scenario, team: Globals.Team, id: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var layer: HexagonTileMapLayer = scenario.get_objectives_layer(team)
	for cell: Vector2i in layer.get_used_cells():
		var data: TileData = layer.get_cell_tile_data(cell)
		if data != null and int(data.get_custom_data("objective_id")) == id:
			result.append(cell)
	return result


func _test_quiet_start() -> void:
	var map: Map = campaign_maps[0]
	var scenario: Scenario = map.get_scenario(0)
	for first: Unit in scenario.get_units():
		for second: Unit in scenario.get_units():
			if first.team == second.team:
				continue
			var distance: int = map.get_ground_layer().cube_distance(map.get_ground_layer().local_to_cube(first.position), map.get_ground_layer().local_to_cube(second.position))
			var range: int = 0
			for soldier: SoldierLoadout in first.squad_loadout.soldiers:
				var weapon: WeaponSpec = soldier.resolve_weapon()
				range = maxi(range, weapon.range_hexes)
			_check(distance > range, "The opener starts outside immediate enemy weapon range")


func _test_progression() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://matches"))
	var first: Scenario = campaign_maps[0].get_scenario(0)
	_check(world.start_screen.get_lock_reason(first).is_empty(), "The opening patrol is available without a prior result")
	for index: int in range(1, campaign_maps.size()):
		var previous: Scenario = campaign_maps[index - 1].get_scenario(0)
		var next: Scenario = campaign_maps[index].get_scenario(0)
		var path: String = "user://matches/" + previous.get_save_id() + ".tres"
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_check(not world.start_screen.get_lock_reason(next).is_empty(), "Later missions remain locked until the preceding mission is won")
		var save: MatchSaveData = MatchSaveData.new()
		save.scenario_id = previous.scenario_id
		save.player_team = previous.player_team
		save.winner_team = Globals.get_enemy_team(previous.player_team)
		ResourceSaver.save(save, path)
		_check(not world.start_screen.get_lock_reason(next).is_empty(), "A defeat does not advance the campaign")
		save.winner_team = save.player_team
		ResourceSaver.save(save, path)
		_check(world.start_screen.get_lock_reason(next).is_empty(), "A victory unlocks the next campaign mission")
		var title: String = previous.scenario_name
		previous.scenario_name = "Edited briefing title"
		_check(world.start_screen.get_lock_reason(next).is_empty(), "Editing a mission title preserves saved campaign progress")
		previous.scenario_name = title
		save.player_team = Globals.get_enemy_team(previous.player_team)
		save.winner_team = save.player_team
		ResourceSaver.save(save, path)
		_check(not world.start_screen.get_lock_reason(next).is_empty(), "A result for the opposite player faction cannot unlock the campaign")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_bridges() -> void:
	for index: int in [3]:
		var map: Map = campaign_maps[index]
		var graph: AStar2D = map.get_ground_layer().astar
		var from: int = graph.get_closest_point(map.get_ground_layer().map_to_local(Vector2i(3, 4)))
		var to: int = graph.get_closest_point(map.get_ground_layer().map_to_local(Vector2i(map.grid_size.x - 4, 4)))
		_check(not graph.get_id_path(from, to).is_empty(), "The authored bridges connect both banks")
		var disabled: Array[int] = []
		var water: HexagonTileMapLayer = map.tile_map_layers.get_node("WaterTileMapLayer") as HexagonTileMapLayer
		for cell: Vector2i in water.get_used_cells():
			if water.get_cell_source_id(cell) == 1:
				var id: int = graph.get_closest_point(map.get_ground_layer().map_to_local(cell))
				graph.set_point_disabled(id, true)
				disabled.append(id)
			else:
				_check(map.get_ground_layer().get_cell_source_id(cell) < 0, "River water is impassable away from bridge cells")
		_check(graph.get_id_path(from, to).is_empty(), "There is no hidden path around the river barrier")
		for id: int in disabled:
			graph.set_point_disabled(id, false)


func _test_visual_variants() -> void:
	var families: Dictionary[String, Dictionary] = {
		"open_ground_green": {}, "woods_green": {}, "field_wheat": {}, "field_green_rows": {}, "orchard_green": {},
	}
	var family_names: Dictionary[String, String] = {"woods": "woods_green", "wheat": "field_wheat", "crops": "field_green_rows", "orchard": "orchard_green"}
	var images: Dictionary[Texture2D, Image] = {}
	for map: Map in campaign_maps:
		var ground: HexagonTileMapLayer = map.get_ground_layer()
		var terrain: HexagonTileMapLayer = map.get_terrain_layer()
		var buildings: HexagonTileMapLayer = map.get_building_layer()
		var crops: Dictionary[String, bool] = {}
		for layer: HexagonTileMapLayer in map.get_tilemap_layers():
			_check(layer.tile_set.tile_size == Vector2i(128, 128), "All map layers use matching 128-pixel spacing")
		for layer: HexagonTileMapLayer in [ground, terrain]:
			for cell: Vector2i in layer.get_used_cells():
				var source: TileSetAtlasSource = layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
				var data: TileData = layer.get_cell_tile_data(cell)
				var family: String = ""
				var file: String = source.texture.resource_path.get_file().get_basename()
				if file.begins_with("open_ground_green_"):
					family = "open_ground_green"
				elif data.has_custom_data("art_family"):
					family = family_names.get(str(data.get_custom_data("art_family")), "")
				if family == "":
					continue
				families[family][str([file, layer.get_cell_atlas_coords(cell)])] = true
				_check(source.texture_region_size == Vector2i(128, 128), "Terrain images match their 128-pixel cells")
				if family == "open_ground_green":
					_check(int(data.get_custom_data("elevation")) == 0 and data.get_collision_polygons_count(0) == 0, "Meadow art keeps open-ground rules")
				elif family == "woods_green":
					_check(bool(data.get_custom_data("woods")) and bool(data.get_custom_data("hindrance")) and bool(data.get_custom_data("blocking")), "Woodland art preserves LOS rules")
					var canopy: TileSetAtlasSource = buildings.tile_set.get_source(buildings.get_cell_source_id(cell)) as TileSetAtlasSource
					for texture: Texture2D in [source.texture, canopy.texture]:
						if not images.has(texture):
							images[texture] = texture.get_image()
					var terrain_image: Image = images[source.texture].get_region(source.get_tile_texture_region(layer.get_cell_atlas_coords(cell)))
					var canopy_image: Image = images[canopy.texture].get_region(canopy.get_tile_texture_region(buildings.get_cell_atlas_coords(cell)))
					_check(_same_visible_pixels(terrain_image, canopy_image) and int(buildings.get_cell_tile_data(cell).get_custom_data("cover")) == 1, "Terrain and cover layers use identical transparent canopy pixels in " + map.map_name + " at " + str(cell))
				else:
					_check(bool(data.get_custom_data("hindrance")) and not bool(data.get_custom_data("blocking")), "Fields and orchards retain their terrain rules")
					_check(ground.get_cell_source_id(cell) >= 0 and buildings.get_cell_source_id(cell) < 0, "Planting never overwrites rivers, buildings, or woods in " + map.map_name + " at " + str(cell))
					if family in ["field_wheat", "field_green_rows"]:
						crops[family] = true
		_check(crops.size() == 2, "Every mission has both wheat and green-crop plots")
	for family: String in families:
		_check(families[family].size() >= 3, "Multiple connected " + family + " pieces appear across the campaign")


func _same_visible_pixels(first: Image, second: Image) -> bool:
	first.convert(Image.FORMAT_RGBA8)
	second.convert(Image.FORMAT_RGBA8)
	var a: PackedByteArray = first.get_data()
	var b: PackedByteArray = second.get_data()
	if a.size() != b.size():
		return false
	for index: int in range(0, a.size(), 4):
		if a[index + 3] != b[index + 3]:
			return false
		# Import fills the RGB of fully transparent atlas padding from its neighbors.
		if a[index + 3] > 25:
			for channel: int in range(3):
				if a[index + channel] != b[index + channel]:
					return false
	return true


func _test_roads() -> void:
	for map: Map in campaign_maps:
		var ground: HexagonTileMapLayer = map.get_ground_layer()
		var terrain: HexagonTileMapLayer = map.get_terrain_layer()
		var buildings: HexagonTileMapLayer = map.get_building_layer()
		var water: HexagonTileMapLayer = map.tile_map_layers.get_node("WaterTileMapLayer") as HexagonTileMapLayer
		var corridor: Dictionary[Vector2i, bool] = {}
		var variants: Dictionary[Vector2i, bool] = {}
		var frontier: Array[Vector2i] = []
		for cell: Vector2i in terrain.get_used_cells():
			if str(terrain.get_cell_tile_data(cell).get_custom_data("name")) != "Road":
				continue
			corridor[cell] = true
			variants[terrain.get_cell_atlas_coords(cell)] = true
			_check(ground.get_cell_source_id(cell) >= 0 and buildings.get_cell_source_id(cell) < 0, "Road corridors have playable ground and no hidden woodland or buildings")
			_check(not bool(terrain.get_cell_tile_data(cell).get_custom_data("hindrance")) and not bool(terrain.get_cell_tile_data(cell).get_custom_data("blocking")), "Curved road pieces preserve open-road LOS rules")
			if cell.x == 0:
				frontier.append(cell)
		for cell: Vector2i in water.get_used_cells():
			if water.get_cell_source_id(cell) == 1:
				corridor[cell] = true
		_check(variants.size() >= 12, "Each mission uses distinct road pieces instead of a repeated chevron")
		_check(not frontier.is_empty(), "Each road network enters from the western map edge")
		var reached: Dictionary[Vector2i, bool] = {}
		for start: Vector2i in frontier:
			reached[start] = true
		var cursor: int = 0
		while cursor < frontier.size():
			var cell: Vector2i = frontier[cursor]
			cursor += 1
			for neighbor: Vector2i in ground.get_surrounding_cells(cell):
				if corridor.has(neighbor) and not reached.has(neighbor):
					reached[neighbor] = true
					frontier.append(neighbor)
		_check(reached.size() == corridor.size(), "All road and bridge pieces belong to continuous routes from the western bank")
		var eastern_connections: int = 0
		for cell: Vector2i in reached:
			if cell.x == map.grid_size.x - 1:
				eastern_connections += 1
		_check(eastern_connections > 0, "The curved road network reaches the eastern map edge")


func _test_match(index: int) -> void:
	var map: Map = campaign_maps[index]
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.time = scenario.duration_s / 60.0
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	var expected: int = scenario.get_units().size()
	_check(world.game_controller.unit_container.get_child_count() > 0 and Globals.get_units().size() == world.game_controller.unit_container.get_child_count(), "Mission startup registers only its own deployed units")
	_check(expected == 0, "All selected mission units move into the active battle container")
	_check(is_equal_approx(world.game_controller.time_left_seconds, scenario.duration_s), "The actual match uses the mission's intended duration")
	_check(not VictoryConditionProgress.outcome_complete(scenario.victory_conditions, scenario.player_team, VictoryCondition.OutcomeLevel.MAJOR, false), "No campaign mission awards player victory at startup")
	for condition: VictoryCondition in scenario.victory_conditions:
		var state: VictoryConditionProgress = VictoryConditionProgress.read(condition)
		_check(state.valid, "Each live victory condition has initialized objective state")
	for unit: Unit in Globals.get_units():
		unit.squad_fire.process_mode = Node.PROCESS_MODE_DISABLED
		unit.stress_system.process_mode = Node.PROCESS_MODE_DISABLED
		unit.combat_stats_timer.stop()
	var planner: PlatoonAI = world.game_controller.platoon_ai
	for frame: int in range(2400):
		await get_tree().process_frame
		if not planner.squad_assignments.is_empty():
			break
	_check(planner.active and not planner.squad_assignments.is_empty(), "Enemy tactical planning publishes actual mission orders")
	if index >= 2:
		_check(planner.company_command.uses_hierarchy(), "Larger enemy forces use company command")
		for formation: CompanyPlatoon in planner.company_command.platoons.values():
			if formation.support != null:
				_check(formation.support.support_firepower() > 0.0, "Mortar-only detachments cannot block maneuver as designated covering platoons")
	if index == 4:
		_check(planner.goal_director.active_fallback == null, "The final defense begins with its hold mission")
		_check(planner.goal_director.diagnostics.has("Exit to deny enemy victory deferred until the linked hold-to-exit fallback activates"), "Enemy escape is deferred until the town defense fails")
		_test_mortar_support_selection(planner.company_command)
	world._on_game_controller_show_winner(scenario.player_team, VictoryCondition.OutcomeLevel.MAJOR, false)
	var path: String = "user://matches/" + scenario.get_save_id() + ".tres"
	var saved: MatchSaveData = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MatchSaveData
	_check(saved != null and saved.match_id == scenario.get_save_id() and saved.scenario_id == scenario.scenario_id, "The real result handler saves stable campaign identifiers")
	if index + 1 < campaign_maps.size():
		_check(world.start_screen.get_lock_reason(campaign_maps[index + 1].get_scenario(0)).is_empty(), "A real saved match result unlocks the next mission")


func _test_mortar_support_selection(command: CompanyAI) -> void:
	var mortar: CompanyPlatoon = command.platoons[Vector2i(0, 0)]
	var rifle: CompanyPlatoon = command.platoons[Vector2i(0, 1)]
	var maneuver: CompanyPlatoon = command.platoons[Vector2i(0, 2)]
	var mortar_task: ScenarioGoalTask = mortar.task
	var rifle_task: ScenarioGoalTask = rifle.task
	mortar.task = null
	rifle.task = null
	_check(command._choose_support([mortar, rifle], maneuver) == rifle, "Company covering-fire selection uses the rifle platoon instead of a mortar-only detachment")
	mortar.task = mortar_task
	rifle.task = rifle_task


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
