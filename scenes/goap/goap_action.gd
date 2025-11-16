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
		GoapTypes.FormationActionId.ESTABLISH_DEFENSE_LINE:
			if state.mission_mode != GoapTypes.FormationMissionMode.DEFEND:
				return false
			if state.friendly_E_level == GoapTypes.WorldELevel.LOW:
				return false
			return true

		GoapTypes.FormationActionId.ASSIGN_BASE_OF_FIRE:
			if not state.line_established:
				return false
			if not state.has_enemy_contacts:
				return false
			return true

		GoapTypes.FormationActionId.COVER_FLANK:
			if not state.line_established:
				return false
			if not state.reserve_present:
				return false
			return true

		GoapTypes.FormationActionId.WITHDRAW_TO_FALLBACK:
			if not state.fallback_line_available:
				return false
			if state.objective_held == false:
				return false
			return true

		GoapTypes.FormationActionId.REORGANIZE_AND_MERGE:
			return true

		GoapTypes.FormationActionId.PROBE_AXIS:
			if state.mission_mode == GoapTypes.FormationMissionMode.DEFEND:
				return false
			return true

		GoapTypes.FormationActionId.PREPARE_ASSAULT:
			if state.mission_mode != GoapTypes.FormationMissionMode.ATTACK:
				return false
			if state.has_enemy_contacts: 
				if not state.base_of_fire_established:
					return false
			return true

		GoapTypes.FormationActionId.LAUNCH_ASSAULT:
			if state.mission_mode != GoapTypes.FormationMissionMode.ATTACK:
				return false
			if not state.assault_element_ready:
				return false
			if state.enemy_E_on_main_axis == GoapTypes.WorldELevel.HIGH:
				return false
			return true

		GoapTypes.FormationActionId.SHIFT_AXIS:
			if state.enemy_E_on_main_axis != GoapTypes.WorldELevel.HIGH:
				return false
			return true

		GoapTypes.FormationActionId.COMMIT_RESERVE:
			if not state.reserve_present:
				return false
			return true

		GoapTypes.FormationActionId.ROTATE_SQUADS_IN_LINE:
			if not state.line_established:
				return false
			return true

		GoapTypes.FormationActionId.REST_AND_RESUPPLY:
			return true

		_:
			return false

func apply_effects(input_state: FormationWorldState) -> FormationWorldState:
	var s: FormationWorldState = input_state.clone()

	match action_id:
		GoapTypes.FormationActionId.ESTABLISH_DEFENSE_LINE:
			s.line_established = true
			s.left_flank_exposed = false
			s.right_flank_exposed = false

		GoapTypes.FormationActionId.ASSIGN_BASE_OF_FIRE:
			s.base_of_fire_established = true

		GoapTypes.FormationActionId.COVER_FLANK:
			if flank_side_left:
				s.left_flank_exposed = false
			else:
				s.right_flank_exposed = false

		GoapTypes.FormationActionId.WITHDRAW_TO_FALLBACK:
			s.line_established = true

		GoapTypes.FormationActionId.REORGANIZE_AND_MERGE:
			if s.friendly_E_level == GoapTypes.WorldELevel.LOW:
				s.friendly_E_level = GoapTypes.WorldELevel.MED
			s.reserve_present = true

		GoapTypes.FormationActionId.PROBE_AXIS:
			s.contact_uncertain = false
			s.probe_result = GoapTypes.WorldProbeResult.CLEAR

		GoapTypes.FormationActionId.PREPARE_ASSAULT:
			s.assault_element_ready = true

		GoapTypes.FormationActionId.LAUNCH_ASSAULT:
			s.objective_clear = true
			s.objective_held = true
			s.enemy_E_on_main_axis = GoapTypes.WorldELevel.MED

		GoapTypes.FormationActionId.SHIFT_AXIS:
			s.enemy_E_on_main_axis = GoapTypes.WorldELevel.MED

		GoapTypes.FormationActionId.COMMIT_RESERVE:
			s.reserve_present = false
			if s.enemy_E_on_main_axis == GoapTypes.WorldELevel.HIGH:
				s.enemy_E_on_main_axis = GoapTypes.WorldELevel.MED

		GoapTypes.FormationActionId.ROTATE_SQUADS_IN_LINE:
			if s.friendly_E_level == GoapTypes.WorldELevel.LOW:
				s.friendly_E_level = GoapTypes.WorldELevel.MED

		GoapTypes.FormationActionId.REST_AND_RESUPPLY:
			if s.ammo_state_global == GoapTypes.WorldAmmoLevel.CRITICAL:
				s.ammo_state_global = GoapTypes.WorldAmmoLevel.LOW
			elif s.ammo_state_global == GoapTypes.WorldAmmoLevel.LOW:
				s.ammo_state_global = GoapTypes.WorldAmmoLevel.OK
			if s.friendly_E_level == GoapTypes.WorldELevel.LOW:
				s.friendly_E_level = GoapTypes.WorldELevel.MED

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
