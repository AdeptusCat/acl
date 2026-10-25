extends Node2D

@export var world_scene: PackedScene
var world: Node2D
var _returning_to_menu: bool = false


func _ready() -> void:
	world = world_scene.instantiate()
	world.try_again.connect(_on_try_again)
	world.fully_freed.connect(_on_fully_freed)
	add_child(world)
	world.start_screen.show()

func _on_try_again() -> void:
	if _returning_to_menu:
		return
	_returning_to_menu = true
	Globals.game_started = false
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.input_manager.set_battle_input_enabled(false)
	await LoadingScreen.show_loading("Loading main menu...")
	world.queue_free()


func _on_fully_freed() -> void:
	if not _returning_to_menu:
		return
	await get_tree().process_frame
	world = world_scene.instantiate()
	world.try_again.connect(_on_try_again)
	world.fully_freed.connect(_on_fully_freed)
	add_child(world)
	world.start_screen.show()
	await get_tree().process_frame
	LoadingScreen.hide_loading()
	_returning_to_menu = false
