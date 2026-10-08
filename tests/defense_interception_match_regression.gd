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


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
