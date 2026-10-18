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
	return state != null and not state.exit_hexes.is_empty() and required_unit_count > 0 and state.units_exited.size() >= required_unit_count


func advance_time(delta: float) -> void:
	if state == null or delta <= 0.0:
		return
	state.record_units(team)


func record_unit_entry(unit: Unit, hex: Vector2i) -> void:
	if state != null:
		state.record_unit_entry(unit, team, hex)

func get_description() -> String:
	var plural_suffix: String = ""
	if required_unit_count > 1:
		plural_suffix = "s"
	
	var text: String = "Move at least {count} of your unit{plural_suffix} to 'Exit' Markers.".format({
	"plural_suffix": plural_suffix,
	"count": required_unit_count
	})
	return text
