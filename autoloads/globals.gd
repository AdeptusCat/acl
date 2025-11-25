extends Node

var team_player: int
var astars: Dictionary[int, AStar2D]
var game_started: bool = false
var movement_system: MovementSystem
var objective_hexes: Dictionary[Team, Array]


enum Team {
	AXIS,
	ALLIES
}
