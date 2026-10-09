extends Node

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(6049)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_child(1)
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var controller: InfluenceMapController = world.game_controller.influence_map_controller
	controller.create_maps(0.0)
	for step: int in range(1000):
		controller._process_los_rebuild()
		controller._process_budgeted_rebuild()
		if controller.snapshot != null and not controller.rebuild_pending:
			break
	_check(controller.snapshot != null, "The authored terrain publishes a complete position snapshot")
	var teams: Dictionary = {}
	var objective: Vector2i = controller.objectives_by_team[Globals.Team.AXIS]
	for unit: Unit in Globals.get_units():
		if unit.squad_type != Globals.SquadType.Rifle:
			continue
		teams[unit.team] = true
		_test_short_range_interception(controller, unit, objective)
	_check(teams.size() == 2, "Both teams exercise the authored interception regression")
	for team: int in teams:
		_test_reserve_crossing(controller, team)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Defense interception match checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_short_range_interception(controller: InfluenceMapController, unit: Unit, objective: Vector2i) -> void:
	# A rifle squad can lose its longer-range weapons; its remaining rifles must still defend locally.
	var weapons: Dictionary[Soldier, WeaponSpec] = {}
	for soldier: Soldier in unit.squad_fire.soldiers:
		if soldier.weapon != null:
			weapons[soldier] = soldier.weapon
			soldier.weapon = soldier.weapon.duplicate(true)
			soldier.weapon.range_hexes = mini(soldier.weapon.range_hexes, 5)
	for evidence: String in ["inferred", "observed", "remembered"]:
		var query: PositionQuery = PositionQuery.new()
		query.unit = unit
		query.team = unit.team
		query.objective_hex = objective
		query.snapshot = controller.snapshot
		query.defense_responsibility = PositionQuery.Responsibility.COVER_APPROACH
		query.snapshot.defensive_contacts[unit.team] = []
		if evidence != "inferred":
			var contact: InfluenceContact = InfluenceContact.new()
			contact.hex = Vector2i(0, 9)
			contact.observed = evidence == "observed"
			contact.last_seen_at = query.snapshot.captured_at
			contact.firepower = 0.01
			query.snapshot.defensive_contacts[unit.team] = [contact]
		var area: DefenseAreaJob = DefenseAreaJob.new()
		area.start(query.snapshot, unit.team, query.objective_hex, 8, 12, [])
		area.advance(-1)
		query.defense_area = area.result
		query.assigned_sector = 3
		query.sector_cells = area.result.covered_positions
		# Preserve the other squad's objective guard and the reserve's woodland position.
		for friendly: Unit in Globals.get_units_for_team(unit.team):
			if friendly == unit:
				continue
			if friendly.squad_type in [Globals.SquadType.MG, Globals.SquadType.Rifle]:
				query.reservations[friendly] = query.objective_hex
			elif friendly.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS:
				query.reservations[friendly] = Vector2i(8, 14)
		var result: PositionResult = PositionQueryService.query_positions(query)
		var connected: int = 0
		for cell: Vector2i in area.result.covered_positions:
			if LOSHelper.get_hex_distance(cell, query.objective_hex) > 3:
				continue
			var f: Dictionary = PositionFeatureEvaluator.evaluate(query, cell, [])
			if result.eligibility[query.snapshot.maps[unit.team].cell_to_index(cell)] == 1 and f["objective_connected_cover"]:
				connected += 1
		_check(connected > 0, "OutpostProbe has eligible connected cover for the long western approach")
		var edge: Vector2i = Vector2i(10, 14)
		var edge_features: Dictionary = PositionFeatureEvaluator.evaluate(query, edge, [])
		_check(edge_features["assigned_corridor_coverage"] < 0.5 and edge_features["assigned_coverage"] >= 0.5, "The woodland edge protects the final approach without needing fire over half the entire western route")
		_check(result.eligibility[query.snapshot.maps[unit.team].cell_to_index(edge)] == 1, "Reservations for the guard and reserve do not eliminate the remaining useful woodland edge")
		_check(result.is_valid() and result.features["objective_connected_cover"] and result.features["return_open_seconds"] == 0.0, "The short-range defender chooses connected woods instead of the detached 9,10 candidate")
		_check(not result.rejections.has("screen_gap"), "Unseen terrain directions cannot impose unrelated mandatory screen coverage")
		query.has_accepted_target = true
		query.accepted_target = result.target_hex
		query.accepted_context = result.context
		query.accepted_at = query.snapshot.captured_at
		var repeated: PositionResult = PositionQueryService.query_positions(query)
		_check(repeated.target_hex == result.target_hex, "Repeated local interception advice remains stable")
		print("Defense interception sample: ", JSON.stringify({"evidence": evidence, "unit": str(unit.name), "target": str(result.target_hex), "eligible": result.eligibility.count(1), "edge_interception": edge_features["assigned_coverage"], "edge_full_corridor": edge_features["assigned_corridor_coverage"], "return_open_seconds": result.features.get("return_open_seconds", -1.0)}))
	for soldier: Soldier in weapons:
		soldier.weapon = weapons[soldier]


func _crossing_snapshot(original: InfluenceSnapshot, team: int) -> InfluenceSnapshot:
	var snapshot: InfluenceSnapshot = InfluenceSnapshot.new()
	snapshot.version = original.version
	snapshot.captured_at = original.captured_at
	snapshot.terrain_key = original.terrain_key
	snapshot.route_topology_key = original.route_topology_key
	snapshot.positions = original.positions.duplicate()
	snapshot.teams = original.teams.duplicate()
	snapshot.los = original.los
	snapshot.point_ids[team] = original.point_ids[team]
	snapshot.objectives[team] = Vector2i(11, 13)
	var source: InfluenceMap = original.maps[team]
	var map: InfluenceMap = InfluenceMap.new()
	map.configure(source.bounds)
	map.playable_cells = source.playable_cells.duplicate()
	for layer: int in [InfluenceMap.Layer.TERRAIN_COVER, InfluenceMap.Layer.TERRAIN_MOVE_COST, InfluenceMap.Layer.NO_GO]:
		map._layers[layer] = source.get_layer_data_copy(layer)
	snapshot.maps[team] = map
	var source_graph: AStar2D = original.routes[team]
	var graph: AStar2D = AStar2D.new()
	for id: int in source_graph.get_point_ids():
		var point: Vector2 = source_graph.get_point_position(id)
		graph.add_point(id, point, source_graph.get_point_weight_scale(id))
		graph.set_point_disabled(id, map.get_layer_value(InfluenceMap.Layer.NO_GO, LOSHelper.ground_layer.local_to_map(point)) > 0.0)
	for id: int in source_graph.get_point_ids():
		for neighbor: int in source_graph.get_point_connections(id):
			graph.connect_points(id, neighbor, false)
	snapshot.routes[team] = graph
	return snapshot


func _crossing_readiness(snapshot: InfluenceSnapshot, team: int, units: Array[Unit], reserve: Unit) -> DefenseReadinessJob:
	var area: DefenseAreaJob = DefenseAreaJob.new()
	area.start(snapshot, team, Vector2i(11, 13), 8, 12, [])
	area.advance(-1)
	var readiness: DefenseReadinessJob = DefenseReadinessJob.new()
	readiness.start(area.result, snapshot, team, units, reserve, 4)
	readiness.advance(-1)
	return readiness


func _test_reserve_crossing(controller: InfluenceMapController, team: int) -> void:
	# Mirror the same four-combat-squad loadout; the authored Allies roster has only two.
	var units: Array[Unit] = Globals.get_units_for_team(Globals.Team.AXIS)
	var saved: Dictionary[Unit, Dictionary] = {}
	var reserve: Unit = null
	var guard: Unit = null
	for unit: Unit in units:
		if unit.squad_type == Globals.SquadType.Rifle:
			reserve = unit
	guard = DefenseSectorAllocator.select_guard(units)
	var snapshot: InfluenceSnapshot = _crossing_snapshot(controller.snapshot, team)
	var other_positions: Array[Vector2i] = [Vector2i(9, 13), Vector2i(10, 14), Vector2i(9, 14), Vector2i(10, 15)]
	for unit: Unit in units:
		saved[unit] = {"team": unit.team, "hex": unit.current_hex, "position": unit.position, "moving": unit.movement.is_moving, "effectiveness": unit.combat_stats.combat_effectiveness, "action": unit.action_controller.action_state}
		unit.team = team
		snapshot.teams[unit] = team
		if unit == reserve:
			unit.current_hex = Vector2i(11, 14)
		elif unit == guard:
			unit.current_hex = Vector2i(11, 13)
		else:
			unit.current_hex = other_positions.pop_front()
		unit.position = LOSHelper.ground_layer.map_to_local(unit.current_hex)
		unit.movement.is_moving = false
		unit.combat_stats.combat_effectiveness = 1.0
		unit.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
		snapshot.positions[unit] = unit.current_hex
	var contact: InfluenceContact = InfluenceContact.new()
	contact.hex = Vector2i(17, 14)
	contact.observed = true
	contact.firepower = 1.0
	contact.weapon_range = 5
	contact.crossing_seconds = 2.0
	contact.last_seen_at = snapshot.captured_at
	snapshot.contacts[team] = [contact]
	snapshot.defensive_contacts[team] = [contact]
	var readiness: DefenseReadinessJob = _crossing_readiness(snapshot, team, units, reserve)
	var sliced: DefenseReadinessJob = DefenseReadinessJob.new()
	sliced.start(readiness.area, snapshot, team, units, reserve, 4)
	sliced.advance(Time.get_ticks_usec() - 1)
	_check(not sliced.completed, "An exhausted frame budget cannot run entrance readiness work")
	while not sliced.completed:
		sliced.advance(Time.get_ticks_usec() + 100)
	_check(sliced.responses == readiness.responses and sliced.coverage == readiness.coverage and sliced.watch_branch == readiness.watch_branch and sliced.emergency == readiness.emergency, "Budgeted entrance readiness matches synchronous coverage, deadlines and duty selection")
	_check(readiness.watch_branch != "", "A right-hand open crossing receives an early reserve watch duty")
	_check(readiness.emergency == "", "Early crossing coverage preserves the protected reserve instead of declaring an objective emergency")
	if readiness.watch_branch != "":
		var response: Dictionary = readiness.responses[readiness.watch_branch]
		_check(response["arrival_seconds"] < response["objective_arrival_seconds"], "Reserve response is timed against entering the woods rather than reaching the objective")
		_check(not response["covered"], "Inner woodland coverage cannot conceal an uncovered eastern entrance")
		_check(response["seconds"].get(reserve.current_hex, INF) <= response["arrival_seconds"], "The reserve can establish useful fire before the early attacker enters the woods")
		var planner: PlatoonAI = PlatoonAI.new()
		planner.team = team
		planner.influence_map_controller = controller
		planner.current_order = MissionOrder.new()
		planner.current_order.objective_hex = Vector2i(11, 13)
		planner.defense_area = readiness.area
		planner._planning_snapshot = snapshot
		planner._planning_readiness = readiness
		planner.reserve_squad = reserve
		for unit: Unit in units:
			planner._planning_reservations[unit] = unit.current_hex
		planner._build_sector_requests(units.duplicate())
		var query: PositionQuery = planner._planning_requests[1]["query"]
		_check(planner._planning_requests[0]["query"].unit == guard, "The stationary anchor keeps the objective guard assignment")
		_check(query.unit == reserve and query.reserve_position and query.required_crossing_branch == readiness.watch_branch, "The mobile reserve covers the threatened entrance before optional flank relocations")
		_check(not planner.reserve_deployed, "Watching the entrance does not consume the protected reserve")
		var result: PositionResult = PositionQueryService.query_positions(query)
		_check(result.is_valid() and result.target_hex != reserve.current_hex, "The reserve leaves its sheltered but ineffective origin for useful connected woods")
		_check(result.features.get("crossing_coverage", 0.0) >= DefenseAreaAssessment.MIN_CROSSING_COVERAGE, "The destination protects the first eastern entrances")
		_check(result.features.get("objective_connected_cover", false) and result.features.get("return_open_seconds", INF) == 0.0 and result.features.get("open_crossing_seconds", INF) <= query.defense_crossing_seconds() + 0.001 and result.features.get("open_exposure_seconds", INF) <= query.profile.max_open_exposure_seconds, "Entrance coverage keeps woodland return access and stays within the short-crossing risk budget")
		_check(result.rejection_reasons[snapshot.maps[team].cell_to_index(reserve.current_hex)] == "crossing_gap", "Diagnostics expose why the high-scoring sheltered origin cannot fulfill the entrance duty")
		var watch: Dictionary = readiness.area.branch_for_key(readiness.watch_branch)
		_check(readiness.area.coverage(query, reserve, result.target_hex, watch)["visible_targets"].has(contact.hex), "The forward reserve has usable fire on the known open-ground attacker")
		var validation: DefensePlanValidationJob = DefensePlanValidationJob.new()
		validation.start(readiness.area, [{"query": query}], [DefensePositionAnalyzer.adapt_result(result, null, "reserve")])
		validation.advance(-1)
		_check(validation.valid, "Completed platoon validation preserves the explicit entrance responsibility")
		query.required_crossing_branch = ""
		query.assigned_branch = ""
		query.assigned_sector = -1
		var sheltered: PositionResult = PositionQueryService.query_positions(query)
		_check(sheltered.is_valid() and sheltered.target_hex == reserve.current_hex, "Without an entrance responsibility the reserve reproduces the ineffective sheltered hold")
		query.required_crossing_branch = readiness.watch_branch
		query.assigned_branch = readiness.watch_branch
		query.assigned_sector = watch["id"]
		query.has_accepted_target = true
		query.accepted_target = result.target_hex
		query.accepted_context = result.context
		query.accepted_at = snapshot.captured_at
		var repeated: PositionResult = PositionQueryService.query_positions(query)
		_check(repeated.target_hex == result.target_hex, "Repeated entrance advice retains the accepted position")
		query.has_accepted_target = false
		query.relocation_allowed = false
		var waiting: PositionResult = PositionQueryService.query_positions(query)
		_check(waiting.status == PositionResult.Status.NO_CANDIDATE and waiting.rejections.has("handoff_wait"), "A useful entrance remains unavailable until the coverage handoff permits movement")
		query.relocation_allowed = true
		for cell: Vector2i in snapshot.maps[team].playable_cells:
			if cell != reserve.current_hex:
				snapshot.maps[team].set_layer_value(InfluenceMap.Layer.THREAT, cell, 100.0)
		var blocked: PositionResult = PositionQueryService.query_positions(query)
		_check(blocked.status == PositionResult.Status.NO_CANDIDATE, "Entrance duty cannot force movement through unsafe transit")
		for cell: Vector2i in snapshot.maps[team].playable_cells:
			snapshot.maps[team].set_layer_value(InfluenceMap.Layer.THREAT, cell, 0.0)
		reserve.in_close_combat = true
		var locked: PositionResult = PositionQueryService.query_positions(query)
		_check(not locked.is_valid(), "The threatened crossing cannot permit leaving close combat")
		reserve.in_close_combat = false
		reserve.current_hex = result.target_hex
		reserve.position = LOSHelper.ground_layer.map_to_local(reserve.current_hex)
		snapshot.positions[reserve] = reserve.current_hex
		contact.hex = Vector2i(15, 14)
		var established: DefenseReadinessJob = _crossing_readiness(snapshot, team, units, reserve)
		_check(established.responses.get(established.watch_branch, {}).get("seconds", {}).get(reserve.current_hex, INF) == 0.0, "An established interception position has no repeated movement or setup delay")
		query.defense_area = established.area
		query.reserve_responses = established.responses
		query.assigned_branch = established.watch_branch
		query.required_crossing_branch = established.watch_branch
		query.reservations.erase(reserve)
		var held: PositionResult = PositionQueryService.query_positions(query)
		_check(held.is_valid() and held.target_hex == reserve.current_hex, "The reserve holds its useful woodland edge as the attacker advances")
		contact.observed = false
		contact.last_seen_at = snapshot.captured_at - 3.0
		var remembered: DefenseReadinessJob = _crossing_readiness(snapshot, team, units, reserve)
		_check(remembered.watch_branch != "" and remembered.emergency == "", "A brief visibility loss retains entrance coverage without inventing an emergency")
		contact.last_seen_at = snapshot.captured_at - 10.0
		var stale: DefenseReadinessJob = _crossing_readiness(snapshot, team, units, reserve)
		_check(stale.watch_branch == "", "Older remembered directions do not impose a permanent entrance duty")
		snapshot.contacts[team] = []
		snapshot.defensive_contacts[team] = []
		snapshot.sector_pressure[team] = {0: {"pressure": 0.25, "arrival_seconds": 20.0}}
		var covered_estimate: DefenseReadinessJob = _crossing_readiness(snapshot, team, units, reserve)
		_check(covered_estimate.watch_branch == "" and covered_estimate.emergency == "", "Coarse pressure on an already covered terrain entrance cannot force needless movement")
		snapshot.sector_pressure[team] = {1: {"pressure": 0.25, "arrival_seconds": 20.0}}
		var estimated: DefenseReadinessJob = _crossing_readiness(snapshot, team, units, reserve)
		_check(estimated.watch_branch != "" and estimated.emergency == "", "Delayed coarse pressure on an unattended entrance can preposition a protected reserve without deploying it")
		if estimated.watch_branch != "":
			var estimated_branch: Dictionary = estimated.area.branch_for_key(estimated.watch_branch)
			_check(estimated_branch["evidence"] == "estimated" and not estimated.area.crossing_zone(4, estimated_branch)["active_target"], "Coarse readiness uses a terrain entrance without treating a hidden hex as a firing target")
		_check(snapshot.get_contacts(team).is_empty() and snapshot.get_defensive_contacts(team).is_empty(), "Estimated entrance duty creates no exact enemy contact")
		print("Reserve entrance sample: ", JSON.stringify({"team": team, "entry_arrival": response["arrival_seconds"], "objective_arrival": response["objective_arrival_seconds"], "target": str(result.target_hex), "held": str(held.target_hex)}))
		planner.free()
	for unit: Unit in saved:
		unit.team = saved[unit]["team"]
		unit.current_hex = saved[unit]["hex"]
		unit.position = saved[unit]["position"]
		unit.movement.is_moving = saved[unit]["moving"]
		unit.combat_stats.combat_effectiveness = saved[unit]["effectiveness"]
		unit.action_controller.action_state = saved[unit]["action"]


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
