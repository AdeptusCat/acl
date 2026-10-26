extends VictoryCondition
class_name OccupyObjectiveCondition

enum ObjectiveId {
	EXIT,
	A,
	B,
	C
}

enum InitialControl { NEUTRAL, FRIENDLY, ENEMY }

@export var objective_id: ObjectiveId = ObjectiveId.A
## Starting ownership of this capture objective, relative to the selected player faction.
## Friendly objectives begin fully captured; neutral objectives have no owner.
@export var initial_control: InitialControl = InitialControl.ENEMY
@export var required_time_s: float = 3.0
@export var required_unit_count: int = 1
@export var contested_by_enemy_presence: bool = true

var state: OccupyObjectiveState

const OBJECTIVE_NAMES: Dictionary[ObjectiveId, String] = {
	ObjectiveId.EXIT: "Exit",
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


func get_initial_owner(selected_player_team: Globals.Team) -> int:
	match initial_control:
		InitialControl.FRIENDLY:
			return selected_player_team
		InitialControl.ENEMY:
			return Globals.get_enemy_team(selected_player_team)
	return -1


func get_description() -> String:
	return "Capture Objective " + OBJECTIVE_NAMES[objective_id]


func get_details() -> String:
	var text: String = "Capture every '%s' hex with at least %d good-order squad(s) for %.0f continuous seconds. Control remains until the enemy recaptures it." % [OBJECTIVE_NAMES[objective_id], required_unit_count, required_time_s]
	return _with_timing(text)


func is_condition_met() -> bool:
	if state == null or state.hexes.is_empty() or required_unit_count <= 0 or required_time_s < 0.0:
		return false
	for hex: Vector2i in state.hexes:
		if not state.victory_conditions_met.get(hex, false):
			return false
	return true


func advance_time(delta: float) -> void:
	if delta <= 0.0:
		return
	_update_control(delta)


func refresh_control() -> void:
	# Refresh presence without advancing either side's capture timer.
	_update_control(0.0)


func complete_after_enemy_defeat(capture_all: bool = false) -> void:
	refresh_control()
	if state == null or required_unit_count <= 0 or required_time_s < 0.0:
		return
	for hex: Vector2i in state.hexes:
		var held_seconds: float = state.required_times_reached_s.get(hex, 0.0)
		# Before the deadline, eliminating the enemy secures even unoccupied objectives.
		if capture_all or held_seconds > 0.0:
			state.required_times_reached_s[hex] = maxf(held_seconds, required_time_s)
			state.victory_conditions_met[hex] = true
			state.controlling_teams[hex] = team


func _update_control(delta: float) -> void:
	if state == null:
		return
	for hex: Vector2i in state.hexes:
		state.units_in_objectives[hex].units_collection[Globals.Team.AXIS].units.clear()
		state.units_in_objectives[hex].units_collection[Globals.Team.ALLIES].units.clear()
	
	var enemy_team: Globals.Team
	if team == Globals.Team.AXIS:
		enemy_team = Globals.Team.ALLIES
	else:
		enemy_team = Globals.Team.AXIS
	
	for unit: Unit in Globals.get_units():
		for hex: Vector2i in state.hexes:
			if hex == unit.current_hex:
				if unit.team == Globals.Team.AXIS:
					if unit.is_good_order():
						state.units_in_objectives[hex].units_collection[Globals.Team.AXIS].units.append(unit)
				elif unit.team == Globals.Team.ALLIES:
					if unit.is_good_order():
						state.units_in_objectives[hex].units_collection[Globals.Team.ALLIES].units.append(unit)
	
	for hex: Vector2i in state.hexes:
		var friendly_units: Array[Unit] = state.units_in_objectives[hex].units_collection[team].units
		var enemy_units: Array[Unit] = state.units_in_objectives[hex].units_collection[enemy_team].units

		var objective_held: bool = false
		if not friendly_units.is_empty() and (not contested_by_enemy_presence or enemy_units.is_empty()):
			if friendly_units.size() >= required_unit_count:
				objective_held = true

		var enemy_held: bool = enemy_units.size() >= required_unit_count and friendly_units.is_empty()
		if objective_held:
			state.required_times_reached_s[hex] += delta
		elif not state.victory_conditions_met.get(hex, false):
			state.required_times_reached_s[hex] = 0.0

		if enemy_held:
			state.enemy_hold_times_s[hex] = state.enemy_hold_times_s.get(hex, 0.0) + delta
		else:
			state.enemy_hold_times_s[hex] = 0.0

		if objective_held and state.required_times_reached_s[hex] >= required_time_s:
			state.victory_conditions_met[hex] = true
			state.controlling_teams[hex] = team
		elif enemy_held and state.enemy_hold_times_s[hex] >= required_time_s:
			state.victory_conditions_met[hex] = false
			state.controlling_teams[hex] = enemy_team
			state.required_times_reached_s[hex] = 0.0
