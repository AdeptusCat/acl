class_name InfluenceMapLayerOps
extends RefCounted


static func write_stamp_to_array_with_result(
	influence_map: InfluenceMap,
	layer: PackedFloat32Array,
	stamp: InfluenceStamp,
	mode: int,
	zero_outside_stamp: bool = false
) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	result.resize(layer.size())

	if not zero_outside_stamp:
		var copy_index: int = 0
		while copy_index < layer.size():
			result[copy_index] = layer[copy_index]
			copy_index += 1

	var y: int = 0
	while y < stamp.size.y:
		var x: int = 0

		while x < stamp.size.x:
			var stamp_index: int = stamp.get_index(x, y)
			var write_value: float = stamp.values[stamp_index]

			if should_write_stamp_value(write_value, mode):
				var cell: Vector2i = Vector2i(
					stamp.min_cell.x + x,
					stamp.min_cell.y + y
				)

				if influence_map.is_valid_cell(cell):
					var layer_index: int = influence_map.get_cell_index(cell)
					var current_value: float = result[layer_index]

					if zero_outside_stamp:
						current_value = layer[layer_index]

					result[layer_index] = get_write_mode_result_value(
						current_value,
						write_value,
						mode
					)

			x += 1

		y += 1

	return result


static func write_stamp_to_layer(
	influence_map: InfluenceMap,
	layer_id: int,
	stamp: InfluenceStamp,
	mode: int
) -> void:
	if not influence_map.is_valid_layer(layer_id):
		return

	var y: int = 0
	while y < stamp.size.y:
		var x: int = 0

		while x < stamp.size.x:
			var index: int = stamp.get_index(x, y)
			var write_value: float = stamp.values[index]

			if should_write_stamp_value(write_value, mode):
				var cell: Vector2i = Vector2i(
					stamp.min_cell.x + x,
					stamp.min_cell.y + y
				)

				if influence_map.is_valid_cell(cell):
					write_layer_value(influence_map, layer_id, cell, write_value, mode)

			x += 1

		y += 1


static func should_write_stamp_value(write_value: float, mode: int) -> bool:
	if write_value != 0.0:
		return true

	if mode == InfluenceMap.WriteMode.ADD:
		return false

	return true


static func write_layer_value(
	influence_map: InfluenceMap,
	layer_id: int,
	cell: Vector2i,
	value: float,
	mode: int
) -> void:
	if mode == InfluenceMap.WriteMode.SET:
		influence_map.set_layer_value(layer_id, cell, value)
		return

	if mode == InfluenceMap.WriteMode.SUBTRACT:
		influence_map.subtract_layer_value(layer_id, cell, value)
		return

	if mode == InfluenceMap.WriteMode.SUBSTRACT:
		influence_map.subtract_layer_value(layer_id, cell, value)
		return

	if mode == InfluenceMap.WriteMode.ADD:
		influence_map.add_layer_value(layer_id, cell, value)
		return

	if mode == InfluenceMap.WriteMode.MAX:
		influence_map.max_layer_value(layer_id, cell, value)
		return

	if mode == InfluenceMap.WriteMode.MIN:
		influence_map.min_layer_value(layer_id, cell, value)
		return


static func apply_positive_mask_with_result(
	layer: PackedFloat32Array,
	mask_layer: PackedFloat32Array
) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()

	if layer.size() != mask_layer.size():
		return result

	result.resize(layer.size())

	var index: int = 0
	while index < layer.size():
		var mask_value: float = mask_layer[index]

		if mask_value > 0.0:
			result[index] = layer[index]
		else:
			result[index] = 0.0

		index += 1

	return result


static func get_write_mode_result_value(
	current_value: float,
	write_value: float,
	mode: int
) -> float:
	if mode == InfluenceMap.WriteMode.SET:
		return write_value

	if mode == InfluenceMap.WriteMode.ADD:
		return current_value + write_value

	if mode == InfluenceMap.WriteMode.SUBTRACT:
		return current_value - write_value

	if mode == InfluenceMap.WriteMode.SUBSTRACT:
		return current_value - write_value

	if mode == InfluenceMap.WriteMode.MULTIPLY:
		return current_value * write_value

	if mode == InfluenceMap.WriteMode.MAX:
		return maxf(current_value, write_value)

	if mode == InfluenceMap.WriteMode.MIN:
		return minf(current_value, write_value)

	return current_value


static func add_arrays_with_result(values_a: PackedFloat32Array, values_b: PackedFloat32Array) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	var result_size: int = min(values_a.size(), values_b.size())
	result.resize(result_size)

	var index: int = 0
	while index < result_size:
		result[index] = values_a[index] + values_b[index]
		index += 1

	return result


static func multiply_arrays_with_result(values_a: PackedFloat32Array, values_b: PackedFloat32Array) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	var result_size: int = min(values_a.size(), values_b.size())
	result.resize(result_size)

	var index: int = 0
	while index < result_size:
		result[index] = values_a[index] * values_b[index]
		index += 1

	return result


static func multiply_layers(
	influence_map: InfluenceMap,
	layer_a: int,
	layer_b: int,
	target_layer: int
) -> void:
	if not influence_map.is_valid_layer(layer_a):
		return

	if not influence_map.is_valid_layer(layer_b):
		return

	if not influence_map.is_valid_layer(target_layer):
		return

	var values_a: PackedFloat32Array = influence_map._layers[layer_a]
	var values_b: PackedFloat32Array = influence_map._layers[layer_b]
	var target_values: PackedFloat32Array = influence_map._layers[target_layer]

	var index: int = 0
	while index < target_values.size():
		target_values[index] = values_a[index] * values_b[index]
		index += 1

	influence_map._layers[target_layer] = target_values
	influence_map.mark_all_dirty()
