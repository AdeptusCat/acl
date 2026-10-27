class_name EnemyTrack
extends RefCounted

var track_id: int = -1

var observer: Unit = null
var enemy: Unit = null

var last_known_hex: Vector2i = Vector2i.ZERO
var last_known_global_position: Vector2 = Vector2.ZERO

# Preserve the pre-contact attention for the first individual reactions.
var reaction_focus_direction: Vector2 = Vector2.ZERO
var acquired_at_s: float = -INF

const SEARCH_MEMORY_S: float = 8.0
const MAX_SEARCH_BONUS: float = 3.0
const TYPE_EVIDENCE_REQUIRED: float = 1.5
const STRENGTH_EVIDENCE_REQUIRED: float = 4.0
var search_remaining_s: float = 0.0
var identification_evidence: float = 0.0
var observed_squad_type: int = -1
var observed_type_name: String = ""
var estimated_strength_min: int = 0
var estimated_strength_max: int = 0

var confidence: float = 0.0
# Remembered contact survives loss of visual confidence and never grants live visibility.
var awareness: float = 0.0
var observed_strength: float = 0.0
var uncertainty_radius: int = 0

var source: int = PlatoonTypes.TrackSource.UNKNOWN

var age_seconds: float = 0.0
var last_update_time: float = 0.0

var is_confirmed: bool = false
var is_stale: bool = false

const CONFIRMED_CONFIDENCE: float = 0.70
const STALE_CONFIDENCE: float = 0.20
const DECAY_PER_SECOND: float = 0.025
const AWARENESS_DECAY_PER_SECOND: float = 1.0 / 30.0
const UNCERTAINTY_GROWTH_INTERVAL: float = 8.0


func _init(p_observer: Unit = null, p_enemy: Unit = null) -> void:
	observer = p_observer
	enemy = p_enemy

	if enemy != null:
		last_known_global_position = enemy.global_position
		last_known_hex = enemy.current_hex


func initialize_track(
	p_track_id: int,
	p_confidence: float,
	p_observed_strength: float,
	p_source: int,
	p_time: float
) -> void:
	track_id = p_track_id
	confidence = clampf(p_confidence, 0.0, 1.0)
	observed_strength = clampf(p_observed_strength, 0.0, 1.0)
	source = p_source
	last_update_time = p_time
	age_seconds = 0.0
	uncertainty_radius = 0

	if enemy != null:
		last_known_global_position = enemy.global_position
		last_known_hex = enemy.current_hex

	_update_flags()


func update_from_enemy_observation(
	p_observer: Unit,
	p_enemy: Unit,
	p_confidence_gain: float,
	p_observed_strength: float,
	p_source: int,
	p_time: float
) -> void:
	observer = p_observer
	enemy = p_enemy

	if enemy != null:
		last_known_global_position = enemy.global_position
		last_known_hex = enemy.current_hex

	confidence += p_confidence_gain
	confidence = clampf(confidence, 0.0, 1.0)

	if p_observed_strength > observed_strength:
		observed_strength = p_observed_strength

	source = p_source
	last_update_time = p_time
	age_seconds = 0.0
	uncertainty_radius = 0

	_update_flags()


func decay(delta: float) -> void:
	age_seconds += delta

	confidence -= DECAY_PER_SECOND * delta
	confidence = clampf(confidence, 0.0, 1.0)

	if age_seconds >= UNCERTAINTY_GROWTH_INTERVAL:
		uncertainty_radius = int(age_seconds / UNCERTAINTY_GROWTH_INTERVAL)

	_update_flags()


func is_actionable(required_confidence: float) -> bool:
	if confidence >= required_confidence:
		return true

	return false


func _update_flags() -> void:
	if confidence >= CONFIRMED_CONFIDENCE:
		is_confirmed = true
	else:
		is_confirmed = false

	if confidence <= STALE_CONFIDENCE:
		is_stale = true
	else:
		is_stale = false



const LOCK_REQUIRED_LOS_TIME_S: float = 0.75
const VISIBLE_CONF_THRESHOLD: float = 0.55
const VISUAL_CONTACT_GRACE_S: float = 5.0
const TRACKING_RATE_MULTIPLIER: float = 10.0

var los_time_s: float = 0.0
var last_seen_unix_s: float = 0.0

var currently_in_los: bool = false
var is_visible: bool = false
var has_confirmed_lock: bool = false
var visual_contact_remaining_s: float = VISUAL_CONTACT_GRACE_S



func update_seen(delta: float, now_unix: float) -> void:
	currently_in_los = true
	los_time_s += delta
	last_seen_unix_s = now_unix

	if is_visible:
		record_detection()
	else:
		_decay_awareness(delta)
		search_remaining_s = maxf(0.0, search_remaining_s - maxf(delta, 0.0))

	if los_time_s >= LOCK_REQUIRED_LOS_TIME_S:
		has_confirmed_lock = true
	else:
		has_confirmed_lock = false


func update_not_seen(delta: float) -> void:
	currently_in_los = false
	los_time_s = 0.0
	has_confirmed_lock = false
	is_visible = false
	visual_contact_remaining_s = 0.0
	search_remaining_s = maxf(0.0, search_remaining_s - maxf(delta, 0.0))
	_decay_awareness(delta)

	confidence -= 0.10 * delta
	if confidence < 0.0:
		confidence = 0.0

	_update_flags()


func acquire_detection() -> void:
	visual_contact_remaining_s = VISUAL_CONTACT_GRACE_S
	record_detection()


func maintain_detection(acquisition_rate: float, delta: float) -> bool:
	# Knowing where to look makes tracking easier, but geometric LOS alone cannot
	# maintain a distant concealed silhouette. Brief lulls retain a stable contact.
	var replenishment: float = maxf(acquisition_rate, 0.0) * TRACKING_RATE_MULTIPLIER
	visual_contact_remaining_s = clampf(visual_contact_remaining_s + maxf(delta, 0.0) * (replenishment - 1.0), 0.0, VISUAL_CONTACT_GRACE_S)
	if visual_contact_remaining_s <= 0.0:
		is_visible = false
	return is_visible


func record_detection() -> void:
	if not is_instance_valid(enemy):
		return
	is_visible = true
	awareness = 1.0
	search_remaining_s = SEARCH_MEMORY_S
	last_known_global_position = enemy.global_position
	last_known_hex = enemy.current_hex
	_update_flags()


func reacquisition_multiplier(candidate_hex: Vector2i) -> float:
	if is_visible or search_remaining_s <= 0.0 or awareness <= 0.0 or not is_instance_valid(LOSHelper.ground_layer):
		return 1.0
	var offset: int = LOSHelper.get_hex_distance(last_known_hex, candidate_hex)
	if offset > 1:
		return 1.0
	var proximity: float = 1.0 / float(offset + 1)
	return 1.0 + (MAX_SEARCH_BONUS - 1.0) * proximity * clampf(search_remaining_s / SEARCH_MEMORY_S, 0.0, 1.0)


func observe_details(rate: float, delta: float) -> void:
	if not is_visible or not is_instance_valid(enemy):
		return
	identification_evidence = minf(STRENGTH_EVIDENCE_REQUIRED, identification_evidence + maxf(delta, 0.0) * clampf(sqrt(maxf(rate, 0.0)) * 0.5, 0.0, 0.5))
	if identification_evidence >= TYPE_EVIDENCE_REQUIRED:
		observed_squad_type = enemy.squad_type
		observed_type_name = enemy.get_squad_type_name(enemy.squad_type)
	if identification_evidence >= STRENGTH_EVIDENCE_REQUIRED:
		estimated_strength_max = maxi(4, ceili(float(enemy.members_alive) / 4.0) * 4)
		estimated_strength_min = estimated_strength_max - 3


func contact_report() -> Dictionary:
	var title: String = "Unidentified contact"
	var status: String = "Brief sighting"
	var strength: String = "Strength unknown"
	if observed_squad_type >= 0:
		title = observed_type_name
		status = "Type identified"
	if estimated_strength_max > 0:
		strength = "Estimated %d–%d soldiers" % [estimated_strength_min, estimated_strength_max]
		status = "Strength estimated"
	return {"title": title, "status": status, "strength": strength, "squad_type": observed_squad_type,
		"strength_min": estimated_strength_min, "strength_max": estimated_strength_max, "evidence": identification_evidence}


func _decay_awareness(delta: float) -> void:
	awareness = maxf(awareness - AWARENESS_DECAY_PER_SECOND * maxf(delta, 0.0), 0.0)


func should_delete() -> bool:
	if currently_in_los:
		return false

	if confidence > 0.0 or awareness > 0.0:
		return false

	return true
