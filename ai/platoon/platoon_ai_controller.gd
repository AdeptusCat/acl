class_name PlatoonAiController
extends Node

const HEX_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 1)
]

const INVALID_SCORE: float = -1000000.0
const ROLE_UNASSIGNED: int = -1

var blackboard: PlatoonBlackboard = PlatoonBlackboard.new()

@export var tactical_tick_interval: float = 0.5
@export var plan_refresh_interval: float = 1.0
@export var phase_transition_cooldown_seconds: float = 1.5

@export var min_suppress_seconds: float = 4.0
@export var min_maneuver_seconds: float = 3.0
@export var withdraw_strength_threshold: float = 0.25
@export var reorganize_strength_threshold: float = 0.38
@export var high_stress_threshold: float = 82.0
@export var emergency_stress_threshold: float = 92.0

@export var squads: Array[Unit] = []
@export var objective_hex: Vector2i = Vector2i(8, 4)

var tactical_tick_timer: float = 0.0
var plan_refresh_timer: float = 0.0
var planned_phase: int = ROLE_UNASSIGNED
var phase_elapsed_seconds: float = 0.0
var phase_transition_cooldown_timer: float = 0.0


func _ready() -> void:
	for squad: Unit in squads:
		blackboard.register_friendly_squad(squad)
	
	set_attack_objective(objective_hex)
	print("--- Platoon AI decision stack started ---")
	print("Objective hex: ", objective_hex)


func setup(p_units: Array[Unit]) -> void:
	squads = p_units
	blackboard.friendly_squads.clear()
	blackboard.squad_states.clear()
	blackboard.assigned_roles.clear()

	for squad: Unit in squads:
		blackboard.register_friendly_squad(squad)


func set_attack_objective(p_objective_hex: Vector2i) -> void:
	blackboard.reset_for_mission(
		PlatoonTypes.MissionType.ATTACK_OBJECTIVE,
		p_objective_hex
	)

	planned_phase = ROLE_UNASSIGNED
	phase_elapsed_seconds = 0.0
	phase_transition_cooldown_timer = 0.0
	plan_refresh_timer = 0.0


func _physics_process(delta: float) -> void:
	if not Globals.game_started:
		return
	
	tactical_tick_timer += delta

	if tactical_tick_timer < tactical_tick_interval:
		return

	var tick_delta: float = tactical_tick_timer
	tactical_tick_timer = 0.0

	_tactical_tick(tick_delta)
	
	_print_blackboard_state()


func _tactical_tick(delta: float) -> void:
	phase_elapsed_seconds += delta
	plan_refresh_timer -= delta
	phase_transition_cooldown_timer -= delta

	if plan_refresh_timer < 0.0:
		plan_refresh_timer = 0.0

	if phase_transition_cooldown_timer < 0.0:
		phase_transition_cooldown_timer = 0.0

	# 1. Read squad states.
	_read_squad_states()

	# 2. Read visible enemies and reports.
	_read_visible_enemies_and_reports()

	# 3. Update PlatoonBlackboard.
	_update_platoon_blackboard(delta)

	# 4. Decay old enemy tracks.
	_decay_old_enemy_tracks(delta)

	# 5. Build suspected enemy zones.
	_build_suspected_enemy_zones()

	# Beliefs depend on post-decay tracks and zones.
	blackboard.recalculate_platoon_values()
	blackboard.recalculate_objective_beliefs(0.0)

	# 6. Evaluate current phase.
	_evaluate_current_phase()

	# 7. Select or update HTN plan for phase.
	_select_or_update_htn_plan_for_phase()

	# 8. Score squad-role assignments.
	_score_squad_role_assignments()

	# 9. Issue squad-level orders.
	_issue_squad_level_orders()

	# 10. Monitor triggers for phase transition.
	_monitor_triggers_for_phase_transition()


func _read_squad_states() -> void:
	for squad: Unit in squads:
		if squad == null:
			continue

		var state: SquadTacticalState = _build_state_from_squad(squad)
		blackboard.update_squad_state(state)


func _read_visible_enemies_and_reports() -> void:
	blackboard.ingest_unit_enemy_tracks(squads)
	_update_objective_observation()


func _update_platoon_blackboard(delta: float) -> void:
	blackboard.tactical_update(delta)


func _decay_old_enemy_tracks(delta: float) -> void:
	blackboard._decay_enemy_tracks(delta)
	blackboard._decay_suspected_zones(delta)


func _build_suspected_enemy_zones() -> void:
	_update_objective_suspected_zone()
	_update_track_suspected_zones()


func _update_objective_suspected_zone() -> void:
	if not blackboard.has_objective:
		return

	var suspicion: float = 0.35
	var danger: float = 0.35

	if blackboard.objective_enemy_confidence > suspicion:
		suspicion = blackboard.objective_enemy_confidence
		danger = blackboard.objective_enemy_confidence

	if blackboard.objective_clear_confidence >= 0.75:
		suspicion = 0.10
		danger = 0.10

	_set_or_create_suspected_zone(
		blackboard.objective_hex,
		suspicion,
		danger,
		PlatoonTypes.ZoneReason.OBJECTIVE,
		-1
	)


func _update_track_suspected_zones() -> void:
	for track: EnemyTrack in blackboard.enemy_tracks:
		if track == null:
			continue

		if track.confidence <= 0.0:
			continue

		var suspicion: float = track.confidence
		var danger: float = track.confidence

		if track.observed_strength > danger:
			danger = track.observed_strength

		if track.uncertainty_radius > 0:
			suspicion -= float(track.uncertainty_radius) * 0.08
			danger -= float(track.uncertainty_radius) * 0.06

		suspicion = clampf(suspicion, 0.05, 1.0)
		danger = clampf(danger, 0.05, 1.0)

		_set_or_create_suspected_zone(
			track.last_known_hex,
			suspicion,
			danger,
			PlatoonTypes.ZoneReason.STALE_CONTACT,
			track.track_id
		)


func _set_or_create_suspected_zone(
	p_hex: Vector2i,
	p_suspicion: float,
	p_danger: float,
	p_reason: int,
	p_source_track_id: int
) -> SuspectedEnemyZone:
	var zone: SuspectedEnemyZone = _find_suspected_zone_at_hex(p_hex)

	if zone == null:
		zone = blackboard._add_or_reinforce_suspected_zone(
			p_hex,
			p_suspicion,
			p_danger,
			p_reason,
			p_source_track_id
		)
		return zone

	zone.suspicion = p_suspicion
	zone.danger = p_danger
	zone.reason = p_reason
	zone.source_track_id = p_source_track_id
	zone.last_update_time = blackboard.current_time_seconds
	zone.age_seconds = 0.0

	return zone


func _find_suspected_zone_at_hex(p_hex: Vector2i) -> SuspectedEnemyZone:
	for zone: SuspectedEnemyZone in blackboard.suspected_enemy_zones:
		if zone.hex == p_hex:
			return zone

	return null


func _evaluate_current_phase() -> void:
	var next_phase: int = _select_phase_from_blackboard()

	if next_phase == blackboard.current_phase:
		return

	if phase_transition_cooldown_timer > 0.0:
		return

	_change_phase(next_phase)


func _select_phase_from_blackboard() -> int:
	if blackboard.mission_type == PlatoonTypes.MissionType.NONE:
		return PlatoonTypes.Phase.IDLE

	if blackboard.mission_type == PlatoonTypes.MissionType.WITHDRAW:
		return PlatoonTypes.Phase.WITHDRAW

	if _must_withdraw_now():
		return PlatoonTypes.Phase.WITHDRAW

	if _must_reorganize_now():
		return PlatoonTypes.Phase.REORGANIZE

	if blackboard.mission_type == PlatoonTypes.MissionType.ATTACK_OBJECTIVE:
		return _select_attack_phase()

	if blackboard.mission_type == PlatoonTypes.MissionType.DEFEND_AREA:
		return _select_defense_phase()

	return PlatoonTypes.Phase.IDLE


func _select_attack_phase() -> int:
	if not blackboard.has_objective:
		return PlatoonTypes.Phase.IDLE

	if blackboard.current_phase == PlatoonTypes.Phase.IDLE:
		return PlatoonTypes.Phase.PLANNING_ATTACK

	if blackboard.current_phase == PlatoonTypes.Phase.PLANNING_ATTACK:
		if phase_elapsed_seconds >= tactical_tick_interval:
			return PlatoonTypes.Phase.APPROACH_TO_OBJECTIVE
		return blackboard.current_phase

	if blackboard.is_objective_probably_clear():
		return PlatoonTypes.Phase.CONSOLIDATE_OBJECTIVE

	if blackboard.objective_enemy_confidence >= PlatoonBlackboard.ACTIONABLE_ENEMY_CONFIDENCE:
		if blackboard.current_phase == PlatoonTypes.Phase.APPROACH_TO_OBJECTIVE:
			return PlatoonTypes.Phase.DEVELOP_CONTACT

		if blackboard.current_phase == PlatoonTypes.Phase.RECON_OBJECTIVE:
			return PlatoonTypes.Phase.DEVELOP_CONTACT

	if blackboard.current_phase == PlatoonTypes.Phase.APPROACH_TO_OBJECTIVE:
		if blackboard.should_recon_objective():
			return PlatoonTypes.Phase.RECON_OBJECTIVE
		return blackboard.current_phase

	if blackboard.current_phase == PlatoonTypes.Phase.RECON_OBJECTIVE:
		if blackboard.objective_clear_confidence >= 0.75:
			return PlatoonTypes.Phase.CONSOLIDATE_OBJECTIVE
		return blackboard.current_phase

	if blackboard.current_phase == PlatoonTypes.Phase.DEVELOP_CONTACT:
		if blackboard.can_assault_objective():
			return PlatoonTypes.Phase.SUPPRESS_OBJECTIVE
		return blackboard.current_phase

	if blackboard.current_phase == PlatoonTypes.Phase.SUPPRESS_OBJECTIVE:
		if phase_elapsed_seconds >= min_suppress_seconds:
			return PlatoonTypes.Phase.MANEUVER_TO_ASSAULT_POSITION
		return blackboard.current_phase

	if blackboard.current_phase == PlatoonTypes.Phase.MANEUVER_TO_ASSAULT_POSITION:
		if phase_elapsed_seconds >= min_maneuver_seconds:
			return PlatoonTypes.Phase.ASSAULT_OBJECTIVE
		return blackboard.current_phase

	if blackboard.current_phase == PlatoonTypes.Phase.ASSAULT_OBJECTIVE:
		if blackboard.is_objective_probably_clear():
			return PlatoonTypes.Phase.CONSOLIDATE_OBJECTIVE
		return blackboard.current_phase

	if blackboard.current_phase == PlatoonTypes.Phase.CONSOLIDATE_OBJECTIVE:
		return blackboard.current_phase

	return PlatoonTypes.Phase.PLANNING_ATTACK


func _select_defense_phase() -> int:
	if _has_actionable_enemy_track():
		return PlatoonTypes.Phase.DEVELOP_CONTACT

	return PlatoonTypes.Phase.CONSOLIDATE_OBJECTIVE


func _must_withdraw_now() -> bool:
	if blackboard.platoon_effective_strength <= withdraw_strength_threshold:
		return true

	if blackboard.platoon_average_stress >= emergency_stress_threshold:
		return true

	return false


func _must_reorganize_now() -> bool:
	if blackboard.current_phase == PlatoonTypes.Phase.WITHDRAW:
		return false

	if blackboard.platoon_effective_strength <= reorganize_strength_threshold:
		return true

	if blackboard.platoon_average_stress >= high_stress_threshold:
		return true

	return false


func _change_phase(p_next_phase: int) -> void:
	blackboard.current_phase = p_next_phase
	phase_elapsed_seconds = 0.0
	phase_transition_cooldown_timer = phase_transition_cooldown_seconds
	planned_phase = ROLE_UNASSIGNED
	plan_refresh_timer = 0.0
	blackboard.clear_phase_tasks()
	blackboard.clear_role_assignments()


func _select_or_update_htn_plan_for_phase() -> void:
	if planned_phase == blackboard.current_phase:
		if plan_refresh_timer > 0.0:
			if blackboard.phase_tasks.size() > 0:
				return

	blackboard.clear_phase_tasks()

	if blackboard.current_phase == PlatoonTypes.Phase.IDLE:
		_build_idle_plan()
	elif blackboard.current_phase == PlatoonTypes.Phase.PLANNING_ATTACK:
		_build_planning_attack_plan()
	elif blackboard.current_phase == PlatoonTypes.Phase.APPROACH_TO_OBJECTIVE:
		_build_approach_plan()
	elif blackboard.current_phase == PlatoonTypes.Phase.RECON_OBJECTIVE:
		_build_recon_plan()
	elif blackboard.current_phase == PlatoonTypes.Phase.DEVELOP_CONTACT:
		_build_develop_contact_plan()
	elif blackboard.current_phase == PlatoonTypes.Phase.SUPPRESS_OBJECTIVE:
		_build_suppress_plan()
	elif blackboard.current_phase == PlatoonTypes.Phase.MANEUVER_TO_ASSAULT_POSITION:
		_build_maneuver_plan()
	elif blackboard.current_phase == PlatoonTypes.Phase.ASSAULT_OBJECTIVE:
		_build_assault_plan()
	elif blackboard.current_phase == PlatoonTypes.Phase.CONSOLIDATE_OBJECTIVE:
		_build_consolidate_plan()
	elif blackboard.current_phase == PlatoonTypes.Phase.REORGANIZE:
		_build_reorganize_plan()
	elif blackboard.current_phase == PlatoonTypes.Phase.WITHDRAW:
		_build_withdraw_plan()

	planned_phase = blackboard.current_phase
	plan_refresh_timer = plan_refresh_interval


func _build_idle_plan() -> void:
	return


func _build_planning_attack_plan() -> void:
	blackboard.create_task(
		PlatoonTypes.TaskType.OBSERVE_HEX,
		blackboard.objective_hex,
		PlatoonTypes.Role.LEAD_PROBE,
		0.70
	)

	blackboard.create_task(
		PlatoonTypes.TaskType.RALLY_AT_HEX,
		_get_platoon_center_hex(),
		PlatoonTypes.Role.RESERVE,
		0.45
	)


func _build_approach_plan() -> void:
	var staging_hex: Vector2i = _get_assault_staging_hex()
	var support_hex: Vector2i = _get_support_by_fire_hex()

	blackboard.create_task(
		PlatoonTypes.TaskType.MOVE_TO_HEX,
		staging_hex,
		PlatoonTypes.Role.LEAD_PROBE,
		0.85
	)

	blackboard.create_task(
		PlatoonTypes.TaskType.MOVE_TO_HEX,
		support_hex,
		PlatoonTypes.Role.OVERWATCH,
		0.70
	)

	blackboard.create_task(
		PlatoonTypes.TaskType.RALLY_AT_HEX,
		_get_platoon_center_hex(),
		PlatoonTypes.Role.RESERVE,
		0.40
	)


func _build_recon_plan() -> void:
	blackboard.create_task(
		PlatoonTypes.TaskType.OBSERVE_HEX,
		blackboard.objective_hex,
		PlatoonTypes.Role.LEAD_PROBE,
		0.95
	)

	blackboard.create_task(
		PlatoonTypes.TaskType.OVERWATCH_ZONE,
		blackboard.objective_hex,
		PlatoonTypes.Role.OVERWATCH,
		0.80
	)

	blackboard.create_task(
		PlatoonTypes.TaskType.RALLY_AT_HEX,
		_get_assault_staging_hex(),
		PlatoonTypes.Role.RESERVE,
		0.45
	)


func _build_develop_contact_plan() -> void:
	var contact_hex: Vector2i = _get_best_contact_hex()
	var support_task: PlatoonTask = blackboard.create_task(
		PlatoonTypes.TaskType.SUPPRESS_TRACK,
		contact_hex,
		PlatoonTypes.Role.SUPPORT_BY_FIRE,
		0.95
	)
	support_task.target_track_id = _get_best_contact_track_id()

	blackboard.create_task(
		PlatoonTypes.TaskType.OVERWATCH_ZONE,
		contact_hex,
		PlatoonTypes.Role.OVERWATCH,
		0.80
	)

	blackboard.create_task(
		PlatoonTypes.TaskType.MANEUVER_TO_HEX,
		_get_assault_staging_hex(),
		PlatoonTypes.Role.ASSAULT,
		0.65
	)


func _build_suppress_plan() -> void:
	var contact_hex: Vector2i = _get_best_contact_hex()
	var task: PlatoonTask = blackboard.create_task(
		PlatoonTypes.TaskType.SUPPORT_BY_FIRE,
		contact_hex,
		PlatoonTypes.Role.SUPPORT_BY_FIRE,
		1.00
	)
	task.target_track_id = _get_best_contact_track_id()

	blackboard.create_task(
		PlatoonTypes.TaskType.SUPPRESS_TRACK,
		contact_hex,
		PlatoonTypes.Role.OVERWATCH,
		0.85
	)

	blackboard.create_task(
		PlatoonTypes.TaskType.MANEUVER_TO_HEX,
		_get_assault_staging_hex(),
		PlatoonTypes.Role.ASSAULT,
		0.60
	)


func _build_maneuver_plan() -> void:
	var contact_hex: Vector2i = _get_best_contact_hex()

	blackboard.create_task(
		PlatoonTypes.TaskType.SUPPORT_BY_FIRE,
		contact_hex,
		PlatoonTypes.Role.SUPPORT_BY_FIRE,
		0.95
	)

	blackboard.create_task(
		PlatoonTypes.TaskType.MANEUVER_TO_HEX,
		_get_assault_staging_hex(),
		PlatoonTypes.Role.ASSAULT,
		0.95
	)

	blackboard.create_task(
		PlatoonTypes.TaskType.OVERWATCH_ZONE,
		blackboard.objective_hex,
		PlatoonTypes.Role.SECURITY,
		0.60
	)


func _build_assault_plan() -> void:
	blackboard.create_task(
		PlatoonTypes.TaskType.ASSAULT_HEX,
		blackboard.objective_hex,
		PlatoonTypes.Role.ASSAULT,
		1.00
	)

	blackboard.create_task(
		PlatoonTypes.TaskType.SUPPORT_BY_FIRE,
		_get_best_contact_hex(),
		PlatoonTypes.Role.SUPPORT_BY_FIRE,
		0.80
	)

	blackboard.create_task(
		PlatoonTypes.TaskType.SECURE_HEX,
		blackboard.objective_hex,
		PlatoonTypes.Role.SECURITY,
		0.65
	)


func _build_consolidate_plan() -> void:
	blackboard.create_task(
		PlatoonTypes.TaskType.SECURE_HEX,
		blackboard.objective_hex,
		PlatoonTypes.Role.SECURITY,
		0.95
	)

	blackboard.create_task(
		PlatoonTypes.TaskType.OVERWATCH_ZONE,
		blackboard.objective_hex,
		PlatoonTypes.Role.OVERWATCH,
		0.75
	)

	blackboard.create_task(
		PlatoonTypes.TaskType.RALLY_AT_HEX,
		blackboard.objective_hex,
		PlatoonTypes.Role.RALLY,
		0.70
	)


func _build_reorganize_plan() -> void:
	var rally_hex: Vector2i = _get_safe_rally_hex()

	blackboard.create_task(
		PlatoonTypes.TaskType.RALLY_AT_HEX,
		rally_hex,
		PlatoonTypes.Role.RALLY,
		1.00
	)

	blackboard.create_task(
		PlatoonTypes.TaskType.OVERWATCH_ZONE,
		rally_hex,
		PlatoonTypes.Role.SECURITY,
		0.65
	)


func _build_withdraw_plan() -> void:
	var withdraw_hex: Vector2i = _get_withdraw_hex()

	blackboard.create_task(
		PlatoonTypes.TaskType.WITHDRAW_TO_HEX,
		withdraw_hex,
		PlatoonTypes.Role.WITHDRAWING,
		1.00
	)

	blackboard.create_task(
		PlatoonTypes.TaskType.OVERWATCH_ZONE,
		withdraw_hex,
		PlatoonTypes.Role.SECURITY,
		0.50
	)


func _score_squad_role_assignments() -> void:
	blackboard.clear_role_assignments()

	var unassigned_squads: Array[Node] = []
	for squad: Unit in squads:
		if squad == null:
			continue
		unassigned_squads.append(squad)

	for task: PlatoonTask in blackboard.phase_tasks:
		var best_squad: Node = null
		var best_score: float = INVALID_SCORE

		for squad: Node in unassigned_squads:
			var state: SquadTacticalState = blackboard.get_squad_state(squad)
			if state == null:
				continue

			var score: float = _score_squad_for_task(state, task)
			if score > best_score:
				best_score = score
				best_squad = squad

		if best_squad == null:
			continue

		if best_score <= INVALID_SCORE * 0.5:
			continue

		task.assigned_squad = best_squad
		blackboard.assign_role(best_squad, task.required_role)
		unassigned_squads.erase(best_squad)

	_assign_remaining_squads_to_reserve(unassigned_squads)


func _assign_remaining_squads_to_reserve(p_unassigned_squads: Array[Node]) -> void:
	for squad: Node in p_unassigned_squads:
		var state: SquadTacticalState = blackboard.get_squad_state(squad)
		if state == null:
			continue

		if state.is_combat_ineffective():
			blackboard.assign_role(squad, PlatoonTypes.Role.RALLY)
		elif state.is_panicking():
			blackboard.assign_role(squad, PlatoonTypes.Role.WITHDRAWING)
		else:
			blackboard.assign_role(squad, PlatoonTypes.Role.RESERVE)


func _score_squad_for_task(state: SquadTacticalState, task: PlatoonTask) -> float:
	if state == null:
		return INVALID_SCORE

	if task == null:
		return INVALID_SCORE

	if state.is_combat_ineffective():
		if task.required_role != PlatoonTypes.Role.RALLY:
			if task.required_role != PlatoonTypes.Role.WITHDRAWING:
				return INVALID_SCORE

	if state.is_panicking():
		if task.required_role != PlatoonTypes.Role.RALLY:
			if task.required_role != PlatoonTypes.Role.WITHDRAWING:
				return INVALID_SCORE

	var distance: int = blackboard.get_hex_distance(state.hex, task.target_hex)
	var distance_score: float = 1.0 - clampf(float(distance) / 10.0, 0.0, 1.0)
	var stress_score: float = 1.0 - clampf(state.stress_effective / 100.0, 0.0, 1.0)
	var score: float = 0.0

	score += task.priority * 100.0
	score += state.combat_effectiveness * 45.0
	score += state.cohesion * 20.0
	score += stress_score * 25.0
	score += distance_score * 18.0

	score += _role_specific_score(state, task, distance)

	return score


func _role_specific_score(state: SquadTacticalState, task: PlatoonTask, distance: int) -> float:
	var score: float = 0.0

	if task.required_role == PlatoonTypes.Role.LEAD_PROBE:
		if state.can_move_normally():
			score += 20.0
		else:
			score -= 40.0

		if state.stress_effective <= 45.0:
			score += 10.0

	elif task.required_role == PlatoonTypes.Role.OVERWATCH:
		if state.can_fire():
			score += 18.0
		else:
			score -= 60.0

		if distance <= 5:
			score += 8.0

	elif task.required_role == PlatoonTypes.Role.SUPPORT_BY_FIRE:
		if state.can_fire():
			score += 30.0
		else:
			score -= 80.0

		if state.combat_effectiveness >= 0.60:
			score += 15.0

	elif task.required_role == PlatoonTypes.Role.ASSAULT:
		if state.can_move_normally():
			score += 25.0
		else:
			score -= 75.0

		if state.combat_effectiveness >= 0.65:
			score += 20.0

		if state.stress_effective <= 55.0:
			score += 12.0

	elif task.required_role == PlatoonTypes.Role.RESERVE:
		score += 5.0

	elif task.required_role == PlatoonTypes.Role.RALLY:
		if state.combat_effectiveness < 0.50:
			score += 30.0

		if state.stress_effective >= 55.0:
			score += 25.0

	elif task.required_role == PlatoonTypes.Role.SECURITY:
		if state.can_fire():
			score += 12.0

	elif task.required_role == PlatoonTypes.Role.WITHDRAWING:
		if state.can_move_normally():
			score += 20.0
		else:
			score += 5.0

	return score


func _issue_squad_level_orders() -> void:
	for task: PlatoonTask in blackboard.phase_tasks:
		if task.assigned_squad == null:
			continue

		var state: SquadTacticalState = blackboard.get_squad_state(task.assigned_squad)
		if state != null:
			state.assigned_task_id = task.task_id

		_issue_task_to_squad(task.assigned_squad, task)

	for squad: Unit in squads:
		if squad == null:
			continue

		if blackboard.assigned_roles.has(squad):
			var role_value: Variant = blackboard.assigned_roles.get(squad)
			var role: int = int(role_value)
			_issue_role_to_squad(squad, role)


func _issue_task_to_squad(squad: Node, task: PlatoonTask) -> void:
	if squad == null:
		return

	if task == null:
		return

	squad.set_meta("platoon_task_id", task.task_id)
	squad.set_meta("platoon_task_type", task.task_type)
	squad.set_meta("platoon_role", task.required_role)
	squad.set_meta("platoon_target_hex", task.target_hex)
	squad.set_meta("platoon_target_track_id", task.target_track_id)

	if _task_is_movement_task(task):
		_issue_move_order(squad, task.target_hex)
		return

	if _task_is_fire_task(task):
		_issue_fire_order(squad, task.target_hex, task.target_track_id)
		return

	if task.task_type == PlatoonTypes.TaskType.OBSERVE_HEX:
		_issue_observe_order(squad, task.target_hex)
		return
	
	pass
	#match task.task_type:
		#PlatoonTypes.TaskType.MOVE_TO_HEX:
			#_issue_move_order(squad, task.target_hex)
#
		#PlatoonTypes.TaskType.MANEUVER_TO_HEX:
			#_issue_move_order(squad, task.target_hex)
#
		#PlatoonTypes.TaskType.ASSAULT_HEX:
			#_issue_assault_order(squad, task.target_hex)
#
		#PlatoonTypes.TaskType.WITHDRAW_TO_HEX:
			#_issue_withdraw_order(squad, task.target_hex)
#
		#PlatoonTypes.TaskType.RALLY_AT_HEX:
			#_issue_rally_order(squad, task.target_hex)
#
		#PlatoonTypes.TaskType.OBSERVE_HEX:
			#_issue_observe_order(squad, task.target_hex)
#
		#PlatoonTypes.TaskType.OVERWATCH_ZONE:
			#_issue_overwatch_order(squad, task.target_hex)
#
		#PlatoonTypes.TaskType.SUPPORT_BY_FIRE:
			#_issue_fire_order(squad, task.target_hex, task.target_track_id)
#
		#PlatoonTypes.TaskType.SUPPRESS_TRACK:
			#_issue_fire_order(squad, task.target_hex, task.target_track_id)
#
		#PlatoonTypes.TaskType.SECURE_HEX:
			#_issue_secure_order(squad, task.target_hex)
#
		#_:
			#_issue_stop_order(squad)

func _issue_role_to_squad(squad: Node, role: int) -> void:
	if squad == null:
		return

	squad.set_meta("platoon_role", role)

	if squad.has_method("set_platoon_role"):
		squad.call("set_platoon_role", role)


func _task_is_movement_task(task: PlatoonTask) -> bool:
	if task.task_type == PlatoonTypes.TaskType.MOVE_TO_HEX:
		return true

	if task.task_type == PlatoonTypes.TaskType.MANEUVER_TO_HEX:
		return true

	if task.task_type == PlatoonTypes.TaskType.ASSAULT_HEX:
		return true

	if task.task_type == PlatoonTypes.TaskType.SECURE_HEX:
		return true

	if task.task_type == PlatoonTypes.TaskType.RALLY_AT_HEX:
		return true

	if task.task_type == PlatoonTypes.TaskType.WITHDRAW_TO_HEX:
		return true

	return false


func _task_is_fire_task(task: PlatoonTask) -> bool:
	if task.task_type == PlatoonTypes.TaskType.OVERWATCH_ZONE:
		return true

	if task.task_type == PlatoonTypes.TaskType.SUPPORT_BY_FIRE:
		return true

	if task.task_type == PlatoonTypes.TaskType.SUPPRESS_TRACK:
		return true

	return false


func _issue_move_order(squad: Unit, target_hex: Vector2i) -> void:
	squad.order(Globals.UnitCmd.MOVE, target_hex)


func _issue_fire_order(squad: Node, target_hex: Vector2i, target_track_id: int) -> void:
	squad.set_meta("platoon_fire_target_hex", target_hex)
	squad.set_meta("platoon_fire_target_track_id", target_track_id)
	squad.order(Globals.UnitCmd.FIRE_AT_HEX, target_hex)


func _issue_observe_order(squad: Unit, target_hex: Vector2i) -> void:
	squad.set_meta("platoon_observe_hex", target_hex)
	squad.movement.stop()


func _monitor_triggers_for_phase_transition() -> void:
	if phase_transition_cooldown_timer > 0.0:
		return

	if _must_withdraw_now():
		if blackboard.current_phase != PlatoonTypes.Phase.WITHDRAW:
			_change_phase(PlatoonTypes.Phase.WITHDRAW)
		return

	if _must_reorganize_now():
		if blackboard.current_phase != PlatoonTypes.Phase.REORGANIZE:
			_change_phase(PlatoonTypes.Phase.REORGANIZE)
		return

	if blackboard.current_phase == PlatoonTypes.Phase.ASSAULT_OBJECTIVE:
		if blackboard.is_objective_probably_clear():
			_change_phase(PlatoonTypes.Phase.CONSOLIDATE_OBJECTIVE)
			return


func _build_state_from_squad(squad: Unit) -> SquadTacticalState:
	var state: SquadTacticalState = SquadTacticalState.new()

	var squad_hex: Vector2i = squad.current_hex
	var members_alive: int = squad.members_alive
	var original_size: int = squad.original_size
	var combat_effectiveness: float = squad.combat_stats.combat_effectiveness
	var stress_effective: float = squad.stress_system.S_eff
	var cohesion: float = squad.combat_stats.cohesion_current
	var morale_state: STATES.MoraleState = squad.stress_system.state

	state.configure(
		squad,
		squad_hex,
		members_alive,
		original_size,
		combat_effectiveness,
		stress_effective,
		cohesion,
		morale_state,
	)
	
	return state


func _update_objective_observation() -> void:
	for squad: Unit in squads:
		if squad == null:
			continue

		if squad.stress_system.state == STATES.MoraleState.COMBAT_INEFFECTIVE:
			continue

		if _squad_can_observe_objective(squad):
			blackboard.mark_objective_observed_clear(0.00)
			return


func _squad_can_observe_objective(squad: Unit) -> bool:
	if squad.current_hex == blackboard.objective_hex:
		return true

	var visible_hexes: Variant = LOSHelper.los_lookup.get(squad.current_hex, [])
	if visible_hexes.has(blackboard.objective_hex):
		return true

	return false


func _has_actionable_enemy_track() -> bool:
	for track: EnemyTrack in blackboard.enemy_tracks:
		if track == null:
			continue

		if track.is_actionable(PlatoonBlackboard.ACTIONABLE_ENEMY_CONFIDENCE):
			return true

	return false


func _get_best_contact_track() -> EnemyTrack:
	var best_track: EnemyTrack = null
	var best_score: float = INVALID_SCORE

	for track: EnemyTrack in blackboard.enemy_tracks:
		if track == null:
			continue

		var distance_to_objective: int = blackboard.get_hex_distance(track.last_known_hex, blackboard.objective_hex)
		var score: float = track.confidence * 100.0
		score += track.observed_strength * 35.0
		score -= float(distance_to_objective) * 4.0
		score -= float(track.uncertainty_radius) * 8.0

		if score > best_score:
			best_score = score
			best_track = track

	return best_track


func _get_best_contact_hex() -> Vector2i:
	var best_track: EnemyTrack = _get_best_contact_track()

	if best_track != null:
		return best_track.last_known_hex

	return blackboard.objective_hex


func _get_best_contact_track_id() -> int:
	var best_track: EnemyTrack = _get_best_contact_track()

	if best_track != null:
		return best_track.track_id

	return -1


func _get_platoon_center_hex() -> Vector2i:
	var count: int = 0
	var total_x: int = 0
	var total_y: int = 0

	for squad: Unit in squads:
		if squad == null:
			continue

		total_x += squad.current_hex.x
		total_y += squad.current_hex.y
		count += 1

	if count <= 0:
		return Vector2i.ZERO

	var center_x: int = int(round(float(total_x) / float(count)))
	var center_y: int = int(round(float(total_y) / float(count)))

	return Vector2i(center_x, center_y)


func _get_assault_staging_hex() -> Vector2i:
	var platoon_center: Vector2i = _get_platoon_center_hex()
	var best_hex: Vector2i = blackboard.objective_hex
	var best_distance: int = 999999

	for direction: Vector2i in HEX_DIRECTIONS:
		var candidate: Vector2i = blackboard.objective_hex + direction * 2
		var distance: int = blackboard.get_hex_distance(candidate, platoon_center)

		if distance < best_distance:
			best_distance = distance
			best_hex = candidate

	return best_hex


func _get_support_by_fire_hex() -> Vector2i:
	if blackboard.support_by_fire_hexes.size() > 0:
		return blackboard.support_by_fire_hexes[0]

	var objective: Vector2i = blackboard.objective_hex
	var platoon_center: Vector2i = _get_platoon_center_hex()
	var best_hex: Vector2i = objective
	var best_score: float = INVALID_SCORE

	for direction: Vector2i in HEX_DIRECTIONS:
		var candidate: Vector2i = objective + direction * 3
		var distance_to_platoon: int = blackboard.get_hex_distance(candidate, platoon_center)
		var distance_to_objective: int = blackboard.get_hex_distance(candidate, objective)
		var score: float = 0.0

		score -= float(distance_to_platoon) * 2.0
		score += float(distance_to_objective) * 1.5

		if score > best_score:
			best_score = score
			best_hex = candidate

	return best_hex


func _get_safe_rally_hex() -> Vector2i:
	if blackboard.current_phase == PlatoonTypes.Phase.CONSOLIDATE_OBJECTIVE:
		return blackboard.objective_hex

	return _get_assault_staging_hex()


func _get_withdraw_hex() -> Vector2i:
	var platoon_center: Vector2i = _get_platoon_center_hex()
	var objective: Vector2i = blackboard.objective_hex
	var best_hex: Vector2i = platoon_center
	var best_distance_from_objective: int = -1

	for direction: Vector2i in HEX_DIRECTIONS:
		var candidate: Vector2i = platoon_center + direction * 3
		var distance_from_objective: int = blackboard.get_hex_distance(candidate, objective)

		if distance_from_objective > best_distance_from_objective:
			best_distance_from_objective = distance_from_objective
			best_hex = candidate

	return best_hex


func _print_blackboard_state() -> void:
	print("--- Blackboard State ----------------------------------------------------------------")
	print("Mission type: ", blackboard.mission_type)
	print("Current phase: ", blackboard.current_phase)
	print("Phase elapsed: ", phase_elapsed_seconds)
	print("Plan tasks: ", blackboard.phase_tasks.size())
	print("Has objective: ", blackboard.has_objective)
	print("Objective hex: ", blackboard.objective_hex)

	print("Friendly squads: ", blackboard.friendly_squads.size())
	print("Squad states: ", blackboard.squad_states.size())

	print("Enemy tracks: ", blackboard.enemy_tracks.size())
	print("Suspected enemy zones: ", blackboard.suspected_enemy_zones.size())

	print("Objective enemy confidence: ", blackboard.objective_enemy_confidence)
	print("Objective clear confidence: ", blackboard.objective_clear_confidence)

	var should_recon: bool = blackboard.should_recon_objective()
	print("Should recon objective: ", should_recon)

	var probably_clear: bool = blackboard.is_objective_probably_clear()
	print("Objective probably clear: ", probably_clear)

	var can_assault: bool = blackboard.can_assault_objective()
	print("Can assault objective: ", can_assault)

	_print_squad_states()
	_print_suspected_zones()
	_print_phase_tasks()


func _print_squad_states() -> void:
	print("--- Squad States ---")

	for squad: Node in blackboard.friendly_squads:
		var state: SquadTacticalState = blackboard.get_squad_state(squad)

		if state == null:
			print("Missing state for squad: ", squad.name)
			continue

		print(
			state.squad.name,
			" hex=", state.hex,
			" E=", state.combat_effectiveness,
			" stress=", state.stress_effective,
			" cohesion=", state.cohesion,
			" morale=", state.morale_state,
			" role=", state.current_role,
			" task=", state.assigned_task_id
		)


func _print_suspected_zones() -> void:
	print("--- Suspected Zones ---")

	for zone: SuspectedEnemyZone in blackboard.suspected_enemy_zones:
		print(
			"zone_id=", zone.zone_id,
			" hex=", zone.hex,
			" suspicion=", zone.suspicion,
			" danger=", zone.danger,
			" reason=", zone.reason,
			" track=", zone.source_track_id
		)


func _print_phase_tasks() -> void:
	print("--- Phase Tasks ---")

	for task: PlatoonTask in blackboard.phase_tasks:
		var assigned_name: String = "none"
		if task.assigned_squad != null:
			assigned_name = task.assigned_squad.name
		
		var task_type_name: String = PlatoonTypes.task_type_to_string(task.task_type)
		var role_name: String = PlatoonTypes.role_to_string(task.required_role)
		
		print(
			"task_id=", task.task_id,
			" type=", task_type_name,
			" role=", role_name,
			" target=", task.target_hex,
			" priority=", task.priority,
			" assigned=", assigned_name
		)
