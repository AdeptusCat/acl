class_name DefenseAreaAssessment
extends RefCounted

var objective_hex: Vector2i
var snapshot_version: int = 0
var geometry: Dictionary = {}
var approaches: Array[Dictionary] = []
var covered_positions: Array[Vector2i] = []
var edge_positions: Array[Vector2i] = []
var max_priority: float = 0.0
var observed_contacts: Dictionary[Unit, Vector2i] = {}
var _interception_zones: Dictionary[String, Dictionary] = {}


func approach_for_sector(sector: int) -> Dictionary:
	for approach: Dictionary in approaches:
		if approach["id"] == sector:
			return approach
	return {}


func sector_at(cell: Vector2i) -> int:
	return sector_for(objective_hex, cell)


static func sector_for(objective: Vector2i, cell: Vector2i) -> int:
	var direction: Vector2 = LOSHelper.ground_layer.map_to_local(cell) - LOSHelper.ground_layer.map_to_local(objective)
	return posmod(int(floor((direction.angle() + PI / 6.0) / (PI / 3.0))), 6)


func coverage(query: PositionQuery, unit: Unit, cell: Vector2i, approach: Dictionary) -> Dictionary:
	if not query.sector_features.has(unit):
		query.sector_features[unit] = {}
	var key: String = str([cell, approach["id"], query.defense_radius])
	if query.sector_features[unit].has(key):
		return query.sector_features[unit][key]
	var total: float = 0.0
	var visible: float = 0.0
	var local_visible: float = 0.0
	var fire: float = 0.0
	var target_fire: Dictionary[Vector2i, float] = {}
	var records: Dictionary = query.snapshot.los.get(cell, {})
	var interception: Dictionary = _interception_zone(query.defense_radius, approach)
	for target: Vector2i in approach["cells"]:
		var weight: float = approach["weights"][target]
		total += weight
		if cell != target and not records.has(target):
			continue
		var distance: int = LOSHelper.get_hex_distance(cell, target)
		var power: float = query.firepower_at_range(unit, distance)
		if cell != target and power <= 0.0:
			continue
		visible += weight
		if interception["weights"].has(target):
			local_visible += weight
		var record: Dictionary = records.get(target, {})
		var ability: float = LosInfluenceProjector.calculate_los_fire_threat(power,
			InfluenceUnitQuery.get_unit_effectiveness(unit), record.get("target_cover", 0.0), record.get("hindrance", 0.0), distance)
		var utility: float = PositionFeatureEvaluator.risk(ability)
		target_fire[target] = utility
		fire += weight * utility
	var result: Dictionary = {"coverage": local_visible / maxf(interception["total"], 0.001),
		"corridor_coverage": visible / maxf(total, 0.001), "fire": fire / maxf(total, 0.001),
		"target_fire": target_fire, "total_weight": total}
	query.sector_features[unit][key] = result
	return result


func _interception_zone(radius: int, approach: Dictionary) -> Dictionary:
	var key: String = str([radius, approach["id"]])
	if not _interception_zones.has(key):
		var weights: Dictionary = {}
		var total: float = 0.0
		# The duty is to intercept the final approach, not to see half the attacker's trip.
		for target: Vector2i in approach["cells"]:
			if LOSHelper.get_hex_distance(target, objective_hex) <= maxi(radius, 1):
				weights[target] = approach["weights"][target]
				total += approach["weights"][target]
		_interception_zones[key] = {"weights": weights, "total": total}
	return _interception_zones[key]


func _support_fire(query: PositionQuery, approach: Dictionary) -> Dictionary:
	var sector: int = approach["id"]
	if not query.support_fire_by_sector.has(sector):
		var support: Dictionary[Vector2i, float] = {}
		# Reservations coordinate future firing positions; established screen checks remain separate.
		for friendly: Unit in query.reservations:
			if friendly == query.unit or not query.snapshot.positions.has(friendly) or query.snapshot.teams[friendly] != query.team or not InfluenceUnitQuery.is_valid_living_unit(friendly):
				continue
			if not PositionQueryService.can_follow_intent(friendly) or friendly.broken or InfluenceUnitQuery.get_unit_effectiveness(friendly) < query.profile.withdrawal_effectiveness:
				continue
			var data: Dictionary = coverage(query, friendly, query.reservations[friendly], approach)
			for target: Vector2i in data["target_fire"]:
				support[target] = maxf(support.get(target, 0.0), data["target_fire"][target])
		query.support_fire_by_sector[sector] = support
	return query.support_fire_by_sector[sector]


func features(query: PositionQuery, cell: Vector2i) -> Dictionary:
	var assigned: float = 0.0
	var assigned_corridor: float = 0.0
	var interdiction: float = 0.0
	var additional_interdiction: float = 0.0
	var readiness: float = 0.0
	var total_priority: float = 0.0
	var coverage_by_sector: Dictionary = {}
	var arrival_seconds: float = INF
	var worst_response: float = 0.0
	var crossing_seconds: float = query.defense_crossing_seconds()
	for approach: Dictionary in approaches:
		var data: Dictionary = coverage(query, query.unit, cell, approach)
		coverage_by_sector[approach["id"]] = data["coverage"]
		var priority: float = approach["priority"]
		total_priority += priority
		var support: Dictionary = _support_fire(query, approach)
		var additional_fire: float = 0.0
		for target: Vector2i in data["target_fire"]:
			# Overlapping fire remains useful, but covering an uncovered crossing adds more.
			additional_fire += approach["weights"][target] * data["target_fire"][target] * (1.0 - 0.6 * support.get(target, 0.0))
		additional_fire /= maxf(data["total_weight"], 0.001)
		var mission_weight: float = 0.35
		if query.assigned_sector == approach["id"] or query.assigned_sector < 0:
			mission_weight = 1.0
		interdiction += priority * data["fire"] * mission_weight
		additional_interdiction += priority * additional_fire * mission_weight
		if query.assigned_sector == approach["id"]:
			assigned = data["coverage"]
			assigned_corridor = data["corridor_coverage"]
			arrival_seconds = approach["arrival_seconds"]
		var response: float = approach["response_distances"].get(cell, INF) * crossing_seconds
		if approach["priority"] >= max_priority * 0.4:
			worst_response = maxf(worst_response, response)
		readiness += priority / (1.0 + response / 8.0)
	return {"assigned_sector": query.assigned_sector, "assigned_coverage": assigned,
		"assigned_corridor_coverage": assigned_corridor,
		"sector_coverage": coverage_by_sector, "interdiction": interdiction / maxf(total_priority, 0.001), "arrival_seconds": arrival_seconds,
		"additional_interdiction": additional_interdiction / maxf(total_priority, 0.001),
		"reserve_readiness": 0.5 * readiness / maxf(total_priority, 0.001) + 0.5 / (1.0 + worst_response / 8.0), "cover_edge": edge_positions.has(cell),
		"objective_return_seconds": geometry["objective_distances"].get(cell, INF) * crossing_seconds,
		"return_open_seconds": geometry["return_open_costs"].get(cell, INF) * crossing_seconds,
		"objective_connected_cover": geometry["return_open_costs"].get(cell, INF) <= 0.000001}
