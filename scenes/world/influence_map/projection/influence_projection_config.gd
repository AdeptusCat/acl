class_name InfluenceProjectionConfig
extends RefCounted

var unit_team: int = Globals.Team.AXIS
var enemy_team: int = Globals.Team.ALLIES
var unit_group: String = ""
var enemy_group: String = ""
var task: int = 1
var objective_hex: Vector2i = Vector2i.ZERO
var enemy_units: Array[Unit] = []

var projected_line_max_cells: int = 8

# Destination stamp settings.
var anchor_skip_front: int = 3
var anchor_count: int = 1

# Simulated enemy LOS settings.
var los_skip_front: int = 4
var los_count: int = 4

var move_improvement_ratio: float = 0.8
var threat_axis: ThreatAxis = null
