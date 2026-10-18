class_name EnemyTrack
extends RefCounted

var track_id: int = -1

var observer: Unit = null
var enemy: Unit = null

var last_known_hex: Vector2i = Vector2i.ZERO
var last_known_global_position: Vector2 = Vector2.ZERO

var confidence: float = 0.0
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

var los_time_s: float = 0.0
var last_seen_unix_s: float = 0.0

var currently_in_los: bool = false
var is_visible: bool = false
var has_confirmed_lock: bool = false



func update_seen(delta: float, now_unix: float) -> void:
	currently_in_los = true
	los_time_s += delta
	last_seen_unix_s = now_unix

	if enemy != null:
		last_known_global_position = enemy.global_position

	if los_time_s >= LOCK_REQUIRED_LOS_TIME_S:
		has_confirmed_lock = true
	else:
		has_confirmed_lock = false


func update_not_seen(delta: float) -> void:
	currently_in_los = false
	los_time_s = 0.0
	has_confirmed_lock = false

	confidence -= 0.10 * delta
	if confidence < 0.0:
		confidence = 0.0

	if confidence < VISIBLE_CONF_THRESHOLD:
		is_visible = false


func should_delete() -> bool:
	if currently_in_los:
		return false

	if confidence > 0.0:
		return false

	return true
