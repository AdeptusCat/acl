class_name DefenseReadinessJob
extends RefCounted

# Advisory response routes end at covered cells that can actually intercept this branch.
# All work is incremental. Hidden intelligence supplies sector pressure, never transit danger.
enum Phase { COVERAGE, TARGETS, FIELD, RESPONSES, FINISH }

const WATCH_SECONDS: float = 12.0
const ESTIMATED_WATCH_SECONDS: float = 20.0
const WATCH_MEMORY_SECONDS: float = 8.0

var completed: bool = false
var area: DefenseAreaAssessment
var query: PositionQuery
var reserve: Unit
var units: Array[Unit] = []
var branches: Array[Dictionary] = []
var coverage: Dictionary[String, float] = {}
var responses: Dictionary[String, Dictionary] = {}
var emergency: String = ""
var watch_branch: String = ""
var phase: Phase = Phase.COVERAGE
var branch_index: int = 0
var unit_index: int = 0
var cell_index: int = 0
var visible: Dictionary = {}
var established_targets: Dictionary[String, Dictionary] = {}
var targets: Array[Vector2i] = []
var response_origins: Array[Vector2i] = []
var field: DefenseTravelField
var steps: Dictionary[Vector2i, Dictionary] = {}
var reserve_capability: String = ""


func start(assessment: DefenseAreaAssessment, snapshot: InfluenceSnapshot, team: int, defenders: Array[Unit], mobile_reserve: Unit, radius: int) -> void:
	area = assessment
	reserve = mobile_reserve
	if reserve != null:
		reserve_capability = capability_key(reserve)
		# Advice only accepts covered destinations; the live origin also needs a response estimate.
		response_origins = area.covered_positions.duplicate()
		if not response_origins.has(reserve.current_hex):
			response_origins.append(reserve.current_hex)
	units = defenders.duplicate()
	branches = area.duties()
	query = PositionQuery.new()
	query.unit = reserve
	if query.unit == null and not units.is_empty():
		query.unit = units[0]
	query.team = team
	query.objective_hex = area.objective_hex
	query.defense_radius = radius
	query.snapshot = snapshot
	query.defense_area = area
	query.forecast_data = snapshot.get_forecast_data(team, area.objective_hex)
	if query.unit == null or not area.geometry.has("cells"):
		completed = true


func advance(deadline_usec: int) -> void:
	while not completed and (deadline_usec < 0 or Time.get_ticks_usec() < deadline_usec):
		if branch_index >= branches.size():
			phase = Phase.FINISH
		match phase:
			Phase.COVERAGE:
				var branch: Dictionary = branches[branch_index]
				if unit_index < units.size():
					var unit: Unit = units[unit_index]
					# The reserve's own protection must not justify committing additional squads.
					if unit != reserve and established(unit, query):
						visible.merge(area.coverage(query, unit, unit.current_hex, branch)["visible_targets"])
					unit_index += 1
				else:
					var key: String = DefenseAreaAssessment.duty_key(branch)
					established_targets[key] = visible
					coverage[key] = area.protection_of_targets(query.defense_radius, visible, branch)
					visible = {}
					unit_index = 0
					if reserve == null or not credible(area, branch):
						branch_index += 1
					else:
						var zone: Dictionary = area.crossing_zone(query.defense_radius, branch)
						responses[key] = {"seconds": {}, "arrival_seconds": zone["arrival_seconds"], "objective_arrival_seconds": branch["arrival_seconds"], "crossing": zone["total"] > 0.0, "has_intercept": false, "weight": maxf(0.15, area.duty_priority(branch)), "covered": coverage[key] >= DefensePositionPolicy.MIN_APPROACH_COVERAGE}
						if responses[key]["covered"]:
							# Existing coverage needs no reserve route. It is rechecked at publication.
							branch_index += 1
						else:
							cell_index = 0
							targets = []
							phase = Phase.TARGETS
			Phase.TARGETS:
				var branch: Dictionary = branches[branch_index]
				var data: Dictionary = responses[DefenseAreaAssessment.duty_key(branch)]
				var connected_required: bool = data["crossing"] and data["arrival_seconds"] <= _watch_window(branch) and _watch_evidence(branch)
				if cell_index < area.covered_positions.size():
					var cell: Vector2i = area.covered_positions[cell_index]
					var combined: Dictionary = established_targets[DefenseAreaAssessment.duty_key(branch)].duplicate()
					combined.merge(area.coverage(query, reserve, cell, branch)["visible_targets"])
					if area.geometry["objective_distances"].has(cell) and area.geometry["return_open_costs"].has(cell) and (not connected_required or area.geometry["return_open_costs"].get(cell, INF) <= 0.000001) and _free_destination(cell) and area.coverage(query, reserve, cell, branch)["coverage"] >= DefensePositionPolicy.MIN_APPROACH_COVERAGE and area.crossing_coverage(query.defense_radius, combined, branch) >= DefenseAreaAssessment.MIN_CROSSING_COVERAGE and _step(cell)["risk"] <= query.profile.max_route_exposure:
						targets.append(cell)
					cell_index += 1
				else:
					responses[DefenseAreaAssessment.duty_key(branch)]["has_intercept"] = not targets.is_empty()
					field = DefenseTravelField.new()
					field.start_sources(area.geometry, targets, true)
					phase = Phase.FIELD
			Phase.FIELD:
				field.advance(deadline_usec)
				if field.completed:
					cell_index = 0
					phase = Phase.RESPONSES
			Phase.RESPONSES:
				if cell_index < response_origins.size():
					var cell: Vector2i = response_origins[cell_index]
					responses[DefenseAreaAssessment.duty_key(branches[branch_index])]["seconds"][cell] = _response_seconds(cell)
					cell_index += 1
				else:
					field = null
					branch_index += 1
					phase = Phase.COVERAGE
			Phase.FINISH:
				emergency = _emergency_reason()
				watch_branch = _watch_branch()
				query.sector_features.clear()
				completed = true


static func capability_key(unit: Unit) -> String:
	if not InfluenceUnitQuery.is_valid_living_unit(unit):
		return "unavailable"
	var usable_ranges: Array[bool] = []
	for distance: int in range(InfluenceUnitQuery.get_unit_range(unit) + 1):
		usable_ranges.append(InfluenceUnitQuery.get_firepower_at_range(unit, distance) > 0.0)
	return str([DefenseSectorAllocator.combat_reserve_capable(unit), InfluenceUnitQuery.captured_crossing_seconds(unit), usable_ranges])


static func established(unit: Unit, request: PositionQuery) -> bool:
	if not InfluenceUnitQuery.is_valid_living_unit(unit) or not PositionQueryService.can_follow_intent(unit) or unit.broken or InfluenceUnitQuery.get_unit_effectiveness(unit) < request.profile.hold_effectiveness:
		return false
	if request.snapshot.positions.get(unit, Vector2i(-999, -999)) != unit.current_hex or (unit.movement != null and unit.movement.is_moving):
		return false
	return unit.action_controller == null or unit.action_controller.action_state not in [SquadActionController.SquadActionState.ESTABLISHING_POSITION, SquadActionController.SquadActionState.REGROUPING]


static func credible(assessment: DefenseAreaAssessment, branch: Dictionary) -> bool:
	return assessment.duty_priority(branch) >= 0.03 and not branch.get("cells", []).is_empty()


func _free_destination(cell: Vector2i) -> bool:
	var ids: Dictionary = query.snapshot.point_ids.get(query.team, {})
	if not ids.has(cell) or query.snapshot.routes[query.team].is_point_disabled(ids[cell]):
		return false
	for unit: Unit in query.snapshot.positions:
		if unit != reserve and query.snapshot.teams[unit] == query.team and query.snapshot.positions[unit] == cell:
			return false
	return true


func _step(cell: Vector2i) -> Dictionary:
	if not steps.has(cell):
		steps[cell] = PositionFeatureEvaluator.route_step(query, cell)
	return steps[cell]


func _response_seconds(origin: Vector2i) -> float:
	if not field.distances.has(origin):
		return INF
	var cell: Vector2i = origin
	var seconds: float = query.profile.establishment_seconds
	if targets.has(origin) and (origin != reserve.current_hex or established(reserve, query)):
		seconds = 0.0
	var exposure: float = 0.0
	var open_exposure: float = 0.0
	var ids: Dictionary = query.snapshot.point_ids[query.team]
	while field.next_cells.has(cell):
		var next: Vector2i = field.next_cells[cell]
		if query.snapshot.routes[query.team].is_point_disabled(ids[next]):
			return INF
		var step: Dictionary = _step(next)
		var crossing: float = PositionFeatureEvaluator.crossing_seconds(query, cell, next)
		seconds += crossing
		exposure += step["risk"] * crossing
		if step["cover"] < query.profile.minimum_cover:
			open_exposure += step["risk"] * crossing
		if step["risk"] > query.profile.max_route_exposure or exposure > query.profile.max_exposure_seconds or open_exposure > query.profile.max_open_exposure_seconds:
			return INF
		cell = next
	return seconds


func _watch_branch() -> String:
	if not DefenseSectorAllocator.combat_reserve_capable(reserve):
		return ""
	var selected: String = ""
	var highest: float = -INF
	for branch: Dictionary in branches:
		var key: String = DefenseAreaAssessment.duty_key(branch)
		var data: Dictionary = responses.get(key, {})
		if data.is_empty() or not data["crossing"] or data["covered"] or not data["has_intercept"] or data["arrival_seconds"] > _watch_window(branch):
			continue
		if not _watch_evidence(branch):
			continue
		var urgency: float = area.duty_priority(branch) / (1.0 + data["arrival_seconds"])
		if urgency > highest:
			selected = key
			highest = urgency
	return selected


func _watch_evidence(branch: Dictionary) -> bool:
	if branch.get("evidence", "inferred") == "observed":
		return true
	if branch.get("evidence", "inferred") == "estimated":
		return area.duty_priority(branch) >= 0.12
	return branch.get("evidence", "inferred") == "remembered" and query.snapshot.captured_at - branch.get("last_seen_at", -INF) <= WATCH_MEMORY_SECONDS


func _watch_window(branch: Dictionary) -> float:
	if branch.get("evidence", "inferred") == "estimated":
		return ESTIMATED_WATCH_SECONDS
	return WATCH_SECONDS


func _emergency_reason() -> String:
	var failing: bool = false
	for unit: Unit in units:
		if unit != reserve and unit.squad_type not in [Globals.SquadType.PLATOON_HEADQUARTERS, Globals.SquadType.COMPANY_HEADQUARTERS, Globals.SquadType.MORTAR]:
			failing = failing or unit.broken or InfluenceUnitQuery.get_unit_effectiveness(unit) < query.profile.hold_effectiveness or InfluenceUnitQuery.get_unit_firepower(unit) <= 0.0
	for contact: InfluenceContact in query.snapshot.get_contacts(query.team):
		if not contact.observed:
			continue
		if LOSHelper.get_hex_distance(contact.hex, area.objective_hex) <= 1:
			return "imminent_breach"
	for branch: Dictionary in branches:
		var key: String = DefenseAreaAssessment.duty_key(branch)
		if branch.get("evidence", "inferred") != "observed" or area.duty_priority(branch) < area.max_duty_priority() * 0.4 or branch["arrival_seconds"] > 12.0 or coverage.get(key, 0.0) >= DefensePositionPolicy.MIN_APPROACH_COVERAGE:
			continue
		if failing:
			return "failing_defense"
		if reserve != null:
			var response: float = responses.get(key, {}).get("seconds", {}).get(reserve.current_hex, INF)
			if is_finite(response) and branch["arrival_seconds"] <= response + 2.0:
				return "imminent_breach"
	return ""
