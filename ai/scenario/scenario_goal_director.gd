class_name ScenarioGoalDirector
extends RefCounted

const REASSESS_SECONDS: float = 0.5
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
var _next_update: float = -INF
var _primary_since: float = -INF
var _contender: String = ""
var _contender_since: float = -INF
var _last_objective: Vector2i
var _initialized: bool = false


func configure(owner: Globals.Team, scenario_conditions: Array[VictoryCondition], mode: PositionProfile.Mode) -> void:
	team = owner
	conditions = scenario_conditions.duplicate()
	posture = mode
	tasks.clear()
	assignments.clear()
	diagnostics.clear()
	primary = null
	manual_override = false
	_initialized = false
	_next_update = -INF
	_primary_since = -INF
	_contender = ""


func initial_order(planner: PlatoonAI, fallback: MissionOrder, seconds_left: float) -> MissionOrder:
	_build_tasks(planner, seconds_left)
	primary = _preferred_primary()
	if primary != null:
		fallback.objective_hex = primary.hex
		fallback.sector_cells = []
		fallback.fallback_hexes = []
	elif not conditions.is_empty():
		# A destruction-denial mission has no geographic target of its own.
		for unit: Unit in planner.squads:
			if TacticalPositionExecutor.is_active_defender(unit) and not HqSupportPositionPolicy.is_headquarters(unit):
				fallback.objective_hex = unit.current_hex
				break
	_last_objective = fallback.objective_hex
	_initialized = true
	return fallback


func update(planner: PlatoonAI, seconds_left: float, now: float) -> void:
	if not planner.active or planner.current_order == null or now < _next_update:
		return
	_next_update = now + REASSESS_SECONDS
	if _initialized and planner.current_order.objective_hex != _last_objective:
		# Debug objective edits remain deliberate overrides until the posture is changed.
		manual_override = true
	if manual_override:
		return
	_build_tasks(planner, seconds_left)
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


func _build_tasks(planner: PlatoonAI, seconds_left: float) -> void:
	tasks.clear()
	diagnostics.clear()
	var progress: Array[VictoryConditionProgress] = []
	for condition: VictoryCondition in conditions:
		var state: VictoryConditionProgress = VictoryConditionProgress.read(condition)
		progress.append(state)
		if not state.valid:
			diagnostics.append(state.diagnostic)
	var own_level: int = _choose_own_outcome(progress, planner, seconds_left)
	for state: VictoryConditionProgress in progress:
		if state.team == team and state.outcome == own_level and state.valid:
			_add_own_tasks(state, planner)
	# Deny one necessary condition in each opposing victory package. Cumulative
	# conditions already completed cannot be undone; occupation remains reversible.
	for level: VictoryCondition.OutcomeLevel in [VictoryCondition.OutcomeLevel.MAJOR, VictoryCondition.OutcomeLevel.MINOR]:
		var blocked: VictoryConditionProgress
		var best_cost: float = INF
		for state: VictoryConditionProgress in progress:
			if state.team == team or state.outcome != level or not state.valid:
				continue
			if state.complete and state.kind != VictoryConditionProgress.Kind.OCCUPY:
				continue
			var cost: float = _denial_cost(state, planner)
			if cost < best_cost:
				blocked = state
				best_cost = cost
		if blocked != null:
			_add_denial_tasks(blocked, planner)
	tasks.sort_custom(_prefer_task)


func _choose_own_outcome(progress: Array[VictoryConditionProgress], planner: PlatoonAI, seconds_left: float) -> int:
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


func _denial_cost(state: VictoryConditionProgress, planner: PlatoonAI) -> float:
	if state.kind == VictoryConditionProgress.Kind.DESTROY:
		return 5.0
	if state.kind == VictoryConditionProgress.Kind.OCCUPY:
		return 15.0 + _friendly_distance(planner, _denial_hex(state, planner))
	return 30.0 + _friendly_distance(planner, _exit_hex(state, planner))


func _add_denial_tasks(state: VictoryConditionProgress, planner: PlatoonAI) -> void:
	if state.kind == VictoryConditionProgress.Kind.DESTROY:
		var task: ScenarioGoalTask = _task(state, ScenarioGoalTask.Kind.PRESERVE, Vector2i.ZERO)
		task.priority = 100.0
		task.required_units = state.remaining_units
		task.reason = "Protect the force: opponent needs %d more destroyed squads" % state.remaining_units
		tasks.append(task)
		return
	var hex: Vector2i = _denial_hex(state, planner)
	var kind: ScenarioGoalTask.Kind = ScenarioGoalTask.Kind.DENY_OCCUPATION
	if state.kind == VictoryConditionProgress.Kind.EXIT:
		hex = _exit_hex(state, planner)
		kind = ScenarioGoalTask.Kind.BLOCK_EXIT
	var task: ScenarioGoalTask = _task(state, kind, hex)
	task.priority = 75.0
	if state.outcome == VictoryCondition.OutcomeLevel.MAJOR:
		task.priority = 90.0
	task.reason = "Prevent enemy occupation of " + str(hex)
	if kind == ScenarioGoalTask.Kind.BLOCK_EXIT:
		task.reason = "Block exits: opponent needs %d more squads to exit" % state.remaining_units
	for contact: InfluenceContact in _contacts(planner):
		if not contact.observed or not TacticalPositionExecutor.is_active_defender(contact.unit) or not contact.unit.is_good_order():
			continue
		if LOSHelper.get_hex_distance(contact.hex, hex) <= 2:
			task.urgent = true
			task.priority = 120.0
	tasks.append(task)


func _task(state: VictoryConditionProgress, kind: ScenarioGoalTask.Kind, hex: Vector2i) -> ScenarioGoalTask:
	var task: ScenarioGoalTask = ScenarioGoalTask.new()
	task.condition = state.condition
	task.kind = kind
	task.hex = hex
	task.key = str([state.condition.get_instance_id(), kind, hex])
	return task


func _preferred_primary() -> ScenarioGoalTask:
	for task: ScenarioGoalTask in tasks:
		if task.kind != ScenarioGoalTask.Kind.PRESERVE:
			return task
	return null


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
		if not TacticalPositionExecutor.is_active_defender(unit) or not unit.is_good_order() or HqSupportPositionPolicy.is_headquarters(unit):
			continue
		if unit.current_hex == hex:
			seconds = 0.0
		elif PositionQueryService.can_follow_intent(unit):
			var steps: int = LOSHelper.get_hex_distance(unit.current_hex, hex)
			if planner.influence_map_controller != null and planner.influence_map_controller.snapshot != null:
				var path: Array[Vector2i] = planner.influence_map_controller.snapshot.get_path(team, unit.current_hex, hex)
				if path.is_empty():
					continue
				steps = path.size() - 1
			seconds = minf(seconds, float(steps) * InfluenceUnitQuery.captured_crossing_seconds(unit) + 3.0)
	return seconds


func _denial_hex(state: VictoryConditionProgress, planner: PlatoonAI) -> Vector2i:
	var best: Vector2i = state.hexes[0]
	var score: float = INF
	for hex: Vector2i in state.hexes:
		var cost: float = _friendly_distance(planner, hex)
		for contact: InfluenceContact in _contacts(planner):
			if contact.observed and TacticalPositionExecutor.is_active_defender(contact.unit):
				cost = minf(cost, float(LOSHelper.get_hex_distance(contact.hex, hex)) - 10.0)
		if cost < score:
			best = hex
			score = cost
	return best


func _exit_hex(state: VictoryConditionProgress, planner: PlatoonAI) -> Vector2i:
	var best: Vector2i = state.hexes[0]
	var score: float = INF
	for hex: Vector2i in state.hexes:
		var cost: float = _friendly_distance(planner, hex)
		if state.team != team:
			for contact: InfluenceContact in _contacts(planner):
				if contact.observed and TacticalPositionExecutor.is_active_defender(contact.unit):
					cost = minf(cost, float(LOSHelper.get_hex_distance(contact.hex, hex)) - 20.0)
		if cost < score:
			best = hex
			score = cost
	# A small change in the nearest exit must not reverse accepted routes.
	for previous: ScenarioGoalTask in assignments.values():
		if previous.condition == state.condition and state.hexes.has(previous.hex) and _friendly_distance(planner, previous.hex) <= _friendly_distance(planner, best) + 1.0:
			return previous.hex
	return best


func _available_exit_units(planner: PlatoonAI, condition: ExitUnitsCondition) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit: Unit in planner.squads:
		if TacticalPositionExecutor.is_active_defender(unit) and unit.is_good_order() and not HqSupportPositionPolicy.is_headquarters(unit) and PositionQueryService.can_follow_intent(unit) and not condition.state.units_exited.has(unit):
			result.append(unit)
	return result


func _allocate(planner: PlatoonAI) -> void:
	var next: Dictionary[Unit, ScenarioGoalTask] = {}
	var available: Array[Unit] = []
	for unit: Unit in planner.squads:
		if TacticalPositionExecutor.is_active_defender(unit) and not HqSupportPositionPolicy.is_headquarters(unit):
			available.append(unit)
	for unit: Unit in assignments:
		var previous: ScenarioGoalTask = assignments[unit]
		if not available.has(unit) or not PlatoonPositionStability.is_busy(unit):
			continue
		# Even a counted exit squad finishes its accepted route and setup. Urgent
		# duties can release other squads; route safety remains the executor's gate.
		next[unit] = previous
		available.erase(unit)
	for task: ScenarioGoalTask in tasks:
		if task.kind == ScenarioGoalTask.Kind.PRESERVE:
			continue
		var demand: int = task.required_units
		for unit: Unit in next:
			if next[unit].key == task.key:
				if task.kind == ScenarioGoalTask.Kind.EXIT and (task.condition as ExitUnitsCondition).state.units_exited.has(unit):
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
	# Preservation is a recovery duty for threatened squads, not a command to
	# abandon every useful firing position or an essential objective garrison.
	for task: ScenarioGoalTask in tasks:
		if task.kind != ScenarioGoalTask.Kind.PRESERVE:
			continue
		for unit: Unit in available:
			if task.required_units <= 1 and unit.stress_system != null and unit.stress_system.S_eff > unit.stress_system.S_CAP * 0.8 and not unit.in_close_combat:
				next[unit] = task
	assignments = next


func _select_unit(task: ScenarioGoalTask, available: Array[Unit]) -> Unit:
	var selected: Unit
	var score: float = -INF
	for unit: Unit in available:
		if task.kind == ScenarioGoalTask.Kind.EXIT and (task.condition as ExitUnitsCondition).state.units_exited.has(unit):
			continue
		if not unit.is_good_order() or (unit.current_hex != task.hex and not PositionQueryService.can_follow_intent(unit)):
			continue
		var prior: ScenarioGoalTask = assignments.get(unit)
		if PlatoonPositionStability.is_busy(unit):
			var already_establishing: bool = unit.current_hex == task.hex and not unit.movement.is_moving
			if (prior == null or prior.key != task.key) and not already_establishing:
				continue
		var value: float = -float(LOSHelper.get_hex_distance(unit.current_hex, task.hex))
		if unit.squad_type == Globals.SquadType.Rifle:
			value += 30.0
		if prior != null and prior.key == task.key:
			value += 50.0
		if unit.current_hex == task.hex:
			value += 100.0
		if task.is_destination_goal() and _unit_route_missing(unit, task.hex):
			continue
		if value > score:
			selected = unit
			score = value
	return selected


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
