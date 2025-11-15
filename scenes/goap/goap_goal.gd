# goap_goal.gd
class_name GoapGoal
extends Resource

const GoapTypes = preload("res://scenes/goap/goap_types.gd")
const FormationWorldState = preload("res://scenes/goap/formation_world_state.gd")

var goal_id: GoapTypes.FormationGoalId = GoapTypes.FormationGoalId.MAINTAIN_DEFENSE
var base_priority: float = 1.0

func is_satisfied(state: FormationWorldState) -> bool:
	match goal_id:
		GoapTypes.FormationGoalId.MAINTAIN_DEFENSE:
			if state.objective_held and state.line_established:
				if state.friendly_E_level != GoapTypes.WorldELevel.LOW:
					if not state.left_flank_exposed and not state.right_flank_exposed:
						return true
			return false

		GoapTypes.FormationGoalId.CAPTURE_OBJECTIVE:
			if state.objective_held and state.objective_clear:
				if state.enemy_E_on_main_axis != GoapTypes.WorldELevel.HIGH:
					return true
			return false

		GoapTypes.FormationGoalId.DELAY_ENEMY:
			if state.friendly_E_level != GoapTypes.WorldELevel.LOW:
				return true
			return false

		GoapTypes.FormationGoalId.GAIN_INFORMATION:
			if not state.contact_uncertain:
				return true
			return false

		GoapTypes.FormationGoalId.IMPROVE_SITUATION:
			if state.friendly_E_level != GoapTypes.WorldELevel.LOW:
				if state.ammo_state_global != GoapTypes.WorldAmmoLevel.CRITICAL:
					if state.reserve_present:
						return true
			return false

		_:
			return false

func compute_dynamic_priority(state: FormationWorldState) -> float:
	var priority: float = base_priority

	if goal_id == GoapTypes.FormationGoalId.MAINTAIN_DEFENSE:
		# Only meaningful if there is an objective at all
		if state.objective_held:
			# We already hold it -> keep it
			priority += 4.0
		else:
			# We do NOT hold it -> maintaining defense around nothing
			# should be low priority compared to capturing
			priority -= 2.0

		if state.left_flank_exposed or state.right_flank_exposed:
			priority += 2.0

		# DEFEND mission bias
		if state.mission_mode == GoapTypes.FormationMissionMode.DEFEND:
			priority += 1.0

	elif goal_id == GoapTypes.FormationGoalId.CAPTURE_OBJECTIVE:
		# If the objective is not held, attacking it becomes important
		if not state.objective_held:
			priority += 6.0
		else:
			# Already held -> do not waste effort on "capture"
			priority -= 3.0

		if state.time_pressure_high:
			priority += 2.0

		# ATTACK mission bias
		if state.mission_mode == GoapTypes.FormationMissionMode.ATTACK:
			priority += 1.0

	elif goal_id == GoapTypes.FormationGoalId.DELAY_ENEMY:
		if state.time_pressure_high:
			priority += 3.0

	elif goal_id == GoapTypes.FormationGoalId.GAIN_INFORMATION:
		if state.contact_uncertain:
			priority += 2.0

	elif goal_id == GoapTypes.FormationGoalId.IMPROVE_SITUATION:
		if state.friendly_E_level == GoapTypes.WorldELevel.LOW:
			priority += 3.0
		if state.ammo_state_global == GoapTypes.WorldAmmoLevel.CRITICAL:
			priority += 3.0

	return priority
