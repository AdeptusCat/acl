class_name DefensePositionAnalyzer
extends RefCounted


static func analyze_best_positions_for_config(
	controller: InfluenceMapController,
	config: InfluenceProjectionConfig,
	reserved_hexes_by_unit: Dictionary = {}
) -> Array[DefensePositionResult]:
	var units: Array[Unit] = InfluenceUnitQuery.get_config_units(config.unit_team, config.unit_group)
	var enemy_units: Array[Unit] = InfluenceUnitQuery.get_config_units(config.enemy_team, config.enemy_group)

	if units.is_empty():
		var empty_units_result: Array[DefensePositionResult] = []
		return empty_units_result

	if enemy_units.is_empty():
		var empty_enemy_result: Array[DefensePositionResult] = []
		return empty_enemy_result

	return analyze_best_positions_against_enemy_units(
		controller,
		config,
		units,
		enemy_units,
		reserved_hexes_by_unit
	)


static func analyze_best_positions_against_enemy_units(
	controller: InfluenceMapController,
	config: InfluenceProjectionConfig,
	units: Array[Unit],
	enemy_units: Array[Unit],
	reserved_hexes_by_unit: Dictionary
) -> Array[DefensePositionResult]:
	var results: Array[DefensePositionResult] = []

	if units.is_empty():
		return results

	if enemy_units.is_empty():
		return results

	var planned_reserved_hexes: Dictionary = reserved_hexes_by_unit.duplicate()
	var ordered_units: Array[Unit] = get_ordered_living_units(controller, units)

	for unit: Unit in ordered_units:
		var influence_map: InfluenceMap = controller.get_map_for_team(unit.team)
		if influence_map == null:
			continue

		var approach_stamp: InfluenceStamp = create_projected_approach_stamp(
			influence_map,
			config,
			enemy_units
		)

		var reserved_hexes_for_other_units: Array[Vector2i] = get_reserved_hexes_except_unit(
			planned_reserved_hexes,
			unit
		)
		var reserved_stamp: PackedFloat32Array = influence_map.create_reserved_stamp(
			reserved_hexes_for_other_units
		)
		var score_map: PackedFloat32Array = influence_map.write_stamp_to_layer_with_return(
			influence_map._composite,
			approach_stamp,
			InfluenceMap.WriteMode.MULTIPLY,
			true
		)

		score_map = influence_map.multiply_layers_with_return(score_map, reserved_stamp)

		var result: DefensePositionResult = create_result_from_score_map(
			influence_map,
			unit,
			null,
			"defend_objective",
			score_map,
			config.move_improvement_ratio
		)

		if not result.is_valid():
			continue

		planned_reserved_hexes[unit] = result.target_hex
		results.append(result)

	return results


static func analyze_best_positions_for_threat_axis(
	controller: InfluenceMapController,
	config: InfluenceProjectionConfig,
	axis_units: Array[Unit],
	axis_enemy_units: Array[Unit],
	reserved_hexes_by_unit: Dictionary
) -> Array[DefensePositionResult]:
	var results: Array[DefensePositionResult] = []
	var units: Array[Unit] = axis_units

	if units.is_empty():
		units = InfluenceUnitQuery.get_config_units(config.unit_team, config.unit_group)

	if units.is_empty():
		return results

	var enemy_units: Array[Unit] = axis_enemy_units
	if enemy_units.is_empty() and config.threat_axis != null:
		enemy_units = config.threat_axis.enemy_units

	if enemy_units.is_empty():
		enemy_units = InfluenceUnitQuery.get_config_units(config.enemy_team, config.enemy_group)

	if enemy_units.is_empty():
		return results

	var first_unit: Unit = units[0]
	if first_unit == null:
		return results

	var influence_map: InfluenceMap = controller.get_map_for_team(first_unit.team)
	if influence_map == null:
		return results

	var axis_composite: PackedFloat32Array = LosInfluenceProjector.create_axis_composite_from_enemy_units(
		influence_map,
		config,
		enemy_units,
		controller.create_default_weights()
	)

	var planned_reserved_hexes: Dictionary = reserved_hexes_by_unit.duplicate()
	var ordered_units: Array[Unit] = get_ordered_living_units(controller, units)

	for unit: Unit in ordered_units:
		var approach_stamp: InfluenceStamp = create_projected_approach_stamp_for_threat_axis(
			influence_map,
			config
		)

		var reserved_hexes_for_other_units: Array[Vector2i] = get_reserved_hexes_except_unit(
			planned_reserved_hexes,
			unit
		)
		var reserved_stamp: PackedFloat32Array = influence_map.create_reserved_stamp(
			reserved_hexes_for_other_units
		)
		var score_map: PackedFloat32Array = influence_map.write_stamp_to_layer_with_return(
			axis_composite,
			approach_stamp,
			InfluenceMap.WriteMode.MULTIPLY,
			true
		)

		score_map = influence_map.multiply_layers_with_return(score_map, reserved_stamp)
		score_map = apply_unit_influence_and_objective_mask(
			influence_map,
			score_map,
			config.objective_hex
		)

		var result: DefensePositionResult = create_result_from_score_map(
			influence_map,
			unit,
			config.threat_axis,
			"defend_axis",
			score_map,
			config.move_improvement_ratio
		)

		if not result.is_valid():
			continue

		planned_reserved_hexes[unit] = result.target_hex
		results.append(result)

	return results


static func analyze_objective_defense_positions(
	controller: InfluenceMapController,
	config: InfluenceProjectionConfig,
	units: Array[Unit],
	reserved_hexes_by_unit: Dictionary
) -> Array[DefensePositionResult]:
	var results: Array[DefensePositionResult] = []

	if units.is_empty():
		return results

	var planned_reserved_hexes: Dictionary = reserved_hexes_by_unit.duplicate()
	var ordered_units: Array[Unit] = get_ordered_living_units(controller, units)

	for unit: Unit in ordered_units:
		var influence_map: InfluenceMap = controller.get_map_for_team(unit.team)
		if influence_map == null:
			continue

		var objective_stamp: InfluenceStamp = create_objective_anchor_stamp(
			influence_map,
			config.objective_hex
		)
		var reserved_hexes_for_other_units: Array[Vector2i] = get_reserved_hexes_except_unit(
			planned_reserved_hexes,
			unit
		)
		var reserved_stamp: PackedFloat32Array = influence_map.create_reserved_stamp(
			reserved_hexes_for_other_units
		)
		var score_map: PackedFloat32Array = influence_map.write_stamp_to_layer_with_return(
			influence_map._composite,
			objective_stamp,
			InfluenceMap.WriteMode.MULTIPLY,
			true
		)

		score_map = influence_map.multiply_layers_with_return(score_map, reserved_stamp)
		score_map = apply_unit_influence_and_objective_mask(
			influence_map,
			score_map,
			config.objective_hex
		)

		var result: DefensePositionResult = create_result_from_score_map(
			influence_map,
			unit,
			null,
			"defend_objective",
			score_map,
			config.move_improvement_ratio
		)

		if not result.is_valid():
			continue

		planned_reserved_hexes[unit] = result.target_hex
		results.append(result)

	return results


static func create_result_from_score_map(
	influence_map: InfluenceMap,
	unit: Unit,
	axis: ThreatAxis,
	role: String,
	score_map: PackedFloat32Array,
	move_improvement_ratio: float
) -> DefensePositionResult:
	var result: DefensePositionResult = DefensePositionResult.new()
	result.unit = unit
	result.axis = axis
	result.role = role
	result.score_map = score_map

	var best_index: int = influence_map.get_max_value_index(score_map)
	if best_index == -1:
		return result

	result.target_index = best_index
	result.target_hex = influence_map.index_to_cell(best_index)
	result.score = score_map[best_index]
	result.previous_score = -INF

	if unit.best_index >= 0 and unit.best_index < score_map.size():
		result.previous_score = score_map[unit.best_index]

	if result.score * move_improvement_ratio > result.previous_score:
		result.should_move = true
	else:
		result.should_move = false

	return result


static func get_ordered_living_units(
	controller: InfluenceMapController,
	units: Array[Unit]
) -> Array[Unit]:
	var ordered_units: Array[Unit] = []

	for unit: Unit in units:
		if not InfluenceUnitQuery.is_valid_living_unit(unit):
			continue

		if not controller.maps_by_team.has(unit.team):
			continue

		ordered_units.append(unit)

	sort_units_by_squad_priority(ordered_units)
	return ordered_units


static func create_projected_approach_stamp(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig,
	enemy_units: Array[Unit]
) -> InfluenceStamp:
	var sources: Array[ProjectionSource] = ProjectionSourceBuilder.build_from_units(
		enemy_units,
		config.objective_hex,
		config.projected_line_max_cells,
		config.anchor_skip_front,
		config.anchor_count
	)

	return create_combined_source_stamp(influence_map, sources, false, config.objective_hex)


static func create_projected_approach_stamp_for_threat_axis(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig
) -> InfluenceStamp:
	var sources: Array[ProjectionSource] = []

	if config.threat_axis != null:
		sources = ProjectionSourceBuilder.build_from_threat_axis(
			config.threat_axis,
			config.objective_hex,
			config.projected_line_max_cells,
			config.anchor_skip_front,
			config.anchor_count
		)
	else:
		var enemy_units: Array[Unit] = InfluenceUnitQuery.get_config_units(config.enemy_team, config.enemy_group)
		sources = ProjectionSourceBuilder.build_from_units(
			enemy_units,
			config.objective_hex,
			config.projected_line_max_cells,
			config.anchor_skip_front,
			config.anchor_count
		)

	return create_combined_source_stamp(influence_map, sources, true, config.objective_hex)


static func create_objective_anchor_stamp(
	influence_map: InfluenceMap,
	objective_hex: Vector2i
) -> InfluenceStamp:
	return influence_map.create_radius_stamp(
		objective_hex,
		4,
		1.0,
		InfluenceMap.FalloffMode.SQUARE_ROOT
	)


static func create_combined_source_stamp(
	influence_map: InfluenceMap,
	sources: Array[ProjectionSource],
	include_objective: bool,
	objective_hex: Vector2i
) -> InfluenceStamp:
	var combined_stamp: InfluenceStamp = null
	var has_stamp: bool = false

	if include_objective:
		combined_stamp = influence_map.create_radius_stamp(
			objective_hex,
			2,
			1.0,
			InfluenceMap.FalloffMode.SQUARE_ROOT
		)
		has_stamp = true

	for source: ProjectionSource in sources:
		var stamp: InfluenceStamp = influence_map.create_radius_stamp(
			source.observer_hex,
			2,
			1.0,
			InfluenceMap.FalloffMode.SQUARE_ROOT
		)

		if not has_stamp:
			combined_stamp = stamp
			has_stamp = true
		else:
			var max_value: float = INF
			if include_objective:
				max_value = 1.0

			combined_stamp = influence_map.add_stamps_with_return(
				combined_stamp,
				stamp,
				max_value
			)

	if not has_stamp:
		combined_stamp = InfluenceStamp.new(Vector2i.ZERO, Vector2i.ZERO)

	return combined_stamp


static func get_reserved_hexes_except_unit(
	reserved_hexes_by_unit: Dictionary,
	unit: Unit
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var reserved_hexes_duplicate: Dictionary = reserved_hexes_by_unit.duplicate()
	reserved_hexes_duplicate.erase(unit)

	for reserved_hex: Vector2i in reserved_hexes_duplicate.values():
		result.append(reserved_hex)

	return result


static func apply_unit_influence_and_objective_mask(
	influence_map: InfluenceMap,
	score_map: PackedFloat32Array,
	objective_hex: Vector2i
) -> PackedFloat32Array:
	var objective_stamp: InfluenceStamp = influence_map.create_radius_stamp(
		objective_hex,
		3,
		1.0,
		InfluenceMap.FalloffMode.NONE
	)

	var unit_influence_with_objective: PackedFloat32Array = influence_map.write_stamp_to_layer_with_return(
		influence_map._layers[InfluenceMap.Layer.UNIT_INFLUENCE],
		objective_stamp,
		InfluenceMap.WriteMode.MAX,
		true
	)

	return influence_map.apply_positive_mask_layer_with_return(
		score_map,
		unit_influence_with_objective
	)


static func sort_units_by_squad_priority(units: Array[Unit]) -> void:
	var sorted: bool = false

	while not sorted:
		sorted = true
		var index: int = 0

		while index < units.size() - 1:
			var current_unit: Unit = units[index]
			var next_unit: Unit = units[index + 1]

			if not InfluenceUnitQuery.compare_units_by_squad_type_priority(current_unit, next_unit):
				units[index] = next_unit
				units[index + 1] = current_unit
				sorted = false

			index += 1
