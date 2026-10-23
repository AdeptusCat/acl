extends "res://autoloads/los_service.gd"

var baked_origins: int = 0
var editor_bake_saving_enabled: bool = true


func bake_los_origin(origin: Vector2i) -> Dictionary:
	baked_origins += 1
	return super.bake_los_origin(origin)


func _can_save_editor_baked_los(file_path: String) -> bool:
	return editor_bake_saving_enabled and super._can_save_editor_baked_los(file_path)
