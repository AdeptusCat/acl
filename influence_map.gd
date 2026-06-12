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
	SET,
	ADD,
	SUBSTRACT,
	MAX,
	MIN,
	MULTIPLY
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
var origin_influence_decay_timer_s: float = 0.0

const DEFAULT_COMPOSITE_MIN: float = 0.05
const DEFAULT_COMPOSITE_MAX: float = 20.0

const UNIT_INFLUENCE_RADIUS: int = 5
const UNIT_INFLUENCE_VALUE: float = 5.0

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


const UNIT_INFLUENCE_CENTER_PULL_WEIGHT: float = 0.25


class UnitInfluenceGradient:
	var unit: Unit = null
	var from_hex: Vector2i = Vector2i.ZERO
	var next_hex: Vector2i = Vector2i.ZERO
	var value_here: float = 0.0
	var value_next: float = 0.0
	var influence_gain: float = 0.0

	func _init(
		p_unit: Unit,
		p_from_hex: Vector2i,
		p_next_hex: Vector2i,
		p_value_here: float,
		p_value_next: float
	) -> void:
		unit = p_unit
		from_hex = p_from_hex
		next_hex = p_next_hex
		value_here = p_value_here
		value_next = p_value_next
		influence_gain = value_next - value_here


class InfluenceStamp extends RefCounted:
	var values: PackedFloat32Array = PackedFloat32Array()
	var min_cell: Vector2i = Vector2i.ZERO
	var size: Vector2i = Vector2i.ZERO

	func _init(p_min_cell: Vector2i, p_size: Vector2i) -> void:
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
	
	var index: int = cell_to_index(cell)
	var data: PackedFloat32Array = _layers[layer_id]
	data[index] += value
	_layers[layer_id] = data

	_mark_dirty_index(index)


func substract_layer_value(layer_id: int, cell: Vector2i, value: float) -> void:
	if not is_valid_layer(layer_id):
		return

	if not is_valid_cell(cell):
		return
	
	var index: int = cell_to_index(cell)
	var data: PackedFloat32Array = _layers[layer_id]
	data[index] -= value
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


func write_stamp_to_layer_with_return(
	layer: PackedFloat32Array,
	stamp: InfluenceStamp,
	mode: int,
	zero_outside_stamp: bool = false
) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	result.resize(layer.size())

	if not zero_outside_stamp:
		var i: int = 0
		while i < layer.size():
			result[i] = layer[i]
			i += 1

	var y: int = 0
	while y < stamp.size.y:
		var x: int = 0

		while x < stamp.size.x:
			var stamp_index: int = stamp.get_index(x, y)
			var write_value: float = stamp.values[stamp_index]

			if _should_write_stamp_value(write_value, mode):
				var cell: Vector2i = Vector2i(
					stamp.min_cell.x + x,
					stamp.min_cell.y + y
				)

				if is_valid_cell(cell):
					var layer_index: int = get_cell_index(cell)
					var current_value: float = 0.0

					if zero_outside_stamp:
						current_value = layer[layer_index]
					else:
						current_value = result[layer_index]

					result[layer_index] = _get_write_mode_result_value(
						current_value,
						write_value,
						mode
					)

			x += 1

		y += 1

	return result


func get_cell_index(cell: Vector2i) -> int:
	return cell_to_index(cell)


func write_stamp_to_layer(
	layer_id: int,
	stamp: InfluenceStamp,
	mode: int
) -> void:
	if not is_valid_layer(layer_id):
		return

	var y: int = 0
	while y < stamp.size.y:
		var x: int = 0

		while x < stamp.size.x:
			var index: int = stamp.get_index(x, y)
			var write_value: float = stamp.values[index]

			if _should_write_stamp_value(write_value, mode):
				var cell: Vector2i = Vector2i(
					stamp.min_cell.x + x,
					stamp.min_cell.y + y
				)

				if is_valid_cell(cell):
					_write_layer_value(layer_id, cell, write_value, mode)

			x += 1

		y += 1


func _should_write_stamp_value(write_value: float, mode: int) -> bool:
	if write_value != 0.0:
		return true

	if mode == InfluenceMap.WriteMode.ADD:
		return false

	return true


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
	
	#var stamp_size: int = radius * 2 + 1
#
	#var min_x: int = center.x - radius
	#var max_x: int = center.x + radius
	#var min_y: int = center.y - radius
	#var max_y: int = center.y + radius
#
	#var y: int = min_y
	#while y <= max_y:
		#var x: int = min_x
#
		#while x <= max_x:
			#var cell: Vector2i = Vector2i(x, y)
#
			#if is_valid_cell(cell):
				#var local_x: int = x - min_x
				#var local_y: int = y - min_y
				#var stamp_index: int = local_y * stamp_size + local_x
				#var write_value: float = stamp[stamp_index]
#
				#if _should_write_stamp_value(write_value, mode):
					#_write_layer_value(layer_id, cell, write_value, mode)
#
			#x += 1
#
		#y += 1


func create_radius_stamp(
	center: Vector2i,
	radius: int,
	value: float,
	falloff_mode: int
) -> InfluenceStamp:
	var stamp_size: int = radius * 2 + 1
	var min_cell: Vector2i = Vector2i(center.x - radius, center.y - radius)
	var stamp: InfluenceStamp = InfluenceStamp.new(
		min_cell,
		Vector2i(stamp_size, stamp_size)
	)

	var y: int = 0
	while y < stamp.size.y:
		var x: int = 0

		while x < stamp.size.x:
			var cell: Vector2i = Vector2i(
				stamp.min_cell.x + x,
				stamp.min_cell.y + y
			)
			
			if x == 7 and y == 8:
				pass
			if cell == Vector2i(7,8):
				pass
			var distance: int = LOSHelper.get_hex_distance(center, cell)
			
			if distance <= radius:
				var index: int = stamp.get_index(x, y)

				stamp.values[index] = _get_radius_falloff_value(
					value,
					distance,
					radius,
					falloff_mode
				)

			x += 1

		y += 1

	return stamp


#func create_radius_stamp(
	#center: Vector2i,
	#radius: int,
	#value: float,
	#falloff_mode: int
#) -> PackedFloat32Array:
	#var stamp_size: int = radius * 2 + 1
	#var stamp: PackedFloat32Array = PackedFloat32Array()
	#stamp.resize(stamp_size * stamp_size)
#
	#var min_x: int = center.x - radius
	#var max_x: int = center.x + radius
	#var min_y: int = center.y - radius
	#var max_y: int = center.y + radius
#
	#var y: int = min_y
	#while y <= max_y:
		#var x: int = min_x
#
		#while x <= max_x:
			#var cell: Vector2i = Vector2i(x, y)
			#var distance: int = _hex_distance(center, cell)
#
			#if distance <= radius:
				#var local_x: int = x - min_x
				#var local_y: int = y - min_y
				#var stamp_index: int = local_y * stamp_size + local_x
#
				#stamp[stamp_index] = _get_radius_falloff_value(
					#value,
					#distance,
					#radius,
					#falloff_mode
				#)
#
			#x += 1
#
		#y += 1
#
	#return stamp



#func stamp_radius(
	#layer_id: int,
	#center: Vector2i,
	#radius: int,
	#value: float,
	#mode: int,
	#falloff_mode: int
#) -> void:
	#if not is_valid_layer(layer_id):
		#return
#
	#var min_x: int = center.x - radius
	#var max_x: int = center.x + radius
	#var min_y: int = center.y - radius
	#var max_y: int = center.y + radius
#
	#var y: int = min_y
	#while y <= max_y:
		#var x: int = min_x
#
		#while x <= max_x:
			#var cell: Vector2i = Vector2i(x, y)
#
			#if is_valid_cell(cell):
				#var distance: int = _hex_distance(center, cell)
#
				#if distance <= radius:
					#var write_value: float = _get_radius_falloff_value(
						#value,
						#distance,
						#radius,
						#falloff_mode
					#)
#
					#_write_layer_value(layer_id, cell, write_value, mode)
#
			#x += 1
#
		#y += 1


func _get_radius_falloff_value(
	value: float,
	distance: int,
	radius: int,
	falloff_mode: int
) -> float:
	if radius <= 0:
		return value

	if falloff_mode == FalloffMode.NONE:
		return value

	var distance_ratio: float = float(distance) / float(radius + 1)
	var falloff_factor: float = 1.0

	if falloff_mode == FalloffMode.LINEAR:
		falloff_factor = 1.0 - distance_ratio

	elif falloff_mode == FalloffMode.SQUARE_ROOT:
		falloff_factor = sqrt(1.0 - distance_ratio)

	elif falloff_mode == FalloffMode.EXPONENTIAL:
		falloff_factor = exp(-4.0 * distance_ratio)

	else:
		falloff_factor = 1.0

	falloff_factor = clampf(falloff_factor, 0.0, 1.0)

	return value * falloff_factor


#func stamp_radius(
	#layer_id: int,
	#center: Vector2i,
	#radius: int,
	#value: float,
	#mode: int,
	#falloff: bool
#) -> void:
	#if not is_valid_layer(layer_id):
		#return
#
	#var min_x: int = center.x - radius
	#var max_x: int = center.x + radius
	#var min_y: int = center.y - radius
	#var max_y: int = center.y + radius
#
	#var y: int = min_y
	#while y <= max_y:
		#var x: int = min_x
#
		#while x <= max_x:
			#var cell: Vector2i = Vector2i(x, y)
#
			#if is_valid_cell(cell):
				#var distance: int = _hex_distance(center, cell)
#
				#if distance <= radius:
					#var write_value: float = value
#
					#if falloff:
						#var falloff_factor: float = 1.0 - float(distance) / float(radius + 1)
						#write_value = value * falloff_factor
#
					#_write_layer_value(layer_id, cell, write_value, mode)
#
			#x += 1
#
		#y += 1


func copy_layer_to(layer_id: int, target: PackedFloat32Array) -> PackedFloat32Array:
	if not is_valid_layer(layer_id):
		return target

	target = _layers[layer_id].duplicate()
	return target


func _write_layer_value(layer_id: int, cell: Vector2i, value: float, mode: int) -> void:
	if mode == WriteMode.SET:
		set_layer_value(layer_id, cell, value)
		return
	
	if mode == WriteMode.SUBSTRACT:
		substract_layer_value(layer_id, cell, value)
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


func _get_write_mode_result_value(
	current_value: float,
	write_value: float,
	mode: int
) -> float:
	if mode == WriteMode.SET:
		return write_value

	if mode == WriteMode.ADD:
		return current_value + write_value

	if mode == WriteMode.MULTIPLY:
		return current_value * write_value

	if mode == WriteMode.MAX:
		return maxf(current_value, write_value)

	if mode == WriteMode.MIN:
		return minf(current_value, write_value)

	return current_value


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


func add_stamps_with_return(stamp_a: InfluenceStamp, stamp_b: InfluenceStamp, max_value: float = INF) -> InfluenceStamp:
	var min_x: int = min(stamp_a.min_cell.x, stamp_b.min_cell.x)
	var min_y: int = min(stamp_a.min_cell.y, stamp_b.min_cell.y)

	var max_x: int = max(
		stamp_a.min_cell.x + stamp_a.size.x - 1,
		stamp_b.min_cell.x + stamp_b.size.x - 1
	)

	var max_y: int = max(
		stamp_a.min_cell.y + stamp_a.size.y - 1,
		stamp_b.min_cell.y + stamp_b.size.y - 1
	)

	var combined_size: Vector2i = Vector2i(
		max_x - min_x + 1,
		max_y - min_y + 1
	)

	var combined_stamp: InfluenceStamp = InfluenceStamp.new(
		Vector2i(min_x, min_y),
		combined_size
	)

	_add_stamp_into_stamp(combined_stamp, stamp_a)
	_add_stamp_into_stamp(combined_stamp, stamp_b)
	
	var y: int = 0
	while y < combined_stamp.size.y:
		var x: int = 0

		while x < combined_stamp.size.x:
			var source_index: int = combined_stamp.get_index(x, y)
			var source_value: float = combined_stamp.values[source_index]

			if source_value != 0.0:
				var cell: Vector2i = Vector2i(
					combined_stamp.min_cell.x + x,
					combined_stamp.min_cell.y + y
				)
				
				var min_value: float = min(source_value, max_value)
				combined_stamp.values[source_index] = min_value
			x += 1

		y += 1
	return combined_stamp


func _add_stamp_into_stamp(target_stamp: InfluenceStamp, source_stamp: InfluenceStamp) -> void:
	var y: int = 0
	while y < source_stamp.size.y:
		var x: int = 0

		while x < source_stamp.size.x:
			var source_index: int = source_stamp.get_index(x, y)
			var source_value: float = source_stamp.values[source_index]

			if source_value != 0.0:
				var cell: Vector2i = Vector2i(
					source_stamp.min_cell.x + x,
					source_stamp.min_cell.y + y
				)
				
				target_stamp.add_value_at_cell(cell, source_value)

			x += 1

		y += 1


func add_layers_with_return(values_a: PackedFloat32Array, values_b: PackedFloat32Array) -> PackedFloat32Array:
	var target_values: PackedFloat32Array = PackedFloat32Array()
	target_values.resize(cell_count)

	for i in range(target_values.size()):
		target_values[i] = values_a[i] + values_b[i]

	return target_values


func multiply_layers_with_return(values_a: PackedFloat32Array, values_b: PackedFloat32Array) -> PackedFloat32Array:
	var target_values: PackedFloat32Array = PackedFloat32Array()
	target_values.resize(cell_count)

	for i in range(target_values.size()):
		target_values[i] = values_a[i] * values_b[i]

	return target_values


func multiply_layers(layer_a: int, layer_b: int, target_layer: int) -> void:
	if layer_a < 0:
		return
	if layer_a >= Layer.COUNT:
		return

	if layer_b < 0:
		return
	if layer_b >= Layer.COUNT:
		return

	if target_layer < 0:
		return
	if target_layer >= Layer.COUNT:
		return

	var values_a: PackedFloat32Array = _layers[layer_a]
	var values_b: PackedFloat32Array = _layers[layer_b]
	var target_values: PackedFloat32Array = _layers[target_layer]

	for i in range(target_values.size()):
		target_values[i] = values_a[i] * values_b[i]

	_layers[target_layer] = target_values


func create_origin_stamp(origin_hex: Vector2i) -> PackedFloat32Array:
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

	return values


func create_unit_stamp(unit: Unit) -> PackedFloat32Array:
	var values: PackedFloat32Array = PackedFloat32Array()
	values.resize(cell_count)
	values.fill(1.0)
	for _unit in Globals.get_units_for_team(unit.team):
		if _unit == unit:
			continue
		var index: int = cell_to_index(_unit.current_hex)
		values[index] = 0.5
	return values


func create_reserved_stamp(reserved_hexes: Array[Vector2i]) -> PackedFloat32Array:
	var values: PackedFloat32Array = PackedFloat32Array()
	values.resize(cell_count)
	values.fill(1.0)
	for hex in reserved_hexes:
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
	origin_influence_decay_timer_s += delta

	if origin_influence_decay_timer_s < ORIGIN_INFLUENCE_DECAY_INTERVAL_S:
		return

	origin_influence_decay_timer_s -= ORIGIN_INFLUENCE_DECAY_INTERVAL_S

	_decay_unit_influence_values()


func _decay_unit_influence_values() -> void:
	if not is_valid_layer(Layer.UNIT_INFLUENCE):
		return

	var values: PackedFloat32Array = _layers[Layer.UNIT_INFLUENCE]

	for i in range(values.size()):
		values[i] -= ORIGIN_INFLUENCE_TIME_LOSS

		if values[i] < 0.0:
			values[i] = 0.0

	_layers[Layer.UNIT_INFLUENCE] = values


func get_max_value(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0

	var max_value: float = values[0]

	var i: int = 1
	while i < values.size():
		var value: float = values[i]
		if value > max_value:
			max_value = value

		i += 1

	return max_value


func get_max_value_index(values: PackedFloat32Array) -> int:
	if values.is_empty():
		return -1

	var best_index: int = 0
	var best_value: float = values[0]

	var i: int = 1
	while i < values.size():
		var value: float = values[i]
		if value > best_value:
			best_value = value
			best_index = i

		i += 1

	return best_index


func get_best_gradient_neighbor(
	layer_id: int,
	from_cell: Vector2i,
	bias_cell: Vector2i,
	bias_weight: float
) -> Vector2i:
	var value_here: float = get_layer_value(layer_id, from_cell)
	var best_cell: Vector2i = from_cell
	var best_score: float = -INF

	var current_bias_distance: int = LOSHelper.get_hex_distance(from_cell, bias_cell)
	var neighbors: Array[Vector2i] = LOSHelper.get_hex_neighbors(from_cell)

	for neighbor_cell: Vector2i in neighbors:
		if not is_valid_cell(neighbor_cell):
			continue

		var neighbor_value: float = get_layer_value(layer_id, neighbor_cell)
		var influence_gain: float = neighbor_value - value_here

		var neighbor_bias_distance: int = LOSHelper.get_hex_distance(neighbor_cell, bias_cell)
		var bias_gain: float = float(current_bias_distance - neighbor_bias_distance)

		var score: float = influence_gain
		score += bias_gain * bias_weight

		if score > best_score:
			best_score = score
			best_cell = neighbor_cell

	return best_cell


func get_largest_gradient_value(
	gradients: Array[UnitInfluenceGradient]
) -> float:
	if gradients.is_empty():
		return 0.0

	var largest_value: float = -INF

	for gradient: UnitInfluenceGradient in gradients:
		if gradient.influence_gain > largest_value:
			largest_value = gradient.influence_gain

	if largest_value == -INF:
		return 0.0

	return largest_value


func get_largest_gradient(
	gradients: Array[UnitInfluenceGradient]
) -> UnitInfluenceGradient:
	var best_gradient: UnitInfluenceGradient = null
	var best_value: float = -INF

	for gradient: UnitInfluenceGradient in gradients:
		if gradient == null:
			continue

		if gradient.influence_gain > best_value:
			best_value = gradient.influence_gain
			best_gradient = gradient

	return best_gradient


func stamp_to_full_map_array(
	stamp: InfluenceStamp,
	outside_value: float = 0.0
) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	result.resize(cell_count)
	result.fill(outside_value)

	var y: int = 0
	while y < stamp.size.y:
		var x: int = 0

		while x < stamp.size.x:
			var stamp_index: int = stamp.get_index(x, y)
			var cell: Vector2i = Vector2i(
				stamp.min_cell.x + x,
				stamp.min_cell.y + y
			)

			if is_valid_cell(cell):
				var map_index: int = get_cell_index(cell)
				result[map_index] = stamp.values[stamp_index]

			x += 1

		y += 1

	return result
