class_name LosInfluenceProjector
extends RefCounted


static func rebuild_los_influence_for_team(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig
) -> void:
	project_actual_friendly_los(influence_map, config)
	project_actual_enemy_los(influence_map, config)
	project_simulated_enemy_los(influence_map, config)


static func clear_los_layers(influence_map: InfluenceMap) -> void:
	influence_map.clear_layer(InfluenceMap.Layer.VISIBILITY, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.FIRE_POWER, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.COVER_VS_ENEMY_FIRE, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.VISIBILITY_HINDRANCE, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.RETURN_FIRE_PENALTY, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.THREAT, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.FORECAST_THREAT, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.ENEMY_VISIBILITY, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.ENEMY_VULNERABILITY, 0.0)
	influence_map.clear_layer(InfluenceMap.Layer.HQ_SUPPORT_NEED, 0.0)


static func project_actual_friendly_los(
	influence_map: InfluenceMap,
	config: InfluenceProjectionConfig
) -> void:
	var units: Array[Unit] = InfluenceUnitQuery.get_config_units(config.unit_team, config.unit_group)
	var los_lookup: Dictionary = LOSHelper.los_lookup

	for unit: Unit in units:
		if not InfluenceUnitQuery.is_valid_living_unit(unit):
			continue

		var observer_hex: Vector2i = unit.current_hex

		if not los_lookup.has(observer_hex):
			continue

		var source: ProjectionSource = ProjectionSource.new(
			unit,
			observer_hex,
			InfluenceUnitQuery.get_unit_firepower(unit),
			InfluenceUnitQuery.get_unit_effectiveness(unit)
		)

		source.weapon_range = InfluenceUnitQuery.get_unit_range(unit)
		project_los_from_source(
			influence_map,
			source,
			true
		)


static func project_simulated_enemy_los(influence_map: InfluenceMap, config: InfluenceProjectionConfig) -> void:
	for source: ProjectionSource in ProjectionSourceBuilder.build_from_contacts(config.contacts, config):
		project_los_from_source(influence_map, source, false)


static func project_actual_enemy_los(influence_map: InfluenceMap, config: InfluenceProjectionConfig) -> void:
	for contact: InfluenceContact in config.contacts:
		var source: ProjectionSource = ProjectionSource.new(contact.unit, contact.hex, contact.firepower * contact.confidence, contact.effectiveness)
		source.weapon_range = contact.weapon_range
		project_los_from_source(influence_map, source, false)


static func project_simulated_enemy_los_from_units(influence_map: InfluenceMap, config: InfluenceProjectionConfig, enemy_units: Array[Unit]) -> void:
	var selected: Array[InfluenceContact] = []
	for contact: InfluenceContact in config.contacts:
		if enemy_units.has(contact.unit):
			selected.append(contact)
	for source: ProjectionSource in ProjectionSourceBuilder.build_from_contacts(selected, config):
		project_los_from_source(influence_map, source, false)


static func project_los_from_source(
	influence_map: InfluenceMap,
	source: ProjectionSource,
	project_as_friendly: bool,
	captured_los: Variant = null
) -> int:
	var los_lookup: Dictionary = LOSHelper.los_lookup
	if captured_los != null:
		los_lookup = captured_los
	var observer_hex: Vector2i = source.observer_hex

	if not los_lookup.has(observer_hex):
		return 0

	var visible_targets: Dictionary = los_lookup[observer_hex]
	var written_target_count: int = 0

	for target_hex: Vector2i in visible_targets.keys():
		if not influence_map.is_valid_cell(target_hex):
			continue

		if LOSHelper.get_hex_distance(observer_hex, target_hex) > source.weapon_range:
			continue
		var los_data: Dictionary = visible_targets[target_hex]
		if source.forecast:
			influence_map.add_layer_value(InfluenceMap.Layer.FORECAST_THREAT, target_hex, calculate_los_fire_threat(source.firepower, source.effectiveness, los_data.get("target_cover", 0.0), los_data.get("hindrance", 0.0), LOSHelper.get_hex_distance(observer_hex, target_hex)))
			written_target_count += 1
			continue

		if project_as_friendly:
			project_friendly_los_record(
				influence_map,
				observer_hex,
				target_hex,
				los_data,
				source.firepower,
				source.effectiveness
			)
		else:
			project_enemy_los_record(
				influence_map,
				observer_hex,
				target_hex,
				los_data,
				source.firepower,
				source.effectiveness
			)

		written_target_count += 1

	return written_target_count

static func project_friendly_los_record(
	influence_map: InfluenceMap,
	observer_hex: Vector2i,
	target_hex: Vector2i,
	los_data: Dictionary,
	unit_firepower: float,
	unit_effectiveness: float
) -> void:
	var target_cover: float = read_los_float(los_data, "target_cover", 0.0)
	var shooter_cover: float = read_los_float(los_data, "shooter_cover", 0.0)
	var hindrance: float = read_los_float(los_data, "hindrance", 0.0)
	var target_concealment: float = read_los_float(los_data, "target_concealment", 0.0)
	var distance: int = LOSHelper.get_hex_distance(observer_hex, target_hex)
	var threat: float = calculate_los_fire_threat(
		unit_firepower,
		unit_effectiveness,
		target_cover,
		hindrance,
		distance
	)

	influence_map.max_layer_value(
		InfluenceMap.Layer.VISIBILITY,
		target_hex,
		1.0
	)

	influence_map.add_layer_value(
		InfluenceMap.Layer.FIRE_POWER,
		target_hex,
		threat
	)

	influence_map.max_layer_value(
		InfluenceMap.Layer.VISIBILITY_HINDRANCE,
		target_hex,
		hindrance
	)

	influence_map.max_layer_value(
		InfluenceMap.Layer.VISIBILITY_HINDRANCE,
		target_hex,
		target_concealment
	)

	influence_map.max_layer_value(
		InfluenceMap.Layer.RETURN_FIRE_PENALTY,
		target_hex,
		shooter_cover
	)


static func project_enemy_los_record(
	influence_map: InfluenceMap,
	observer_hex: Vector2i,
	target_hex: Vector2i,
	los_data: Dictionary,
	unit_firepower: float,
	unit_effectiveness: float
) -> void:
	var target_cover: float = read_los_float(los_data, "target_cover", 0.0)
	var shooter_cover: float = read_los_float(los_data, "shooter_cover", 0.0)
	var hindrance: float = read_los_float(los_data, "hindrance", 0.0)
	var distance: int = LOSHelper.get_hex_distance(observer_hex, target_hex)
	var threat: float = calculate_los_fire_threat(
		unit_firepower,
		unit_effectiveness,
		target_cover,
		hindrance,
		distance
	)

	influence_map.max_layer_value(
		InfluenceMap.Layer.COVER_VS_ENEMY_FIRE,
		target_hex,
		target_cover
	)

	influence_map.add_layer_value(
		InfluenceMap.Layer.THREAT,
		target_hex,
		threat
	)

	influence_map.max_layer_value(
		InfluenceMap.Layer.ENEMY_VISIBILITY,
		target_hex,
		1.0
	)

	influence_map.max_layer_value(
		InfluenceMap.Layer.ENEMY_VULNERABILITY,
		target_hex,
		remap(shooter_cover, 0.0, 5.0, 5.0, 0.0)
	)


static func read_los_float(data: Dictionary, key: String, fallback: float) -> float:
	if not data.has(key):
		return fallback

	var value: Variant = data[key]

	if typeof(value) == TYPE_INT:
		return float(value)

	if typeof(value) == TYPE_FLOAT:
		return value

	return fallback


static func calculate_los_fire_threat(
	enemy_firepower: float,
	enemy_effectiveness: float,
	target_cover: float,
	hindrance: float,
	distance: int
) -> float:
	var threat: float = enemy_firepower * enemy_effectiveness
	var cover_multiplier: float = 1.0 / (1.0 + target_cover * 0.35)
	var hindrance_multiplier: float = 1.0 / (1.0 + hindrance * 0.25)
	var range_multiplier: float = get_range_threat_multiplier(distance)

	threat *= cover_multiplier
	threat *= hindrance_multiplier
	threat *= range_multiplier

	if threat < 0.0:
		threat = 0.0

	return threat


static func get_range_threat_multiplier(distance: int) -> float:
	if distance <= 1:
		return 2.0

	if distance <= 3:
		return 1.3

	if distance <= 6:
		return 1.0

	if distance <= 10:
		return 0.65

	return 0.35


static func create_axis_composite_from_enemy_units(
	source_map: InfluenceMap,
	config: InfluenceProjectionConfig,
	axis_enemy_units: Array[Unit],
	weights: PackedFloat32Array
) -> PackedFloat32Array:
	var axis_map: InfluenceMap = InfluenceMap.new()
	axis_map.configure(source_map.bounds)

	axis_map.configure_composite_weights(
		weights,
		0.0,
		0.0,
		20.0
	)

	axis_map.set_layer_data_copy(
		InfluenceMap.Layer.TERRAIN_COVER,
		source_map.get_layer_data_copy(InfluenceMap.Layer.TERRAIN_COVER)
	)

	axis_map.set_layer_data_copy(
		InfluenceMap.Layer.TERRAIN_MOVE_COST,
		source_map.get_layer_data_copy(InfluenceMap.Layer.TERRAIN_MOVE_COST)
	)

	# Reuse captured friendly layers; an axis diagnostic must not resample live units.
	for layer: int in [InfluenceMap.Layer.VISIBILITY, InfluenceMap.Layer.FIRE_POWER, InfluenceMap.Layer.VISIBILITY_HINDRANCE, InfluenceMap.Layer.RETURN_FIRE_PENALTY]:
		axis_map.set_layer_data_copy(layer, source_map.get_layer_data_copy(layer))
	var selected: InfluenceProjectionConfig = InfluenceProjectionConfig.new()
	selected.objective_hex = config.objective_hex
	selected.has_objective = config.has_objective
	for contact: InfluenceContact in config.contacts:
		if axis_enemy_units.has(contact.unit):
			selected.contacts.append(contact)
	project_actual_enemy_los(axis_map, selected)
	project_simulated_enemy_los(axis_map, selected)
	axis_map.rebuild_all_composite()

	return axis_map.get_composite_data_copy()


static func begin_budgeted_rebuild_for_team(controller: InfluenceMapController, influence_map: InfluenceMap, config: InfluenceProjectionConfig) -> void:
	var job: LosRebuildJob = LosRebuildJob.new()
	job.influence_map = influence_map
	job.defending_team = config.unit_team
	job.los_lookup = controller.pending_snapshot.los
	for unit: Unit in InfluenceUnitQuery.get_config_units(config.unit_team, config.unit_group):
		var source: ProjectionSource = ProjectionSource.new(unit, unit.current_hex, InfluenceUnitQuery.get_unit_firepower(unit), InfluenceUnitQuery.get_unit_effectiveness(unit))
		source.weapon_range = InfluenceUnitQuery.get_unit_range(unit)
		job.sources.append(source)
		job.projection_modes.append(true)
	for contact: InfluenceContact in config.contacts:
		var source: ProjectionSource = ProjectionSource.new(contact.unit, contact.hex, contact.firepower * contact.confidence, contact.effectiveness)
		source.weapon_range = contact.weapon_range
		job.sources.append(source)
		job.projection_modes.append(false)
	for source: ProjectionSource in ProjectionSourceBuilder.build_from_contacts(config.contacts, config):
		job.sources.append(source)
		job.projection_modes.append(false)
	controller.los_rebuild_jobs.append(job)


static func process_budgeted_rebuild(controller: InfluenceMapController, sources_per_frame: int) -> void:
	var processed: int = 0
	while processed < sources_per_frame and not controller.los_rebuild_jobs.is_empty():
		var job: LosRebuildJob = controller.los_rebuild_jobs.pop_front()
		if job.cursor < job.sources.size():
			project_los_from_source(job.influence_map, job.sources[job.cursor], job.projection_modes[job.cursor], job.los_lookup)
			job.cursor += 1
			processed += 1
		if job.cursor < job.sources.size():
			controller.los_rebuild_jobs.append(job)
