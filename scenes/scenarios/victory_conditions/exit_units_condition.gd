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

const OBJECTIVE_NAMES: Array[String] = ["Exit", "A", "B", "C"]

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
	var squads: String = "squads"
	if required_unit_count == 1:
		squads = "squad"
	var text: String = "Exit with %d %s" % [required_unit_count, squads]
	if objective_id != ObjectiveId.EXIT:
		text += " at Objective " + OBJECTIVE_NAMES[objective_id]
	return text


func get_details() -> String:
	var marker: String = OBJECTIVE_NAMES[objective_id]
	return _with_timing("Move at least %d squads to the '%s' exit markers." % [required_unit_count, marker])
