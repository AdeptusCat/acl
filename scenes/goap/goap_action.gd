# goap_action.gd
class_name GoapAction
extends Resource

var action_id: GoapTypes.FormationActionId = GoapTypes.FormationActionId.MOVE_TO_OBJECTIVE

# Parameterization (example)
var line_id: int = -1
var flank_side_left: bool = true
var axis_id: int = -1
var objective_id: int = -1

var base_cost: float = 1.0

func are_preconditions_met(state: FormationWorldState) -> bool:
	match action_id:
		GoapTypes.FormationActionId.MOVE_TO_OBJECTIVE:
			if state.has_enemy_contacts:
				return false
			if state.enemy_holds_objective:
				return false
			return true
		
		GoapTypes.FormationActionId.PREPARE_ASSAULT:
			if not state.has_enemy_contacts: 
				return false
			if state.objective_held:
				return false
			return true
		
		GoapTypes.FormationActionId.LAUNCH_ASSAULT:
			if not state.has_enemy_contacts:
				return false
			if not state.assault_plan_ready:
				return false
			if state.objective_held:
				return false
			return true
		_:
			return false

func apply_effects(input_state: FormationWorldState) -> FormationWorldState:
	var s: FormationWorldState = input_state.clone()

	match action_id:
		GoapTypes.FormationActionId.MOVE_TO_OBJECTIVE:
			s.objective_held = true
		
		GoapTypes.FormationActionId.PREPARE_ASSAULT:
			s.assault_plan_ready = true

		GoapTypes.FormationActionId.LAUNCH_ASSAULT:
			s.enemy_holds_objective = false
			s.objective_held = true
	
	return s


func get_cost(state: FormationWorldState) -> float:
	var cost: float = base_cost

	match action_id:
		GoapTypes.FormationActionId.MOVE_TO_OBJECTIVE:
			cost += 5.0
		GoapTypes.FormationActionId.PREPARE_ASSAULT:
			cost += 5.0
		GoapTypes.FormationActionId.LAUNCH_ASSAULT:
			cost += 5.0
	
	#if state.time_pressure_high:
		#if action_id == GoapTypes.FormationActionId.REST_AND_RESUPPLY:
			#cost += 2.0

	return cost
