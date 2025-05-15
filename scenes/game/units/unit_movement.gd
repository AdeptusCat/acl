# UnitMovement.gd
class_name UnitMovement
extends Node

var unit: Node2D
var ground_map: HexagonTileMapLayer

# Movement state
var path_hexes: Array[Vector2i] = []
var path_index: int = 0
var target_position: Vector2
var moving: bool = false
var move_speed: float = 100.0

# Retreat state
var retreating: bool = false
var retreat_distance := 3
var retreat_target_hex: Vector2i = Vector2i()


func _init(_unit: Node2D):
	unit = _unit

func process(delta: float):
	if moving:
		_process_movement(delta)

func move_to_hex(new_hex: Vector2i):
	unit.current_hex = new_hex
	target_position = ground_map.map_to_local(new_hex)
	moving = true
	unit.emit_signal("moved_to_hex", unit, new_hex)

func follow_cube_path(cube_path: Array[Vector3i]):
	path_hexes.clear()
	for c in cube_path:
		path_hexes.append(ground_map.cube_to_map(c))
	if path_hexes.size() > 1:
		path_index = 1
		move_to_hex(path_hexes[path_index])

func begin_retreat(target_hex: Vector2i):
	retreat_target_hex = target_hex
	retreating = true
	var from_id = ground_map.pathfinding_get_point_id(unit.current_hex)
	var to_id = ground_map.pathfinding_get_point_id(target_hex)
	var id_path = ground_map.astar.get_id_path(from_id, to_id)

	var cube_path: Array[Vector3i] = []
	for pid in id_path:
		var pos = ground_map.astar.get_point_position(pid)
		cube_path.append(ground_map.local_to_cube(pos))
	follow_cube_path(cube_path)

func _process_movement(delta: float):
	var dir = (target_position - unit.position).normalized()
	var dist = unit.position.distance_to(target_position)
	var step = move_speed * delta

	if dist <= step:
		unit.position = target_position
		moving = false

		if path_index < path_hexes.size() - 1:
			path_index += 1
			move_to_hex(path_hexes[path_index])
		else:
			if retreating:
				retreating = false
				unit.emit_signal("retreat_complete", unit.current_hex)
			unit.unit_arrived_at_hex.emit(unit.current_hex)
			path_hexes.clear()
			path_index = 0
	else:
		unit.position += dir * step
