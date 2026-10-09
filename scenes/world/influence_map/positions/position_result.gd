class_name PositionResult
extends RefCounted

enum Status { NO_SNAPSHOT, NO_CANDIDATE, ACCEPTED, RETAINED }
enum Decision { POSITION, HOLD_DEFENSE, WITHDRAW }
enum CellState { UNEVALUATED, REJECTED, AVAILABLE, WAITING_HANDOFF }

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
var cell_states: PackedByteArray = PackedByteArray()
var rejection_reasons: PackedStringArray = PackedStringArray()
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
var approach_cells: Array[Vector2i] = []
var remembered_approach_cells: Array[Vector2i] = []
var inferred_approach_cells: Array[Vector2i] = []
var sector_priorities: Dictionary[int, float] = {}
var approach_evidence: Dictionary[int, String] = {}
var approach_sources: Dictionary[int, Vector2i] = {}
var branch_sources: Dictionary[String, Vector2i] = {}
var branch_evidence: Dictionary[String, String] = {}


func describe_cell(index: int) -> String:
	if index < 0 or index >= cell_states.size():
		return "No completed assessment for this hex"
	if cell_states[index] == CellState.AVAILABLE:
		return "Available position"
	if cell_states[index] == CellState.WAITING_HANDOFF:
		return "Useful position; waiting for another defender to establish covering fire"
	var descriptions: Dictionary[String, String] = {
		"terrain": "Impassable terrain", "geography": "Outside the assigned positioning area",
		"capacity": "Occupied or reserved by another unit", "cover": "Insufficient defensive cover",
		"responsibility": "Cannot protect the assigned objective or approach branch",
		"crossing_gap": "Cannot cover the threatened open crossing into objective-side cover",
		"objective_access": "No terrain route back to objective protection",
		"screen_gap": "Moving here would leave established approach coverage open",
		"withdrawal_direction": "Withdrawal would move closer to known enemies",
		"exposure_budget": "Route exceeds the allowed exposure budget", "risk": "Excessive incoming fire",
		"route": "No route within the movement risk limits", "firing": "No useful firing lane",
		"unit_unavailable": "This unit cannot execute the positioning order"
	}
	return descriptions.get(rejection_reasons[index], "Assessment pending")


func is_valid() -> bool:
	return is_instance_valid(unit) and unit.alive and target_index >= 0 and (status == Status.ACCEPTED or status == Status.RETAINED)
