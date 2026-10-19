class_name EscapeMissionPolicy
extends Resource

## Escape is the mission even while squads are pinned or the victory quota is unattainable.
@export var exit_condition: ExitUnitsCondition
## Send every surviving eligible unit instead of only the remaining victory quota.
@export var withdraw_entire_force: bool = true
## Exit conditions count headquarters too; scenarios can explicitly retain them.
@export var include_headquarters: bool = true
## Compare routes by travel time plus time exposed to known or remembered fire.
@export_range(0.0, 20.0, 0.5) var exposure_weight: float = 4.0
## Bypass only weakly observed corridors; fight to clear lanes covered by effective fire.
@export_range(0.0, 1.0, 0.05) var maximum_bypass_visibility: float = 0.25
@export_range(0.0, 1.0, 0.05) var maximum_bypass_risk: float = 0.4
@export var enabled: bool = true


func configuration_error(conditions: Array[VictoryCondition]) -> String:
	if exit_condition == null or not conditions.has(exit_condition):
		return "Escape mission must reference an existing scenario exit condition"
	if not is_finite(exposure_weight) or exposure_weight < 0.0:
		return "Escape mission exposure weight must be finite and nonnegative"
	if not is_finite(maximum_bypass_visibility) or maximum_bypass_visibility < 0.0 or maximum_bypass_visibility > 1.0:
		return "Escape mission bypass visibility must be between zero and one"
	if not is_finite(maximum_bypass_risk) or maximum_bypass_risk < 0.0 or maximum_bypass_risk > 1.0:
		return "Escape mission bypass risk must be between zero and one"
	return ""


func allows(unit: Unit) -> bool:
	return include_headquarters or not HqSupportPositionPolicy.is_headquarters(unit)
