extends Resource
class_name HqSupportNeedLayer

static func build_squad_support_need_layer(
	influence_map: InfluenceMap,
	squads: Array[Unit]
) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	result.resize(influence_map.cell_count)

	var i: int = 0
	while i < result.size():
		result[i] = 0.0
		i += 1

	for squad: Unit in squads:
		if squad == null:
			continue

		if squad.is_queued_for_deletion():
			continue

		var squad_hex: Vector2i = squad.current_hex
		var need: float = get_squad_support_need(squad)

		if need <= 0.0:
			continue

		_write_squad_support_need(
			influence_map,
			result,
			squad_hex,
			need
		)

	return result


static func _write_squad_support_need(
	influence_map: InfluenceMap,
	layer: PackedFloat32Array,
	squad_hex: Vector2i,
	need: float
) -> void:
	var max_radius: int = 5
	var distance: int = 1

	while distance <= max_radius:
		var ring_value: float = get_support_ring_value(distance)

		if ring_value > 0.0:
			var cells: Array[Vector2i] = LOSHelper.get_hex_ring(
				squad_hex,
				distance
			)

			for cell: Vector2i in cells:
				if not influence_map.is_valid_cell(cell):
					continue

				var index: int = influence_map.get_cell_index(cell)
				layer[index] += ring_value * need

		distance += 1


#static func get_support_ring_value(distance: int) -> float:
	#if distance <= 0:
		#return 1.0
#
	#if distance == 1:
		#return 1.0
#
	#if distance == 2:
		#return 1.0
#
	#if distance == 3:
		#return 1.0
#
	#if distance == 4:
		#return 1.0
#
	#if distance == 5:
		#return 1.0
#
	#if distance == 6:
		#return 1.0
#
	#return 0.0


static func get_support_ring_value(distance: int) -> float:
	if distance <= 0:
		return 0.25

	if distance == 1:
		return 1.0

	if distance == 2:
		return 0.9

	if distance == 3:
		return 0.8

	if distance == 4:
		return 0.5

	if distance == 5:
		return 0.25

	return 0.0


static func get_squad_support_need(squad: Unit) -> float:
	var need: float = 0.0

	if squad.stress_system.state == Unit.MoraleState.NORMAL:
		need = 0.1
	elif squad.stress_system.state == Unit.MoraleState.CAUTIOUS:
		need = 0.35
	elif squad.stress_system.state == Unit.MoraleState.PINNED:
		need = 1.0
	elif squad.stress_system.state == Unit.MoraleState.PANIC:
		need = 1.25
	elif squad.stress_system.state == Unit.MoraleState.COMBAT_INEFFECTIVE:
		need = 1.5
	else:
		need = 0.0

	var stress_need: float = squad.stress_system.S_eff / 100.0
	need += stress_need * 0.5

	if squad.members_alive < squad.original_size:
		var casualties_taken: int = squad.original_size - squad.members_alive
		var casualty_ratio: float = float(casualties_taken) / float(squad.original_size)
		need += casualty_ratio * 0.5

	if need > 1.5:
		need = 1.5

	return need
