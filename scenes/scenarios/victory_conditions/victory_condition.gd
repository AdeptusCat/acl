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


var units_in_objective: UnitsCollection = UnitsCollection.new()
var axis_units_in_objective: Array[Unit]
var allies_units_in_objective: Array[Unit]
var time_occupied_s: float



func is_condition_met() -> bool:
	push_error("VictoryCondition.evaluate() must be overridden.")
	return false


func get_description() -> String:
	push_error("VictoryCondition.evaluate() must be overridden.")
	return ""
