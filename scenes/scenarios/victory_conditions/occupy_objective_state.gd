extends RefCounted
class_name OccupyObjectiveState

var hexes: Array[Vector2i]
var required_times_reached_s: Dictionary[Vector2i, float]
var units_in_objectives: Dictionary[Vector2i, UnitsCollection]
var victory_conditions_met: Dictionary[Vector2i, bool]

# Ownership survives an empty or contested hex; only a completed capture transfers it.
var controlling_teams: Dictionary[Vector2i, int] = {}
var enemy_hold_times_s: Dictionary[Vector2i, float] = {}
