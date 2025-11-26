extends Node

var team_player: Team
var astars: Dictionary[int, AStar2D]
var game_started: bool = false
var movement_system: MovementSystem
var objective_hexes: Dictionary[Team, Array]
var game_mode: GameMode

enum Team {
	AXIS,
	ALLIES
}

enum GameMode {
	ATTACK,
	DEFEND
}
