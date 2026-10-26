extends Node

const UI_SCENE: PackedScene = preload("res://scenes/game/units/presentation/unit_battlefield_view.tscn")
const UNIT_SCENE: PackedScene = preload("res://scenes/game/units/unit.tscn")
const LINES_SCRIPT: Script = preload("res://scenes/world/overlays/tactical_lines_overlay.gd")

class PreviewHudProbe extends Node:
	var hide_calls: int = 0

	func hide_target_hex_cover_distance() -> void:
		hide_calls += 1


class PreviewWorldProbe extends Node2D:
	var ui: PreviewHudProbe


class ControllerProbe extends Node2D:
	var ground_layer: HexagonTileMapLayer
	var selected_unit: Unit
	var previous_selected_hex: Vector2i = Vector2i(-999, -999)
	var selected_hex_index: int = 0
	var end_game_handled: bool = false
	var continuing_after_end: bool = false
	signal hex_selected(cell: Vector2i, point: Vector2)
	signal show_unit_details_in_ui(unit: Unit)
	signal hide_unit_details_in_ui
	signal mouse_event_position_changed(point: Vector2)

	func _select_unit(unit: Unit) -> void:
		if is_instance_valid(selected_unit):
			selected_unit.deselect()
		selected_unit = unit
		unit.select()

	func _deselect_unit(unit: Unit) -> void:
		if selected_unit == unit:
			unit.deselect()
			selected_unit = null

	func click(point: Vector2) -> void:
		MatchInteractionHandler.on_mouse_button_left_pressed(self, point)


var checks: int = 0
var failures: int = 0
var map_clicks: int = 0
var zooms: int = 0
var right_clicks: int = 0
var hud_clicks: int = 0
var controller: ControllerProbe
var units: Array[Unit] = []


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--render"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_run.call_deferred()


func _run() -> void:
	get_tree().root.size = Vector2i(1152, 648)
	var world: Node = Node.new()
	world.name = "World"
	add_child(world)
	var audio: AudioPool = AudioPool.new()
	audio.name = "AudioPool"
	world.add_child(audio)
	var input: Node = (load("res://scenes/game/input/input_manager.tscn") as PackedScene).instantiate()
	add_child(input)
	input.set_battle_input_enabled(true)
	input.mouse_button_left_pressed.connect(func(_point: Vector2) -> void: map_clicks += 1)
	input.zoom_in.connect(func() -> void: zooms += 1)
	input.right_button_pressed.connect(func() -> void: right_clicks += 1)
	_test_unavailable_map()
	await _test_passive_controls()
	_test_stack_selection()
	await _test_pointer_stack_input(input)
	await _test_selected_visibility()
	await _test_target_link()
	for unit: Unit in units:
		unit.squad_fire.calc.free()
		unit.free()
	units.clear()
	controller.free()
	print("Battlefield selection checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_target_link() -> void:
	var original_sight: Dictionary = Globals.unit_visible_enemies
	var original_los: Dictionary = LOSHelper.los_lookup
	var original_debug: bool = Debug.enemy_selectable
	Debug.enemy_selectable = false
	var source: Unit = _unit(Globals.Team.ALLIES, Vector2i(1, 1))
	var target: Unit = _unit(Globals.Team.AXIS, Vector2i(4, 1))
	var overlay: Node2D = LINES_SCRIPT.new() as Node2D
	add_child(overlay)
	overlay.set_process(false)
	source.squad_fire.unit = source
	source.squad_fire.target_unit = target
	source.selected = true
	Globals.unit_visible_enemies = {source: [target]}
	LOSHelper.los_lookup = {source.current_hex: {target.current_hex: {}}}
	_check(overlay._target_for_link(source) == target, "A selected squad exposes its actual tracked enemy for the target line")
	source.selected = false
	_check(overlay._target_for_link(source) == null, "Deselecting immediately removes the target line")
	source.selected = true
	source.attackState = Unit.AttackState.MANUAL_GROUND
	_check(overlay._target_for_link(source) == null, "Ground fire cannot display a stale enemy link")
	source.attackState = Unit.AttackState.AUTO
	target.hide()
	_check(overlay._target_for_link(source) == null, "The target line never reveals a hidden enemy")
	target.show()
	LOSHelper.los_lookup = {}
	_check(overlay._target_for_link(source) == null, "LOS loss removes the line before detection refreshes")
	LOSHelper.los_lookup = {source.current_hex: {target.current_hex: {}}}
	Globals.unit_visible_enemies = {}
	_check(overlay._target_for_link(source) == null, "An undetected target cannot receive a line through team spotting alone")
	Globals.unit_visible_enemies = {source: [target]}
	target.surrendered = true
	_check(overlay._target_for_link(source) == null, "Surrendered targets lose their targeting line")
	target.surrendered = false
	source.in_close_combat = true
	_check(overlay._target_for_link(source) == null, "Close combat does not retain an old ranged targeting line")
	source.in_close_combat = false
	var old_center: Vector2 = overlay._counter_center(target)
	target.position += Vector2(40.0, 20.0)
	_check(overlay._counter_center(target).is_equal_approx(old_center + Vector2(40.0, 20.0)), "The target endpoint follows the moving counter")
	if OS.get_cmdline_user_args().has("--render"):
		await _render_target_link(overlay, source, target)
	source.team = Globals.Team.AXIS
	target.team = Globals.Team.ALLIES
	_check(overlay._target_for_link(source) == null, "Read-only enemy inspection cannot expose enemy targeting decisions")
	Debug.enemy_selectable = true
	_check(overlay._target_for_link(source) == target, "Explicit enemy debug control permits a selected enemy's target line")
	source.squad_fire.target_unit = null
	_check(overlay._target_for_link(source) == null, "Clearing the target removes the line")
	source.selected = false
	Globals.unit_visible_enemies = original_sight
	LOSHelper.los_lookup = original_los
	Debug.enemy_selectable = original_debug
	overlay.free()


func _render_target_link(overlay: Node2D, source: Unit, target: Unit) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(800, 320)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var background: ColorRect = ColorRect.new()
	background.size = Vector2(800.0, 320.0)
	background.color = Color(0.25, 0.30, 0.17)
	viewport.add_child(background)
	var source_position: Vector2 = source.position
	var target_position: Vector2 = target.position
	source.reparent(viewport)
	target.reparent(viewport)
	overlay.reparent(viewport)
	source.position = Vector2(200.0, 160.0)
	target.position = Vector2(600.0, 160.0)
	source.ui.update_team_sprite(source.team, Globals.SquadType.Rifle)
	target.ui.update_team_sprite(target.team, Globals.SquadType.Rifle)
	var camera: Camera2D = Camera2D.new()
	camera.position = Vector2(400.0, 160.0)
	viewport.add_child(camera)
	for zoom: float in [0.6, 1.0, 1.5]:
		camera.zoom = Vector2.ONE * zoom
		overlay.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		RenderingServer.force_draw(false)
		_check(viewport.get_texture().get_image().save_png("/tmp/acl-target-link-" + str(zoom) + ".png") == OK, "Render the selected target link at zoom " + str(zoom))
	source.reparent(controller)
	target.reparent(controller)
	overlay.reparent(self)
	source.position = source_position
	target.position = target_position
	viewport.free()


func _test_selected_visibility() -> void:
	var original_sight: Dictionary = Globals.unit_visible_enemies.duplicate()
	var original_debug: bool = Debug.show_enemies
	Debug.show_enemies = false
	var first: Unit = _unit(Globals.Team.ALLIES, Vector2i(1, 1))
	var second: Unit = _unit(Globals.Team.ALLIES, Vector2i(2, 1))
	var direct: Unit = _unit(Globals.Team.AXIS, Vector2i(3, 1))
	var indirect: Unit = _unit(Globals.Team.AXIS, Vector2i(4, 1))
	var hidden: Unit = _unit(Globals.Team.AXIS, Vector2i(5, 1))
	Globals.unit_visible_enemies = {first: [direct], second: [indirect]}
	controller.selected_unit = first
	MatchVisibilityCoordinator.show_visible_units(controller)
	_check(direct.visible and direct.modulate == Color.WHITE, "The selected squad's own sighting stays fully visible")
	_check(indirect.visible and indirect.modulate == MatchVisibilityCoordinator.INDIRECT_CONTACT_TINT, "An enemy seen only by another squad is dimmed")
	_check(not hidden.visible, "Selection never reveals an enemy unknown to the team")
	_check(first.modulate == Color.WHITE and second.modulate == Color.WHITE, "Friendly counters keep their normal appearance")
	var direct_material: ShaderMaterial = direct.ui.sprite_node.material as ShaderMaterial
	var indirect_material: ShaderMaterial = indirect.ui.sprite_node.material as ShaderMaterial
	_check(not bool(direct_material.get_shader_parameter("indirect_contact")) and bool(indirect_material.get_shader_parameter("indirect_contact")), "The counter shader distinguishes direct and indirect contacts independently")
	if OS.get_cmdline_user_args().has("--render"):
		await _render_sight_comparison(direct, indirect)
	controller.selected_unit = second
	MatchVisibilityCoordinator.show_visible_units(controller)
	_check(direct.modulate == MatchVisibilityCoordinator.INDIRECT_CONTACT_TINT and indirect.modulate == Color.WHITE, "Switching squads swaps which enemy sightings are emphasized")
	Globals.unit_visible_enemies[second] = [direct, indirect]
	MatchVisibilityCoordinator.show_visible_units(controller)
	_check(direct.modulate == Color.WHITE and not bool(direct_material.get_shader_parameter("indirect_contact")), "New sightings restore the selected squad's contacts")
	Globals.unit_visible_enemies[second] = [indirect]
	MatchVisibilityCoordinator.show_visible_units(controller)
	_check(direct.modulate == MatchVisibilityCoordinator.INDIRECT_CONTACT_TINT, "Losing a sighting dims a contact still seen by another squad")
	controller.selected_unit = null
	MatchVisibilityCoordinator.show_visible_units(controller)
	_check(direct.modulate == Color.WHITE and indirect.modulate == Color.WHITE and not hidden.visible, "Deselecting restores team-wide contact appearance without revealing hidden enemies")
	controller.selected_unit = direct
	MatchVisibilityCoordinator.show_visible_units(controller)
	_check(first.modulate == Color.WHITE and second.modulate == MatchVisibilityCoordinator.INDIRECT_CONTACT_TINT, "Inspecting an enemy highlights only friendlies that can see it")
	Globals.unit_visible_enemies[second] = [direct, indirect]
	MatchVisibilityCoordinator.show_visible_units(controller)
	_check(second.modulate == Color.WHITE, "New friendly sightings update enemy inspection")
	Globals.unit_visible_enemies[first] = []
	Globals.unit_visible_enemies[second] = []
	MatchVisibilityCoordinator.show_visible_units(controller)
	_check(controller.selected_unit == null and not direct.visible, "Losing the team's last sighting clears enemy inspection")
	Globals.unit_visible_enemies[first] = [direct]
	Globals.unit_visible_enemies[second] = [indirect]
	controller.selected_unit = first
	Debug.show_enemies = true
	MatchVisibilityCoordinator.show_visible_units(controller)
	_check(hidden.visible and hidden.modulate == MatchVisibilityCoordinator.INDIRECT_CONTACT_TINT, "Debug reveal still identifies enemies the selected squad cannot see")
	first.surrendered = true
	MatchVisibilityCoordinator.show_visible_units(controller)
	_check(indirect.modulate == Color.WHITE, "An unavailable selected squad does not retain sight filtering")
	first.surrendered = false
	controller.selected_unit = null
	Globals.unit_visible_enemies = original_sight
	Debug.show_enemies = original_debug
	MatchVisibilityCoordinator.show_visible_units(controller)


func _render_sight_comparison(direct: Unit, indirect: Unit) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(600, 230)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var index: int = 0
	for enemy: Unit in [direct, indirect]:
		var old_position: Vector2 = enemy.position
		enemy.set_meta("sight_preview_position", old_position)
		enemy.reparent(viewport)
		enemy.position = Vector2(110.0 + float(index) * 300.0, 70.0)
		enemy.ui.update_team_sprite(enemy.team, Globals.SquadType.Rifle)
		enemy.ui.set_members_alive(8)
		var caption: Label = Label.new()
		caption.position = Vector2(40.0 + float(index) * 300.0, 170.0)
		caption.text = "Selected squad sees this"
		if index == 1:
			caption.text = "Seen by another squad only"
		viewport.add_child(caption)
		index += 1
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	_check(viewport.get_texture().get_image().save_png("/tmp/acl-selected-sight.png") == OK, "Render direct and indirect enemy contacts together")
	for enemy: Unit in [direct, indirect]:
		enemy.reparent(controller)
		enemy.position = enemy.get_meta("sight_preview_position") as Vector2
		enemy.remove_meta("sight_preview_position")
	viewport.free()


func _test_unavailable_map() -> void:
	var world: PreviewWorldProbe = PreviewWorldProbe.new()
	world.ui = PreviewHudProbe.new()
	world.add_child(world.ui)
	var pending: ControllerProbe = ControllerProbe.new()
	world.add_child(pending)
	add_child(world)
	var motions: Array[Vector2] = []
	var clicks: Array[Vector2i] = []
	pending.mouse_event_position_changed.connect(func(point: Vector2) -> void: motions.append(point))
	pending.hex_selected.connect(func(cell: Vector2i, _point: Vector2) -> void: clicks.append(cell))
	LOSHelper.los_lines.append({})
	MatchInteractionHandler.handle_mouse_event_position_changed(pending, Vector2(10.0, 20.0))
	pending.click(Vector2(10.0, 20.0))
	_check(world.ui.hide_calls == 1 and LOSHelper.los_lines.is_empty(), "Mouse movement before map assignment clears targeting feedback without accessing a map")
	_check(clicks.is_empty() and motions == [Vector2(10.0, 20.0)], "Before setup, clicks are ignored while mouse-position notifications continue")
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ground.tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	ground.tile_set.tile_size = Vector2i(128, 128)
	ground.pathfinding_enabled = false
	pending.add_child(ground)
	pending.ground_layer = ground
	ground.free()
	# A selected squad can remain referenced while a map is being removed.
	var selected: Unit = Unit.new()
	pending.selected_unit = selected
	LOSHelper.los_lines.append({})
	MatchInteractionHandler.handle_mouse_event_position_changed(pending, Vector2(30.0, 40.0))
	pending.click(Vector2(30.0, 40.0))
	_check(world.ui.hide_calls == 2 and LOSHelper.los_lines.is_empty(), "Mouse movement after map deletion clears stale targeting feedback")
	MatchInteractionHandler.refresh_target_preview(pending, Vector2.ZERO, Vector2.ZERO)
	_check(world.ui.hide_calls == 3, "Direct targeting-preview refresh also handles a freed map")
	_check(clicks.is_empty() and motions.size() == 2 and pending.selected_unit == selected, "Map cleanup cannot interpret clicks or change selection through an invalid layer")
	selected.free()
	world.free()


func _test_passive_controls() -> void:
	var ui: UnitUi = UI_SCENE.instantiate() as UnitUi
	ui.position = Vector2(350.0, 200.0)
	ui.scale = Vector2(2.0, 2.0)
	add_child(ui)
	ui.set_cover(3)
	await get_tree().process_frame
	await get_tree().process_frame
	var cover: Control = ui.cover_container.get_child(0) as Control
	var cover_point: Vector2 = cover.get_global_transform_with_canvas() * (cover.size * 0.5)
	_check_pointer_passes(cover_point, "Cover icons")
	ui.die()
	await get_tree().process_frame
	await get_tree().process_frame
	_check_pointer_passes(ui.dead.get_global_transform_with_canvas() * (ui.dead.size * 0.5), "Corpse images")
	ui.show_casualty(1)
	_check_pointer_passes(ui.get_global_transform_with_canvas() * Vector2(32.0, -12.0), "Casualty badges")
	_check_pointer_passes(ui.get_global_transform_with_canvas() * Vector2(32.0, 73.0), "State ribbons")
	ui.free()
	var button: Button = Button.new()
	button.position = Vector2(40.0, 40.0)
	button.size = Vector2(120.0, 36.0)
	button.text = "HUD control"
	button.pressed.connect(func() -> void: hud_clicks += 1)
	add_child(button)
	await get_tree().process_frame
	var before: int = map_clicks
	_mouse(button.position + button.size * 0.5, MouseButton.MOUSE_BUTTON_LEFT, true)
	_mouse(button.position + button.size * 0.5, MouseButton.MOUSE_BUTTON_LEFT, false)
	_check(hud_clicks == 1 and map_clicks == before, "Interactive HUD controls still consume clicks")
	button.free()


func _check_pointer_passes(point: Vector2, label: String) -> void:
	var clicks_before: int = map_clicks
	var zooms_before: int = zooms
	var right_before: int = right_clicks
	_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, true)
	_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, false)
	_mouse(point, MouseButton.MOUSE_BUTTON_RIGHT, true)
	_mouse(point, MouseButton.MOUSE_BUTTON_RIGHT, false)
	_mouse(point, MouseButton.MOUSE_BUTTON_WHEEL_UP, true)
	_mouse(point, MouseButton.MOUSE_BUTTON_WHEEL_UP, false)
	_check(map_clicks == clicks_before + 1, label + " pass left clicks to the battlefield")
	_check(right_clicks == right_before + 1, label + " pass right clicks to the battlefield")
	_check(zooms == zooms_before + 1, label + " do not block map zoom")
	_check(get_viewport().gui_get_hovered_control() == null, label + " do not masquerade as HUD controls and block commands or targeting previews")


func _test_stack_selection() -> void:
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ground.tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	ground.tile_set.tile_size = Vector2i(128, 128)
	ground.pathfinding_enabled = false
	controller = ControllerProbe.new()
	add_child(controller)
	controller.add_child(ground)
	controller.ground_layer = ground
	Globals.team_player = Globals.Team.ALLIES
	Debug.enemy_selectable = false
	var cell: Vector2i = Vector2i(3, 2)
	var enemy: Unit = _unit(Globals.Team.AXIS, cell)
	var first: Unit = _unit(Globals.Team.ALLIES, cell)
	var second: Unit = _unit(Globals.Team.ALLIES, cell)
	var point: Vector2 = ground.get_global_transform_with_canvas() * ground.map_to_local(cell)
	controller.click(point)
	_check(controller.selected_unit != null, "A mixed stack selects a visible squad")
	var previous: Unit = controller.selected_unit
	controller.click(point)
	_check(controller.selected_unit != null and controller.selected_unit != previous, "Cycling a mixed stack advances selection")
	previous = controller.selected_unit
	controller.click(point)
	_check(controller.selected_unit != null and controller.selected_unit != previous, "Every stack click advances to a selectable squad")
	enemy.z_index = 3
	controller.click(enemy.ui.sprite_node.get_global_transform_with_canvas() * Vector2(32.0, 8.0))
	_check(controller.selected_unit == enemy, "Clicking a visible enemy counter inspects it without enabling debug command access")
	enemy.surrendered = true
	controller.click(enemy.ui.sprite_node.get_global_transform_with_canvas() * Vector2(32.0, 8.0))
	_check(controller.selected_unit == first or controller.selected_unit == second, "A surrendered enemy cannot intercept clicks on friendlies in the same hex")
	var friendly_selection: Unit = controller.selected_unit
	Debug.enemy_selectable = true
	MatchInteractionHandler.select_unit(controller, enemy)
	_check(controller.selected_unit == friendly_selection, "Debug enemy selection cannot select a surrendered enemy")
	controller.click(point)
	_check(controller.selected_unit != enemy, "Debug pointer selection also excludes surrendered enemies")
	Debug.enemy_selectable = false
	enemy.surrendered = false
	enemy.z_index = 0
	enemy.hide()
	Debug.enemy_selectable = true
	for click: int in range(4):
		controller.click(point)
		_check(controller.selected_unit != null and controller.selected_unit != enemy, "Hidden enemies are excluded even when debug selection is enabled")
	Debug.enemy_selectable = false
	enemy.show()
	first.current_hex = Vector2i(5, 2)
	first.position = ground.map_to_local(first.current_hex)
	second.current_hex = first.current_hex
	second.position = first.position + Vector2(0.0, -60.0)
	second.z_index = 2
	var edge_point: Vector2 = second.ui.sprite_node.get_global_transform_with_canvas() * Vector2(32.0, 8.0)
	_check(ground.local_to_map(ground.get_global_transform_with_canvas().affine_inverse() * edge_point) != second.current_hex, "The fixture has a drawn counter outside its occupied hex")
	controller.previous_selected_hex = Vector2i(-999, -999)
	controller.selected_unit = null
	controller.click(edge_point)
	_check(controller.selected_unit == first or controller.selected_unit == second, "Clicking an offset counter selects its actual stack")
	ground.position = Vector2(179.0, 143.0)
	first.current_hex = Vector2i(2, 1)
	second.hide()
	first.hide()
	enemy.hide()
	# Ground clicks use the layer's transform even when no sprite is under the pointer.
	var clicked: Array[Vector2i] = []
	controller.hex_selected.connect(func(hex: Vector2i, _point: Vector2) -> void: clicked.append(hex))
	point = ground.get_global_transform_with_canvas() * ground.map_to_local(Vector2i(2, 2))
	controller.click(point)
	_check(clicked.back() == Vector2i(2, 2), "Hex picking uses the ground layer's transform")


func _unit(team: Globals.Team, cell: Vector2i) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	controller.add_child(unit)
	unit.team = team
	unit.current_hex = cell
	unit.position = controller.ground_layer.map_to_local(cell)
	unit.set_process(false)
	for child: Node in unit.get_children():
		child.set_process(false)
		child.set_physics_process(false)
		if child is Timer:
			(child as Timer).stop()
	unit.add_to_group("units")
	units.append(unit)
	return unit


func _test_pointer_stack_input(input: Node) -> void:
	input.mouse_button_left_pressed.connect(controller.click)
	var original_canvas: Transform2D = get_viewport().canvas_transform
	var ground: HexagonTileMapLayer = controller.ground_layer
	controller.position = Vector2(37.0, 19.0)
	ground.position = Vector2(79.0, 53.0)
	var cell: Vector2i = Vector2i(3, 2)
	var center: Vector2 = ground.to_global(ground.map_to_local(cell))
	for index: int in range(units.size()):
		var unit: Unit = units[index]
		unit.current_hex = cell
		unit.global_position = center + Vector2(0.0, -16.0 * float(index))
		unit.z_index = index
		unit.show()
	units[1].ui.set_cover(3)
	for zoom: float in [0.5, 1.0, 2.0]:
		var canvas: Transform2D = Transform2D.IDENTITY.scaled(Vector2(zoom, zoom))
		canvas.origin = Vector2(420.0, 270.0) - center * zoom
		get_viewport().canvas_transform = canvas
		await get_tree().process_frame
		await get_tree().process_frame
		controller.previous_selected_hex = Vector2i(-999, -999)
		if controller.selected_unit != null:
			controller._deselect_unit(controller.selected_unit)
		var point: Vector2 = units[2].ui.sprite_node.get_global_transform_with_canvas() * Vector2(32.0, 20.0)
		_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, true)
		_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, false)
		_check(controller.selected_unit == units[2], "Actual pointer input selects the front counter after zoom and pan: " + str(zoom))
		_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, true)
		_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, false)
		_check(controller.selected_unit == units[1], "A repeated pointer click cycles to the next friendly squad: " + str(zoom))
		_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, true)
		_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, false)
		_check(controller.selected_unit == units[2], "Actual stack cycling has no enemy-induced dead click: " + str(zoom))
	# A corpse drawn over a living unit must neither intercept input nor enter the cycle.
	units[2].alive = false
	units[2].ui.die()
	await get_tree().process_frame
	var corpse_point: Vector2 = units[2].ui.dead.get_global_transform_with_canvas() * (units[2].ui.dead.size * 0.5)
	controller.previous_selected_hex = Vector2i(-999, -999)
	_mouse(corpse_point, MouseButton.MOUSE_BUTTON_LEFT, true)
	_mouse(corpse_point, MouseButton.MOUSE_BUTTON_LEFT, false)
	_check(controller.selected_unit == units[1], "Clicks through an overlapping corpse still select the living squad")
	_check(get_viewport().gui_get_hovered_control() == null, "A corpse over a stack cannot block the command wheel")
	var hidden_details: Array[int] = [0]
	var shown_details: Array[Unit] = []
	controller.hide_unit_details_in_ui.connect(func() -> void: hidden_details[0] += 1)
	controller.show_unit_details_in_ui.connect(func(unit: Unit) -> void: shown_details.append(unit))
	for click: int in range(3):
		_mouse(corpse_point, MouseButton.MOUSE_BUTTON_LEFT, true)
		_mouse(corpse_point, MouseButton.MOUSE_BUTTON_LEFT, false)
		_check(controller.selected_unit == units[1] and units[1].selected, "Repeated pointer clicks preserve the only living squad's selection")
	_check(hidden_details[0] == 0 and shown_details == [units[1], units[1], units[1]], "Repeated selection keeps squad details visible")
	get_viewport().canvas_transform = original_canvas


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


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
