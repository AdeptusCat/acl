extends Node

const LINES: Script = preload("res://scenes/world/overlays/tactical_lines_overlay.gd")

var checks: int = 0
var failures: int = 0
var world: Node
var controller: Node2D
var friendly: Unit
var enemy: Unit


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	world = main.world
	var map: Map = world.maps.get_child(1)
	var scenario: Scenario = map.get_scenario(0)
	scenario.axis_ai_status = Scenario.AIStatus.OFF
	scenario.allies_ai_status = Scenario.AIStatus.OFF
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	controller = world.game_controller
	friendly = Globals.get_units_for_team(Globals.team_player)[1]
	enemy = Globals.get_units_for_team(Globals.team_enemy)[0]
	_set_hex(friendly, Vector2i(2, 2))
	_reset_contacts(3)
	_test_sector_tradeoffs()
	_test_diversion_and_movement()
	_test_reaction_snapshot()
	_test_orders_and_controls()
	_test_save()
	await _test_overlay()
	_test_lifecycle()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Watch sector checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_sector_tradeoffs() -> void:
	_check(friendly.set_watch_direction(Vector2.RIGHT * 10.0) and friendly.watch_direction == Vector2.RIGHT, "Watch directions are normalized world-space bearings")
	_check(not friendly.set_watch_direction(Vector2.ZERO) and not friendly.set_watch_direction(Vector2(INF, 0.0)) and friendly.watch_direction == Vector2.RIGHT, "Invalid bearings cannot erase a valid assignment")
	var centres: Array[float] = []
	var flanks: Array[float] = []
	for width: Unit.WatchWidth in [Unit.WatchWidth.NARROW, Unit.WatchWidth.NORMAL, Unit.WatchWidth.WIDE]:
		friendly.set_watch_width(width)
		var state: SquadTacticalState = friendly.tactical_state
		centres.append(state.detection_multiplier(Vector2.RIGHT))
		flanks.append(state.detection_multiplier(Vector2.from_angle(deg_to_rad(75.0))))
		_check(state.watch_focus_active and state.focus_direction == Vector2.RIGHT and is_equal_approx(state.attention_width, friendly.watch_arc_radians()), "An explicit watch sector takes priority over automatic objectives")
		var boundary: float = friendly.watch_arc_radians() * 0.5
		var inside: float = state.detection_multiplier(Vector2.from_angle(boundary - 0.0001))
		var outside: float = state.detection_multiplier(Vector2.from_angle(boundary + 0.0001))
		_check(absf(inside - outside) < 0.001 and state.detection_multiplier(Vector2.LEFT) > 0.0, "Sector boundaries are smooth and peripheral awareness never becomes blindness")
	_check(centres[0] > centres[1] and centres[1] > centres[2], "Narrow sectors give greater concentration at their centre")
	_check(flanks[0] < flanks[1] and flanks[1] < flanks[2], "Wider sectors improve coverage toward the flanks")


func _test_diversion_and_movement() -> void:
	var bearing: Vector2 = friendly.global_position.direction_to(enemy.global_position)
	var assigned: Vector2 = -bearing
	friendly.set_watch_direction(assigned)
	friendly.set_watch_width(Unit.WatchWidth.NORMAL)
	Globals.unit_visible_enemies[friendly] = [enemy]
	friendly.tactical_state.update_attention(friendly)
	_check(friendly.tactical_state.focus_direction.is_equal_approx(assigned) and not friendly.tactical_state.watch_diverted, "A distant sighting reduces watch commitment without turning the squad away from its assignment")
	friendly.squad_fire.set_target_unit(enemy)
	_check(friendly.squad_fire.target_unit == enemy, "A watch sector permits targeting a detected enemy outside its arc")
	_reset_contacts(2)
	Globals.unit_visible_enemies[friendly] = [enemy]
	friendly.tactical_state.update_attention(friendly)
	_check(friendly.tactical_state.watch_diverted and friendly.tactical_state.focus_direction.dot(assigned) < -0.99 and friendly.watch_direction.is_equal_approx(assigned), "A nearby detected enemy diverts actual attention without changing the stored watch order")
	_reset_contacts(3)
	friendly.tactical_state.update_attention(friendly)
	_check(friendly.tactical_state.watch_focus_active and friendly.tactical_state.focus_direction.is_equal_approx(assigned), "Attention returns to the assignment when the immediate contact disappears")
	var state: SquadTacticalState = friendly.tactical_state
	state.register_incoming_fire(bearing, friendly._now())
	state.update_attention(friendly)
	_check(state.watch_diverted and state.focus_direction.is_equal_approx(bearing) and Globals.unit_visible_enemies[friendly].is_empty(), "Incoming fire supplies a reactive bearing without revealing its source")
	state.register_incoming_fire(bearing, friendly._now() - SquadTacticalState.INCOMING_FIRE_WINDOW_SECONDS - 1.0)
	state.update_attention(friendly)
	_check(state.watch_focus_active and state.focus_direction.is_equal_approx(assigned), "An expired fire bearing releases attention back to the assigned sector")
	var stationary: float = state.detection_multiplier(assigned)
	friendly.is_moving = true
	friendly.movement.is_moving = true
	state.update_attention(friendly)
	_check(state.detection_multiplier(assigned) < stationary and friendly.watch_direction.is_equal_approx(assigned), "Movement reduces watch commitment while retaining the world-space assignment")
	friendly.is_moving = false
	friendly.movement.is_moving = false
	friendly.stress_system.state = STATES.MoraleState.PINNED
	state.update_attention(friendly)
	_check(state.watch_focus_active and state.detection_multiplier(assigned) < stationary, "Pinned squads retain the assignment with reduced observation quality")
	friendly.stress_system.state = STATES.MoraleState.NORMAL
	state.update_attention(friendly)


func _test_reaction_snapshot() -> void:
	_reset_contacts(2)
	var bearing: Vector2 = friendly.global_position.direction_to(enemy.global_position)
	friendly.set_watch_direction(-bearing)
	friendly.set_watch_width(Unit.WatchWidth.NARROW)
	var track: EnemyTrack = EnemyTrack.new(friendly, enemy)
	var tracks: Dictionary[Unit, EnemyTrack] = {enemy: track}
	Globals.unit_enemy_tracks[friendly] = tracks
	MatchVisibilityCoordinator.on_unit_visibility_checker_timer_timeout(controller, 1000.0)
	_check(track.is_visible and track.reaction_watch_focus and track.reaction_focus_direction.is_equal_approx(-bearing) and is_equal_approx(track.reaction_attention_width, PI / 3.0), "Acquisition snapshots the watch direction and width before attention reacts to the nearby contact")
	var surprised: Soldier = _soldier(10)
	friendly.squad_fire._begin_soldier_engagement(surprised, enemy, enemy.current_hex)
	track.reaction_focus_direction = bearing
	var prepared: Soldier = _soldier(10)
	friendly.squad_fire._begin_soldier_engagement(prepared, enemy, enemy.current_hex)
	_check(surprised.aquire_target_task.remaining_time_s > prepared.aquire_target_task.remaining_time_s, "Turning toward a newly detected enemy cannot erase the original out-of-sector reaction penalty")
	var earliest: float = INF
	var latest: float = 0.0
	for index: int in range(12):
		var soldier: Soldier = _soldier(index)
		friendly.squad_fire._begin_soldier_engagement(soldier, enemy, enemy.current_hex)
		earliest = minf(earliest, soldier.aquire_target_task.remaining_time_s)
		latest = maxf(latest, soldier.aquire_target_task.remaining_time_s)
	_check(latest - earliest > 0.3 and earliest < 1.0, "Watching a sector preserves individual reactions instead of synchronizing the squad's first shots")
	_reset_contacts(3)


func _test_orders_and_controls() -> void:
	controller._select_unit(friendly)
	var target: Vector2i = enemy.current_hex
	_check(not controller.order_via_option_wheel(friendly.current_hex, WheelOption.Option.WATCH), "The squad's own hex cannot define a watch bearing")
	LOSHelper.los_lookup[friendly.current_hex] = {}
	var order_id: int = friendly.action_controller.action_order_id
	_check(controller.order_via_option_wheel(target, WheelOption.Option.WATCH), "A watch order may point toward obstructed terrain without requiring a firing solution")
	var assigned: Vector2 = friendly.watch_direction
	_check(not friendly.is_moving and friendly.action_controller.action_order_id == order_id, "Watch does not move the squad")
	var moved: bool = false
	for neighbor: Vector2i in world.ground_layer.get_surrounding_cells(friendly.current_hex):
		if MatchInteractionHandler.command_restriction(controller, neighbor, WheelOption.Option.MOVE_NORMAL).is_empty():
			moved = controller.order_via_option_wheel(neighbor, WheelOption.Option.MOVE_NORMAL)
			break
	_check(moved and friendly.watch_direction.is_equal_approx(assigned), "An actual movement order retains the independent watch bearing")
	_check(controller.order_via_option_wheel(target, WheelOption.Option.STOP) and friendly.watch_direction.is_equal_approx(assigned), "Stop clears action orders while preserving the independent watch assignment")
	var details: Control = world.ui.unit_details
	details.show_unit_detail(friendly, false)
	for width: int in details.watch_width_buttons:
		var button: Button = details.watch_width_buttons[width]
		button.pressed.emit()
		_check(friendly.watch_width == width and is_equal_approx(friendly.tactical_state.attention_width, friendly.watch_arc_radians()), "Each watch icon changes the actual watch width")
		_check(button.button_pressed and button.button_group.get_pressed_button() == button, "Watch icons highlight only the selected angle")
		_check(button.icon != null and button.text.is_empty() and not button.tooltip_text.is_empty(), "Watch angle options use icons and explanatory tooltips")
	details.watch_automatic.pressed.emit()
	_check(not friendly.has_watch_order() and details.watch_status.text == "Automatic attention", "Auto clears the assignment and restores automatic attention")
	controller.order_via_option_wheel(target, WheelOption.Option.WATCH)
	_check(friendly.watch_width == Unit.WatchWidth.WIDE, "A new assignment retains the player's selected width")
	controller.end_game_handled = true
	controller.continuing_after_end = false
	details._refresh_summary()
	for width: int in details.watch_width_buttons:
		_check(details.watch_width_buttons[width].disabled, "Mission completion disables every watch angle icon")
	details._on_watch_width_selected(Unit.WatchWidth.NARROW)
	_check(friendly.watch_width == Unit.WatchWidth.WIDE and details.watch_automatic.disabled and not controller.order_via_option_wheel(target, WheelOption.Option.WATCH), "Mission completion blocks watch commands and stale details signals")
	controller.end_game_handled = false
	Debug.enemy_selectable = false
	Globals.unit_visible_enemies[friendly] = [enemy]
	controller.show_visible_units()
	details.show_unit_detail(enemy, false)
	var previous_width: Unit.WatchWidth = enemy.watch_width
	details._on_watch_width_selected(Unit.WatchWidth.NARROW)
	_check(not details.watch_row.visible and enemy.watch_width == previous_width, "Enemy inspection cannot reveal or change enemy watch assignments")
	details.show_unit_detail(friendly, false)
	_reset_contacts(3)


func _test_save() -> void:
	friendly.set_watch_direction(Vector2(2.0, -1.0))
	friendly.set_watch_width(Unit.WatchWidth.NARROW)
	var assigned: Vector2 = friendly.watch_direction
	var saved: UnitSaveData = friendly.create_save_data()
	DirAccess.make_dir_recursive_absolute("user://tests")
	_check(ResourceSaver.save(saved, "user://tests/watch_sector.tres") == OK, "Watch assignments can be serialized with unit saves")
	var loaded: UnitSaveData = ResourceLoader.load("user://tests/watch_sector.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as UnitSaveData
	friendly.clear_watch_order()
	friendly.apply_save_data(loaded)
	_check(friendly.watch_direction.is_equal_approx(assigned) and friendly.watch_width == Unit.WatchWidth.NARROW and friendly.tactical_state.watch_focus_active, "Loading restores the bearing, width and effective watch attention")
	var details: Control = world.ui.unit_details
	details._refresh_summary()
	_check(details.watch_width_buttons[Unit.WatchWidth.NARROW].button_pressed, "Loading a saved angle updates the highlighted watch icon")
	var defaults: UnitSaveData = UnitSaveData.new()
	_check(defaults.watch_direction == Vector2.ZERO and defaults.watch_width == Unit.WatchWidth.NORMAL, "Older saves default to automatic attention and a normal arc")
	loaded.watch_direction = defaults.watch_direction
	loaded.watch_width = defaults.watch_width
	friendly.apply_save_data(loaded)
	_check(not friendly.has_watch_order(), "Loading an automatic-attention save clears any previous assignment")
	friendly.set_watch_direction(Vector2.RIGHT)


func _test_overlay() -> void:
	var lines: Node2D = LINES.new()
	world.add_child(lines)
	lines.set_process(false)
	friendly.selected = true
	var points: PackedVector2Array = lines._watch_sector_points(friendly)
	_check(not points.is_empty(), "A selected friendly squad displays its assigned watch arc")
	_check(not Geometry2D.triangulate_polygon(points.slice(0, points.size() - 1)).is_empty(), "The watch arc forms valid filled geometry")
	lines.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	var details: Control = world.ui.unit_details
	var narrow: Button = details.watch_width_buttons[Unit.WatchWidth.NARROW]
	_check(details.watch_row.get_global_rect().encloses(narrow.get_global_rect()) and details.watch_row.get_global_rect().encloses(details.watch_automatic.get_global_rect()), "The watch icons and Auto button fit inside the squad panel")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/acl-watch-angle-icons.png")
	var left: Vector2 = points[1] - points[0]
	var right: Vector2 = points[points.size() - 2] - points[0]
	_check(is_equal_approx(absf(left.angle_to(right)), friendly.watch_arc_radians()), "The displayed arc matches the chosen width")
	friendly.selected = false
	_check(lines._watch_sector_points(friendly).is_empty(), "Deselecting the squad hides its watch arc")
	enemy.set_watch_direction(Vector2.RIGHT)
	enemy.selected = true
	enemy.show()
	_check(lines._watch_sector_points(enemy).is_empty(), "Inspecting an enemy does not reveal its assigned sector")
	enemy.selected = false
	lines.free()


func _test_lifecycle() -> void:
	friendly.set_watch_direction(Vector2.RIGHT)
	friendly._on_morale_breaks()
	_check(not friendly.has_watch_order() and not friendly.set_watch_direction(Vector2.RIGHT), "Routing clears the assignment and prevents new watch orders")
	friendly._on_morale_recovered()
	friendly.in_close_combat = true
	_check(not friendly.set_watch_direction(Vector2.RIGHT), "Close combat prevents new watch assignments")
	friendly.in_close_combat = false
	friendly.set_watch_direction(Vector2.RIGHT)
	friendly.surrender()
	_check(not friendly.has_watch_order() and not friendly.set_watch_direction(Vector2.RIGHT), "Surrender clears the assignment and prevents new ones")
	enemy.die()
	_check(not enemy.has_watch_order(), "Elimination clears the assignment")


func _soldier(index: int) -> Soldier:
	var weapon: WeaponSpec = (load("res://resources/weapons/m1_garand.tres") as WeaponSpec).create_runtime()
	return Soldier.new(index, "Watch probe", RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, weapon, friendly, friendly.team)


func _reset_contacts(distance: int) -> void:
	_set_hex(enemy, world.ground_layer.cube_to_map(friendly.current_cube + Vector3i(distance, -distance, 0)))
	Globals.unit_visible_enemies = {friendly: []}
	Globals.unit_enemies_in_los = {friendly: [enemy]}
	Globals.unit_enemy_tracks.clear()
	LOSHelper.los_lookup = {friendly.current_hex: {enemy.current_hex: {"target_cover": 0, "target_concealment": 0, "hindrance": 0}}}
	friendly.squad_fire.clear_target()
	friendly.setAttackState(Unit.AttackState.AUTO)


func _set_hex(unit: Unit, cell: Vector2i) -> void:
	unit.current_hex = cell
	unit.current_cube = world.ground_layer.map_to_cube(cell)
	unit.global_position = world.ground_layer.to_global(world.ground_layer.map_to_local(cell))


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
