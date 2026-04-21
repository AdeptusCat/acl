extends VictoryCondition
class_name DestroyUnitsCondition

@export var required_unit_count: int = 1
var state: DestroyUnitsState

func is_condition_met() -> bool:
	if Globals.units_destroyed.units_collection[team].units.size() >= required_unit_count:
		return true
	return false
