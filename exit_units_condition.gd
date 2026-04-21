extends VictoryCondition
class_name ExitUnitsCondition

enum ObjectiveId {
	EXIT,
	A,
	B,
	C
}

@export var exit_zone_id: ObjectiveId = ObjectiveId.EXIT
@export var required_unit_count: int = 1

var units_exited: int = 0
