extends Node

# Active scene integration, with --default-map for the other authored map.
# Use --fixed-fps 60 for deterministic frame progression and isolated user data.
var failures: int = 0
var attack_rifle: Unit
var attack_mg: Unit
var attack_hq: Unit
var attack_controller: PlatoonAI
var attack_mg_shots: int = 0
var attack_rifle_start_distance: int = 0


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
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	var controller: Node = world.game_controller
	if scenario.ai_attacks_axis_objective:
		var attack_ai: PlatoonAI = controller.get_node("PlatoonAi")
		if Globals.team_enemy == Globals.Team.ALLIES:
			attack_ai = controller.get_node("PlatoonAi2")
		var order: MissionOrder = attack_ai.current_order
		attack_controller = attack_ai
		_check(order != null, "OutpostProbe assigns an enemy attack mission")
		if order != null:
			_check(order.position_mode == PositionProfile.Mode.ASSAULT, "OutpostProbe uses assault position planning")
			_check(order.execution_intent == TacticalPositionExecutor.Intent.ASSAULT, "OutpostProbe executes assault orders")
			_check(scenario.axis_objectives_tile_map_layer.get_used_cells().has(order.objective_hex), "OutpostProbe attacks the authored Axis objective hex")
			_check(order.reserve_policy == MissionOrder.ReservePolicy.NONE, "OutpostProbe commits its fighting squads to the attack")
			for unit: Unit in attack_ai.squads:
				if unit.squad_type == Globals.SquadType.Rifle:
					attack_rifle = unit
					attack_rifle_start_distance = LOSHelper.get_hex_distance(unit.current_hex, order.objective_hex)
					_check(attack_ai._attack_mode_for_unit(unit) == PositionProfile.Mode.SUPPORT_BY_FIRE, "Attack rifles begin by establishing fire support")
				elif unit.squad_type == Globals.SquadType.MG:
					attack_mg = unit
					attack_mg.squad_fire.fire_shot.connect(_on_attack_mg_fired)
					_check(attack_ai._attack_mode_for_unit(unit) == PositionProfile.Mode.SUPPORT_BY_FIRE, "Attack MG searches for fire support even without current objective LOS")
				elif HqSupportPositionPolicy.is_headquarters(unit):
					attack_hq = unit
					_check(attack_ai._attack_mode_for_unit(unit) == PositionProfile.Mode.HQ_SUPPORT, "Attack headquarters retains its support role")
	if attack_controller != null:
		_test_all_defenders_suppression(attack_controller)
	var players: Array[Unit] = Globals.get_units_for_team(Globals.team_player)
	_check(not players.is_empty(), "Scenario initializes player units")
	var selected: Unit = players[0]
	controller._select_unit(selected)
	controller.show_unit_details_in_ui.emit(selected)
	SessionSettings.showCmdConnectivity = true
	Debug.showEnemyCmdConnectivity = true
	Debug.draw_thread_map = true
	controller.influence_map_debug_draw.set_team(Globals.team_player)
	controller.influence_map_debug_draw.set_debug_view(InfluenceMapDebugDraw.DebugView.FIRE_POWER)
	controller.influence_map_debug_draw.show()
	var simulation_frames: int = 600
	if attack_rifle != null:
		simulation_frames = 3600
	var advance_release_observed: bool = false
	for frame: int in range(simulation_frames):
		await get_tree().process_frame
		if attack_controller != null and attack_controller.attack_advance_released and not advance_release_observed:
			advance_release_observed = true
			_check(attack_controller._has_established_attack_support(attack_controller.squads), "Rifle advance starts after MG fire support is established")
			_check(attack_controller._are_visible_attack_defenders_suppressed(attack_controller.squads), "Rifle advance starts after every visible attack target is suppressed")
	if attack_rifle != null:
		var objective: Vector2i = scenario.axis_objectives_tile_map_layer.get_used_cells()[0]
		if advance_release_observed:
			_check(LOSHelper.get_hex_distance(attack_rifle.current_hex, objective) < attack_rifle_start_distance, "Released attack rifle makes progress toward the objective")
		else:
			_check(attack_controller._attack_mode_for_unit(attack_rifle) == PositionProfile.Mode.SUPPORT_BY_FIRE, "Rifle continues fire support while enemies remain unsuppressed")
		if attack_mg != null:
			_check(attack_mg.position_advice != null and attack_mg.position_advice.is_valid() and attack_mg.position_advice.profile_mode == PositionProfile.Mode.SUPPORT_BY_FIRE, "MG establishes a valid firing position while the rifle attacks")
			_check(attack_mg_shots > 0, "MG fires in support during the attack")
		if attack_hq != null:
			_check(attack_hq.position_advice != null and attack_hq.position_advice.is_valid() and attack_hq.position_advice.profile_mode == PositionProfile.Mode.HQ_SUPPORT, "HQ maintains a covered support position during the attack")
	var state: Array[Dictionary] = []
	for unit: Unit in Globals.get_units():
		_check(unit.squad_fire.soldiers.size() == unit.members_alive, "Active match retains consistent runtime strength")
		state.append({"name": str(unit.name), "team": unit.team, "hex": [unit.current_hex.x, unit.current_hex.y],
			"members": unit.members_alive, "casualties": unit.casualties_taken, "alive": unit.alive})
	print("Active match snapshot: ", JSON.stringify({"map": str(map.name), "units": state, "rng_tail": randf()}))
	if controller.selected_unit != null:
		controller._deselect_unit(controller.selected_unit)
	controller.time_left_seconds = 0.0
	controller._on_win_condition_timer_timeout()
	_check(world.result_screen.visible, "Match result reaches the existing screen")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Match smoke regression failures: ", failures)
	get_tree().quit(failures)


func _test_all_defenders_suppression(planner: PlatoonAI) -> void:
	var enemies: Array[Unit] = Globals.get_units_for_team(Globals.team_player)
	var observer: Unit = attack_mg
	var saved_visible: Array = Globals.unit_visible_enemies.get(observer, []).duplicate()
	var saved_los: Dictionary = LOSHelper.los_lookup.get(observer.current_hex, {}).duplicate()
	var saved_states: Array[UnitStates.MoraleState] = []
	var saved_stress: Array[float] = []
	Globals.unit_visible_enemies[observer] = enemies
	var visible_lanes: Dictionary = saved_los.duplicate()
	for enemy: Unit in enemies:
		saved_states.append(enemy.stress_system.state)
		saved_stress.append(enemy.stress_system.S_eff)
		enemy.stress_system.state = UnitStates.MoraleState.NORMAL
		enemy.stress_system.S_eff = 0.0
		visible_lanes[enemy.current_hex] = {}
	LOSHelper.los_lookup[observer.current_hex] = visible_lanes
	_check(not planner._are_visible_attack_defenders_suppressed(planner.squads), "Unsuppressed defenders block rifle advance")
	enemies[0].stress_system.state = UnitStates.MoraleState.PINNED
	_check(not planner._are_visible_attack_defenders_suppressed(planner.squads), "One pinned defender cannot release an attack against its unpinned neighbours")
	var target: Unit = TacticalPositionExecutor.select_support_target(observer, planner.current_order.objective_hex)
	_check(target != null and target != enemies[0], "Support fire shifts from the pinned squad to an unsuppressed defender")
	for enemy: Unit in enemies:
		enemy.stress_system.state = UnitStates.MoraleState.PINNED
	_check(planner._are_visible_attack_defenders_suppressed(planner.squads), "Every visible defender suppressed permits rifle advance")
	var support_query: PositionQuery = PositionQuery.new()
	support_query.unit = attack_hq
	support_query.team = observer.team
	support_query.profile = PositionProfile.for_mode(PositionProfile.Mode.HQ_SUPPORT)
	support_query.profile.support_assault_squads = true
	support_query.snapshot = InfluenceSnapshot.new()
	var contact: InfluenceContact = InfluenceContact.new()
	contact.unit = enemies[0]
	contact.hex = enemies[0].current_hex
	contact.observed = true
	var support_hex: Vector2i = contact.hex + Vector2i(0, 1)
	support_query.snapshot.defensive_contacts[observer.team] = [contact]
	support_query.snapshot.los[contact.hex] = {support_hex: {}}
	var pinned_features: Dictionary = HqSupportPositionPolicy.features(support_query, support_hex)
	_check(not pinned_features["frontline"], "Observed suppressed defender does not forbid nearby HQ support")
	contact.observed = false
	_check(HqSupportPositionPolicy.features(support_query, support_hex)["frontline"], "HQ cannot infer suppression from a hidden defender's live state")
	contact.observed = true
	enemies[0].stress_system.state = UnitStates.MoraleState.NORMAL
	var normal_features: Dictionary = HqSupportPositionPolicy.features(support_query, support_hex)
	_check(normal_features["frontline"] and normal_features["enemy_visibility"] > pinned_features["enemy_visibility"], "Recovered defender restores HQ exposure restrictions")
	enemies[0].stress_system.state = UnitStates.MoraleState.PINNED
	enemies[-1].stress_system.state = UnitStates.MoraleState.NORMAL
	_check(not planner._are_visible_attack_defenders_suppressed(planner.squads), "A recovered defender closes the advance opportunity")
	for index: int in range(enemies.size()):
		enemies[index].stress_system.state = saved_states[index]
		enemies[index].stress_system.S_eff = saved_stress[index]
	Globals.unit_visible_enemies[observer] = saved_visible
	LOSHelper.los_lookup[observer.current_hex] = saved_los


func _on_attack_mg_fired(_weapon: WeaponSpec, _hex: Vector2i) -> void:
	attack_mg_shots += 1


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
