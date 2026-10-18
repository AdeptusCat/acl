class_name InfluenceMapQueryOps
extends RefCounted


static func get_max_value(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0

	var best_value: float = values[0]
	var index: int = 1

	while index < values.size():
		var value: float = values[index]
		if value > best_value:
			best_value = value

		index += 1

	return best_value


static func get_max_value_index(values: PackedFloat32Array) -> int:
	if values.is_empty():
		return -1

	var best_index: int = 0
	var best_value: float = values[0]
	var index: int = 1

	while index < values.size():
		var value: float = values[index]
		if value > best_value:
			best_value = value
			best_index = index

		index += 1

	return best_index


static func get_best_gradient_neighbor(
	influence_map: InfluenceMap,
	layer_id: int,
	from_cell: Vector2i,
	bias_cell: Vector2i,
	bias_weight: float
) -> Vector2i:
	var value_here: float = influence_map.get_layer_value(layer_id, from_cell)
	var best_cell: Vector2i = from_cell
	var best_score: float = -INF

	var current_bias_distance: int = LOSHelper.get_hex_distance(from_cell, bias_cell)
	var neighbors: Array[Vector2i] = LOSHelper.get_hex_neighbors(from_cell)

	for neighbor_cell: Vector2i in neighbors:
		if not influence_map.is_valid_cell(neighbor_cell):
			continue

		var neighbor_value: float = influence_map.get_layer_value(layer_id, neighbor_cell)
		var influence_gain: float = neighbor_value - value_here

		var neighbor_bias_distance: int = LOSHelper.get_hex_distance(neighbor_cell, bias_cell)
		var bias_gain: float = float(current_bias_distance - neighbor_bias_distance)

		var score: float = influence_gain
		score += bias_gain * bias_weight

		if score > best_score:
			best_score = score
			best_cell = neighbor_cell

	return best_cell


static func get_largest_gradient_value(gradients: Array[UnitInfluenceGradient]) -> float:
	if gradients.is_empty():
		return 0.0

	var largest_value: float = -INF

	for gradient: UnitInfluenceGradient in gradients:
		if gradient == null:
			continue

		if gradient.influence_gain > largest_value:
			largest_value = gradient.influence_gain

	if largest_value == -INF:
		return 0.0

	return largest_value


static func get_largest_gradient(gradients: Array[UnitInfluenceGradient]) -> UnitInfluenceGradient:
	var best_gradient: UnitInfluenceGradient = null
	var best_value: float = -INF

	for gradient: UnitInfluenceGradient in gradients:
		if gradient == null:
			continue

		if gradient.influence_gain > best_value:
			best_value = gradient.influence_gain
			best_gradient = gradient

	return best_gradient
