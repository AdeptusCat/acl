extends Node

# Run with: godot --headless --path . tests/unit_movement_regression.tscn
class MovementUnderTest extends UnitMovement:
	func _get_terrain_multiplier() -> void:
		terrain_mult = 1.0


var failures: int = 0
var entered_hexes: Array[Vector2i] = []
var arrived_hexes: Array[Vector2i] = []
var crossing_count: int = 0


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
	unit.unit_entered_hex.connect(_on_entered)
	unit.unit_arrived_at_hex.connect(_on_arrived)
	movement.crossing_exposed_started.connect(_on_crossing)
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

	unit.stress_system.free()
	unit.free()
	movement.free()
	LOSHelper.ground_layer = null
	ground.free()
	print("Movement regression failures: ", failures)
	get_tree().quit(failures)


func _reset(unit: Unit, ground: HexagonTileMapLayer, hex: Vector2i) -> void:
	unit.current_hex = hex
	unit.current_cube = ground.map_to_cube(hex)
	unit.position = ground.map_to_local(hex)
	entered_hexes.clear()
	arrived_hexes.clear()
	crossing_count = 0


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
