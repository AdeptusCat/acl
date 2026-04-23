extends VictoryCondition
class_name DestroyUnitsCondition

@export var required_unit_count: int = 1
var state: DestroyUnitsState

func is_condition_met() -> bool:
	if Globals.units_destroyed.units_collection[team].units.size() >= required_unit_count:
		return true
	return false

func get_description() -> String:
	var plural_suffix: String = ""
	if required_unit_count > 1:
		plural_suffix = "s"
	
	var text: String = "Destroy at least {count} enemy unit{plural_suffix}.".format({
	"plural_suffix": plural_suffix,
	"count": required_unit_count
	})
	return text
