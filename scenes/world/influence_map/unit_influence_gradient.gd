class_name UnitInfluenceGradient
extends RefCounted

var unit: Unit = null
var from_hex: Vector2i = Vector2i.ZERO
var next_hex: Vector2i = Vector2i.ZERO
var value_here: float = 0.0
var value_next: float = 0.0
var influence_gain: float = 0.0


func _init(
	p_unit: Unit = null,
	p_from_hex: Vector2i = Vector2i.ZERO,
	p_next_hex: Vector2i = Vector2i.ZERO,
	p_value_here: float = 0.0,
	p_value_next: float = 0.0
) -> void:
	unit = p_unit
	from_hex = p_from_hex
	next_hex = p_next_hex
	value_here = p_value_here
	value_next = p_value_next
	influence_gain = value_next - value_here
