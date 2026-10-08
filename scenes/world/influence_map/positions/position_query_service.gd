class_name PositionQueryService
extends RefCounted


static func query_positions(query: PositionQuery) -> PositionResult:
	var result: PositionResult = PositionResult.new()
	result.unit = query.unit
	result.context = query.context_key()
	result.objective_hex = query.objective_hex
	result.profile_mode = query.profile.mode
	if query.snapshot == null or not query.snapshot.maps.has(query.team):
		result.reason = "No completed influence snapshot"
		return result
	result.snapshot_version = query.snapshot.version
	result.status = PositionResult.Status.NO_CANDIDATE
	if not InfluenceUnitQuery.is_valid_living_unit(query.unit) or query.unit.team != query.team:
		result.reason = "Unit is outside the query's ownership"
		return result
	if query.unit.members_alive <= 0 or query.unit.surrendered or not can_follow_intent(query.unit):
		result.reason = "Unit cannot execute tactical movement"
		return result
	if query.profile.mode == PositionProfile.Mode.ASSAULT and not can_assault(query.unit):
		result.reason = "Unit is not fit for an assault"
		return result
	var map: InfluenceMap = query.snapshot.maps[query.team]
	query.forecast_data = query.snapshot.get_forecast_data(query.team, query.objective_hex)
	if query.include_score_map:
		result.score_map.resize(map.cell_count)
		result.score_map.fill(0.0)
	result.eligibility.resize(map.cell_count)
	var candidates: Array[PositionCandidate] = _candidates(query, false, result)
	if candidates.is_empty() and not query.fallback_hexes.is_empty():
		candidates = _candidates(query, true, result)
	if candidates.is_empty():
		result.reason = "No reachable position satisfies geography, capacity and risk limits"
		return result
	candidates.sort_custom(_prefer_candidate)
	var best: PositionCandidate = candidates[0]
	result.proposed_hex = best.hex
	var retained: PositionCandidate = null
	var prior: Vector2i = query.unit.current_hex
	if query.has_accepted_target and query.accepted_context == result.context:
		prior = query.accepted_target
	for candidate: PositionCandidate in candidates:
		if query.include_score_map:
			result.score_map[candidate.index] = candidate.score
		if candidate.hex == prior:
			retained = candidate
		if result.alternatives.size() < query.max_alternatives:
			result.alternatives.append(candidate)
	result.status = PositionResult.Status.ACCEPTED
	if retained != null:
		result.previous_score = retained.score
		var margin: float = maxf(query.profile.improvement_absolute, absf(retained.score) * query.profile.improvement_relative)
		if best.score <= retained.score + margin:
			best = retained
			result.status = PositionResult.Status.RETAINED
	result.target_hex = best.hex
	result.target_index = best.index
	result.score = best.score
	result.features = best.features
	result.path = best.path
	result.should_move = best.hex != query.unit.current_hex
	# Continuing an already accepted move should not restart the action every tick.
	if query.has_accepted_target and query.accepted_context == result.context and best.hex == query.accepted_target and query.unit.movement != null and query.unit.movement.is_moving and query.unit.movement.target_hex == best.hex and _is_following_path(query.unit, best.path):
		result.should_move = false
	result.reason = "Accepted a feasible position"
	if result.status == PositionResult.Status.RETAINED:
		result.reason = "Retained the feasible position within the improvement margin"
	return result


static func _candidates(query: PositionQuery, fallback: bool, diagnostics: PositionResult) -> Array[PositionCandidate]:
	var result: Array[PositionCandidate] = []
	var map: InfluenceMap = query.snapshot.maps[query.team]
	for index: int in range(map.cell_count):
		var cell: Vector2i = map.index_to_cell(index)
		if not map.is_playable_cell(cell) or map.get_layer_value(InfluenceMap.Layer.NO_GO, cell) > 0.0:
			_reject(diagnostics, "terrain")
			continue
		if not _in_geography(query, cell, fallback):
			_reject(diagnostics, "geography")
			continue
		if _occupied(query, cell):
			_reject(diagnostics, "capacity")
			continue
		var path: Array[Vector2i] = query.snapshot.get_path(query.team, query.unit.current_hex, cell)
		if path.is_empty():
			_reject(diagnostics, "route")
			continue
		var features: Dictionary = PositionFeatureEvaluator.evaluate(query, cell, path)
		if features["incoming"] > query.profile.max_incoming_risk or features["peak_exposure"] > query.profile.max_route_exposure:
			_reject(diagnostics, "risk")
			continue
		if query.profile.mode == PositionProfile.Mode.SUPPORT_BY_FIRE and features["firing"] <= 0.0:
			_reject(diagnostics, "firing")
			continue
		diagnostics.eligibility[index] = 1
		var candidate: PositionCandidate = PositionCandidate.new()
		candidate.hex = cell
		candidate.index = index
		candidate.features = features
		candidate.path = path
		candidate.score = query.profile.score(features, query.unit)
		result.append(candidate)
	return result


static func _in_geography(query: PositionQuery, cell: Vector2i, fallback: bool) -> bool:
	if fallback:
		return query.fallback_hexes.has(cell)
	var objective_distance: int = LOSHelper.get_hex_distance(cell, query.objective_hex)
	if query.profile.mode == PositionProfile.Mode.DEFEND or query.profile.mode == PositionProfile.Mode.LEGACY_DEFENSE:
		if query.geography == PositionQuery.Geography.SECTOR_ONLY:
			return query.sector_cells.has(cell)
		if query.geography == PositionQuery.Geography.OBJECTIVE_RADIUS:
			return objective_distance <= query.defense_radius
		return objective_distance <= query.defense_radius or query.sector_cells.has(cell)
	if LOSHelper.get_hex_distance(query.unit.current_hex, cell) > query.movement_radius:
		return false
	if query.profile.mode == PositionProfile.Mode.SUPPORT_BY_FIRE:
		return objective_distance > 0 and objective_distance <= InfluenceUnitQuery.get_unit_range(query.unit)
	if query.profile.mode == PositionProfile.Mode.ASSAULT:
		return objective_distance <= 1
	return objective_distance <= LOSHelper.get_hex_distance(query.unit.current_hex, query.objective_hex)


static func _occupied(query: PositionQuery, cell: Vector2i) -> bool:
	for other: Unit in query.reservations:
		if other != query.unit and is_instance_valid(other) and other.alive and query.reservations[other] == cell:
			return true
	for other: Unit in query.snapshot.positions:
		if other != query.unit and query.snapshot.teams[other] == query.team and query.snapshot.positions[other] == cell:
			return true
	for contact: InfluenceContact in query.snapshot.get_contacts(query.team):
		if contact.hex == cell:
			return true
	return false


static func _prefer_candidate(a: PositionCandidate, b: PositionCandidate) -> bool:
	if not is_equal_approx(a.score, b.score):
		return a.score > b.score
	if not is_equal_approx(a.features["travel"], b.features["travel"]):
		return a.features["travel"] < b.features["travel"]
	return a.index < b.index


static func can_assault(unit: Unit) -> bool:
	if InfluenceUnitQuery.get_unit_effectiveness(unit) < 0.6 or InfluenceUnitQuery.get_unit_firepower(unit) <= 0.0:
		return false
	if unit.stress_system != null and unit.stress_system.state != Unit.MoraleState.NORMAL and unit.stress_system.state != Unit.MoraleState.CAUTIOUS:
		return false
	return unit.squad_type != Globals.SquadType.PLATOON_HEADQUARTERS and unit.squad_type != Globals.SquadType.COMPANY_HEADQUARTERS and unit.squad_type != Globals.SquadType.MORTAR


static func _reject(diagnostics: PositionResult, reason: String) -> void:
	diagnostics.rejections[reason] = diagnostics.rejections.get(reason, 0) + 1


static func _is_following_path(unit: Unit, recommended: Array[Vector2i]) -> bool:
	var movement: UnitMovement = unit.movement
	var remaining: Array[Vector2i] = [unit.current_hex]
	for index: int in range(movement.path_index, movement.path_hexes.size()):
		var cell: Vector2i = movement.path_hexes[index]
		if remaining[-1] != cell:
			remaining.append(cell)
	if movement.attack_in_progress and not movement.in_exposed_phase:
		for cell: Vector2i in movement.exposed_path_hexes:
			if remaining[-1] != cell:
				remaining.append(cell)
	return remaining == recommended


static func can_follow_intent(unit: Unit) -> bool:
	if unit.stress_system == null:
		return true
	return unit.stress_system.state != Unit.MoraleState.PANIC and unit.stress_system.state != Unit.MoraleState.COMBAT_INEFFECTIVE
