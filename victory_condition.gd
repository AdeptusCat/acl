extends Resource
class_name VictoryCondition

enum ConditionType {
	OCCUPY_OBJECTIVE,
	CLEAR_OBJECTIVE,
	EXIT_UNITS,
	PRESERVE_FORCE,
	BREAK_ENEMY,
	DELAY_UNTIL_TIME
}

enum OutcomeLevel {
	MINOR,
	MAJOR
}

enum ObjetiveId {
	A,
	B,
	C
}

@export var team: Globals.Team = Globals.Team.AXIS
@export var condition_type: ConditionType = ConditionType.OCCUPY_OBJECTIVE
@export var outcome_level: OutcomeLevel = OutcomeLevel.MAJOR

@export var objective_id: ObjetiveId = ObjetiveId.A
@export var required_ratio: float = 1.0
@export var required_time_s: float = 3.0

@export var required_unit_count: int = 1
@export var required_effective_ratio: float = 0.0
@export var required_enemy_effective_ratio_below: float = -1.0
@export var required_time_reached_s: float = -1.0

var is_met: bool = false

var hexes: Array[Vector2i]
var required_times_reached_s: Dictionary[Vector2i, float]
var units_in_objectives: Dictionary[Vector2i, UnitsCollection]

var hex: Vector2i
var cube: Vector3i
var units_in_objective: UnitsCollection = UnitsCollection.new()
var axis_units_in_objective: Array[Unit]
var allies_units_in_objective: Array[Unit]
var time_occupied_s: float
