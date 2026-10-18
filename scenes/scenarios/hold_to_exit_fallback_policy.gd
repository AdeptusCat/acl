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
## Low strength below this many eligible combat squads. HQ does not count.
## In multi-objective defenses, objective losses are also required. Zero disables this threshold.
@export_range(0, 128, 1, "or_greater") var minimum_combat_squads: int = 0
## Multi-objective defenses withdraw only after this many distinct markers fall to the enemy.
@export_range(2, 128, 1, "or_greater") var minimum_lost_objectives: int = 2
## Multi-objective defenses also consider ready combat personnel relative to the initial force.
## Zero disables this relative low-strength threshold; single-objective fallback is unchanged.
@export_range(0.0, 1.0, 0.05) var withdrawal_strength_ratio: float = 0.5
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
	if minimum_lost_objectives < 2:
		return "Multi-objective fallback requires at least two lost objectives"
	if not is_finite(withdrawal_strength_ratio) or withdrawal_strength_ratio < 0.0 or withdrawal_strength_ratio > 1.0:
		return "Hold-to-exit fallback strength ratio must be between zero and one"
	if not is_finite(confirmation_seconds) or confirmation_seconds < 0.0 or not is_finite(withdrawal_margin_seconds) or withdrawal_margin_seconds < 0.0:
		return "Hold-to-exit fallback timing must be finite and nonnegative"
	return ""
