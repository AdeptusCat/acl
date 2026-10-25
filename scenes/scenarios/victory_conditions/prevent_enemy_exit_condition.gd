@tool
extends VictoryCondition
class_name PreventEnemyExitCondition

enum ObjectiveId { EXIT, A, B, C }

## Selects markers belonging to the opponent of Team, not Team's own markers.
@export var objective_id: ObjectiveId = ObjectiveId.EXIT
## Zero means no enemy squad may exit. Recorded exits cannot be undone.
@export_range(0, 128, 1, "or_greater") var max_allowed_enemy_exits: int = 0

# The inherited export's static default is false. Preserve an explicit OFF
# through a hidden override, since ResourceSaver otherwise omits that value.
@export_storage var _test_at_scenario_end_override: bool = true:
	get:
		return test_at_scenario_end
	set(value):
		test_at_scenario_end = value

var state: ExitUnitsState

const OBJECTIVE_NAMES: Dictionary[ObjectiveId, String] = {
	ObjectiveId.EXIT: "Exit",
	ObjectiveId.A: "A",
	ObjectiveId.B: "B",
	ObjectiveId.C: "C",
}


func _init() -> void:
	# Preventing escape is an ongoing duty, so an initially empty exit ledger
	# must not award victory at the beginning of the scenario. Tool mode also
	# applies this inherited-property default to resources made in the Inspector.
	test_at_scenario_end = true


func _property_can_revert(property: StringName) -> bool:
	return property == &"test_at_scenario_end"


func _property_get_revert(property: StringName) -> Variant:
	if property == &"test_at_scenario_end":
		return true
	return null


func is_condition_met() -> bool:
	return state != null and not state.exit_hexes.is_empty() and max_allowed_enemy_exits >= 0 and state.units_exited.size() <= max_allowed_enemy_exits


func advance_time(delta: float) -> void:
	if state == null or delta <= 0.0:
		return
	state.record_units(Globals.get_enemy_team(team))


func record_unit_entry(unit: Unit, hex: Vector2i) -> void:
	if state != null:
		state.record_unit_entry(unit, Globals.get_enemy_team(team), hex)


func get_description() -> String:
	var text: String = "Stop enemy exits"
	if max_allowed_enemy_exits > 0:
		var exits: String = "exits"
		if max_allowed_enemy_exits == 1:
			exits = "exit"
		text = "Allow no more than %d enemy %s" % [max_allowed_enemy_exits, exits]
	if objective_id != ObjectiveId.EXIT:
		text += " at Objective " + OBJECTIVE_NAMES[objective_id]
	return text


func get_details() -> String:
	var marker: String = OBJECTIVE_NAMES[objective_id]
	if max_allowed_enemy_exits == 0:
		return _with_timing("Prevent any enemy unit from reaching the enemy '%s' markers." % marker)
	return _with_timing("Allow no more than %d enemy units to reach the enemy '%s' markers." % [max_allowed_enemy_exits, marker])
