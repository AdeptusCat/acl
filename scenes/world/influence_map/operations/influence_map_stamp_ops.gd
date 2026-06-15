class_name InfluenceMapStampOps
extends RefCounted


static func create_radius_stamp(
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

			var distance: int = LOSHelper.get_hex_distance(center, cell)

			if distance <= radius:
				var index: int = stamp.get_index(x, y)
				stamp.values[index] = get_radius_falloff_value(
					value,
					distance,
					radius,
					falloff_mode
				)

			x += 1

		y += 1

	return stamp


static func get_radius_falloff_value(
	value: float,
	distance: int,
	radius: int,
	falloff_mode: int
) -> float:
	if radius <= 0:
		return value

	if falloff_mode == InfluenceMap.FalloffMode.NONE:
		return value

	var distance_ratio: float = float(distance) / float(radius + 1)
	var falloff_factor: float = 1.0

	if falloff_mode == InfluenceMap.FalloffMode.LINEAR:
		falloff_factor = 1.0 - distance_ratio
	elif falloff_mode == InfluenceMap.FalloffMode.SQUARE_ROOT:
		falloff_factor = sqrt(1.0 - distance_ratio)
	elif falloff_mode == InfluenceMap.FalloffMode.EXPONENTIAL:
		falloff_factor = exp(-4.0 * distance_ratio)
	else:
		falloff_factor = 1.0

	falloff_factor = clampf(falloff_factor, 0.0, 1.0)
	return value * falloff_factor


static func add_stamps_with_result(
	stamp_a: InfluenceStamp,
	stamp_b: InfluenceStamp,
	max_value: float = INF
) -> InfluenceStamp:
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

	add_stamp_into_stamp(combined_stamp, stamp_a)
	add_stamp_into_stamp(combined_stamp, stamp_b)
	clamp_stamp_values(combined_stamp, max_value)

	return combined_stamp


static func add_stamp_into_stamp(target_stamp: InfluenceStamp, source_stamp: InfluenceStamp) -> void:
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


static func clamp_stamp_values(stamp: InfluenceStamp, max_value: float) -> void:
	var index: int = 0
	while index < stamp.values.size():
		var source_value: float = stamp.values[index]
		if source_value != 0.0:
			stamp.values[index] = min(source_value, max_value)

		index += 1


static func stamp_to_full_map_array(
	influence_map: InfluenceMap,
	stamp: InfluenceStamp,
	outside_value: float = 0.0
) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	result.resize(influence_map.cell_count)
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

			if influence_map.is_valid_cell(cell):
				var map_index: int = influence_map.get_cell_index(cell)
				result[map_index] = stamp.values[stamp_index]

			x += 1

		y += 1

	return result
