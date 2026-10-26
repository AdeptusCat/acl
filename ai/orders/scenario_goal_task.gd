class_name ScenarioGoalTask
extends RefCounted

enum Kind { OCCUPY, EXIT, DENY_OCCUPATION, BLOCK_EXIT, HUNT, PRESERVE }
enum EscapeDuty { EXIT, RECOVER, HEADQUARTERS_SUPPORT, BREACH }

const SECURED_DEFENSE_RADIUS: int = 2

var kind: Kind
var key: String
var condition: VictoryCondition
var hex: Vector2i
var required_units: int = 1
var priority: float = 0.0
var urgent: bool = false
var withdrawal: bool = false
var escape_policy: EscapeMissionPolicy
var bypass_units: Dictionary[Unit, bool] = {}
var recovering_units: Dictionary[Unit, bool] = {}
var breach_required: bool = false
var breach_hex: Vector2i
var defend_from_cover: bool = false
var reason: String = ""


func is_destination_goal() -> bool:
	return kind == Kind.EXIT or (kind == Kind.OCCUPY and not defend_from_cover)


func includes_headquarters() -> bool:
	if escape_policy != null:
		return escape_policy.include_headquarters
	return withdrawal


func requires_breach(unit: Unit) -> bool:
	return breach_required and (escape_policy == null or (not bypass_units.has(unit) and not recovering_units.has(unit)))


func escape_duty(unit: Unit) -> EscapeDuty:
	if recovering_units.has(unit):
		return EscapeDuty.RECOVER
	if HqSupportPositionPolicy.is_headquarters(unit):
		for subordinate: Unit in recovering_units:
			if not TacticalPositionExecutor.is_active_defender(subordinate) or HqSupportPositionPolicy.is_headquarters(subordinate):
				continue
			var belongs: bool = subordinate.command_squad == unit
			belongs = belongs or (subordinate.company == unit.company and (unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS or subordinate.platoon == unit.platoon))
			if belongs:
				return EscapeDuty.HEADQUARTERS_SUPPORT
		if requires_breach(unit):
			return EscapeDuty.HEADQUARTERS_SUPPORT
	elif requires_breach(unit):
		return EscapeDuty.BREACH
	return EscapeDuty.EXIT


static func exit_state_for(source: VictoryCondition) -> ExitUnitsState:
	if source is ExitUnitsCondition:
		return (source as ExitUnitsCondition).state
	if source is PreventEnemyExitCondition:
		return (source as PreventEnemyExitCondition).state
	return null


func exit_capacity() -> int:
	if withdrawal:
		return maxi(required_units, (condition as ExitUnitsCondition).required_unit_count)
	if condition is ExitUnitsCondition:
		return (condition as ExitUnitsCondition).required_unit_count
	if condition is PreventEnemyExitCondition:
		return (condition as PreventEnemyExitCondition).max_allowed_enemy_exits + 1
	return 1
