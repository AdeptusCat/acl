class_name PlatoonBlackboard
extends RefCounted

const ACTIONABLE_ENEMY_CONFIDENCE: float = 0.60
const ASSAULT_REQUIRED_ENEMY_CONFIDENCE: float = 0.70
const OBJECTIVE_NEAR_RADIUS: int = 2
const CLEAR_CONFIDENCE_GAIN_PER_SECOND: float = 0.01
const CLEAR_CONFIDENCE_LOSS_PER_SECOND: float = 0.12

var mission_type: int = PlatoonTypes.MissionType.NONE
var current_phase: int = PlatoonTypes.Phase.IDLE

var objective_hex: Vector2i = Vector2i.ZERO
var has_objective: bool = false

var friendly_squads: Array[Node] = []
var squad_states: Dictionary = {}

var enemy_tracks: Array[EnemyTrack] = []
var suspected_enemy_zones: Array[SuspectedEnemyZone] = []
var phase_tasks: Array[PlatoonTask] = []

var assigned_roles: Dictionary = {}

var objective_enemy_confidence: float = 0.0
var objective_clear_confidence: float = 0.0
var objective_observed_this_tick: bool = false

var platoon_effective_strength: float = 1.0
var platoon_average_stress: float = 0.0
var platoon_average_cohesion: float = 1.0

var support_by_fire_hexes: Array[Vector2i] = []
var assault_staging_hexes: Array[Vector2i] = []
var covered_approach_routes: Array[Array] = []

var current_time_seconds: float = 0.0

var next_track_id: int = 1
var next_zone_id: int = 1
var next_task_id: int = 1

func reset_for_mission(p_mission_type: int, p_objective_hex: Vector2i) -> void:
	mission_type = p_mission_type
	current_phase = PlatoonTypes.Phase.IDLE

	objective_hex = p_objective_hex
	has_objective = true

	enemy_tracks.clear()
	suspected_enemy_zones.clear()
	phase_tasks.clear()
	assigned_roles.clear()

	objective_enemy_confidence = 0.0
	objective_clear_confidence = 0.0
	objective_observed_this_tick = false

	support_by_fire_hexes.clear()
	assault_staging_hexes.clear()
	covered_approach_routes.clear()

	_add_or_reinforce_suspected_zone(
		objective_hex,
		0.35,
		0.35,
		PlatoonTypes.ZoneReason.OBJECTIVE,
		-1
	)

func tactical_update(delta: float) -> void:
	current_time_seconds += delta

	#_decay_enemy_tracks(delta)
	#_decay_suspected_zones(delta)

	recalculate_platoon_values()
	recalculate_objective_beliefs(delta)

	objective_observed_this_tick = false

func register_friendly_squad(squad: Node) -> void:
	if squad == null:
		return

	if friendly_squads.has(squad):
		return

	friendly_squads.append(squad)

func unregister_friendly_squad(squad: Node) -> void:
	if squad == null:
		return

	friendly_squads.erase(squad)
	squad_states.erase(squad)
	assigned_roles.erase(squad)

func update_squad_state(state: SquadTacticalState) -> void:
	if state == null:
		return

	if state.squad == null:
		return

	register_friendly_squad(state.squad)
	squad_states[state.squad] = state

func get_squad_state(squad: Node) -> SquadTacticalState:
	var value: Variant = squad_states.get(squad)

	if value == null:
		return null

	return value as SquadTacticalState

func assign_role(squad: Node, role: int) -> void:
	if squad == null:
		return

	assigned_roles[squad] = role

	var state: SquadTacticalState = get_squad_state(squad)
	if state != null:
		state.current_role = role

func clear_role_assignments() -> void:
	assigned_roles.clear()

	for squad: Node in friendly_squads:
		var state: SquadTacticalState = get_squad_state(squad)
		if state != null:
			state.current_role = PlatoonTypes.Role.NONE


func ingest_unit_enemy_tracks(p_friendly_units: Array[Unit]) -> void:
	enemy_tracks.clear()

	var best_tracks_by_enemy: Dictionary[Unit, EnemyTrack] = {}

	for observer: Unit in p_friendly_units:
		if observer == null:
			continue

		var track_map: Dictionary = Globals.unit_enemy_tracks.get(observer, {})

		for enemy_variant: Variant in track_map.keys():
			var enemy: Unit = enemy_variant as Unit
			if enemy == null:
				continue

			var track: EnemyTrack = track_map.get(enemy, null) as EnemyTrack
			if track == null:
				continue

			if track.should_delete():
				continue

			if not best_tracks_by_enemy.has(enemy):
				best_tracks_by_enemy[enemy] = track
				continue

			var current_best: EnemyTrack = best_tracks_by_enemy[enemy]

			if _is_track_better_for_platoon(track, current_best):
				best_tracks_by_enemy[enemy] = track

	for enemy: Unit in best_tracks_by_enemy.keys():
		var best_track: EnemyTrack = best_tracks_by_enemy[enemy]
		enemy_tracks.append(best_track)


func _is_track_better_for_platoon(a: EnemyTrack, b: EnemyTrack) -> bool:
	if a.confidence > b.confidence:
		return true

	if a.confidence < b.confidence:
		return false

	if a.age_seconds < b.age_seconds:
		return true

	return false


func _find_enemy_track_for_enemy(p_enemy: Unit) -> EnemyTrack:
	for track: EnemyTrack in enemy_tracks:
		if track.enemy == p_enemy:
			return track

	return null


func register_incoming_fire_estimate(
	p_estimated_hex: Vector2i,
	p_confidence: float,
	p_danger: float
) -> void:
	_add_or_reinforce_suspected_zone(
		p_estimated_hex,
		p_confidence,
		p_danger,
		PlatoonTypes.ZoneReason.INCOMING_FIRE_DIRECTION,
		-1
	)



func mark_objective_observed_clear(p_confidence_gain: float) -> void:
	objective_observed_this_tick = true
	objective_clear_confidence += p_confidence_gain
	objective_clear_confidence = clampf(objective_clear_confidence, 0.0, 1.0)


func clear_phase_tasks() -> void:
	phase_tasks.clear()


func create_task(
	p_task_type: int,
	p_target_hex: Vector2i,
	p_required_role: int,
	p_priority: float
) -> PlatoonTask:
	var task: PlatoonTask = PlatoonTask.new()
	task.configure(
		next_task_id,
		p_task_type,
		p_target_hex,
		p_required_role,
		p_priority
	)

	next_task_id += 1
	phase_tasks.append(task)

	return task

func get_actionable_enemy_tracks() -> Array[EnemyTrack]:
	var result: Array[EnemyTrack] = []

	for track: EnemyTrack in enemy_tracks:
		if track.is_actionable(ACTIONABLE_ENEMY_CONFIDENCE):
			result.append(track)

	return result

func has_actionable_enemy_near_objective() -> bool:
	for track: EnemyTrack in enemy_tracks:
		if not track.is_actionable(ACTIONABLE_ENEMY_CONFIDENCE):
			continue

		var distance: int = LOSHelper.get_hex_distance(track.hex, objective_hex)
		if distance <= OBJECTIVE_NEAR_RADIUS:
			return true

	return false

func should_recon_objective() -> bool:
	if not has_objective:
		return false

	if objective_enemy_confidence >= ACTIONABLE_ENEMY_CONFIDENCE:
		return false

	if objective_clear_confidence >= 0.75:
		return false

	return true

func can_assault_objective() -> bool:
	if not has_objective:
		return false

	if objective_enemy_confidence < ASSAULT_REQUIRED_ENEMY_CONFIDENCE:
		return false

	if platoon_effective_strength < 0.45:
		return false

	if platoon_average_stress > 70.0:
		return false

	return true

func is_objective_probably_clear() -> bool:
	if objective_clear_confidence >= 0.75 and objective_enemy_confidence < 0.30:
		return true

	return false

func recalculate_platoon_values() -> void:
	var count: int = 0
	var total_effectiveness: float = 0.0
	var total_stress: float = 0.0
	var total_cohesion: float = 0.0

	for squad: Node in friendly_squads:
		var state: SquadTacticalState = get_squad_state(squad)

		if state == null:
			continue

		if state.morale_state == STATES.MoraleState.COMBAT_INEFFECTIVE:
			continue

		total_effectiveness += state.combat_effectiveness
		total_stress += state.stress_effective
		total_cohesion += state.cohesion
		count += 1

	if count <= 0:
		platoon_effective_strength = 0.0
		platoon_average_stress = 100.0
		platoon_average_cohesion = 0.0
		return

	platoon_effective_strength = total_effectiveness / float(count)
	platoon_average_stress = total_stress / float(count)
	platoon_average_cohesion = total_cohesion / float(count)

func recalculate_objective_beliefs(delta: float) -> void:
	var strongest_enemy_confidence: float = 0.0

	for track: EnemyTrack in enemy_tracks:
		var distance: int = LOSHelper.get_hex_distance(track.last_known_hex, objective_hex)
		
		if distance > OBJECTIVE_NEAR_RADIUS:
			continue
		
		if track.confidence > strongest_enemy_confidence:
			strongest_enemy_confidence = track.confidence
	
	objective_enemy_confidence = strongest_enemy_confidence

	if objective_enemy_confidence >= 0.30:
		objective_clear_confidence -= CLEAR_CONFIDENCE_LOSS_PER_SECOND * delta
	else:
		if objective_observed_this_tick:
			objective_clear_confidence += CLEAR_CONFIDENCE_GAIN_PER_SECOND * delta

	objective_clear_confidence = clampf(objective_clear_confidence, 0.0, 1.0)


func _find_enemy_track_near_hex(p_hex: Vector2i, p_radius: int) -> EnemyTrack:
	for track: EnemyTrack in enemy_tracks:
		var distance: int = LOSHelper.get_hex_distance(track.hex, p_hex)

		if distance <= p_radius:
			return track

	return null

func _find_suspected_zone_at_hex(p_hex: Vector2i) -> SuspectedEnemyZone:
	for zone: SuspectedEnemyZone in suspected_enemy_zones:
		if zone.hex == p_hex:
			return zone

	return null

func _add_or_reinforce_suspected_zone(
	p_hex: Vector2i,
	p_suspicion: float,
	p_danger: float,
	p_reason: int,
	p_source_track_id: int
) -> SuspectedEnemyZone:
	var existing_zone: SuspectedEnemyZone = _find_suspected_zone_at_hex(p_hex)

	if existing_zone != null:
		existing_zone.reinforce(p_suspicion, p_danger, current_time_seconds)
		return existing_zone

	var zone: SuspectedEnemyZone = SuspectedEnemyZone.new()
	zone.configure(
		next_zone_id,
		p_hex,
		p_suspicion,
		p_danger,
		p_reason,
		p_source_track_id,
		current_time_seconds
	)

	next_zone_id += 1
	suspected_enemy_zones.append(zone)

	return zone

func _decay_enemy_tracks(delta: float) -> void:
	var index: int = enemy_tracks.size() - 1

	while index >= 0:
		var track: EnemyTrack = enemy_tracks[index]
		track.decay(delta)

		if track.confidence <= 0.0:
			enemy_tracks.remove_at(index)

		index -= 1

func _decay_suspected_zones(delta: float) -> void:
	var index: int = suspected_enemy_zones.size() - 1

	while index >= 0:
		var zone: SuspectedEnemyZone = suspected_enemy_zones[index]
		zone.decay(delta)

		if zone.should_remove():
			suspected_enemy_zones.remove_at(index)

		index -= 1
