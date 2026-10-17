class_name PlatoonAI
extends Node

@export var reconsider_interval: float = 0.5
@export var team: Globals.Team = Globals.Team.AXIS
@export var influence_map_controller: InfluenceMapController

var squads: Array[Unit] = []
var active: bool = true
var goal_director: ScenarioGoalDirector
var company_command: CompanyAI
var publish_team_objective: bool = true
var company_reservations: Dictionary[Unit, Vector2i] = {}
var company_support_squads: Array[Unit] = []
var company_maneuver_squads: Array[Unit] = []
var company_requires_support: bool = false
var company_defensive_posture: bool = false
var company_reserve_capacity: int = -1
var goal_assignments: Dictionary[Unit, ScenarioGoalTask] = {}
var current_order: MissionOrder = null
var squad_assignments: Dictionary = {}
var reserved_hexes_by_squad: Dictionary = {}
var accepted_positions: Dictionary = {}
var time_until_reconsider: float = 0.0
var executor: TacticalPositionExecutor = TacticalPositionExecutor.new()
var position_stability: PlatoonPositionStability = PlatoonPositionStability.new()
var _planning_requests: Array[Dictionary] = []
var _planning_results: Array[DefensePositionResult] = []
var _planning_reservations: Dictionary = {}
var _planning_baseline: Dictionary[Unit, Vector2i] = {}
var _departure_origins: Dictionary[Unit, Vector2i] = {}
var _planning_job: PositionQueryJob
var _planning_index: int = 0
var defense_area: DefenseAreaAssessment
var defense_gaps: Array[int] = []
var defense_branch_gaps: Array[String] = []
var _area_job: DefenseAreaJob
var _planning_available: Array[Unit] = []
var _planning_snapshot: InfluenceSnapshot
var _planning_objective_hex: Vector2i
var _validation_job: DefensePlanValidationJob
var _readiness_job: DefenseReadinessJob
var _planning_readiness: DefenseReadinessJob
var reserve_squad: Unit
var reserve_deployed: bool = false
var attack_advance_released: bool = false
var attack_approach_started: bool = false
var attack_maneuver_squad: Unit
var reserve_reason: String = ""
var _reserve_quiet_since: float = -INF
var _validating_batch: bool = false
var _position_mission_context: String = ""
var _position_optimization_due: Dictionary[Unit, float] = {}
var _defense_urgent_units: Dictionary[Unit, bool] = {}
var _defense_capabilities: Dictionary[Unit, bool] = {}
var _defense_observed_hexes: Dictionary[Unit, Vector2i] = {}
var _defense_events_initialized: bool = false
var _defense_event_timer: float = 0.0
var _defense_refresh_version: int = -1

const RESERVE_RECOVERY_SECONDS: float = 8.0
const POSITION_OPTIMIZATION_SECONDS: float = 3.0


func _process(delta: float) -> void:
	if not active or current_order == null:
		return
	if company_command != null:
		company_command.update(delta)
		if company_command.uses_hierarchy():
			return
	_check_company_cover()
	position_stability.observe(squads, _position_time())
	if current_order.position_mode == PositionProfile.Mode.DEFEND:
		_defense_event_timer -= delta
		if _defense_event_timer <= 0.0:
			_defense_event_timer = 0.1
			_check_defense_events()
		if _defense_refresh_version >= 0:
			if influence_map_controller.snapshot == null or influence_map_controller.snapshot.version < _defense_refresh_version:
				return
			_defense_refresh_version = -1
			# Published orders remain owned; fresh role checks reuse unaffected positions.
			_cancel_plan()
			time_until_reconsider = 0.0
	time_until_reconsider -= delta
	if (not _planning_requests.is_empty() or _readiness_job != null) and _defense_plan_outdated():
		_cancel_plan()
		time_until_reconsider = 0.0
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
		_refresh_coverage_delay()
		_validation_job.advance(Time.get_ticks_usec() + InfluenceMapController.POSITION_QUERY_BUDGET_USEC)
		if _validation_job.completed:
			if _validation_job.valid:
				if _validating_batch:
					_commit_plan()
				else:
					_publish_ready_result()
			else:
				_cancel_plan()
				time_until_reconsider = 0.0
		return
	if _planning_job != null:
		_continue_budgeted_plan()
		return
	if time_until_reconsider <= 0.0 or _defense_plan_outdated():
		time_until_reconsider = reconsider_interval
		_start_plan(true)


func _exit_tree() -> void:
	if company_command != null:
		company_command.stop()
	_cancel_plan()
	_set_mission_control(false)
	executor.cancel_all()
	position_stability.clear()
	_departure_origins.clear()
	_position_optimization_due.clear()
	_reset_defense_events()


func set_active(is_active: bool) -> void:
	_cancel_plan()
	active = is_active
	if active:
		_set_mission_control(current_order != null)
		return
	if company_command != null:
		company_command.stop()
	_set_mission_control(false)
	_clear_reserve()
	# Release only actions owned by this planner when handing control to the player.
	executor.cancel_all(true)
	position_stability.clear()
	_departure_origins.clear()
	_position_optimization_due.clear()
	_reset_defense_events()
	current_order = null
	goal_assignments.clear()
	attack_maneuver_squad = null
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
	if company_command != null:
		company_command.reset_mission()
	_cancel_plan()
	_clear_reserve()
	executor.cancel_all(true)
	position_stability.clear()
	_departure_origins.clear()
	_position_optimization_due.clear()
	_reset_defense_events()
	accepted_positions.clear()
	goal_assignments.clear()
	current_order = order
	attack_advance_released = false
	attack_approach_started = false
	attack_maneuver_squad = null
	_set_mission_control(true)
	time_until_reconsider = reconsider_interval
	_start_plan(is_inside_tree())


func change_scenario_objective(hex: Vector2i) -> void:
	# The director delays ordinary mission changes until accepted bounds finish.
	_cancel_plan()
	current_order.objective_hex = hex
	current_order.sector_cells = []
	current_order.fallback_hexes = []
	# Mission reassignment does not discard physical movement commitments. Their
	# remaining routes are still checked against the next influence snapshot.
	_position_mission_context = str([current_order.objective_hex, current_order.position_mode, current_order.geography, current_order.sector_cells, current_order.defense_responsibility])
	attack_advance_released = false
	attack_approach_started = false
	attack_maneuver_squad = null
	time_until_reconsider = 0.0


func set_scenario_goal_assignments(assignments: Dictionary[Unit, ScenarioGoalTask]) -> void:
	var changed: bool = false
	var affected: Array[Unit] = []
	affected.assign(goal_assignments.keys())
	for unit: Unit in assignments:
		if not affected.has(unit):
			affected.append(unit)
	for unit: Unit in affected:
		var previous: ScenarioGoalTask = goal_assignments.get(unit)
		var next: ScenarioGoalTask = assignments.get(unit)
		if previous != null and next != null and previous.key == next.key:
			continue
		if previous == null and next == null:
			continue
		changed = true
		position_stability.forget(unit)
		accepted_positions.erase(unit)
		_position_optimization_due.erase(unit)
	goal_assignments = assignments.duplicate()
	if changed:
		_cancel_plan()
		time_until_reconsider = 0.0
		if company_command != null and company_command.uses_hierarchy():
			company_command.reconsider(true)


func set_squads(new_squads: Array[Unit]) -> void:
	var owned: Array[Unit] = []
	for squad: Unit in new_squads:
		if InfluenceUnitQuery.is_valid_living_unit(squad) and squad.team == team and not owned.has(squad):
			owned.append(squad)
	_cancel_plan()
	_clear_reserve()
	_set_mission_control(false)
	executor.cancel_all(true)
	position_stability.clear()
	_departure_origins.clear()
	_position_optimization_due.clear()
	_reset_defense_events()
	squad_assignments.clear()
	reserved_hexes_by_squad.clear()
	accepted_positions.clear()
	defense_area = null
	defense_gaps.clear()
	defense_branch_gaps.clear()
	time_until_reconsider = 0.0
	squads = owned
	attack_maneuver_squad = null
	_set_mission_control(active and current_order != null)
	if company_command != null:
		company_command.sync_roster()


func _set_mission_control(enabled: bool) -> void:
	for squad: Unit in squads:
		if not is_instance_valid(squad):
			continue
		squad.ai_support_only = enabled and HqSupportPositionPolicy.is_headquarters(squad)
		if squad.ai_support_only and squad.squad_fire != null:
			squad.squad_fire.clear_target()
		if squad.squad_ai_controller != null:
			squad.squad_ai_controller.defensive_mission_controlled = enabled and current_order != null and (current_order.position_mode == PositionProfile.Mode.DEFEND or company_defensive_posture)


func bind_active_squads(active_units: Array[Unit]) -> void:
	# Each match supplies its complete runtime roster; squad numbers do not gate ownership.
	if company_command == null:
		company_command = CompanyAI.new()
		company_command.configure(self)
	set_squads(active_units)


func reconsider_assignments() -> void:
	_start_plan(false)


func _start_plan(budgeted: bool) -> void:
	_cancel_plan()
	if not active or current_order == null or influence_map_controller == null:
		return
	if company_command != null and company_command.uses_hierarchy():
		company_command.reconsider(budgeted)
		return
	_sync_position_mission()
	_planning_objective_hex = current_order.objective_hex
	if publish_team_objective:
		influence_map_controller.set_objective_for_team(team, current_order.objective_hex)
	if influence_map_controller.snapshot == null:
		return
	var available: Array[Unit] = _get_effective_squads()
	position_stability.observe(available, _position_time())
	for unit: Unit in accepted_positions.keys():
		if not available.has(unit):
			accepted_positions.erase(unit)
			_position_optimization_due.erase(unit)
			_defense_urgent_units.erase(unit)
			position_stability.forget(unit)
			executor.cancel(unit)
	_planning_reservations = _create_current_reserved_hexes(available)
	_planning_available = available
	_planning_snapshot = influence_map_controller.snapshot
	if current_order.position_mode == PositionProfile.Mode.DEFEND:
		_planning_baseline = _capture_planning_baseline()
		var priority: int = 0
		if accepted_positions.is_empty() or not _defense_urgent_units.is_empty():
			priority = 2
		_area_job = influence_map_controller.request_defense_area(team, current_order.objective_hex, current_order.defense_area_radius, current_order.approach_analysis_radius, current_order.threat_axes, priority)
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
		_accept_planning_result(request, PositionQueryService.query_positions(query))
	_commit_plan()


func _capture_planning_baseline() -> Dictionary[Unit, Vector2i]:
	var baseline: Dictionary[Unit, Vector2i] = DefensePositionPolicy.capture_departure_baseline(_planning_snapshot, team)
	for unit: Unit in _departure_origins.keys():
		if not InfluenceUnitQuery.is_valid_living_unit(unit) or unit.team != team:
			_departure_origins.erase(unit)
			continue
		var relocating: bool = unit.movement != null and unit.movement.is_moving
		if unit.action_controller != null:
			relocating = relocating or unit.action_controller.action_state in [SquadActionController.SquadActionState.ESTABLISHING_POSITION, SquadActionController.SquadActionState.REGROUPING]
		if relocating:
			baseline[unit] = _departure_origins[unit]
		else:
			_departure_origins.erase(unit)
	return baseline


func _prepare_readiness(budgeted: bool) -> void:
	var available: Array[Unit] = _combat_units(_planning_available)
	for unit: Unit in goal_assignments:
		available.erase(unit)
	var reserve: Unit = null
	if current_order.defense_responsibility == PositionQuery.Responsibility.AUTO and not _has_objective_goal_duty() and available.size() >= 2:
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
	if company_reserve_capacity == 0:
		return false
	if current_order.reserve_policy == MissionOrder.ReservePolicy.NONE:
		return false
	if current_order.reserve_policy == MissionOrder.ReservePolicy.KEEP_HQ_NEAR_OBJECTIVE:
		return false
	var combat_count: int = 0
	for unit: Unit in available:
		if not goal_assignments.has(unit) and DefenseSectorAllocator.combat_reserve_capable(unit):
			combat_count += 1
	# Readiness decides whether a capable reserve can cover gaps or must deploy.
	if company_reserve_capacity > 0:
		return combat_count >= 2
	return combat_count >= 3


func _has_objective_goal_duty() -> bool:
	for unit: Unit in goal_assignments:
		var task: ScenarioGoalTask = goal_assignments[unit]
		if task.hex == current_order.objective_hex and task.kind in [ScenarioGoalTask.Kind.OCCUPY, ScenarioGoalTask.Kind.DENY_OCCUPATION, ScenarioGoalTask.Kind.BLOCK_EXIT] and TacticalPositionExecutor.is_active_defender(unit) and unit.is_good_order():
			return true
	return false


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
		if goal_assignments.has(unit):
			continue
		if HqSupportPositionPolicy.is_headquarters(unit):
			var config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, current_order.objective_hex, current_order, accepted_positions)
			config.profile = PositionProfile.for_mode(PositionProfile.Mode.HQ_SUPPORT)
			if current_order.position_mode == PositionProfile.Mode.ASSAULT:
				config.profile.support_assault_squads = true
				config.profile.commitment_seconds = 8.0
				config.profile.progress_weight = 12.0
				config.profile.max_exposure_seconds = current_order.exposure_budget_seconds
				config.profile.max_open_exposure_seconds = current_order.open_crossing_budget_seconds
			_add_planning_requests(config, [unit], "hq_support", null)


func _build_planning_requests(available: Array[Unit]) -> void:
	var combat: Array[Unit] = _combat_units(available)
	for unit: Unit in available:
		if goal_assignments.has(unit):
			_add_goal_request(unit, goal_assignments[unit])
			combat.erase(unit)
	_build_combat_planning_requests(combat)
	_add_support_requests(available)
	_prioritize_planning_requests()


func _add_goal_request(unit: Unit, task: ScenarioGoalTask) -> void:
	var clear_exit: bool = task.kind == ScenarioGoalTask.Kind.EXIT and not task.breach_required
	var combat_hex: Vector2i = task.hex
	if task.breach_required:
		combat_hex = task.breach_hex
	var config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, combat_hex, current_order, accepted_positions)
	config.sector_cells = []
	config.fallback_hexes = []
	config.geography = PositionQuery.Geography.OBJECTIVE_RADIUS
	config.defense_responsibility = PositionQuery.Responsibility.AUTO
	var advancing: bool = task.is_destination_goal() or task.kind == ScenarioGoalTask.Kind.HUNT
	if task.kind == ScenarioGoalTask.Kind.OCCUPY and unit.current_hex == task.hex:
		advancing = false
	if task.kind == ScenarioGoalTask.Kind.DENY_OCCUPATION:
		for contact: InfluenceContact in _planning_snapshot.get_contacts(team):
			if contact.observed and contact.hex == task.hex and TacticalPositionExecutor.is_active_defender(contact.unit) and contact.unit.is_good_order():
				advancing = true
	if task.kind == ScenarioGoalTask.Kind.PRESERVE:
		config.objective_hex = unit.current_hex
		config.defense_radius = 2
		config.withdrawal_requested = true
	config.profile = PositionProfile.for_mode(PositionProfile.Mode.DEFEND)
	if task.kind == ScenarioGoalTask.Kind.OCCUPY and not advancing:
		config.defense_responsibility = PositionQuery.Responsibility.OCCUPY
		config.profile.minimum_cover = 0.0
	elif task.kind in [ScenarioGoalTask.Kind.DENY_OCCUPATION, ScenarioGoalTask.Kind.BLOCK_EXIT] and not advancing:
		config.defense_responsibility = PositionQuery.Responsibility.COVER_APPROACH
		config.geography = current_order.geography
		config.sector_cells = current_order.sector_cells.duplicate()
		if defense_area != null and defense_area.objective_hex == combat_hex and config.geography == PositionQuery.Geography.OBJECTIVE_OR_SECTOR:
			for cell: Vector2i in defense_area.covered_positions:
				if not config.sector_cells.has(cell):
					config.sector_cells.append(cell)
	if advancing:
		config.profile = PositionProfile.for_mode(PositionProfile.Mode.ADVANCE)
		config.profile.progress_weight = 12.0
		config.profile.cover_weight = 0.8
		config.profile.avoid_unsuppressed_defenders = true
		var defenders: Array[Unit] = []
		for contact: InfluenceContact in _planning_snapshot.get_contacts(team):
			if contact.observed and LOSHelper.get_hex_distance(contact.hex, combat_hex) <= 2 and TacticalPositionExecutor.is_active_defender(contact.unit):
				defenders.append(contact.unit)
		var ready: bool = defenders.is_empty()
		if not defenders.is_empty():
			ready = true
			for defender: Unit in defenders:
				if not TacticalPositionExecutor.is_sufficiently_suppressed(defender):
					ready = false
			ready = ready and _goal_support_ready(unit, combat_hex)
			for defender: Unit in defenders:
				if defender.current_hex == combat_hex and TacticalPositionExecutor.is_overwhelmed(defender):
					ready = true
		var press: bool = false
		for defender: Unit in defenders:
			if defender.current_hex == combat_hex and TacticalPositionExecutor.is_overwhelmed(defender):
				press = true
		if not defenders.is_empty() and not press and _goal_maneuver(combat_hex) != unit:
			ready = false
		if task.kind == ScenarioGoalTask.Kind.OCCUPY and unit.current_hex == task.hex:
			ready = true
		if company_requires_support and not clear_exit and not task.withdrawal and unit.current_hex != task.hex and not _has_company_support():
			ready = false
		if not ready:
			config.profile = PositionProfile.for_mode(PositionProfile.Mode.SUPPORT_BY_FIRE)
			config.profile.minimum_cover = 0.1
		elif LOSHelper.get_hex_distance(unit.current_hex, combat_hex) == 1:
			for defender: Unit in defenders:
				if defender.current_hex == combat_hex and TacticalPositionExecutor.is_sufficiently_suppressed(defender):
					config.profile = PositionProfile.for_mode(PositionProfile.Mode.ASSAULT)
					config.profile.enter_suppressed_enemy_hex = true
					config.profile.avoid_unsuppressed_defenders = true
	if task.breach_required:
		# A blocked escape needs a deliberate fight rather than rejecting every exposed approach.
		config.profile.max_incoming_risk = 1.0
		config.profile.max_route_exposure = 1.0
		config.profile.forecast_route_weight = 0.25
		config.profile.minimum_cover = 0.0
		if config.profile.mode == PositionProfile.Mode.SUPPORT_BY_FIRE:
			config.profile.support_advance_weight = 8.0
	var query: PositionQuery = DefensePositionAnalyzer.make_query(config, unit, _planning_reservations)
	if task.withdrawal and HqSupportPositionPolicy.is_headquarters(unit):
		# A deliberate exit duty overrides the default HQ support profile.
		query.profile = config.profile
	query.snapshot = _planning_snapshot
	if not advancing and defense_area != null and defense_area.objective_hex == combat_hex:
		query.defense_area = defense_area
		query.departure_baseline = _planning_baseline
		query.has_departure_baseline = true
	if task.breach_required and query.profile.mode == PositionProfile.Mode.SUPPORT_BY_FIRE:
		query.has_support_anchor = true
		query.support_anchor_hex = combat_hex
	query.use_defense_area = not advancing and task.kind != ScenarioGoalTask.Kind.PRESERVE
	query.goal_key = task.key
	query.goal_reason = task.reason
	query.goal_destination_required = task.is_destination_goal() and not task.breach_required and query.profile.mode == PositionProfile.Mode.ADVANCE
	if task.kind == ScenarioGoalTask.Kind.OCCUPY:
		query.goal_capacity = task.required_units
	elif task.kind == ScenarioGoalTask.Kind.EXIT:
		# Exited squads remain on the board; later squads must still be able to
		# register at the same marker without waiting for a counted squad to leave.
		query.goal_capacity = task.exit_capacity()
	query.press_attack = _can_attack_without_overwatch(unit, combat_hex)
	if query.press_attack:
		query.profile.forecast_weight = 0.0
		query.profile.forecast_route_weight = 0.0
	_configure_position_stability(query)
	query.mission_objective_hex = task.hex
	query.deliberate_movement = query.profile.mode in [PositionProfile.Mode.ADVANCE, PositionProfile.Mode.ASSAULT]
	query.response_priority = 2
	if task.urgent:
		query.response_priority = 3
	_planning_requests.append({"query": query, "role": "scenario_goal", "axis": null})


func _goal_support_ready(attacker: Unit, hex: Vector2i) -> bool:
	if company_requires_support:
		return _has_company_support()
	for friendly: Unit in squads:
		if friendly == attacker or HqSupportPositionPolicy.is_headquarters(friendly) or not TacticalPositionExecutor.is_active_defender(friendly) or not PositionQueryService.can_follow_intent(friendly) or PlatoonPositionStability.is_busy(friendly):
			continue
		if TacticalPositionExecutor.select_support_target(friendly, hex) != null:
			return true
	return false


func _goal_maneuver(hex: Vector2i) -> Unit:
	var selected: Unit
	for unit: Unit in goal_assignments:
		var objective: Vector2i = goal_assignments[unit].hex
		if goal_assignments[unit].breach_required:
			objective = goal_assignments[unit].breach_hex
		if objective != hex or unit.squad_type != Globals.SquadType.Rifle or not PositionQueryService.can_assault(unit) or not PositionQueryService.can_follow_intent(unit):
			continue
		if PlatoonPositionStability.is_busy(unit) or unit.in_close_combat:
			return unit
		if selected == null or LOSHelper.get_hex_distance(unit.current_hex, hex) < LOSHelper.get_hex_distance(selected.current_hex, hex):
			selected = unit
	return selected


func _prioritize_planning_requests() -> void:
	if _planning_requests.size() < 2:
		return
	_defer_established_guard()
	# Stable sort preserves guard/branch allocation order among equally urgent duties.
	for index: int in range(1, _planning_requests.size()):
		var request: Dictionary = _planning_requests[index]
		var cursor: int = index
		while cursor > 0 and request["query"].response_priority > _planning_requests[cursor - 1]["query"].response_priority:
			_planning_requests[cursor] = _planning_requests[cursor - 1]
			cursor -= 1
		_planning_requests[cursor] = request


func _defer_established_guard() -> void:
	if _planning_requests[0]["role"] != "guard_objective":
		return
	var request: Dictionary = _planning_requests[0]
	var query: PositionQuery = request["query"]
	var accepted: Dictionary = accepted_positions.get(query.unit, {})
	if accepted.get("hex") != query.unit.current_hex or accepted.get("context") != query.context_key() or not DefenseReadinessJob.established(query.unit, query):
		return
	if query.snapshot.maps[query.team].get_layer_value(InfluenceMap.Layer.TERRAIN_COVER, query.unit.current_hex) < query.profile.minimum_cover:
		return
	_planning_requests.pop_front()
	var index: int = 0
	while index < _planning_requests.size() and _planning_requests[index]["role"] != "hq_support":
		index += 1
	_planning_requests.insert(index, request)


func _build_combat_planning_requests(available: Array[Unit]) -> void:
	if available.is_empty():
		return
	if goal_director != null and goal_director.primary == null and not goal_director.conditions.is_empty():
		for unit: Unit in available:
			var hold_config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, current_order.objective_hex, current_order, accepted_positions)
			hold_config.profile = PositionProfile.for_mode(PositionProfile.Mode.DEFEND)
			_add_planning_requests(hold_config, [unit], "protect_force", null)
		return
	if current_order.position_mode == PositionProfile.Mode.DEFEND and defense_area != null:
		_build_sector_requests(available.duplicate())
		return
	if current_order.position_mode != PositionProfile.Mode.DEFEND and current_order.position_mode != PositionProfile.Mode.LEGACY_DEFENSE:
		if current_order.position_mode == PositionProfile.Mode.ASSAULT:
			_update_attack_roles(available)
			attack_advance_released = _has_pressing_attack(available) or (_has_established_attack_support(available) and (_are_visible_attack_defenders_suppressed(available) or not _has_known_attack_defenders(available)))
			attack_approach_started = attack_approach_started or attack_advance_released
		for unit: Unit in available:
			var config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, current_order.objective_hex, current_order, accepted_positions)
			var role: String = "offense"
			if current_order.position_mode == PositionProfile.Mode.ASSAULT:
				var mode: PositionProfile.Mode = _attack_mode_for_unit(unit)
				config.profile = PositionProfile.for_mode(mode)
				if mode == PositionProfile.Mode.SUPPORT_BY_FIRE:
					config.objective_hex = _attack_support_objective(available)
					config.profile.minimum_cover = 0.1
					config.profile.commitment_seconds = 8.0
					if unit.squad_type == Globals.SquadType.MG:
						config.profile.commitment_seconds = 16.0
					var front: Unit = _attack_front_squad(available)
					var follows_front: bool = attack_approach_started and front != null
					if follows_front:
						config.profile.support_advance_weight = 12.0
						config.profile.avoid_unsuppressed_defenders = true
					config.profile.improvement_absolute = 0.35
					config.profile.improvement_relative = 0.2
				if mode == PositionProfile.Mode.ADVANCE and unit.squad_type == Globals.SquadType.Rifle:
					var pressure_target: Unit = _attack_pressure_target(unit)
					if pressure_target != null:
						config.objective_hex = pressure_target.current_hex
					config.profile.minimum_cover = 0.1
					if pressure_target != null or not _has_known_attack_defenders(available):
						# An overwhelmed defender or a cleared objective permits an open approach.
						config.profile.minimum_cover = 0.0
					config.profile.avoid_unsuppressed_defenders = true
					# Approach the objective instead of optimizing a stationary firing position.
					config.profile.progress_weight = 12.0
					config.profile.cover_weight = 0.8
					config.profile.incoming_weight = 2.0
					config.profile.forecast_weight = 0.25
					config.profile.exposure_weight = 0.5
					config.profile.max_incoming_risk = 0.9
					config.profile.max_route_exposure = 0.9
				if mode == PositionProfile.Mode.ASSAULT:
					var defender: Unit = _close_combat_target(unit)
					var pressure_target: Unit = _attack_pressure_target(unit)
					if pressure_target != null and LOSHelper.get_hex_distance(unit.current_hex, pressure_target.current_hex) == 1:
						defender = pressure_target
					if defender != null:
						config.objective_hex = defender.current_hex
						config.profile.enter_suppressed_enemy_hex = true
						config.profile.avoid_unsuppressed_defenders = true
				role = "advance"
				if mode == PositionProfile.Mode.SUPPORT_BY_FIRE:
					role = "support_by_fire"
				elif mode == PositionProfile.Mode.ASSAULT:
					role = "assault"
				elif mode == PositionProfile.Mode.HQ_SUPPORT:
					role = "hq_support"
			_add_planning_requests(config, [unit], role, null)
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
	var has_guard: bool = _has_objective_goal_duty()
	var can_reserve: bool = _can_keep_reserve(available)
	if current_order.defense_responsibility == PositionQuery.Responsibility.AUTO and not has_guard and available.size() >= 2:
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


func _can_provide_attack_support(unit: Unit) -> bool:
	return TacticalPositionExecutor.is_active_defender(unit) and unit.team == team and unit.squad_type in [Globals.SquadType.Rifle, Globals.SquadType.MG] and PositionQueryService.can_follow_intent(unit) and InfluenceUnitQuery.get_unit_firepower(unit) > 0.0


func _has_attack_cover_candidate(available: Array[Unit], maneuver: Unit) -> bool:
	if _attack_pressure_target(maneuver) != null:
		return true
	for unit: Unit in available:
		if unit != maneuver and _can_provide_attack_support(unit):
			return true
	for unit: Unit in company_support_squads:
		if _can_provide_attack_support(unit):
			return true
	return false


func _attack_front_squad(available: Array[Unit]) -> Unit:
	var front: Unit = null
	var best_distance: int = 2147483647
	for unit: Unit in available:
		if unit.squad_type != Globals.SquadType.Rifle or not TacticalPositionExecutor.is_active_defender(unit):
			continue
		var distance: int = LOSHelper.get_hex_distance(unit.current_hex, current_order.objective_hex)
		if distance < best_distance or (distance == best_distance and unit == attack_maneuver_squad):
			front = unit
			best_distance = distance
	return position_stability.choose_support_anchor(front, available, current_order.objective_hex, _position_time())


func _attack_pressure_target(unit: Unit) -> Unit:
	if current_order == null or influence_map_controller == null or influence_map_controller.snapshot == null:
		return null
	if not TacticalPositionExecutor.is_active_defender(unit) or unit.squad_type != Globals.SquadType.Rifle or not PositionQueryService.can_assault(unit) or not PositionQueryService.can_follow_intent(unit):
		return null
	var target: Unit = null
	var best_distance: int = 2147483647
	for observer: Unit in squads:
		for enemy: Unit in Globals.unit_visible_enemies.get(observer, []):
			if not TacticalPositionExecutor.is_overwhelmed(enemy) or enemy.team == team:
				continue
			if LOSHelper.get_hex_distance(enemy.current_hex, current_order.objective_hex) > current_order.defense_radius:
				continue
			if not _overwhelmed_target_is_safe(enemy):
				continue
			var distance: int = LOSHelper.get_hex_distance(unit.current_hex, enemy.current_hex)
			if distance < best_distance:
				target = enemy
				best_distance = distance
	return target


func _overwhelmed_target_is_safe(target: Unit) -> bool:
	for observer: Unit in squads:
		for enemy: Unit in Globals.unit_visible_enemies.get(observer, []):
			if not TacticalPositionExecutor.is_active_defender(enemy) or TacticalPositionExecutor.is_overwhelmed(enemy):
				continue
			if LOSHelper.get_hex_distance(enemy.current_hex, target.current_hex) <= 1 or influence_map_controller.snapshot.los.get(enemy.current_hex, {}).has(target.current_hex):
				return false
	for contact: InfluenceContact in influence_map_controller.snapshot.get_defensive_contacts(team):
		if contact.observed and (not TacticalPositionExecutor.is_active_defender(contact.unit) or TacticalPositionExecutor.is_overwhelmed(contact.unit)):
			continue
		if LOSHelper.get_hex_distance(contact.hex, target.current_hex) <= 1 or influence_map_controller.snapshot.los.get(contact.hex, {}).has(target.current_hex):
			return false
	return true


func _can_attack_without_overwatch(unit: Unit, objective: Vector2i) -> bool:
	var target: Unit = _attack_pressure_target(unit)
	return target != null and target.current_hex == objective


func _has_pressing_attack(available: Array[Unit]) -> bool:
	for unit: Unit in available:
		if _attack_pressure_target(unit) != null:
			return true
	return false


func _has_attack_bound(available: Array[Unit]) -> bool:
	for unit: Unit in available:
		if unit.squad_type == Globals.SquadType.Rifle and (unit.movement.is_moving or unit.in_close_combat):
			return true
	return false


func _update_attack_roles(available: Array[Unit]) -> void:
	var goal_maneuver: Unit = _goal_maneuver(current_order.objective_hex)
	if goal_maneuver != null:
		attack_maneuver_squad = goal_maneuver
		return
	# Retain the moving squad so small scoring changes cannot send both rifles forward.
	if available.has(attack_maneuver_squad) and TacticalPositionExecutor.is_active_defender(attack_maneuver_squad):
		if attack_maneuver_squad.in_close_combat:
			return
		if PositionQueryService.can_assault(attack_maneuver_squad) and _has_attack_cover_candidate(available, attack_maneuver_squad):
			return
	attack_maneuver_squad = null
	var best_distance: int = 2147483647
	for unit: Unit in available:
		if unit.squad_type != Globals.SquadType.Rifle or not _can_provide_attack_support(unit) or not PositionQueryService.can_assault(unit):
			continue
		if not _has_attack_cover_candidate(available, unit):
			continue
		var distance: int = LOSHelper.get_hex_distance(unit.current_hex, current_order.objective_hex)
		if attack_maneuver_squad == null or distance < best_distance or (distance == best_distance and unit.get_instance_id() < attack_maneuver_squad.get_instance_id()):
			attack_maneuver_squad = unit
			best_distance = distance


func _has_established_attack_support(available: Array[Unit], departing: Unit = null) -> bool:
	if company_requires_support:
		return _has_company_support(departing)
	var has_defenders: bool = _has_known_attack_defenders(squads)
	for unit: Unit in available:
		if unit == attack_maneuver_squad or unit == departing or not _can_provide_attack_support(unit):
			continue
		var advice: PositionResult = unit.position_advice
		if advice == null or not advice.is_valid() or advice.profile_mode != PositionProfile.Mode.SUPPORT_BY_FIRE:
			continue
		if unit.movement.is_moving or unit.current_hex != advice.target_hex:
			continue
		if unit.action_controller.action_state != SquadActionController.SquadActionState.HOLDING_POSITION:
			continue
		if advice.features.get("cover", 0.0) < 0.1 or advice.features.get("firing", 0.0) <= 0.0:
			continue
		if not has_defenders:
			# A cleared objective still needs stationary overwatch, but nothing to shoot at.
			return true
		if unit.squad_fire != null and (unit.squad_fire.has_target_hex or unit.squad_fire.target_unit != null) and TacticalPositionExecutor.select_support_target(unit, current_order.objective_hex) != null:
			return true
	return false


func _has_company_support(departing: Unit = null) -> bool:
	if current_order == null or influence_map_controller == null or influence_map_controller.snapshot == null:
		return false
	var has_defenders: bool = _has_known_attack_defenders(squads)
	for unit: Unit in company_support_squads:
		if unit == departing or not _can_provide_attack_support(unit):
			continue
		var advice: PositionResult = unit.position_advice
		if advice == null or not advice.is_valid() or advice.profile_mode != PositionProfile.Mode.SUPPORT_BY_FIRE or advice.objective_hex != current_order.objective_hex:
			continue
		if unit.movement.is_moving or unit.current_hex != advice.target_hex or unit.action_controller.action_state != SquadActionController.SquadActionState.HOLDING_POSITION:
			continue
		if advice.features.get("cover", 0.0) < 0.1 or advice.features.get("firing", 0.0) <= 0.0:
			continue
		if not has_defenders:
			return true
		if unit.squad_fire != null and (unit.squad_fire.has_target_hex or unit.squad_fire.target_unit != null) and TacticalPositionExecutor.select_support_target(unit, current_order.objective_hex) != null:
			return true
	return false


func _check_company_cover() -> void:
	if not company_requires_support or _has_company_support():
		return
	for unit: Unit in executor.pending.keys():
		var result: PositionResult = executor.pending[unit]["result"]
		if result.profile_mode not in [PositionProfile.Mode.ADVANCE, PositionProfile.Mode.ASSAULT]:
			continue
		executor.cancel(unit, true)
		position_stability.forget(unit)
		accepted_positions.erase(unit)
		company_reservations[unit] = unit.current_hex
		time_until_reconsider = 0.0


func _has_known_attack_defenders(available: Array[Unit]) -> bool:
	for observer: Unit in available:
		for enemy: Unit in Globals.unit_visible_enemies.get(observer, []):
			if TacticalPositionExecutor.is_active_defender(enemy) and LOSHelper.get_hex_distance(enemy.current_hex, current_order.objective_hex) <= current_order.defense_radius:
				return true
	for contact: InfluenceContact in influence_map_controller.snapshot.get_defensive_contacts(team):
		if LOSHelper.get_hex_distance(contact.hex, current_order.objective_hex) > current_order.defense_radius:
			continue
		if not contact.observed or TacticalPositionExecutor.is_active_defender(contact.unit):
			return true
	return false


func _are_visible_attack_defenders_suppressed(available: Array[Unit]) -> bool:
	var defenders: Array[Unit] = []
	for observer: Unit in available:
		for enemy: Unit in Globals.unit_visible_enemies.get(observer, []):
			if not TacticalPositionExecutor.is_active_defender(enemy) or enemy.stress_system == null:
				continue
			if LOSHelper.get_hex_distance(enemy.current_hex, current_order.objective_hex) > current_order.defense_radius:
				continue
			if not defenders.has(enemy):
				defenders.append(enemy)
	for enemy: Unit in defenders:
		if not TacticalPositionExecutor.is_sufficiently_suppressed(enemy):
			return false
	return not defenders.is_empty()


func _attack_support_objective(available: Array[Unit]) -> Vector2i:
	var target: Vector2i = current_order.objective_hex
	var selected: Unit = null
	var selected_suppressed: bool = true
	var lowest_stress: float = INF
	for observer: Unit in available:
		for enemy: Unit in Globals.unit_visible_enemies.get(observer, []):
			if not TacticalPositionExecutor.is_active_defender(enemy) or enemy.stress_system == null:
				continue
			if LOSHelper.get_hex_distance(enemy.current_hex, current_order.objective_hex) > current_order.defense_radius or not TacticalPositionExecutor.support_hex_is_clear(observer, enemy.current_hex):
				continue
			var suppressed: bool = TacticalPositionExecutor.is_sufficiently_suppressed(enemy)
			if selected == null or (selected_suppressed and not suppressed) or (selected_suppressed == suppressed and enemy.stress_system.S_eff < lowest_stress):
				selected = enemy
				selected_suppressed = suppressed
				lowest_stress = enemy.stress_system.S_eff
				target = enemy.current_hex
	if selected == null:
		var best_distance: int = 2147483647
		for contact: InfluenceContact in influence_map_controller.snapshot.get_defensive_contacts(team):
			if contact.observed and not TacticalPositionExecutor.is_active_defender(contact.unit):
				continue
			var distance: int = LOSHelper.get_hex_distance(contact.hex, current_order.objective_hex)
			if distance <= current_order.defense_radius and distance < best_distance:
				target = contact.hex
				best_distance = distance
	return target


func _close_combat_target(unit: Unit) -> Unit:
	if not PositionQueryService.can_assault(unit):
		return null
	for enemy: Unit in Globals.unit_visible_enemies.get(unit, []):
		if not TacticalPositionExecutor.is_sufficiently_suppressed(enemy) or enemy.team == unit.team:
			continue
		if LOSHelper.get_hex_distance(unit.current_hex, enemy.current_hex) != 1:
			continue
		if LOSHelper.get_hex_distance(enemy.current_hex, current_order.objective_hex) > current_order.defense_radius:
			continue
		# Established covering fire can support the final assault despite nearby fresh defenders.
		return enemy
	return null


func _attack_mode_for_unit(unit: Unit) -> PositionProfile.Mode:
	if HqSupportPositionPolicy.is_headquarters(unit):
		return PositionProfile.Mode.HQ_SUPPORT
	if unit.squad_type == Globals.SquadType.MG:
		# Search for a firing lane even when the current hex has no objective LOS.
		return PositionProfile.Mode.SUPPORT_BY_FIRE
	if company_requires_support and not _has_company_support():
		return PositionProfile.Mode.SUPPORT_BY_FIRE
	var pressure_target: Unit = _attack_pressure_target(unit)
	if pressure_target != null:
		if LOSHelper.get_hex_distance(unit.current_hex, pressure_target.current_hex) == 1:
			return PositionProfile.Mode.ASSAULT
		return PositionProfile.Mode.ADVANCE
	if unit != attack_maneuver_squad:
		return PositionProfile.Mode.SUPPORT_BY_FIRE
	if _close_combat_target(unit) != null and _has_established_attack_support(squads):
		return PositionProfile.Mode.ASSAULT
	if not attack_approach_started:
		return PositionProfile.Mode.SUPPORT_BY_FIRE
	return PositionProfile.Mode.ADVANCE


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
	query.departure_baseline = _planning_baseline
	query.has_departure_baseline = true
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
	if query.reserve_position:
		query.profile.firing_weight = 0.0
	_configure_position_stability(query)
	_set_goal_support_reason(query)
	_planning_requests.append({"query": query, "role": role, "axis": null})


func _add_planning_requests(config: InfluenceProjectionConfig, units: Array[Unit], role: String, axis: ThreatAxis) -> void:
	for unit: Unit in units:
		var query: PositionQuery = DefensePositionAnalyzer.make_query(config, unit, _planning_reservations)
		query.snapshot = influence_map_controller.snapshot
		if query.profile.mode == PositionProfile.Mode.HQ_SUPPORT and query.profile.support_assault_squads:
			query.assault_support_squad = attack_maneuver_squad
			if attack_approach_started:
				query.assault_support_squad = _attack_front_squad(squads)
		if current_order.position_mode == PositionProfile.Mode.ASSAULT and query.profile.mode == PositionProfile.Mode.SUPPORT_BY_FIRE:
			# Establish the initial covered firing lane before requiring post-attack retargeting.
			var idle_lane: bool = position_stability.support_lane_failed(unit, query.objective_hex, _position_time())
			query.require_live_support_target = (attack_approach_started or idle_lane) and _has_known_attack_defenders(squads)
			var front: Unit = _attack_front_squad(squads)
			if attack_approach_started and front != null:
				query.has_support_anchor = true
				query.support_anchor_hex = front.current_hex
				query.support_anchor_squad = front
		if current_order.position_mode == PositionProfile.Mode.ASSAULT and query.profile.mode in [PositionProfile.Mode.ADVANCE, PositionProfile.Mode.ASSAULT]:
			query.press_attack = _can_attack_without_overwatch(unit, query.objective_hex)
			if query.press_attack:
				# Known contact capability controls this opportunity, not an older generic forecast.
				query.profile.forecast_weight = 0.0
				query.profile.forecast_route_weight = 0.0
		if current_order.position_mode == PositionProfile.Mode.ASSAULT and query.profile.mode in [PositionProfile.Mode.ADVANCE, PositionProfile.Mode.ASSAULT] and not query.press_attack and not _has_established_attack_support(squads):
			# Wait at the forward position while the covering squad restores its firing lane.
			query.movement_radius = 0
		if query.profile.mode == PositionProfile.Mode.DEFEND:
			query.departure_baseline = _planning_baseline
			query.has_departure_baseline = true
		_configure_position_stability(query)
		_set_goal_support_reason(query)
		_planning_requests.append({"query": query, "role": role, "axis": axis})


func _set_goal_support_reason(query: PositionQuery) -> void:
	if goal_director == null or goal_director.manual_override:
		return
	if goal_director.primary != null:
		query.goal_reason = "Supporting mission: " + goal_director.primary.reason
	elif not goal_director.tasks.is_empty():
		query.goal_reason = goal_director.tasks[0].reason
	elif not goal_director.diagnostics.is_empty():
		query.goal_reason = goal_director.diagnostics[0]


func _submit_planning_query() -> void:
	var query: PositionQuery = _planning_requests[_planning_index]["query"]
	query.stability_time = _position_time()
	_planning_job = influence_map_controller.enqueue_position_query(query)


func _position_time() -> float:
	var now: float = float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)
	if influence_map_controller != null and influence_map_controller.snapshot != null:
		now = maxf(now, influence_map_controller.snapshot.captured_at)
	return now


func _configure_position_stability(query: PositionQuery) -> void:
	_sync_position_mission()
	query.stability = position_stability
	query.stability_time = _position_time()
	query.mission_objective_hex = current_order.objective_hex
	query.deliberate_movement = current_order.position_mode == PositionProfile.Mode.ASSAULT and query.profile.mode in [PositionProfile.Mode.ADVANCE, PositionProfile.Mode.ASSAULT]
	if current_order.position_mode != PositionProfile.Mode.DEFEND:
		return
	if goal_director != null and not goal_director.manual_override and not goal_director.conditions.is_empty():
		query.objective_guard_required = false
		for task: ScenarioGoalTask in goal_director.tasks:
			if task.kind == ScenarioGoalTask.Kind.OCCUPY and task.hex == query.objective_hex:
				query.objective_guard_required = true
				query.protect_garrison_hex = query.defense_responsibility == PositionQuery.Responsibility.COVER_APPROACH
				break
	query.rapid_response = true
	query.optimize_position = false
	if query.profile.mode == PositionProfile.Mode.DEFEND and query.defense_responsibility == PositionQuery.Responsibility.COVER_APPROACH and not query.reserve_position and InfluenceUnitQuery.get_unit_range(query.unit) > 2:
		var screen_strength: int = 0
		for unit: Unit in squads:
			if DefenseSectorAllocator.combat_reserve_capable(unit):
				screen_strength += 1
		if screen_strength >= 3:
			query.minimum_forward_progress = 2
	query.initial_deployment = not accepted_positions.has(query.unit) and query.profile.mode == PositionProfile.Mode.DEFEND and query.defense_responsibility == PositionQuery.Responsibility.COVER_APPROACH
	query.response_priority = 1
	if accepted_positions.has(query.unit):
		query.response_priority = 0
		var record: Dictionary = position_stability.orders.get(query.unit, {})
		if not record.is_empty() and not PlatoonPositionStability.is_busy(query.unit):
			var seconds: float = 8.0
			if query.unit.squad_type == Globals.SquadType.MG:
				seconds = 16.0
			if _position_time() - record["settled_at"] >= seconds and _position_time() >= _position_optimization_due.get(query.unit, -INF):
				query.optimize_position = true
				_position_optimization_due[query.unit] = _position_time() + POSITION_OPTIMIZATION_SECONDS
	if _defense_urgent_units.has(query.unit):
		query.response_priority = 3
		query.optimize_position = false
	elif query.defense_responsibility == PositionQuery.Responsibility.GUARD and not accepted_positions.has(query.unit):
		query.response_priority = 2
	elif query.required_crossing_branch != "":
		query.response_priority = 2
	elif query.reserve_position:
		# A protected reserve's exhaustive response search cannot delay initial front deployment.
		query.response_priority = 0


func _sync_position_mission() -> void:
	var context: String = str([current_order.objective_hex, current_order.position_mode, current_order.geography, current_order.sector_cells, current_order.defense_responsibility])
	if context != _position_mission_context:
		position_stability.clear()
		_position_optimization_due.clear()
		_reset_defense_events()
		_position_mission_context = context


func _reset_defense_events() -> void:
	_defense_capabilities.clear()
	_defense_observed_hexes.clear()
	_defense_urgent_units.clear()
	_defense_events_initialized = false
	_defense_event_timer = 0.0
	_defense_refresh_version = -1


func _check_defense_events() -> void:
	if influence_map_controller == null or current_order == null or current_order.position_mode != PositionProfile.Mode.DEFEND:
		return
	var changed: bool = false
	var observed: Dictionary[Unit, Vector2i] = {}
	for squad: Unit in squads:
		if not is_instance_valid(squad):
			continue
		var capable: bool = TacticalPositionExecutor.is_active_defender(squad) and PositionQueryService.can_follow_intent(squad) and not squad.broken and InfluenceUnitQuery.get_unit_effectiveness(squad) >= 0.45
		if _defense_events_initialized and _defense_capabilities.get(squad, capable) and not capable:
			_mark_defense_response(squad.current_hex)
			changed = true
		_defense_capabilities[squad] = capable
		for enemy: Unit in Globals.unit_visible_enemies.get(squad, []):
			if TacticalPositionExecutor.is_active_defender(enemy) and enemy.team != team:
				observed[enemy] = enemy.current_hex
	if influence_map_controller.knowledge_policy == InfluenceMapController.KnowledgePolicy.OMNISCIENT:
		for enemy: Unit in Globals.get_units_for_team(Globals.get_enemy_team(team)):
			if TacticalPositionExecutor.is_active_defender(enemy):
				observed[enemy] = enemy.current_hex
	for enemy: Unit in observed:
		var hex: Vector2i = observed[enemy]
		var significant: bool = not _defense_observed_hexes.has(enemy)
		if not significant:
			var previous: Vector2i = _defense_observed_hexes[enemy]
			significant = LOSHelper.get_hex_distance(hex, previous) >= 2 or DefenseAreaAssessment.sector_for(current_order.objective_hex, hex) != DefenseAreaAssessment.sector_for(current_order.objective_hex, previous)
			if LOSHelper.get_hex_distance(hex, current_order.objective_hex) <= current_order.defense_radius:
				significant = significant or LOSHelper.get_hex_distance(hex, current_order.objective_hex) < LOSHelper.get_hex_distance(previous, current_order.objective_hex)
		if significant:
			_defense_observed_hexes[enemy] = hex
			if _defense_events_initialized:
				_mark_defense_response(hex)
				changed = true
	_defense_events_initialized = true
	if changed:
		_defense_refresh_version = influence_map_controller.request_defense_refresh()
		time_until_reconsider = 0.0


func _mark_defense_response(hex: Vector2i) -> void:
	var sector: int = DefenseAreaAssessment.sector_for(current_order.objective_hex, hex)
	var nearest: Unit = null
	var nearest_distance: int = 2147483647
	for squad: Unit in squads:
		if HqSupportPositionPolicy.is_headquarters(squad) or not TacticalPositionExecutor.is_active_defender(squad) or not PositionQueryService.can_follow_intent(squad):
			continue
		var distance: int = LOSHelper.get_hex_distance(squad.current_hex, hex)
		if distance < nearest_distance:
			nearest = squad
			nearest_distance = distance
		var assignment: Dictionary = squad_assignments.get(squad, {})
		var assigned_sector: int = -1
		if assignment.has("result"):
			assigned_sector = assignment["result"].features.get("assigned_sector", -1)
		if squad == reserve_squad or assigned_sector == sector or distance <= 2:
			_defense_urgent_units[squad] = true
	if nearest != null:
		_defense_urgent_units[nearest] = true


func _continue_budgeted_plan() -> void:
	if _planning_job == null:
		return
	var mission_objective: Vector2i = _planning_job.query.objective_hex
	if current_order.position_mode == PositionProfile.Mode.ASSAULT or _planning_job.query.goal_key != "":
		mission_objective = _planning_objective_hex
	if _planning_job.canceled or current_order.objective_hex != mission_objective:
		_cancel_plan()
		time_until_reconsider = 0.0
		return
	if not _planning_job.completed:
		return
	var query: PositionQuery = _planning_job.query
	# Keep only the checked route suffix when an owned move has advanced.
	if not PositionQueryService.refresh_moving_origin(query, _planning_job.result):
		_cancel_plan()
		time_until_reconsider = 0.0
		return
	_accept_planning_result(_planning_requests[_planning_index], _planning_job.result)
	_planning_job = null
	_validation_job = DefensePlanValidationJob.new()
	_validation_job.report_gaps = false
	_validation_job.start(query.defense_area, [_planning_requests[_planning_index]], [_planning_results[_planning_index]])
	_validating_batch = false


func _refresh_coverage_delay() -> void:
	var now: float = maxf(influence_map_controller.snapshot.captured_at, float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second))
	for request: Dictionary in _planning_requests:
		var query: PositionQuery = request["query"]
		query.coverage_delay_seconds = maxf(0.0, now - query.snapshot.captured_at)


func _publish_ready_result() -> void:
	var result: DefensePositionResult = _planning_results[_planning_index]
	var query: PositionQuery = _planning_requests[_planning_index]["query"]
	if not PositionQueryService.refresh_moving_origin(query, result) or _defense_plan_outdated():
		_cancel_plan()
		time_until_reconsider = 0.0
		return
	# Publish only checked advice. Later departures are checked against this live
	# movement and its reservation, never against its promised future firing lane.
	_apply_position_results([result], result.role, result.axis)
	_issue_order(result.unit)
	var accepted: Dictionary = accepted_positions.get(result.unit, {})
	if result.is_valid() and accepted.get("hex") == result.target_hex and accepted.get("context") == result.context:
		query.has_accepted_target = true
		query.accepted_target = result.target_hex
		query.accepted_context = result.context
		query.movement_order_id = result.unit.action_controller.action_order_id
		if result.unit.movement.is_moving and result.unit.movement.target_hex == result.target_hex:
			result.should_move = false
			squad_assignments[result.unit]["should_move"] = false
	_validation_job = null
	_planning_index += 1
	if _planning_index < _planning_requests.size():
		_submit_planning_query()
	else:
		_validation_job = DefensePlanValidationJob.new()
		var assessment: DefenseAreaAssessment = null
		if current_order.position_mode == PositionProfile.Mode.DEFEND:
			assessment = defense_area
		_validation_job.start(assessment, _planning_requests, _planning_results)
		_validating_batch = true


func _accept_planning_result(request: Dictionary, advice: PositionResult) -> void:
	var result: DefensePositionResult = DefensePositionAnalyzer.adapt_result(advice, request["axis"], request["role"])
	_planning_results.append(result)
	if result.is_valid():
		_planning_reservations[result.unit] = result.target_hex


func _commit_plan() -> void:
	if _defense_plan_outdated() or (_validation_job != null and (not _validation_job.completed or not _validation_job.valid or not _validation_job.unchanged())):
		_cancel_plan()
		time_until_reconsider = 0.0
		return
	for index: int in range(_planning_requests.size()):
		var query: PositionQuery = _planning_requests[index]["query"]
		if not PositionQueryService.refresh_moving_origin(query, _planning_results[index]):
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
			query.baseline_screen.clear()
			query.handoff_prepared = false
			var protection: Dictionary = DefensePositionPolicy.evaluate(query, result.target_hex)
			if protection["responsibility"] == "" or not protection["preserves_screen"] or not DefensePositionPolicy.handoff_ready(query, result.target_hex, result.features):
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
	_planning_baseline = {}
	_validation_job = null
	_planning_readiness = null
	_validating_batch = false


func _defense_plan_outdated() -> bool:
	if current_order == null or influence_map_controller == null or influence_map_controller.snapshot == null or current_order.position_mode != PositionProfile.Mode.DEFEND or defense_area == null:
		return false
	for contact: InfluenceContact in influence_map_controller.snapshot.get_contacts(team):
		if contact.observed:
			if not defense_area.observed_contacts.has(contact.unit):
				return true
			var captured: Vector2i = defense_area.observed_contacts[contact.unit]
			var distance: int = LOSHelper.get_hex_distance(contact.hex, current_order.objective_hex)
			if distance <= current_order.defense_radius and distance < LOSHelper.get_hex_distance(captured, current_order.objective_hex):
				return true
			if defense_area.sector_at(contact.hex) != defense_area.sector_at(captured) or LOSHelper.get_hex_distance(contact.hex, captured) >= 2:
				return true
	return false


func _cancel_plan() -> void:
	position_stability.release_unstarted_optional()
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
	_planning_baseline = {}
	_planning_index = 0
	_planning_snapshot = null
	_validating_batch = false


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
		_issue_order(squad)


func _issue_order(squad: Unit) -> void:
	var result: PositionResult = squad_assignments[squad]["result"]
	if result.is_valid() and result.profile_mode == PositionProfile.Mode.SUPPORT_BY_FIRE and result.should_move and not company_maneuver_squads.is_empty():
		var bound: bool = false
		for maneuver: Unit in company_maneuver_squads:
			if InfluenceUnitQuery.is_valid_living_unit(maneuver) and (maneuver.movement.is_moving or maneuver.in_close_combat):
				bound = true
		if bound and _has_established_attack_support(squads) and not _has_established_attack_support(squads, squad):
			position_stability.declined(squad)
			return
	if result.is_valid() and not company_reservations.is_empty():
		var capacity: int = 1
		if goal_assignments.has(squad) and goal_assignments[squad].is_destination_goal():
			capacity = goal_assignments[squad].required_units
			if goal_assignments[squad].kind == ScenarioGoalTask.Kind.EXIT:
				capacity = goal_assignments[squad].exit_capacity()
		var occupants: Dictionary[Unit, bool] = {}
		for other: Unit in company_reservations:
			if other == squad or not TacticalPositionExecutor.is_active_defender(other) or HqSupportPositionPolicy.can_share_position(squad, other):
				continue
			if company_reservations[other] == result.target_hex or other.current_hex == result.target_hex:
				occupants[other] = true
		if occupants.size() >= capacity:
			result.status = PositionResult.Status.NO_CANDIDATE
			result.should_move = false
			result.reason = "Position occupied or claimed by another platoon"
			time_until_reconsider = 0.0
			return
	var clear_exit: bool = goal_assignments.has(squad) and goal_assignments[squad].kind == ScenarioGoalTask.Kind.EXIT and not goal_assignments[squad].breach_required
	if result.is_valid() and company_requires_support and not clear_exit and result.profile_mode in [PositionProfile.Mode.ADVANCE, PositionProfile.Mode.ASSAULT] and not _has_company_support():
		executor.cancel(squad, true)
		position_stability.forget(squad)
		accepted_positions.erase(squad)
		company_reservations[squad] = squad.current_hex
		time_until_reconsider = 0.0
		return
	if result.is_valid() and result.features.has("scenario_goal") and result.profile_mode in [PositionProfile.Mode.ADVANCE, PositionProfile.Mode.ASSAULT]:
		var check: PositionQuery = PositionQuery.new()
		check.unit = squad
		check.team = team
		check.snapshot = influence_map_controller.snapshot
		check.objective_hex = result.objective_hex
		check.origin_hex = squad.current_hex
		check.profile = result.position_profile
		check.press_attack = _can_attack_without_overwatch(squad, result.objective_hex)
		var safe: bool = not result.features.get("press_attack", false) or check.press_attack
		if check.profile.avoid_unsuppressed_defenders:
			safe = safe and PositionQueryService.approach_path_is_safe(check, result.path)
		var requires_cover: bool = false
		var overwhelmed_goal: bool = false
		if squad.current_hex != result.objective_hex:
			for contact: InfluenceContact in check.snapshot.get_contacts(team):
				if contact.observed and contact.hex == result.objective_hex and TacticalPositionExecutor.is_overwhelmed(contact.unit):
					overwhelmed_goal = true
				if contact.observed and LOSHelper.get_hex_distance(contact.hex, result.objective_hex) <= 2 and TacticalPositionExecutor.is_active_defender(contact.unit) and not TacticalPositionExecutor.is_overwhelmed(contact.unit):
					requires_cover = true
		if requires_cover and not check.press_attack and not overwhelmed_goal:
			safe = safe and _goal_support_ready(squad, result.objective_hex)
		if not safe:
			executor.cancel(squad, true)
			position_stability.forget(squad)
			accepted_positions.erase(squad)
			reserved_hexes_by_squad[squad] = squad.current_hex
			_planning_reservations[squad] = squad.current_hex
			time_until_reconsider = 0.0
			return
	if result.is_valid() and result.profile_mode == PositionProfile.Mode.HQ_SUPPORT and result.features.get("open_support_position", false):
		if HqSupportPositionPolicy.known_good_order_enemy_has_los(influence_map_controller.snapshot, team, result.target_hex):
			# Suppression can end while a budgeted query or an accepted move is in progress.
			executor.cancel(squad, true)
			position_stability.forget(squad)
			accepted_positions.erase(squad)
			reserved_hexes_by_squad[squad] = squad.current_hex
			_planning_reservations[squad] = squad.current_hex
			time_until_reconsider = 0.0
			return
	if current_order != null and current_order.position_mode == PositionProfile.Mode.ASSAULT and not result.features.has("scenario_goal"):
		var press_attack: bool = _can_attack_without_overwatch(squad, result.objective_hex)
		if press_attack and result.profile_mode in [PositionProfile.Mode.ADVANCE, PositionProfile.Mode.ASSAULT]:
			press_attack = PositionQueryService.press_attack_path_is_safe(influence_map_controller.snapshot, team, squad.current_hex, result.path)
		if result.profile_mode in [PositionProfile.Mode.ADVANCE, PositionProfile.Mode.ASSAULT] and not press_attack and (result.features.get("press_attack", false) or not _has_established_attack_support(squads)):
			executor.cancel(squad, true)
			position_stability.forget(squad)
			accepted_positions.erase(squad)
			reserved_hexes_by_squad[squad] = squad.current_hex
			_planning_reservations[squad] = squad.current_hex
			return
		if result.profile_mode == PositionProfile.Mode.SUPPORT_BY_FIRE and result.should_move and not _has_pressing_attack(squads):
			var protects_attack: bool = _has_attack_bound(squads) or (_has_known_attack_defenders(squads) and _has_established_attack_support(squads))
			if protects_attack and not _has_established_attack_support(squads, squad):
				# Keep actual suppression while other squads restore or improve their positions.
				reserved_hexes_by_squad[squad] = squad.current_hex
				_planning_reservations[squad] = squad.current_hex
				position_stability.declined(squad)
				return
	var departing: bool = result.should_move and result.target_hex != squad.current_hex and result.profile_mode == PositionProfile.Mode.DEFEND
	var origin: Vector2i = squad.current_hex
	squad.position_advice = result
	squad.influence_map = result.score_map
	var intent: TacticalPositionExecutor.Intent = TacticalPositionExecutor.Intent.FROM_PROFILE
	if current_order != null and current_order.position_mode != PositionProfile.Mode.ASSAULT and not result.features.has("scenario_goal"):
		intent = current_order.execution_intent
	if result.is_valid() and executor.execute(result, intent):
		if not company_reservations.is_empty():
			company_reservations[squad] = result.target_hex
		position_stability.accepted(result, _position_time())
		_defense_urgent_units.erase(squad)
		if departing and not _departure_origins.has(squad):
			_departure_origins[squad] = _planning_baseline.get(squad, origin)
		var accepted_at: float = influence_map_controller.snapshot.captured_at
		var previous: Dictionary = accepted_positions.get(squad, {})
		if previous.get("hex") == result.target_hex and previous.get("context") == result.context:
			accepted_at = previous.get("at", accepted_at)
		accepted_positions[squad] = {"hex": result.target_hex, "context": result.context, "at": accepted_at}
		squad.best_index = result.target_index
	else:
		executor.cancel(squad, true)
		position_stability.forget(squad)
		accepted_positions.erase(squad)
		reserved_hexes_by_squad[squad] = squad.current_hex
		_planning_reservations[squad] = squad.current_hex


func _get_effective_squads() -> Array[Unit]:
	var result: Array[Unit] = []
	for squad: Unit in squads:
		if InfluenceUnitQuery.is_valid_living_unit(squad) and squad.team == team and squad.members_alive > 0 and squad.movement != null and influence_map_controller.snapshot.positions.has(squad) and not result.has(squad):
			result.append(squad)
	result.sort_custom(InfluenceUnitQuery.compare_units_by_squad_type_priority)
	return result


func _create_current_reserved_hexes(units: Array[Unit]) -> Dictionary:
	var result: Dictionary = company_reservations.duplicate()
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
