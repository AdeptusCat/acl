class_name GameGlobals
extends Node

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
	if not Engine.is_editor_hint():
		casualty_history = CasualtyHistory.load_history()


func _exit_tree() -> void:
	if _casualty_save_queued:
		_save_casualty_history()


func begin_battle() -> void:
	battle_id = Crypto.new().generate_random_bytes(16).hex_encode()
	battle_casualties.clear()


func record_casualty(unit: Unit, soldier: Soldier) -> CasualtyRecord:
	if not soldier.casualty_record_id.is_empty():
		return casualty_history.find_record(soldier.casualty_record_id)
	if battle_id.is_empty():
		begin_battle()
	var record: CasualtyRecord = CasualtyRecord.capture(unit, soldier, battle_id)
	soldier.casualty_record_id = record.record_id
	casualty_history.add_record(record)
	battle_casualties.append(record)
	_queue_casualty_save()
	return record


func import_casualty_records(records: Array[CasualtyRecord]) -> void:
	var changed: bool = false
	for record: CasualtyRecord in records:
		if casualty_history.add_record(record):
			changed = true
	if changed:
		_queue_casualty_save()


func _queue_casualty_save() -> void:
	if _casualty_save_queued:
		return
	_casualty_save_queued = true
	_save_casualty_history.call_deferred()


func _save_casualty_history() -> void:
	_casualty_save_queued = false
	var save_error: Error = casualty_history.save_history()
	if save_error != OK:
		push_error("Could not save casualty history: %s" % save_error)


func reset() -> void:
	battle_id = ""
	battle_casualties.clear()
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
	var save_path: String = "user://matches/%s.tres" % match_save.match_id
	print("Saved match as: " + save_path)
	var dir_path: String = save_path.get_base_dir()

	if not DirAccess.dir_exists_absolute(dir_path):
		var dir_error: Error = DirAccess.make_dir_recursive_absolute(dir_path)

		if dir_error != OK:
			push_error("Could not create save directory: %s Error: %s" % [dir_path, dir_error])
			return

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
	return match_save


func get_enemy_team(team: int) -> int:
	if team == Globals.Team.ALLIES:
		return Globals.Team.AXIS

	return Globals.Team.ALLIES
