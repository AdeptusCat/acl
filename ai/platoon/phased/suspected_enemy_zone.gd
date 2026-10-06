class_name SuspectedEnemyZone
extends RefCounted

var zone_id: int = -1

var hex: Vector2i = Vector2i.ZERO
var suspicion: float = 0.0
var danger: float = 0.0

var reason: int = PlatoonTypes.ZoneReason.OBJECTIVE
var source_track_id: int = -1

var age_seconds: float = 0.0
var last_update_time: float = 0.0

const DECAY_PER_SECOND: float = 0.0125
const REMOVE_THRESHOLD: float = 0.05

func configure(
	p_zone_id: int,
	p_hex: Vector2i,
	p_suspicion: float,
	p_danger: float,
	p_reason: int,
	p_source_track_id: int,
	p_time: float
) -> void:
	zone_id = p_zone_id
	hex = p_hex
	suspicion = clampf(p_suspicion, 0.0, 1.0)
	danger = clampf(p_danger, 0.0, 1.0)
	reason = p_reason
	source_track_id = p_source_track_id
	last_update_time = p_time
	age_seconds = 0.0

func reinforce(
	p_suspicion_gain: float,
	p_danger_gain: float,
	p_time: float
) -> void:
	suspicion += p_suspicion_gain
	danger += p_danger_gain

	suspicion = clampf(suspicion, 0.0, 1.0)
	danger = clampf(danger, 0.0, 1.0)

	last_update_time = p_time
	age_seconds = 0.0

func decay(delta: float) -> void:
	if reason == PlatoonTypes.ZoneReason.OBJECTIVE:
		return
	
	age_seconds += delta

	suspicion -= DECAY_PER_SECOND * delta
	danger -= DECAY_PER_SECOND * delta

	suspicion = clampf(suspicion, 0.0, 1.0)
	danger = clampf(danger, 0.0, 1.0)

func should_remove() -> bool:
	if reason == PlatoonTypes.ZoneReason.OBJECTIVE:
		return false
	
	if suspicion <= REMOVE_THRESHOLD and danger <= REMOVE_THRESHOLD:
		return true
	
	return false
