extends VictoryCondition
class_name OccupyObjectiveCondition

enum ObjectiveId {
	EXIT,
	A,
	B,
	C
}

@export var objective_id: ObjectiveId = ObjectiveId.A
@export var required_time_s: float = 3.0
@export var required_unit_count: int = 1
@export var contested_by_enemy_presence: bool = true

#func is_condition_met(scenario_state: ScenarioState) -> bool:
	#return scenario_state.is_objective_occupied_for_time(
		#team,
		#objective_id,
		#required_control_ratio,
		#required_time_s,
		#required_unit_count,
		#contested_by_enemy_presence
	#)
