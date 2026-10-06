extends Node

# Run with: godot --headless --path . tests/unit_arrival_regression.tscn
const START: Vector2i = Vector2i(10, 14)
const WAYPOINT: Vector2i = Vector2i(11, 14)
const DESTINATION: Vector2i = Vector2i(11, 15)

var failures: int = 0
var unit: Unit
var arrivals: Array[Vector2i] = []
var action_states: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_child(1)
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze_simulation(main)
	var soldiers: Array[Soldier] = []
	for candidate: Unit in Globals.get_units():
		soldiers.append_array(candidate.squad_fire.soldiers)
	unit = Globals.get_units()[0]
	unit.unit_arrived_at_hex.connect(_on_arrival)
	unit.action_controller.action_state_changed.connect(_on_action_state_changed)
	unit.action_controller.establishing_timer.wait_time = 0.02
	unit.action_controller.regroup_timer.wait_time = 0.02
	for hex: Vector2i in [START, WAYPOINT, DESTINATION]:
		_check(LOSHelper.ground_layer.get_cell_source_id(hex) != -1, "Fixture uses valid ground hexes")
	for take_and_hold: bool in [false, true]:
		_prepare()
		unit.give_move_to_hex_order(DESTINATION, _path([START, WAYPOINT, DESTINATION]), take_and_hold)
		_check_state(SquadActionController.SquadActionState.MOVING_TO_POSITION, "Move order starts moving")
		_advance()
		_check(unit.current_hex == WAYPOINT and unit.movement.is_moving, "Movement continues after its first waypoint")
		_check_state(SquadActionController.SquadActionState.MOVING_TO_POSITION, "Waypoint stop does not complete the order")
		_check(arrivals.is_empty() and unit.action_controller.establishing_timer.is_stopped(), "Waypoint does not emit final arrival or start establishing")
		_advance()
		await _check_establish_then_hold("Move arrival")
	_prepare()
	unit.give_defend_area_order(DESTINATION, _path([START, DESTINATION]))
	_advance()
	await _check_establish_then_hold("Defend arrival")
	await _test_attack_arrivals()
	await _test_withdrawal_and_rout()
	_test_cancellation_and_replacement()
	_test_late_arrivals()
	_test_direct_ai_move()
	_prepare()
	unit.give_move_to_hex_order(START, _path([START]), true)
	_advance()
	await _check_establish_then_hold("Already-at-destination arrival", START)
	main._on_try_again()
	await get_tree().create_timer(0.2).timeout
	_check(Globals.get_units().is_empty(), "Restart clears units and action timers")
	for soldier: Soldier in soldiers:
		var tasks: Array[SoldierTask] = [
			soldier.setup_weapon_task, soldier.aquire_target_task, soldier.reload_task,
			soldier.fire_weapon_task, soldier.assist_task, soldier.close_combat_task,
		]
		for task: SoldierTask in tasks:
			if is_instance_valid(task):
				task.free()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Unit arrival regression failures: ", failures)
	get_tree().quit(failures)


func _test_attack_arrivals() -> void:
	_prepare()
	unit.give_attack_hex_order(DESTINATION, _path([START, WAYPOINT]), _path([DESTINATION]))
	_advance()
	_check(unit.movement.in_exposed_phase and unit.movement.is_moving, "Covered path continues into the exposed segment")
	_check_state(SquadActionController.SquadActionState.MOVING_TO_POSITION, "Covered phase completion does not establish a position")
	_check(arrivals.is_empty() and unit.action_controller.establishing_timer.is_stopped(), "Covered phase emits no final arrival")
	_advance()
	await _check_establish_then_hold("Assault arrival")
	_check(unit.squad_fire.target_hex == DESTINATION, "Holding an assault position preserves its attack target")
	# The arrival handler also supports the action controller's crossing state.
	_prepare()
	unit.give_attack_hex_order(DESTINATION, [], _path([DESTINATION]))
	unit.action_controller._set_action_state(SquadActionController.SquadActionState.CROSSING_EXPOSED)
	_advance()
	await _check_establish_then_hold("Crossing-exposed arrival")
	_prepare()
	unit.give_attack_hex_order(DESTINATION, _path([START, DESTINATION]), [])
	_advance()
	await _check_establish_then_hold("Assault with only a covered path")


func _test_withdrawal_and_rout() -> void:
	_prepare()
	unit.give_withdraw_to_hex_order(DESTINATION, _path([START, WAYPOINT, DESTINATION]))
	_advance()
	_check_state(SquadActionController.SquadActionState.LOCAL_FALLBACK, "Withdrawal keeps its action state through waypoints")
	_advance()
	await _check_establish_then_hold("Withdrawal arrival")
	_prepare()
	unit.action_controller._set_action_state(SquadActionController.SquadActionState.ROUTING)
	unit.movement.follow_cube_path(_path([START, WAYPOINT, DESTINATION]))
	unit.movement.retreating = true
	_advance()
	_check_state(SquadActionController.SquadActionState.ROUTING, "Rout continues through waypoints")
	_advance()
	_check_state(SquadActionController.SquadActionState.REGROUPING, "Retreat completion enters regrouping")
	_check(unit.action_controller.establishing_timer.is_stopped(), "Final rout arrival does not replace regrouping with establishing")
	_check(not unit.action_controller.regroup_timer.is_stopped(), "Rout starts its regrouping timer")
	await get_tree().create_timer(0.08).timeout
	_check_state(SquadActionController.SquadActionState.HOLDING_POSITION, "Regrouping timer still advances to holding")


func _test_cancellation_and_replacement() -> void:
	_prepare()
	# Exercise the public command API used by player input and AI withdrawal.
	unit.order(Globals.UnitCmd.MOVE, DESTINATION)
	_check(unit.movement.is_moving, "Player move command starts a path")
	unit.movement._process_movement(0.01)
	unit.order(Globals.UnitCmd.STOP, null)
	_advance()
	_check_state(SquadActionController.SquadActionState.HOLDING_POSITION, "Stop before the objective holds at the recentered hex")
	_check(unit.action_controller.establishing_timer.is_stopped(), "Canceled objective does not start establishing")
	_prepare()
	unit.give_move_to_hex_order(DESTINATION, _path([START, DESTINATION]), true)
	unit.give_hold_order()
	_advance()
	_check_state(SquadActionController.SquadActionState.HOLDING_POSITION, "Hold remains holding after recentering")
	_prepare()
	unit.give_move_to_hex_order(DESTINATION, _path([START, DESTINATION]), true)
	unit.clear_orders()
	unit.unit_arrived_at_hex.emit(START)
	_check_state(SquadActionController.SquadActionState.NO_ORDER, "Late arrival cannot restore cleared orders")
	_prepare()
	unit.give_move_to_hex_order(DESTINATION, _path([START, DESTINATION]), true)
	unit.give_move_to_hex_order(WAYPOINT, _path([START, WAYPOINT]), true)
	unit._on_unit_arrived_at_hex(DESTINATION)
	unit._on_unit_arrived_at_hex(START)
	_check_state(SquadActionController.SquadActionState.MOVING_TO_POSITION, "Old or mid-movement arrival notifications cannot finish a replacement order")
	_advance()
	_check_state(SquadActionController.SquadActionState.ESTABLISHING_POSITION, "Replacement order completes at its own destination")
	unit.give_move_to_hex_order(DESTINATION, _path([WAYPOINT, DESTINATION]), true)
	_check(unit.action_controller.establishing_timer.is_stopped(), "Replacement movement cancels the previous establishing timer")


func _test_late_arrivals() -> void:
	_prepare()
	unit.action_controller.objective_hex = START
	unit.action_controller._set_action_state(SquadActionController.SquadActionState.MOVING_TO_POSITION)
	unit.surrendered = true
	unit._on_unit_arrived_at_hex(START)
	_check(unit.action_controller.establishing_timer.is_stopped(), "Late arrival cannot start establishing for a surrendered unit")
	unit.surrendered = false
	unit.alive = false
	unit._on_unit_arrived_at_hex(START)
	_check(unit.action_controller.establishing_timer.is_stopped(), "Late arrival cannot start establishing for a dead unit")
	unit.alive = true


func _test_direct_ai_move() -> void:
	_prepare()
	var order: AiOrder = AiOrder.new()
	order.order_type = AiOrder.OrderType.MOVE_TO
	order.target_hex = DESTINATION
	unit.squad_ai_controller.set_order(order)
	unit.squad_ai_controller._execute_order()
	_check_state(SquadActionController.SquadActionState.MOVING_TO_POSITION, "Direct AI movement enters the moving state")
	_advance()
	_check_state(SquadActionController.SquadActionState.HOLDING_POSITION, "Direct AI movement leaves the moving state on arrival")
	unit.squad_ai_controller.set_order(null)


func _check_establish_then_hold(label: String, destination: Vector2i = DESTINATION) -> void:
	_check(unit.current_hex == destination and not unit.movement.is_moving, label + ": final destination reached")
	_check(arrivals == [destination], label + ": final arrival emitted once")
	_check_state(SquadActionController.SquadActionState.ESTABLISHING_POSITION, label + ": establishes position")
	_check(not unit.action_controller.establishing_timer.is_stopped(), label + ": establishing timer starts")
	_check(action_states.count(SquadActionController.SquadActionState.ESTABLISHING_POSITION) == 1, label + ": one establishing transition")
	var time_left: float = unit.action_controller.establishing_timer.time_left
	unit.unit_arrived_at_hex.emit(destination)
	_check(unit.action_controller.establishing_timer.time_left == time_left, label + ": duplicate arrival does not restart the timer")
	await get_tree().create_timer(0.08).timeout
	_check_state(SquadActionController.SquadActionState.HOLDING_POSITION, label + ": establishing timer advances to holding")


func _prepare() -> void:
	unit.movement.is_moving = false
	unit.is_moving = false
	unit.movement._clear_path_state()
	unit.clear_orders()
	unit.current_hex = START
	unit.current_cube = LOSHelper.ground_layer.map_to_cube(START)
	unit.position = LOSHelper.ground_layer.map_to_local(START)
	unit.alive = true
	unit.surrendered = false
	unit.broken = false
	unit.stress_system.state = STATES.MoraleState.NORMAL
	arrivals.clear()
	action_states.clear()


func _path(hexes: Array[Vector2i]) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for hex: Vector2i in hexes:
		result.append(LOSHelper.ground_layer.map_to_cube(hex))
	return result


func _advance() -> void:
	unit.movement._process_movement(100.0)


func _freeze_simulation(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer:
		var timer: Timer = node as Timer
		timer.stop()
	for child: Node in node.get_children():
		_freeze_simulation(child)


func _on_arrival(hex: Vector2i) -> void:
	arrivals.append(hex)


func _on_action_state_changed(_prev: int, next: int) -> void:
	action_states.append(next)


func _check_state(expected: int, label: String) -> void:
	_check(unit.action_controller.action_state == expected, label)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
