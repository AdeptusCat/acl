extends Node

var team_player: Team
var team_enemy: Team
var astars: Dictionary[int, AStar2D]
var game_started: bool = false
var objective_hexes: Dictionary[Team, Array]
var game_mode: GameMode
var unit_visible_enemies: Dictionary
var unit_enemies_in_los: Dictionary
var unit_enemy_los_time_s: Dictionary[Unit, Dictionary] = {}
var unit_enemy_last_seen_unix_s: Dictionary[Unit, Dictionary] = {}
var unit_enemy_spot_conf: Dictionary[Unit, Dictionary] = {} # unit -> enemy -> 0..1
var units_in_close_combat: Array[Unit]
var close_combat_locations: Array[Vector2i]
var close_combat_instances: Array[CloseCombatInstance]

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
