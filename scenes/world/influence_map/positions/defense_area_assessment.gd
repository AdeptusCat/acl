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
	var key: String = str([cell, approach["id"]])
	if query.sector_features[unit].has(key):
		return query.sector_features[unit][key]
	var total: float = 0.0
	var visible: float = 0.0
	var fire: float = 0.0
	var records: Dictionary = query.snapshot.los.get(cell, {})
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
		var record: Dictionary = records.get(target, {})
		var ability: float = LosInfluenceProjector.calculate_los_fire_threat(power,
			InfluenceUnitQuery.get_unit_effectiveness(unit), record.get("target_cover", 0.0), record.get("hindrance", 0.0), distance)
		fire += weight * PositionFeatureEvaluator.risk(ability)
	var result: Dictionary = {"coverage": visible / maxf(total, 0.001), "fire": fire / maxf(total, 0.001)}
	query.sector_features[unit][key] = result
	return result


func features(query: PositionQuery, cell: Vector2i) -> Dictionary:
	var assigned: float = 0.0
	var interdiction: float = 0.0
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
		var marginal: float = 1.0
		for friendly: Unit in query.reservations:
			if friendly == query.unit or not query.snapshot.positions.has(friendly) or not InfluenceUnitQuery.is_valid_living_unit(friendly) or query.snapshot.teams[friendly] != query.team:
				continue
			marginal = minf(marginal, 1.0 - 0.6 * coverage(query, friendly, query.reservations[friendly], approach)["coverage"])
		var mission_weight: float = 0.35
		if query.assigned_sector == approach["id"] or query.assigned_sector < 0:
			mission_weight = 1.0
		interdiction += priority * data["fire"] * marginal * mission_weight
		if query.assigned_sector == approach["id"]:
			assigned = data["coverage"]
			arrival_seconds = approach["arrival_seconds"]
		var response: float = approach["response_distances"].get(cell, INF) * crossing_seconds
		if approach["priority"] >= max_priority * 0.4:
			worst_response = maxf(worst_response, response)
		readiness += priority / (1.0 + response / 8.0)
	return {"assigned_sector": query.assigned_sector, "assigned_coverage": assigned,
		"sector_coverage": coverage_by_sector, "interdiction": interdiction / maxf(total_priority, 0.001), "arrival_seconds": arrival_seconds,
		"reserve_readiness": 0.5 * readiness / maxf(total_priority, 0.001) + 0.5 / (1.0 + worst_response / 8.0), "cover_edge": edge_positions.has(cell),
		"objective_return_seconds": geometry["objective_distances"].get(cell, INF) * crossing_seconds,
		"return_open_seconds": geometry["return_open_costs"].get(cell, INF) * crossing_seconds,
		"objective_connected_cover": geometry["return_open_costs"].get(cell, INF) <= 0.000001}
