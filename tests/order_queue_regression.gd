extends Node

var checks: int = 0
var failures: int = 0
var ground: HexagonTileMapLayer
var controller: Node2D
var first: Unit
var second: Unit
var origin: Vector2i
var destination: Vector2i
var onward: Vector2i


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_node("DefaultMap")
	var scenario: Scenario = map.get_scenario(0)
	scenario.axis_ai_status = Scenario.AIStatus.OFF
	scenario.allies_ai_status = Scenario.AIStatus.OFF
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	controller = world.game_controller
	ground = world.ground_layer
	first = Globals.get_units_for_team(Globals.team_player)[1]
	second = Globals.get_units_for_team(Globals.team_player)[2]
	origin = first.current_hex
	destination = _neighbor(origin, origin)
	onward = _neighbor(destination, origin)
	_test_sequence()
	_test_interruptions()
	await _test_controls(world)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Order queue checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_freeze(child)


func _neighbor(cell: Vector2i, excluded: Vector2i) -> Vector2i:
	var graph: AStar2D = Globals.astars[first.team]
	var id: int = ground.pathfinding_get_point_id(cell)
	for neighbor: int in graph.get_point_connections(id):
		var target: Vector2i = ground.local_to_map(graph.get_point_position(neighbor))
		if target != excluded and not graph.is_point_disabled(neighbor):
			return target
	_check(false, "Fixture has a reachable neighbor")
	return cell


func _reset(unit: Unit, cell: Vector2i) -> void:
	unit.alive = true
	unit.broken = false
	unit.surrendered = false
	unit.in_close_combat = false
	unit.exited = false
	unit.stress_system.state = STATES.MoraleState.NORMAL
	unit.current_hex = cell
	unit.current_cube = ground.map_to_cube(cell)
	unit.position = ground.map_to_local(cell)
	unit.clear_orders()
	unit.clear_watch_order()


func _finish(unit: Unit) -> void:
	for index: int in range(100):
		if not unit.movement.is_moving:
			break
		unit.movement._process_movement(100.0)
	unit.action_controller.order_queue._process(0.0)


func _test_sequence() -> void:
	_reset(first, origin)
	var queue: SquadOrderQueue = first.action_controller.order_queue
	_check(queue.append(SquadOrderQueue.Kind.MOVE, destination) and queue.append(SquadOrderQueue.Kind.MOVE, onward), "Multiple moves append without issuing the later leg")
	queue.append(SquadOrderQueue.Kind.WATCH, origin)
	first.setAttackState(Unit.AttackState.MANUAL_GROUND)
	_check(not queue.append(SquadOrderQueue.Kind.MOVE, origin), "Watch is a final action until removed")
	queue._process(0.0)
	_check(first.action_controller.objective_hex == destination and queue.pending.size() == 2, "Only the first move starts")
	_finish(first)
	queue._process(0.0)
	_check(first.action_controller.objective_hex == onward and first.movement.is_moving, "Arrival starts the next move from the reached hex")
	_finish(first)
	queue._process(0.0)
	var expected: Vector2 = first.global_position.direction_to(ground.to_global(ground.map_to_local(origin)))
	_check(first.has_watch_order() and first.watch_direction.is_equal_approx(expected), "Final Watch computes its bearing from the final position")
	_check(first.attackState == Unit.AttackState.AUTO, "Final Watch returns firing to automatic targeting")
	queue._process(0.0)
	_check(queue.current.get("kind") == SquadOrderQueue.Kind.WATCH and not first.movement.is_moving, "Watch remains active")
	queue.remove(0)
	_check(queue.entries().is_empty() and not first.has_watch_order(), "Removing the active Watch also clears its bearing")
	_reset(first, origin)
	first.order(Globals.UnitCmd.MOVE, destination)
	queue.append(SquadOrderQueue.Kind.MOVE, onward)
	_check(queue.current["target"] == destination and queue.pending[0]["target"] == onward, "Shift adopts an existing live move without replacing it")
	first.order(Globals.UnitCmd.MOVE, onward)
	_check(queue.entries().is_empty(), "An ordinary move replaces the queue")
	queue.append(SquadOrderQueue.Kind.WATCH, origin)
	first.clear_orders()
	_check(queue.entries().is_empty(), "Stop clears queued actions")


func _test_interruptions() -> void:
	_reset(first, origin)
	var queue: SquadOrderQueue = first.action_controller.order_queue
	queue.append(SquadOrderQueue.Kind.MOVE, destination)
	queue.append(SquadOrderQueue.Kind.WATCH, origin)
	queue._process(0.0)
	first.stress_system._set_state(STATES.MoraleState.PINNED)
	queue._process(0.0)
	_check(not first.movement.is_moving and queue.pending.size() == 1, "Pinning pauses movement without consuming later orders")
	first.stress_system._set_state(STATES.MoraleState.NORMAL)
	queue._process(0.0)
	_check(first.movement.is_moving and first.movement.target_hex == destination, "Recovery replans the interrupted leg")
	_finish(first)
	queue._process(0.0)
	_check(queue.current.get("kind") == SquadOrderQueue.Kind.WATCH and not first.movement.is_moving, "Final Watch starts after reaching the destination")
	_reset(first, origin)
	queue.append(SquadOrderQueue.Kind.MOVE, Vector2i(-900, -900))
	queue.append(SquadOrderQueue.Kind.WATCH, origin)
	queue._process(0.0)
	_check(not queue.failure.is_empty() and queue.pending.size() == 1, "An unreachable leg blocks the queue instead of silently skipping it")
	queue.remove(0)
	queue._process(0.0)
	_check(queue.current.get("kind") == SquadOrderQueue.Kind.WATCH, "Removing a blocked leg lets the queue continue")
	_reset(first, origin)
	queue.append(SquadOrderQueue.Kind.MOVE, destination)
	first.in_close_combat = true
	queue._process(0.0)
	_check(queue.entries().is_empty(), "Close combat cancels queued actions")
	first.in_close_combat = false
	_reset(first, origin)
	queue.append(SquadOrderQueue.Kind.MOVE, destination)
	queue._process(0.0)
	_finish(first)
	queue._process(0.0)
	_check(queue.entries().is_empty() and not first.movement.is_moving and first.current_hex == destination, "A final move stops at its destination without an additional queued action")
	_reset(first, origin)


func _test_controls(world: Node) -> void:
	controller.select_and_center_unit(first)
	var details: PanelContainer = world.ui.unit_details
	details.show_unit_detail(first, false)
	var shift: InputEventKey = InputEventKey.new()
	shift.keycode = KEY_SHIFT
	shift.pressed = true
	Input.parse_input_event(shift)
	Input.flush_buffered_events()
	_check(controller.order_via_option_wheel(destination, WheelOption.Option.MOVE_NORMAL), "Shift Move is accepted through the command wheel")
	_check(first.action_controller.order_queue.pending.size() == 1 and not first.movement.is_moving, "Shift Move appends rather than replacing through the UI")
	_check(controller.order_via_option_wheel(origin, WheelOption.Option.WATCH), "Queued Watch can point back toward the current hex from a future destination")
	_check(not controller.order_via_option_wheel(destination, WheelOption.Option.WATCH), "Queued Watch rejects a direction equal to its future position")
	first.action_controller.order_queue.remove(1)
	shift = InputEventKey.new()
	shift.keycode = KEY_SHIFT
	Input.parse_input_event(shift)
	Input.flush_buffered_events()
	details._refresh_order_controls()
	_check(details._order_rows.get_child_count() == 1, "The panel displays numbered queued orders")
	if OS.get_cmdline_user_args().has("--capture"):
		get_tree().root.size = Vector2i(1152, 648)
		details._orders_section.folded = false
		details._refresh_order_controls()
		controller.los_renderer.queue_redraw()
		for frame: int in range(6):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/acl-order-queue.png")
	first.clear_orders()
	second.clear_orders()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
