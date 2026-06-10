class_name MissionOrder
extends RefCounted

enum MissionType {
	HOLD,
	DELAY,
	SCREEN,
	RESERVE,
	BLOCK,
	SUPPORT_BY_FIRE,
}

enum ReservePolicy {
	NONE,
	KEEP_ONE_SQUAD_IF_POSSIBLE,
	KEEP_HQ_NEAR_OBJECTIVE,
}

var mission_type: MissionType = MissionType.HOLD
var objective_hex: Vector2i = Vector2i.ZERO
var sector_cells: Array[Vector2i] = []
var fallback_hexes: Array[Vector2i] = []
var threat_axes: Array[ThreatAxis] = []
var reserve_policy: ReservePolicy = ReservePolicy.KEEP_ONE_SQUAD_IF_POSSIBLE
