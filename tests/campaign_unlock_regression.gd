extends Node

const SELECTOR: Script = preload("res://scenes/ui/screens/scenario_selection_screen.gd")
const MATCH_ID: String = "tests/campaign_unlock/prerequisite"
const SAVE_PATH: String = "user://matches/" + MATCH_ID + ".tres"

var checks: int = 0
var failures: int = 0
var screen: CanvasLayer
var previous: Scenario
var next: Scenario


func _ready() -> void:
	screen = SELECTOR.new()
	previous = Scenario.new()
	previous.scenario_id = MATCH_ID
	previous.scenario_name = "Prerequisite"
	previous.player_team = Globals.Team.ALLIES
	next = Scenario.new()
	next.previous_scenario = previous
	next.released = true
	if OS.get_cmdline_user_args().has("--verify"):
		_verify_restart()
	else:
		_test_replays()
		_test_legacy_results()
		_test_mismatched_scenario()
		_save(Globals.Team.ALLIES, Globals.Team.ALLIES, VictoryCondition.OutcomeLevel.MINOR, "final-win")
		_save(Globals.Team.ALLIES, Globals.Team.AXIS, VictoryCondition.OutcomeLevel.MINOR, "final-defeat")
		_verify_restart()
	screen.free()
	next.free()
	previous.free()
	print("Campaign unlock checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_replays() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	_check(not screen.get_lock_reason(next).is_empty(), "An unplayed prerequisite keeps the next mission locked")
	_save(Globals.Team.ALLIES, Globals.Team.AXIS, VictoryCondition.OutcomeLevel.MINOR, "first-defeat")
	_check(not screen.get_lock_reason(next).is_empty(), "A defeat alone cannot unlock the next mission")
	_save(Globals.Team.ALLIES, -1, VictoryCondition.OutcomeLevel.MINOR, "first-draw")
	_check(not screen.get_lock_reason(next).is_empty(), "A draw alone cannot unlock the next mission")
	_save(Globals.Team.AXIS, Globals.Team.AXIS, VictoryCondition.OutcomeLevel.MAJOR, "opposite-win")
	_check(not screen.get_lock_reason(next).is_empty(), "A victory as the opposite player faction cannot unlock the authored campaign")
	_save(Globals.Team.ALLIES, Globals.Team.ALLIES, VictoryCondition.OutcomeLevel.MINOR, "minor-win")
	_check(screen.get_lock_reason(next).is_empty(), "A minor player victory unlocks the next mission")
	_save(Globals.Team.ALLIES, Globals.Team.AXIS, VictoryCondition.OutcomeLevel.MINOR, "replay-defeat")
	_check(screen.get_lock_reason(next).is_empty(), "Losing a replay preserves the earned unlock")
	_check_latest(Globals.Team.ALLIES, Globals.Team.AXIS, "replay-defeat")
	_save(Globals.Team.ALLIES, -1, VictoryCondition.OutcomeLevel.MINOR, "replay-draw")
	_check(screen.get_lock_reason(next).is_empty(), "Drawing a replay preserves the earned unlock")
	_save(Globals.Team.AXIS, Globals.Team.ALLIES, VictoryCondition.OutcomeLevel.MINOR, "opposite-defeat")
	_check(screen.get_lock_reason(next).is_empty(), "Replaying as the opposite faction cannot erase the original player's completion")
	_check_latest(Globals.Team.AXIS, Globals.Team.ALLIES, "opposite-defeat")
	previous.scenario_name = "Renamed prerequisite"
	_check(screen.get_lock_reason(next).is_empty(), "Renaming the briefing preserves completion under the stable scenario identifier")
	# Legacy prerequisites without a stable scenario ID retain their any-faction rule.
	previous.scenario_id = ""
	previous.scenario_name = MATCH_ID
	_check(screen.get_lock_reason(next).is_empty(), "An unnamed legacy prerequisite also retains completion after replay")
	previous.scenario_id = MATCH_ID


func _test_legacy_results() -> void:
	for level: VictoryCondition.OutcomeLevel in [VictoryCondition.OutcomeLevel.MINOR, VictoryCondition.OutcomeLevel.MAJOR]:
		DirAccess.remove_absolute(SAVE_PATH)
		var legacy: MatchSaveData = MatchSaveData.new()
		legacy.save_version = 3
		legacy.match_id = MATCH_ID
		legacy.scenario_id = MATCH_ID
		legacy.player_team = Globals.Team.ALLIES
		legacy.winner_team = Globals.Team.ALLIES
		legacy.outcome_level = level
		_check(ResourceSaver.save(legacy, SAVE_PATH) == OK, "A legacy victory without completion metadata is saved")
		_check(screen.get_lock_reason(next).is_empty(), "Existing minor and major victories still unlock the next mission")
		_save(Globals.Team.ALLIES, Globals.Team.AXIS, level, "legacy-replay-defeat")
		_check(screen.get_lock_reason(next).is_empty(), "The first replay preserves a victory from an older save")
		_check_latest(Globals.Team.ALLIES, Globals.Team.AXIS, "legacy-replay-defeat")
		_save(Globals.Team.ALLIES, -1, level, "legacy-replay-draw")
		_check(screen.get_lock_reason(next).is_empty(), "Migrated completion survives further overwrites")


func _test_mismatched_scenario() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	var unrelated: MatchSaveData = MatchSaveData.new()
	unrelated.match_id = MATCH_ID
	unrelated.scenario_id = "another_scenario"
	unrelated.player_team = Globals.Team.ALLIES
	unrelated.winner_team = Globals.Team.ALLIES
	_check(ResourceSaver.save(unrelated, SAVE_PATH) == OK, "A mismatched result fixture is saved")
	_check(not screen.get_lock_reason(next).is_empty(), "An unrelated scenario result cannot unlock the prerequisite")
	_save(Globals.Team.ALLIES, Globals.Team.AXIS, VictoryCondition.OutcomeLevel.MINOR, "mismatched-replay")
	_check(not screen.get_lock_reason(next).is_empty(), "Completion from an unrelated scenario is not inherited when saving a defeat")


func _save(player: Globals.Team, winner: int, level: VictoryCondition.OutcomeLevel, battle: String) -> void:
	var result: MatchSaveData = MatchSaveData.new()
	result.match_id = MATCH_ID
	result.scenario_id = MATCH_ID
	result.player_team = player
	result.winner_team = winner
	result.outcome_level = level
	result.battle_id = battle
	result.timeout = winner != player
	var roster: UnitSaveData = UnitSaveData.new()
	roster.unit_id = battle.hash()
	result.player_units.append(roster)
	Globals.save_match_data(result)
	_check(FileAccess.file_exists(SAVE_PATH), "The latest battle result is saved")


func _check_latest(player: Globals.Team, winner: int, battle: String) -> void:
	var latest: MatchSaveData = ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as MatchSaveData
	_check(latest != null and latest.player_team == player and latest.winner_team == winner and latest.battle_id == battle,
		"Completion history does not replace the actual latest battle result")
	_check(latest != null and latest.timeout and latest.player_units.size() == 1 and latest.player_units[0].unit_id == battle.hash(),
		"The latest replay retains its own timeout and unit roster")


func _verify_restart() -> void:
	_check(screen.get_lock_reason(next).is_empty(), "Earned completion persists when loaded in a fresh process")
	_check_latest(Globals.Team.ALLIES, Globals.Team.AXIS, "final-defeat")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
