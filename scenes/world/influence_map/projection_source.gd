class_name ProjectionSource
extends RefCounted

var unit: Unit = null
var observer_hex: Vector2i = Vector2i.ZERO
var firepower: float = 0.0
var effectiveness: float = 0.0


func _init(
	p_unit: Unit = null,
	p_observer_hex: Vector2i = Vector2i.ZERO,
	p_firepower: float = 0.0,
	p_effectiveness: float = 0.0
) -> void:
	unit = p_unit
	observer_hex = p_observer_hex
	firepower = p_firepower
	effectiveness = p_effectiveness
