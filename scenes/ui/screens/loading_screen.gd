extends CanvasLayer

@onready var status: Label = $Control/Status


func _ready() -> void:
	set_process_input(false)


func show_loading(message: String = "Loading...") -> void:
	status.text = message
	show()
	set_process_input(true)
	# Present the splash before synchronous map setup or world teardown blocks a frame.
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	# Give the browser a chance to present that frame before resuming heavy work.
	await get_tree().process_frame


func hide_loading() -> void:
	hide()
	set_process_input(false)


func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
