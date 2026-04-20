extends RefCounted
class_name ObjectiveState

var objective_id: int = -1
var hexes: Array[Vector2i] = []

var controlling_side: int = -1
var is_contested: bool = false

var side_control_ratio: Dictionary = {}
var side_hold_time_s: Dictionary = {}
