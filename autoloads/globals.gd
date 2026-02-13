extends Node

var team_player: Team
var team_enemy: Team
var astars: Dictionary[int, AStar2D]
var game_started: bool = false
var objective_hexes: Dictionary[Team, Array]
var game_mode: GameMode
var unit_visible_enemies: Dictionary
var unit_enemies_in_los: Dictionary
var units: Array[Unit]


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
	ATTACK
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
