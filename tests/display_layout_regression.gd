extends Node

const UNIT_SCENE: PackedScene = preload("res://scenes/game/units/unit.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud/battle_hud.tscn")
const STACK_CELL: Vector2i = Vector2i(3, 2)
const TEST_UI_SCALES: Array[float] = [0.75, 0.83, 1.0, 1.13, 1.25]

class ControllerProbe extends Node2D:
	var ground_layer: HexagonTileMapLayer
	var selected_unit: Unit
	var previous_selected_hex: Vector2i = Vector2i(-999, -999)
	var selected_hex_index: int = 0
	var end_game_handled: bool = false
	var continuing_after_end: bool = false
	var stacks: BattlefieldStacks
	signal hex_selected(cell: Vector2i, point: Vector2)
	signal show_unit_details_in_ui(unit: Unit)
	signal hide_unit_details_in_ui

	func _select_unit(unit: Unit) -> void:
		if is_instance_valid(selected_unit):
			selected_unit.deselect()
		selected_unit = unit
		unit.select()

	func _deselect_unit(unit: Unit) -> void:
		if selected_unit == unit:
			unit.deselect()
			selected_unit = null

	func cycle_stack_selection(cell: Vector2i, picked: Unit) -> bool:
		return stacks.cycle_selection(cell, picked)

	func click(point: Vector2) -> void:
		MatchInteractionHandler.on_mouse_button_left_pressed(self, point)

var checks: int = 0
var failures: int = 0
var hud: CanvasLayer
var root_control: Control
var controller: ControllerProbe
var camera: Camera2D
var units: Array[Unit] = []
var input: Node
var zoom_events: int = 0
var tested_layouts: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	name = "Main"
	DisplaySettings.preferences_path = ""
	DisplaySettings.set_ui_scale(1.0)
	_test_preferences()
	_build_fixture()
	await _settle()
	await _test_scale_slider()
	for resolution: Vector2i in DisplaySettings.WINDOW_PRESETS:
		get_window().size = resolution
		await _settle()
		if DisplayServer.get_name() != "headless" and get_window().size != resolution:
			print("Native render skipped: ", resolution, " capped by desktop to ", get_window().size, "; covered by headless matrix")
			continue
		for value: float in TEST_UI_SCALES:
			await _test_layout(resolution, value)
	if DisplayServer.get_name() != "headless":
		await _test_window_controls()
	DisplaySettings.set_ui_scale(1.0)
	for unit: Unit in units:
		unit.squad_fire.calc.free()
	print("Display layout checks: ", checks, "; failures: ", failures, "; layouts: ", tested_layouts)
	get_tree().quit(failures)


func _test_preferences() -> void:
	var path: String = "user://display-regression.cfg"
	_check(DisplaySettings.window_mode == Window.MODE_FULLSCREEN, "Fresh display settings default to fullscreen")
	DisplaySettings.preferences_path = path
	DisplaySettings.windowed_size = Vector2i(1472, 856)
	DisplaySettings.window_mode = Window.MODE_FULLSCREEN
	DisplaySettings.set_ui_scale(0.83)
	DisplaySettings.windowed_size = DisplaySettings.DESIGN_SIZE
	DisplaySettings.window_mode = Window.MODE_WINDOWED
	DisplaySettings.ui_scale = 1.0
	DisplaySettings.load_preferences()
	_check(DisplaySettings.windowed_size == Vector2i(1472, 856) and DisplaySettings.window_mode == Window.MODE_FULLSCREEN and is_equal_approx(DisplaySettings.ui_scale, 0.83), "Display preferences retain arbitrary slider percentages and a manually sized window")
	var config: ConfigFile = ConfigFile.new()
	config.set_value("display", "ui_scale", 0.75)
	config.save(path)
	DisplaySettings.load_preferences()
	_check(DisplaySettings.ui_scale == 1.0 and DisplaySettings.get_hud_scale() == 0.75, "The previous 75% preference migrates to the new 100% at the same physical size")
	_check(DisplaySettings.window_mode == Window.MODE_FULLSCREEN, "Preferences without a window mode default to fullscreen")
	DisplaySettings.save_preferences()
	DisplaySettings.ui_scale = 1.25
	DisplaySettings.load_preferences()
	_check(DisplaySettings.ui_scale == 1.0, "Reloading a migrated preference cannot rebase it twice")
	config.clear()
	config.set_value("display", "fullscreen", false)
	config.save(path)
	DisplaySettings.load_preferences()
	_check(DisplaySettings.ui_scale == 1.0, "A missing scale preference retains the new 100% default")
	_check(DisplaySettings.window_mode == Window.MODE_WINDOWED, "An explicitly saved windowed preference overrides the fullscreen default")
	config.clear()
	config.set_value("display", "windowed_size", Vector2i(-2, 200))
	config.set_value("display", "ui_scale", "invalid")
	config.set_value("display", "fullscreen", "invalid")
	config.save(path)
	DisplaySettings.ui_scale = 1.0
	DisplaySettings.load_preferences()
	_check(DisplaySettings.windowed_size == DisplaySettings.DESIGN_SIZE and DisplaySettings.ui_scale == 1.0 and DisplaySettings.window_mode == Window.MODE_FULLSCREEN, "Invalid preferences retain supported sizes, scaling, and the fullscreen default")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DisplaySettings.preferences_path = ""
	DisplaySettings.set_window_mode(Window.MODE_WINDOWED)
	DisplaySettings.set_ui_scale(1.0)


func _test_scale_slider() -> void:
	var settings: Control = root_control.get_node("Settings")
	var slider: HSlider = settings.scale_slider
	_check(slider.min_value == 75.0 and slider.max_value == 125.0 and slider.step == 1.0, "Interface-size slider covers 75–125% in 1% increments")
	_check(DisplaySettings.get_hud_scale() == 0.75 and hud.scale == Vector2.ONE * 0.75, "The new 100% renders at the former 75% HUD size")
	for percent: float in [75.0, 83.0, 100.0, 125.0]:
		slider.value = percent
		await _settle()
		_check(is_equal_approx(DisplaySettings.ui_scale, percent / 100.0) and settings.scale_label.text.ends_with("%d%%" % roundi(percent)), "Slider applies %d%% and displays its percentage" % roundi(percent))
	DisplaySettings.set_ui_scale(-1.0)
	_check(DisplaySettings.ui_scale == 0.75 and slider.value == 75.0 and DisplaySettings.get_hud_scale() == 0.5625, "The new 75% minimum renders at the former 56.25% size")
	DisplaySettings.set_ui_scale(4.0)
	_check(DisplaySettings.ui_scale == 1.25 and slider.value == 125.0 and DisplaySettings.get_hud_scale() == 0.9375, "The new 125% maximum renders at the former 93.75% size")
	DisplaySettings.set_ui_scale(NAN)
	DisplaySettings.set_ui_scale(INF)
	_check(DisplaySettings.ui_scale == 1.25, "Non-finite scales cannot corrupt the HUD transform")
	DisplaySettings.set_ui_scale(1.0)
	settings.settings_button.button_pressed = true
	await _settle()
	settings.menu_scroll.ensure_control_visible(slider)
	await _settle()
	var zoom_before: Vector2 = camera.zoom
	var start: Vector2 = slider.get_global_transform_with_canvas() * (slider.size * 0.5)
	_mouse(start, MOUSE_BUTTON_LEFT, true)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = slider.get_global_transform_with_canvas() * Vector2(slider.size.x * 0.25, slider.size.y * 0.5)
	motion.global_position = motion.position
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	await _settle()
	_check(slider.value < 100.0 and DisplaySettings.ui_scale == 1.0 and settings.menu.visible, "Dragging previews a smaller percentage while keeping the HUD and slider stationary")
	_mouse(motion.position, MOUSE_BUTTON_LEFT, false)
	await _settle()
	_check(is_equal_approx(DisplaySettings.ui_scale, slider.value / 100.0) and DisplaySettings.ui_scale < 1.0 and camera.zoom == zoom_before, "Releasing the slider applies its percentage independently of camera zoom")
	slider.grab_focus()
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.pressed = true
	var before: float = slider.value
	get_viewport().push_input(key, true)
	await _settle()
	_check(slider.value == before + 1.0 and is_equal_approx(DisplaySettings.ui_scale, slider.value / 100.0), "Keyboard input adjusts and applies the interface size in 1% steps")
	key.pressed = false
	get_viewport().push_input(key, true)
	slider.release_focus()
	var scale_before_close: float = DisplaySettings.ui_scale
	_mouse(slider.get_global_transform_with_canvas() * (slider.size * 0.5), MOUSE_BUTTON_LEFT, true)
	settings.close_panels()
	_mouse(motion.position, MOUSE_BUTTON_LEFT, false)
	await _settle()
	_check(is_equal_approx(DisplaySettings.ui_scale, scale_before_close) and not settings._scale_dragging, "Closing settings during a drag cancels its preview and clears the drag state")
	slider.value = 83.0
	await _settle()
	_check(is_equal_approx(DisplaySettings.ui_scale, 0.83), "The slider remains usable after a cancelled drag")
	DisplaySettings.set_ui_scale(1.0)
	await _settle()


func _test_window_controls() -> void:
	var settings: Control = root_control.get_node("Settings")
	DisplaySettings.preferences_path = "user://display-regression.cfg"
	_check(get_window().min_size == DisplaySettings.DESIGN_SIZE and not get_window().unresizable, "Native window enforces the supported minimum and allows manual resizing")
	DisplaySettings.set_windowed_size(Vector2i(1472, 856))
	await get_tree().create_timer(0.4).timeout
	var custom_size: Vector2i = get_window().size
	_check(custom_size == Vector2i(1472, 856), "Windowed mode accepts a manual size")
	settings.mode_selector.item_selected.emit(settings.mode_selector.get_item_index(Window.MODE_FULLSCREEN))
	await get_tree().create_timer(0.4).timeout
	_check(get_window().mode == Window.MODE_FULLSCREEN and settings.resolution_selector.disabled, "Fullscreen controls switch the native window and disable window presets")
	_check(get_window().size.x == DisplayServer.screen_get_size().x and absi(get_window().size.y - DisplayServer.screen_get_size().y) <= 1, "Fullscreen uses the desktop resolution")
	_check(DisplaySettings.windowed_size == custom_size, "Fullscreen never overwrites the remembered windowed size")
	settings.mode_selector.item_selected.emit(settings.mode_selector.get_item_index(Window.MODE_WINDOWED))
	await get_tree().create_timer(0.4).timeout
	_check(get_window().size == custom_size and not settings.resolution_selector.disabled, "Returning to windowed mode restores the previous size")
	get_window().size = Vector2i(1500, 900)
	await get_tree().create_timer(0.4).timeout
	var config: ConfigFile = ConfigFile.new()
	config.load(DisplaySettings.preferences_path)
	_check(DisplaySettings.windowed_size == Vector2i(1500, 900) and config.get_value("display", "windowed_size") == Vector2i(1500, 900), "Manual native resizing updates the saved window preference")
	settings.scale_slider.value = 75.0
	await _settle()
	_check(DisplaySettings.ui_scale == 0.75, "The interface-size slider applies its setting")
	DisplaySettings.preferences_path = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://display-regression.cfg"))


func _build_fixture() -> void:
	Globals.team_player = Globals.Team.AXIS
	var world: Node2D = Node2D.new()
	world.name = "World"
	add_child(world)
	var audio: AudioPool = AudioPool.new()
	audio.name = "AudioPool"
	world.add_child(audio)
	controller = ControllerProbe.new()
	world.add_child(controller)
	var template: HexagonTileMapLayer = load("res://scenes/world/maps/layers/ground_tile_map_layer.tscn").instantiate() as HexagonTileMapLayer
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.pathfinding_enabled = false
	ground.tile_set = template.tile_set
	template.free()
	controller.add_child(ground)
	controller.ground_layer = ground
	for x: int in range(10):
		for y: int in range(7):
			ground.set_cell(Vector2i(x, y), 1, Vector2i.ZERO)
	camera = Camera2D.new()
	world.add_child(camera)
	hud = HUD_SCENE.instantiate() as CanvasLayer
	add_child(hud)
	root_control = hud.get_node("Control") as Control
	hud.ground_layer = ground
	hud.setup()
	for index: int in range(3):
		var unit: Unit = UNIT_SCENE.instantiate() as Unit
		unit.squad = index + 1
		unit.platoon = 1
		unit.team = Globals.Team.AXIS
		controller.add_child(unit)
		unit.current_hex = STACK_CELL
		unit.current_cube = ground.map_to_cube(STACK_CELL)
		unit.global_position = ground.to_global(ground.map_to_local(STACK_CELL)) + Vector2(0.0, float(index - 1) * 16.0)
		unit.movement.unit = unit
		unit.action_controller.init(unit, unit.movement, unit.squad_fire, unit.stress_system, unit.ui)
		unit._setup_runtime_soldiers(unit.squad_loadout)
		unit.ui.update_team_sprite(unit.team, unit.squad_type)
		_freeze(unit)
		unit.add_to_group("units")
		units.append(unit)
	controller.stacks = BattlefieldStacks.new()
	controller.add_child(controller.stacks)
	controller.stacks.setup(controller)
	controller.show_unit_details_in_ui.connect(hud._on_show_unit_details)
	var conditions: Array[VictoryCondition] = []
	for index: int in range(24):
		var condition: DestroyUnitsCondition = DestroyUnitsCondition.new()
		condition.team = Globals.Team.AXIS
		conditions.append(condition)
	hud.show_mission_objectives(conditions, Globals.Team.AXIS, 300.0)
	hud.show_squad_roster(Globals.Team.AXIS)
	hud.show_tile_data({"hex": STACK_CELL, "tile_name": "Open ground"})
	input = load("res://scenes/game/input/input_manager.tscn").instantiate()
	add_child(input)
	input.set_battle_input_enabled(true)
	input.mouse_button_left_pressed.connect(controller.click)
	input.zoom_in.connect(func() -> void: zoom_events += 1)
	var tooltip: Control = root_control.get_node("Tooltip")
	tooltip.set_process(false)


func _test_layout(resolution: Vector2i, value: float) -> void:
	tested_layouts += 1
	var settings: Control = root_control.get_node("Settings")
	settings.close_panels()
	hud.hide_order_feedback()
	hud.hide_target_hex_cover_distance()
	var zoom_before: Vector2 = camera.zoom
	DisplaySettings.set_ui_scale(value)
	await _settle()
	var context: String = "%s at %d%%" % [resolution, roundi(value * 100.0)]
	_check(get_window().size == resolution, context + ": output uses the requested resolution")
	_check(camera.zoom == zoom_before and get_window().content_scale_factor == 1.0, context + ": UI scale leaves battlefield zoom and root stretch unchanged")
	_check((root_control.size * value * 0.75).is_equal_approx(get_viewport().get_visible_rect().size), context + ": rebased HUD fills the logical viewport")
	camera.position = controller.ground_layer.to_global(controller.ground_layer.map_to_local(STACK_CELL))
	camera.zoom = Vector2.ONE * 0.8
	camera.force_update_scroll()
	controller._select_unit(units[0])
	hud.unit_details.show_unit_detail(units[0], false)
	await _settle()
	var panels: Array[Control] = [hud.retry_panel, hud.countdown_panel_container, settings, hud.squad_roster, hud.mission_objectives, hud.unit_details, hud.tile_details, hud.debug_panel]
	for index: int in range(panels.size()):
		_check(_inside(panels[index]), context + ": " + panels[index].name + " stays onscreen")
		for other: int in range(index + 1, panels.size()):
			_check(not panels[index].get_rect().intersects(panels[other].get_rect()), context + ": " + panels[index].name + " avoids " + panels[other].name)
	var field_width: float = hud.unit_details.position.x - hud.squad_roster.get_rect().end.x
	_check(field_width >= root_control.size.x * 0.25, context + ": side panels preserve central battlefield space")
	hud.mission_objectives.section.expand()
	await _settle()
	_check(hud.mission_objectives.scroll.size.y < hud.mission_objectives.rows.size.y and _inside(hud.mission_objectives), context + ": long objective lists scroll within their bound")
	await _test_panel_height_limits(context)
	if root_control.size.x < 1100.0 or root_control.size.y < 620.0:
		hud.mission_objectives.section.fold()
	await _settle()
	var tooltip: Control = root_control.get_node("Tooltip")
	tooltip.show()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	for point: Vector2 in [Vector2.ONE, Vector2(viewport_size.x - 1.0, 1.0), viewport_size - Vector2.ONE, Vector2(1.0, viewport_size.y - 1.0)]:
		tooltip.place_at(point)
		_check(_inside(tooltip), context + ": tooltip fits at edge " + str(point))
		hud.show_target_hex_cover_distance(point, 1, 2, 1.0)
		await _settle()
		_check(_inside(hud.target_cover_distance), context + ": target hint fits at edge " + str(point))
	tooltip.hide()
	hud.hide_target_hex_cover_distance()
	var wheel: Control = hud.selection_wheel_alt
	var point: Vector2 = viewport_size * 0.5
	wheel.open(point)
	await _settle()
	_check((wheel.get_global_transform_with_canvas() * Vector2.ZERO).is_equal_approx(point), context + ": wheel opens at the pointer")
	for index: int in range(wheel.options.size()):
		wheel.select_at(wheel.get_global_transform_with_canvas() * wheel.get_option_point(index))
		_check(wheel.selection == index, context + ": wheel sector " + str(index) + " follows scaled input")
	wheel.cancel()
	# This uses the real input pipeline and the world's canvas, independently of HUD scale.
	point = BattlefieldStacks.counter_rect(units[1]).get_center()
	_click(point)
	await _settle()
	_check(controller.selected_unit == units[1], context + ": battlefield clicks cycle the selected stack")
	_check(not root_control.has_node("HexStackRoster"), context + ": stack selection adds no floating squad panel")
	_click(point)
	_check(controller.selected_unit == units[2], context + ": repeated clicks reach every squad without a floating panel")
	_click(settings.settings_button.get_global_transform_with_canvas() * (settings.settings_button.size * 0.5))
	await _settle()
	_check(settings.menu.visible and _inside(settings.menu), context + ": scaled Settings button opens a contained, scrollable menu")
	var zoom_count: int = zoom_events
	_mouse(settings.menu.get_global_transform_with_canvas() * (settings.menu.size * 0.5), MOUSE_BUTTON_WHEEL_UP, true)
	_check(zoom_events == zoom_count and settings.menu.visible, context + ": scrolling settings keeps the menu open and cannot zoom the battlefield")
	_check(is_equal_approx(settings.scale_slider.value, value * 100.0) and settings.scale_label.text.ends_with("%d%%" % roundi(value * 100.0)), context + ": display controls reflect the chosen UI size")
	if OS.get_cmdline_user_args().has("--capture") and resolution == DisplaySettings.DESIGN_SIZE and value == 1.25:
		settings.menu_scroll.ensure_control_visible(settings.scale_slider)
		await _settle()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/acl-display-settings-125.png")
	settings.close_panels()
	hud.show_order_feedback(true, "Move", "Squad moving to its destination")
	await _settle()
	_check(_inside(root_control.get_node("OrderFeedback")), context + ": command feedback remains onscreen")
	_check(settings.settings_button.get_theme_font_size("font_size") >= 13, context + ": HUD uses readable base type")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/acl-display-%dx%d-%d.png" % [resolution.x, resolution.y, roundi(value * 100.0)])


func _test_panel_height_limits(context: String) -> void:
	var sections: Array[FoldableContainer] = [hud.squad_roster.section, hud.tile_details.details, hud.unit_details.details_section, hud.unit_details.roster_section, hud.mission_objectives.section]
	var folded_before: Dictionary[FoldableContainer, bool] = {}
	for section: FoldableContainer in sections:
		folded_before[section] = section.folded
		section.expand()
	var spacers: Array[Control] = []
	for content: Control in [hud.squad_roster.groups, hud.tile_details.breakdown, hud.unit_details.summary, hud.mission_objectives.rows]:
		# Force overflow so every panel must use its full allowance at every scale.
		var spacer: Control = Control.new()
		spacer.custom_minimum_size.y = root_control.size.y
		content.add_child(spacer)
		spacers.append(spacer)
	await _settle()
	var panels: Array[Control] = [hud.squad_roster, hud.tile_details, hud.unit_details, hud.mission_objectives]
	var expected_height: float = get_viewport().get_visible_rect().size.y / 3.0
	for panel: Control in panels:
		var rendered: Rect2 = panel.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, panel.size)
		_check(absf(rendered.size.y - expected_height) <= 2.0, context + ": expanded " + panel.name + " uses one-third of the screen independently of HUD scale: " + str(rendered.size.y))
		_check(_inside(panel), context + ": expanded " + panel.name + " stays onscreen")
	for index: int in range(panels.size()):
		for other: int in range(index + 1, panels.size()):
			_check(not panels[index].get_rect().intersects(panels[other].get_rect()), context + ": expanded " + panels[index].name + " avoids " + panels[other].name)
	for scroll: ScrollContainer in [hud.squad_roster.scroll, hud.tile_details.scroll, hud.unit_details.summary_scroll, hud.mission_objectives.scroll]:
		_check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, context + ": excess panel content remains scrollable")
	for spacer: Control in spacers:
		spacer.get_parent().remove_child(spacer)
		spacer.queue_free()
	for section: FoldableContainer in sections:
		if folded_before[section]:
			section.fold()
	await _settle()


func _inside(panel: Control) -> bool:
	return Rect2(Vector2.ZERO, root_control.size).grow(0.1).encloses(root_control.get_global_transform().affine_inverse() * panel.get_global_rect())


func _click(point: Vector2) -> void:
	_mouse(point, MOUSE_BUTTON_LEFT, true)
	_mouse(point, MOUSE_BUTTON_LEFT, false)


func _mouse(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	get_viewport().push_input(event, true)


func _settle() -> void:
	for frame: int in range(8):
		await get_tree().process_frame


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer:
		(node as Timer).stop()
	for child: Node in node.get_children():
		_freeze(child)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
