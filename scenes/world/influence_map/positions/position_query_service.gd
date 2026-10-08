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
	query.route_field = null
	if query.profile.mode == PositionProfile.Mode.DEFEND:
		DefensePositionPolicy.prepare(query)
		if DefensePositionPolicy.needs_withdrawal(query):
			result.decision = PositionResult.Decision.WITHDRAW
		query.route_field = PositionRouteField.new()
		query.route_field.build(query)
	if query.include_score_map:
		result.score_map.resize(map.cell_count)
		result.score_map.fill(0.0)
	result.eligibility.resize(map.cell_count)
	var candidates: Array[PositionCandidate] = _candidates(query, false, result)
	if candidates.is_empty() and not query.fallback_hexes.is_empty():
		candidates = _candidates(query, true, result)
	if candidates.is_empty():
		result.reason = "No reachable position satisfies geography, capacity and risk limits"
		if query.profile.mode == PositionProfile.Mode.DEFEND:
			result.reason = "No covered reachable position protects the objective within the exposure budget"
			if result.rejections.has("screen_gap"):
				result.reason = "Holding until relocation can preserve existing approach coverage"
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
	var committed: bool = false
	if retained != null:
		result.previous_score = retained.score
		var margin: float = maxf(query.profile.improvement_absolute, absf(retained.score) * query.profile.improvement_relative)
		committed = _maintains_commitment(query, retained.hex, result.context)
		var holding_pressure: bool = retained.features.get("holding_under_pressure", false)
		# A healthy front holds; an enemy that passed the screen can require a new interception.
		if retained.features.get("responsibility") == "cover_approach" and best.features.get("interposition", 0.0) > retained.features.get("interposition", 0.0):
			holding_pressure = false
		committed = committed or holding_pressure
		if committed or best.score <= retained.score + margin:
			best = retained
			result.status = PositionResult.Status.RETAINED
	result.target_hex = best.hex
	result.target_index = best.index
	result.score = best.score
	result.features = best.features
	result.path = best.path
	if best.features.get("withdrawal", false):
		result.decision = PositionResult.Decision.WITHDRAW
	elif best.features.get("holding_under_pressure", false):
		result.decision = PositionResult.Decision.HOLD_DEFENSE
	result.should_move = best.hex != query.unit.current_hex
	# Continuing an already accepted move should not restart the action every tick.
	if query.has_accepted_target and query.accepted_context == result.context and best.hex == query.accepted_target and query.unit.movement != null and query.unit.movement.is_moving and query.unit.movement.target_hex == best.hex and _is_following_path(query.unit, best.path):
		result.should_move = false
	result.reason = "Accepted a feasible position"
	if query.profile.mode == PositionProfile.Mode.DEFEND:
		result.reason = "Accepted defensive " + str(best.features["responsibility"]) + " position"
	if result.status == PositionResult.Status.RETAINED:
		result.reason = "Retained the feasible position within the improvement margin"
		if committed:
			result.reason = "Maintained a safe defensive position commitment"
	if result.decision == PositionResult.Decision.HOLD_DEFENSE:
		result.reason = "Holding covered defensive responsibility under pressure"
	elif result.decision == PositionResult.Decision.WITHDRAW:
		result.reason = "Mission-constrained withdrawal preserves approach coverage"
		if result.target_hex == query.unit.current_hex:
			result.reason = "Holding defensive responsibility until a covered withdrawal is available"
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
		var path: Array[Vector2i] = _path_to_candidate(query, cell)
		if path.is_empty():
			_reject(diagnostics, "route")
			continue
		var features: Dictionary = PositionFeatureEvaluator.evaluate(query, cell, path)
		if features["cover"] < query.profile.minimum_cover:
			_reject(diagnostics, "cover")
			continue
		if query.profile.mode == PositionProfile.Mode.DEFEND:
			var rejection: String = DefensePositionPolicy.rejection(query, cell, features)
			if rejection != "":
				_reject(diagnostics, rejection)
				continue
		elif features["incoming"] > query.profile.max_incoming_risk or features["peak_exposure"] > query.profile.max_route_exposure:
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
	return _remaining_path(unit) == recommended


static func _remaining_path(unit: Unit) -> Array[Vector2i]:
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
	return remaining


static func _maintains_commitment(query: PositionQuery, cell: Vector2i, context: String) -> bool:
	if query.profile.commitment_seconds <= 0.0 or not query.has_accepted_target or query.accepted_context != context or query.accepted_target != cell:
		return false
	return query.snapshot.captured_at - query.accepted_at < query.profile.commitment_seconds or _moving_to(query.unit, cell)


static func _moving_to(unit: Unit, cell: Vector2i) -> bool:
	return unit.movement != null and unit.movement.is_moving and unit.movement.target_hex == cell


static func _path_to_candidate(query: PositionQuery, cell: Vector2i) -> Array[Vector2i]:
	if query.profile.mode == PositionProfile.Mode.DEFEND and query.has_accepted_target and query.accepted_context == query.context_key() and cell == query.accepted_target and _moving_to(query.unit, cell):
		var remaining: Array[Vector2i] = _remaining_path(query.unit)
		if _valid_snapshot_path(query, remaining, cell):
			var features: Dictionary = PositionFeatureEvaluator.evaluate(query, cell, remaining)
			if DefensePositionPolicy.allows_route(query, features):
				return remaining
	if query.route_field != null:
		return query.route_field.path_to(cell)
	return query.snapshot.get_path(query.team, query.unit.current_hex, cell)


static func _valid_snapshot_path(query: PositionQuery, path: Array[Vector2i], target: Vector2i) -> bool:
	if path.is_empty() or path[-1] != target or not query.snapshot.routes.has(query.team):
		return false
	var graph: AStar2D = query.snapshot.routes[query.team]
	var ids: Dictionary = query.snapshot.point_ids[query.team]
	var previous: int = -1
	for cell: Vector2i in path:
		if not ids.has(cell) or graph.is_point_disabled(ids[cell]):
			return false
		var id: int = ids[cell]
		if previous >= 0 and previous != id and not graph.are_points_connected(previous, id):
			return false
		previous = id
	return true


static func can_follow_intent(unit: Unit) -> bool:
	if unit.stress_system == null:
		return true
	return unit.stress_system.state != Unit.MoraleState.PANIC and unit.stress_system.state != Unit.MoraleState.COMBAT_INEFFECTIVE
