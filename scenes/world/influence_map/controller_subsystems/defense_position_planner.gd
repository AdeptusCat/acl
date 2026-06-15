class_name DefensePositionPlanner
extends RefCounted


static func assign_best_positions_for_config(
	controller: InfluenceMapController,
	config: InfluenceProjectionConfig
) -> void:
	var units: Array[Unit] = InfluenceUnitQuery.get_config_units(config.unit_team, config.unit_group)
	var enemy_units: Array[Unit] = InfluenceUnitQuery.get_config_units(config.enemy_team, config.enemy_group)

	if units.is_empty():
		return

	if enemy_units.is_empty():
		return

	var local_reserved_hexes: Array[Vector2i] = []
	var ordered_units: Array[Unit] = get_ordered_living_units(controller, units)

	for unit: Unit in ordered_units:
		var influence_map: InfluenceMap = controller.maps_by_team[unit.team]
		var approach_stamp: InfluenceStamp = create_projected_approach_stamp(
			influence_map,
			config,
			enemy_units
		)

		var reserved_stamp: PackedFloat32Array = influence_map.create_reserved_stamp(local_reserved_hexes)
		var result: PackedFloat32Array = influence_map.write_stamp_to_layer_with_return(
			influence_map._composite,
			approach_stamp,
			InfluenceMap.WriteMode.MULTIPLY,
			true
		)

		result = influence_map.multiply_layers_with_return(result, reserved_stamp)
		var best_index: int = influence_map.get_max_value_index(result)

		if best_index == -1:
			continue

		var best_value: float = result[best_index]
		var best_hex: Vector2i = influence_map.index_to_cell(best_index)
		local_reserved_hexes.append(best_hex)

		var previous_best_value: float = -INF
		if unit.best_index >= 0 and unit.best_index < result.size():
			previous_best_value = result[unit.best_index]

		if best_value * config.move_improvement_ratio > previous_best_value:
			unit.order(Globals.UnitCmd.MOVE, best_hex)
			unit.best_index = best_index

		unit.influence_map = result


static func assign_best_positions_for_threat_axis(
	controller: InfluenceMapController,
	config: InfluenceProjectionConfig,
	axis_units: Array[Unit],
	axis_enemy_units: Array[Unit]
) -> void:
	var units: Array[Unit] = axis_units

	if units.is_empty():
		units = InfluenceUnitQuery.get_config_units(config.unit_team, config.unit_group)

	if units.is_empty():
		return

	if config.threat_axis == null:
		var enemy_units: Array[Unit] = InfluenceUnitQuery.get_config_units(config.enemy_team, config.enemy_group)
		if enemy_units.is_empty():
			return

	var influence_map: InfluenceMap = controller.maps_by_team[units[0].team]
	var composite: PackedFloat32Array = LosInfluenceProjector.create_axis_composite_from_enemy_units(
		influence_map,
		config,
		axis_enemy_units,
		controller.create_default_weights()
	)

	var ordered_units: Array[Unit] = get_ordered_living_units(controller, units)

	for unit: Unit in ordered_units:
		var approach_stamp: InfluenceStamp = create_projected_approach_stamp_for_threat_axis(
			influence_map,
			config
		)

		var reserved_hexes_for_other_units: Array[Vector2i] = get_reserved_hexes_except_unit(
			controller,
			unit
		)

		var reserved_stamp: PackedFloat32Array = influence_map.create_reserved_stamp(
			reserved_hexes_for_other_units
		)

		var result: PackedFloat32Array = influence_map.write_stamp_to_layer_with_return(
			composite,
			approach_stamp,
			InfluenceMap.WriteMode.MULTIPLY,
			true
		)

		result = influence_map.multiply_layers_with_return(result, reserved_stamp)
		result = apply_unit_influence_and_objective_mask(influence_map, result, config.objective_hex)

		var best_index: int = influence_map.get_max_value_index(result)
		if best_index == -1:
			continue

		var best_value: float = result[best_index]
		var best_hex: Vector2i = influence_map.index_to_cell(best_index)
		controller.reserved_hexes[unit] = best_hex

		var previous_best_value: float = -INF
		if unit.best_index >= 0 and unit.best_index < result.size():
			previous_best_value = result[unit.best_index]

		if best_value * config.move_improvement_ratio > previous_best_value:
			unit.order(Globals.UnitCmd.MOVE, best_hex)
			unit.best_index = best_index

		unit.influence_map = result


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
	controller: InfluenceMapController,
	unit: Unit
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var reserved_hexes_duplicate: Dictionary[Unit, Vector2i] = controller.reserved_hexes.duplicate()
	reserved_hexes_duplicate.erase(unit)

	for reserved_hex: Vector2i in reserved_hexes_duplicate.values():
		result.append(reserved_hex)

	return result


static func apply_unit_influence_and_objective_mask(
	influence_map: InfluenceMap,
	result: PackedFloat32Array,
	objective_hex: Vector2i
) -> PackedFloat32Array:
	var objective_stamp: InfluenceStamp = influence_map.create_radius_stamp(
		objective_hex,
		2,
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
		result,
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
