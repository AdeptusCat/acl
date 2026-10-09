class_name DefenseAreaAssessment
extends RefCounted

const MIN_CROSSING_COVERAGE: float = 0.75

var objective_hex: Vector2i
var snapshot_version: int = 0
var geometry: Dictionary = {}
var approaches: Array[Dictionary] = []
var covered_positions: Array[Vector2i] = []
var edge_positions: Array[Vector2i] = []
var max_priority: float = 0.0
var observed_contacts: Dictionary[Unit, Vector2i] = {}
var _interception_zones: Dictionary[String, Dictionary] = {}
var _crossing_zones: Dictionary[String, Dictionary] = {}


static func duty_key(approach: Dictionary) -> String:
	return approach.get("key", str(approach["id"]))


func duties() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for approach: Dictionary in approaches:
		if approach.has("branches"):
			result.append_array(approach["branches"])
		else:
			result.append(approach)
	return result


func branch_for_key(key: String) -> Dictionary:
	for branch: Dictionary in duties():
		if duty_key(branch) == key:
			return branch
	return {}


func support_duties(query: PositionQuery) -> Array[Dictionary]:
	var result: Array[Dictionary] = duties()
	if query.assigned_branch == "":
		for approach: Dictionary in approaches:
			if approach.has("branches"):
				result.append(approach)
	return result


func duty_priority(approach: Dictionary) -> float:
	var parent: Dictionary = approach_for_sector(approach["id"])
	return parent.get("priority", approach["priority"]) * approach.get("share", 1.0)


func max_duty_priority() -> float:
	var priority: float = 0.0
	for approach: Dictionary in duties():
		priority = maxf(priority, duty_priority(approach))
	return priority


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
	var key: String = str([cell, duty_key(approach), query.defense_radius])
	if query.sector_features[unit].has(key):
		return query.sector_features[unit][key]
	var total: float = 0.0
	var visible: float = 0.0
	var local_visible: float = 0.0
	var fire: float = 0.0
	var target_fire: Dictionary[Vector2i, float] = {}
	var visible_targets: Dictionary[Vector2i, float] = {}
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
			visible_targets[target] = weight
		var record: Dictionary = records.get(target, {})
		var ability: float = LosInfluenceProjector.calculate_los_fire_threat(power,
			InfluenceUnitQuery.get_unit_effectiveness(unit), record.get("target_cover", 0.0), record.get("hindrance", 0.0), distance)
		var utility: float = PositionFeatureEvaluator.risk(ability)
		if target == approach.get("source", objective_hex) and utility > 0.0:
			visible_targets[target] = weight
		elif target == approach.get("source", objective_hex) and cell != target:
			visible_targets.erase(target)
		target_fire[target] = utility
		fire += weight * utility
	var result: Dictionary = {"coverage": local_visible / maxf(interception["total"], 0.001),
		"corridor_coverage": visible / maxf(total, 0.001), "fire": fire / maxf(total, 0.001),
		"target_fire": target_fire, "total_weight": total, "visible_targets": visible_targets}
	query.sector_features[unit][key] = result
	return result


func _interception_zone(radius: int, approach: Dictionary) -> Dictionary:
	var key: String = str([radius, duty_key(approach)])
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
	var key: String = duty_key(approach)
	if not query.support_fire_by_branch.has(key):
		warm_support(query, approach, null)
		for friendly: Unit in query.snapshot.positions:
			warm_support(query, approach, friendly)
	return query.support_fire_by_branch[key]


func crossing_zone(radius: int, approach: Dictionary) -> Dictionary:
	var key: String = str([radius, duty_key(approach)])
	if _crossing_zones.has(key):
		return _crossing_zones[key]
	var result: Dictionary = {"weights": {}, "total": 0.0, "arrival_seconds": approach["arrival_seconds"], "active_target": false}
	_crossing_zones[key] = result
	if not approach.has("distances") or not geometry.has("cover"):
		return result
	var entrances: Array[Dictionary] = []
	var earliest: float = INF
	var source_distances: Dictionary = approach["distances"]
	var best: float = source_distances.get(objective_hex, INF)
	for cell: Vector2i in approach["cells"]:
		if LOSHelper.get_hex_distance(cell, objective_hex) > maxi(radius, 1) or geometry["cover"].get(cell, 0.0) >= 0.1:
			continue
		for next: Vector2i in geometry["neighbors"].get(cell, []):
			if geometry["cover"].get(next, 0.0) < 0.1 or geometry["return_open_costs"].get(next, INF) > 0.000001:
				continue
			if LOSHelper.get_hex_distance(next, objective_hex) >= LOSHelper.get_hex_distance(cell, objective_hex):
				continue
			var entry: float = source_distances.get(cell, INF) + geometry["costs"][next]
			if not is_finite(entry) or entry + geometry["objective_distances"].get(next, INF) > best + 2.5:
				continue
			earliest = minf(earliest, entry)
			entrances.append({"cell": cell, "cost": entry})
	# Protect the first credible entrances, rather than averaging them with inner woods.
	for entrance: Dictionary in entrances:
		if entrance["cost"] <= earliest + 1.0:
			var cell: Vector2i = entrance["cell"]
			result["weights"][cell] = approach["weights"][cell]
	for weight: float in result["weights"].values():
		result["total"] += weight
	if result["total"] > 0.0:
		result["arrival_seconds"] = earliest * approach.get("crossing_seconds", 2.0)
		result["active_target"] = approach.get("evidence", "inferred") == "observed" and geometry["cover"].get(approach["source"], 0.0) < 0.1 and LOSHelper.get_hex_distance(approach["source"], objective_hex) <= maxi(radius, 1) + 2
		if approach.get("evidence", "inferred") == "estimated":
			# Coarse intelligence stays coarse: scale its delayed bucket by terrain progress.
			result["arrival_seconds"] = approach["arrival_seconds"] * clampf(earliest / maxf(best, 0.001), 0.0, 1.0)
	return result


func crossing_coverage(radius: int, visible: Dictionary, approach: Dictionary) -> float:
	var zone: Dictionary = crossing_zone(radius, approach)
	if zone["total"] <= 0.0:
		return 1.0
	# A known attacker already in the nearby open lane must actually be under usable fire.
	if zone["active_target"] and not visible.has(approach["source"]):
		return 0.0
	var protected: float = 0.0
	for cell: Vector2i in zone["weights"]:
		if visible.has(cell):
			protected += zone["weights"][cell]
	return protected / zone["total"]


func protection_of_targets(radius: int, visible: Dictionary, approach: Dictionary) -> float:
	if crossing_zone(radius, approach)["total"] <= 0.0:
		return coverage_of_targets(radius, visible, approach)
	return minf(coverage_of_targets(radius, visible, approach), crossing_coverage(radius, visible, approach) * DefensePositionPolicy.MIN_APPROACH_COVERAGE / MIN_CROSSING_COVERAGE)


func combined_crossing_coverage(query: PositionQuery, cell: Vector2i, approach: Dictionary) -> float:
	var visible: Dictionary = established_targets(query, approach).duplicate()
	visible.merge(coverage(query, query.unit, cell, approach)["visible_targets"])
	return crossing_coverage(query.defense_radius, visible, approach)


func established_targets(query: PositionQuery, approach: Dictionary) -> Dictionary:
	var key: String = duty_key(approach)
	if not query.established_screen.has(key):
		warm_support(query, approach, null)
		for friendly: Unit in query.snapshot.positions:
			warm_support(query, approach, friendly)
	return query.established_screen[key]


func warm_support(query: PositionQuery, approach: Dictionary, friendly: Unit) -> void:
	var key: String = duty_key(approach)
	if not query.support_fire_by_branch.has(key):
		query.support_fire_by_branch[key] = {}
	if not query.established_screen.has(key):
		query.established_screen[key] = {}
	if friendly == query.unit or not InfluenceUnitQuery.is_valid_living_unit(friendly) or not query.snapshot.positions.has(friendly) or query.snapshot.teams[friendly] != query.team:
		return
	if not PositionQueryService.can_follow_intent(friendly) or friendly.broken or InfluenceUnitQuery.get_unit_effectiveness(friendly) < query.profile.withdrawal_effectiveness:
		return
	# Future reservations affect complementary firing utility, never established screen protection.
	if query.reservations.has(friendly):
		var data: Dictionary = coverage(query, friendly, query.reservations[friendly], approach)
		for target: Vector2i in data["target_fire"]:
			query.support_fire_by_branch[key][target] = maxf(query.support_fire_by_branch[key].get(target, 0.0), data["target_fire"][target])
	if friendly.movement != null and friendly.movement.is_moving:
		return
	if friendly.current_hex != query.snapshot.positions[friendly]:
		return
	if query.reservations.has(friendly) and query.reservations[friendly] != query.snapshot.positions[friendly]:
		return
	if friendly.action_controller != null and friendly.action_controller.action_state in [SquadActionController.SquadActionState.ESTABLISHING_POSITION, SquadActionController.SquadActionState.REGROUPING]:
		return
	query.established_screen[key].merge(coverage(query, friendly, query.snapshot.positions[friendly], approach)["visible_targets"])


func combined_coverage(query: PositionQuery, cell: Vector2i, approach: Dictionary) -> float:
	var own_targets: Dictionary = coverage(query, query.unit, cell, approach)["visible_targets"]
	var support: Dictionary = established_targets(query, approach)
	var zone: Dictionary = _interception_zone(query.defense_radius, approach)
	var visible: float = 0.0
	for target: Vector2i in zone["weights"]:
		if own_targets.has(target) or support.has(target):
			visible += zone["weights"][target]
	return visible / maxf(zone["total"], 0.001)


func coverage_of_positions(query: PositionQuery, positions: Dictionary[Unit, Vector2i], approach: Dictionary) -> float:
	var visible: Dictionary = {}
	for friendly: Unit in positions:
		if not InfluenceUnitQuery.is_valid_living_unit(friendly) or not PositionQueryService.can_follow_intent(friendly) or friendly.broken or InfluenceUnitQuery.get_unit_effectiveness(friendly) < query.profile.withdrawal_effectiveness:
			continue
		visible.merge(coverage(query, friendly, positions[friendly], approach)["visible_targets"])
	return coverage_of_targets(query.defense_radius, visible, approach)


func protection_of_positions(query: PositionQuery, positions: Dictionary[Unit, Vector2i], approach: Dictionary) -> float:
	var visible: Dictionary = {}
	for friendly: Unit in positions:
		if InfluenceUnitQuery.is_valid_living_unit(friendly) and PositionQueryService.can_follow_intent(friendly) and not friendly.broken and InfluenceUnitQuery.get_unit_effectiveness(friendly) >= query.profile.withdrawal_effectiveness:
			visible.merge(coverage(query, friendly, positions[friendly], approach)["visible_targets"])
	return protection_of_targets(query.defense_radius, visible, approach)


func coverage_of_targets(radius: int, visible: Dictionary, approach: Dictionary) -> float:
	var zone: Dictionary = _interception_zone(radius, approach)
	var total: float = 0.0
	for target: Vector2i in visible:
		total += zone["weights"].get(target, 0.0)
	return total / maxf(zone["total"], 0.001)


func features(query: PositionQuery, cell: Vector2i) -> Dictionary:
	var assigned: float = 0.0
	var assigned_corridor: float = 0.0
	var interdiction: float = 0.0
	var additional_interdiction: float = 0.0
	var readiness: float = 0.0
	var total_priority: float = 0.0
	var coverage_by_sector: Dictionary = {}
	var coverage_by_branch: Dictionary = {}
	var arrival_seconds: float = INF
	var worst_response: float = 0.0
	var crossing_seconds: float = query.defense_crossing_seconds()
	var evaluated: Array[Dictionary] = approaches
	if query.assigned_branch != "":
		evaluated = duties()
	var highest: float = max_priority
	if query.assigned_branch != "":
		highest = max_duty_priority()
	for approach: Dictionary in evaluated:
		var data: Dictionary = coverage(query, query.unit, cell, approach)
		var key: String = duty_key(approach)
		coverage_by_sector[approach["id"]] = maxf(coverage_by_sector.get(approach["id"], 0.0), data["coverage"])
		coverage_by_branch[key] = data["coverage"]
		var priority: float = duty_priority(approach)
		total_priority += priority
		var support: Dictionary = _support_fire(query, approach)
		var additional_fire: float = 0.0
		for target: Vector2i in data["target_fire"]:
			# Overlapping fire remains useful, but covering an uncovered crossing adds more.
			additional_fire += approach["weights"][target] * data["target_fire"][target] * (1.0 - 0.6 * support.get(target, 0.0))
		additional_fire /= maxf(data["total_weight"], 0.001)
		var mission_weight: float = 0.35
		var assigned_duty: bool = query.assigned_sector == approach["id"]
		if query.assigned_branch != "":
			assigned_duty = query.assigned_branch == key
		if assigned_duty or query.assigned_sector < 0:
			mission_weight = 1.0
		interdiction += priority * data["fire"] * mission_weight
		additional_interdiction += priority * additional_fire * mission_weight
		if assigned_duty:
			assigned = data["coverage"]
			assigned_corridor = data["corridor_coverage"]
			arrival_seconds = approach["arrival_seconds"]
		var response: float = approach["response_distances"].get(cell, INF) * crossing_seconds
		if priority >= highest * 0.4:
			worst_response = maxf(worst_response, response)
		readiness += priority / (1.0 + response / 8.0)
	var reserve_data: Dictionary = _reserve_features(query, cell)
	return {"assigned_sector": query.assigned_sector, "assigned_branch": query.assigned_branch, "assigned_coverage": assigned,
		"assigned_corridor_coverage": assigned_corridor,
		"sector_coverage": coverage_by_sector, "branch_coverage": coverage_by_branch, "interdiction": interdiction / maxf(total_priority, 0.001), "arrival_seconds": arrival_seconds,
		"additional_interdiction": additional_interdiction / maxf(total_priority, 0.001),
		"reserve_readiness": reserve_data.get("readiness", 0.5 * readiness / maxf(total_priority, 0.001) + 0.5 / (1.0 + worst_response / 8.0)),
		"reserve_branch_status": reserve_data.get("branches", {}), "reserve_reason": query.reserve_reason, "cover_edge": edge_positions.has(cell),
		"objective_return_seconds": geometry["objective_distances"].get(cell, INF) * crossing_seconds,
		"return_open_seconds": geometry["return_open_costs"].get(cell, INF) * crossing_seconds,
		"objective_connected_cover": geometry["return_open_costs"].get(cell, INF) <= 0.000001}


func _reserve_features(query: PositionQuery, cell: Vector2i, mobilization_seconds: float = 0.0) -> Dictionary:
	if not query.reserve_position or query.reserve_responses.is_empty():
		return {}
	var total: float = 0.0
	var readiness: float = 0.0
	var worst: float = 1.0
	var branches: Dictionary[String, Dictionary] = {}
	for key: String in query.reserve_responses:
		var data: Dictionary = query.reserve_responses[key]
		var response: float = data["seconds"].get(cell, INF) + mobilization_seconds
		var arrival: float = data["arrival_seconds"]
		var timely: bool = response <= arrival
		var protected: bool = data["covered"] or timely
		branches[key] = {"covered": data["covered"], "response_seconds": response, "arrival_seconds": arrival, "objective_arrival_seconds": data.get("objective_arrival_seconds", arrival), "crossing": data.get("crossing", false), "protected": protected}
		if data["covered"]:
			continue
		var utility: float = 1.0 / (1.0 + response / 8.0)
		if not timely:
			utility *= 0.25
		total += data["weight"]
		readiness += data["weight"] * utility
		worst = minf(worst, utility)
	if total <= 0.0:
		return {"readiness": 1.0, "branches": branches}
	return {"readiness": 0.5 * readiness / total + 0.5 * worst, "branches": branches}
