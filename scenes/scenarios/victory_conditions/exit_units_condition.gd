extends VictoryCondition
class_name ExitUnitsCondition

enum ObjectiveId {
	EXIT,
	A,
	B,
	C
}

@export var objective_id: ObjectiveId = ObjectiveId.EXIT
@export var required_unit_count: int = 1

var state: ExitUnitsState

func is_condition_met() -> bool:
	var is_met: bool = false
	
	for unit in Globals.get_units():
		for hex in state.exit_hexes:
			if hex == unit.current_hex:
				if unit.team == team:
					if not state.units_exited.has(unit):
						state.units_exited.append(unit)
	
	if state.units_exited.size() >= required_unit_count:
		is_met = true
	return is_met

func get_description() -> String:
	var plural_suffix: String = ""
	if required_unit_count > 1:
		plural_suffix = "s"
	
	var text: String = "Move at least {count} of your unit{plural_suffix} to 'Exit' Markers.".format({
	"plural_suffix": plural_suffix,
	"count": required_unit_count
	})
	return text
