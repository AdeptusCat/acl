class_name GameGlobals
extends Node

const CASUALTY_ARCHIVE_WRITER: Script = preload("res://resources/casualties/casualty_archive_writer.gd")
const CASUALTY_SAVE_BATCH_SECONDS: float = 0.25

var team_player: Team
var team_enemy: Team
var astars: Dictionary[int, AStar2D]
var game_started: bool = false
var objective_hexes: Dictionary[Team, Array]
var game_mode: GameMode
var unit_visible_enemies: Dictionary
var unit_enemy_tracks: Dictionary[Unit, Dictionary] = {}
var unit_enemies_in_los: Dictionary
var units_in_close_combat: Array[Unit]
var close_combat_locations: Array[Vector2i]
var close_combat_instances: Array[CloseCombatInstance]
var objectives: Dictionary[Team, ObjectivesCollection]
var victory_conditions: Dictionary[Team, VictoryConditionCollection]
var map_chosen: Map
var scenario_chosen: Scenario
var units_destroyed: UnitsCollection = UnitsCollection.new()
var casualty_history: CasualtyHistory = CasualtyHistory.new()
var battle_casualties: Array[CasualtyRecord] = []
var battle_id: String = ""
var _casualty_save_queued: bool = false
var _casualty_save_elapsed: float = 0.0
var _pending_casualty_histories: Dictionary[String, CasualtyHistory] = {}
var _casualty_writer: CASUALTY_ARCHIVE_WRITER
var session_log: SessionLog = SessionLog.new()
var battle_exits: Array[UnitExitRecord] = []
var _session_log_save_queued: bool = false

enum Team {
	AXIS,
	ALLIES
}

enum GameMode {
	ATTACK,
	DEFEND
}

enum UnitCmd {
	MOVE,
	FIRE_AT_HEX,
	FIRE_AT_UNIT,
	ATTACK_UNIT,
	STOP,
}


enum SquadType {
	Rifle,
	MG,
	ANTITANK,
	MORTAR,
	PLATOON_HEADQUARTERS,
	COMPANY_HEADQUARTERS,
}

const SQUAD_TYPE_NAMES: Dictionary[SquadType, String] = {
	SquadType.Rifle: "Rifle",
	SquadType.MG: "MG",
	SquadType.ANTITANK: "Antitank",
	SquadType.MORTAR: "Mortar",
	SquadType.PLATOON_HEADQUARTERS: "PlatoonHQ",
	SquadType.COMPANY_HEADQUARTERS: "CompanyHQ",
}

const TEAM_NAMES: Dictionary[Team, String] = {
	Team.AXIS: "Axis",
	Team.ALLIES: "Allies",
}

const SQUAD_SHIFT: int = 0
const PLATOON_SHIFT: int = 8
const COMPANY_SHIFT: int = 16
const TEAM_SHIFT: int = 24

#var company_hierarchy: Dictionary[Unit.Company, Dictionary]
#var platoon_hierarchy: Dictionary[int, Dictionary]
#var unit_hierarchy: Dictionary[int, Unit]

var unit_hierarchy: Dictionary[int, Unit] = {}

func make_key(team: Team, company: Unit.Company, platoon: int, squad: int) -> int:
	var t: int = int(team) & 0xFF
	var c: int = int(company) & 0xFF
	var p: int = platoon & 0xFF
	var s: int = squad & 0xFF
	
	return (t << TEAM_SHIFT) | (c << COMPANY_SHIFT) | (p << PLATOON_SHIFT) | s

func register_unit(team: Team, company: Unit.Company, platoon: int, squad: int, unit: Unit) -> void:
	var key: int = make_key(team, company, platoon, squad)
	unit_hierarchy[key] = unit

func get_unit(team: Team, company: Unit.Company, platoon: int, squad: int) -> Unit:
	var key: int = make_key(team, company, platoon, squad)
	if unit_hierarchy.has(key) == false:
		return null
	return unit_hierarchy[key]

func unregister_unit(team: Team, company: Unit.Company, platoon: int, squad: int) -> void:
	var key: int = make_key(team, company, platoon, squad)
	if unit_hierarchy.has(key) == false:
		return
	unit_hierarchy.erase(key)


func get_units() -> Array[Unit]:
	var _units: Array[Unit] = []
	_units.assign(get_tree().get_nodes_in_group("units"))
	return _units


func get_exited_units() -> Array[Unit]:
	var result: Array[Unit] = []
	result.assign(get_tree().get_nodes_in_group("exited_units"))
	return result


func get_units_for_team(team: Team) -> Array[Unit]:
	var result: Array[Unit] = []
	
	for unit: Unit in Globals.get_units():
		if not is_instance_valid(unit):
			continue

		if not unit.alive:
			continue

		if unit.team != team:
			continue

		result.append(unit)

	return result


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Engine.is_editor_hint():
		casualty_history = CasualtyHistory.load_history()
		session_log = SessionLog.load_log()


func _exit_tree() -> void:
	flush_casualty_history()
	if _casualty_writer != null:
		_casualty_writer.shutdown()
	if _session_log_save_queued:
		_save_session_log()


func begin_battle() -> void:
	battle_id = Crypto.new().generate_random_bytes(16).hex_encode()
	battle_casualties.clear()
	battle_exits.clear()


func record_unit_exit(unit: Unit) -> UnitExitRecord:
	if unit.exit_record != null:
		return unit.exit_record
	if battle_id.is_empty():
		begin_battle()
	var record: UnitExitRecord = UnitExitRecord.capture(unit, battle_id)
	import_exit_records([record])
	battle_exits.append(record)
	print("%s unit %s exited at %s (%s soldiers)" % [TEAM_NAMES[unit.team], unit.name, unit.current_hex, unit.members_alive])
	return record


func import_exit_records(records: Array[UnitExitRecord]) -> void:
	for record: UnitExitRecord in records:
		if session_log.add_exit(record) and not _session_log_save_queued:
			_session_log_save_queued = true
			_save_session_log.call_deferred()


func _save_session_log() -> void:
	_session_log_save_queued = false
	var save_error: Error = session_log.save_log()
	if save_error != OK:
		push_error("Could not save session log: %s" % save_error)


func record_casualty(unit: Unit, soldier: Soldier) -> CasualtyRecord:
	if not soldier.casualty_record_id.is_empty():
		return casualty_history.find_record(soldier.casualty_record_id)
	if battle_id.is_empty():
		begin_battle()
	var record: CasualtyRecord = CasualtyRecord.capture(unit, soldier, battle_id)
	soldier.casualty_record_id = record.record_id
	casualty_history.add_record(record)
	battle_casualties.append(record)
	if is_instance_valid(Debug.engagement_recorder):
		Debug.engagement_recorder.record_casualty(unit, soldier, record)
	_queue_casualty_save()
	return record


func import_casualty_records(records: Array[CasualtyRecord]) -> void:
	var changed: bool = false
	for record: CasualtyRecord in records:
		if casualty_history.add_record(record):
			changed = true
	if changed:
		_queue_casualty_save()


func _process(delta: float) -> void:
	if _casualty_save_queued:
		_casualty_save_elapsed += delta
		if _casualty_save_elapsed >= CASUALTY_SAVE_BATCH_SECONDS:
			_save_casualty_history()
	_report_casualty_save_results()


func _queue_casualty_save() -> void:
	_pending_casualty_histories[casualty_history.storage_path] = casualty_history
	_casualty_save_queued = true


func _save_casualty_history() -> void:
	_casualty_save_queued = false
	_casualty_save_elapsed = 0.0
	if _casualty_writer == null:
		_casualty_writer = CASUALTY_ARCHIVE_WRITER.new()
	for path: String in _pending_casualty_histories.keys():
		var history: CasualtyHistory = _pending_casualty_histories[path]
		var error: Error = _casualty_writer.queue_save(history)
		if error != OK:
			push_error("Could not queue casualty history save: %s" % error_string(error))
		else:
			_pending_casualty_histories.erase(path)
	_casualty_save_queued = not _pending_casualty_histories.is_empty()


func _report_casualty_save_results() -> void:
	if _casualty_writer == null:
		return
	_casualty_writer.process_pending()
	for result: Dictionary in _casualty_writer.take_results():
		if result["error"] != OK:
			push_error("Could not save casualty history '%s': %s" % [result["path"], error_string(result["error"])])


func flush_casualty_history() -> void:
	# Blocking is reserved for shutdown and explicit persistence checkpoints.
	if _casualty_save_queued:
		_save_casualty_history()
	if _casualty_writer != null:
		_casualty_writer.flush()
		_report_casualty_save_results()
	# If a worker could not start, only this explicit blocking checkpoint may
	# fall back to synchronous saving. Gameplay keeps its pending records.
	for path: String in _pending_casualty_histories.keys():
		var error: Error = _pending_casualty_histories[path].save_history()
		if error != OK:
			push_error("Could not flush casualty history '%s': %s" % [path, error_string(error)])
		else:
			_pending_casualty_histories.erase(path)
	_casualty_save_queued = not _pending_casualty_histories.is_empty()


func reset() -> void:
	Debug.finish_engagement_capture("match_reset")
	battle_id = ""
	battle_casualties.clear()
	battle_exits.clear()
	unit_visible_enemies.clear()
	unit_enemies_in_los.clear()
	unit_enemy_tracks.clear()
	units_in_close_combat.clear()
	close_combat_locations.clear()
	close_combat_instances.clear()
	for team: Team in victory_conditions:
		victory_conditions[team].victory_conditions.clear()
	for team: Team in objectives:
		objectives[team].objectives.clear()
	map_chosen = null
	scenario_chosen = null
	units_destroyed = UnitsCollection.new()
	unit_hierarchy.clear()


func save_match_data(match_save: MatchSaveData) -> void:
	import_casualty_records(match_save.casualty_records)
	import_exit_records(match_save.exit_records)
	var save_path: String = "user://matches/%s.tres" % match_save.match_id
	print("Saved match as: " + save_path)
	var dir_path: String = save_path.get_base_dir()

	if not DirAccess.dir_exists_absolute(dir_path):
		var dir_error: Error = DirAccess.make_dir_recursive_absolute(dir_path)

		if dir_error != OK:
			push_error("Could not create save directory: %s Error: %s" % [dir_path, dir_error])
			return

	var previous: MatchSaveData
	if ResourceLoader.exists(save_path):
		previous = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as MatchSaveData
	match_save.preserve_player_victories(previous)
	var save_error: Error = ResourceSaver.save(match_save, save_path)

	if save_error != OK:
		push_error("Could not save match data: %s Error: %s" % [save_path, save_error])
		return


func load_match_data(match_id: String) -> MatchSaveData:
	var save_path: String = "user://matches/%s.tres" % match_id

	if not ResourceLoader.exists(save_path):
		push_error("Match save does not exist: %s" % save_path)
		return null

	var loaded_resource: Resource = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE)

	if loaded_resource == null:
		push_error("Could not load match save: %s" % save_path)
		return null

	var match_save: MatchSaveData = loaded_resource as MatchSaveData

	if match_save == null:
		push_error("Loaded resource is not MatchSaveData: %s" % save_path)
		return null

	import_casualty_records(match_save.casualty_records)
	import_exit_records(match_save.exit_records)
	return match_save


func get_enemy_team(team: int) -> int:
	if team == Globals.Team.ALLIES:
		return Globals.Team.AXIS

	return Globals.Team.ALLIES
