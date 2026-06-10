class_name ThreatAxis
extends Resource

enum AxisType {
	CONFIRMED,
	SUSPECTED,
	SCRIPTED,
}

@export var axis_name: String = ""
@export var axis_type: AxisType = AxisType.SCRIPTED

# Where the enemy pressure is coming from.
@export var source_hex: Vector2i = Vector2i.ZERO

# What the axis threatens.
@export var target_hex: Vector2i = Vector2i.ZERO

# Hexes that roughly describe the approach lane.
@export var approach_hexes: Array[Vector2i] = []

# Optional sector cells influenced by this axis.
@export var influence_cells: Array[Vector2i] = []

# Estimated enemy info.
@export var estimated_enemy_count: int = 0
@export var estimated_firepower: float = 0.0

# Confidence: 0.0 = guess, 1.0 = confirmed.
@export var confidence: float = 1.0

# Tactical scoring inputs.
@export var proximity_to_objective: float = 0.0
@export var attack_lane_quality: float = 0.0
@export var flank_danger: float = 0.0
@export var time_pressure: float = 0.0

var score: float = 0.0


func recompute_score() -> void:
	var strength_score: float = float(estimated_enemy_count) + estimated_firepower

	score = strength_score
	score *= confidence
	score *= 1.0 + proximity_to_objective
	score *= 1.0 + attack_lane_quality
	score *= 1.0 + flank_danger
	score *= 1.0 + time_pressure


func is_valid_axis() -> bool:
	if source_hex == target_hex:
		return false

	if confidence <= 0.0:
		return false

	return true


func get_primary_pressure_hex() -> Vector2i:
	if approach_hexes.size() > 0:
		return approach_hexes[0]

	return source_hex
