# goap_action.gd
class_name GoapAction
extends Resource

const GoapTypes = preload("res://scenes/goap/goap_types.gd")
const FormationWorldState = preload("res://scenes/goap/formation_world_state.gd")

var action_id: GoapTypes.FormationActionId = GoapTypes.FormationActionId.ESTABLISH_DEFENSE_LINE

# Parameterization (example)
var line_id: int = -1
var flank_side_left: bool = true
var axis_id: int = -1
var objective_id: int = -1

var base_cost: float = 1.0

func are_preconditions_met(state: FormationWorldState) -> bool:
	match action_id:
		GoapTypes.FormationActionId.MOVE_TO_OBJECTIVE:
			if state.path_blocked_by_enemy:
				return false
			if state.enemy_holds_objective:
				return false
			return true
		
		GoapTypes.FormationActionId.PREPARE_ASSAULT:
			if not state.path_blocked_by_enemy: 
				return false
			if not state.enemy_holds_objective: 
				return false
			return true
		
		GoapTypes.FormationActionId.LAUNCH_ASSAULT:
			if not state.assault_plan_ready:
				return false
			if not state.has_enemy_contacts:
				return false
			return true

		_:
			return false

func apply_effects(input_state: FormationWorldState) -> FormationWorldState:
	var s: FormationWorldState = input_state.clone()

	match action_id:
		GoapTypes.FormationActionId.MOVE_TO_OBJECTIVE:
			s.objective_reached = true
		
		GoapTypes.FormationActionId.PREPARE_ASSAULT:
			s.assault_plan_ready = true

		GoapTypes.FormationActionId.LAUNCH_ASSAULT:
			s.enemy_holds_objective = false
			s.path_blocked_by_enemy = false
			s.objective_reached = true
	
	return s


func get_cost(state: FormationWorldState) -> float:
	var cost: float = base_cost

	if action_id == GoapTypes.FormationActionId.LAUNCH_ASSAULT:
		cost += 5.0
	elif action_id == GoapTypes.FormationActionId.COMMIT_RESERVE:
		cost += 3.0
	elif action_id == GoapTypes.FormationActionId.WITHDRAW_TO_FALLBACK:
		cost += 2.0

	if state.time_pressure_high:
		if action_id == GoapTypes.FormationActionId.REST_AND_RESUPPLY:
			cost += 2.0

	return cost
