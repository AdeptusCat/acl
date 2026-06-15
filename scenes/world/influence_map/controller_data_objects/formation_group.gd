class_name FormationGroup
extends RefCounted

enum Role {
	FRONT,
	FLANK
}

var role: int = Role.FRONT
var seed_gradient: UnitInfluenceGradient = null
var seed_unit: Unit = null
var seed_hex: Vector2i = Vector2i.ZERO
var gradients: Array[UnitInfluenceGradient] = []
var units: Array[Unit] = []


func _init(
	p_role: int = Role.FRONT,
	p_seed_gradient: UnitInfluenceGradient = null
) -> void:
	role = p_role
	seed_gradient = p_seed_gradient

	if seed_gradient != null:
		seed_unit = seed_gradient.unit
		seed_hex = seed_gradient.from_hex
