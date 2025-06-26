extends Node2D

@export var world_scene: PackedScene
var world

func _ready() -> void:
	world = world_scene.instantiate()
	world.try_again.connect(_on_try_again)
	world.fully_freed.connect(_on_fully_freed)
	add_child(world)


func _on_try_again():
	world.queue_free()


func _on_fully_freed():
	await get_tree().process_frame
	world = world_scene.instantiate()
	world.try_again.connect(_on_try_again)
	world.fully_freed.connect(_on_fully_freed)
	add_child(world)
