class_name PositionQueryService
extends RefCounted


static func query_positions(query: PositionQuery) -> PositionResult:
	var job: PositionQueryJob = PositionQueryJob.new()
	job.query = query
	job.advance(-1)
	return job.result


static func initialize(query: PositionQuery, result: PositionResult) -> bool:
	result.unit = query.unit
	result.context = query.context_key()
	result.objective_hex = query.objective_hex
	result.profile_mode = query.profile.mode
	if query.snapshot == null or not query.snapshot.maps.has(query.team):
		result.reason = "No completed influence snapshot"
		return false
	result.snapshot_version = query.snapshot.version
	result.status = PositionResult.Status.NO_CANDIDATE
	var map: InfluenceMap = query.snapshot.maps[query.team]
	result.cell_states.resize(map.cell_count)
	result.cell_states.fill(PositionResult.CellState.REJECTED)
	result.rejection_reasons.resize(map.cell_count)
	result.rejection_reasons.fill("unit_unavailable")
	if not InfluenceUnitQuery.is_valid_living_unit(query.unit) or query.unit.team != query.team:
		result.reason = "Unit is outside the query's ownership"
		return false
	if query.unit.members_alive <= 0 or query.unit.surrendered or not can_follow_intent(query.unit):
		result.reason = "Unit cannot execute tactical movement"
		return false
	if query.profile.mode == PositionProfile.Mode.ASSAULT and not can_assault(query.unit):
		result.reason = "Unit is not fit for an assault"
		return false
	if query.reserve_response_context != "" and query.reserve_response_context != DefenseReadinessJob.capability_key(query.unit):
		result.reason = "Reserve capability changed; response assessment needs rebuilding"
		return false
	result.cell_states.fill(PositionResult.CellState.UNEVALUATED)
	result.rejection_reasons.fill("")
	query.forecast_data = query.snapshot.get_forecast_data(query.team, query.objective_hex)
	query.reset_evaluation()
	if query.profile.mode == PositionProfile.Mode.DEFEND:
		DefensePositionPolicy.prepare(query)
		if DefensePositionPolicy.needs_withdrawal(query):
			result.decision = PositionResult.Decision.WITHDRAW
	if query.include_score_map:
		result.score_map.resize(map.cell_count)
		result.score_map.fill(0.0)
	result.eligibility.resize(map.cell_count)
	if query.defense_area != null:
		result.features["assigned_sector"] = query.assigned_sector
		result.features["assigned_branch"] = query.assigned_branch
		result.features["reserve_reason"] = query.reserve_reason
		var cells: Dictionary = {}
		var remembered: Dictionary = {}
		var inferred: Dictionary = {}
		for approach: Dictionary in query.defense_area.approaches:
			result.sector_priorities[approach["id"]] = approach["priority"]
			result.approach_evidence[approach["id"]] = approach["evidence"]
			result.approach_sources[approach["id"]] = approach["source"]
		for approach: Dictionary in query.defense_area.duties():
			var branch_key: String = DefenseAreaAssessment.duty_key(approach)
			result.branch_sources[branch_key] = approach["source"]
			result.branch_evidence[branch_key] = approach["evidence"]
			if query.assigned_branch != "" and query.assigned_branch != branch_key:
				continue
			if query.assigned_sector >= 0 and query.assigned_sector != approach["id"]:
				continue
			if query.assigned_sector < 0 and query.defense_area.approach_for_sector(approach["id"]).get("priority", approach["priority"]) < query.defense_area.max_priority * 0.4:
				continue
			var destination: Dictionary = cells
			if approach["evidence"] == "remembered":
				destination = remembered
			elif approach["evidence"] in ["inferred", "estimated"]:
				destination = inferred
			for cell: Vector2i in approach["cells"]:
				destination[cell] = true
		result.approach_cells.assign(cells.keys())
		result.remembered_approach_cells.assign(remembered.keys())
		result.inferred_approach_cells.assign(inferred.keys())
	return true


static func finish(query: PositionQuery, result: PositionResult, candidates: Array[PositionCandidate]) -> void:
	if candidates.is_empty():
		result.reason = "No reachable position satisfies geography, capacity and risk limits"
		if query.profile.mode == PositionProfile.Mode.DEFEND:
			result.reason = "No covered reachable position protects the objective within the exposure budget"
			if result.rejections.has("screen_gap"):
				result.reason = "Holding until relocation can preserve existing approach coverage"
			if result.cell_states.has(PositionResult.CellState.WAITING_HANDOFF):
				result.reason = "Waiting for the relocating defender to establish covering fire"
		return
	candidates.sort_custom(_prefer_candidate)
	var best: PositionCandidate = candidates[0]
	result.proposed_hex = best.hex
	var protected_choice: PositionCandidate = _prefer_connected_cover(query, best, candidates)
	var protected_preference: bool = protected_choice != best
	best = protected_choice
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
	result.features["connected_cover_preferred"] = protected_preference and best == protected_choice
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
		if query.assigned_sector >= 0:
			result.reason += " for sector %d (coverage %.0f%%)" % [query.assigned_sector, best.features.get("assigned_coverage", 0.0) * 100.0]
	if result.status == PositionResult.Status.RETAINED:
		result.reason = "Retained the feasible position within the improvement margin"
		if committed:
			result.reason = "Maintained a safe defensive position commitment"
	if result.decision == PositionResult.Decision.HOLD_DEFENSE:
		result.reason = "Holding covered defensive responsibility under pressure"
		if query.assigned_sector >= 0:
			result.reason += " in sector %d" % query.assigned_sector
	elif result.decision == PositionResult.Decision.WITHDRAW:
		result.reason = "Mission-constrained withdrawal preserves approach coverage"
		if result.target_hex == query.unit.current_hex:
			result.reason = "Holding defensive responsibility until a covered withdrawal is available"
	if result.features["connected_cover_preferred"] and result.status == PositionResult.Status.ACCEPTED:
		result.reason += "; preferred useful connected cover over a marginal detached firing gain"
	return


static func _prefer_connected_cover(query: PositionQuery, best: PositionCandidate, candidates: Array[PositionCandidate]) -> PositionCandidate:
	if query.profile.mode != PositionProfile.Mode.DEFEND or query.defense_area == null or best.features.get("objective_connected_cover", false):
		return best
	var starts_connected: bool = query.defense_area.geometry["return_open_costs"].get(query.origin_hex, INF) <= 0.000001
	for candidate: PositionCandidate in candidates:
		if not candidate.features.get("objective_connected_cover", false):
			continue
		# An established defense must not make a longer excursion to obtain connected cover.
		# A squad starting outside that cover can still deploy into the objective's woods.
		if starts_connected and candidate.features.get("open_crossing_seconds", 0.0) > best.features.get("open_crossing_seconds", 0.0) + 0.000001:
			continue
		var margin: float = maxf(query.profile.connected_cover_improvement_absolute, absf(candidate.score) * query.profile.connected_cover_improvement_relative)
		if best.score <= candidate.score + margin:
			return candidate
		# Candidates are sorted by utility; weaker connected positions cannot justify this preference.
		return best
	return best


static func prepare_candidate(query: PositionQuery, index: int, fallback: bool, diagnostics: PositionResult) -> bool:
	var map: InfluenceMap = query.snapshot.maps[query.team]
	var cell: Vector2i = map.index_to_cell(index)
	if not map.is_playable_cell(cell) or map.get_layer_value(InfluenceMap.Layer.NO_GO, cell) > 0.0:
		_reject(diagnostics, "terrain", index)
		return false
	if not _in_geography(query, cell, fallback):
		# A fallback search must not erase a completed primary-position diagnosis.
		if not fallback or diagnostics.rejection_reasons[index] == "geography":
			_reject(diagnostics, "geography", index)
		return false
	if _occupied(query, cell):
		_reject(diagnostics, "capacity", index)
		return false
	if query.profile.mode == PositionProfile.Mode.DEFEND:
		var features: Dictionary = PositionFeatureEvaluator.evaluate(query, cell, [])
		if features["cover"] < query.profile.minimum_cover:
			_reject(diagnostics, "cover", index)
			return false
		var rejection: String = DefensePositionPolicy.rejection(query, cell, features, false)
		if rejection != "":
			_reject(diagnostics, rejection, index)
			return false
	return true


static func evaluate_candidate(query: PositionQuery, index: int, diagnostics: PositionResult) -> PositionCandidate:
	var cell: Vector2i = query.snapshot.maps[query.team].index_to_cell(index)
	var path: Array[Vector2i] = _path_to_candidate(query, cell)
	if path.is_empty():
		_reject(diagnostics, "route", index)
		return null
	var features: Dictionary = PositionFeatureEvaluator.evaluate(query, cell, path)
	if features["cover"] < query.profile.minimum_cover:
		_reject(diagnostics, "cover", index)
		return null
	if query.profile.mode == PositionProfile.Mode.DEFEND:
		var rejection: String = DefensePositionPolicy.rejection(query, cell, features)
		if rejection != "":
			_reject(diagnostics, rejection, index)
			if rejection == "handoff_wait":
				diagnostics.cell_states[index] = PositionResult.CellState.WAITING_HANDOFF
				if query.include_score_map:
					diagnostics.score_map[index] = query.profile.score(features, query.unit)
			return null
	elif features["incoming"] > query.profile.max_incoming_risk or features["peak_exposure"] > query.profile.max_route_exposure:
		_reject(diagnostics, "risk", index)
		return null
	if query.profile.mode == PositionProfile.Mode.SUPPORT_BY_FIRE and features["firing"] <= 0.0:
		_reject(diagnostics, "firing", index)
		return null
	diagnostics.eligibility[index] = 1
	diagnostics.cell_states[index] = PositionResult.CellState.AVAILABLE
	diagnostics.rejection_reasons[index] = ""
	var candidate: PositionCandidate = PositionCandidate.new()
	candidate.hex = cell
	candidate.index = index
	candidate.features = features
	candidate.path = path
	candidate.score = query.profile.score(features, query.unit)
	return candidate


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


static func _reject(diagnostics: PositionResult, reason: String, index: int) -> void:
	diagnostics.rejections[reason] = diagnostics.rejections.get(reason, 0) + 1
	diagnostics.cell_states[index] = PositionResult.CellState.REJECTED
	diagnostics.rejection_reasons[index] = reason


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
	if unit.in_close_combat:
		return false
	if unit.stress_system == null:
		return true
	return unit.stress_system.state != Unit.MoraleState.PANIC and unit.stress_system.state != Unit.MoraleState.COMBAT_INEFFECTIVE
