class_name VictoryConditionProgress
extends RefCounted

enum Kind { UNSUPPORTED, OCCUPY, EXIT, DESTROY, PREVENT_EXIT }

var condition: VictoryCondition
var kind: Kind = Kind.UNSUPPORTED
var team: Globals.Team
var objective_team: Globals.Team
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
	progress.objective_team = source.team
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
	elif source is PreventEnemyExitCondition:
		var prevention: PreventEnemyExitCondition = source as PreventEnemyExitCondition
		progress.kind = Kind.PREVENT_EXIT
		progress.objective_team = Globals.get_enemy_team(source.team)
		# This threshold is the number of exits that would invalidate prevention.
		progress.required_units = prevention.max_allowed_enemy_exits + 1
		progress.remaining_units = progress.required_units
		if prevention.state != null:
			progress.hexes = prevention.state.exit_hexes.duplicate()
			progress.remaining_units = maxi(0, progress.required_units - prevention.state.units_exited.size())
		progress.valid = not progress.hexes.is_empty() and prevention.max_allowed_enemy_exits >= 0
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


static func outcome_possible(conditions: Array[VictoryCondition], owner: Globals.Team, level: VictoryCondition.OutcomeLevel) -> bool:
	var units: Array[Unit] = Globals.get_units()
	var friendly_count: int = _remaining_units(units, owner)
	var enemy_team: Globals.Team = Globals.get_enemy_team(owner)
	var enemy_count: int = _remaining_units(units, enemy_team)
	var garrisons: Dictionary[Vector2i, int] = {}
	var exits_needed: int = 0
	var found: bool = false
	for source: VictoryCondition in conditions:
		if source.team != owner or source.outcome_level != level:
			continue
		found = true
		var progress: VictoryConditionProgress = read(source)
		# Missing state and custom conditions cannot prove an irreversible defeat.
		if not progress.valid or progress.complete:
			continue
		match progress.kind:
			Kind.EXIT:
				var exit: ExitUnitsCondition = source as ExitUnitsCondition
				if progress.remaining_units > _remaining_units(units, owner, exit.state.units_exited):
					return false
				# Overlapping exit objectives can credit the same departing squad.
				exits_needed = maxi(exits_needed, progress.remaining_units)
			Kind.DESTROY:
				var defeated: Array[Unit] = Globals.units_destroyed.units_collection[owner].units
				if friendly_count == 0 or progress.remaining_units > _remaining_units(units, enemy_team, defeated):
					return false
			Kind.PREVENT_EXIT:
				# Recorded enemy exits can never be reversed.
				return false
			Kind.OCCUPY:
				if friendly_count == 0:
					return false
				# Eliminating the remaining enemy can secure even unoccupied objectives.
				# Do not reject a capture for insufficient garrisons while that route remains.
				if enemy_count > 0:
					continue
				for hex: Vector2i in progress.hexes:
					garrisons[hex] = maxi(garrisons.get(hex, 0), progress.required_units)
	var garrison_count: int = 0
	for count: int in garrisons.values():
		garrison_count += count
	return found and garrison_count + exits_needed <= friendly_count


static func _remaining_units(units: Array[Unit], team: Globals.Team, credited: Array[Unit] = []) -> int:
	var count: int = 0
	for unit: Unit in units:
		if is_instance_valid(unit) and not unit.is_queued_for_deletion() and unit.team == team and unit.is_active() and not unit.surrendered and not credited.has(unit):
			# Pinning and routing are recoverable; they do not remove a squad's potential.
			count += 1
	return count
