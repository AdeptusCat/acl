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
	var map_index: int = 1
	if OS.get_cmdline_user_args().has("--default-map"):
		map_index = 0
	var map: Map = world.maps.get_child(map_index)
	var scenario: Scenario = map.get_scenario(0)
	var player_team: Globals.Team = scenario.player_team
	if OS.get_cmdline_user_args().has("--axis"):
		player_team = Globals.Team.AXIS
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, player_team, Globals.GameMode.ATTACK)
	var controller: InfluenceMapController = world.game_controller.influence_map_controller
	var planner: PlatoonAI = world.game_controller.platoon_ai
	if planner.team == player_team:
		planner = world.game_controller.get_node("PlatoonAi2")
	# Keep combat strength fixed to isolate positional decisions, while running real movement/perception.
	for unit: Unit in Globals.get_units():
		unit.squad_fire.process_mode = Node.PROCESS_MODE_DISABLED
		unit.squad_ai_controller.process_mode = Node.PROCESS_MODE_DISABLED
		unit.stress_system.process_mode = Node.PROCESS_MODE_DISABLED
		unit.combat_stats_timer.stop()
		unit.movement.base_speed = 90.0
		unit.movement.move_speed = 90.0
	var initial_plan_frames: int = 0
	for frame: int in range(1800):
		await get_tree().process_frame
		initial_plan_frames += 1
		if frame >= 599 and not planner.squad_assignments.is_empty():
			break
	_check(not planner.squad_assignments.is_empty(), "The initial complete defensive batch publishes before posture observation")
	var combat_squads: int = 0
	for unit: Unit in planner.squads:
		if DefenseSectorAllocator.combat_reserve_capable(unit):
			combat_squads += 1
	if combat_squads >= 3:
		_check(DefenseSectorAllocator.combat_reserve_capable(planner.reserve_squad), "The authored platoon retains a combat-capable designated reserve")
		var mobile_mount: WeaponSpec.Mount = WeaponSpec.Mount.TRIPOD
		for unit: Unit in planner.squads:
			if DefenseSectorAllocator.combat_reserve_capable(unit) and planner.squad_assignments.get(unit, {}).get("role") != "guard_objective":
				mobile_mount = mini(mobile_mount, InfluenceUnitQuery.get_defensive_mount(unit)) as WeaponSpec.Mount
		_check(InfluenceUnitQuery.get_defensive_mount(planner.reserve_squad) == mobile_mount, "The authored reserve uses the least stationary available equipment, including mixed rifle and bipod loadouts")
	var tripod_anchor: Unit = null
	var tripod_count: int = 0
	for unit: Unit in planner.squads:
		if InfluenceUnitQuery.get_defensive_mount(unit) == WeaponSpec.Mount.TRIPOD:
			tripod_anchor = unit
			tripod_count += 1
	if tripod_count == 1 and planner.squads.size() >= 2:
		_check(planner.squad_assignments.get(tripod_anchor, {}).get("role") == "guard_objective", "The authored platoon's sole tripod MG receives the stationary objective guard duty")
	else:
		tripod_anchor = null
	var player: Unit = null
	for unit: Unit in Globals.get_units_for_team(player_team):
		if unit.squad_type == Globals.SquadType.Rifle:
			player = unit
			break
	_check(player != null and not planner.squads.is_empty(), "Authored scenario has player and defender squads")
	var target: Vector2i = _relocation_hex(controller, player, planner.squads[0])
	_check(target != Vector2i(-999, -999), "A different reachable player position exists two hexes from the defense")
	if target == Vector2i(-999, -999):
		get_tree().quit(failures)
		return
	player.order(Globals.UnitCmd.MOVE, target)
	for frame: int in range(1800):
		await get_tree().process_frame
		if not player.movement.is_moving:
			break
	_check(player.current_hex == target, "Player relocates through the real order and movement APIs")
	player.give_hold_order()
	var player_order: int = player.action_controller.action_order_id
	# Provide one confirmed sighting; subsequent visibility loss is handled by normal perception.
	for defender: Unit in planner.squads:
		if LOSHelper.los_lookup.get(defender.current_hex, {}).has(player.current_hex):
			Globals.unit_visible_enemies[defender] = [player]
			defender.remember_enemy(player)
	controller.create_maps(0.0)
	var last_targets: Dictionary[Unit, String] = {}
	var changes: Dictionary[Unit, int] = {}
	var initial_orders: Dictionary[Unit, int] = {}
	var samples: Array[Dictionary] = []
	var valid_positions: int = 0
	var no_candidates: int = 0
	for frame: int in range(2400):
		await get_tree().process_frame
		if frame % 60 != 59:
			continue
		_check(player.current_hex == target and not player.movement.is_moving and player.action_controller.action_order_id == player_order, "Player stays stationary after relocation")
		for unit: Unit in planner.squads:
			var advice: PositionResult = unit.position_advice
			if advice == null:
				continue
			var target_key: String = "none"
			if advice.is_valid():
				valid_positions += 1
				target_key = str(advice.target_hex)
				_check(advice.features["cover"] >= 0.1, "Defensive endpoints have cover on authored terrain")
				_check(advice.features["exposure_seconds"] <= 6.0 and advice.features["open_exposure_seconds"] <= 2.0 and advice.features["peak_exposure"] <= 0.98, "Routes obey accumulated movement exposure budgets")
				if HqSupportPositionPolicy.is_headquarters(unit):
					_check(advice.profile_mode == PositionProfile.Mode.HQ_SUPPORT and advice.features["responsibility"] == "hq_support" and unit.ai_support_only, "Headquarters holds a covered support duty outside combat allocation")
				else:
					_check(advice.features["responsibility"] != "" and advice.features["preserves_screen"], "Every fighting squad fulfils its objective responsibility without opening a screen gap")
			elif advice.status == PositionResult.Status.NO_CANDIDATE:
				no_candidates += 1
				_check(not planner.executor.pending.has(unit) and not unit.movement.is_moving, "No safe candidate leaves the defender holding rather than moving into danger")
			if frame >= 599:
				if not initial_orders.has(unit):
					initial_orders[unit] = unit.action_controller.action_order_id
					changes[unit] = 0
				elif advice.is_valid() and last_targets.get(unit, target_key) != target_key:
					changes[unit] += 1
			# A temporary no-candidate/waiting diagnosis issues no destination; track real target changes.
			if advice.is_valid():
				last_targets[unit] = target_key
			samples.append({"frame": frame + 1, "unit": str(unit.name), "hex": str(unit.current_hex), "target": target_key, "order": unit.action_controller.action_order_id, "reason": advice.reason, "responsibility": advice.features.get("responsibility", ""), "blocking": advice.features.get("blocking", 0.0), "branch": advice.features.get("assigned_branch", ""), "rejections": advice.rejections})
		if frame >= 599:
			_check(_objective_guarded(planner), "A stationary nearby opponent does not leave the objective or its approach unprotected")
			if tripod_anchor != null:
				_check(planner.squad_assignments.get(tripod_anchor, {}).get("role") == "guard_objective", "Flank pressure retains the only tripod MG as the objective anchor")
	_check(valid_positions + no_candidates > 0, "Stationary opposition produces safe position advice or an explicit no-candidate result")
	_check(not controller.snapshot.get_defensive_contacts(planner.team).is_empty(), "Defense retains confirmed danger after short firing memory expires")
	for unit: Unit in changes:
		_check(changes[unit] <= 1, "Static opposition does not cause repeated defensive target changes")
		_check(unit.action_controller.action_order_id - initial_orders[unit] <= 2, "Static opposition does not repeatedly restart defensive orders")
	var advance: Vector2i = _advance_hex(controller, player, planner.current_order.objective_hex)
	_check(advance != Vector2i(-999, -999), "The player can advance to an unoccupied hex beside the protected objective")
	if advance != Vector2i(-999, -999):
		player.order(Globals.UnitCmd.MOVE, advance)
		for frame: int in range(1800):
			await get_tree().process_frame
			if not player.movement.is_moving:
				break
		_check(player.current_hex == advance, "Player advances through real movement toward the objective")
		player.give_hold_order()
		for frame: int in range(600):
			await get_tree().process_frame
			if frame % 60 == 59:
				_check(_objective_guarded(planner), "Healthy defenders continue protecting the objective against an advancing adjacent player")
	print("Defensive posture trace: ", JSON.stringify({"map": str(map.name), "player_team": player_team, "initial_plan_frames": initial_plan_frames, "player_hex": str(target), "advance_hex": str(advance), "objective": str(planner.current_order.objective_hex), "valid_positions": valid_positions, "no_candidates": no_candidates, "changes": _named_changes(changes), "samples": samples}))
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Defensive posture match checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _relocation_hex(controller: InfluenceMapController, player: Unit, defender: Unit) -> Vector2i:
	var best: Vector2i = Vector2i(-999, -999)
	var best_distance: int = 999999
	var cells: Array[Vector2i] = LOSHelper.ground_layer.get_used_cells()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y)
	for cell: Vector2i in cells:
		if cell == player.current_hex or cell == controller.objectives_by_team[defender.team] or LOSHelper.get_hex_distance(cell, defender.current_hex) != 2 or not LOSHelper.los_lookup.get(defender.current_hex, {}).has(cell):
			continue
		var occupied: bool = false
		for unit: Unit in Globals.get_units():
			occupied = occupied or unit.current_hex == cell
			# The positional fixture must not send the player into an AI destination/close combat.
			occupied = occupied or (unit.movement.is_moving and unit.movement.target_hex == cell)
			occupied = occupied or (unit.position_advice != null and unit.position_advice.is_valid() and unit.position_advice.target_hex == cell)
		if occupied or controller.snapshot.get_path(player.team, player.current_hex, cell).is_empty():
			continue
		var distance: int = LOSHelper.get_hex_distance(player.current_hex, cell)
		if distance < best_distance:
			best = cell
			best_distance = distance
	return best


func _named_changes(changes: Dictionary[Unit, int]) -> Dictionary:
	var named: Dictionary = {}
	for unit: Unit in changes:
		named[str(unit.name)] = changes[unit]
	return named


func _objective_guarded(planner: PlatoonAI) -> bool:
	for unit: Unit in planner.squads:
		if unit.current_hex == planner.current_order.objective_hex and not unit.movement.is_moving:
			return true
		var advice: PositionResult = unit.position_advice
		if advice != null and advice.is_valid() and not unit.movement.is_moving and unit.current_hex == advice.target_hex:
			if advice.features.get("responsibility") in ["occupy", "guard"]:
				return true
			var required: int = advice.features.get("important_approach_count", advice.features.get("approach_count", 0))
			var covered: int = advice.features.get("important_approaches_covered", advice.features.get("covered_approaches", 0))
			if planner.squads.size() == 1 and required > 0 and covered == required:
				return true
	return false


func _advance_hex(controller: InfluenceMapController, player: Unit, objective: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-999, -999)
	var distance: int = 999999
	for cell: Vector2i in LOSHelper.get_hex_neighbors(objective):
		var occupied: bool = false
		for unit: Unit in Globals.get_units():
			occupied = occupied or unit.current_hex == cell
		if occupied or cell == player.current_hex or not LOSHelper.los_lookup.get(cell, {}).has(objective) or controller.snapshot.get_path(player.team, player.current_hex, cell).is_empty():
			continue
		var candidate_distance: int = LOSHelper.get_hex_distance(player.current_hex, cell)
		if candidate_distance < distance:
			best = cell
			distance = candidate_distance
	return best


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
