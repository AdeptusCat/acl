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
	if query.profile.mode in [PositionProfile.Mode.DEFEND, PositionProfile.Mode.HQ_SUPPORT]:
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
	var escape_cost: float = 0.0
	var visibility_seconds: float = 0.0
	var open_crossing_seconds: float = 0.0
	for index: int in range(1, path.size()):
		var step: Vector2i = path[index]
		var step_risk: float = risk(map.get_layer_value(InfluenceMap.Layer.THREAT, step))
		var step_features: Dictionary = {}
		if query.escape_policy != null or query.profile.mode in [PositionProfile.Mode.DEFEND, PositionProfile.Mode.HQ_SUPPORT] or query.press_attack:
			if query.route_field != null:
				step_features = query.route_field.step_data(step)
			else:
				step_features = route_step(query, step)
			step_risk = step_features["risk"]
		var step_cover: float = clampf(map.get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, step), 0.0, 1.0)
		open_ground += 1.0 - step_cover
		if step_cover < query.profile.minimum_cover:
			open_fire = maxf(open_fire, step_risk)
		route_contact_distance = mini(route_contact_distance, nearest_contact_distance(contacts, step))
		var seconds: float = crossing_seconds(query, path[index - 1], step)
		route_seconds += seconds
		if query.escape_policy != null:
			escape_cost += route_step_cost(query, step_features, seconds)
			visibility_seconds += seconds * step_features["visibility"]
		exposure_seconds += seconds * step_risk
		if step_cover < query.profile.minimum_cover:
			open_exposure_seconds += seconds * step_risk
			open_crossing_seconds += seconds
		exposure += step_risk
		peak_exposure = maxf(peak_exposure, step_risk)
		travel += 1.0 + map.get_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, step)
	if path.size() > 1:
		exposure /= float(path.size() - 1)
		open_ground /= float(path.size() - 1)
	features.merge({"travel": travel, "route_exposure": exposure, "peak_exposure": peak_exposure,
		"open_ground": open_ground, "open_fire": open_fire, "route_contact_distance": route_contact_distance,
		"route_seconds": route_seconds, "exposure_seconds": exposure_seconds, "open_exposure_seconds": open_exposure_seconds, "open_crossing_seconds": open_crossing_seconds})
	if query.escape_policy != null:
		features["escape_cost"] = escape_cost
		features["visibility_seconds"] = visibility_seconds
	if query.defense_area != null:
		features["deadline_slack_seconds"] = features.get("arrival_seconds", INF) - route_seconds - query.profile.establishment_seconds
		if query.reserve_position and path.size() > 1:
			var response: Dictionary = query.defense_area._reserve_features(query, cell, route_seconds + query.profile.establishment_seconds)
			if not response.is_empty():
				features["reserve_readiness"] = response["readiness"]
				features["reserve_branch_status"] = response["branches"]
	return features


static func _destination_features(query: PositionQuery, cell: Vector2i) -> Dictionary:
	var map: InfluenceMap = query.snapshot.maps[query.team]
	var objective_distance: int = LOSHelper.get_hex_distance(cell, query.objective_hex)
	var start_distance: int = LOSHelper.get_hex_distance(query.unit.current_hex, query.objective_hex)
	var incoming: float = risk(map.get_layer_value(InfluenceMap.Layer.THREAT, cell))
	var cover: float = clampf(map.get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell), 0.0, 1.0)
	if query.escape_policy != null:
		return {"escape": true, "cover": cover, "incoming": incoming, "forecast": 0.0,
			"firing": 0.0, "objective_coverage": 0.0, "support": 0.0, "progress": 0.0}
	var contacts: Array[InfluenceContact] = query.snapshot.get_contacts(query.team)
	if query.profile.mode in [PositionProfile.Mode.DEFEND, PositionProfile.Mode.HQ_SUPPORT] or query.press_attack:
		contacts = query.snapshot.get_defensive_contacts(query.team)
		if (query.profile.mode == PositionProfile.Mode.HQ_SUPPORT and query.profile.follows_moving_squads()) or query.press_attack:
			incoming = _contact_fire_risk(query, contacts, cell, false)
		else:
			incoming = maxf(incoming, _contact_fire_risk(query, contacts, cell, false))
	if query.profile.mode == PositionProfile.Mode.HQ_SUPPORT:
		var support_features: Dictionary = {"cover": cover, "incoming": incoming, "forecast": 0.0, "firing": 0.0, "objective_coverage": 0.0, "support": 0.0, "progress": 0.0}
		support_features.merge(HqSupportPositionPolicy.features(query, cell))
		return support_features
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
		if query.profile.mode == PositionProfile.Mode.SUPPORT_BY_FIRE and query.require_live_support_target and cell == query.origin_hex and not query.unit.movement.is_moving and query.unit.action_controller.action_state == SquadActionController.SquadActionState.HOLDING_POSITION:
			# A theoretical lane cannot retain an idle position; any live fresh defender remains useful.
			var target: Unit = TacticalPositionExecutor.select_support_target_for_objective(query.unit, query.objective_hex)
			firing = 0.0
			if target != null:
				firing = outgoing_utility(query, cell, target.current_hex)
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
	features["press_attack"] = query.press_attack
	if query.has_support_anchor:
		var origin_gap: int = maxi(0, LOSHelper.get_hex_distance(query.origin_hex, query.support_anchor_hex) - query.support_anchor_radius)
		var destination_gap: int = maxi(0, LOSHelper.get_hex_distance(cell, query.support_anchor_hex) - query.support_anchor_radius)
		features["support_advance"] = float(origin_gap - destination_gap) / float(maxi(1, query.movement_radius))
		features["support_anchor_distance"] = LOSHelper.get_hex_distance(cell, query.support_anchor_hex)
	if query.profile.mode == PositionProfile.Mode.DEFEND:
		if query.defense_area != null:
			features.merge(query.defense_area.features(query, cell))
			features["approach_duty"] = query.defense_responsibility == PositionQuery.Responsibility.COVER_APPROACH
			# Capture protection is a duty; distance alone adds no firing value.
			features["objective_coverage"] = float(cell == query.objective_hex or (objective_distance <= 1 and coverage > 0.0))
		features.merge(DefensePositionPolicy.evaluate(query, cell))
		if query.defense_responsibility == PositionQuery.Responsibility.COVER_APPROACH:
			features.merge(DefensePositionPolicy.deployment_features(query, cell))
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
		var firepower: float = contact.firepower
		if query.profile.mode == PositionProfile.Mode.HQ_SUPPORT:
			firepower *= HqSupportPositionPolicy.contact_threat_multiplier(query, contact)
		elif query.press_attack and contact.observed:
			if not TacticalPositionExecutor.is_active_defender(contact.unit):
				firepower = 0.0
			elif TacticalPositionExecutor.is_overwhelmed(contact.unit):
				firepower *= 0.1
		incoming += LosInfluenceProjector.calculate_los_fire_threat(firepower,
			contact.effectiveness, cover, record.get("hindrance", 0.0), distance)
	return risk(incoming)


static func route_step(query: PositionQuery, cell: Vector2i) -> Dictionary:
	var map: InfluenceMap = query.snapshot.maps[query.team]
	var contacts: Array[InfluenceContact] = query.snapshot.get_defensive_contacts(query.team)
	# Moving headquarters use observed contact capability rather than stale unsuppressed map risk.
	var danger: float = _contact_fire_risk(query, contacts, cell, true)
	if not query.press_attack and (query.profile.mode != PositionProfile.Mode.HQ_SUPPORT or not query.profile.follows_moving_squads()):
		danger = maxf(risk(map.get_layer_value(InfluenceMap.Layer.THREAT, cell)), danger)
	if query.forecast_data.size() == map.cell_count:
		danger = maxf(danger, query.profile.forecast_route_weight * risk(query.forecast_data[map.cell_to_index(cell)]))
	var cover: float = clampf(map.get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, cell), 0.0, 1.0)
	var open_fire: float = 0.0
	if cover < query.profile.minimum_cover:
		open_fire = danger
	var visibility: float = 0.0
	if query.escape_policy != null:
		visibility = EscapeCorridorPolicy.route_visibility(query.snapshot, query.team, cell)
	return {"risk": danger, "open_fire": open_fire, "cover": cover, "visibility": visibility}


static func route_step_cost(query: PositionQuery, step: Dictionary, seconds: float) -> float:
	var cost: float = 1.0 + query.profile.exposure_weight * step["risk"] + query.profile.open_ground_weight * (1.0 - step["cover"])
	if query.escape_policy != null:
		cost += query.escape_policy.concealment_weight * step["visibility"]
	return seconds * cost


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
