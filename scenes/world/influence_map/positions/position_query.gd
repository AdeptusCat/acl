class_name PositionQuery
extends RefCounted

enum Geography { OBJECTIVE_RADIUS, SECTOR_ONLY, OBJECTIVE_OR_SECTOR }

var unit: Unit = null
var team: int = -1
var objective_hex: Vector2i = Vector2i.ZERO
var profile: PositionProfile = PositionProfile.for_mode(PositionProfile.Mode.DEFEND)
var snapshot: InfluenceSnapshot = null
var forecast_data: PackedFloat32Array = PackedFloat32Array()
var geography: Geography = Geography.OBJECTIVE_OR_SECTOR
var defense_radius: int = 4
var movement_radius: int = 6
var sector_cells: Array[Vector2i] = []
var fallback_hexes: Array[Vector2i] = []
var reservations: Dictionary = {}
var has_accepted_target: bool = false
var accepted_target: Vector2i = Vector2i.ZERO
var accepted_context: String = ""
var axis: ThreatAxis = null
var include_score_map: bool = true
var max_alternatives: int = 5


func context_key() -> String:
	var axis_key: String = ""
	if axis != null:
		axis_key = axis.axis_name
	return str([team, objective_hex, profile.mode, axis_key, geography, defense_radius, movement_radius, sector_cells, fallback_hexes])
