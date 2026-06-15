class_name InfluenceMap
extends RefCounted

enum Layer {
	TERRAIN_COVER,
	TERRAIN_MOVE_COST,

	ENEMY_VISIBILITY,
	VISIBILITY,
	FIRE_POWER,
	THREAT,
	ENEMY_VULNERABILITY,

	COVER_VS_ENEMY_FIRE,
	VISIBILITY_HINDRANCE,

	UNIT_INFLUENCE,

	RETURN_FIRE_PENALTY,

	FRIENDLY_SUPPORT,
	OBJECTIVE_PRESSURE,
	KNOWN_ENEMY_POSITION,
	NO_GO,

	COUNT
}

enum WriteMode {
	SET = 0,
	ADD = 1,
	SUBTRACT = 2,
	SUBSTRACT = 2,
	MAX = 3,
	MIN = 4,
	MULTIPLY = 5,
	POSITIVE_MASK = 6
}

enum FalloffMode {
	NONE,
	LINEAR,
	SQUARE_ROOT,
	EXPONENTIAL
}

const ORIGIN_INFLUENCE_START_VALUE: float = 1.0
const ORIGIN_INFLUENCE_DISTANCE_LOSS: float = 0.1
const ORIGIN_INFLUENCE_MAX_DISTANCE: int = 3
const ORIGIN_INFLUENCE_TIME_LOSS: float = 0.1
const ORIGIN_INFLUENCE_DECAY_INTERVAL_S: float = 5.0

const DEFAULT_COMPOSITE_MIN: float = 0.05
const DEFAULT_COMPOSITE_MAX: float = 20.0

const UNIT_INFLUENCE_RADIUS: int = 5
const UNIT_INFLUENCE_VALUE: float = 5.0
const UNIT_INFLUENCE_CENTER_PULL_WEIGHT: float = 0.25

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
var unit_influence_decay_timer_s: float = 0.0


func configure(p_bounds: Rect2i) -> void:
	bounds = p_bounds
	width = bounds.size.x
	height = bounds.size.y
	cell_count = width * height

	_layers.clear()

	var layer_id: int = 0
	while layer_id < Layer.COUNT:
		var layer_data: PackedFloat32Array = PackedFloat32Array()
		layer_data.resize(cell_count)
		layer_data.fill(0.0)
		_layers.append(layer_data)
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


func get_cell_index(cell: Vector2i) -> int:
	return cell_to_index(cell)


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


func get_layer_value_by_cell(layer_id: int, cell: Vector2i, fallback: float = 0.0) -> float:
	return get_layer_value(layer_id, cell, fallback)


func get_layer_data_copy(layer_id: int) -> PackedFloat32Array:
	if not is_valid_layer(layer_id):
		return PackedFloat32Array()

	var data: PackedFloat32Array = _layers[layer_id]
	return data.duplicate()


func set_layer_data_copy(layer_id: int, values: PackedFloat32Array) -> void:
	if not is_valid_layer(layer_id):
		return

	if values.size() != cell_count:
		return

	_layers[layer_id] = values.duplicate()
	mark_all_dirty()


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

	var index: int = cell_to_index(cell)
	var data: PackedFloat32Array = _layers[layer_id]
	data[index] += value
	_layers[layer_id] = data

	_mark_dirty_index(index)


func subtract_layer_value(layer_id: int, cell: Vector2i, value: float) -> void:
	if not is_valid_layer(layer_id):
		return

	if not is_valid_cell(cell):
		return

	var index: int = cell_to_index(cell)
	var data: PackedFloat32Array = _layers[layer_id]
	data[index] -= value
	_layers[layer_id] = data

	_mark_dirty_index(index)


func substract_layer_value(layer_id: int, cell: Vector2i, value: float) -> void:
	subtract_layer_value(layer_id, cell, value)


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


func clear_layer_without_dirty(layer_id: int, value: float = 0.0) -> void:
	if not is_valid_layer(layer_id):
		return

	var data: PackedFloat32Array = _layers[layer_id]
	data.fill(value)
	_layers[layer_id] = data


func copy_layer_to(layer_id: int, target: PackedFloat32Array) -> PackedFloat32Array:
	if not is_valid_layer(layer_id):
		return target

	target = _layers[layer_id].duplicate()
	return target


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


func get_composite_data_copy() -> PackedFloat32Array:
	return _composite.duplicate()


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


func write_stamp_to_layer_with_return(
	layer: PackedFloat32Array,
	stamp: InfluenceStamp,
	mode: int,
	zero_outside_stamp: bool = false
) -> PackedFloat32Array:
	return InfluenceMapLayerOps.write_stamp_to_array_with_result(
		self,
		layer,
		stamp,
		mode,
		zero_outside_stamp
	)


func write_stamp_to_layer(layer_id: int, stamp: InfluenceStamp, mode: int) -> void:
	InfluenceMapLayerOps.write_stamp_to_layer(self, layer_id, stamp, mode)


func stamp_radius(
	layer_id: int,
	center: Vector2i,
	radius: int,
	value: float,
	mode: int,
	falloff_mode: int
) -> void:
	if not is_valid_layer(layer_id):
		return

	var stamp: InfluenceStamp = create_radius_stamp(
		center,
		radius,
		value,
		falloff_mode
	)

	write_stamp_to_layer(layer_id, stamp, mode)


func create_radius_stamp(
	center: Vector2i,
	radius: int,
	value: float,
	falloff_mode: int
) -> InfluenceStamp:
	return InfluenceMapStampOps.create_radius_stamp(
		center,
		radius,
		value,
		falloff_mode
	)


func add_stamps_with_return(
	stamp_a: InfluenceStamp,
	stamp_b: InfluenceStamp,
	max_value: float = INF
) -> InfluenceStamp:
	return InfluenceMapStampOps.add_stamps_with_result(stamp_a, stamp_b, max_value)


func stamp_to_full_map_array(
	stamp: InfluenceStamp,
	outside_value: float = 0.0
) -> PackedFloat32Array:
	return InfluenceMapStampOps.stamp_to_full_map_array(self, stamp, outside_value)


func apply_positive_mask_layer_with_return(
	layer: PackedFloat32Array,
	mask_layer: PackedFloat32Array
) -> PackedFloat32Array:
	return InfluenceMapLayerOps.apply_positive_mask_with_result(layer, mask_layer)


func add_layers_with_return(values_a: PackedFloat32Array, values_b: PackedFloat32Array) -> PackedFloat32Array:
	return InfluenceMapLayerOps.add_arrays_with_result(values_a, values_b)


func multiply_layers_with_return(values_a: PackedFloat32Array, values_b: PackedFloat32Array) -> PackedFloat32Array:
	return InfluenceMapLayerOps.multiply_arrays_with_result(values_a, values_b)


func multiply_layers(layer_a: int, layer_b: int, target_layer: int) -> void:
	InfluenceMapLayerOps.multiply_layers(self, layer_a, layer_b, target_layer)


func create_origin_stamp(origin_hex: Vector2i) -> PackedFloat32Array:
	var values: PackedFloat32Array = _layers[Layer.UNIT_INFLUENCE].duplicate()

	for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
			var hex: Vector2i = Vector2i(x, y)
			var distance: int = LOSHelper.get_hex_distance(origin_hex, hex)

			if distance > ORIGIN_INFLUENCE_MAX_DISTANCE:
				continue

			var value: float = ORIGIN_INFLUENCE_START_VALUE
			value -= float(distance) * ORIGIN_INFLUENCE_DISTANCE_LOSS

			if value < 0.0:
				value = 0.0

			var index: int = cell_to_index(hex)
			if index < 0:
				continue

			values[index] = value

	return values


func create_unit_stamp(unit: Unit) -> PackedFloat32Array:
	var values: PackedFloat32Array = PackedFloat32Array()
	values.resize(cell_count)
	values.fill(1.0)

	for other_unit: Unit in Globals.get_units_for_team(unit.team):
		if other_unit == unit:
			continue

		if not is_valid_cell(other_unit.current_hex):
			continue

		var index: int = cell_to_index(other_unit.current_hex)
		values[index] = 0.5

	return values


func create_reserved_stamp(reserved_hexes: Array[Vector2i]) -> PackedFloat32Array:
	var values: PackedFloat32Array = PackedFloat32Array()
	values.resize(cell_count)
	values.fill(1.0)

	for hex: Vector2i in reserved_hexes:
		if not is_valid_cell(hex):
			continue

		var index: int = cell_to_index(hex)
		values[index] = 0.6

	return values


func stamp_unit_influence(origin_hex: Vector2i) -> void:
	if not is_valid_layer(Layer.UNIT_INFLUENCE):
		return

	var values: PackedFloat32Array = _layers[Layer.UNIT_INFLUENCE]

	for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
			var hex: Vector2i = Vector2i(x, y)
			var distance: int = LOSHelper.get_hex_distance(origin_hex, hex)

			if distance > ORIGIN_INFLUENCE_MAX_DISTANCE:
				continue

			var value: float = ORIGIN_INFLUENCE_START_VALUE
			value -= float(distance) * ORIGIN_INFLUENCE_DISTANCE_LOSS

			if value < 0.0:
				value = 0.0

			var index: int = cell_to_index(hex)
			if index < 0:
				continue

			values[index] = value

	_layers[Layer.UNIT_INFLUENCE] = values


func update_unit_influence_decay(delta: float) -> void:
	unit_influence_decay_timer_s += delta

	if unit_influence_decay_timer_s < ORIGIN_INFLUENCE_DECAY_INTERVAL_S:
		return

	unit_influence_decay_timer_s -= ORIGIN_INFLUENCE_DECAY_INTERVAL_S
	_decay_unit_influence_values()


func get_unit_influence_value(influence_map: InfluenceMap, cell: Vector2i) -> float:
	if not influence_map.is_valid_cell(cell):
		return 0.0

	var index: int = influence_map.get_cell_index(cell)
	if index < 0:
		return 0.0

	var layer: PackedFloat32Array = influence_map._layers[InfluenceMap.Layer.UNIT_INFLUENCE]
	if index >= layer.size():
		return 0.0

	return layer[index]


func get_max_value(values: PackedFloat32Array) -> float:
	return InfluenceMapQueryOps.get_max_value(values)


func get_max_value_index(values: PackedFloat32Array) -> int:
	return InfluenceMapQueryOps.get_max_value_index(values)


func get_best_gradient_neighbor(
	layer_id: int,
	from_cell: Vector2i,
	bias_cell: Vector2i,
	bias_weight: float
) -> Vector2i:
	return InfluenceMapQueryOps.get_best_gradient_neighbor(
		self,
		layer_id,
		from_cell,
		bias_cell,
		bias_weight
	)


func get_largest_gradient_value(gradients: Array[UnitInfluenceGradient]) -> float:
	return InfluenceMapQueryOps.get_largest_gradient_value(gradients)


func get_largest_gradient(gradients: Array[UnitInfluenceGradient]) -> UnitInfluenceGradient:
	return InfluenceMapQueryOps.get_largest_gradient(gradients)


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


func _decay_unit_influence_values() -> void:
	if not is_valid_layer(Layer.UNIT_INFLUENCE):
		return

	var values: PackedFloat32Array = _layers[Layer.UNIT_INFLUENCE]

	for index: int in range(values.size()):
		values[index] -= ORIGIN_INFLUENCE_TIME_LOSS

		if values[index] < 0.0:
			values[index] = 0.0

	_layers[Layer.UNIT_INFLUENCE] = values
	mark_all_dirty()
