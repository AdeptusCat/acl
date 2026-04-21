extends Resource
class_name VictoryCondition

enum ConditionType {
	OCCUPY_OBJECTIVE,
	CLEAR_OBJECTIVE,
	EXIT_UNITS,
	DESTROY_UNITS,
	PRESERVE_FORCE,
	BREAK_ENEMY,
	DELAY_UNTIL_TIME
}

enum OutcomeLevel {
	MINOR,
	MAJOR
}


@export var team: Globals.Team = Globals.Team.AXIS
@export var outcome_level: OutcomeLevel = OutcomeLevel.MAJOR
@export var test_at_scenario_end: bool = false

#@export var objective_id: ObjetiveId = ObjetiveId.A
#@export var required_time_s: float = 3.0
#@export var required_unit_count: int = 1
#@export var condition_type: ConditionType = ConditionType.OCCUPY_OBJECTIVE


#func is_condition_met(_scenario_state: ScenarioState) -> bool:
	#push_error("VictoryCondition.is_condition_met() must be overridden.")
	#return false

var is_met: bool = false
var hex: Vector2i
var cube: Vector3i

var hexes: Array[Vector2i]
var required_times_reached_s: Dictionary[Vector2i, float]
var units_in_objectives: Dictionary[Vector2i, UnitsCollection]
var victory_conditions_met: Dictionary[Vector2i, bool]

var units_in_objective: UnitsCollection = UnitsCollection.new()
var axis_units_in_objective: Array[Unit]
var allies_units_in_objective: Array[Unit]
var time_occupied_s: float
