class_name DefensePositionPolicy
extends RefCounted

# Mission responsibility is evaluated separately from travel safety and cover quality.
const MIN_APPROACH_COVERAGE: float = 0.5


static func prepare(query: PositionQuery) -> void:
	query.defense_approaches.clear()
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
	for approach: Dictionary in query.defense_approaches:
		var coverage: float = _approach_coverage(query, query.unit, cell, approach)
		blocking += coverage
		approach_covered = approach_covered or coverage >= MIN_APPROACH_COVERAGE
		if coverage >= MIN_APPROACH_COVERAGE:
			covered_approaches += 1
		var enemy_distance: int = LOSHelper.get_hex_distance(query.objective_hex, approach["source"])
		var detour: int = distance + LOSHelper.get_hex_distance(cell, approach["source"]) - enemy_distance
		if distance <= enemy_distance and detour <= 1:
			interposition = maxf(interposition, 1.0 - 0.5 * float(maxi(detour, 0)))
	if not query.defense_approaches.is_empty():
		blocking /= float(query.defense_approaches.size())
	var responsibility: String = ""
	if cell == query.objective_hex:
		responsibility = "occupy"
	elif guard:
		responsibility = "guard"
	elif approach_covered:
		responsibility = "cover_approach"
	if query.defense_responsibility == PositionQuery.Responsibility.OCCUPY and cell != query.objective_hex:
		responsibility = ""
	elif query.defense_responsibility == PositionQuery.Responsibility.GUARD and not guard and cell != query.objective_hex:
		responsibility = ""
	elif query.defense_responsibility == PositionQuery.Responsibility.COVER_APPROACH and not approach_covered:
		responsibility = ""
	return {"responsibility": responsibility, "blocking": blocking, "interposition": interposition,
		"covered_approaches": covered_approaches, "approach_count": query.defense_approaches.size(),
		"preserves_screen": _preserves_screen(query, cell), "withdrawal": needs_withdrawal(query)}


static func _can_cover(query: PositionQuery, unit: Unit, from: Vector2i, target: Vector2i) -> bool:
	if from == target:
		return true
	return query.snapshot.los.get(from, {}).has(target) and query.firepower_at_range(unit, LOSHelper.get_hex_distance(from, target)) > 0.0


static func _approach_coverage(query: PositionQuery, unit: Unit, cell: Vector2i, approach: Dictionary) -> float:
	var covered: int = 0
	for target: Vector2i in approach["cells"]:
		if _can_cover(query, unit, cell, target):
			covered += 1
	return float(covered) / float(maxi(approach["cells"].size(), 1))


static func _preserves_screen(query: PositionQuery, cell: Vector2i) -> bool:
	if cell == query.unit.current_hex:
		return true
	for approach: Dictionary in query.defense_approaches:
		if _approach_coverage(query, query.unit, query.unit.current_hex, approach) < MIN_APPROACH_COVERAGE or _approach_coverage(query, query.unit, cell, approach) >= MIN_APPROACH_COVERAGE:
			continue
		var covered_by_other: bool = false
		for friendly: Unit in query.snapshot.positions:
			if friendly == query.unit or query.snapshot.teams[friendly] != query.team or not InfluenceUnitQuery.is_valid_living_unit(friendly):
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


static func needs_withdrawal(query: PositionQuery) -> bool:
	return query.withdrawal_requested or InfluenceUnitQuery.get_unit_effectiveness(query.unit) < query.profile.withdrawal_effectiveness


static func can_hold_under_pressure(query: PositionQuery, cell: Vector2i, features: Dictionary) -> bool:
	return not needs_withdrawal(query) and cell == query.unit.current_hex and not (query.unit.movement != null and query.unit.movement.is_moving) and InfluenceUnitQuery.get_unit_effectiveness(query.unit) >= query.profile.hold_effectiveness and features["cover"] >= query.profile.minimum_cover and features["responsibility"] != ""


static func allows_route(query: PositionQuery, features: Dictionary) -> bool:
	return features["peak_exposure"] <= query.profile.max_route_exposure and features["exposure_seconds"] <= query.profile.max_exposure_seconds and features["open_exposure_seconds"] <= query.profile.max_open_exposure_seconds


static func rejection(query: PositionQuery, cell: Vector2i, features: Dictionary) -> String:
	if features["responsibility"] == "":
		return "responsibility"
	if not features["preserves_screen"]:
		return "screen_gap"
	if needs_withdrawal(query) and features["contact_distance"] < PositionFeatureEvaluator.nearest_contact_distance(query.snapshot.get_defensive_contacts(query.team), query.unit.current_hex):
		return "withdrawal_direction"
	if not allows_route(query, features):
		return "exposure_budget"
	if features["incoming"] > query.profile.max_incoming_risk and not can_hold_under_pressure(query, cell, features):
		return "risk"
	return ""
