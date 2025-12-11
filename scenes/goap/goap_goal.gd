# goap_goal.gd
class_name GoapGoal
extends Resource

var goal_id: GoapTypes.FormationGoalId = GoapTypes.FormationGoalId.MAINTAIN_DEFENSE
var base_priority: float = 1.0

func is_satisfied(state: FormationWorldState) -> bool:
	match goal_id:
		GoapTypes.FormationGoalId.MAINTAIN_DEFENSE:
			# this is stupid and has to go
			# the goal should not be dependend on the following
			# but how?
			if state.objective_held and state.position_held == true:
				return true
			return false

		GoapTypes.FormationGoalId.CAPTURE_OBJECTIVE:
			if state.enemy_holds_objective or state.objective_held:
				return true
			return false
		_:
			return false

func compute_dynamic_priority(state: FormationWorldState) -> float:
	var priority: float = base_priority

	if goal_id == GoapTypes.FormationGoalId.MAINTAIN_DEFENSE:
		# Only meaningful if there is an objective at all
		#if state.objective_held:
			## We already hold it -> keep it
			#priority += 4.0
		#else:
			## We do NOT hold it -> maintaining defense around nothing
			## should be low priority compared to capturing
			#priority -= 2.0

		# DEFEND mission bias
		if state.mission_mode == GoapTypes.FormationMissionMode.DEFEND:
			priority += 1.0

	elif goal_id == GoapTypes.FormationGoalId.CAPTURE_OBJECTIVE:
		# If the objective is not held, attacking it becomes important
		#if not state.objective_held:
			#priority += 6.0
		#else:
			## Already held -> do not waste effort on "capture"
			#priority -= 3.0

		# ATTACK mission bias
		if state.mission_mode == GoapTypes.FormationMissionMode.ATTACK:
			priority += 1.0

	return priority
