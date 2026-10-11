extends Node

# Active scene integration, with --default-map for the other authored map.
# Use --fixed-fps 60 for deterministic frame progression and isolated user data.
var failures: int = 0
var attack_rifle: Unit
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
					_check(attack_ai._attack_mode_for_unit(unit) == PositionProfile.Mode.ADVANCE, "Distant attack rifles advance before assaulting")
				elif unit.squad_type == Globals.SquadType.MG:
					_check(attack_ai._attack_mode_for_unit(unit) != PositionProfile.Mode.ASSAULT, "Attack MG supports or advances instead of assaulting")
				elif HqSupportPositionPolicy.is_headquarters(unit):
					_check(attack_ai._attack_mode_for_unit(unit) == PositionProfile.Mode.HQ_SUPPORT, "Attack headquarters retains its support role")
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
		simulation_frames = 1800
	for frame: int in range(simulation_frames):
		await get_tree().process_frame
	if attack_rifle != null:
		var objective: Vector2i = scenario.axis_objectives_tile_map_layer.get_used_cells()[0]
		_check(LOSHelper.get_hex_distance(attack_rifle.current_hex, objective) < attack_rifle_start_distance, "Attack rifle makes progress toward the objective")
		_check(LOSHelper.get_hex_distance(attack_rifle.current_hex, objective) <= 2, "Attack rifle reaches assault range instead of settling behind the MG")
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


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
