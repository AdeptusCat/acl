class_name PlatoonAI
extends Node

@export var reconsider_interval: float = 1.0
@export var team: Globals.Team = Globals.Team.AXIS
@export var influence_map_controller: InfluenceMapController

var squads: Array[Unit] = []
var active: bool = true
var current_order: MissionOrder = null
var squad_assignments: Dictionary = {}
var reserved_hexes_by_squad: Dictionary = {}
var accepted_positions: Dictionary = {}
var time_until_reconsider: float = 0.0
var executor: TacticalPositionExecutor = TacticalPositionExecutor.new()
var _planning_requests: Array[Dictionary] = []
var _planning_results: Array[DefensePositionResult] = []
var _planning_reservations: Dictionary = {}
var _planning_job: PositionQueryJob
var _planning_index: int = 0
var defense_area: DefenseAreaAssessment
var defense_gaps: Array[int] = []
var defense_branch_gaps: Array[String] = []
var _area_job: DefenseAreaJob
var _planning_available: Array[Unit] = []
var _relocation_claimed: bool = false
var _planning_snapshot: InfluenceSnapshot
var _validation_job: DefensePlanValidationJob
var _readiness_job: DefenseReadinessJob
var _planning_readiness: DefenseReadinessJob
var reserve_squad: Unit
var reserve_deployed: bool = false
var reserve_reason: String = ""
var _reserve_quiet_since: float = -INF

const RESERVE_RECOVERY_SECONDS: float = 8.0


func _process(delta: float) -> void:
	if not active or current_order == null:
		return
	if _readiness_job != null:
		if _readiness_job.area.objective_hex != current_order.objective_hex:
			_cancel_plan()
			time_until_reconsider = 0.0
			return
		_readiness_job.advance(Time.get_ticks_usec() + InfluenceMapController.POSITION_QUERY_BUDGET_USEC)
		if _readiness_job.completed:
			_planning_readiness = _readiness_job
			_readiness_job = null
			_area_job = null
			_build_planning_requests(_planning_available)
			if not _planning_requests.is_empty():
				_submit_planning_query()
			else:
				_commit_plan()
		return
	if _area_job != null:
		if _area_job.objective != current_order.objective_hex:
			_cancel_plan()
			time_until_reconsider = 0.0
			return
		if _area_job.completed:
			defense_area = _area_job.result
			_prepare_readiness(true)
		return
	if _validation_job != null:
		_validation_job.advance(Time.get_ticks_usec() + InfluenceMapController.POSITION_QUERY_BUDGET_USEC)
		if _validation_job.completed:
			if _validation_job.valid:
				_commit_plan()
			else:
				_cancel_plan()
				time_until_reconsider = 0.0
		return
	if _planning_job != null:
		_continue_budgeted_plan()
		return
	time_until_reconsider -= delta
	if time_until_reconsider <= 0.0:
		time_until_reconsider = reconsider_interval
		_start_plan(true)


func _exit_tree() -> void:
	_cancel_plan()
	_set_mission_control(false)
	executor.cancel_all()


func set_active(is_active: bool) -> void:
	_cancel_plan()
	active = is_active
	if active:
		_set_mission_control(current_order != null)
		return
	_set_mission_control(false)
	_clear_reserve()
	# Release only actions owned by this planner when handing control to the player.
	executor.cancel_all(true)
	current_order = null
	squad_assignments.clear()
	reserved_hexes_by_squad.clear()
	accepted_positions.clear()
	defense_area = null
	defense_gaps.clear()
	defense_branch_gaps.clear()
	time_until_reconsider = 0.0


func receive_mission_order(order: MissionOrder) -> void:
	if not active:
		return
	_cancel_plan()
	_clear_reserve()
	executor.cancel_all(true)
	accepted_positions.clear()
	current_order = order
	_set_mission_control(true)
	time_until_reconsider = reconsider_interval
	_start_plan(is_inside_tree())


func set_squads(new_squads: Array[Unit]) -> void:
	var owned: Array[Unit] = []
	for squad: Unit in new_squads:
		if InfluenceUnitQuery.is_valid_living_unit(squad) and squad.team == team and not owned.has(squad):
			owned.append(squad)
	_cancel_plan()
	_clear_reserve()
	_set_mission_control(false)
	executor.cancel_all(true)
	squad_assignments.clear()
	reserved_hexes_by_squad.clear()
	accepted_positions.clear()
	defense_area = null
	defense_gaps.clear()
	defense_branch_gaps.clear()
	time_until_reconsider = 0.0
	squads = owned
	_set_mission_control(active and current_order != null)


func _set_mission_control(enabled: bool) -> void:
	for squad: Unit in squads:
		if not is_instance_valid(squad):
			continue
		squad.ai_support_only = enabled and HqSupportPositionPolicy.is_headquarters(squad)
		if squad.ai_support_only and squad.squad_fire != null:
			squad.squad_fire.clear_target()
		if squad.squad_ai_controller != null:
			squad.squad_ai_controller.defensive_mission_controlled = enabled and current_order != null and current_order.position_mode == PositionProfile.Mode.DEFEND


func bind_active_squads(active_units: Array[Unit]) -> void:
	# Each match supplies its complete runtime roster; squad numbers do not gate ownership.
	set_squads(active_units)


func reconsider_assignments() -> void:
	_start_plan(false)


func _start_plan(budgeted: bool) -> void:
	_cancel_plan()
	if not active or current_order == null or influence_map_controller == null:
		return
	influence_map_controller.set_objective_for_team(team, current_order.objective_hex)
	if influence_map_controller.snapshot == null:
		return
	var available: Array[Unit] = _get_effective_squads()
	for unit: Unit in accepted_positions.keys():
		if not available.has(unit):
			accepted_positions.erase(unit)
			executor.cancel(unit)
	_planning_reservations = _create_current_reserved_hexes(available)
	_planning_available = available
	_planning_snapshot = influence_map_controller.snapshot
	_reset_relocation(available)
	if current_order.position_mode == PositionProfile.Mode.DEFEND:
		_area_job = influence_map_controller.request_defense_area(team, current_order.objective_hex, current_order.defense_area_radius, current_order.approach_analysis_radius, current_order.threat_axes)
		if budgeted and not _area_job.completed:
			return
		_area_job.advance(-1)
		defense_area = _area_job.result
		_prepare_readiness(budgeted)
		if budgeted:
			return
	_build_planning_requests(available)
	if budgeted and not _planning_requests.is_empty():
		_submit_planning_query()
		return
	for request: Dictionary in _planning_requests:
		var query: PositionQuery = request["query"]
		query.relocation_allowed = _can_relocate(query.unit)
		_accept_planning_result(request, PositionQueryService.query_positions(query))
	_commit_plan()


func _prepare_readiness(budgeted: bool) -> void:
	var available: Array[Unit] = _combat_units(_planning_available)
	var reserve: Unit = null
	if current_order.defense_responsibility == PositionQuery.Responsibility.AUTO and available.size() >= 2:
		available.erase(_select_guard_squad(available))
	if _can_keep_reserve(_planning_available):
		reserve = _select_reserve_squad(available)
	_readiness_job = DefenseReadinessJob.new()
	_readiness_job.start(defense_area, _planning_snapshot, team, _combat_units(_planning_available), reserve, current_order.defense_radius)
	_readiness_job.query.profile.max_exposure_seconds = current_order.exposure_budget_seconds
	_readiness_job.query.profile.max_open_exposure_seconds = current_order.open_crossing_budget_seconds
	if not budgeted:
		_readiness_job.advance(-1)
		_planning_readiness = _readiness_job
		_readiness_job = null
		_area_job = null


func _can_keep_reserve(available: Array[Unit]) -> bool:
	if current_order.reserve_policy == MissionOrder.ReservePolicy.NONE:
		return false
	if current_order.reserve_policy == MissionOrder.ReservePolicy.KEEP_HQ_NEAR_OBJECTIVE:
		return false
	var combat_count: int = 0
	for unit: Unit in available:
		if DefenseSectorAllocator.combat_reserve_capable(unit):
			combat_count += 1
	return combat_count >= 3


func _clear_reserve() -> void:
	reserve_squad = null
	reserve_deployed = false
	reserve_reason = ""
	_reserve_quiet_since = -INF


func _combat_units(available: Array[Unit]) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit: Unit in available:
		if not HqSupportPositionPolicy.is_headquarters(unit):
			result.append(unit)
	return result


func _add_support_requests(available: Array[Unit]) -> void:
	for unit: Unit in available:
		if HqSupportPositionPolicy.is_headquarters(unit):
			var config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, current_order.objective_hex, current_order, accepted_positions)
			_add_planning_requests(config, [unit], "hq_support", null)


func _build_planning_requests(available: Array[Unit]) -> void:
	_build_combat_planning_requests(_combat_units(available))
	_add_support_requests(available)


func _build_combat_planning_requests(available: Array[Unit]) -> void:
	if available.is_empty():
		return
	if current_order.position_mode == PositionProfile.Mode.DEFEND and defense_area != null:
		_build_sector_requests(available.duplicate())
		return
	if current_order.position_mode != PositionProfile.Mode.DEFEND and current_order.position_mode != PositionProfile.Mode.LEGACY_DEFENSE:
		var config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, current_order.objective_hex, current_order, accepted_positions)
		for unit: Unit in available:
			_add_planning_requests(config, [unit], "offense", null)
		return
	var can_reserve: bool = current_order.reserve_policy != MissionOrder.ReservePolicy.NONE and available.size() >= 3
	if current_order.position_mode == PositionProfile.Mode.DEFEND and current_order.defense_responsibility == PositionQuery.Responsibility.AUTO and available.size() >= 2:
		var guard: Unit = _select_guard_squad(available)
		available.erase(guard)
		var guard_config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, current_order.objective_hex, current_order, accepted_positions)
		guard_config.defense_responsibility = PositionQuery.Responsibility.GUARD
		_add_planning_requests(guard_config, [guard], "guard_objective", null)
	if can_reserve:
		var reserve: Unit = _select_reserve_squad(available)
		if reserve != null:
			available.erase(reserve)
			var reserve_config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, current_order.objective_hex, current_order, accepted_positions)
			reserve_config.defense_radius = 2
			reserve_config.profile.firing_weight = 0.0
			reserve_config.defense_responsibility = PositionQuery.Responsibility.GUARD
			_add_planning_requests(reserve_config, [reserve], "reserve", null)
	var axes: Array[ThreatAxis] = _get_sorted_threat_axes()
	if axes.is_empty():
		var config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, current_order.objective_hex, current_order, accepted_positions)
		_add_planning_requests(config, available, "defend_objective", null)
	else:
		var assignments: Dictionary = _distribute_squads_over_axes(available, axes)
		for axis: ThreatAxis in axes:
			var config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, current_order.objective_hex, current_order, accepted_positions)
			config.threat_axis = axis
			_add_planning_requests(config, assignments[axis], "defend_axis", axis)


func _reset_relocation(available: Array[Unit]) -> void:
	_relocation_claimed = false
	for unit: Unit in available:
		if HqSupportPositionPolicy.is_headquarters(unit):
			continue
		if (unit.movement != null and unit.movement.is_moving) or (unit.action_controller != null and unit.action_controller.action_state in [SquadActionController.SquadActionState.ESTABLISHING_POSITION, SquadActionController.SquadActionState.REGROUPING]):
			_relocation_claimed = true


func _can_relocate(unit: Unit) -> bool:
	# A moving defender must be able to finish or redirect to cover after its duty changes.
	return HqSupportPositionPolicy.is_headquarters(unit) or not _relocation_claimed or (unit.movement != null and unit.movement.is_moving)


func _build_sector_requests(available: Array[Unit]) -> void:
	_build_combat_sector_requests(_combat_units(available))
	_add_support_requests(available)


func _build_combat_sector_requests(available: Array[Unit]) -> void:
	if available.is_empty():
		_clear_reserve()
		return
	if current_order.defense_responsibility in [PositionQuery.Responsibility.OCCUPY, PositionQuery.Responsibility.GUARD]:
		for unit: Unit in available:
			_add_sector_request(unit, "guard_objective", -1, current_order.defense_responsibility)
		return
	var reserve: Unit = null
	var has_guard: bool = false
	var can_reserve: bool = _can_keep_reserve(available)
	if current_order.defense_responsibility == PositionQuery.Responsibility.AUTO and available.size() >= 2:
		var guard: Unit = _select_guard_squad(available)
		available.erase(guard)
		_add_sector_request(guard, "guard_objective", -1, PositionQuery.Responsibility.GUARD)
		has_guard = true
	if can_reserve:
		reserve = _select_reserve_squad(available)
		if reserve != null:
			reserve_squad = reserve
			available.erase(reserve)
			_update_reserve_state()
			if reserve_deployed:
				available.append(reserve)
				reserve = null
		else:
			_clear_reserve()
	else:
		_clear_reserve()
	var previous: Dictionary = {}
	for unit: Unit in squad_assignments:
		previous[unit] = {"sector": squad_assignments[unit]["result"].features.get("assigned_sector", -1), "branch": squad_assignments[unit]["result"].features.get("assigned_branch", "")}
	var coverage: Dictionary[String, float] = {}
	var previous_watch: String = ""
	if reserve != null and squad_assignments.has(reserve):
		previous_watch = squad_assignments[reserve]["result"].features.get("required_crossing_branch", "")
	if _planning_readiness != null:
		coverage = _planning_readiness.coverage.duplicate()
		var watch_response: Dictionary = _planning_readiness.responses.get(previous_watch, {})
		if reserve != null and not watch_response.is_empty() and watch_response["seconds"].get(reserve.current_hex, INF) == 0.0:
			# The retained reserve's established fire reduces demand, unlike a future response promise.
			coverage[previous_watch] = DefensePositionPolicy.MIN_APPROACH_COVERAGE
	var assignments: Dictionary[Unit, String] = DefenseSectorAllocator.assign_branches(defense_area, available, previous, coverage)
	var reserve_requested: bool = false
	if _planning_readiness != null:
		if reserve != null and _planning_readiness.emergency == "":
			var failed_duties: Dictionary[Unit, String] = {}
			for unit: Unit in available:
				if squad_assignments.has(unit):
					var prior_result: DefensePositionResult = squad_assignments[unit]["result"]
					if not prior_result.is_valid() and not prior_result.cell_states.has(PositionResult.CellState.WAITING_HANDOFF):
						failed_duties[unit] = prior_result.features.get("assigned_branch", "")
			_planning_readiness.watch_branch = _planning_readiness.select_watch(assignments, previous_watch, failed_duties)
		if _planning_readiness.watch_branch != "":
			var watch: Dictionary = defense_area.branch_for_key(_planning_readiness.watch_branch)
			if reserve != null:
				# Duty selection follows front allocation; urgent execution still precedes optional moves.
				_add_sector_request(reserve, "reserve", watch["id"], PositionQuery.Responsibility.AUTO, DefenseAreaAssessment.duty_key(watch))
				reserve_requested = true
			elif reserve_deployed and available.has(reserve_squad):
				available.erase(reserve_squad)
				assignments.erase(reserve_squad)
				_add_sector_request(reserve_squad, "defend_sector", watch["id"], PositionQuery.Responsibility.COVER_APPROACH, DefenseAreaAssessment.duty_key(watch))
	for approach: Dictionary in DefenseSectorAllocator.branch_priorities(defense_area):
		for unit: Unit in available:
			if assignments.get(unit, "") == DefenseAreaAssessment.duty_key(approach):
				var responsibility: PositionQuery.Responsibility = current_order.defense_responsibility
				if responsibility == PositionQuery.Responsibility.AUTO and has_guard:
					responsibility = PositionQuery.Responsibility.COVER_APPROACH
				_add_sector_request(unit, "defend_sector", approach["id"], responsibility, DefenseAreaAssessment.duty_key(approach))
	if assignments.is_empty():
		for unit: Unit in available:
			_add_sector_request(unit, "defend_objective", -1, current_order.defense_responsibility)
	if reserve != null and not reserve_requested:
		_add_sector_request(reserve, "reserve", -1, PositionQuery.Responsibility.AUTO)


func _update_reserve_state() -> void:
	var emergency: String = ""
	if _planning_readiness != null:
		emergency = _planning_readiness.emergency
	if current_order.reserve_policy == MissionOrder.ReservePolicy.KEEP_HQ_NEAR_OBJECTIVE:
		reserve_deployed = false
		reserve_reason = "explicit_hq_reserve"
		return
	if emergency != "":
		reserve_deployed = true
		reserve_reason = emergency
		_reserve_quiet_since = -INF
	elif reserve_deployed:
		if not is_finite(_reserve_quiet_since):
			_reserve_quiet_since = _planning_snapshot.captured_at
		if _planning_snapshot.captured_at - _reserve_quiet_since >= RESERVE_RECOVERY_SECONDS:
			reserve_deployed = false
			reserve_reason = "recovering_reserve"
		else:
			reserve_reason = "emergency_settling"
	else:
		reserve_reason = "protected_reserve"


func _add_sector_request(unit: Unit, role: String, sector: int, responsibility: PositionQuery.Responsibility, branch: String = "") -> void:
	var config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, current_order.objective_hex, current_order, accepted_positions)
	config.defense_responsibility = responsibility
	if role != "guard_objective" and config.geography == PositionQuery.Geography.OBJECTIVE_OR_SECTOR:
		config.sector_cells = config.sector_cells.duplicate()
		for cell: Vector2i in defense_area.covered_positions:
			if not config.sector_cells.has(cell):
				config.sector_cells.append(cell)
	var query: PositionQuery = DefensePositionAnalyzer.make_query(config, unit, _planning_reservations)
	query.snapshot = _planning_snapshot
	query.defense_area = defense_area
	query.assigned_sector = sector
	query.assigned_branch = branch
	query.reserve_position = role == "reserve"
	query.reserve_reason = reserve_reason
	if unit == reserve_squad and _planning_readiness != null and branch != "" and branch == _planning_readiness.watch_branch:
		query.required_crossing_branch = branch
		query.reserve_reason = "cover_threatened_crossing"
	if query.reserve_position and _planning_readiness != null and _planning_readiness.reserve == unit:
		query.reserve_responses = _planning_readiness.responses
		query.reserve_response_context = _planning_readiness.reserve_capability
		query.reserve_response_limits = _planning_readiness.response_limits()
	query.relocation_allowed = _can_relocate(unit)
	if query.reserve_position:
		query.profile.firing_weight = 0.0
	_planning_requests.append({"query": query, "role": role, "axis": null})


func _add_planning_requests(config: InfluenceProjectionConfig, units: Array[Unit], role: String, axis: ThreatAxis) -> void:
	for unit: Unit in units:
		var query: PositionQuery = DefensePositionAnalyzer.make_query(config, unit, _planning_reservations)
		query.snapshot = influence_map_controller.snapshot
		_planning_requests.append({"query": query, "role": role, "axis": axis})


func _submit_planning_query() -> void:
	var query: PositionQuery = _planning_requests[_planning_index]["query"]
	query.relocation_allowed = _can_relocate(query.unit)
	_planning_job = influence_map_controller.enqueue_position_query(query)


func _continue_budgeted_plan() -> void:
	if _planning_job == null:
		return
	if _planning_job.canceled or _planning_job.query.objective_hex != current_order.objective_hex:
		_cancel_plan()
		time_until_reconsider = 0.0
		return
	if not _planning_job.completed:
		return
	var query: PositionQuery = _planning_job.query
	# A route computed from an old occupied hex cannot authorize a new move.
	if not InfluenceUnitQuery.is_valid_living_unit(query.unit) or query.unit.current_hex != query.origin_hex:
		_cancel_plan()
		time_until_reconsider = 0.0
		return
	_accept_planning_result(_planning_requests[_planning_index], _planning_job.result)
	_planning_index += 1
	if _planning_index < _planning_requests.size():
		_submit_planning_query()
	else:
		_validation_job = DefensePlanValidationJob.new()
		_validation_job.start(query.defense_area, _planning_requests, _planning_results)


func _accept_planning_result(request: Dictionary, advice: PositionResult) -> void:
	var result: DefensePositionResult = DefensePositionAnalyzer.adapt_result(advice, request["axis"], request["role"])
	_planning_results.append(result)
	if result.is_valid():
		_planning_reservations[result.unit] = result.target_hex
		if result.should_move and not HqSupportPositionPolicy.is_headquarters(result.unit):
			_relocation_claimed = true


func _commit_plan() -> void:
	if _defense_plan_outdated() or (_validation_job != null and (not _validation_job.completed or not _validation_job.valid or not _validation_job.unchanged())):
		_cancel_plan()
		time_until_reconsider = 0.0
		return
	for request: Dictionary in _planning_requests:
		var query: PositionQuery = request["query"]
		if not InfluenceUnitQuery.is_valid_living_unit(query.unit) or query.unit.current_hex != query.origin_hex:
			_cancel_plan()
			time_until_reconsider = 0.0
			return
	for index: int in range(_planning_results.size()):
		var result: DefensePositionResult = _planning_results[index]
		var query: PositionQuery = _planning_requests[index]["query"]
		if result.context != query.context_key():
			_cancel_plan()
			time_until_reconsider = 0.0
			return
		if _validation_job == null and result.is_valid() and query.profile.mode == PositionProfile.Mode.DEFEND:
			query.firepower_by_unit.clear()
			query.sector_features.clear()
			query.established_screen.clear()
			var protection: Dictionary = DefensePositionPolicy.evaluate(query, result.target_hex)
			if protection["responsibility"] == "" or not protection["preserves_screen"]:
				_cancel_plan()
				time_until_reconsider = 0.0
				return
	squad_assignments.clear()
	defense_gaps.clear()
	defense_branch_gaps.clear()
	reserved_hexes_by_squad = _planning_reservations
	for result: DefensePositionResult in _planning_results:
		_apply_position_results([result], result.role, result.axis)
	if _validation_job != null:
		defense_branch_gaps = _validation_job.branch_gaps.duplicate()
		for key: String in defense_branch_gaps:
			var sector: int = defense_area.branch_for_key(key)["id"]
			if not defense_gaps.has(sector):
				defense_gaps.append(sector)
	elif defense_area != null and not _planning_requests.is_empty() and current_order.position_mode == PositionProfile.Mode.DEFEND:
		var positions: Dictionary[Unit, Vector2i] = {}
		for result: DefensePositionResult in _planning_results:
			if result.is_valid():
				positions[result.unit] = result.target_hex
		var query: PositionQuery = _planning_requests[0]["query"]
		var highest: float = defense_area.max_duty_priority()
		for approach: Dictionary in defense_area.duties():
			var covered: bool = defense_area.protection_of_positions(query, positions, approach) >= DefensePositionPolicy.MIN_APPROACH_COVERAGE
			for result: DefensePositionResult in _planning_results:
				if result.is_valid() and result.features.get("responsibility") == "reserve" and DefenseSectorAllocator.combat_reserve_capable(result.unit):
					var status: Dictionary = result.features.get("reserve_branch_status", {}).get(DefenseAreaAssessment.duty_key(approach), {})
					covered = covered or (not status.is_empty() and status["response_seconds"] <= status["arrival_seconds"])
			if not covered and defense_area.duty_priority(approach) >= highest * 0.4:
				defense_branch_gaps.append(DefenseAreaAssessment.duty_key(approach))
				if not defense_gaps.has(approach["id"]):
					defense_gaps.append(approach["id"])
	_issue_orders()
	_planning_job = null
	_planning_requests.clear()
	_planning_results.clear()
	_planning_index = 0
	_planning_snapshot = null
	_validation_job = null
	_planning_readiness = null


func _defense_plan_outdated() -> bool:
	if current_order.position_mode != PositionProfile.Mode.DEFEND or defense_area == null:
		return false
	for contact: InfluenceContact in influence_map_controller.snapshot.get_contacts(team):
		if contact.observed:
			if not defense_area.observed_contacts.has(contact.unit):
				return true
			var captured: Vector2i = defense_area.observed_contacts[contact.unit]
			if defense_area.sector_at(contact.hex) != defense_area.sector_at(captured) or LOSHelper.get_hex_distance(contact.hex, captured) >= 2:
				return true
	return false


func _cancel_plan() -> void:
	_readiness_job = null
	_planning_readiness = null
	_validation_job = null
	if influence_map_controller != null and _planning_job != null:
		influence_map_controller.cancel_position_query(_planning_job)
	_planning_job = null
	_area_job = null
	_planning_available.clear()
	_planning_requests.clear()
	_planning_results.clear()
	_planning_reservations = {}
	_planning_index = 0
	_planning_snapshot = null


func _select_guard_squad(available: Array[Unit]) -> Unit:
	var candidates: Array[Unit] = _combat_units(available)
	if candidates.is_empty():
		return null
	return DefenseSectorAllocator.select_guard(candidates)


func _select_reserve_squad(available: Array[Unit]) -> Unit:
	if current_order.reserve_policy == MissionOrder.ReservePolicy.KEEP_HQ_NEAR_OBJECTIVE:
		return null
	if InfluenceUnitQuery.is_valid_living_unit(reserve_squad) and available.has(reserve_squad) and DefenseSectorAllocator.combat_reserve_capable(reserve_squad):
		return reserve_squad
	var reserve: Unit = null
	for unit: Unit in available:
		if not DefenseSectorAllocator.combat_reserve_capable(unit):
			continue
		if reserve == null or InfluenceUnitQuery.get_defensive_mount(unit) < InfluenceUnitQuery.get_defensive_mount(reserve):
			reserve = unit
		elif InfluenceUnitQuery.get_defensive_mount(unit) == InfluenceUnitQuery.get_defensive_mount(reserve) and InfluenceUnitQuery.get_unit_effectiveness(unit) > InfluenceUnitQuery.get_unit_effectiveness(reserve):
			reserve = unit
	return reserve


func _get_sorted_threat_axes() -> Array[ThreatAxis]:
	var axes: Array[ThreatAxis] = influence_map_controller.get_sorted_threat_axes_for_team(team, current_order.objective_hex)
	if axes.is_empty():
		for axis: ThreatAxis in current_order.threat_axes:
			if axis != null and axis.is_valid_axis():
				axes.append(axis)
	return axes


func _distribute_squads_over_axes(available: Array[Unit], axes: Array[ThreatAxis]) -> Dictionary:
	var result: Dictionary = {}
	for axis: ThreatAxis in axes:
		var assigned: Array[Unit] = []
		result[axis] = assigned
	for index: int in range(available.size()):
		result[axes[index % axes.size()]].append(available[index])
	return result


func _apply_position_results(results: Array[DefensePositionResult], _fallback_role: String, _fallback_axis: ThreatAxis) -> void:
	for result: DefensePositionResult in results:
		if result == null or not squads.has(result.unit) or result.unit.team != team:
			continue
		# Keep no-candidate diagnostics; never substitute an unchecked objective move.
		squad_assignments[result.unit] = {"result": result, "role": _fallback_role, "target_hex": result.target_hex,
			"should_move": result.should_move, "score_map": result.score_map, "reason": result.reason}
		if result.is_valid():
			reserved_hexes_by_squad[result.unit] = result.target_hex


func _issue_orders() -> void:
	if not active:
		return
	for squad: Unit in squad_assignments:
		var result: PositionResult = squad_assignments[squad]["result"]
		squad.position_advice = result
		squad.influence_map = result.score_map
		if result.is_valid() and executor.execute(result, current_order.execution_intent):
			var accepted_at: float = influence_map_controller.snapshot.captured_at
			var previous: Dictionary = accepted_positions.get(squad, {})
			if previous.get("hex") == result.target_hex and previous.get("context") == result.context:
				accepted_at = previous.get("at", accepted_at)
			accepted_positions[squad] = {"hex": result.target_hex, "context": result.context, "at": accepted_at}
			squad.best_index = result.target_index
		else:
			executor.cancel(squad, true)
			accepted_positions.erase(squad)
			reserved_hexes_by_squad[squad] = squad.current_hex


func _get_effective_squads() -> Array[Unit]:
	var result: Array[Unit] = []
	for squad: Unit in squads:
		if InfluenceUnitQuery.is_valid_living_unit(squad) and squad.team == team and squad.members_alive > 0 and squad.movement != null and influence_map_controller.snapshot.positions.has(squad) and not result.has(squad):
			result.append(squad)
	result.sort_custom(InfluenceUnitQuery.compare_units_by_squad_type_priority)
	return result


func _create_current_reserved_hexes(units: Array[Unit]) -> Dictionary:
	var result: Dictionary = {}
	for unit: Unit in units:
		var cell: Vector2i = unit.current_hex
		if unit.movement != null and unit.movement.is_moving:
			cell = unit.movement.target_hex
		result[unit] = cell
	return result


func _unhandled_input(event: InputEvent) -> void:
	if not active or current_order == null:
		return
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse == null or mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return
	if (mouse.ctrl_pressed and team == Globals.Team.AXIS) or (mouse.shift_pressed and team == Globals.Team.ALLIES):
		current_order.objective_hex = LOSHelper.ground_layer.local_to_map(get_parent().get_global_mouse_position())
		_start_plan(is_inside_tree())
