extends Node

var team_player: Team
var astars: Dictionary[int, AStar2D]
var game_started: bool = false
var objective_hexes: Dictionary[Team, Array]
var game_mode: GameMode
var unit_visible_enemies: Dictionary
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
