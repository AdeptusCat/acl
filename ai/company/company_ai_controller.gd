class_name CompanyAI
extends RefCounted

const REASSESS_SECONDS: float = 0.5
const RESERVE_RECOVERY_SECONDS: float = 8.0

var owner: PlatoonAI
var platoons: Dictionary[Vector2i, CompanyPlatoon] = {}
var reservations: Dictionary[Unit, Vector2i] = {}
var diagnostics: PackedStringArray = []
var _headquarters: Array[Unit] = []
var _headquarters_planner: PlatoonAI
var _elapsed: float = 0.0
var _clock: float = 0.0
var _sector_cache: Dictionary[String, Dictionary] = {}
var _initial_batch_complete: bool = false


func configure(planner: PlatoonAI) -> void:
	owner = planner


func uses_hierarchy() -> bool:
	return platoons.size() > 1


func sync_roster() -> void:
	var was_hierarchical: bool = uses_hierarchy()
	var groups: Dictionary[Vector2i, Array] = {}
	var headquarters: Array[Unit] = []
	for unit: Unit in owner.squads:
		if not InfluenceUnitQuery.is_valid_living_unit(unit) or unit.surrendered:
			continue
		if unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
			headquarters.append(unit)
			continue
		var key: Vector2i = Vector2i(int(unit.company), unit.platoon)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(unit)
	# A surviving HQ without fighting squads remains a support unit, not a platoon.
	for key: Vector2i in groups.keys():
		var has_combat: bool = false
		for unit: Unit in groups[key]:
			has_combat = has_combat or not HqSupportPositionPolicy.is_headquarters(unit)
		if not has_combat:
			headquarters.append_array(groups[key])
			groups.erase(key)
	for key: Vector2i in platoons.keys():
		if groups.has(key):
			continue
		_release_planner(platoons[key].planner)
		platoons.erase(key)
		_sector_cache.clear()
	for key: Vector2i in groups:
		if not platoons.has(key):
			var formation: CompanyPlatoon = CompanyPlatoon.new()
			formation.company = key.x as Unit.Company
			formation.number = key.y
			platoons[key] = formation
			_sector_cache.clear()
			_initial_batch_complete = false
		var formation: CompanyPlatoon = platoons[key]
		var roster: Array[Unit] = []
		roster.assign(groups[key])
		if formation.squads != roster:
			formation.squads = roster
			formation.mission_key = ""
			if formation.planner != null:
				formation.planner.set_squads(roster)
	_headquarters = headquarters
	if was_hierarchical != uses_hierarchy():
		owner._cancel_plan()
		owner.executor.cancel_all(true)
		owner.position_stability.clear()
		owner.squad_assignments.clear()
		reservations.clear()
		if not uses_hierarchy():
			for formation: CompanyPlatoon in platoons.values():
				_release_planner(formation.planner)
				formation.planner = null
			_release_planner(_headquarters_planner)
			_headquarters_planner = null
			owner._set_mission_control(owner.active and owner.current_order != null)
	if uses_hierarchy():
		for formation: CompanyPlatoon in platoons.values():
			if formation.planner == null:
				formation.planner = _create_planner(formation.squads)
		if not _headquarters.is_empty() and _headquarters_planner == null:
			_headquarters_planner = _create_planner(_headquarters)
		elif _headquarters_planner != null and _headquarters_planner.squads != _headquarters:
			_headquarters_planner.set_squads(_headquarters)
	_refresh_reservations()


func _create_planner(roster: Array[Unit]) -> PlatoonAI:
	var planner: PlatoonAI = PlatoonAI.new()
	planner.team = owner.team
	planner.influence_map_controller = owner.influence_map_controller
	planner.publish_team_objective = false
	planner.company_reservations = reservations
	planner.active = owner.active
	owner.add_child(planner)
	planner.set_process_unhandled_input(false)
	planner.set_squads(roster)
	return planner


func _release_planner(planner: PlatoonAI) -> void:
	if not is_instance_valid(planner):
		return
	planner.set_active(false)
	if planner.get_parent() != null:
		planner.get_parent().remove_child(planner)
	planner.free()


func stop() -> void:
	for formation: CompanyPlatoon in platoons.values():
		if is_instance_valid(formation.planner):
			formation.planner.set_active(false)
		formation.mission_key = ""
		formation.support = null
	if is_instance_valid(_headquarters_planner):
		_headquarters_planner.set_active(false)
	reservations.clear()


func reset_mission() -> void:
	stop()
	_initial_batch_complete = false
	_sector_cache.clear()
	for formation: CompanyPlatoon in platoons.values():
		formation.task = null
		formation.reserve_deployed = false
		formation.provides_reserve = false
		formation.quiet_since = -INF
	_elapsed = 0.0


func update(delta: float) -> void:
	_clock += delta
	_elapsed -= delta
	if _elapsed <= 0.0:
		_elapsed = REASSESS_SECONDS
		sync_roster()
		if owner.active and owner.current_order != null and uses_hierarchy():
			reconsider(true)
	if uses_hierarchy():
		collect_assignments()


func reconsider(budgeted: bool) -> void:
	if not owner.active or owner.current_order == null or not uses_hierarchy():
		return
	owner.influence_map_controller.set_objective_for_team(owner.team, owner.current_order.objective_hex)
	diagnostics.clear()
	_refresh_reservations()
	_assign_roles()
	for formation: CompanyPlatoon in platoons.values():
		_dispatch(formation)
		if not budgeted:
			formation.planner.reconsider_assignments()
	if _headquarters_planner != null:
		_headquarters_planner.goal_director = owner.goal_director
		if not _headquarters_planner.active:
			_headquarters_planner.set_active(true)
		if _headquarters_planner.current_order == null:
			_headquarters_planner.receive_mission_order(owner.current_order.copy())
		elif _headquarters_planner.current_order.objective_hex != owner.current_order.objective_hex:
			_headquarters_planner.change_scenario_objective(owner.current_order.objective_hex)
		_headquarters_planner.set_scenario_goal_assignments(_goals_for(_headquarters))
		if not budgeted:
			_headquarters_planner.reconsider_assignments()
	collect_assignments()


func allocate(tasks: Array[ScenarioGoalTask], previous: Dictionary[Unit, ScenarioGoalTask]) -> Dictionary[Unit, ScenarioGoalTask]:
	var next: Dictionary[Unit, ScenarioGoalTask] = {}
	var committed: Dictionary[Vector2i, ScenarioGoalTask] = {}
	for formation: CompanyPlatoon in platoons.values():
		formation.task = null
	for unit: Unit in previous:
		if not InfluenceUnitQuery.is_valid_living_unit(unit) or unit.surrendered or not PlatoonPositionStability.is_busy(unit):
			continue
		var duty: ScenarioGoalTask = owner.goal_director._refresh_escape_task(previous[unit])
		next[unit] = duty
		var key: Vector2i = Vector2i(int(unit.company), unit.platoon)
		if platoons.has(key):
			committed[key] = duty
			platoons[key].task = duty
	for task: ScenarioGoalTask in tasks:
		if task.kind == ScenarioGoalTask.Kind.PRESERVE:
			continue
		var demand: int = task.required_units
		for unit: Unit in next:
			if next[unit].key == task.key and _eligible_for_goal(unit, task):
				demand -= 1
		# Headquarters participate only when the mission explicitly includes them.
		if task.includes_headquarters():
			for unit: Unit in _headquarters:
				if demand > 0 and not next.has(unit) and _eligible_for_goal(unit, task):
					next[unit] = task
					demand -= 1
		var tried: Array[Vector2i] = []
		while demand > 0:
			var formation: CompanyPlatoon = _select_platoon(task, committed, tried, previous)
			if formation == null:
				diagnostics.append("No available platoon for " + task.reason)
				break
			var key: Vector2i = Vector2i(int(formation.company), formation.number)
			tried.append(key)
			var available: Array[Unit] = formation.combat_units()
			if task.includes_headquarters():
				available = formation.squads.duplicate()
			for unit: Unit in next:
				available.erase(unit)
			var assigned: bool = false
			while demand > 0:
				var selected: Unit = owner.goal_director._select_unit(task, available)
				if selected == null:
					break
				next[selected] = task
				available.erase(selected)
				assigned = true
				demand -= 1
			if assigned:
				committed[key] = task
				formation.task = task
	for task: ScenarioGoalTask in tasks:
		if task.kind != ScenarioGoalTask.Kind.PRESERVE:
			continue
		for formation: CompanyPlatoon in platoons.values():
			for unit: Unit in formation.combat_units():
				if not next.has(unit) and unit.stress_system != null and unit.stress_system.S_eff > unit.stress_system.S_CAP * 0.8 and not unit.in_close_combat:
					next[unit] = task
	return next


func _eligible_for_goal(unit: Unit, task: ScenarioGoalTask) -> bool:
	if task.escape_policy != null and not task.escape_policy.allows(unit):
		return false
	if not TacticalPositionExecutor.is_active_defender(unit) or not unit.is_good_order():
		return false
	if task.kind == ScenarioGoalTask.Kind.HUNT and not PositionQueryService.can_assault(unit):
		return false
	if task.kind == ScenarioGoalTask.Kind.EXIT and not task.withdrawal:
		return not ScenarioGoalTask.exit_state_for(task.condition).units_exited.has(unit)
	return true


func _select_platoon(task: ScenarioGoalTask, committed: Dictionary[Vector2i, ScenarioGoalTask], tried: Array[Vector2i], previous: Dictionary[Unit, ScenarioGoalTask]) -> CompanyPlatoon:
	var selected: CompanyPlatoon
	var best: float = -INF
	for key: Vector2i in platoons:
		var formation: CompanyPlatoon = platoons[key]
		if tried.has(key) or (committed.has(key) and committed[key].key != task.key):
			continue
		if formation.is_busy() and not task.urgent and formation.objective != task.hex and not committed.has(key):
			continue
		var value: float = -float(LOSHelper.get_hex_distance(formation.anchor(), task.hex)) + 10.0 * formation.effectiveness()
		var eligible: bool = false
		for unit: Unit in formation.squads:
			if not _eligible_for_goal(unit, task) or (HqSupportPositionPolicy.is_headquarters(unit) and not task.includes_headquarters()):
				continue
			if owner.goal_director._goal_travel_seconds(owner, unit, task) == INF:
				continue
			eligible = true
			if previous.has(unit) and previous[unit].key == task.key:
				value += 50.0
			if unit.current_hex == task.hex:
				value += 100.0
		if eligible and value > best:
			selected = formation
			best = value
	return selected


func _assign_roles() -> void:
	var groups: Dictionary[String, Array] = {}
	for formation: CompanyPlatoon in platoons.values():
		formation.support = null
		formation.sector_cells.clear()
		if owner.goal_director != null and owner.goal_director.manual_override:
			formation.task = null
		formation.objective = owner.current_order.objective_hex
		if owner.current_order.position_mode == PositionProfile.Mode.DEFEND and formation.task == null and formation.support_firepower() <= 0.0:
			formation.objective = formation.anchor()
		if formation.task != null:
			formation.objective = formation.task.hex
			if formation.task.breach_required:
				formation.objective = formation.task.breach_hex
		var key: String = str([formation.company, formation.objective])
		if not groups.has(key):
			groups[key] = []
		groups[key].append(formation)
	for key: String in groups:
		var members: Array[CompanyPlatoon] = []
		members.assign(groups[key])
		var attack: bool = false
		for formation: CompanyPlatoon in members:
			attack = attack or _needs_attack(formation)
		var maneuver: CompanyPlatoon
		var support: CompanyPlatoon
		if attack:
			maneuver = _choose_maneuver(members)
			if maneuver != null:
				support = _choose_support(members, maneuver)
		var reserve: CompanyPlatoon
		if members.size() >= 3:
			reserve = _choose_reserve(members, maneuver, support)
		for formation: CompanyPlatoon in members:
			var next_role: CompanyPlatoon.Role = CompanyPlatoon.Role.DEFEND
			if attack:
				next_role = CompanyPlatoon.Role.MANEUVER
			if formation == support:
				next_role = CompanyPlatoon.Role.SUPPORT
			elif formation == reserve:
				_update_reserve(formation, maneuver)
				next_role = CompanyPlatoon.Role.RESERVE
				if formation.reserve_deployed:
					next_role = CompanyPlatoon.Role.REINFORCE
			if formation.task != null and (formation.task.withdrawal or formation.task.escape_policy != null) and not formation.task.breach_required:
				next_role = CompanyPlatoon.Role.WITHDRAW
			if next_role == CompanyPlatoon.Role.RESERVE and formation.role != CompanyPlatoon.Role.RESERVE:
				formation.staging_hex = formation.anchor()
			formation.role = next_role
			if next_role in [CompanyPlatoon.Role.MANEUVER, CompanyPlatoon.Role.REINFORCE]:
				formation.support = support
			formation.reason = "Company %s: platoon %d %s at %s" % [Unit.COMPANY_NAMES[formation.company], formation.number, CompanyPlatoon.Role.keys()[formation.role].to_lower(), formation.objective]
			diagnostics.append(formation.reason)
	# Defensive neighbors coordinate even when they protect different objectives.
	var defenders: Dictionary[int, Array] = {}
	for formation: CompanyPlatoon in platoons.values():
		if formation.role != CompanyPlatoon.Role.DEFEND or formation.support_firepower() <= 0.0:
			continue
		if not defenders.has(formation.company):
			defenders[formation.company] = []
		defenders[formation.company].append(formation)
	for company: int in defenders:
		var members: Array[CompanyPlatoon] = []
		members.assign(defenders[company])
		_assign_defense_sectors(str(company), members)
		_assign_defense_reserves(members)


func _assign_defense_reserves(members: Array[CompanyPlatoon]) -> void:
	var combat_count: int = 0
	var whole_reserve_squads: int = 0
	for formation: CompanyPlatoon in platoons.values():
		if formation.company != members[0].company:
			continue
		for unit: Unit in formation.combat_units():
			if DefenseSectorAllocator.combat_reserve_capable(unit):
				combat_count += 1
				if formation.role == CompanyPlatoon.Role.RESERVE:
					whole_reserve_squads += 1
	var budget: int = maxi(0, floori(float(combat_count) / 6.0) - whole_reserve_squads)
	var eligible: Array[CompanyPlatoon] = []
	var priorities: Dictionary[CompanyPlatoon, float] = {}
	for formation: CompanyPlatoon in members:
		var free: int = 0
		var has_objective_duty: bool = false
		for unit: Unit in formation.combat_units():
			if owner.goal_assignments.has(unit):
				var task: ScenarioGoalTask = owner.goal_assignments[unit]
				if task.hex == formation.objective and task.kind in [ScenarioGoalTask.Kind.OCCUPY, ScenarioGoalTask.Kind.DENY_OCCUPATION, ScenarioGoalTask.Kind.BLOCK_EXIT]:
					has_objective_duty = true
			elif DefenseSectorAllocator.combat_reserve_capable(unit):
				free += 1
		if not has_objective_duty and owner.current_order.defense_responsibility == PositionQuery.Responsibility.AUTO and (formation.sector_cells.is_empty() or formation.sector_cells.has(formation.objective)):
			free -= 1
		if free >= 2:
			var priority: float = formation.effectiveness() * 10.0
			for other: CompanyPlatoon in members:
				priority -= float(LOSHelper.get_hex_distance(formation.anchor(), other.objective))
			if formation.provides_reserve:
				priority += 50.0
			priorities[formation] = priority
			eligible.append(formation)
		formation.provides_reserve = false
	eligible.sort_custom(func(a: CompanyPlatoon, b: CompanyPlatoon) -> bool: return priorities[a] > priorities[b])
	for index: int in range(mini(budget, eligible.size())):
		eligible[index].provides_reserve = true


func _needs_attack(formation: CompanyPlatoon) -> bool:
	if formation.task != null and formation.task.escape_policy != null:
		return formation.task.breach_required
	if formation.task != null and formation.task.withdrawal:
		return false
	if formation.task != null and formation.task.kind == ScenarioGoalTask.Kind.EXIT:
		return formation.task.breach_required
	if owner.goal_director != null and not owner.goal_director.manual_override and owner.goal_director.primary == null and not owner.goal_director.conditions.is_empty():
		return false
	if owner.current_order.position_mode == PositionProfile.Mode.ASSAULT:
		return true
	if formation.task == null:
		return false
	if formation.task.kind == ScenarioGoalTask.Kind.HUNT:
		return formation.can_maneuver()
	# An occupation requirement describes a garrison, not an assault mission.
	if owner.influence_map_controller.snapshot != null:
		for contact: InfluenceContact in owner.influence_map_controller.snapshot.get_contacts(owner.team):
			if contact.observed and contact.hex == formation.objective and TacticalPositionExecutor.is_active_defender(contact.unit) and contact.unit.is_good_order() and formation.can_maneuver():
				return true
	return false


func _choose_maneuver(members: Array[CompanyPlatoon]) -> CompanyPlatoon:
	var selected: CompanyPlatoon
	var best: float = -INF
	for formation: CompanyPlatoon in members:
		if not formation.can_maneuver() and (formation.role != CompanyPlatoon.Role.MANEUVER or formation.combat_units().is_empty()):
			continue
		var score: float = 10.0 * formation.effectiveness() - float(LOSHelper.get_hex_distance(formation.anchor(), formation.objective))
		if formation.role == CompanyPlatoon.Role.MANEUVER:
			score += 20.0
		if formation.task != null:
			score += 100.0
		if score > best:
			selected = formation
			best = score
	return selected


func _choose_support(members: Array[CompanyPlatoon], maneuver: CompanyPlatoon) -> CompanyPlatoon:
	var selected: CompanyPlatoon
	var best: float = 0.0
	for formation: CompanyPlatoon in members:
		var shared_breach: bool = formation.task != null and formation.task.kind == ScenarioGoalTask.Kind.EXIT and formation.task.breach_required and formation.objective == maneuver.objective
		if formation == maneuver or (formation.task != null and not shared_breach) or formation.effectiveness() <= 0.0:
			continue
		var score: float = formation.support_firepower()
		if formation.role == CompanyPlatoon.Role.SUPPORT:
			score *= 1.5
		if score > best:
			selected = formation
			best = score
	return selected


func _choose_reserve(members: Array[CompanyPlatoon], maneuver: CompanyPlatoon, support: CompanyPlatoon) -> CompanyPlatoon:
	var selected: CompanyPlatoon
	var best: float = -INF
	for formation: CompanyPlatoon in members:
		if formation == maneuver or formation == support or formation.task != null or not formation.can_maneuver():
			continue
		var score: float = float(LOSHelper.get_hex_distance(formation.anchor(), formation.objective)) + formation.effectiveness()
		if formation.role in [CompanyPlatoon.Role.RESERVE, CompanyPlatoon.Role.REINFORCE]:
			score += 100.0
		if score > best:
			selected = formation
			best = score
	return selected


func _update_reserve(formation: CompanyPlatoon, maneuver: CompanyPlatoon) -> void:
	var emergency: bool = maneuver != null and (maneuver.effectiveness() < 0.45 or not maneuver.can_maneuver())
	if owner.current_order.position_mode == PositionProfile.Mode.DEFEND and owner.influence_map_controller.snapshot != null:
		for contact: InfluenceContact in owner.influence_map_controller.snapshot.get_contacts(owner.team):
			if contact.observed and TacticalPositionExecutor.is_active_defender(contact.unit) and contact.unit.is_good_order() and LOSHelper.get_hex_distance(contact.hex, formation.objective) <= 2:
				emergency = true
	if emergency:
		formation.reserve_deployed = true
		formation.quiet_since = -INF
	elif formation.reserve_deployed:
		if not is_finite(formation.quiet_since):
			formation.quiet_since = _clock
		if _clock - formation.quiet_since >= RESERVE_RECOVERY_SECONDS and not formation.is_busy():
			formation.reserve_deployed = false


func _assign_defense_sectors(key: String, members: Array[CompanyPlatoon]) -> void:
	var front: Array[CompanyPlatoon] = []
	for formation: CompanyPlatoon in members:
		if formation.role != CompanyPlatoon.Role.RESERVE:
			front.append(formation)
	if front.size() < 2 or owner.influence_map_controller.snapshot == null:
		return
	var identities: Array = []
	for formation: CompanyPlatoon in front:
		identities.append([formation.number, formation.objective, formation.combat_units().size()])
	var context: String = str([key, owner.current_order.defense_radius, owner.current_order.defense_area_radius, identities])
	if not _sector_cache.has(context):
		var sectors: Dictionary[int, Array] = {}
		var anchors: Dictionary[CompanyPlatoon, Vector2i] = {}
		var radii: Dictionary[CompanyPlatoon, int] = {}
		for formation: CompanyPlatoon in front:
			sectors[formation.number] = []
			anchors[formation] = formation.anchor()
			radii[formation] = mini(owner.current_order.defense_area_radius, maxi(owner.current_order.defense_radius, formation.combat_units().size() * 2 + 2))
		var map: InfluenceMap = owner.influence_map_controller.snapshot.maps[owner.team]
		for cell: Vector2i in map.playable_cells:
			var selected: CompanyPlatoon
			var distance: float = INF
			for formation: CompanyPlatoon in front:
				var objective_distance: int = LOSHelper.get_hex_distance(cell, formation.objective)
				if objective_distance > radii[formation]:
					continue
				var candidate: float = float(objective_distance) + float(LOSHelper.get_hex_distance(cell, anchors[formation])) * 0.25
				if cell == formation.objective:
					candidate -= 1000.0
				if candidate < distance:
					selected = formation
					distance = candidate
			if selected != null:
				sectors[selected.number].append(cell)
		if _sector_cache.size() >= 8:
			_sector_cache.clear()
		_sector_cache[context] = sectors
	for formation: CompanyPlatoon in front:
		formation.sector_cells.assign(_sector_cache[context][formation.number])


func _dispatch(formation: CompanyPlatoon) -> void:
	var planner: PlatoonAI = formation.planner
	planner.goal_director = owner.goal_director
	planner.company_defensive_posture = owner.current_order.position_mode == PositionProfile.Mode.DEFEND
	planner.company_reserve_capacity = 0
	if formation.role == CompanyPlatoon.Role.DEFEND and formation.provides_reserve:
		planner.company_reserve_capacity = 1
	if not planner.active:
		planner.set_active(true)
	planner.company_support_squads.clear()
	planner.company_maneuver_squads.clear()
	planner.company_requires_support = formation.support != null
	if formation.support != null:
		planner.company_support_squads.assign(formation.support.combat_units())
	for other: CompanyPlatoon in platoons.values():
		if other.support == formation:
			planner.company_maneuver_squads.append_array(other.combat_units())
	var order: MissionOrder = owner.current_order.copy()
	order.objective_hex = formation.objective
	order.sector_cells = formation.sector_cells.duplicate()
	order.fallback_hexes = []
	if not order.sector_cells.is_empty():
		order.geography = PositionQuery.Geography.SECTOR_ONLY
		if not order.sector_cells.has(order.objective_hex):
			order.defense_responsibility = PositionQuery.Responsibility.COVER_APPROACH
	if formation.role == CompanyPlatoon.Role.SUPPORT:
		order.mission_type = MissionOrder.MissionType.SUPPORT_BY_FIRE
		order.position_mode = PositionProfile.Mode.SUPPORT_BY_FIRE
		order.execution_intent = TacticalPositionExecutor.Intent.SUPPORT_BY_FIRE
		order.reserve_policy = MissionOrder.ReservePolicy.NONE
	elif formation.role == CompanyPlatoon.Role.RESERVE:
		order.mission_type = MissionOrder.MissionType.RESERVE
		order.position_mode = PositionProfile.Mode.DEFEND
		order.execution_intent = TacticalPositionExecutor.Intent.HOLD
		order.objective_hex = formation.staging_hex
		order.geography = PositionQuery.Geography.OBJECTIVE_RADIUS
		order.defense_radius = 2
		order.defense_responsibility = PositionQuery.Responsibility.GUARD
		order.reserve_policy = MissionOrder.ReservePolicy.NONE
	elif formation.role in [CompanyPlatoon.Role.MANEUVER, CompanyPlatoon.Role.REINFORCE] and _needs_attack(formation):
		order.position_mode = PositionProfile.Mode.ASSAULT
		order.execution_intent = TacticalPositionExecutor.Intent.ASSAULT
		order.reserve_policy = MissionOrder.ReservePolicy.NONE
	elif formation.role == CompanyPlatoon.Role.WITHDRAW:
		order.position_mode = PositionProfile.Mode.ADVANCE
		order.execution_intent = TacticalPositionExecutor.Intent.WITHDRAW
		order.reserve_policy = MissionOrder.ReservePolicy.NONE
	elif formation.role == CompanyPlatoon.Role.DEFEND:
		order.mission_type = MissionOrder.MissionType.HOLD
		order.position_mode = PositionProfile.Mode.DEFEND
		order.execution_intent = TacticalPositionExecutor.Intent.FROM_PROFILE
	var mission: String = str([formation.role, order.objective_hex, order.position_mode, order.sector_cells, order.defense_responsibility, planner.company_reserve_capacity])
	if formation.mission_key != mission or planner.current_order == null:
		planner.receive_mission_order(order)
		formation.mission_key = mission
	planner._set_mission_control(true)
	planner.set_scenario_goal_assignments(_goals_for(formation.squads))


func _goals_for(roster: Array[Unit]) -> Dictionary[Unit, ScenarioGoalTask]:
	var result: Dictionary[Unit, ScenarioGoalTask] = {}
	if owner.goal_director != null and owner.goal_director.manual_override:
		return result
	for unit: Unit in roster:
		if owner.goal_assignments.has(unit):
			result[unit] = owner.goal_assignments[unit]
	return result


func _refresh_reservations() -> void:
	for unit: Unit in reservations.keys():
		if not InfluenceUnitQuery.is_valid_living_unit(unit) or unit.surrendered:
			reservations.erase(unit)
	for unit: Unit in owner.squads:
		if not InfluenceUnitQuery.is_valid_living_unit(unit) or unit.surrendered:
			continue
		var cell: Vector2i = unit.current_hex
		if unit.movement != null and unit.movement.is_moving:
			cell = unit.movement.target_hex
		reservations[unit] = cell


func collect_assignments() -> void:
	owner.squad_assignments.clear()
	owner.accepted_positions.clear()
	owner.defense_gaps.clear()
	owner.defense_branch_gaps.clear()
	owner.reserve_squad = null
	owner.reserve_deployed = false
	var planners: Array[PlatoonAI] = []
	for formation: CompanyPlatoon in platoons.values():
		if is_instance_valid(formation.planner):
			planners.append(formation.planner)
			for unit: Unit in formation.planner.squad_assignments:
				var assignment: Dictionary = formation.planner.squad_assignments[unit]
				assignment["company_role"] = formation.role
				assignment["company_platoon"] = Vector2i(int(formation.company), formation.number)
				var result: PositionResult = assignment["result"]
				result.features["company_mission"] = formation.reason
		if formation.role in [CompanyPlatoon.Role.RESERVE, CompanyPlatoon.Role.REINFORCE]:
			var combat: Array[Unit] = formation.combat_units()
			if not combat.is_empty():
				owner.reserve_squad = combat[0]
			owner.reserve_deployed = formation.reserve_deployed
	if _headquarters_planner != null:
		planners.append(_headquarters_planner)
	if not _initial_batch_complete:
		for planner: PlatoonAI in planners:
			if planner.squad_assignments.is_empty():
				return
		_initial_batch_complete = true
	for planner: PlatoonAI in planners:
		owner.squad_assignments.merge(planner.squad_assignments, true)
		owner.accepted_positions.merge(planner.accepted_positions, true)
		owner.defense_gaps.append_array(planner.defense_gaps)
		owner.defense_branch_gaps.append_array(planner.defense_branch_gaps)
	owner.reserved_hexes_by_squad = reservations.duplicate()
