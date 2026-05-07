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
#var unit_enemy_los_time_s: Dictionary[Unit, Dictionary] = {}
#var unit_enemy_last_seen_unix_s: Dictionary[Unit, Dictionary] = {}
#var unit_enemy_spot_conf: Dictionary[Unit, Dictionary] = {} # unit -> enemy -> 0..1
var units_in_close_combat: Array[Unit]
var close_combat_locations: Array[Vector2i]
var close_combat_instances: Array[CloseCombatInstance]
var objectives: Dictionary[Team, ObjectivesCollection]
var victory_conditions: Dictionary[Team, VictoryConditionCollection]
var map_chosen: Map
var scenario_chosen: Scenario
var units_destroyed: UnitsCollection = UnitsCollection.new()

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

func reset():
	unit_visible_enemies.clear()
	unit_enemies_in_los.clear()
	unit_enemy_tracks.clear()
	#unit_enemy_los_time_s.clear()
	#unit_enemy_last_seen_unix_s.clear()
	#unit_enemy_spot_conf.clear()
	units_in_close_combat.clear()
	close_combat_locations.clear()
	close_combat_instances.clear()
	for team in victory_conditions:
		victory_conditions[team].victory_conditions.clear()
	for team in objectives:
		objectives[team].objectives.clear()
	map_chosen = null
	scenario_chosen = null
	units_destroyed = UnitsCollection.new()
	unit_hierarchy.clear()


func save_match_data(match_save: MatchSaveData) -> void:
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

	var loaded_resource: Resource = ResourceLoader.load(save_path)

	if loaded_resource == null:
		push_error("Could not load match save: %s" % save_path)
		return null

	var match_save: MatchSaveData = loaded_resource as MatchSaveData

	if match_save == null:
		push_error("Loaded resource is not MatchSaveData: %s" % save_path)
		return null

	return match_save
