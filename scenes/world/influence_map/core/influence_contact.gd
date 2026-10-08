class_name InfluenceContact
extends RefCounted

# Captured knowledge. Queries never read a hidden unit's live position.
var unit: Unit = null
var hex: Vector2i = Vector2i.ZERO
var confidence: float = 1.0
var firepower: float = 0.0
var effectiveness: float = 1.0
var weapon_range: int = 0
var observed: bool = false
