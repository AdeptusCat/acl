class_name HoldToExitFallbackPolicy
extends Resource

## References an existing occupation condition in this scenario's Victory Conditions.
@export var hold_condition: OccupyObjectiveCondition
## References an existing exit condition for the same side at a lower victory level.
@export var exit_condition: ExitUnitsCondition
## Require a continuous failure before abandoning the hold. Brief setbacks reset this timer.
@export_range(0.0, 60.0, 0.5, "or_greater") var confirmation_seconds: float = 5.0
## Leave this much time beyond estimated exit travel when the hold is not secured.
@export_range(0.0, 120.0, 1.0, "or_greater") var withdrawal_margin_seconds: float = 10.0
## Withdraw below this many eligible combat squads, even if the objective is held.
## HQ does not count. Zero disables this force-strength trigger.
@export_range(0, 128, 1, "or_greater") var minimum_combat_squads: int = 0
## Withdraw HQ and all surviving squads; OFF sends only the outstanding exit quota.
@export var withdraw_entire_force: bool = true
@export var enabled: bool = true


func configuration_error(conditions: Array[VictoryCondition]) -> String:
	if hold_condition == null or exit_condition == null:
		return "Hold-to-exit fallback needs both a hold condition and an exit condition"
	if not conditions.has(hold_condition) or not conditions.has(exit_condition):
		return "Hold-to-exit fallback must reference existing scenario victory conditions"
	if hold_condition.team != exit_condition.team:
		return "Hold-to-exit fallback conditions must belong to the same side"
	if exit_condition.outcome_level >= hold_condition.outcome_level:
		return "Hold-to-exit fallback requires an exit at a lower victory level than the hold"
	if minimum_combat_squads < 0:
		return "Hold-to-exit fallback minimum combat squads must be nonnegative"
	if not is_finite(confirmation_seconds) or confirmation_seconds < 0.0 or not is_finite(withdrawal_margin_seconds) or withdrawal_margin_seconds < 0.0:
		return "Hold-to-exit fallback timing must be finite and nonnegative"
	return ""
