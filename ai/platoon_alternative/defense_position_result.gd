class_name DefensePositionResult
extends RefCounted

var unit: Unit = null
var axis: ThreatAxis = null
var role: String = ""
var target_hex: Vector2i = Vector2i.ZERO
var target_index: int = -1
var score: float = -INF
var previous_score: float = -INF
var should_move: bool = false
var score_map: PackedFloat32Array = PackedFloat32Array()


func is_valid() -> bool:
	if unit == null:
		return false

	if target_index < 0:
		return false

	return true
