extends "res://autoloads/los_service.gd"

var baked_origins: int = 0


func bake_los_origin(origin: Vector2i) -> Dictionary:
	baked_origins += 1
	return super.bake_los_origin(origin)
