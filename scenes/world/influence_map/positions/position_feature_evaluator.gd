class_name PositionFeatureEvaluator
extends RefCounted


static func risk(value: float) -> float:
	return maxf(value, 0.0) / (1.0 + maxf(value, 0.0))


static func evaluate(query: PositionQuery, cell: Vector2i, path: Array[Vector2i]) -> Dictionary:
	var map: InfluenceMap = query.snapshot.maps[query.team]
	var origin: Vector2i = query.unit.current_hex
	var objective_distance: int = LOSHelper.get_hex_distance(cell, query.objective_hex)
	var start_distance: int = LOSHelper.get_hex_distance(origin, query.objective_hex)
	var incoming: float = risk(map.get_layer_value(InfluenceMap.Layer.THREAT, cell))
	var cover: float = clampf(map.get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell), 0.0, 1.0)
	var contacts: Array[InfluenceContact] = query.snapshot.get_contacts(query.team)
	if query.profile.mode == PositionProfile.Mode.DEFEND:
		contacts = query.snapshot.get_defensive_contacts(query.team)
		incoming = maxf(incoming, _contact_fire_risk(query, contacts, cell, false))
	var exposure: float = 0.0
	var travel: float = 0.0
	var peak_exposure: float = 0.0
	var open_ground: float = 0.0
	var open_fire: float = 0.0
	var route_contact_distance: int = 999999
	for index: int in range(1, path.size()):
		var step: Vector2i = path[index]
		var step_risk: float = risk(map.get_layer_value(InfluenceMap.Layer.THREAT, step))
		if query.profile.mode == PositionProfile.Mode.DEFEND:
			# A moving squad cannot claim stationary cover while crossing a hex.
			step_risk = maxf(step_risk, _contact_fire_risk(query, contacts, step, true))
			if query.forecast_data.size() == map.cell_count:
				step_risk = maxf(step_risk, risk(query.forecast_data[map.cell_to_index(step)]))
		var step_cover: float = clampf(map.get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, step), 0.0, 1.0)
		open_ground += 1.0 - step_cover
		if step_cover < query.profile.minimum_cover:
			open_fire = maxf(open_fire, step_risk)
		route_contact_distance = mini(route_contact_distance, _nearest_contact_distance(contacts, step))
		exposure += step_risk
		peak_exposure = maxf(peak_exposure, step_risk)
		travel += 1.0 + map.get_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, step)
	if path.size() > 1:
		exposure /= float(path.size() - 1)
		open_ground /= float(path.size() - 1)
	var support: float = 0.0
	for friendly: Unit in query.snapshot.positions:
		if friendly != query.unit and query.snapshot.teams[friendly] == query.team:
			support += maxf(0.0, 1.0 - float(LOSHelper.get_hex_distance(cell, query.snapshot.positions[friendly])) / 5.0)
	var targets: Array[Vector2i] = []
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
	return {"cover": cover, "incoming": incoming,
		"forecast": forecast,
		"firing": firing, "firing_lanes": visible_count, "objective_coverage": coverage,
		"support": minf(support, 1.0), "travel": travel, "route_exposure": exposure, "peak_exposure": peak_exposure,
		"open_ground": open_ground, "open_fire": open_fire,
		"contact_distance": _nearest_contact_distance(contacts, cell), "route_contact_distance": route_contact_distance,
		"progress": float(start_distance - objective_distance) / float(maxi(start_distance, 1)), "legacy": legacy}


static func _nearest_contact_distance(contacts: Array[InfluenceContact], cell: Vector2i) -> int:
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
		danger = maxf(danger, risk(query.forecast_data[map.cell_to_index(cell)]))
	var cover: float = clampf(map.get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell), 0.0, 1.0)
	var open_fire: float = 0.0
	if cover < query.profile.minimum_cover:
		open_fire = danger
	return {"risk": danger, "open_fire": open_fire, "cover": cover, "contact_distance": _nearest_contact_distance(contacts, cell)}


static func outgoing_utility(query: PositionQuery, from_hex: Vector2i, target_hex: Vector2i) -> float:
	var records: Dictionary = query.snapshot.los.get(from_hex, {})
	if not records.has(target_hex):
		return 0.0
	var distance: int = LOSHelper.get_hex_distance(from_hex, target_hex)
	var power: float = InfluenceUnitQuery.get_firepower_at_range(query.unit, distance)
	if power <= 0.0:
		return 0.0
	var data: Dictionary = records[target_hex]
	var expected: float = LosInfluenceProjector.calculate_los_fire_threat(power,
		InfluenceUnitQuery.get_unit_effectiveness(query.unit), data.get("target_cover", 0.0), data.get("hindrance", 0.0), distance)
	return risk(expected)
