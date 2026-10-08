extends Node

var failures: int = 0
var checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(6049)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map_index: int = 1
	if OS.get_cmdline_user_args().has("--default-map"):
		map_index = 0
	var map: Map = world.maps.get_child(map_index)
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	var player_team: Globals.Team = scenario.player_team
	if OS.get_cmdline_user_args().has("--axis"):
		player_team = Globals.Team.AXIS
	await world._on_game_started(map, scenario, player_team, Globals.GameMode.ATTACK)
	var controller: InfluenceMapController = world.game_controller.influence_map_controller
	var planners: Array[PlatoonAI] = [world.game_controller.platoon_ai, world.game_controller.get_node("PlatoonAi2")]
	var manual_orders: Dictionary[Unit, int] = {}
	for planner: PlatoonAI in planners:
		if planner.team == player_team:
			_check(not planner.active and planner.current_order == null and planner.squad_assignments.is_empty(), "Player platoon receives no automatic mission at startup")
			for unit: Unit in planner.squads:
				unit.give_hold_order()
				manual_orders[unit] = unit.action_controller.action_order_id
			# Direct director updates and reconsideration must also respect player control.
			var director: DefenseDirector = world.game_controller.defense_director
			if planner.team == Globals.Team.ALLIES:
				director = world.game_controller.get_node("DefenseDirector2")
			director.assign_order_to_platoon()
			planner.reconsider_assignments()
			_check(planner.current_order == null and planner.squad_assignments.is_empty() and planner.executor.pending.is_empty(), "Player planner rejects automatic mission updates")
		else:
			_check(planner.active and planner.current_order != null, "Enemy platoon retains its automatic mission")
	_check(not manual_orders.is_empty(), "Scenario includes player squads previously controlled by the planner")
	var samples: Array[Dictionary] = []
	for frame: int in range(600):
		await get_tree().process_frame
		if frame % 60 == 59:
			for planner: PlatoonAI in planners:
				if planner.team == player_team:
					_check(planner.current_order == null and planner.squad_assignments.is_empty() and planner.executor.pending.is_empty(), "Player remains outside automatic planning across tactical ticks")
					for unit: Unit in manual_orders:
						_check(unit.action_controller.action_order_id == manual_orders[unit] and not unit.movement.is_moving, "Player hold commands survive automatic reconsideration")
				var targets: Array[String] = []
				var claimed: Array[Vector2i] = []
				for owned: Unit in planner.squad_assignments:
					_check(Globals.get_units().has(owned) and owned.team == planner.team and planner.squads.has(owned), "Match orders remain inside active platoon ownership")
					var advice: PositionResult = planner.squad_assignments[owned]["result"]
					if advice.is_valid():
						_check(not claimed.has(advice.target_hex), "Owned squads reserve distinct destinations")
						claimed.append(advice.target_hex)
						targets.append("%s:%s" % [owned.name, advice.target_hex])
				samples.append({"frame": frame + 1, "team": planner.team, "targets": targets})
	for planner: PlatoonAI in planners:
		if planner.team != player_team:
			_check(planner.active and not planner.squad_assignments.is_empty(), "Enemy continues to allocate positions during the match")
	_check(controller.snapshot != null and controller.snapshot.maps.size() == 2, "Active match publishes both teams")
	# Freeze execution while comparing policies over exactly the same match snapshot.
	main.process_mode = Node.PROCESS_MODE_DISABLED
	_test_position_inspection(world, player_team)
	var observations: Array[Dictionary] = []
	var covered_teams: int = 0
	var valid_offense: int = 0
	var exercised: Array[int] = []
	var executor: TacticalPositionExecutor = TacticalPositionExecutor.new()
	for team: int in [Globals.Team.AXIS, Globals.Team.ALLIES]:
		var units: Array[Unit] = Globals.get_units_for_team(team)
		var enemies: Array[Unit] = Globals.get_units_for_team(Globals.get_enemy_team(team))
		var objective: Vector2i = controller.objectives_by_team[team]
		var coverage: bool = false
		for unit: Unit in units:
			var query: PositionQuery = PositionQuery.new()
			query.unit = unit
			query.team = team
			query.objective_hex = objective
			query.snapshot = controller.snapshot
			query.profile = PositionProfile.for_mode(PositionProfile.Mode.LEGACY_DEFENSE)
			var legacy: PositionResult = PositionQueryService.query_positions(query)
			query.profile = PositionProfile.for_mode(PositionProfile.Mode.DEFEND)
			var defense: PositionResult = PositionQueryService.query_positions(query)
			if defense.is_valid():
				_check(LOSHelper.get_hex_distance(defense.target_hex, objective) <= query.defense_radius, "Defense stays within mission geography")
				_check(not defense.path.is_empty() and defense.path[-1] == defense.target_hex, "Defense returns a valid route")
				coverage = coverage or defense.features["objective_coverage"] > 0.0
				query.has_accepted_target = true
				query.accepted_target = defense.target_hex
				query.accepted_context = defense.context
				var repeated: PositionResult = PositionQueryService.query_positions(query)
				_check(repeated.target_hex == defense.target_hex, "Repeated snapshot retains a stable defensive position")
			observations.append({"unit": str(unit.name), "team": team, "mode": "defend", "valid": defense.is_valid(), "target": str(defense.target_hex), "score": _finite_score(defense.score), "features": defense.features, "legacy_target": str(legacy.target_hex), "legacy_score": _finite_score(legacy.score)})
			query.has_accepted_target = false
			for mode: PositionProfile.Mode in [PositionProfile.Mode.SUPPORT_BY_FIRE, PositionProfile.Mode.ADVANCE, PositionProfile.Mode.ASSAULT]:
				if enemies.is_empty():
					continue
				query.objective_hex = enemies[0].current_hex
				query.profile = PositionProfile.for_mode(mode)
				var offense: PositionResult = PositionQueryService.query_positions(query)
				if offense.is_valid():
					valid_offense += 1
					_check(not offense.path.is_empty(), "Offensive recommendation has a route")
					if offense.should_move and not exercised.has(mode):
						_check(executor.execute(offense), "Real unit action controller accepts offensive advice")
						_check(unit.action_controller.objective_hex == offense.target_hex, "Execution uses the advised destination")
						if mode == PositionProfile.Mode.ASSAULT:
							_check(unit.action_controller.has_attack_flag, "Assault retains existing attack execution semantics")
						exercised.append(mode)
						executor.cancel(unit)
						unit.action_controller.clear_orders()
					if mode == PositionProfile.Mode.SUPPORT_BY_FIRE:
						_check(offense.features["firing"] > 0.0, "Support position can fire toward the target")
					if mode == PositionProfile.Mode.ASSAULT:
						_check(LOSHelper.get_hex_distance(offense.target_hex, query.objective_hex) <= 1, "Assault position is adjacent to the target")
				observations.append({"unit": str(unit.name), "team": team, "mode": mode, "valid": offense.is_valid(), "target": str(offense.target_hex), "score": _finite_score(offense.score), "features": offense.features})
		if coverage:
			covered_teams += 1
	_check(covered_teams == 2, "Both teams have positions covering their defensive objective")
	_check(valid_offense > 0, "Authored map supports offensive position recommendations")
	executor.cancel_all()
	# Stress the same authored terrain with explicitly omniscient danger knowledge.
	controller.knowledge_policy = InfluenceMapController.KnowledgePolicy.OMNISCIENT
	_complete_rebuild(controller)
	var danger_cases: int = 0
	for team: int in [Globals.Team.AXIS, Globals.Team.ALLIES]:
		_check(not controller.snapshot.get_contacts(team).is_empty(), "Explicit knowledge policy captures the enemy team")
		for unit: Unit in Globals.get_units_for_team(team):
			var query: PositionQuery = PositionQuery.new()
			query.unit = unit
			query.team = team
			query.objective_hex = controller.objectives_by_team[team]
			query.snapshot = controller.snapshot
			var advice: PositionResult = PositionQueryService.query_positions(query)
			if advice.is_valid():
				_check(advice.features["incoming"] <= query.profile.max_incoming_risk and advice.features["peak_exposure"] <= query.profile.max_route_exposure, "Known-danger advice obeys destination and route limits")
				danger_cases += 1
			observations.append({"unit": str(unit.name), "team": team, "mode": "defend_known_danger", "valid": advice.is_valid(), "target": str(advice.target_hex), "score": _finite_score(advice.score), "features": advice.features, "reason": advice.reason})
	_check(danger_cases > 0, "Representative map retains feasible positions under known danger")
	_test_support_fire(controller)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file: FileAccess = FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			file.store_string(JSON.stringify({"map": str(map.name), "player_team": player_team, "checks": checks, "failures": failures, "snapshot_version": controller.snapshot.version, "observations": observations, "planning_samples": samples}, "  "))
	var map_name: String = str(map.name)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Influence match checks: ", checks, "; failures: ", failures, "; map: ", map_name)
	get_tree().quit(failures)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _finite_score(score: float) -> Variant:
	if is_finite(score):
		return score
	return null


func _complete_rebuild(controller: InfluenceMapController) -> void:
	# Finish a pending capture before creating a capture with the new policy.
	for attempt: int in range(2):
		controller.create_maps(0.0)
		for step: int in range(1000):
			controller._process_los_rebuild()
			controller._process_budgeted_rebuild()
			if not controller.rebuild_pending:
				break
	_check(not controller.rebuild_pending, "Completed snapshot publishes after policy change")


func _test_support_fire(controller: InfluenceMapController) -> void:
	var exercised: bool = false
	for unit: Unit in Globals.get_units():
		for cell: Vector2i in controller.snapshot.los.get(unit.current_hex, {}):
			if cell == unit.current_hex or InfluenceUnitQuery.get_firepower_at_range(unit, LOSHelper.get_hex_distance(unit.current_hex, cell)) <= 0.0:
				continue
			var occupied: bool = false
			for friendly: Unit in Globals.get_units_for_team(unit.team):
				occupied = occupied or friendly.current_hex == cell
			if occupied:
				continue
			var query: PositionQuery = PositionQuery.new()
			query.unit = unit
			query.team = unit.team
			query.objective_hex = cell
			query.movement_radius = 0
			query.profile = PositionProfile.for_mode(PositionProfile.Mode.SUPPORT_BY_FIRE)
			query.snapshot = controller.snapshot
			var advice: PositionResult = PositionQueryService.query_positions(query)
			if not advice.is_valid():
				continue
			var executor: TacticalPositionExecutor = TacticalPositionExecutor.new()
			_check(executor.execute(advice), "Support intent executes at an existing firing position")
			_check(unit.attackState != Unit.AttackState.AUTO and unit.squad_fire.has_target_hex, "Real fire controller receives the support target")
			unit.setAttackState(Unit.AttackState.AUTO)
			unit.squad_fire.clear_target()
			_check(executor.execute(advice), "Completed support advice can resume its fire intent")
			_check(unit.attackState != Unit.AttackState.AUTO and unit.squad_fire.has_target_hex, "Support fire resumes after an existing ground-fire budget finishes")
			executor.cancel_all()
			_check(unit.attackState == Unit.AttackState.AUTO and not unit.squad_fire.has_target_hex, "Canceling support intent releases its fire target")
			exercised = true
			break
		if exercised:
			break
	_check(exercised, "Authored match exercises real support-by-fire execution")


func _test_position_inspection(world: Node, player_team: Globals.Team) -> void:
	var draw: InfluenceMapDebugDraw = world.game_controller.influence_map_debug_draw
	var controller: InfluenceMapController = world.game_controller.influence_map_controller
	draw.set_debug_view(InfluenceMapDebugDraw.DebugView.THREAT)
	var valid_previews: int = 0
	for unit: Unit in Globals.get_units_for_team(player_team):
		var order_id: int = unit.action_controller.action_order_id
		var tactical_advice: PositionResult = unit.position_advice
		world.game_controller._select_unit(unit)
		_check(draw.selected_unit == unit and draw.team == player_team and draw.debug_view == InfluenceMapDebugDraw.DebugView.POSITION_SCORE, "Click selection opens the player's position overlay without a keyboard shortcut")
		var advice: PositionResult = draw.position_advice
		_check(advice != null and advice.unit == unit and advice.snapshot_version == controller.snapshot.version, "Player inspection queries the completed snapshot without an AI mission")
		_check(unit.action_controller.action_order_id == order_id and unit.position_advice == tactical_advice, "Player inspection neither issues orders nor replaces tactical advice")
		if advice != null and advice.is_valid():
			valid_previews += 1
			_check(draw._should_draw_cell(controller.snapshot.maps[player_team], advice.target_hex), "The advised destination is visibly marked as a feasible candidate")
		world.game_controller._deselect_unit(unit)
		_check(draw.debug_view == InfluenceMapDebugDraw.DebugView.THREAT and draw.position_advice == null, "Deselecting returns to the previous layer")
	_check(valid_previews > 0, "Manually controlled scenario units retain inspectable position candidates")
	var planners: Array[PlatoonAI] = [world.game_controller.platoon_ai, world.game_controller.get_node("PlatoonAi2")]
	for planner: PlatoonAI in planners:
		if planner.team == player_team:
			_check(not planner.active and planner.current_order == null and planner.executor.pending.is_empty(), "Inspection does not re-enable player AI")
		else:
			for unit: Unit in planner.squad_assignments:
				world.game_controller._select_unit(unit)
				_check(draw.position_advice == planner.squad_assignments[unit]["result"], "AI inspection preserves the exact assigned query and reservation diagnostics")
				world.game_controller._deselect_unit(unit)
