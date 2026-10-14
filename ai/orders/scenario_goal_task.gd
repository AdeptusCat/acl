class_name ScenarioGoalTask
extends RefCounted

enum Kind { OCCUPY, EXIT, DENY_OCCUPATION, BLOCK_EXIT, HUNT, PRESERVE }

var kind: Kind
var key: String
var condition: VictoryCondition
var hex: Vector2i
var required_units: int = 1
var priority: float = 0.0
var urgent: bool = false
var withdrawal: bool = false
var breach_required: bool = false
var breach_hex: Vector2i
var reason: String = ""


func is_destination_goal() -> bool:
	return kind in [Kind.OCCUPY, Kind.EXIT]


static func exit_state_for(source: VictoryCondition) -> ExitUnitsState:
	if source is ExitUnitsCondition:
		return (source as ExitUnitsCondition).state
	if source is PreventEnemyExitCondition:
		return (source as PreventEnemyExitCondition).state
	return null


func exit_capacity() -> int:
	if withdrawal:
		return maxi(required_units, (condition as ExitUnitsCondition).required_unit_count)
	if condition is ExitUnitsCondition:
		return (condition as ExitUnitsCondition).required_unit_count
	if condition is PreventEnemyExitCondition:
		return (condition as PreventEnemyExitCondition).max_allowed_enemy_exits + 1
	return 1
