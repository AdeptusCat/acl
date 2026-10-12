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
var reason: String = ""


func is_destination_goal() -> bool:
	return kind in [Kind.OCCUPY, Kind.EXIT]
