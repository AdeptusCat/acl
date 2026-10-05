extends Node

# Run with: godot --headless --path . tests/unit_movement_regression.tscn
class MovementUnderTest extends UnitMovement:
	func _get_terrain_multiplier() -> void:
		terrain_mult = 1.0


class UiUnderTest extends UnitUi:
	func state_changed(_state: int) -> void:
		pass


class ActionControllerUnderTest extends SquadActionController:
	var retreat_destination: Vector2i

	func compute_retreat_hex(_origin: Vector2i, _enemies: Array[Unit], _max_steps: int) -> Vector2i:
		return retreat_destination

	func create_restricted_astar(_allowed_hexes: Array[Vector2i]) -> AStar2D:
		var route: AStar2D = AStar2D.new()
		route.add_point(0, LOSHelper.ground_layer.map_to_local(unit.current_hex))
		route.add_point(1, LOSHelper.ground_layer.map_to_local(retreat_destination))
		route.connect_points(0, 1)
		return route


var failures: int = 0
var entered_hexes: Array[Vector2i] = []
var arrived_hexes: Array[Vector2i] = []
var crossing_count: int = 0
var retreat_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ground.tile_set.tile_size = Vector2i(64, 64)
	ground.pathfinding_enabled = false
	add_child(ground)
	LOSHelper.ground_layer = ground
	var unit: Unit = Unit.new()
	unit.stress_system = StressController.new()
	var movement: MovementUnderTest = MovementUnderTest.new()
	movement.unit = unit
	unit.movement = movement
	unit.unit_entered_hex.connect(_on_entered)
	unit.unit_arrived_at_hex.connect(_on_arrived)
	movement.crossing_exposed_started.connect(_on_crossing)
	unit.retreat_complete.connect(_on_retreat)
	var start: Vector2i = Vector2i(2, 2)
	var target: Vector2i = Vector2i(6, 4)
	_reset(unit, ground, start)
	movement.move_to_hex(target)
	# A small step crosses a cell boundary before arrival.
	for index: int in range(60):
		movement._process_movement(0.05)
	_check(not entered_hexes.is_empty(), "Direct movement emits entry before arrival")
	_check(unit.current_hex == ground.local_to_map(unit.position), "Direct movement tracks occupied hex")
	movement._process_movement(100.0)
	_check(unit.current_hex == target, "Direct arrival updates hex")
	_check(unit.current_cube == ground.map_to_cube(target), "Direct arrival updates cube")
	_check(arrived_hexes == [target], "Arrival signal uses destination")
	_check(entered_hexes.count(target) == 1, "Destination entry is emitted once")

	_reset(unit, ground, start)
	var path: Array[Vector3i] = [ground.map_to_cube(start), ground.map_to_cube(target)]
	movement.follow_cube_path(path)
	movement._process_movement(100.0)
	_check(unit.current_hex == target, "Large path step updates hex before completion")
	_check(entered_hexes == [target], "Large path step emits entry")
	_check(arrived_hexes == [target], "Large path step emits correct arrival")

	var exposed: Array[Vector3i] = [ground.map_to_cube(target)]
	for covered_size: int in range(3):
		_reset(unit, ground, start)
		var covered: Array[Vector3i] = []
		if covered_size > 0:
			covered.append(ground.map_to_cube(start))
		if covered_size > 1:
			covered.append(ground.map_to_cube(Vector2i(3, 3)))
		movement.set_attack_paths(covered, exposed)
		_check(movement.exposed_path_hexes == [target], "Exposed cubes convert to map coordinates")
		movement.start_covered_phase()
		if covered_size > 1:
			movement._process_movement(100.0)
		_check(movement.is_moving and movement.in_exposed_phase, "Attack starts exposed movement")
		_check(crossing_count == 1, "Attack emits crossing once")
		movement._process_movement(100.0)
		_check(unit.current_hex == target, "Attack reaches exposed destination")
		_check(not movement.attack_in_progress, "Attack completes")
		_check(arrived_hexes == [target], "Attack emits final arrival once")

	_test_stop(unit, ground, movement)
	_test_replacement_moves(unit, ground, movement)
	_test_action_orders(unit, ground, movement)

	unit.stress_system.free()
	unit.free()
	movement.free()
	LOSHelper.ground_layer = null
	ground.free()
	print("Movement regression failures: ", failures)
	get_tree().quit(failures)


func _test_stop(unit: Unit, ground: HexagonTileMapLayer, movement: UnitMovement) -> void:
	var start: Vector2i = Vector2i(11, 8)
	for exposed_phase: bool in [false, true]:
		_begin_attack(unit, ground, movement, start)
		if exposed_phase:
			movement._process(100.0)
		movement._process(0.05)
		var stopped_hex: Vector2i = unit.current_hex
		var crossings_before: int = crossing_count
		movement.stop()
		_check_assault_canceled(movement, "Stop cancels assault in either phase")
		movement._process(100.0)
		movement._process(100.0)
		_check(not movement.is_moving, "Stop stays stopped after recentering")
		_check(unit.current_hex == stopped_hex, "Stop does not resume the old exposed destination")
		_check(unit.position == ground.map_to_local(stopped_hex), "Stop recenters on the occupied hex")
		_check(crossing_count == crossings_before, "Stop does not start another exposed crossing")

	_begin_attack(unit, ground, movement, start)
	movement.is_moving = false
	movement.stop()
	_check_assault_canceled(movement, "Stop clears a paused assault")
	movement.start_covered_phase()
	_check(not movement.is_moving, "A late phase-start call cannot restart a canceled assault")

	_reset(unit, ground, start)
	movement.is_moving = false
	var covered: Array[Vector3i] = [ground.map_to_cube(start), ground.map_to_cube(start + Vector2i(0, 1))]
	var exposed: Array[Vector3i] = [ground.map_to_cube(start + Vector2i(0, 2))]
	movement.set_attack_paths(covered, exposed)
	movement.stop()
	movement.start_covered_phase()
	_check_assault_canceled(movement, "Stop cancels an assault before its first phase starts")
	_check(not movement.is_moving, "Canceled staged assault remains idle")


func _test_replacement_moves(unit: Unit, ground: HexagonTileMapLayer, movement: UnitMovement) -> void:
	var start: Vector2i = Vector2i(11, 8)
	var target: Vector2i = Vector2i(13, 7)
	_begin_attack(unit, ground, movement, start)
	movement.move_to_hex(target)
	_check_assault_canceled(movement, "Direct replacement move cancels assault")
	_check(movement.path_hexes.is_empty(), "Direct replacement move discards old waypoints")
	movement._process(100.0)
	movement._process(100.0)
	_check(unit.current_hex == target and not movement.is_moving, "Direct replacement ends at its own target")
	_check(crossing_count == 0, "Direct replacement does not cross the old exposed segment")

	_begin_attack(unit, ground, movement, start)
	var replacement: Array[Vector3i] = [ground.map_to_cube(start), ground.map_to_cube(Vector2i(12, 7)), ground.map_to_cube(target)]
	movement.follow_cube_path(replacement)
	_check_assault_canceled(movement, "Replacement path cancels assault")
	movement._process(100.0)
	_check(movement.is_moving, "Replacement path continues through its own waypoints")
	movement._process(100.0)
	movement._process(100.0)
	_check(unit.current_hex == target and not movement.is_moving, "Replacement path ends without the old exposed segment")

	_begin_attack(unit, ground, movement, start)
	var empty: Array[Vector3i] = []
	movement.follow_cube_path(empty)
	movement._process(100.0)
	_check_assault_canceled(movement, "Empty replacement path cancels assault")
	_check(unit.current_hex == start and not movement.is_moving, "Empty replacement stops instead of following an old goal")

	_begin_attack(unit, ground, movement, start)
	var covered: Array[Vector3i] = [ground.map_to_cube(start), ground.map_to_cube(Vector2i(12, 7))]
	var exposed: Array[Vector3i] = [ground.map_to_cube(target)]
	movement.set_attack_paths(covered, exposed)
	_check(not movement.is_moving, "Preparing a replacement assault suspends the old movement")
	movement.start_covered_phase()
	movement._process(100.0)
	movement._process(100.0)
	_check(unit.current_hex == target and not movement.is_moving, "Replacement assault reaches its new exposed target")
	_check(crossing_count == 1, "Replacement assault crosses only its new exposed segment")


func _test_action_orders(unit: Unit, ground: HexagonTileMapLayer, movement: UnitMovement) -> void:
	var controller: ActionControllerUnderTest = ActionControllerUnderTest.new()
	var squad_fire: SquadFireController = SquadFireController.new()
	squad_fire.unit = unit
	var ui: UiUnderTest = UiUnderTest.new()
	controller.init(unit, movement, squad_fire, unit.stress_system, ui)
	var start: Vector2i = Vector2i(11, 8)
	_begin_attack(unit, ground, movement, start)
	controller.give_hold_order()
	_check_assault_canceled(movement, "Hold order cancels pending assault")
	movement._process(100.0)
	_check(unit.current_hex == start and not movement.is_moving, "Hold order stays in the occupied hex")

	_begin_attack(unit, ground, movement, start)
	controller.clear_orders()
	_check_assault_canceled(movement, "Clearing orders cancels pending assault")
	_check(not movement.is_moving, "Clearing orders ends movement")

	_begin_attack(unit, ground, movement, start)
	var empty: Array[Vector3i] = []
	controller.give_move_to_hex_order(Vector2i(13, 7), empty, false)
	_check_assault_canceled(movement, "Invalid replacement order cancels pending assault")

	_begin_attack(unit, ground, movement, start)
	controller.action_state = SquadActionController.SquadActionState.MOVING_TO_POSITION
	controller.on_morale_state_changed(STATES.MoraleState.NORMAL, STATES.MoraleState.PINNED)
	movement._process(100.0)
	_check_assault_canceled(movement, "Pinning cancels the remaining assault")
	_check(unit.current_hex == start and not movement.is_moving, "Pinned squad does not resume assault after recentering")

	_begin_attack(unit, ground, movement, start)
	controller.retreat_destination = Vector2i(10, 7)
	controller._start_rout()
	_check_assault_canceled(movement, "Rout replaces assault with a retreat path")
	_check(movement.retreating, "New rout retains its own retreat context")
	movement._process(100.0)
	movement._process(100.0)
	_check(unit.current_hex == controller.retreat_destination and not movement.is_moving, "Rout ends at the retreat destination")
	_check(retreat_count == 1, "Rout emits retreat completion once")

	_reset(unit, ground, start)
	var retreat_path: Array[Vector3i] = [ground.map_to_cube(start), ground.map_to_cube(Vector2i(10, 7))]
	movement.follow_cube_path(retreat_path)
	movement.retreating = true
	movement.stop()
	movement._process(100.0)
	_check(not movement.retreating and retreat_count == 0, "Stopping a retreat does not emit false retreat completion")

	controller.free()
	squad_fire.free()
	ui.free()


func _begin_attack(unit: Unit, ground: HexagonTileMapLayer, movement: UnitMovement, start: Vector2i) -> void:
	_reset(unit, ground, start)
	movement.is_moving = false
	var covered: Array[Vector3i] = [ground.map_to_cube(start), ground.map_to_cube(start + Vector2i(0, 1))]
	var exposed: Array[Vector3i] = [ground.map_to_cube(start + Vector2i(0, 2))]
	movement.set_attack_paths(covered, exposed)
	movement.start_covered_phase()


func _check_assault_canceled(movement: UnitMovement, context: String) -> void:
	_check(not movement.attack_in_progress and not movement.in_exposed_phase, context + ": phase flags")
	_check(movement.covered_path_cubes.is_empty() and movement.exposed_path_hexes.is_empty(), context + ": queued segments")


func _reset(unit: Unit, ground: HexagonTileMapLayer, hex: Vector2i) -> void:
	unit.current_hex = hex
	unit.current_cube = ground.map_to_cube(hex)
	unit.position = ground.map_to_local(hex)
	entered_hexes.clear()
	arrived_hexes.clear()
	crossing_count = 0
	retreat_count = 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _on_entered(unit: Unit, hex: Vector2i) -> void:
	_check(unit.current_hex == hex, "Entry signal sees updated coordinates")
	entered_hexes.append(hex)


func _on_arrived(hex: Vector2i) -> void:
	arrived_hexes.append(hex)


func _on_crossing() -> void:
	crossing_count += 1


func _on_retreat(_hex: Vector2i) -> void:
	retreat_count += 1
