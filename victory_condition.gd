extends Resource
class_name VictoryCondition

enum RuleType {
	OCCUPY_OBJECTIVE,
	CLEAR_OBJECTIVE,
	EXIT_UNITS,
	PRESERVE_FORCE,
	BREAK_ENEMY,
	DELAY_UNTIL_TIME
}

enum OutcomeLevel {
	MINOR,
	MAJOR
}

enum ObjetiveId {
	A,
	B,
	C
}

@export var side: Globals.Team = Globals.Team.AXIS
@export var rule_type: RuleType = RuleType.OCCUPY_OBJECTIVE
@export var outcome_level: OutcomeLevel = OutcomeLevel.MINOR

@export var objective_id: ObjetiveId = ObjetiveId.A
@export var required_ratio: float = 1.0
@export var required_time_s: float = 0.0

@export var required_unit_count: int = 0
@export var required_effective_ratio: float = 0.0
@export var required_enemy_effective_ratio_below: float = -1.0
@export var required_time_reached_s: float = -1.0
