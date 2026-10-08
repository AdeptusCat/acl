class_name PositionFeatureEvaluator
extends RefCounted


static func risk(value: float) -> float:
	return maxf(value, 0.0) / (1.0 + maxf(value, 0.0))


static func evaluate(query: PositionQuery, cell: Vector2i, path: Array[Vector2i]) -> Dictionary:
	if not query.destination_features.has(cell):
		query.destination_features[cell] = _destination_features(query, cell)
	var features: Dictionary = query.destination_features[cell].duplicate()
	var map: InfluenceMap = query.snapshot.maps[query.team]
	var contacts: Array[InfluenceContact] = query.snapshot.get_contacts(query.team)
	if query.profile.mode == PositionProfile.Mode.DEFEND:
		contacts = query.snapshot.get_defensive_contacts(query.team)
	var exposure: float = 0.0
	var travel: float = 0.0
	var peak_exposure: float = 0.0
	var open_ground: float = 0.0
	var open_fire: float = 0.0
	var route_contact_distance: int = 999999
	var exposure_seconds: float = 0.0
	var open_exposure_seconds: float = 0.0
	var route_seconds: float = 0.0
	for index: int in range(1, path.size()):
		var step: Vector2i = path[index]
		var step_risk: float = risk(map.get_layer_value(InfluenceMap.Layer.THREAT, step))
		if query.profile.mode == PositionProfile.Mode.DEFEND:
			if query.route_field != null:
				step_risk = query.route_field.step_data(step)["risk"]
			else:
				step_risk = route_step(query, step)["risk"]
		var step_cover: float = clampf(map.get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, step), 0.0, 1.0)
		open_ground += 1.0 - step_cover
		if step_cover < query.profile.minimum_cover:
			open_fire = maxf(open_fire, step_risk)
		route_contact_distance = mini(route_contact_distance, nearest_contact_distance(contacts, step))
		var seconds: float = crossing_seconds(query, path[index - 1], step)
		route_seconds += seconds
		exposure_seconds += seconds * step_risk
		if step_cover < query.profile.minimum_cover:
			open_exposure_seconds += seconds * step_risk
		exposure += step_risk
		peak_exposure = maxf(peak_exposure, step_risk)
		travel += 1.0 + map.get_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, step)
	if path.size() > 1:
		exposure /= float(path.size() - 1)
		open_ground /= float(path.size() - 1)
	features.merge({"travel": travel, "route_exposure": exposure, "peak_exposure": peak_exposure,
		"open_ground": open_ground, "open_fire": open_fire, "route_contact_distance": route_contact_distance,
		"route_seconds": route_seconds, "exposure_seconds": exposure_seconds, "open_exposure_seconds": open_exposure_seconds})
	if query.defense_area != null:
		features["deadline_slack_seconds"] = features.get("arrival_seconds", INF) - route_seconds - query.profile.establishment_seconds
	return features


static func _destination_features(query: PositionQuery, cell: Vector2i) -> Dictionary:
	var map: InfluenceMap = query.snapshot.maps[query.team]
	var objective_distance: int = LOSHelper.get_hex_distance(cell, query.objective_hex)
	var start_distance: int = LOSHelper.get_hex_distance(query.unit.current_hex, query.objective_hex)
	var incoming: float = risk(map.get_layer_value(InfluenceMap.Layer.THREAT, cell))
	var cover: float = clampf(map.get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell), 0.0, 1.0)
	var contacts: Array[InfluenceContact] = query.snapshot.get_contacts(query.team)
	if query.profile.mode == PositionProfile.Mode.DEFEND:
		contacts = query.snapshot.get_defensive_contacts(query.team)
		incoming = maxf(incoming, _contact_fire_risk(query, contacts, cell, false))
	var support: float = 0.0
	for friendly: Unit in query.snapshot.positions:
		if friendly != query.unit and query.snapshot.teams[friendly] == query.team:
			support += maxf(0.0, 1.0 - float(LOSHelper.get_hex_distance(cell, query.snapshot.positions[friendly])) / 5.0)
	var targets: Array[Vector2i] = query.firing_targets
	if not query.firing_targets_prepared:
		query.firing_targets_prepared = true
		_prepare_firing_targets(query, contacts)
	var firing: float = 0.0
	var visible_count: int = 0
	for target: Vector2i in targets:
		var ability: float = outgoing_utility(query, cell, target)
		if ability > 0.0:
			visible_count += 1
			firing += ability
	if not targets.is_empty():
		firing /= float(targets.size())
	if query.profile.mode != PositionProfile.Mode.DEFEND and query.profile.mode != PositionProfile.Mode.LEGACY_DEFENSE:
		firing = outgoing_utility(query, cell, query.objective_hex)
	var forecast: float = 0.0
	if query.forecast_data.size() == map.cell_count:
		forecast = risk(query.forecast_data[map.cell_to_index(cell)])
	var coverage: float = 0.0
	if cell == query.objective_hex or (query.snapshot.los.get(cell, {}).has(query.objective_hex) and objective_distance <= maxi(InfluenceUnitQuery.get_unit_range(query.unit), query.defense_radius)):
		coverage = maxf(0.0, 1.0 - float(objective_distance) / float(query.defense_radius + 1))
	var legacy: float = map.get_composite_value(cell) * sqrt(maxf(0.0, 1.0 - float(objective_distance) / float(query.defense_radius + 1)))
	var features: Dictionary = {"cover": cover, "incoming": incoming,
		"forecast": forecast,
		"firing": firing, "firing_lanes": visible_count, "objective_coverage": coverage,
		"support": minf(support, 1.0),
		"contact_distance": nearest_contact_distance(contacts, cell),
		"progress": float(start_distance - objective_distance) / float(maxi(start_distance, 1)), "legacy": legacy}
	if query.profile.mode == PositionProfile.Mode.DEFEND:
		if query.defense_area != null:
			features.merge(query.defense_area.features(query, cell))
			# Capture protection is a duty; distance alone adds no firing value.
			features["objective_coverage"] = float(cell == query.objective_hex or (objective_distance <= 1 and coverage > 0.0))
		features.merge(DefensePositionPolicy.evaluate(query, cell))
		features["holding_under_pressure"] = incoming > 0.0 and DefensePositionPolicy.can_hold_under_pressure(query, cell, features)
		features["contact_pressure"] = _contact_pressure(query, contacts, cell, cover)
		features["exposure_budget_seconds"] = query.profile.max_exposure_seconds
		features["open_exposure_budget_seconds"] = query.profile.max_open_exposure_seconds
	return features


static func _prepare_firing_targets(query: PositionQuery, contacts: Array[InfluenceContact]) -> void:
	var targets: Array[Vector2i] = query.firing_targets
	if query.profile.mode == PositionProfile.Mode.DEFEND and query.defense_area != null:
		# The area features evaluate weighted corridors, rather than near-objective samples.
		return
	for contact: InfluenceContact in contacts:
		if query.axis != null and not query.axis.enemy_units.is_empty() and not query.axis.enemy_units.has(contact.unit):
			continue
		if query.profile.mode == PositionProfile.Mode.DEFEND or query.profile.mode == PositionProfile.Mode.LEGACY_DEFENSE:
			var line: Array[Vector2i] = ProjectionSourceBuilder.get_projected_line_hexes(query.objective_hex, contact.hex, 5, 1, 3)
			targets.append_array(line)
		else:
			targets.append(contact.hex)
	if query.axis != null and targets.is_empty():
		targets.append_array(query.axis.approach_hexes)
		targets.append(query.axis.source_hex)
	if targets.is_empty() or query.profile.mode != PositionProfile.Mode.DEFEND:
		targets.append(query.objective_hex)


static func nearest_contact_distance(contacts: Array[InfluenceContact], cell: Vector2i) -> int:
	var distance: int = 999999
	for contact: InfluenceContact in contacts:
		distance = mini(distance, LOSHelper.get_hex_distance(cell, contact.hex))
	return distance


static func _contact_fire_risk(query: PositionQuery, contacts: Array[InfluenceContact], cell: Vector2i, moving: bool) -> float:
	var incoming: float = 0.0
	for contact: InfluenceContact in contacts:
		var distance: int = LOSHelper.get_hex_distance(contact.hex, cell)
		var records: Dictionary = query.snapshot.los.get(contact.hex, {})
		if distance > contact.weapon_range or not records.has(cell):
			continue
		var record: Dictionary = records[cell]
		var cover: float = record.get("target_cover", 0.0)
		if moving:
			cover = 0.0
		# Uncertainty about location does not make the last confirmed firing lane safe.
		incoming += LosInfluenceProjector.calculate_los_fire_threat(contact.firepower,
			contact.effectiveness, cover, record.get("hindrance", 0.0), distance)
	return risk(incoming)


static func route_step(query: PositionQuery, cell: Vector2i) -> Dictionary:
	var map: InfluenceMap = query.snapshot.maps[query.team]
	var contacts: Array[InfluenceContact] = query.snapshot.get_defensive_contacts(query.team)
	var danger: float = maxf(risk(map.get_layer_value(InfluenceMap.Layer.THREAT, cell)), _contact_fire_risk(query, contacts, cell, true))
	if query.forecast_data.size() == map.cell_count:
		danger = maxf(danger, query.profile.forecast_route_weight * risk(query.forecast_data[map.cell_to_index(cell)]))
	var cover: float = clampf(map.get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell), 0.0, 1.0)
	var open_fire: float = 0.0
	if cover < query.profile.minimum_cover:
		open_fire = danger
	return {"risk": danger, "open_fire": open_fire, "cover": cover}


static func crossing_seconds(query: PositionQuery, from: Vector2i, to: Vector2i) -> float:
	var map: InfluenceMap = query.snapshot.maps[query.team]
	var from_position: Vector2 = LOSHelper.ground_layer.map_to_local(from)
	var to_position: Vector2 = LOSHelper.ground_layer.map_to_local(to)
	if query.unit.movement != null and query.unit.movement.is_moving and from == query.unit.current_hex and LOSHelper.ground_layer.local_to_map(query.unit.position) == from:
		from_position = query.unit.position
	var movement_factor: float = 1.0 + map.get_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, to)
	if query.snapshot.los.get(from, {}).get(to, {}).get("wall_cover", 0.0) > 0.0:
		movement_factor += 1.0
	if query.unit.movement == null:
		return INF
	return query.unit.movement.estimate_travel_seconds(from_position, to_position, movement_factor)


static func _contact_pressure(query: PositionQuery, contacts: Array[InfluenceContact], cell: Vector2i, cover: float) -> float:
	var pressure: float = 0.0
	for contact: InfluenceContact in contacts:
		var distance: int = LOSHelper.get_hex_distance(contact.hex, cell)
		if distance <= 2 and query.snapshot.los.get(contact.hex, {}).has(cell):
			pressure = maxf(pressure, (1.0 - float(distance) / 3.0) * (1.0 - 0.5 * cover) * risk(contact.firepower * contact.effectiveness))
	return pressure


static func outgoing_utility(query: PositionQuery, from_hex: Vector2i, target_hex: Vector2i) -> float:
	var records: Dictionary = query.snapshot.los.get(from_hex, {})
	if not records.has(target_hex):
		return 0.0
	var distance: int = LOSHelper.get_hex_distance(from_hex, target_hex)
	var power: float = query.firepower_at_range(query.unit, distance)
	if power <= 0.0:
		return 0.0
	var data: Dictionary = records[target_hex]
	var expected: float = LosInfluenceProjector.calculate_los_fire_threat(power,
		InfluenceUnitQuery.get_unit_effectiveness(query.unit), data.get("target_cover", 0.0), data.get("hindrance", 0.0), distance)
	return risk(expected)
