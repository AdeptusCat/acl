class_name VictoryConditionProgress
extends RefCounted

enum Kind { UNSUPPORTED, OCCUPY, EXIT, DESTROY }

var condition: VictoryCondition
var kind: Kind = Kind.UNSUPPORTED
var team: Globals.Team
var outcome: VictoryCondition.OutcomeLevel
var hexes: Array[Vector2i] = []
var required_units: int = 0
var remaining_units: int = 0
var required_seconds: float = 0.0
var held_seconds: Dictionary[Vector2i, float] = {}
var complete: bool = false
var valid: bool = true
var diagnostic: String = ""


static func read(source: VictoryCondition) -> VictoryConditionProgress:
	var progress: VictoryConditionProgress = VictoryConditionProgress.new()
	progress.condition = source
	progress.team = source.team
	progress.outcome = source.outcome_level
	if source is OccupyObjectiveCondition:
		var occupy: OccupyObjectiveCondition = source as OccupyObjectiveCondition
		progress.kind = Kind.OCCUPY
		progress.required_units = occupy.required_unit_count
		progress.required_seconds = occupy.required_time_s
		if occupy.state != null:
			progress.hexes = occupy.state.hexes.duplicate()
			progress.held_seconds = occupy.state.required_times_reached_s.duplicate()
		progress.valid = not progress.hexes.is_empty() and progress.required_units > 0 and progress.required_seconds >= 0.0
	elif source is ExitUnitsCondition:
		var exit: ExitUnitsCondition = source as ExitUnitsCondition
		progress.kind = Kind.EXIT
		progress.required_units = exit.required_unit_count
		progress.remaining_units = exit.required_unit_count
		if exit.state != null:
			progress.hexes = exit.state.exit_hexes.duplicate()
			progress.remaining_units = maxi(0, exit.required_unit_count - exit.state.units_exited.size())
		progress.valid = not progress.hexes.is_empty() and progress.required_units > 0
	elif source is DestroyUnitsCondition:
		var destroy: DestroyUnitsCondition = source as DestroyUnitsCondition
		progress.kind = Kind.DESTROY
		progress.required_units = destroy.required_unit_count
		progress.remaining_units = maxi(0, destroy.required_unit_count - Globals.units_destroyed.units_collection[source.team].units.size())
		progress.valid = progress.required_units >= 0
	else:
		progress.valid = false
		progress.diagnostic = "Unsupported victory condition: " + source.get_script().resource_path
	if not progress.valid and progress.diagnostic == "":
		progress.diagnostic = "Victory condition has no matching objective markers or invalid thresholds"
	if progress.valid:
		progress.complete = source.is_condition_met()
	return progress


static func outcome_complete(conditions: Array[VictoryCondition], owner: Globals.Team, level: VictoryCondition.OutcomeLevel, at_end: bool) -> bool:
	var found: bool = false
	for condition: VictoryCondition in conditions:
		if condition.team != owner or condition.outcome_level != level:
			continue
		found = true
		if condition.test_at_scenario_end and not at_end:
			return false
		if not condition.is_condition_met():
			return false
	return found
