class_name DefensePlanValidationJob
extends RefCounted

# Recheck live ownership/coverage incrementally, then publish the whole platoon atomically.
var completed: bool = false
var valid: bool = true
var branch_gaps: Array[String] = []
var area: DefenseAreaAssessment
var queries: Array[PositionQuery] = []
var results: Array[DefensePositionResult] = []
var states: Dictionary[Unit, Array] = {}
var index: int = 0
var branch_index: int = 0
var unit_index: int = 0
var branches: Array[Dictionary] = []
var positions: Dictionary[Unit, Vector2i] = {}
var units: Array[Unit] = []
var visible: Dictionary = {}
var highest_priority: float = 0.0
var warming_index: int = -1
var support_duties: Array[Dictionary] = []
var support_units: Array[Unit] = []
var support_index: int = 0
var support_unit_index: int = 0
var cleanup_index: int = 0


func start(assessment: DefenseAreaAssessment, requests: Array[Dictionary], advice: Array[DefensePositionResult]) -> void:
	area = assessment
	results = advice.duplicate()
	for request: Dictionary in requests:
		queries.append(request["query"])
	if queries.is_empty():
		completed = true
		return
	for unit: Unit in queries[0].snapshot.positions:
		if queries[0].snapshot.teams[unit] == queries[0].team and is_instance_valid(unit):
			states[unit] = _state(unit)
			if unit.alive and (unit.movement == null or not unit.movement.is_moving):
				positions[unit] = unit.current_hex
	for result_index: int in range(results.size()):
		var unit: Unit = queries[result_index].unit
		if results[result_index].is_valid():
			positions[unit] = results[result_index].target_hex
		elif InfluenceUnitQuery.is_valid_living_unit(unit):
			positions[unit] = unit.current_hex
	units.assign(positions.keys())
	if area != null:
		branches = area.duties()
		highest_priority = area.max_duty_priority()


func advance(deadline_usec: int) -> void:
	if not unchanged():
		valid = false
		completed = true
		return
	while not completed and (deadline_usec < 0 or Time.get_ticks_usec() < deadline_usec):
		if index < queries.size():
			var query: PositionQuery = queries[index]
			var result: DefensePositionResult = results[index]
			if not InfluenceUnitQuery.is_valid_living_unit(query.unit) or query.origin_hex != query.unit.current_hex or result.context != query.context_key():
				valid = false
				completed = true
				return
			if result.is_valid() and query.profile.mode == PositionProfile.Mode.DEFEND:
				if warming_index != index:
					warming_index = index
					query.firepower_by_unit.clear()
					query.sector_features.clear()
					query.established_screen.clear()
					query.support_fire_by_branch.clear()
					support_duties = []
					if query.defense_area != null:
						support_duties = query.defense_area.support_duties(query)
					support_units.assign(query.snapshot.positions.keys())
					support_index = 0
					support_unit_index = 0
				if support_index < support_duties.size():
					var duty: Dictionary = support_duties[support_index]
					if support_unit_index < support_units.size():
						query.defense_area.warm_support(query, duty, support_units[support_unit_index])
						support_unit_index += 1
					else:
						query.defense_area.warm_support(query, duty, null)
						support_unit_index = 0
						support_index += 1
					continue
				var protection: Dictionary = DefensePositionPolicy.evaluate(query, result.target_hex)
				if protection["responsibility"] == "" or not protection["preserves_screen"]:
					valid = false
					completed = true
					return
			index += 1
		elif branch_index < branches.size():
			var branch: Dictionary = branches[branch_index]
			if unit_index < units.size():
				var unit: Unit = units[unit_index]
				if InfluenceUnitQuery.is_valid_living_unit(unit) and PositionQueryService.can_follow_intent(unit) and not unit.broken and InfluenceUnitQuery.get_unit_effectiveness(unit) >= queries[0].profile.withdrawal_effectiveness:
					visible.merge(area.coverage(queries[0], unit, positions[unit], branch)["visible_targets"])
				unit_index += 1
			else:
				if area.duty_priority(branch) >= highest_priority * 0.4 and area.coverage_of_targets(queries[0].defense_radius, visible, branch) < DefensePositionPolicy.MIN_APPROACH_COVERAGE and not _reserve_can_intercept(DefenseAreaAssessment.duty_key(branch)):
					branch_gaps.append(DefenseAreaAssessment.duty_key(branch))
				visible = {}
				unit_index = 0
				branch_index += 1
		elif cleanup_index < queries.size():
			# Releasing every flood field/candidate cache in the publication frame causes a spike.
			var query: PositionQuery = queries[cleanup_index]
			query.destination_features.clear()
			query.sector_features.clear()
			query.route_field = null
			query.support_fire_by_branch.clear()
			query.established_screen.clear()
			cleanup_index += 1
		else:
			valid = unchanged()
			completed = true


func unchanged() -> bool:
	for unit: Unit in states:
		if not is_instance_valid(unit) or states[unit] != _state(unit):
			return false
	return true


func _reserve_can_intercept(key: String) -> bool:
	for result_index: int in range(results.size()):
		if queries[result_index].reserve_position and results[result_index].is_valid() and DefenseSectorAllocator.combat_reserve_capable(queries[result_index].unit):
			var status: Dictionary = results[result_index].features.get("reserve_branch_status", {}).get(key, {})
			if not status.is_empty() and status["response_seconds"] <= status["arrival_seconds"]:
				return true
	return false


static func _state(unit: Unit) -> Array:
	var state: Array = [unit.alive, unit.current_hex, unit.members_alive, unit.surrendered, unit.broken, unit.in_close_combat,
		InfluenceUnitQuery.get_defensive_mount(unit), InfluenceUnitQuery.get_unit_range(unit), InfluenceUnitQuery.get_unit_effectiveness(unit)]
	if unit.movement != null:
		state.append_array([unit.movement.is_moving, unit.movement.target_hex])
	if unit.action_controller != null:
		state.append_array([unit.action_controller.action_order_id, unit.action_controller.action_state])
	# Weapon transfers, jams, exhaustion and casualties can remove an established firing lane.
	if unit.squad_fire != null:
		for soldier: Soldier in unit.squad_fire.soldiers:
			state.append_array([soldier.is_alive, soldier.weapon, soldier.jammed])
			if soldier.weapon != null:
				state.append(soldier.weapon.ammunition > 0)
	else:
		state.append(unit.firepower)
	return state
