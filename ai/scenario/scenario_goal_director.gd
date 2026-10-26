class_name ScenarioGoalDirector
extends RefCounted

const REASSESS_SECONDS: float = 0.5
const BREACH_SEARCH_BUDGET_USEC: int = 1500
const MISSION_HOLD_SECONDS: float = 8.0
const CHANGE_CONFIRM_SECONDS: float = 3.0

var team: Globals.Team
var conditions: Array[VictoryCondition] = []
var posture: PositionProfile.Mode = PositionProfile.Mode.DEFEND
var tasks: Array[ScenarioGoalTask] = []
var assignments: Dictionary[Unit, ScenarioGoalTask] = {}
var diagnostics: PackedStringArray = []
var primary: ScenarioGoalTask
var manual_override: bool = false
var fallback_policies: Array[HoldToExitFallbackPolicy] = []
var escape_policies: Array[EscapeMissionPolicy] = []
var _fallback_escape_policy: EscapeMissionPolicy
var active_fallback: HoldToExitFallbackPolicy
var fallback_reason: String = ""
var _fallback_pending_since: Dictionary[HoldToExitFallbackPolicy, float] = {}
var _secured_holds: Dictionary[OccupyObjectiveCondition, bool] = {}
var _lost_objectives: Dictionary[Vector2i, bool] = {}
var _initial_combat_personnel: int = -1
var _policy_diagnostics: PackedStringArray = []
var _next_update: float = -INF
var _primary_since: float = -INF
var _contender: String = ""
var _contender_since: float = -INF
var _last_objective: Vector2i
var _initialized: bool = false
var last_breach_slice_usec: int = 0
var _breach_search: ExitBreachPlanner.Search
var _budgeted_update: bool = false
var _breach_pending: bool = false


func configure(owner: Globals.Team, scenario_conditions: Array[VictoryCondition], mode: PositionProfile.Mode, policies: Array[HoldToExitFallbackPolicy] = [], escapes: Array[EscapeMissionPolicy] = []) -> void:
	team = owner
	conditions.clear()
	for condition: VictoryCondition in scenario_conditions:
		if condition != null and condition.team == owner:
			conditions.append(condition)
	fallback_policies.clear()
	escape_policies.clear()
	_fallback_escape_policy = null
	_policy_diagnostics.clear()
	active_fallback = null
	fallback_reason = ""
	_fallback_pending_since.clear()
	_secured_holds.clear()
	_lost_objectives.clear()
	_initial_combat_personnel = -1
	for policy: HoldToExitFallbackPolicy in policies:
		if policy == null or not policy.enabled:
			continue
		if policy.hold_condition != null and policy.hold_condition.team != team:
			continue
		var error: String = policy.configuration_error(conditions)
		if error != "":
			_policy_diagnostics.append(error)
		elif not fallback_policies.has(policy):
			fallback_policies.append(policy)
	for policy: EscapeMissionPolicy in escapes:
		if policy == null or not policy.enabled:
			continue
		if policy.exit_condition != null and policy.exit_condition.team != team:
			continue
		var error: String = policy.configuration_error(conditions)
		if error != "":
			_policy_diagnostics.append(error)
		elif not escape_policies.has(policy):
			escape_policies.append(policy)
	change_posture(mode)


func change_posture(mode: PositionProfile.Mode) -> void:
	# Debug posture changes reset tactical planning, not an accepted withdrawal.
	posture = mode
	tasks.clear()
	assignments.clear()
	diagnostics.clear()
	primary = null
	manual_override = false
	_initialized = false
	_next_update = -INF
	_breach_search = null
	_breach_pending = false
	last_breach_slice_usec = 0
	_primary_since = -INF
	_contender = ""


func initial_order(planner: PlatoonAI, fallback: MissionOrder, seconds_left: float) -> MissionOrder:
	_build_tasks(planner, seconds_left)
	primary = _preferred_primary()
	if primary != null:
		fallback.objective_hex = primary.hex
		fallback.sector_cells = []
		fallback.fallback_hexes = []
	else:
		# Without a geographic win condition, remain anchored to our own force.
		for unit: Unit in planner.squads:
			if TacticalPositionExecutor.is_active_defender(unit) and not HqSupportPositionPolicy.is_headquarters(unit):
				fallback.objective_hex = unit.current_hex
				break
	_last_objective = fallback.objective_hex
	_initialized = true
	return fallback


func update(planner: PlatoonAI, seconds_left: float, now: float) -> void:
	if not planner.active or planner.current_order == null or (now < _next_update and _breach_search == null):
		return
	if _initialized and planner.current_order.objective_hex != _last_objective:
		# Debug objective edits remain deliberate overrides until the posture is changed.
		manual_override = true
	if manual_override:
		_breach_search = null
		return
	var previous_tasks: Array[ScenarioGoalTask] = tasks.duplicate()
	var previous_diagnostics: PackedStringArray = diagnostics.duplicate()
	_budgeted_update = planner.is_inside_tree() and planner.is_processing()
	_breach_pending = false
	last_breach_slice_usec = 0
	_build_tasks(planner, seconds_left, now)
	_budgeted_update = false
	if _breach_pending:
		# Do not publish a partially searched mission or change existing squad orders.
		tasks = previous_tasks
		diagnostics = previous_diagnostics
		return
	_breach_search = null
	_next_update = now + REASSESS_SECONDS
	var preferred: ScenarioGoalTask = _preferred_primary()
	if primary == null or not _contains_task(primary.key):
		primary = preferred
		_primary_since = now
	elif preferred != null and preferred.key != primary.key:
		if _contender != preferred.key:
			_contender = preferred.key
			_contender_since = now
		var busy: bool = false
		for unit: Unit in planner.squads:
			if TacticalPositionExecutor.is_active_defender(unit) and PlatoonPositionStability.is_busy(unit):
				busy = true
		if preferred.urgent or (not busy and now - _primary_since >= MISSION_HOLD_SECONDS and now - _contender_since >= CHANGE_CONFIRM_SECONDS):
			primary = preferred
			_primary_since = now
	else:
		_contender = ""
	if primary != null:
		for task: ScenarioGoalTask in tasks:
			if task.key != primary.key:
				continue
			primary.reason = task.reason
			if task.hex == primary.hex:
				primary = task
			elif task.kind == ScenarioGoalTask.Kind.HUNT and now - _primary_since >= MISSION_HOLD_SECONDS and LOSHelper.get_hex_distance(primary.hex, task.hex) >= 2:
				primary = task
				_primary_since = now
			break
	if primary != null and planner.current_order.objective_hex != primary.hex:
		planner.change_scenario_objective(primary.hex)
		_last_objective = primary.hex
	_initialize_primary_time(now)
	_allocate(planner)
	planner.set_scenario_goal_assignments(assignments)


func _initialize_primary_time(now: float) -> void:
	if _primary_since == -INF:
		_primary_since = now


func _build_tasks(planner: PlatoonAI, seconds_left: float, now: float = -INF) -> void:
	tasks.clear()
	diagnostics = _policy_diagnostics.duplicate()
	var progress: Array[VictoryConditionProgress] = []
	for condition: VictoryCondition in conditions:
		var state: VictoryConditionProgress = VictoryConditionProgress.read(condition)
		progress.append(state)
		if not state.valid:
			diagnostics.append(state.diagnostic)
	_update_objective_control(progress, planner)
	_evaluate_fallbacks(progress, planner, seconds_left, now)
	var escape: EscapeMissionPolicy = _escape_mission(progress)
	if escape != null:
		_add_escape_task(escape, planner)
		return
	var own_level: int = _choose_own_outcome(progress, planner, seconds_left)
	for state: VictoryConditionProgress in progress:
		if state.team == team and state.outcome == own_level and state.valid:
			_add_own_tasks(state, planner)
	_prioritize_garrisons(planner)
	for task: ScenarioGoalTask in tasks:
		if task.kind != ScenarioGoalTask.Kind.EXIT:
			continue
		var breach: InfluenceContact = ExitBreachPlanner.select(planner, ScenarioGoalTask.exit_state_for(task.condition).exit_hexes)
		if breach != null:
			task.breach_required = true
			task.breach_hex = breach.hex
			# Concentrate the column before assigning squads to other objectives.
			task.priority = maxf(task.priority, 140.0)
			task.urgent = true
			task.reason += "; breach the weakest defended corridor at " + str(breach.hex)
	tasks.sort_custom(_prefer_task)


func _escape_mission(progress: Array[VictoryConditionProgress]) -> EscapeMissionPolicy:
	if active_fallback != null:
		var state: VictoryConditionProgress = _progress_for(active_fallback.exit_condition, progress)
		if state == null or not state.valid:
			return null
		if _fallback_escape_policy == null:
			_fallback_escape_policy = EscapeMissionPolicy.new()
		_fallback_escape_policy.exit_condition = active_fallback.exit_condition
		_fallback_escape_policy.withdraw_entire_force = active_fallback.withdraw_entire_force
		_fallback_escape_policy.include_headquarters = active_fallback.withdraw_entire_force
		return _fallback_escape_policy
	for policy: EscapeMissionPolicy in escape_policies:
		var state: VictoryConditionProgress = _progress_for(policy.exit_condition, progress)
		if state != null and state.valid:
			return policy
	return null


func _add_escape_task(policy: EscapeMissionPolicy, planner: PlatoonAI) -> void:
	var state: VictoryConditionProgress = VictoryConditionProgress.read(policy.exit_condition)
	var demand: int = state.remaining_units
	if policy.withdraw_entire_force:
		demand = 0
		for unit: Unit in planner.squads:
			if TacticalPositionExecutor.is_active_defender(unit) and policy.allows(unit):
				demand += 1
	if demand <= 0:
		return
	var anchor: Vector2i = _exit_hex(state, planner)
	if primary != null and primary.condition == policy.exit_condition and state.hexes.has(primary.hex):
		# Each unit chooses its own exit corridor. Keep the company mission anchor stable.
		anchor = primary.hex
	var task: ScenarioGoalTask = _task(state, ScenarioGoalTask.Kind.EXIT, anchor)
	# A different exit or a temporary breach must not become a different strategic mission.
	task.key = str([state.condition.get_instance_id(), ScenarioGoalTask.Kind.EXIT, "escape"])
	task.escape_policy = policy
	for unit: Unit in planner.squads:
		if TacticalPositionExecutor.is_active_defender(unit) and policy.allows(unit) and (not unit.is_good_order() or not PositionQueryService.can_follow_intent(unit)):
			task.recovering_units[unit] = true
	task.withdrawal = policy.withdraw_entire_force
	task.required_units = demand
	task.priority = 200.0
	task.urgent = true
	task.reason = "Escape to an exit: %d more distinct units required" % state.remaining_units
	if active_fallback != null:
		task.reason = "Withdraw to exit: " + fallback_reason
	var breach: InfluenceContact = _escape_breach(planner, state.hexes, policy, task.bypass_units)
	if breach != null:
		task.breach_required = true
		task.breach_hex = breach.hex
		task.reason += "; open a passage at " + str(breach.hex)
	tasks.append(task)


func _escape_breach(planner: PlatoonAI, exits: Array[Vector2i], policy: EscapeMissionPolicy, bypass_units: Dictionary[Unit, bool]) -> InfluenceContact:
	if not _budgeted_update:
		_breach_search = null
		return ExitBreachPlanner.select(planner, exits, policy, bypass_units)
	var started: int = Time.get_ticks_usec()
	if _breach_search == null or not _breach_search.matches(planner, exits, policy):
		_breach_search = ExitBreachPlanner.Search.new()
		_breach_search.start(planner, exits, policy)
	_breach_search.advance(started + BREACH_SEARCH_BUDGET_USEC)
	last_breach_slice_usec = Time.get_ticks_usec() - started
	if not _breach_search.completed:
		_breach_pending = true
		return null
	bypass_units.merge(_breach_search.bypass_units)
	return _breach_search.result


func _progress_for(condition: VictoryCondition, progress: Array[VictoryConditionProgress]) -> VictoryConditionProgress:
	for state: VictoryConditionProgress in progress:
		if state.condition == condition:
			return state
	return null


func _policy_has_markers(policy: HoldToExitFallbackPolicy, progress: Array[VictoryConditionProgress]) -> bool:
	var hold: VictoryConditionProgress = _progress_for(policy.hold_condition, progress)
	var exit: VictoryConditionProgress = _progress_for(policy.exit_condition, progress)
	return hold != null and hold.valid and exit != null and exit.valid


func _hold_hexes(progress: Array[VictoryConditionProgress], level: int = -1) -> Array[Vector2i]:
	var hexes: Array[Vector2i] = []
	for state: VictoryConditionProgress in progress:
		if state.team != team or state.kind != VictoryConditionProgress.Kind.OCCUPY or not state.valid or (level >= 0 and state.outcome != level):
			continue
		for hex: Vector2i in state.hexes:
			if not hexes.has(hex):
				hexes.append(hex)
	return hexes


func _friendly_on_objective(planner: PlatoonAI, hex: Vector2i) -> bool:
	for unit: Unit in planner.squads:
		if unit.current_hex == hex and TacticalPositionExecutor.is_active_defender(unit) and unit.is_good_order():
			return true
	return false


func _update_objective_control(progress: Array[VictoryConditionProgress], planner: PlatoonAI) -> void:
	if _initial_combat_personnel < 0:
		_initial_combat_personnel = 0
		for unit: Unit in planner.squads:
			if TacticalPositionExecutor.is_active_defender(unit) and not HqSupportPositionPolicy.is_headquarters(unit):
				_initial_combat_personnel += unit.members_alive
	for hex: Vector2i in _hold_hexes(progress):
		var enemy_present: bool = false
		for contact: InfluenceContact in _contacts(planner):
			if contact.observed and contact.hex == hex and TacticalPositionExecutor.is_active_defender(contact.unit) and contact.unit.is_good_order():
				enemy_present = true
				break
		var friendly_present: bool = _friendly_on_objective(planner, hex)
		if enemy_present and not friendly_present:
			_lost_objectives[hex] = true
		elif friendly_present and not enemy_present:
			# Recover control immediately; the victory hold timer can finish later.
			_lost_objectives.erase(hex)
		# Remember an observed capture until retaken. Empty or initially unsecured
		# markers and hidden live enemy positions are not evidence of a capture.


func _prioritize_garrisons(planner: PlatoonAI) -> void:
	if posture != PositionProfile.Mode.DEFEND:
		return
	var objectives: Array[Vector2i] = []
	for task: ScenarioGoalTask in tasks:
		if task.kind == ScenarioGoalTask.Kind.OCCUPY and not objectives.has(task.hex):
			objectives.append(task.hex)
	if objectives.size() < 2:
		return
	for task: ScenarioGoalTask in tasks:
		if task.kind == ScenarioGoalTask.Kind.OCCUPY and _friendly_on_objective(planner, task.hex):
			# Allocate intact garrisons before sending local forces to recapture a
			# lost objective.
			task.priority = maxf(task.priority, 130.0)


func _multi_objective_failure_reason(policy: HoldToExitFallbackPolicy, hexes: Array[Vector2i], planner: PlatoonAI) -> String:
	var lost: int = 0
	for hex: Vector2i in hexes:
		if _lost_objectives.has(hex):
			lost += 1
	if lost < policy.minimum_lost_objectives:
		return ""
	var fighters: int = 0
	var personnel: int = 0
	for unit: Unit in planner.squads:
		if TacticalPositionExecutor.is_active_defender(unit) and unit.is_good_order() and not HqSupportPositionPolicy.is_headquarters(unit):
			fighters += 1
			personnel += unit.members_alive
	var depleted: bool = policy.minimum_combat_squads > 0 and fighters < policy.minimum_combat_squads
	if _initial_combat_personnel > 0 and float(personnel) / float(_initial_combat_personnel) < policy.withdrawal_strength_ratio:
		depleted = true
	if not depleted:
		return ""
	return "%d/%d objectives lost; combat squads remaining: %d; ready combat personnel: %d/%d" % [lost, hexes.size(), fighters, personnel, _initial_combat_personnel]


func _evaluate_fallbacks(progress: Array[VictoryConditionProgress], planner: PlatoonAI, seconds_left: float, now: float) -> void:
	if active_fallback != null:
		diagnostics.append("Committed hold-to-exit fallback: " + fallback_reason)
		return
	for policy: HoldToExitFallbackPolicy in fallback_policies:
		if not _policy_has_markers(policy, progress):
			_fallback_pending_since.erase(policy)
			diagnostics.append("Hold-to-exit fallback awaits valid hold and exit markers")
			continue
		var hold: VictoryConditionProgress = _progress_for(policy.hold_condition, progress)
		var exit: VictoryConditionProgress = _progress_for(policy.exit_condition, progress)
		if hold.complete:
			_secured_holds[policy.hold_condition] = true
		var hexes: Array[Vector2i] = _hold_hexes(progress, hold.outcome)
		var reason: String = ""
		if hexes.size() > 1:
			# A setback at one district is a local defense problem. Neither the
			# linked hold timer nor the exit deadline can bypass both loss gates.
			reason = _multi_objective_failure_reason(policy, hexes, planner)
		else:
			reason = _hold_failure_reason(hold, planner, seconds_left, policy.minimum_combat_squads)
			var travel: float = _estimate_exit_seconds(exit, planner, policy.withdraw_entire_force)
			if not hold.complete and is_finite(travel) and seconds_left <= travel + policy.withdrawal_margin_seconds:
				_activate_fallback(policy, "Unsecured objective: %.1f seconds left; %.1f seconds reserved for exit" % [seconds_left, travel + policy.withdrawal_margin_seconds])
				return
		if reason == "":
			_fallback_pending_since.erase(policy)
			continue
		if policy.confirmation_seconds <= 0.0:
			_activate_fallback(policy, reason)
			return
		if not is_finite(now):
			continue
		if not _fallback_pending_since.has(policy):
			_fallback_pending_since[policy] = now
		var elapsed: float = now - _fallback_pending_since[policy]
		if elapsed >= policy.confirmation_seconds:
			_activate_fallback(policy, reason)
			return
		diagnostics.append("Hold-to-exit pending: %s (%.1f/%.1f seconds)" % [reason, elapsed, policy.confirmation_seconds])


func _activate_fallback(policy: HoldToExitFallbackPolicy, reason: String) -> void:
	active_fallback = policy
	fallback_reason = reason
	_fallback_pending_since.clear()
	diagnostics.append("Committed hold-to-exit fallback: " + reason)


func _hold_failure_reason(hold: VictoryConditionProgress, planner: PlatoonAI, seconds_left: float, minimum_combat_squads: int = 0) -> String:
	var fighters: int = 0
	for unit: Unit in planner.squads:
		if TacticalPositionExecutor.is_active_defender(unit) and unit.is_good_order() and not HqSupportPositionPolicy.is_headquarters(unit):
			fighters += 1
	# Operational strength is separate from the occupation victory threshold.
	# A depleted force can withdraw even while its last squad still holds the hex.
	if minimum_combat_squads > 0 and fighters < minimum_combat_squads:
		return "Combat squads remaining: %d; minimum required to hold: %d" % [fighters, minimum_combat_squads]
	if hold.complete:
		return ""
	if _secured_holds.has(hold.condition):
		return "Previously secured objective was lost"
	if fighters < hold.required_units * hold.hexes.size():
		return "Too few combat squads remain to hold all linked markers"
	for hex: Vector2i in hold.hexes:
		var travel: float = _travel_seconds(planner, hex)
		if not is_finite(travel):
			return "No eligible squad can currently reach the hold objective"
		if travel + maxf(0.0, hold.required_seconds - hold.held_seconds.get(hex, 0.0)) > seconds_left:
			return "Insufficient time to reach and secure the hold objective"
	return ""


func _estimate_exit_seconds(exit: VictoryConditionProgress, planner: PlatoonAI, entire_force: bool) -> float:
	var arrivals: Array[float] = []
	var ledger: ExitUnitsState = ScenarioGoalTask.exit_state_for(exit.condition)
	for unit: Unit in planner.squads:
		if not TacticalPositionExecutor.is_active_defender(unit):
			continue
		if not entire_force and (HqSupportPositionPolicy.is_headquarters(unit) or ledger.units_exited.has(unit)):
			continue
		var travel: float = INF
		for hex: Vector2i in exit.hexes:
			travel = minf(travel, _unit_travel_seconds(planner, unit, hex))
		if is_finite(travel):
			arrivals.append(travel)
	if entire_force:
		if arrivals.is_empty():
			return INF
		return arrivals.max()
	if exit.remaining_units <= 0:
		return 0.0
	if arrivals.size() < exit.remaining_units:
		return INF
	arrivals.sort()
	return arrivals[exit.remaining_units - 1]


func _choose_own_outcome(progress: Array[VictoryConditionProgress], planner: PlatoonAI, seconds_left: float) -> int:
	if active_fallback != null:
		return active_fallback.exit_condition.outcome_level
	# A linked secondary exit is not an independent reason to abandon the hold.
	# Its explicit confirmation and exit-window rules govern that transition.
	for policy: HoldToExitFallbackPolicy in fallback_policies:
		if _policy_has_markers(policy, progress):
			return policy.hold_condition.outcome_level
	for level: VictoryCondition.OutcomeLevel in [VictoryCondition.OutcomeLevel.MAJOR, VictoryCondition.OutcomeLevel.MINOR]:
		var found: bool = false
		var feasible: bool = true
		var garrisons: Dictionary[Vector2i, int] = {}
		for state: VictoryConditionProgress in progress:
			if state.team != team or state.outcome != level:
				continue
			found = true
			if not state.valid:
				feasible = false
				continue
			if state.kind == VictoryConditionProgress.Kind.PREVENT_EXIT and not state.complete:
				feasible = false
			if state.kind == VictoryConditionProgress.Kind.OCCUPY:
				for hex: Vector2i in state.hexes:
					garrisons[hex] = maxi(garrisons.get(hex, 0), state.required_units)
					var seconds: float = _travel_seconds(planner, hex) + maxf(0.0, state.required_seconds - state.held_seconds.get(hex, 0.0))
					if seconds > seconds_left:
						feasible = false
			elif state.kind == VictoryConditionProgress.Kind.EXIT and not state.complete:
				if state.remaining_units > _available_exit_units(planner, state.condition as ExitUnitsCondition).size() or _travel_seconds(planner, _exit_hex(state, planner)) > seconds_left:
					feasible = false
		var fighters: int = 0
		var needed_garrisons: int = 0
		for count: int in garrisons.values():
			needed_garrisons += count
		for unit: Unit in planner.squads:
			if TacticalPositionExecutor.is_active_defender(unit) and unit.is_good_order() and not HqSupportPositionPolicy.is_headquarters(unit):
				fighters += 1
		if needed_garrisons > fighters:
			feasible = false
		if found and feasible:
			return level
	return -1


func _add_own_tasks(state: VictoryConditionProgress, planner: PlatoonAI) -> void:
	if state.kind == VictoryConditionProgress.Kind.OCCUPY:
		for hex: Vector2i in state.hexes:
			var existing: ScenarioGoalTask
			for candidate: ScenarioGoalTask in tasks:
				if candidate.kind == ScenarioGoalTask.Kind.OCCUPY and candidate.hex == hex:
					existing = candidate
			if existing != null:
				existing.required_units = maxi(existing.required_units, state.required_units)
				existing.reason = "Occupy %s: maintain %d squads for all occupation conditions" % [hex, existing.required_units]
				continue
			var task: ScenarioGoalTask = _task(state, ScenarioGoalTask.Kind.OCCUPY, hex)
			task.required_units = state.required_units
			task.priority = 80.0
			if posture == PositionProfile.Mode.ASSAULT:
				task.priority = 100.0
			task.reason = "Occupy %s: %.1f/%.1f seconds; %d squads required" % [hex, state.held_seconds.get(hex, 0.0), state.required_seconds, state.required_units]
			tasks.append(task)
	elif state.kind == VictoryConditionProgress.Kind.EXIT and not state.complete:
		var task: ScenarioGoalTask = _task(state, ScenarioGoalTask.Kind.EXIT, _exit_hex(state, planner))
		task.required_units = state.remaining_units
		task.priority = 85.0
		task.reason = "Reach an exit: %d more distinct squads required" % state.remaining_units
		tasks.append(task)
	elif state.kind == VictoryConditionProgress.Kind.PREVENT_EXIT:
		var task: ScenarioGoalTask = _task(state, ScenarioGoalTask.Kind.BLOCK_EXIT, _exit_hex(state, planner))
		task.priority = 95.0
		task.reason = "Prevent enemy exit: %d more enemy exits would fail the condition" % state.remaining_units
		for contact: InfluenceContact in _contacts(planner):
			if contact.observed and TacticalPositionExecutor.is_active_defender(contact.unit) and LOSHelper.get_hex_distance(contact.hex, task.hex) <= 2:
				task.urgent = true
				task.priority = 120.0
		tasks.append(task)
	elif state.kind == VictoryConditionProgress.Kind.DESTROY and not state.complete:
		var target: InfluenceContact = _hunt_contact(planner)
		if target != null:
			var task: ScenarioGoalTask = _task(state, ScenarioGoalTask.Kind.HUNT, target.hex)
			task.key = str([state.condition.get_instance_id(), ScenarioGoalTask.Kind.HUNT, target.unit])
			task.priority = 70.0
			task.reason = "Attack a known enemy: %d more enemy squads must be destroyed" % state.remaining_units
			tasks.append(task)
		else:
			diagnostics.append("Destruction goal awaits an observed or remembered enemy contact")


func _task(state: VictoryConditionProgress, kind: ScenarioGoalTask.Kind, hex: Vector2i) -> ScenarioGoalTask:
	var task: ScenarioGoalTask = ScenarioGoalTask.new()
	task.condition = state.condition
	task.kind = kind
	task.hex = hex
	task.key = str([state.condition.get_instance_id(), kind, hex])
	return task


func _preferred_primary() -> ScenarioGoalTask:
	if tasks.is_empty():
		return null
	return tasks[0]


func _contains_task(key: String) -> bool:
	for task: ScenarioGoalTask in tasks:
		if task.key == key:
			return true
	return false


func _contacts(planner: PlatoonAI) -> Array[InfluenceContact]:
	if planner.influence_map_controller == null or planner.influence_map_controller.snapshot == null:
		return []
	return planner.influence_map_controller.snapshot.get_defensive_contacts(team)


func _hunt_contact(planner: PlatoonAI) -> InfluenceContact:
	var best: InfluenceContact
	var score: float = INF
	for contact: InfluenceContact in _contacts(planner):
		if contact.observed and not TacticalPositionExecutor.is_active_defender(contact.unit):
			continue
		if contact.confidence < 0.25:
			continue
		var cost: float = _friendly_distance(planner, contact.hex)
		if not contact.observed:
			cost += 8.0
		if cost < score:
			best = contact
			score = cost
	return best


func _friendly_distance(planner: PlatoonAI, hex: Vector2i) -> float:
	var distance: float = INF
	for unit: Unit in planner.squads:
		if TacticalPositionExecutor.is_active_defender(unit) and not HqSupportPositionPolicy.is_headquarters(unit):
			distance = minf(distance, float(LOSHelper.get_hex_distance(unit.current_hex, hex)))
	return distance


func _travel_seconds(planner: PlatoonAI, hex: Vector2i) -> float:
	var seconds: float = INF
	for unit: Unit in planner.squads:
		if HqSupportPositionPolicy.is_headquarters(unit):
			continue
		seconds = minf(seconds, _unit_travel_seconds(planner, unit, hex))
	return seconds


func _unit_travel_seconds(planner: PlatoonAI, unit: Unit, hex: Vector2i) -> float:
	if not TacticalPositionExecutor.is_active_defender(unit) or not unit.is_good_order():
		return INF
	if unit.current_hex == hex:
		return 0.0
	if not PositionQueryService.can_follow_intent(unit):
		return INF
	var steps: int = LOSHelper.get_hex_distance(unit.current_hex, hex)
	if planner.influence_map_controller != null and planner.influence_map_controller.snapshot != null:
		var path: Array[Vector2i] = planner.influence_map_controller.snapshot.get_path(team, unit.current_hex, hex)
		if path.is_empty():
			return INF
		steps = path.size() - 1
	return float(steps) * InfluenceUnitQuery.captured_crossing_seconds(unit) + 3.0


func _exit_hex(state: VictoryConditionProgress, planner: PlatoonAI) -> Vector2i:
	var best: Vector2i = state.hexes[0]
	var score: float = INF
	for hex: Vector2i in state.hexes:
		var cost: float = _exit_cost(state, planner, hex)
		if cost < score:
			best = hex
			score = cost
	# A small change in the nearest exit must not reverse accepted routes.
	for previous: ScenarioGoalTask in assignments.values():
		if previous.condition == state.condition and state.hexes.has(previous.hex) and _exit_cost(state, planner, previous.hex) <= score + 1.0:
			return previous.hex
	return best


func _exit_cost(state: VictoryConditionProgress, planner: PlatoonAI, hex: Vector2i) -> float:
	var cost: float = _friendly_distance(planner, hex)
	if state.objective_team != team:
		for contact: InfluenceContact in _contacts(planner):
			if contact.observed and TacticalPositionExecutor.is_active_defender(contact.unit):
				cost = minf(cost, float(LOSHelper.get_hex_distance(contact.hex, hex)) - 20.0)
	return cost


func _available_exit_units(planner: PlatoonAI, condition: VictoryCondition) -> Array[Unit]:
	var result: Array[Unit] = []
	var state: ExitUnitsState = ScenarioGoalTask.exit_state_for(condition)
	for unit: Unit in planner.squads:
		if TacticalPositionExecutor.is_active_defender(unit) and unit.is_good_order() and not HqSupportPositionPolicy.is_headquarters(unit) and PositionQueryService.can_follow_intent(unit) and not state.units_exited.has(unit):
			result.append(unit)
	return result


func _allocate(planner: PlatoonAI) -> void:
	if planner.company_command != null and planner.company_command.uses_hierarchy():
		assignments = planner.company_command.allocate(tasks, assignments)
		diagnostics.append_array(planner.company_command.diagnostics)
		return
	var next: Dictionary[Unit, ScenarioGoalTask] = {}
	var available: Array[Unit] = []
	for unit: Unit in planner.squads:
		var withdraw_hq: bool = active_fallback != null and active_fallback.withdraw_entire_force
		for task: ScenarioGoalTask in tasks:
			withdraw_hq = withdraw_hq or (task.escape_policy != null and task.escape_policy.include_headquarters)
		if TacticalPositionExecutor.is_active_defender(unit) and (withdraw_hq or not HqSupportPositionPolicy.is_headquarters(unit)):
			available.append(unit)
	for unit: Unit in assignments:
		var previous: ScenarioGoalTask = assignments[unit]
		if not available.has(unit) or not PlatoonPositionStability.is_busy(unit):
			continue
		# Even a counted exit squad finishes its accepted route and setup. Urgent
		# duties can release other squads; route safety remains the executor's gate.
		next[unit] = _refresh_escape_task(previous)
		available.erase(unit)
	for task: ScenarioGoalTask in tasks:
		var demand: int = task.required_units
		for unit: Unit in next:
			if next[unit].key == task.key:
				if task.kind == ScenarioGoalTask.Kind.EXIT and not task.withdrawal and ScenarioGoalTask.exit_state_for(task.condition).units_exited.has(unit):
					continue
				demand -= 1
		while demand > 0:
			var selected: Unit = _select_unit(task, available)
			if selected == null:
				if task.is_destination_goal():
					diagnostics.append("No available squad for " + task.reason)
				break
			next[selected] = task
			available.erase(selected)
			demand -= 1
	assignments = next


func _select_unit(task: ScenarioGoalTask, available: Array[Unit]) -> Unit:
	var selected: Unit
	var score: float = -INF
	for unit: Unit in available:
		if task.escape_policy != null and not task.escape_policy.allows(unit):
			continue
		if task.kind == ScenarioGoalTask.Kind.HUNT and not PositionQueryService.can_assault(unit):
			continue
		if task.kind == ScenarioGoalTask.Kind.EXIT and not task.withdrawal and ScenarioGoalTask.exit_state_for(task.condition).units_exited.has(unit):
			continue
		if task.escape_policy == null and (not unit.is_good_order() or (unit.current_hex != task.hex and not PositionQueryService.can_follow_intent(unit))):
			continue
		var prior: ScenarioGoalTask = assignments.get(unit)
		if PlatoonPositionStability.is_busy(unit):
			var already_establishing: bool = unit.current_hex == task.hex and not unit.movement.is_moving
			if (prior == null or prior.key != task.key) and not already_establishing:
				continue
		var value: float = -float(LOSHelper.get_hex_distance(unit.current_hex, task.hex))
		if task.recovering_units.has(unit):
			# Keep the mission through recovery; mobile squads satisfy a limited quota first.
			value -= 1000.0
		if unit.squad_type == Globals.SquadType.Rifle:
			value += 30.0
		if prior != null and prior.key == task.key:
			value += 50.0
		if unit.current_hex == task.hex:
			value += 100.0
		if task.is_destination_goal() and task.escape_policy == null and _unit_route_missing(unit, task.hex):
			continue
		if value > score:
			selected = unit
			score = value
	return selected


func _refresh_escape_task(previous: ScenarioGoalTask) -> ScenarioGoalTask:
	if previous.escape_policy != null:
		for task: ScenarioGoalTask in tasks:
			if task.key == previous.key:
				return task
	return previous


func _goal_travel_seconds(planner: PlatoonAI, unit: Unit, task: ScenarioGoalTask) -> float:
	if task.escape_policy == null:
		return _unit_travel_seconds(planner, unit, task.hex)
	var best: float = INF
	for hex: Vector2i in ScenarioGoalTask.exit_state_for(task.condition).exit_hexes:
		best = minf(best, _unit_travel_seconds(planner, unit, hex))
	return best


func _unit_route_missing(unit: Unit, hex: Vector2i) -> bool:
	if unit.current_hex == hex or not Globals.astars.has(team):
		return false
	var graph: AStar2D = Globals.astars[team]
	var from: int = graph.get_closest_point(LOSHelper.ground_layer.map_to_local(unit.current_hex))
	var to: int = graph.get_closest_point(LOSHelper.ground_layer.map_to_local(hex))
	return graph.is_point_disabled(to) or graph.get_id_path(from, to).is_empty()


static func _prefer_task(left: ScenarioGoalTask, right: ScenarioGoalTask) -> bool:
	if not is_equal_approx(left.priority, right.priority):
		return left.priority > right.priority
	return left.key < right.key
