extends VictoryCondition
class_name PreventEnemyExitCondition

enum ObjectiveId { EXIT, A, B, C }

## Selects markers belonging to the opponent of Team, not Team's own markers.
@export var objective_id: ObjectiveId = ObjectiveId.EXIT
## Zero means no enemy squad may exit. Recorded exits cannot be undone.
@export_range(0, 128, 1, "or_greater") var max_allowed_enemy_exits: int = 0

var state: ExitUnitsState

const OBJECTIVE_NAMES: Dictionary[ObjectiveId, String] = {
	ObjectiveId.EXIT: "Exit",
	ObjectiveId.A: "A",
	ObjectiveId.B: "B",
	ObjectiveId.C: "C",
}


func _init() -> void:
	# Preventing escape is an ongoing duty, so an initially empty exit ledger
	# must not award victory at the beginning of the scenario.
	test_at_scenario_end = true


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
	var marker: String = OBJECTIVE_NAMES[objective_id]
	if max_allowed_enemy_exits == 0:
		return "Prevent any enemy unit from reaching the enemy '%s' markers." % marker
	return "Allow no more than %d enemy units to reach the enemy '%s' markers." % [max_allowed_enemy_exits, marker]
