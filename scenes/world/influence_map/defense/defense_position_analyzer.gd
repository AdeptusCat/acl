class_name DefensePositionAnalyzer
extends RefCounted

# Compatibility adapters. Allocation/scoring live in the shared query pipeline.
static func analyze_best_positions_for_config(controller: InfluenceMapController, config: InfluenceProjectionConfig, reservations: Dictionary = {}) -> Array[DefensePositionResult]:
	return _analyze(controller, config, InfluenceUnitQuery.get_config_units(config.unit_team, config.unit_group), reservations, "defend_objective")


static func analyze_best_positions_against_enemy_units(controller: InfluenceMapController, config: InfluenceProjectionConfig, units: Array[Unit], _enemies: Array[Unit], reservations: Dictionary) -> Array[DefensePositionResult]:
	return _analyze(controller, config, units, reservations, "defend_objective")


static func analyze_best_positions_for_threat_axis(controller: InfluenceMapController, config: InfluenceProjectionConfig, units: Array[Unit], _enemies: Array[Unit], reservations: Dictionary) -> Array[DefensePositionResult]:
	# An empty explicit assignment is never expanded to a team-wide assignment.
	return _analyze(controller, config, units, reservations, "defend_axis")


static func analyze_objective_defense_positions(controller: InfluenceMapController, config: InfluenceProjectionConfig, units: Array[Unit], reservations: Dictionary) -> Array[DefensePositionResult]:
	return _analyze(controller, config, units, reservations, "defend_objective")


static func _analyze(controller: InfluenceMapController, config: InfluenceProjectionConfig, units: Array[Unit], reservations: Dictionary, role: String) -> Array[DefensePositionResult]:
	var result: Array[DefensePositionResult] = []
	var planned: Dictionary = reservations.duplicate()
	var ordered: Array[Unit] = []
	for unit: Unit in units:
		if InfluenceUnitQuery.is_valid_living_unit(unit) and unit.team == config.unit_team and not ordered.has(unit):
			ordered.append(unit)
	ordered.sort_custom(InfluenceUnitQuery.compare_units_by_squad_type_priority)
	for unit: Unit in ordered:
		var query: PositionQuery = PositionQuery.new()
		query.unit = unit
		query.team = config.unit_team
		query.objective_hex = config.objective_hex
		query.sector_cells = config.sector_cells
		query.fallback_hexes = config.fallback_hexes
		query.defense_radius = config.defense_radius
		query.geography = config.geography
		query.profile = config.profile
		query.axis = config.threat_axis
		query.reservations = planned
		if config.accepted_positions.has(unit):
			query.has_accepted_target = true
			query.accepted_target = config.accepted_positions[unit]["hex"]
			query.accepted_context = config.accepted_positions[unit]["context"]
		var advice: PositionResult = controller.query_positions(query)
		var adapted: DefensePositionResult = adapt_result(advice, config.threat_axis, role)
		result.append(adapted)
		if adapted.is_valid():
			planned[unit] = adapted.target_hex
	return result


static func adapt_result(advice: PositionResult, axis: ThreatAxis, role: String) -> DefensePositionResult:
	var result: DefensePositionResult = DefensePositionResult.new()
	for property: String in ["unit", "status", "target_hex", "target_index", "proposed_hex", "score", "previous_score", "should_move", "score_map", "eligibility", "rejections", "features", "alternatives", "path", "snapshot_version", "context", "profile_mode", "objective_hex", "reason"]:
		result.set(property, advice.get(property))
	result.axis = axis
	result.role = role
	return result


static func create_result_from_score_map(map: InfluenceMap, unit: Unit, axis: ThreatAxis, role: String, scores: PackedFloat32Array, improvement_ratio: float) -> DefensePositionResult:
	# Legacy diagnostic callers lack an eligibility mask: require positive playable cells.
	var result: DefensePositionResult = DefensePositionResult.new()
	result.unit = unit
	result.axis = axis
	result.role = role
	result.status = PositionResult.Status.NO_CANDIDATE
	result.score_map = scores
	if not InfluenceUnitQuery.is_valid_living_unit(unit) or scores.size() != map.cell_count:
		return result
	var best: int = -1
	for index: int in range(scores.size()):
		if scores[index] > 0.0 and map.is_playable_cell(map.index_to_cell(index)) and (best < 0 or scores[index] > scores[best]):
			best = index
	if best < 0:
		return result
	var current: int = map.cell_to_index(unit.current_hex)
	result.previous_score = -INF
	if map.is_playable_cell(unit.current_hex):
		result.previous_score = scores[current]
	if result.previous_score > 0.0 and scores[best] * improvement_ratio <= result.previous_score:
		best = current
		result.status = PositionResult.Status.RETAINED
	else:
		result.status = PositionResult.Status.ACCEPTED
	result.target_index = best
	result.target_hex = map.index_to_cell(best)
	result.score = scores[best]
	result.should_move = result.target_hex != unit.current_hex
	return result


static func create_projected_approach_stamp(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig,
	enemy_units: Array[Unit]
) -> InfluenceStamp:
	var selected: Array[InfluenceContact] = []
	for contact: InfluenceContact in config.contacts:
		if enemy_units.has(contact.unit):
			selected.append(contact)
	var sources: Array[ProjectionSource] = []
	for contact: InfluenceContact in selected:
		for cell: Vector2i in ProjectionSourceBuilder.get_projected_line_hexes(config.objective_hex, contact.hex, config.projected_line_max_cells, config.anchor_skip_front, config.anchor_count):
			sources.append(ProjectionSource.new(contact.unit, cell, contact.firepower * contact.confidence, contact.effectiveness))

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
		push_error("no threat axis")
		#var enemy_units: Array[Unit] = InfluenceUnitQuery.get_config_units(config.enemy_team, config.enemy_group)
		#sources = ProjectionSourceBuilder.build_from_units(
			#enemy_units,
			#config.objective_hex,
			#config.projected_line_max_cells,
			#config.anchor_skip_front,
			#config.anchor_count
		#)
	
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
		false
	)

	return influence_map.apply_positive_mask_layer_with_return(
		score_map,
		unit_influence_with_objective
	)
