class_name InfluenceMap
extends RefCounted

enum Layer {
	TERRAIN_COVER,
	TERRAIN_MOVE_COST,
	
	ENEMY_VISIBILITY,
	ENEMY_FIRE_THREAT,
	
	COVER_VS_ENEMY_FIRE,
	ENEMY_VISIBILITY_HINDRANCE,
	RETURN_FIRE_PENALTY,
	
	FRIENDLY_SUPPORT,
	OBJECTIVE_PRESSURE,
	KNOWN_ENEMY_POSITION,
	NO_GO,
	
	COUNT
}

enum WriteMode {
	SET,
	ADD,
	MAX,
	MIN
}

const DEFAULT_COMPOSITE_MIN: float = 0.05
const DEFAULT_COMPOSITE_MAX: float = 20.0

var bounds: Rect2i = Rect2i()
var width: int = 0
var height: int = 0
var cell_count: int = 0

var _layers: Array[PackedFloat32Array] = []
var _composite: PackedFloat32Array = PackedFloat32Array()
var _composite_weights: PackedFloat32Array = PackedFloat32Array()

var _dirty_flags: PackedByteArray = PackedByteArray()
var _dirty_indices: PackedInt32Array = PackedInt32Array()
var _dirty_cursor: int = 0

var composite_min: float = DEFAULT_COMPOSITE_MIN
var composite_max: float = DEFAULT_COMPOSITE_MAX
var composite_base: float = 1.0


func get_layer_value_by_cell(layer_id: int, cell: Vector2i, fallback: float = 0.0) -> float:
	if not is_valid_layer(layer_id):
		return fallback

	if not is_valid_cell(cell):
		return fallback

	var index: int = cell_to_index(cell)
	var data: PackedFloat32Array = _layers[layer_id]

	return data[index]


func get_layer_data_copy(layer_id: int) -> PackedFloat32Array:
	if not is_valid_layer(layer_id):
		return PackedFloat32Array()

	var data: PackedFloat32Array = _layers[layer_id]
	return data.duplicate()


func configure(p_bounds: Rect2i) -> void:
	bounds = p_bounds
	width = bounds.size.x
	height = bounds.size.y
	cell_count = width * height

	_layers.clear()

	var layer_id: int = 0
	while layer_id < Layer.COUNT:
		var data: PackedFloat32Array = PackedFloat32Array()
		data.resize(cell_count)
		data.fill(0.0)
		_layers.append(data)
		layer_id += 1

	_composite.resize(cell_count)
	_composite.fill(composite_base)

	_composite_weights.resize(Layer.COUNT)
	_composite_weights.fill(0.0)

	_dirty_flags.resize(cell_count)
	_dirty_flags.fill(0)

	_dirty_indices.clear()
	_dirty_cursor = 0

	mark_all_dirty()


func configure_composite_weights(
	p_weights: PackedFloat32Array,
	p_base: float,
	p_min: float,
	p_max: float
) -> void:
	composite_base = p_base
	composite_min = p_min
	composite_max = p_max

	_composite_weights.resize(Layer.COUNT)
	_composite_weights.fill(0.0)

	var index: int = 0
	while index < p_weights.size() and index < Layer.COUNT:
		_composite_weights[index] = p_weights[index]
		index += 1

	mark_all_dirty()


func is_valid_layer(layer_id: int) -> bool:
	if layer_id < 0:
		return false

	if layer_id >= Layer.COUNT:
		return false

	return true


func is_valid_cell(cell: Vector2i) -> bool:
	if cell.x < bounds.position.x:
		return false

	if cell.y < bounds.position.y:
		return false

	if cell.x >= bounds.position.x + width:
		return false

	if cell.y >= bounds.position.y + height:
		return false

	return true


func cell_to_index(cell: Vector2i) -> int:
	var local_x: int = cell.x - bounds.position.x
	var local_y: int = cell.y - bounds.position.y
	var index: int = local_y * width + local_x
	return index


func index_to_cell(index: int) -> Vector2i:
	var local_y: int = index / width
	var local_x: int = index - local_y * width

	var cell: Vector2i = Vector2i(
		bounds.position.x + local_x,
		bounds.position.y + local_y
	)

	return cell


func get_layer_value(layer_id: int, cell: Vector2i, fallback: float = 0.0) -> float:
	if not is_valid_layer(layer_id):
		return fallback

	if not is_valid_cell(cell):
		return fallback

	var index: int = cell_to_index(cell)
	var data: PackedFloat32Array = _layers[layer_id]

	return data[index]


func set_layer_value(layer_id: int, cell: Vector2i, value: float) -> void:
	if not is_valid_layer(layer_id):
		return

	if not is_valid_cell(cell):
		return

	var index: int = cell_to_index(cell)
	var data: PackedFloat32Array = _layers[layer_id]
	data[index] = value
	_layers[layer_id] = data

	_mark_dirty_index(index)


func add_layer_value(layer_id: int, cell: Vector2i, value: float) -> void:
	if not is_valid_layer(layer_id):
		return

	if not is_valid_cell(cell):
		return
	
	if layer_id == InfluenceMap.Layer.ENEMY_VISIBILITY_HINDRANCE:
		if value > 0.0:
			pass
	
	var index: int = cell_to_index(cell)
	var data: PackedFloat32Array = _layers[layer_id]
	data[index] += value
	_layers[layer_id] = data

	_mark_dirty_index(index)


func max_layer_value(layer_id: int, cell: Vector2i, value: float) -> void:
	if not is_valid_layer(layer_id):
		return

	if not is_valid_cell(cell):
		return

	var index: int = cell_to_index(cell)
	var data: PackedFloat32Array = _layers[layer_id]

	if value > data[index]:
		data[index] = value
		_layers[layer_id] = data
		_mark_dirty_index(index)


func min_layer_value(layer_id: int, cell: Vector2i, value: float) -> void:
	if not is_valid_layer(layer_id):
		return

	if not is_valid_cell(cell):
		return

	var index: int = cell_to_index(cell)
	var data: PackedFloat32Array = _layers[layer_id]

	if value < data[index]:
		data[index] = value
		_layers[layer_id] = data
		_mark_dirty_index(index)


func clear_layer(layer_id: int, value: float = 0.0) -> void:
	if not is_valid_layer(layer_id):
		return

	var data: PackedFloat32Array = _layers[layer_id]
	data.fill(value)
	_layers[layer_id] = data

	mark_all_dirty()


func get_composite_value(cell: Vector2i, fallback: float = 1.0) -> float:
	if not is_valid_cell(cell):
		return fallback

	var index: int = cell_to_index(cell)
	return _composite[index]


func get_composite_value_by_index(index: int) -> float:
	if index < 0:
		return composite_base

	if index >= cell_count:
		return composite_base

	return _composite[index]


func rebuild_all_composite() -> void:
	var index: int = 0

	while index < cell_count:
		_composite[index] = _calculate_composite_at_index(index)
		index += 1

	_dirty_flags.fill(0)
	_dirty_indices.clear()
	_dirty_cursor = 0


func rebuild_dirty_composite_budgeted(max_cells: int) -> bool:
	var processed: int = 0

	while _dirty_cursor < _dirty_indices.size() and processed < max_cells:
		var index: int = _dirty_indices[_dirty_cursor]

		if index >= 0 and index < cell_count:
			_composite[index] = _calculate_composite_at_index(index)
			_dirty_flags[index] = 0

		_dirty_cursor += 1
		processed += 1

	if _dirty_cursor >= _dirty_indices.size():
		_dirty_indices.clear()
		_dirty_cursor = 0
		return true

	return false


func mark_all_dirty() -> void:
	_dirty_indices.clear()
	_dirty_cursor = 0

	_dirty_flags.resize(cell_count)
	_dirty_flags.fill(1)

	var index: int = 0
	while index < cell_count:
		_dirty_indices.append(index)
		index += 1


func stamp_radius(
	layer_id: int,
	center: Vector2i,
	radius: int,
	value: float,
	mode: int,
	falloff: bool
) -> void:
	if not is_valid_layer(layer_id):
		return

	var min_x: int = center.x - radius
	var max_x: int = center.x + radius
	var min_y: int = center.y - radius
	var max_y: int = center.y + radius

	var y: int = min_y
	while y <= max_y:
		var x: int = min_x

		while x <= max_x:
			var cell: Vector2i = Vector2i(x, y)

			if is_valid_cell(cell):
				var distance: int = _hex_distance(center, cell)

				if distance <= radius:
					var write_value: float = value

					if falloff:
						var falloff_factor: float = 1.0 - float(distance) / float(radius + 1)
						write_value = value * falloff_factor

					_write_layer_value(layer_id, cell, write_value, mode)

			x += 1

		y += 1


func copy_layer_to(layer_id: int, target: PackedFloat32Array) -> PackedFloat32Array:
	if not is_valid_layer(layer_id):
		return target

	target = _layers[layer_id].duplicate()
	return target


func _write_layer_value(layer_id: int, cell: Vector2i, value: float, mode: int) -> void:
	if mode == WriteMode.SET:
		set_layer_value(layer_id, cell, value)
		return

	if mode == WriteMode.ADD:
		add_layer_value(layer_id, cell, value)
		return

	if mode == WriteMode.MAX:
		max_layer_value(layer_id, cell, value)
		return

	if mode == WriteMode.MIN:
		min_layer_value(layer_id, cell, value)
		return


func _calculate_composite_at_index(index: int) -> float:
	var result: float = composite_base

	var layer_id: int = 0
	while layer_id < Layer.COUNT:
		var weight: float = _composite_weights[layer_id]

		if weight != 0.0:
			var data: PackedFloat32Array = _layers[layer_id]
			result += data[index] * weight

		layer_id += 1

	result = clamp(result, composite_min, composite_max)
	return result


func _mark_dirty_index(index: int) -> void:
	if index < 0:
		return

	if index >= cell_count:
		return

	if _dirty_flags[index] == 1:
		return

	_dirty_flags[index] = 1
	_dirty_indices.append(index)


func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	var ds: int = -a.x - a.y - (-b.x - b.y)

	var distance: int = (abs(dq) + abs(dr) + abs(ds)) / 2
	return distance
