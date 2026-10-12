extends Node

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var panel: PanelContainer = world.ui.get_node("Control/Debug")
	_check(panel.axis_ai_status.disabled and panel.allies_ai_status.disabled, "AI controls remain unavailable before match setup")
	var map_name: String = "DefaultMap"
	if OS.get_cmdline_user_args().has("--orchard-road"):
		map_name = "OrchardRoad"
	var map: Map = world.maps.get_node(map_name)
	var scenario: Scenario = map.get_scenario(0)
	# Both sides need distinct capture markers to verify attack objective selection.
	scenario.axis_objectives_tile_map_layer.set_cell(Vector2i(10, 12), 3, Vector2i.ZERO)
	scenario.allied_objectives_tile_map_layer.set_cell(Vector2i(17, 11), 6, Vector2i.ZERO)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	var controller: Node2D = world.game_controller
	var axis: PlatoonAI = controller.get_node("PlatoonAi")
	var allies: PlatoonAI = controller.get_node("PlatoonAi2")
	_check(_capture_hex(axis.team) != _capture_hex(allies.team), "The two sides have distinct capture objectives")
	for planner: PlatoonAI in [axis, allies]:
		var status_selector: OptionButton = panel.axis_ai_status
		var mode_selector: OptionButton = panel.axis_ai_mode
		if planner.team == Globals.Team.ALLIES:
			status_selector = panel.allies_ai_status
			mode_selector = panel.allies_ai_mode
		_check(not status_selector.disabled and not mode_selector.disabled, "Match setup enables both AI selectors")
		_check((status_selector.get_selected_id() == 1) == planner.active, "Initial ON/OFF matches the actual controller")
		_check(planner.active == (planner.team == Globals.team_enemy), "Startup retains human and enemy ownership")
		if planner.current_order != null:
			_check(mode_selector.get_selected_id() == planner.current_order.position_mode, "Initial mode reflects the scenario mission")
		_test_side(controller, planner, status_selector, mode_selector)
	_test_disabled_mode(controller, panel, allies)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("AI debug controls checks: ", checks, "; failures: ", failures, "; map: ", map_name)
	get_tree().quit(failures)


func _test_side(controller: Node2D, planner: PlatoonAI, status_selector: OptionButton, mode_selector: OptionButton) -> void:
	var other: PlatoonAI = controller.get_node("PlatoonAi2")
	if planner.team == Globals.Team.ALLIES:
		other = controller.get_node("PlatoonAi")
	var other_active: bool = other.active
	var other_order: MissionOrder = other.current_order
	_select(status_selector, 1)
	_check(planner.active and planner.current_order != null, "ON gives the selected side a mission")
	_select(mode_selector, PositionProfile.Mode.ASSAULT)
	var attack: MissionOrder = planner.current_order
	_check(attack.position_mode == PositionProfile.Mode.ASSAULT and attack.execution_intent == TacticalPositionExecutor.Intent.ASSAULT, "ATTACK enables coordinated assault planning and execution")
	_check(attack.objective_hex == _capture_hex(planner.team), "ATTACK targets this side's capture marker")
	_check(attack.reserve_policy == MissionOrder.ReservePolicy.NONE and attack.sector_cells.is_empty(), "ATTACK releases fighting squads from defensive reserves and sectors")
	var rifle: Unit
	var hq: Unit
	for unit: Unit in planner.squads:
		if unit.squad_type == Globals.SquadType.Rifle:
			rifle = unit
		if HqSupportPositionPolicy.is_headquarters(unit):
			hq = unit
	if hq != null:
		_check(hq.ai_support_only, "ON assigns headquarters its support role")
	var move: PositionResult = _movement_result(rifle)
	_check(move != null and planner.executor.execute(move), "The selected AI owns an actual move before switching mode")
	_select(mode_selector, PositionProfile.Mode.DEFEND)
	_check(rifle.movement.path_hexes.is_empty() and rifle.movement.target_hex == rifle.current_hex and planner.executor.pending.is_empty(), "Changing mode cancels the previous AI route and pending execution")
	_check(planner.current_order.position_mode == PositionProfile.Mode.DEFEND and planner.current_order.objective_hex == _capture_hex(Globals.get_enemy_team(planner.team)), "DEFEND protects the opponent's capture marker")
	_check(rifle.squad_ai_controller.defensive_mission_controlled, "DEFEND assigns positioning to the platoon planner")
	move = _movement_result(rifle)
	_check(move != null and planner.executor.execute(move), "The selected AI owns an actual move before OFF")
	var saved_order: MissionOrder = planner.current_order
	_select(status_selector, 0)
	_check(not planner.active and planner.current_order == null and rifle.movement.path_hexes.is_empty() and rifle.movement.target_hex == rifle.current_hex, "OFF clears the active mission and cancels its owned route")
	_check(planner.executor.pending.is_empty() and planner.executor.completed.is_empty() and planner.position_stability.orders.is_empty(), "OFF clears pending execution and position commitments")
	_check(not rifle.squad_ai_controller.defensive_mission_controlled, "OFF releases defensive squad control")
	if hq != null:
		_check(not hq.ai_support_only, "OFF releases headquarters support control")
	_select(status_selector, 1)
	_check(planner.active and planner.current_order == saved_order, "ON restores the selected mission and objective")
	# A player order issued after the AI move must survive the ownership handoff.
	move = _movement_result(rifle)
	_check(move != null and planner.executor.execute(move), "The AI owns a move before a manual replacement")
	var cubes: Array[Vector3i] = []
	for cell: Vector2i in move.path:
		cubes.append(LOSHelper.ground_layer.map_to_cube(cell))
	rifle.give_move_to_hex_order(move.target_hex, cubes, false)
	var manual_id: int = rifle.action_controller.action_order_id
	_select(status_selector, 0)
	_check(rifle.movement.is_moving and rifle.action_controller.action_order_id == manual_id, "OFF preserves an intervening manual order")
	rifle.give_hold_order()
	_check(other.active == other_active and other.current_order == other_order, "Changing one side never changes the other controller")


func _test_disabled_mode(controller: Node2D, panel: PanelContainer, planner: PlatoonAI) -> void:
	_select(panel.allies_ai_mode, PositionProfile.Mode.ASSAULT)
	_check(not planner.active and planner.current_order == null, "Selecting ATTACK while OFF does not activate or issue orders")
	_check(controller.get_team_ai_mode(planner.team) == PositionProfile.Mode.ASSAULT, "Disabled AI remembers its chosen mode")
	_select(panel.allies_ai_status, 1)
	_check(planner.active and planner.current_order.position_mode == PositionProfile.Mode.ASSAULT and planner.current_order.objective_hex == _capture_hex(planner.team), "ON uses the mode selected while OFF")
	var retained: MissionOrder = planner.current_order
	_select(panel.allies_ai_mode, PositionProfile.Mode.ASSAULT)
	_check(planner.current_order == retained, "Selecting the current mode does not restart the mission")
	retained.objective_hex = Vector2i(16, 10)
	_select(panel.allies_ai_status, 0)
	_select(panel.allies_ai_status, 1)
	_check(planner.current_order.objective_hex == Vector2i(16, 10), "OFF/ON preserves an edited objective")
	_select(panel.allies_ai_status, 0)


func _movement_result(unit: Unit) -> PositionResult:
	if unit == null:
		return null
	var graph: AStar2D = Globals.astars[unit.team]
	var origin: int = graph.get_closest_point(LOSHelper.ground_layer.map_to_local(unit.current_hex))
	for id: int in graph.get_point_connections(origin):
		if graph.is_point_disabled(id):
			continue
		var hex: Vector2i = LOSHelper.ground_layer.local_to_map(graph.get_point_position(id))
		if not LOSHelper.find_units_at(hex).is_empty():
			continue
		var result: PositionResult = PositionResult.new()
		result.unit = unit
		result.status = PositionResult.Status.ACCEPTED
		result.target_index = 0
		result.target_hex = hex
		result.should_move = true
		result.path = [unit.current_hex, hex]
		return result
	return null


func _capture_hex(team: Globals.Team) -> Vector2i:
	for objective: ObjectiveDefinition in Globals.objectives[team].objectives:
		if objective.objective_id == 1:
			return objective.hex
	return Vector2i.ZERO


func _select(selector: OptionButton, id: int) -> void:
	var index: int = selector.get_item_index(id)
	selector.select(index)
	selector.item_selected.emit(index)


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer:
		var timer: Timer = node as Timer
		timer.stop()
	for child: Node in node.get_children():
		_freeze(child)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
