class_name PlatoonTask
extends RefCounted

var task_id: int = -1
var task_type: PlatoonTypes.TaskType = PlatoonTypes.TaskType.NONE

var target_hex: Vector2i = Vector2i.ZERO
var target_track_id: int = -1
var target_zone_id: int = -1

var required_role: PlatoonTypes.Role = PlatoonTypes.Role.NONE
var assigned_squad: Node = null

var priority: float = 0.0
var is_complete: bool = false
var is_locked: bool = false

func configure(
	p_task_id: int,
	p_task_type: PlatoonTypes.TaskType,
	p_target_hex: Vector2i,
	p_required_role: PlatoonTypes.Role,
	p_priority: float
) -> void:
	task_id = p_task_id
	task_type = p_task_type
	target_hex = p_target_hex
	required_role = p_required_role
	priority = clampf(p_priority, 0.0, 1.0)
	is_complete = false
	is_locked = false
