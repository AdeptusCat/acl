extends Node

const UNIT_SCENE: PackedScene = preload("res://scenes/game/units/unit.tscn")
const STACK_SCRIPT: Script = preload("res://scenes/world/overlays/battlefield_stacks.gd")
const COMMAND_SCRIPT: Script = preload("res://scenes/world/overlays/command_connectivity_renderer.gd")

class ControllerProbe extends Node2D:
	var ground_layer: HexagonTileMapLayer
	var selected_unit: Unit
	var previous_selected_hex: Vector2i = Vector2i(-999, -999)
	var selected_hex_index: int = 0
	var end_game_handled: bool = false
	var stacks: BattlefieldStacks
	var map_clicks: int = 0
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

	func cycle_stack_roster(cell: Vector2i, picked: Unit) -> bool:
		return stacks.cycle_roster(cell, picked)

	func click(point: Vector2) -> void:
		map_clicks += 1
		MatchInteractionHandler.on_mouse_button_left_pressed(self, point)


var checks: int = 0
var failures: int = 0
var zooms: int = 0
var units: Array[Unit] = []
var controller: ControllerProbe
var stacks: BattlefieldStacks
var commands: CommandConnectivityRenderer
var hud: Control
var first: Unit
var second: Unit
var third: Unit
var headquarters: Unit
var single: Unit
var stack_cell: Vector2i = Vector2i(3, 2)
var snapshots: Dictionary[int, Dictionary] = {}


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--render"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_run.call_deferred()


func _run() -> void:
	name = "Main"
	get_tree().root.size = Vector2i(1152, 648)
	Globals.team_player = Globals.Team.AXIS
	Debug.enemy_selectable = false
	SessionSettings.showCmdConnectivity = false
	var world: Node2D = Node2D.new()
	world.name = "World"
	add_child(world)
	var audio: AudioPool = AudioPool.new()
	audio.name = "AudioPool"
	world.add_child(audio)
	controller = ControllerProbe.new()
	controller.position = Vector2(37.0, 19.0)
	world.add_child(controller)
	var template: HexagonTileMapLayer = (load("res://scenes/world/maps/layers/ground_tile_map_layer.tscn") as PackedScene).instantiate() as HexagonTileMapLayer
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.pathfinding_enabled = false
	ground.tile_set = template.tile_set
	template.free()
	ground.position = Vector2(79.0, 53.0)
	ground.z_index = -10
	controller.add_child(ground)
	controller.ground_layer = ground
	var previous_ground: HexagonTileMapLayer = LOSHelper.ground_layer
	LOSHelper.ground_layer = ground
	for x: int in range(10):
		for y: int in range(7):
			ground.set_cell(Vector2i(x, y), 1, Vector2i.ZERO)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	hud = Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var input: Node = (load("res://scenes/game/input/input_manager.tscn") as PackedScene).instantiate()
	add_child(input)
	input.set_battle_input_enabled(true)
	input.mouse_button_left_pressed.connect(controller.click)
	input.zoom_in.connect(func() -> void: zooms += 1)
	first = _unit(stack_cell, 1, Globals.SquadType.Rifle, Vector2(0.0, -16.0))
	second = _unit(stack_cell, 2, Globals.SquadType.MG)
	third = _unit(stack_cell, 3, Globals.SquadType.Rifle, Vector2(0.0, 16.0))
	headquarters = _unit(Vector2i(6, 2), 0, Globals.SquadType.PLATOON_HEADQUARTERS)
	single = _unit(Vector2i(2, 2), 4, Globals.SquadType.Rifle)
	for unit: Unit in [first, second, third, single]:
		unit.command_squad = headquarters
		unit.command_connectivity.runner_chain_to_leader = true
	for unit: Unit in units:
		snapshots[unit.get_instance_id()] = {"transform": unit.global_transform, "hex": unit.current_hex, "cube": unit.current_cube, "ui_transform": unit.ui.get_global_transform()}
	stacks = STACK_SCRIPT.new() as BattlefieldStacks
	controller.add_child(stacks)
	controller.stacks = stacks
	stacks.setup(controller, hud)
	stacks.set_process(false)
	commands = COMMAND_SCRIPT.new() as CommandConnectivityRenderer
	controller.add_child(commands)
	commands.setup()
	commands.set_process(false)
	await _settle()
	_test_preserved_stack()
	await _test_arrival_popup()
	_test_enemy_visibility()
	await _test_pointer_and_selection()
	await _test_outside_hud_click()
	await _test_shared_hq()
	await _test_live_updates_and_large_stacks()
	_test_model_positions()
	_test_removal_and_cleanup()
	for unit: Unit in units:
		unit.squad_fire.calc.free()
	LOSHelper.ground_layer = previous_ground
	world.free()
	layer.free()
	print("Stacked squad checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _unit(cell: Vector2i, number: int, type: Globals.SquadType, offset: Vector2 = Vector2.ZERO) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.squad = number
	unit.platoon = 1
	unit.squad_type = type
	controller.add_child(unit)
	unit.current_hex = cell
	unit.current_cube = controller.ground_layer.map_to_cube(cell)
	unit.global_position = controller.ground_layer.to_global(controller.ground_layer.map_to_local(cell)) + offset
	unit.movement.unit = unit
	unit.action_controller.init(unit, unit.movement, unit.squad_fire, unit.stress_system, unit.ui)
	unit._setup_runtime_soldiers(unit.squad_loadout)
	unit.stress_system.state_changed.connect(unit._on_state_changed)
	unit.ui.update_team_sprite(unit.team, type)
	_freeze(unit)
	unit.add_to_group("units")
	units.append(unit)
	return unit


func _test_preserved_stack() -> void:
	_check(hud.get_child_count() == 1 and hud.get_child(0) == stacks.roster, "Stack interaction adds only the roster, with no squad-count indicator")
	_check(not stacks.roster.visible, "Existing stacks do not open a roster during setup")
	_check(Globals.get_units().size() == units.size(), "Stack interaction does not create gameplay units")
	for unit: Unit in [first, second, third]:
		_check(unit.ui.modulate.a == 1.0 and unit.ui.is_visible_in_tree(), "Each slightly offset squad counter remains visible")
	_check(single.ui.modulate.a == 1.0, "Single squads retain their normal counter")
	_test_model_positions()


func _test_arrival_popup() -> void:
	var mover: Unit = _unit(Vector2i(1, 4), 7, Globals.SquadType.Rifle)
	stacks.refresh()
	controller._select_unit(second)
	_move_to(mover, Vector2i(1, 5))
	_check(not stacks.roster.visible, "Moving into an empty hex does not open a roster")
	_move_to(mover, headquarters.current_hex)
	await _settle()
	_check(stacks.roster.visible and stacks.roster.cell == headquarters.current_hex and stacks.roster.rows.size() == 2, "A real movement entry into a friendly squad's hex opens the two-squad roster")
	_check(controller.selected_unit == second and mover.current_hex == headquarters.current_hex and mover.current_cube == headquarters.current_cube, "An arrival popup preserves selection and the movement system's occupied hex")
	_check(mover.global_position.is_equal_approx(controller.ground_layer.to_global(controller.ground_layer.map_to_local(mover.current_hex))), "Opening the arrival roster leaves the movement endpoint unchanged")
	stacks.roster.close()
	for frame: int in range(3):
		stacks.refresh()
		await get_tree().process_frame
	_move_to(mover, mover.current_hex)
	_check(not stacks.roster.visible, "Dismissing an arrival roster keeps it closed through refresh and same-hex recentering")
	_move_to(mover, stack_cell)
	await _settle()
	_check(stacks.roster.visible and stacks.roster.cell == stack_cell and stacks.roster.rows.size() == 4 and stacks.roster.rows[second.get_instance_id()].button_pressed, "A later entry into a larger stack reopens its roster with the existing selection highlighted")
	stacks.roster.close()
	var enemy: Unit = _unit(Vector2i(1, 4), 8, Globals.SquadType.Rifle)
	enemy.team = Globals.get_enemy_team(Globals.team_player)
	stacks.refresh()
	_move_to(enemy, stack_cell)
	_check(not stacks.roster.visible, "Enemy movement does not open a friendly stack roster")
	var hidden: Unit = _unit(Vector2i(1, 4), 9, Globals.SquadType.Rifle)
	hidden.hide()
	stacks.refresh()
	_move_to(hidden, stack_cell)
	_check(not stacks.roster.visible and not hidden.is_visible_in_tree(), "Hidden units cannot reveal a stack through automatic popups")
	mover.exited = true
	mover.unit_entered_hex.emit(mover, stack_cell)
	_check(not stacks.roster.visible, "Exited units cannot open an arrival roster")
	mover.exited = false
	controller.end_game_handled = true
	_move_to(mover, headquarters.current_hex)
	_check(not stacks.roster.visible, "Movement after the match ends cannot open a roster")
	controller.end_game_handled = false
	for unit: Unit in [mover, enemy, hidden]:
		units.erase(unit)
		unit.squad_fire.calc.free()
		unit.free()
	stacks.refresh()
	controller._deselect_unit(second)
	_test_model_positions()


func _move_to(unit: Unit, cell: Vector2i) -> void:
	unit.goal_hex = cell
	unit.movement.target_position = controller.to_local(controller.ground_layer.to_global(controller.ground_layer.map_to_local(cell)))
	unit.movement.is_moving = true
	unit.movement._process_movement(100.0)


func _test_pointer_and_selection() -> void:
	var center: Vector2 = controller.ground_layer.to_global(controller.ground_layer.map_to_local(stack_cell))
	for zoom: float in [0.5, 1.0, 2.0]:
		var canvas: Transform2D = Transform2D.IDENTITY.scaled(Vector2(zoom, zoom))
		canvas.origin = Vector2(350.0, 270.0) - center * zoom
		get_viewport().canvas_transform = canvas
		stacks.refresh()
		await _settle()
		stacks.refresh()
		if is_instance_valid(controller.selected_unit):
			controller._deselect_unit(controller.selected_unit)
		var point: Vector2 = BattlefieldStacks.counter_rect(second).get_center()
		_click(point)
		await _settle()
		_check(stacks.roster.visible and stacks.roster.rows.size() == 3, "One battlefield click opens all occupants after zoom and pan %.1f" % zoom)
		_check(controller.selected_unit == third and stacks.roster.rows[third.get_instance_id()].button_pressed, "The first stack click selects the front counter and its roster row at zoom %.1f" % zoom)
		for expected: Unit in [first, second, third]:
			_click(point)
			await _settle()
			commands.refresh(0.0)
			_check(stacks.roster.visible and controller.selected_unit == expected and stacks.roster.rows[expected.get_instance_id()].button_pressed, "Repeated clicks cycle through every squad and wrap the roster selection at zoom %.1f" % zoom)
			_check(commands.displayed_links == [expected] and commands.highlighted_units.has(headquarters.get_instance_id()), "Every cycle step updates the selected squad's HQ connection")
		var row: SquadRosterRow = stacks.roster.rows[second.get_instance_id()]
		_check(row.identity.text.contains("/1/2") and row.identity.text.contains("MG") and row.command_status.visible, "Stack rows show unique formation identifiers, type and command status")
		_click(row.get_global_transform_with_canvas() * (row.size * 0.5))
		await _settle()
		stacks.refresh()
		commands.refresh(0.0)
		_check(controller.selected_unit == second and second.selected and not first.selected and not third.selected, "A roster row selects the exact squad at zoom %.1f" % zoom)
		_check(commands.displayed_links == [second] and commands.highlighted_units.has(headquarters.get_instance_id()), "Exact stack selection highlights its commanding HQ")
		_check(commands.counter_rect(second).is_equal_approx(BattlefieldStacks.counter_rect(second)), "Command links retain the selected squad's original counter origin")
		_check(Rect2(Vector2.ZERO, hud.size).encloses(stacks.roster.get_rect()), "The roster stays within the HUD after pan and zoom")
		_check(not stacks.roster.get_rect().intersects(commands.counter_rect(second)) and not stacks.roster.get_rect().intersects(commands.counter_rect(headquarters)), "The roster keeps the selected counter and its HQ visible at zoom %.1f" % zoom)
		if OS.get_cmdline_user_args().has("--render"):
			await _capture("zoom-" + str(zoom))
		# The same click must close the popup and select a different map squad.
		var single_point: Vector2 = BattlefieldStacks.counter_rect(single).get_center()
		var before: int = controller.map_clicks
		_click(single_point)
		await _settle()
		_check(not stacks.roster.visible and controller.map_clicks == before + 1 and controller.selected_unit == single, "An outside click closes the roster and selects a different squad without a dead click at zoom %.1f" % zoom)
		controller._deselect_unit(single)
		_click(point)
		await _settle()
		_check(stacks.roster.visible, "The slightly stacked counters reopen the roster directly")
		var escape: InputEventKey = InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		get_viewport().push_input(escape, true)
		_check(not stacks.roster.visible, "Escape closes the stack roster")
	get_viewport().canvas_transform = Transform2D.IDENTITY
	stacks.refresh()


func _test_enemy_visibility() -> void:
	var enemy: Unit = _unit(stack_cell, 8, Globals.SquadType.Rifle)
	enemy.team = Globals.get_enemy_team(Globals.team_player)
	stacks.open_roster(stack_cell)
	_check(stacks.roster.rows.size() == 3 and not stacks.roster.rows.has(enemy.get_instance_id()), "Friendly stack rosters never include enemy squads")
	enemy.hide()
	stacks.refresh()
	_check(stacks.roster.rows.size() == 3 and not enemy.is_visible_in_tree(), "Opening the roster never reveals hidden enemy counters")
	stacks.roster.close()
	units.erase(enemy)
	enemy.squad_fire.calc.free()
	enemy.free()


func _test_outside_hud_click() -> void:
	stacks.open_roster(stack_cell)
	var button: Button = Button.new()
	button.position = Vector2(12.0, 12.0)
	button.size = Vector2(140.0, 32.0)
	button.text = "HUD control"
	var presses: Array[int] = [0]
	button.pressed.connect(func() -> void: presses[0] += 1)
	hud.add_child(button)
	var before: int = controller.map_clicks
	_click(button.get_global_rect().get_center())
	await _settle()
	_check(not stacks.roster.visible and presses[0] == 1 and controller.map_clicks == before, "An outside HUD click closes the roster and activates that same control")
	button.free()


func _test_shared_hq() -> void:
	var original_hex: Vector2i = headquarters.current_hex
	var original_cube: Vector3i = headquarters.current_cube
	var original_transform: Transform2D = headquarters.global_transform
	headquarters.current_hex = stack_cell
	headquarters.current_cube = controller.ground_layer.map_to_cube(stack_cell)
	headquarters.global_position = controller.ground_layer.to_global(controller.ground_layer.map_to_local(stack_cell)) + Vector2(0.0, -32.0)
	controller._select_unit(second)
	stacks.refresh()
	commands.refresh(0.0)
	stacks.open_roster(stack_cell)
	_check(stacks.roster.rows.size() == 4 and commands.badge_text(headquarters).begins_with("HQ"), "The selected squad's HQ stays identified when it shares the stack")
	_check(commands.link_points(second).size() > 2, "An HQ in the same stack retains its local command loop")
	if OS.get_cmdline_user_args().has("--render"):
		stacks.open_roster(stack_cell)
		await _settle()
		commands.refresh(3.0)
		await _capture("shared-hq")
		stacks.roster.close()
	headquarters.current_hex = original_hex
	headquarters.current_cube = original_cube
	headquarters.global_transform = original_transform
	stacks.refresh()


func _test_live_updates_and_large_stacks() -> void:
	stacks.open_roster(stack_cell)
	var old_strength: int = first.squad_fire.soldiers.size()
	first.squad_fire.soldiers.pop_back()
	first.members_alive -= 1
	first.stress_system._set_state(STATES.MoraleState.PINNED)
	first.command_connectivity.clear_connectivity()
	stacks.refresh()
	await _settle()
	var row: SquadRosterRow = stacks.roster.rows[first.get_instance_id()]
	_check(row.strength.text.begins_with(str(old_strength - 1) + "/") and row.morale.text == "Pinned" and row.command_status.text == "Contact: No contact", "An open roster updates casualties, morale and communication without changing its membership")
	controller._select_unit(second)
	stacks.refresh()
	first.ui.show_casualty(1)
	_check(first.ui._casualty_feedback.active and first.ui.modulate.a == 1.0, "Each stacked squad retains its own visible casualty feedback")
	for index: int in range(8):
		_unit(stack_cell, 5 + index, Globals.SquadType.Rifle)
	stacks.refresh()
	await _settle()
	stacks.refresh()
	_check(stacks.roster.rows.size() == 11 and hud.get_child_count() == 1, "Large stack rosters retain every squad without adding battlefield count indicators")
	controller._select_unit(second)
	stacks.refresh()
	var point: Vector2 = BattlefieldStacks.counter_rect(second).get_center()
	for click: int in range(9):
		_click(point)
	await _settle()
	var last: Unit = units.back()
	var last_row: SquadRosterRow = stacks.roster.rows[last.get_instance_id()]
	_check(controller.selected_unit == last and last_row.button_pressed and stacks.roster.scroll.scroll_vertical > 0 and stacks.roster.scroll.get_global_rect().encloses(last_row.get_global_rect()), "Rapid stack clicks select and scroll to the last squad in a large roster")
	_click(point)
	await _settle()
	_check(controller.selected_unit == first and stacks.roster.rows[first.get_instance_id()].button_pressed and stacks.roster.scroll.scroll_vertical == 0, "Cycling past the last squad wraps and scrolls back to the first row")
	var scroll_point: Vector2 = stacks.roster.scroll.get_global_transform_with_canvas() * (stacks.roster.scroll.size * 0.5)
	var before: int = zooms
	_mouse(scroll_point, MouseButton.MOUSE_BUTTON_WHEEL_UP, true)
	_mouse(scroll_point, MouseButton.MOUSE_BUTTON_WHEEL_UP, false)
	_check(zooms == before, "Scrolling the roster never zooms the battlefield")
	for window_size: Vector2i in [Vector2i(800, 600), Vector2i(708, 639)]:
		get_tree().root.size = window_size
		await _settle()
		stacks.refresh()
		await _settle()
		stacks.refresh()
		_check(Rect2(Vector2.ZERO, hud.size).encloses(stacks.roster.get_rect()) and stacks.roster.scroll.size.y < stacks.roster.row_container.size.y, "Large rosters fit and scroll at window size %s" % window_size)
	if OS.get_cmdline_user_args().has("--render"):
		await _capture("large-stack")
	stacks.roster.close()


func _test_model_positions() -> void:
	for unit: Unit in [first, second, third, headquarters, single]:
		var original: Dictionary = snapshots[unit.get_instance_id()]
		_check(unit.global_transform == original["transform"] and unit.current_hex == original["hex"] and unit.current_cube == original["cube"] and unit.ui.get_global_transform() == original["ui_transform"], "Stack presentation preserves unit transforms, occupied hexes and counter origins")
		_check(not unit.is_moving and not unit.movement.is_moving, "Opening and selecting a stack does not issue movement orders")


func _test_removal_and_cleanup() -> void:
	stacks.open_roster(stack_cell)
	third.current_hex = Vector2i(7, 4)
	stacks.refresh()
	_check(third.ui.modulate.a == 1.0 and stacks.roster.rows.size() == 10 and not stacks.roster.rows.has(third.get_instance_id()), "Leaving a stack removes the roster row and preserves the original counter")
	first.alive = false
	first.ui.die()
	stacks.refresh()
	_check(first.ui.modulate.a == 1.0 and not stacks.roster.rows.has(first.get_instance_id()), "Eliminated squads retain their own corpse and fade presentation")
	stacks.open_roster(stack_cell)
	var doomed: Unit = units.back()
	var doomed_id: int = doomed.get_instance_id()
	controller._select_unit(doomed)
	units.erase(doomed)
	doomed.squad_fire.calc.free()
	doomed.free()
	stacks.refresh()
	_check(not stacks.roster.rows.has(doomed_id), "Freed squads disappear from open rosters without stale Node keys")
	_click(BattlefieldStacks.counter_rect(second).get_center())
	_check(is_instance_valid(controller.selected_unit) and controller.selected_unit.is_active() and stacks.roster.rows[controller.selected_unit.get_instance_id()].button_pressed, "Cycling skips removed squads and recovers from a freed current selection")
	for unit: Unit in units:
		if unit != second:
			unit.current_hex = Vector2i(15 + unit.squad, 15)
	stacks.refresh()
	_check(not stacks.roster.visible and not stacks.open_roster(stack_cell) and second.ui.modulate.a == 1.0, "A stack roster closes cleanly when only one squad remains")
	controller.end_game_handled = true
	stacks.refresh()
	_check(not stacks.roster.visible, "Ending the match closes any stack roster")


func _capture(label: String) -> void:
	await get_tree().process_frame
	# Minimized test windows do not reliably emit frame_post_draw on every driver.
	RenderingServer.force_draw(false)
	var capture: Image = get_viewport().get_texture().get_image()
	_check(capture.save_png("/tmp/acl-stacks-" + label + ".png") == OK, "Capture stack roster %s" % label)


func _settle() -> void:
	for frame: int in range(3):
		await get_tree().process_frame


func _click(point: Vector2) -> void:
	_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, true)
	_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, false)


func _mouse(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	get_viewport().push_input(event, true)


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
