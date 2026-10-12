class_name DefensePositionPolicy
extends RefCounted

# Mission responsibility is evaluated separately from travel safety and cover quality.
const MIN_APPROACH_COVERAGE: float = 0.5
const HANDOFF_MARGIN_SECONDS: float = 1.0


static func capture_departure_baseline(snapshot: InfluenceSnapshot, team: int) -> Dictionary[Unit, Vector2i]:
	var baseline: Dictionary[Unit, Vector2i] = {}
	var profile: PositionProfile = PositionProfile.for_mode(PositionProfile.Mode.DEFEND)
	for unit: Unit in snapshot.positions:
		if HqSupportPositionPolicy.is_headquarters(unit) or snapshot.teams[unit] != team or not InfluenceUnitQuery.is_valid_living_unit(unit):
			continue
		if not PositionQueryService.can_follow_intent(unit) or unit.broken or InfluenceUnitQuery.get_unit_effectiveness(unit) < profile.withdrawal_effectiveness:
			continue
		if unit.current_hex != snapshot.positions[unit] or (unit.movement != null and unit.movement.is_moving):
			continue
		if unit.action_controller != null and unit.action_controller.action_state in [SquadActionController.SquadActionState.ESTABLISHING_POSITION, SquadActionController.SquadActionState.REGROUPING]:
			continue
		if snapshot.maps[team].get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, unit.current_hex) >= profile.minimum_cover:
			baseline[unit] = unit.current_hex
	return baseline


static func prepare(query: PositionQuery) -> void:
	query.defense_approaches.clear()
	if query.defense_area != null:
		query.defense_approaches = query.defense_area.approaches.duplicate()
		if query.assigned_branch != "":
			query.defense_approaches = query.defense_area.duties()
		return
	var contacts: Array[InfluenceContact] = query.snapshot.get_defensive_contacts(query.team)
	var graph: AStar2D = null
	if not contacts.is_empty():
		graph = _approach_graph(query, contacts)
	var ids: Dictionary = query.snapshot.point_ids.get(query.team, {})
	for contact: InfluenceContact in contacts:
		var cells: Array[Vector2i] = []
		if graph != null and ids.has(contact.hex) and ids.has(query.objective_hex):
			for id: int in graph.get_id_path(ids[contact.hex], ids[query.objective_hex]):
				var cell: Vector2i = LOSHelper.ground_layer.local_to_map(graph.get_point_position(id))
				if cell != query.objective_hex and LOSHelper.get_hex_distance(cell, query.objective_hex) <= query.defense_radius:
					cells.append(cell)
		if cells.is_empty():
			cells.append(query.objective_hex)
		query.defense_approaches.append({"source": contact.hex, "cells": cells})
	if contacts.is_empty() and query.axis != null:
		var cells: Array[Vector2i] = query.axis.approach_hexes.duplicate()
		if cells.is_empty():
			cells.append(query.axis.source_hex)
		query.defense_approaches.append({"source": query.axis.source_hex, "cells": cells})


static func _approach_graph(query: PositionQuery, contacts: Array[InfluenceContact]) -> AStar2D:
	if not query.snapshot.routes.has(query.team):
		return null
	var source: AStar2D = query.snapshot.routes[query.team]
	var graph: AStar2D = AStar2D.new()
	var map: InfluenceMap = query.snapshot.maps[query.team]
	var endpoints: Array[Vector2i] = [query.objective_hex]
	for contact: InfluenceContact in contacts:
		endpoints.append(contact.hex)
	for id: int in source.get_point_ids():
		var position: Vector2 = source.get_point_position(id)
		var cell: Vector2i = LOSHelper.ground_layer.local_to_map(position)
		graph.add_point(id, position, 1.0 + map.get_layer_value(InfluenceMap.Layer.TERRAIN_MOVE_COST, cell))
		graph.set_point_disabled(id, source.is_point_disabled(id) and not endpoints.has(cell))
	for id: int in source.get_point_ids():
		for neighbor: int in source.get_point_connections(id):
			graph.connect_points(id, neighbor, false)
	return graph


static func evaluate(query: PositionQuery, cell: Vector2i) -> Dictionary:
	var distance: int = LOSHelper.get_hex_distance(cell, query.objective_hex)
	var covers_objective: bool = _can_cover(query, query.unit, cell, query.objective_hex)
	var guard: bool = covers_objective and distance <= 1
	if query.defense_approaches.is_empty():
		guard = covers_objective and distance <= query.defense_radius
	var blocking: float = 0.0
	var interposition: float = 0.0
	var approach_covered: bool = false
	var covered_approaches: int = 0
	var total_priority: float = 0.0
	var important_count: int = 0
	var important_covered: int = 0
	var highest: float = 0.0
	if query.defense_area != null:
		highest = query.defense_area.max_priority
		if query.assigned_branch != "":
			highest = query.defense_area.max_duty_priority()
	for approach: Dictionary in query.defense_approaches:
		var coverage: float = _approach_coverage(query, query.unit, cell, approach)
		var priority: float = approach.get("priority", 1.0)
		if query.defense_area != null:
			priority = query.defense_area.duty_priority(approach)
		if query.defense_area == null or priority >= highest * 0.4:
			important_count += 1
			if coverage >= MIN_APPROACH_COVERAGE:
				important_covered += 1
		total_priority += priority
		blocking += coverage * priority
		var assigned: bool = query.assigned_sector == approach.get("id", -1)
		if query.assigned_branch != "":
			assigned = query.assigned_branch == DefenseAreaAssessment.duty_key(approach)
		if (query.assigned_sector < 0 and (query.defense_area == null or priority >= highest * 0.4)) or assigned:
			approach_covered = approach_covered or coverage >= MIN_APPROACH_COVERAGE
		if coverage >= MIN_APPROACH_COVERAGE:
			covered_approaches += 1
		var enemy_distance: int = LOSHelper.get_hex_distance(query.objective_hex, approach["source"])
		var detour: int = distance + LOSHelper.get_hex_distance(cell, approach["source"]) - enemy_distance
		if distance <= enemy_distance and detour <= 1:
			if query.assigned_sector < 0 or assigned:
				interposition = maxf(interposition, 1.0 - 0.5 * float(maxi(detour, 0)))
	if not query.defense_approaches.is_empty():
		blocking /= maxf(total_priority, 0.001)
	var responsibility: String = ""
	if cell == query.objective_hex:
		responsibility = "occupy"
	elif guard:
		responsibility = "guard"
	elif approach_covered:
		responsibility = "cover_approach"
	if query.reserve_position and query.defense_area != null and query.defense_area.geometry["objective_distances"].has(cell):
		responsibility = "reserve"
	if query.defense_responsibility == PositionQuery.Responsibility.OCCUPY and cell != query.objective_hex:
		responsibility = ""
	elif query.defense_responsibility == PositionQuery.Responsibility.GUARD and not guard and cell != query.objective_hex:
		responsibility = ""
	elif query.defense_responsibility == PositionQuery.Responsibility.COVER_APPROACH and not approach_covered:
		responsibility = ""
	var crossing: float = 1.0
	if query.required_crossing_branch != "" and query.defense_area != null:
		var branch: Dictionary = query.defense_area.branch_for_key(query.required_crossing_branch)
		if branch.is_empty():
			crossing = 0.0
			responsibility = ""
		else:
			crossing = query.defense_area.combined_crossing_coverage(query, cell, branch)
			if crossing < DefenseAreaAssessment.MIN_CROSSING_COVERAGE or query.defense_area.geometry["return_open_costs"].get(cell, INF) > 0.000001:
				responsibility = ""
	return {"responsibility": responsibility, "blocking": blocking, "interposition": interposition,
		"required_crossing_branch": query.required_crossing_branch, "crossing_coverage": crossing,
		"covered_approaches": covered_approaches, "approach_count": query.defense_approaches.size(),
		"important_approaches_covered": important_covered, "important_approach_count": important_count,
		"preserves_screen": _preserves_screen(query, cell), "withdrawal": needs_withdrawal(query)}


static func _can_cover(query: PositionQuery, unit: Unit, from: Vector2i, target: Vector2i) -> bool:
	if from == target:
		return true
	return query.snapshot.los.get(from, {}).has(target) and query.firepower_at_range(unit, LOSHelper.get_hex_distance(from, target)) > 0.0


static func _approach_coverage(query: PositionQuery, unit: Unit, cell: Vector2i, approach: Dictionary) -> float:
	if query.defense_area != null:
		return query.defense_area.coverage(query, unit, cell, approach)["coverage"]
	var covered: int = 0
	for target: Vector2i in approach["cells"]:
		if _can_cover(query, unit, cell, target):
			covered += 1
	return float(covered) / float(maxi(approach["cells"].size(), 1))


static func _preserves_screen(query: PositionQuery, cell: Vector2i) -> bool:
	if cell == query.unit.current_hex:
		return true
	if query.defense_area != null:
		return _preserves_branch_screen(query, cell)
	for approach: Dictionary in query.defense_approaches:
		if _approach_coverage(query, query.unit, query.unit.current_hex, approach) < MIN_APPROACH_COVERAGE or _approach_coverage(query, query.unit, cell, approach) >= MIN_APPROACH_COVERAGE:
			continue
		var covered_by_other: bool = false
		for friendly: Unit in query.snapshot.positions:
			if HqSupportPositionPolicy.is_headquarters(friendly) or friendly == query.unit or query.snapshot.teams[friendly] != query.team or not InfluenceUnitQuery.is_valid_living_unit(friendly):
				continue
			# A future reservation cannot replace an established defender's covering fire.
			if friendly.movement != null and friendly.movement.is_moving:
				continue
			if query.reservations.has(friendly) and query.reservations[friendly] != query.snapshot.positions[friendly]:
				continue
			if not PositionQueryService.can_follow_intent(friendly) or friendly.broken:
				continue
			if friendly.action_controller != null and friendly.action_controller.action_state in [SquadActionController.SquadActionState.ESTABLISHING_POSITION, SquadActionController.SquadActionState.REGROUPING]:
				continue
			if InfluenceUnitQuery.get_unit_effectiveness(friendly) >= query.profile.withdrawal_effectiveness and _approach_coverage(query, friendly, query.snapshot.positions[friendly], approach) >= MIN_APPROACH_COVERAGE:
				covered_by_other = true
				break
		if not covered_by_other:
			return false
	return true


static func _preserves_branch_screen(query: PositionQuery, cell: Vector2i) -> bool:
	var highest: float = query.defense_area.max_duty_priority()
	var assigned: Dictionary = query.defense_area.branch_for_key(query.assigned_branch)
	if assigned.is_empty():
		assigned = query.defense_area.approach_for_sector(query.assigned_sector)
	for branch: Dictionary in query.defense_area.duties():
		var priority: float = query.defense_area.duty_priority(branch)
		if branch["evidence"] in ["inferred", "estimated"] or priority < highest * 0.4:
			continue
		# A dominant new axis can release a less urgent old front, as in sector planning.
		if not assigned.is_empty() and assigned["id"] != branch["id"] and query.defense_area.duty_priority(assigned) > priority * 1.4:
			continue
		if query.defense_area.combined_coverage(query, query.unit.current_hex, branch) >= MIN_APPROACH_COVERAGE and query.defense_area.combined_coverage(query, cell, branch) < MIN_APPROACH_COVERAGE:
			return false
		if query.defense_area.crossing_zone(query.defense_radius, branch)["total"] > 0.0 and query.defense_area.combined_crossing_coverage(query, query.unit.current_hex, branch) >= DefenseAreaAssessment.MIN_CROSSING_COVERAGE and query.defense_area.combined_crossing_coverage(query, cell, branch) < DefenseAreaAssessment.MIN_CROSSING_COVERAGE:
			return false
	return true


static func needs_withdrawal(query: PositionQuery) -> bool:
	return query.withdrawal_requested or InfluenceUnitQuery.get_unit_effectiveness(query.unit) < query.profile.withdrawal_effectiveness


static func needs_interception(query: PositionQuery, features: Dictionary) -> bool:
	if features.get("responsibility", "") != "cover_approach" or features.get("interposition", 0.0) > 0.0:
		return false
	var distance: int = LOSHelper.get_hex_distance(query.origin_hex, query.objective_hex)
	for contact: InfluenceContact in query.snapshot.get_defensive_contacts(query.team):
		if not contact.observed or not TacticalPositionExecutor.is_active_defender(contact.unit):
			continue
		var enemy_distance: int = LOSHelper.get_hex_distance(contact.hex, query.objective_hex)
		if enemy_distance <= query.defense_radius and enemy_distance < distance:
			return true
	return false


static func can_hold_under_pressure(query: PositionQuery, cell: Vector2i, features: Dictionary) -> bool:
	var capture_guard: bool = features["responsibility"] in ["occupy", "guard"] and query.defense_responsibility != PositionQuery.Responsibility.COVER_APPROACH
	if query.assigned_sector >= 0 and features.get("assigned_coverage", 0.0) < MIN_APPROACH_COVERAGE and not capture_guard:
		return false
	return not needs_withdrawal(query) and cell == query.unit.current_hex and not (query.unit.movement != null and query.unit.movement.is_moving) and InfluenceUnitQuery.get_unit_effectiveness(query.unit) >= query.profile.hold_effectiveness and features["cover"] >= query.profile.minimum_cover and features["responsibility"] != ""


static func allows_route(query: PositionQuery, features: Dictionary) -> bool:
	return features["peak_exposure"] <= query.profile.max_route_exposure and features["exposure_seconds"] <= query.profile.max_exposure_seconds and features["open_exposure_seconds"] <= query.profile.max_open_exposure_seconds


static func handoff_ready(query: PositionQuery, cell: Vector2i, features: Dictionary) -> bool:
	if query.defense_area == null or cell == query.unit.current_hex or query.snapshot.get_defensive_contacts(query.team).is_empty():
		return true
	if not query.handoff_prepared:
		_prepare_handoff(query)
	if query.objective_handoff_required:
		return false
	var area: DefenseAreaAssessment = query.defense_area
	var ready_seconds: float = features.get("route_seconds", INF) + query.profile.establishment_seconds + query.coverage_delay_seconds + HANDOFF_MARGIN_SECONDS
	for requirement: Dictionary in query.handoff_requirements:
		var branch: Dictionary = requirement["branch"]
		# A short redeployment may restore protection before attackers arrive. Future
		# reservations never contribute fire; only this route's verified endpoint does.
		if ready_seconds >= requirement["arrival_seconds"]:
			return false
		if requirement["screen_gap"] and area.combined_coverage(query, cell, branch) < MIN_APPROACH_COVERAGE:
			return false
		if requirement["crossing_gap"] and area.combined_crossing_coverage(query, cell, branch) < DefenseAreaAssessment.MIN_CROSSING_COVERAGE:
			return false
	return true


static func _prepare_handoff(query: PositionQuery) -> void:
	query.handoff_prepared = true
	query.handoff_requirements.clear()
	query.objective_handoff_required = _loses_objective_guard(query)
	var area: DefenseAreaAssessment = query.defense_area
	var highest: float = area.max_duty_priority()
	for branch: Dictionary in area.duties():
		if branch["evidence"] in ["inferred", "estimated"] or area.duty_priority(branch) < highest * 0.4:
			continue
		var remaining: Dictionary = area.established_targets(query, branch)
		var baseline: Dictionary = query.baseline_screen.get(DefenseAreaAssessment.duty_key(branch), {})
		var before: float = area.coverage_of_targets(query.defense_radius, baseline, branch)
		var after: float = area.coverage_of_targets(query.defense_radius, remaining, branch)
		var crossing: Dictionary = area.crossing_zone(query.defense_radius, branch)
		var before_crossing: float = area.crossing_coverage(query.defense_radius, baseline, branch)
		var after_crossing: float = area.crossing_coverage(query.defense_radius, remaining, branch)
		var screen_gap: bool = before >= MIN_APPROACH_COVERAGE and after < MIN_APPROACH_COVERAGE
		var crossing_gap: bool = crossing["total"] > 0.0 and before_crossing >= DefenseAreaAssessment.MIN_CROSSING_COVERAGE and after_crossing < DefenseAreaAssessment.MIN_CROSSING_COVERAGE
		if not screen_gap and not crossing_gap:
			continue
		query.handoff_requirements.append({"branch": branch, "screen_gap": screen_gap, "crossing_gap": crossing_gap,
			"arrival_seconds": crossing.get("arrival_seconds", branch["arrival_seconds"])})


static func _loses_objective_guard(query: PositionQuery) -> bool:
	if not DefenseReadinessJob.established(query.unit, query) or LOSHelper.get_hex_distance(query.unit.current_hex, query.objective_hex) > 1 or not _can_cover(query, query.unit, query.unit.current_hex, query.objective_hex):
		return false
	var imminent: bool = false
	for contact: InfluenceContact in query.snapshot.get_defensive_contacts(query.team):
		imminent = imminent or LOSHelper.get_hex_distance(contact.hex, query.objective_hex) <= 2
	if not imminent:
		return false
	for friendly: Unit in query.snapshot.positions:
		if friendly == query.unit or query.snapshot.teams[friendly] != query.team or not DefenseReadinessJob.established(friendly, query):
			continue
		if query.reservations.get(friendly, friendly.current_hex) != friendly.current_hex:
			continue
		if LOSHelper.get_hex_distance(friendly.current_hex, query.objective_hex) <= 1 and _can_cover(query, friendly, friendly.current_hex, query.objective_hex):
			return false
	return true


static func rejection(query: PositionQuery, cell: Vector2i, features: Dictionary, check_handoff: bool = true) -> String:
	for key: String in query.reserve_response_limits:
		if features.get("reserve_branch_status", {}).get(key, {}).get("response_seconds", INF) > query.reserve_response_limits[key]:
			return "reserve_gap"
	if query.required_crossing_branch != "":
		if features.get("crossing_coverage", 0.0) < DefenseAreaAssessment.MIN_CROSSING_COVERAGE:
			return "crossing_gap"
		if not features.get("objective_connected_cover", false):
			return "objective_access"
	if features["responsibility"] == "":
		return "responsibility"
	if query.defense_area != null and (not is_finite(features["objective_return_seconds"]) or not is_finite(features["return_open_seconds"])):
		return "objective_access"
	if not features["preserves_screen"]:
		return "screen_gap"
	if needs_withdrawal(query) and features["contact_distance"] < PositionFeatureEvaluator.nearest_contact_distance(query.snapshot.get_defensive_contacts(query.team), query.unit.current_hex):
		return "withdrawal_direction"
	if not allows_route(query, features):
		return "exposure_budget"
	if features["incoming"] > query.profile.max_incoming_risk and not can_hold_under_pressure(query, cell, features):
		return "risk"
	if check_handoff and not handoff_ready(query, cell, features):
		return "handoff_wait"
	if check_handoff and query.defense_area != null and not query.relocation_allowed and cell != query.unit.current_hex and not (query.has_accepted_target and query.accepted_context == query.context_key() and cell == query.accepted_target):
		return "handoff_wait"
	return ""
