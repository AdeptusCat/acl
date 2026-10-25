extends Node

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplaySettings.preferences_path = ""
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _settle()
	_check(not LoadingScreen.visible, "The mission menu starts without a loading overlay")
	var splash: TextureRect = LoadingScreen.get_node("Control/Splash")
	var boot_image: String = str(ProjectSettings.get_setting("application/boot_splash/image"))
	_check(splash.texture == load(boot_image), "Loading uses the configured boot splash image")
	_check(LoadingScreen.layer > main.world.result_screen.layer, "Loading covers menus, battle HUD and results")
	var world: Node = main.world
	var map: Map = world.maps.get_node("Alderbrook1") as Map
	var scenario: Scenario = map.get_scenario(0)
	scenario.axis_ai_status = Scenario.AIStatus.OFF
	scenario.allies_ai_status = Scenario.AIStatus.OFF
	world.start_screen._on_scenario_button_pressed(map, scenario)
	world.start_screen._on_start_mission_pressed()
	_check(await _wait_loading(true), "Launching a mission shows loading before map setup finishes")
	_check(not world.input_manager._battle_input_enabled, "Battle input stays disabled during loading")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	get_viewport().push_input(key, true)
	_check(get_viewport().is_input_handled(), "Loading consumes keyboard input")
	key.pressed = false
	get_viewport().push_input(key, true)
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("battlefield")
	_check(await _wait_loading(false), "The overlay closes when the battlefield is ready")
	_check(world.is_setup and world.input_manager._battle_input_enabled and not world.start_screen.visible, "The loaded battle replaces the mission menu and restores input")
	var old_world_id: int = world.get_instance_id()
	main._on_try_again()
	_check(LoadingScreen.visible and is_instance_valid(world), "Returning shows the splash before freeing the active world")
	_check(world.process_mode == Node.PROCESS_MODE_DISABLED and not world.input_manager._battle_input_enabled, "The departing battle stops while the menu loads")
	main._on_try_again()
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("menu")
	_check(await _wait_loading(false), "Returning finishes loading the replacement menu")
	_check(is_instance_valid(main.world) and main.world.get_instance_id() != old_world_id and not is_instance_valid(world), "The transition replaces and frees the old world")
	_check(main.world.start_screen.visible and not main.world.is_setup and not main._returning_to_menu, "The replacement mission menu is ready before input resumes")
	_check(main.get_child_count() == 1, "Repeated return requests create only one replacement world")
	_check(LOSHelper.ground_layer == null and LOSHelper.los_lookup.is_empty(), "Returning releases the old mission's LOS data")
	main.queue_free()
	await _settle()
	_check(not LoadingScreen.visible, "Normal scene teardown leaves no loading overlay behind")
	print("Loading screen checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _wait_loading(expected: bool) -> bool:
	for frame: int in range(180):
		if LoadingScreen.visible == expected:
			return true
		await get_tree().process_frame
	return false


func _capture(label: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_check(image.save_png("/tmp/acl-loading-%s.png" % label) == OK, "The loading screen is captured")


func _settle() -> void:
	for frame: int in range(6):
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
