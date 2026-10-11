class_name HqSupportPositionPolicy
extends RefCounted


static func is_headquarters(unit: Unit) -> bool:
	return is_instance_valid(unit) and unit.squad_type in [Globals.SquadType.PLATOON_HEADQUARTERS, Globals.SquadType.COMPANY_HEADQUARTERS]


static func can_share_position(first: Unit, second: Unit) -> bool:
	if not is_instance_valid(first) or not is_instance_valid(second) or first.team != second.team:
		return false
	return is_headquarters(first) or is_headquarters(second)


static func configure(query: PositionQuery) -> void:
	query.profile = PositionProfile.for_unit(query.profile, query.unit)
	query.use_defense_area = false
	query.defense_area = null
	query.area_job = null
	if query.snapshot != null:
		prepare(query)


static func prepare(query: PositionQuery) -> void:
	query.support_targets.clear()
	query.support_radius = 2
	var headquarters: Dictionary = query.snapshot.support_units.get(query.unit, {})
	query.support_radius = headquarters.get("radius", 2)
	for friendly: Unit in query.snapshot.positions:
		if friendly == query.unit or query.snapshot.teams[friendly] != query.team:
			continue
		var captured: Dictionary = query.snapshot.support_units.get(friendly, {})
		if captured.is_empty() or captured["headquarters"] or captured["members"] <= 0 or captured.get("surrendered", false):
			continue
		var belongs: bool = captured["commander"] == query.unit
		if not headquarters.is_empty():
			belongs = belongs or (captured["company"] == headquarters["company"] and (headquarters.get("company_hq", false) or captured["platoon"] == headquarters["platoon"]))
		if belongs:
			var need: float = captured["need"]
			if query.profile.support_assault_squads and friendly.squad_type == Globals.SquadType.Rifle and (query.assault_support_squad == null or friendly == query.assault_support_squad):
				# Advancing rifles need leadership before stress forces a support response.
				need = maxf(need, 0.35)
			query.support_targets[friendly] = {"hex": query.snapshot.positions[friendly], "need": need}


static func in_geography(query: PositionQuery, cell: Vector2i) -> bool:
	if cell == query.origin_hex:
		return true
	if LOSHelper.get_hex_distance(query.origin_hex, cell) > query.movement_radius:
		return false
	for target: Dictionary in query.support_targets.values():
		if LOSHelper.get_hex_distance(cell, target["hex"]) <= query.support_radius + 2:
			return true
	return false


static func features(query: PositionQuery, cell: Vector2i) -> Dictionary:
	var total_weight: float = 0.0
	var utility: float = 0.0
	var nearest: int = 999999
	var supported: Array[Unit] = []
	var urgent: Unit = null
	var highest_need: float = -1.0
	var priority_distance: int = 999999
	for friendly: Unit in query.support_targets:
		var target: Dictionary = query.support_targets[friendly]
		var distance: int = LOSHelper.get_hex_distance(cell, target["hex"])
		var weight: float = 0.25 + 2.0 * float(target["need"])
		var proximity: float = maxf(0.0, 1.0 - float(distance) / float(query.support_radius + 3))
		if distance <= query.support_radius:
			proximity += 1.0
			supported.append(friendly)
		utility += proximity * weight
		total_weight += weight
		nearest = mini(nearest, distance)
		if target["need"] > highest_need or (is_equal_approx(target["need"], highest_need) and friendly == query.assault_support_squad):
			highest_need = target["need"]
			urgent = friendly
			priority_distance = distance
	# Actual aura coverage of an urgent squad must outweigh proximity to calm squads.
	var priority_support: float = 0.0
	if highest_need >= 0.35 and priority_distance <= query.support_radius:
		priority_support = highest_need
	var visibility: float = 0.0
	var frontline: bool = false
	var good_order_enemy_los: bool = false
	for contact: InfluenceContact in query.snapshot.get_defensive_contacts(query.team):
		var multiplier: float = contact_threat_multiplier(query, contact)
		if multiplier <= 0.0:
			continue
		if query.snapshot.los.get(contact.hex, {}).has(cell):
			# Remembered enemies remain dangerous until their suppression is observed.
			if not contact.observed or not TacticalPositionExecutor.is_sufficiently_suppressed(contact.unit):
				good_order_enemy_los = true
			visibility += multiplier * maxf(0.2, contact.confidence)
			if multiplier >= 1.0:
				frontline = frontline or LOSHelper.get_hex_distance(cell, contact.hex) <= 1
	return {"responsibility": "hq_support", "support_utility": utility / maxf(total_weight, 0.001) + priority_support,
		"supported_squads": supported, "support_priority_squad": urgent, "support_priority_need": highest_need,
		"support_distance": nearest, "leadership_radius": query.support_radius,
		"support_priority_distance": priority_distance, "support_priority_covered": priority_distance <= query.support_radius,
		"enemy_visibility": PositionFeatureEvaluator.risk(visibility), "frontline": frontline,
		"good_order_enemy_los": good_order_enemy_los}


static func contact_threat_multiplier(query: PositionQuery, contact: InfluenceContact) -> float:
	# Hidden contacts retain their captured threat; only observations reveal suppression or surrender.
	if contact.observed:
		if not TacticalPositionExecutor.is_active_defender(contact.unit):
			return 0.0
		if query.profile.support_assault_squads and TacticalPositionExecutor.is_sufficiently_suppressed(contact.unit):
			return 0.1
	return 1.0


static func known_good_order_enemy_has_los(snapshot: InfluenceSnapshot, team: int, cell: Vector2i) -> bool:
	for contact: InfluenceContact in snapshot.get_defensive_contacts(team):
		if not snapshot.los.get(contact.hex, {}).has(cell):
			continue
		if not contact.observed:
			return true
		if TacticalPositionExecutor.is_active_defender(contact.unit) and not TacticalPositionExecutor.is_sufficiently_suppressed(contact.unit):
			return true
	return false


static func rejection(query: PositionQuery, features: Dictionary, check_route: bool = true) -> String:
	if features["cover"] < query.profile.minimum_cover and features["good_order_enemy_los"]:
		return "hq_open_enemy_los"
	if features["frontline"]:
		return "hq_frontline"
	if features["incoming"] > query.profile.max_incoming_risk:
		return "risk"
	if check_route and (features["peak_exposure"] > query.profile.max_route_exposure or features["exposure_seconds"] > query.profile.max_exposure_seconds or features["open_exposure_seconds"] > query.profile.max_open_exposure_seconds):
		return "route_risk"
	return ""
