class_name InfluenceStamp
extends RefCounted

var values: PackedFloat32Array = PackedFloat32Array()
var min_cell: Vector2i = Vector2i.ZERO
var size: Vector2i = Vector2i.ZERO


func _init(p_min_cell: Vector2i = Vector2i.ZERO, p_size: Vector2i = Vector2i.ZERO) -> void:
	min_cell = p_min_cell
	size = p_size
	values.resize(size.x * size.y)


func get_index(local_x: int, local_y: int) -> int:
	return local_y * size.x + local_x


func contains_cell(cell: Vector2i) -> bool:
	if cell.x < min_cell.x:
		return false

	if cell.y < min_cell.y:
		return false

	if cell.x >= min_cell.x + size.x:
		return false

	if cell.y >= min_cell.y + size.y:
		return false

	return true


func get_value_at_cell(cell: Vector2i) -> float:
	if not contains_cell(cell):
		return 0.0

	var local_x: int = cell.x - min_cell.x
	var local_y: int = cell.y - min_cell.y
	var index: int = get_index(local_x, local_y)

	return values[index]


func add_value_at_cell(cell: Vector2i, value: float) -> void:
	if not contains_cell(cell):
		return

	var local_x: int = cell.x - min_cell.x
	var local_y: int = cell.y - min_cell.y
	var index: int = get_index(local_x, local_y)

	values[index] += value
