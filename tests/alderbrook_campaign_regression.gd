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
	_check(campaign_maps.size() == 6, "The normal mission menu installs the prologue and five campaign maps")
	_test_mission_catalog()
	var mission: int = 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mission="):
			mission = argument.trim_prefix("--mission=").to_int()
	if OS.get_cmdline_user_args().has("--prologue-layout-only"):
		_test_prologue()
		_test_roads()
	elif mission > 0:
		if mission <= 2:
			_test_prologue()
			_test_quiet_start()
		await _test_match(mission - 1)
	elif not OS.get_cmdline_user_args().has("--catalog-only"):
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


func _test_mission_catalog() -> void:
	var expected: Array[Scenario] = []
	for map: Map in world.maps.get_children():
		if OS.is_debug_build() or campaign_maps.has(map):
			expected.append_array(map.get_scenarios())
	_check(world.start_screen.scenario_buttons.size() == expected.size(), "The mission catalog contains exactly the missions available in this build")
	for scenario: Scenario in expected:
		_check(world.start_screen.scenario_buttons.has(scenario), "Available missions appear in the actual selection screen: " + scenario.scenario_name)
	if OS.is_debug_build():
		_check(expected.size() > 5 and world.start_screen.scenario_buttons.has(world.maps.get_node("DefaultMap").get_scenario(0)), "Debug builds retain the development maps alongside Alderbrook")
	else:
		_check(expected.size() == 6, "Release builds expose the prologue and five Alderbrook missions")
		var headings: Array[String] = []
		for child: Node in world.start_screen.maps_v_box_container.get_children():
			if child is Label:
				headings.append((child as Label).text)
		_check(headings == ["Road to Alderbrook"], "Release builds do not show headings for standalone or development maps")
		for scenario: Scenario in world.start_screen.scenario_buttons:
			_check(scenario.campaign_id == "road_to_alderbrook", "Every selectable release mission belongs to the Alderbrook campaign")


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
	_check(headings == 1, "All six missions share one campaign heading")
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
			_check(map.get_ground_layer().get_cell_source_id(hex) >= 0 and not cells.has(hex), "Distinct playable deployment: %s / %s / %s" % [map.name, unit.name, hex])
			cells[hex] = true
			var key: int = Globals.make_key(unit.team, unit.company, unit.platoon, unit.squad)
			_check(not keys.has(key), "Distinct command identity: %s / %s / %s" % [map.name, unit.name, key])
			keys[key] = true
			counts[unit.team] += 1
			_check(unit.squad_loadout != null and unit.squad_loadout.team == unit.team, "Deployment uses the correct faction loadout")
			if unit.team == scenario.player_team and not HqSupportPositionPolicy.is_headquarters(unit):
				combat += 1
		if index > 1:
			_check(combat > last_combat_count, "Player force size increases after the restricted patrol")
		elif index == 1:
			_check(combat == 1 and combat < last_combat_count, "Quiet Approach reduces the prologue force to one rifle squad")
			_check(scenario.offboard_batteries.is_empty() and scenario.get_reinforcements().is_empty(), "The patrol has no off-map support or reinforcements")
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
		for policy: EscapeMissionPolicy in scenario.ai_escape_policies:
			_check(policy.configuration_error(scenario.victory_conditions).is_empty(), "Escape missions reference the actual campaign exit condition")
		if index == 3:
			_check(scenario.ai_escape_policies.size() == 1 and scenario.ai_escape_policies[0].exit_condition.team == Globals.Team.AXIS, "Roadblock explicitly assigns the Axis column an escape mission")
		else:
			_check(scenario.ai_escape_policies.is_empty(), "Other campaign missions retain their existing strategic policies")
		previous = scenario
	_check(kinds.size() == 4, "The campaign uses all four implemented victory-condition types")
	_test_quiet_start()
	_test_prologue()


func _test_prologue() -> void:
	var scenario: Scenario = campaign_maps[0].get_scenario(0)
	_check(scenario.scenario_id == "alderbrook_00_opening_the_road", "The prologue leads the campaign with its own stable save ID")
	_test_prologue_landscape(campaign_maps[0])
	var counts: Dictionary[int, int] = {}
	var defenders: int = 0
	for unit: Unit in scenario.get_units():
		if unit.team == scenario.player_team:
			counts[unit.squad_type] = counts.get(unit.squad_type, 0) + 1
		else:
			defenders += 1
	_check(counts.get(Globals.SquadType.Rifle, 0) == 3 and counts.get(Globals.SquadType.MG, 0) == 2, "The prologue fields three rifle squads and two MG teams")
	_check(counts.get(Globals.SquadType.PLATOON_HEADQUARTERS, 0) == 1 and counts.get(Globals.SquadType.COMPANY_HEADQUARTERS, 0) == 1 and counts.get(Globals.SquadType.MORTAR, 0) == 1, "The prologue includes both HQ levels and an onboard mortar")
	_check(defenders == 4, "A small dispersed defence faces the full player force")
	_check(scenario.offboard_batteries.size() == 1, "The prologue supplies off-map artillery")
	if scenario.offboard_batteries.size() == 1:
		var battery: OffboardBattery = scenario.offboard_batteries[0]
		_check(battery.is_valid() and battery.team == scenario.player_team and battery.gun_count == 4 and battery.rounds == 48, "The four-gun artillery battery is valid and supplied")
	var major_holds: int = 0
	var minor_holds: int = 0
	for condition: VictoryCondition in scenario.victory_conditions:
		if condition.team != scenario.player_team:
			continue
		_check(condition is OccupyObjectiveCondition, "Prologue victory requires securing ground rather than destroying every defender")
		if condition.outcome_level == VictoryCondition.OutcomeLevel.MAJOR:
			major_holds += 1
		else:
			minor_holds += 1
	_check(major_holds == 2 and minor_holds == 1, "Both objectives are needed for major victory; the road alone permits minor victory")


func _test_prologue_landscape(map: Map) -> void:
	_check(map.grid_size.x >= 28 and map.grid_size.y >= 20, "The prologue has room for separate field and farm approaches")
	var roads: HexagonTileMapLayer = map.get_road_layer()
	var north: bool = false
	var south: bool = false
	var west_or_east: bool = false
	for cell: Vector2i in roads.get_used_cells():
		north = north or cell.y == 0
		south = south or cell.y == map.grid_size.y - 1
		west_or_east = west_or_east or cell.x == 0 or cell.x == map.grid_size.x - 1
		_check(map.get_building_layer().get_cell_source_id(cell) < 0, "The winding road stays clear of buildings and woodland")
	_check(north and south and not west_or_east, "The prologue road runs south to north rather than across the map")
	var kinds: Dictionary[int, int] = {1: 0, 2: 0}
	var walls: WallTileMapLayer = map.get_wall_layer() as WallTileMapLayer
	for cell: Vector2i in walls.get_used_cells():
		var data: TileData = walls.get_cell_tile_data(cell)
		_check(ConnectedWalls.is_barrier(data), "Prologue boundaries use directional edge cover")
		var cover: int = int(data.get_custom_data("cover"))
		kinds[cover] = kinds.get(cover, 0) + 1
		for side: int in range(6):
			if (walls.get_edge_mask(cell) & (1 << side)) == 0:
				continue
			var neighbor: Vector2i = walls.get_neighbor_cell(cell, ConnectedWalls.SIDES[side])
			_check(roads.get_cell_source_id(cell) < 0 and roads.get_cell_source_id(neighbor) < 0, "Boundary gates leave the road verges open")
			_check((walls.get_edge_mask(neighbor) & (1 << ((side + 3) % 6))) == 0, "Each field boundary has a single edge owner")
	_check(kinds[1] >= 60 and kinds[2] >= 12, "Hedged fields and stone courts both provide substantial cover")
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	var start: int = ground.astar.get_closest_point(ground.map_to_local(Vector2i(5, 17)))
	for target: Vector2i in [Vector2i(19, 9), Vector2i(23, 13)]:
		var finish: int = ground.astar.get_closest_point(ground.map_to_local(target))
		_check(not ground.astar.get_id_path(start, finish).is_empty(), "Both objectives remain reachable from the southern deployment")


func _markers(scenario: Scenario, team: Globals.Team, id: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var layer: HexagonTileMapLayer = scenario.get_objectives_layer(team)
	for cell: Vector2i in layer.get_used_cells():
		var data: TileData = layer.get_cell_tile_data(cell)
		if data != null and int(data.get_custom_data("objective_id")) == id:
			result.append(cell)
	return result


func _test_quiet_start() -> void:
	var map: Map = campaign_maps[1]
	var scenario: Scenario = map.get_scenario(0)
	var rifles: int = 0
	var headquarters: int = 0
	var minor_retreat: bool = false
	for unit: Unit in scenario.get_units():
		if unit.team == scenario.player_team:
			if unit.squad_type == Globals.SquadType.Rifle:
				rifles += 1
			elif unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS:
				headquarters += 1
	_check(rifles == 1 and headquarters == 1 and scenario.offboard_batteries.is_empty() and scenario.get_reinforcements().is_empty(), "Quiet Approach has exactly the restricted rifle patrol without support")
	for condition: VictoryCondition in scenario.victory_conditions:
		if condition is OccupyObjectiveCondition and condition.team == scenario.player_team and condition.outcome_level == VictoryCondition.OutcomeLevel.MINOR:
			minor_retreat = (condition as OccupyObjectiveCondition).objective_id == OccupyObjectiveCondition.ObjectiveId.B and condition.test_at_scenario_end
	_check(minor_retreat, "The unsupported patrol can earn minor victory by holding rally point B")
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
	_check(world.start_screen.get_lock_reason(first).is_empty(), "The prologue is available without a prior result")
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
	for index: int in [4]:
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
					var canopy_id: int = buildings.get_cell_source_id(cell)
					_check(canopy_id >= 0, "Woodland has a cover layer: %s / %s" % [map.name, cell])
					if canopy_id < 0:
						continue
					var canopy: TileSetAtlasSource = buildings.tile_set.get_source(canopy_id) as TileSetAtlasSource
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
		_check(crops.size() == 2, "Wheat and crop plots: " + str(map.name))
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
		var roads: HexagonTileMapLayer = map.get_road_layer()
		var water: HexagonTileMapLayer = map.tile_map_layers.get_node("WaterTileMapLayer") as HexagonTileMapLayer
		var corridor: Dictionary[Vector2i, bool] = {}
		var variants: Dictionary[Vector2i, bool] = {}
		var frontier: Array[Vector2i] = []
		var prologue: bool = map.name == &"AlderbrookPrologue"
		for cell: Vector2i in roads.get_used_cells():
			corridor[cell] = true
			variants[roads.get_cell_atlas_coords(cell)] = true
			_check(ground.get_cell_source_id(cell) >= 0, "Road corridors have playable ground")
			_check(not bool(roads.get_cell_tile_data(cell).get_custom_data("hindrance")) and not bool(roads.get_cell_tile_data(cell).get_custom_data("blocking")), "Curved road pieces preserve open-road LOS rules")
			if (prologue and cell.y == map.grid_size.y - 1) or (not prologue and cell.x == 0):
				frontier.append(cell)
		for cell: Vector2i in water.get_used_cells():
			if water.get_cell_source_id(cell) == 1:
				corridor[cell] = true
		_check(variants.size() >= 12, "Each mission uses distinct road pieces instead of a repeated chevron")
		_check(not frontier.is_empty(), "Each road network enters from its deployment edge")
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
		_check(reached.size() == corridor.size(), "All road and bridge pieces belong to continuous routes from the deployment edge")
		var eastern_connections: int = 0
		for cell: Vector2i in reached:
			if (prologue and cell.y == 0) or (not prologue and cell.x == map.grid_size.x - 1):
				eastern_connections += 1
		_check(eastern_connections > 0, "The curved road network reaches its far map edge")


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
	if index == 0:
		var support: FireSupportController = world.game_controller.fire_support
		_check(support != null and support.assets.size() == 2, "The live prologue exposes onboard mortar and off-map artillery in the support tray")
		if support != null and support.assets.size() == 2:
			_check(support.available_guns(1) == 4 and support.ammunition(1) == 48, "The live artillery battery retains its four guns and ammunition")
			_check(support.request(1, Vector2i(19, 9), 15.0, FireSupportMission.Intensity.INTENSE), "The prologue artillery accepts an actual fire mission")
	var planner: PlatoonAI = world.game_controller.platoon_ai
	for frame: int in range(2400):
		await get_tree().process_frame
		if not planner.squad_assignments.is_empty():
			break
	_check(planner.active and not planner.squad_assignments.is_empty(), "Enemy tactical planning publishes actual mission orders")
	if index == 0:
		_test_prologue_guard(planner)
	if index >= 3:
		_check(planner.company_command.uses_hierarchy(), "Larger enemy forces use company command")
		for formation: CompanyPlatoon in planner.company_command.platoons.values():
			if formation.support != null:
				_check(formation.support.support_firepower() > 0.0, "Mortar-only detachments cannot block maneuver as designated covering platoons")
	if index == 5:
		_check(planner.goal_director.active_fallback == null, "The final defense begins with its hold mission")
		_check(planner.goal_director.diagnostics.has("Exit to deny enemy victory deferred until the linked hold-to-exit fallback activates"), "Enemy escape is deferred until the town defense fails")
		_test_mortar_support_selection(planner.company_command)
		_test_final_defense_losses(planner)
	world._on_game_controller_show_winner(scenario.player_team, VictoryCondition.OutcomeLevel.MAJOR, false)
	var path: String = "user://matches/" + scenario.get_save_id() + ".tres"
	var saved: MatchSaveData = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MatchSaveData
	_check(saved != null and saved.match_id == scenario.get_save_id() and saved.scenario_id == scenario.scenario_id, "The real result handler saves stable campaign identifiers")
	if index + 1 < campaign_maps.size():
		_check(world.start_screen.get_lock_reason(campaign_maps[index + 1].get_scenario(0)).is_empty(), "A real saved match result unlocks the next mission")


func _test_prologue_guard(planner: PlatoonAI) -> void:
	var found: bool = false
	for unit: Unit in planner.goal_assignments:
		var task: ScenarioGoalTask = planner.goal_assignments[unit]
		if task.kind != ScenarioGoalTask.Kind.OCCUPY:
			continue
		found = true
		_check(task.defend_from_cover, "The secured prologue outpost receives a covered defense duty")
		var assignment: Dictionary = planner.squad_assignments.get(unit, {})
		var result: PositionResult = assignment.get("result") as PositionResult
		_check(result != null and result.is_valid(), "The authored outpost has an available covered guard position")
		if result != null and result.is_valid():
			_check(result.profile_mode == PositionProfile.Mode.DEFEND and result.features.get("cover", 0.0) >= 0.1, "The prologue defender uses actual terrain or directional wall cover")
			_check(LOSHelper.get_hex_distance(result.target_hex, task.hex) <= ScenarioGoalTask.SECURED_DEFENSE_RADIUS, "The prologue guard remains within response distance of its objective")
	_check(found, "The prologue retains a guard assigned to its secured outpost")


func _test_final_defense_losses(planner: PlatoonAI) -> void:
	var goals: ScenarioGoalDirector = planner.goal_director
	var snapshot: InfluenceSnapshot = planner.influence_map_controller.snapshot
	var contacts_before: Array[InfluenceContact] = snapshot.get_defensive_contacts(planner.team)
	var holds: Array[OccupyObjectiveCondition] = []
	for condition: VictoryCondition in goals.conditions:
		if condition is OccupyObjectiveCondition and condition.team == planner.team:
			holds.append(condition as OccupyObjectiveCondition)
	_check(holds.size() == 3, "The final withdrawal policy covers all three authored town objectives")
	var positions: Dictionary[Unit, Vector2i] = {}
	var alive_before: Dictionary[Unit, bool] = {}
	var survivor: Unit
	for formation: CompanyPlatoon in planner.company_command.platoons.values():
		formation.planner.executor.cancel_all(true)
		formation.planner.position_stability.clear()
	for unit: Unit in planner.squads:
		positions[unit] = unit.current_hex
		alive_before[unit] = unit.alive
		unit.give_hold_order()
		unit.current_hex = holds[2].state.hexes[0]
		unit.current_cube = LOSHelper.ground_layer.map_to_cube(unit.current_hex)
		unit.position = LOSHelper.ground_layer.map_to_local(unit.current_hex)
		unit.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
		if unit.squad_type == Globals.SquadType.Rifle:
			survivor = unit
	var enemies: Array[Unit] = Globals.get_units_for_team(Globals.get_enemy_team(planner.team))
	var first: InfluenceContact = InfluenceContact.new()
	first.unit = enemies[0]
	first.hex = holds[0].state.hexes[0]
	first.observed = true
	snapshot.defensive_contacts[planner.team] = [first]
	goals.update(planner, 10000.0, 1000.0)
	goals.update(planner, 10000.0, 1007.0)
	_check(goals.active_fallback == null, "Capturing Alderbrook's linked objective does not send the whole enemy company to the exit")
	var second: InfluenceContact = InfluenceContact.new()
	second.unit = enemies[1]
	second.hex = holds[1].state.hexes[0]
	second.observed = true
	snapshot.defensive_contacts[planner.team] = [first, second]
	goals.update(planner, 0.0, 1008.0)
	goals.update(planner, 0.0, 1015.0)
	_check(goals.active_fallback == null, "Two captured town objectives still do not release a healthy defending company")
	for unit: Unit in planner.squads:
		if unit != survivor and not HqSupportPositionPolicy.is_headquarters(unit):
			unit.alive = false
	goals.update(planner, 10000.0, 1016.0)
	goals.update(planner, 10000.0, 1021.0)
	_check(goals.active_fallback == null, "Alderbrook's authored six-second confirmation applies to combined losses and depletion")
	goals.update(planner, 10000.0, 1022.0)
	_check(goals.active_fallback != null and goals.fallback_reason.contains("2/3 objectives lost"), "The real Alderbrook company withdraws after two objective losses and low strength persist")
	_check(goals.assignments.has(survivor) and goals.assignments[survivor].withdrawal, "The surviving town defender receives the actual exit mission")
	for unit: Unit in positions:
		unit.alive = alive_before[unit]
		unit.current_hex = positions[unit]
		unit.current_cube = LOSHelper.ground_layer.map_to_cube(unit.current_hex)
		unit.position = LOSHelper.ground_layer.map_to_local(unit.current_hex)
	snapshot.defensive_contacts[planner.team] = contacts_before


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
