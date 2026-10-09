class_name HqSupportPositionPolicy
extends RefCounted


static func is_headquarters(unit: Unit) -> bool:
	return is_instance_valid(unit) and unit.squad_type in [Globals.SquadType.PLATOON_HEADQUARTERS, Globals.SquadType.COMPANY_HEADQUARTERS]


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
		if captured.is_empty() or captured["headquarters"] or captured["members"] <= 0:
			continue
		var belongs: bool = captured["commander"] == query.unit
		if not headquarters.is_empty():
			belongs = belongs or (captured["company"] == headquarters["company"] and (headquarters.get("company_hq", false) or captured["platoon"] == headquarters["platoon"]))
		if belongs:
			query.support_targets[friendly] = {"hex": query.snapshot.positions[friendly], "need": captured["need"]}


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
		if target["need"] > highest_need:
			highest_need = target["need"]
			urgent = friendly
	var visibility: float = 0.0
	var frontline: bool = false
	for contact: InfluenceContact in query.snapshot.get_defensive_contacts(query.team):
		if query.snapshot.los.get(contact.hex, {}).has(cell):
			visibility += maxf(0.2, contact.confidence)
			frontline = frontline or LOSHelper.get_hex_distance(cell, contact.hex) <= 1
	return {"responsibility": "hq_support", "support_utility": utility / maxf(total_weight, 0.001),
		"supported_squads": supported, "support_priority_squad": urgent, "support_priority_need": highest_need,
		"support_distance": nearest, "leadership_radius": query.support_radius,
		"enemy_visibility": PositionFeatureEvaluator.risk(visibility), "frontline": frontline}


static func rejection(query: PositionQuery, features: Dictionary, check_route: bool = true) -> String:
	if features["cover"] < query.profile.minimum_cover:
		return "cover"
	if features["frontline"]:
		return "hq_frontline"
	if features["incoming"] > query.profile.max_incoming_risk:
		return "risk"
	if check_route and (features["peak_exposure"] > query.profile.max_route_exposure or features["exposure_seconds"] > query.profile.max_exposure_seconds or features["open_exposure_seconds"] > query.profile.max_open_exposure_seconds):
		return "route_risk"
	return ""
