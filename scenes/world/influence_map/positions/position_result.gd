class_name PositionResult
extends RefCounted

enum Status { NO_SNAPSHOT, NO_CANDIDATE, ACCEPTED, RETAINED }
enum Decision { POSITION, HOLD_DEFENSE, WITHDRAW }

var status: Status = Status.NO_SNAPSHOT
var unit: Unit = null
var target_hex: Vector2i = Vector2i.ZERO
var target_index: int = -1
var proposed_hex: Vector2i = Vector2i.ZERO
var score: float = -INF
var previous_score: float = -INF
var should_move: bool = false
var score_map: PackedFloat32Array = PackedFloat32Array()
var eligibility: PackedByteArray = PackedByteArray()
var rejections: Dictionary[String, int] = {}
var features: Dictionary = {}
var alternatives: Array[PositionCandidate] = []
var path: Array[Vector2i] = []
var snapshot_version: int = 0
var context: String = ""
var profile_mode: PositionProfile.Mode = PositionProfile.Mode.DEFEND
var objective_hex: Vector2i = Vector2i.ZERO
var reason: String = ""
var decision: Decision = Decision.POSITION


func is_valid() -> bool:
	return is_instance_valid(unit) and unit.alive and target_index >= 0 and (status == Status.ACCEPTED or status == Status.RETAINED)
