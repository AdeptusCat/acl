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

var state: OccupyObjectiveState

const OBJECTIVE_NAMES := {
	ObjectiveId.A: "A",
	ObjectiveId.B: "B",
	ObjectiveId.C: "C",
}

#func is_condition_met(scenario_state: ScenarioState) -> bool:
	#return scenario_state.is_objective_occupied_for_time(
		#team,
		#objective_id,
		#required_control_ratio,
		#required_time_s,
		#required_unit_count,
		#contested_by_enemy_presence
	#)


func get_description() -> String:
	var text: String = "Occupy the Hex(es) marked '{objective}' with your units.".format({
	"objective": OBJECTIVE_NAMES[objective_id]
	})
	
	#var plural_suffix: String = ""
	#if hexes.size() > 1:
		#plural_suffix = "es"
	#var text: String = "Occupy the Hex{plural_suffix} marked '{objective}' with your units.".format({
	#"plural_suffix": plural_suffix,
	#"objective": OBJECTIVE_NAMES[objective_id]
	#})
	
	return text


func is_condition_met() -> bool:
	var is_met: bool = true
	
	for hex in state.hexes:
		state.units_in_objectives[hex].units_collection[Globals.Team.AXIS].units.clear()
		state.units_in_objectives[hex].units_collection[Globals.Team.ALLIES].units.clear()
	
	var enemy_team: Globals.Team
	if team == Globals.Team.AXIS:
		enemy_team = Globals.Team.ALLIES
	else:
		enemy_team = Globals.Team.AXIS
	
	for unit in Globals.get_units():
		for hex in state.hexes:
			if hex == unit.current_hex:
				if unit.team == Globals.Team.AXIS:
					if unit.is_good_order():
						state.units_in_objectives[hex].units_collection[Globals.Team.AXIS].units.append(unit)
				elif unit.team == Globals.Team.ALLIES:
					if unit.is_good_order():
						state.units_in_objectives[hex].units_collection[Globals.Team.ALLIES].units.append(unit)
	
	for hex in state.hexes:
		var friendly_units: Array[Unit] = state.units_in_objectives[hex].units_collection[team].units
		var enemy_units: Array[Unit] = state.units_in_objectives[hex].units_collection[enemy_team].units

		var objective_held: bool = false
		if not friendly_units.is_empty() and enemy_units.is_empty():
			if friendly_units.size() >= required_unit_count:
				objective_held = true

		
		if objective_held:
			state.required_times_reached_s[hex] += 1
		else:
			state.required_times_reached_s[hex] = 0

		if state.required_times_reached_s[hex] >= required_time_s:
			state.victory_conditions_met[hex] = true
		else:
			state.victory_conditions_met[hex] = false
	
	for hex in state.victory_conditions_met:
		if not state.victory_conditions_met[hex]:
			is_met = false
	return is_met
