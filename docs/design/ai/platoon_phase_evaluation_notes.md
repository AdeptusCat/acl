# 6. Evaluate current phase.
_select_attack_phase()
PlatoonTypes.Phase.PLANNING_ATTACK


# 7. Select or update HTN plan for phase.
_build_planning_attack_plan
blackboard.phase_tasks:
PlatoonTypes.TaskType.RALLY_AT_HEX,

# 8. Score squad-role assignments.
_score_squad_role_assignments
_score_squad_for_task
every squad gets RALLY_AT_HEX task
get into wedge formation


# 6. Evaluate current phase.
_select_attack_phase()
PlatoonTypes.Phase.APPROACH_TO_OBJECTIVE


# 7. Select or update HTN plan for phase.
