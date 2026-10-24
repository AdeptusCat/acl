extends Node

# Run headlessly for state checks; add -- --render for the battlefield preview.
const FEEDBACK: Script = preload("res://scenes/game/effects/unit_state_feedback.gd")
const CASUALTIES: Script = preload("res://scenes/game/effects/casualty_feedback.gd")
const UI_SCENE: PackedScene = preload("res://scenes/game/units/presentation/unit_battlefield_view.tscn")
const UNIT_SCENE: PackedScene = preload("res://scenes/game/units/unit.tscn")

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--render"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_run.call_deferred()


func _run() -> void:
	var world: Node = Node.new()
	world.name = "World"
	add_child(world)
	var audio: AudioPool = AudioPool.new()
	audio.name = "AudioPool"
	world.add_child(audio)
	_test_pinned_and_recovery()
	_test_ribbon_fade()
	_test_terminal_states()
	_test_elimination_fade()
	_test_visibility_and_details()
	_test_unit_events()
	if OS.get_cmdline_user_args().has("--render"):
		await _render_preview()
	print("Unit state feedback checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_pinned_and_recovery() -> void:
	var ui: UnitUi = UI_SCENE.instantiate() as UnitUi
	add_child(ui)
	ui._show_shooting_status()
	ui.state_changed(STATES.MoraleState.PINNED)
	var marker: FEEDBACK = ui.get_node("StateFeedback") as FEEDBACK
	_check(marker.state == FEEDBACK.State.PINNED and marker.is_visible_in_tree(), "Pinning creates the temporary amber notification")
	_check(ui.pinned_texture_rect.visible and not ui.idle_texture_rect.visible and not ui.shooting_texture_rect.visible, "Pinning immediately changes the soldier pose")
	_check((ui.get_node("Timer") as Timer).is_stopped(), "Pinning cancels the shooting pose timer")
	marker.advance(0.3)
	ui.state_changed(STATES.MoraleState.PINNED)
	_check(is_equal_approx(marker.elapsed, 0.3), "Duplicate morale notifications do not restart the transition pulse")
	ui._show_shooting_status()
	_check(ui.pinned_texture_rect.visible and not ui.shooting_texture_rect.visible, "Shooting keeps the pinned pose and marker")
	ui._on_timer_timeout()
	_check(ui.pinned_texture_rect.visible and not ui.idle_texture_rect.visible, "A stale pose timer cannot clear pinning")
	ui.started_moving(false, false)
	ui.stopped_moving(false, false)
	_check(ui.pinned_texture_rect.visible and not ui.moving_texture_rect.visible, "Movement callbacks cannot overwrite the pinned pose")
	marker.advance(10.0)
	_check(not marker.visible and not marker.is_processing() and ui.pinned_texture_rect.visible, "The pinned ribbon disappears while the pinned pose remains")
	ui.state_changed(STATES.MoraleState.CAUTIOUS)
	_check(marker.state == FEEDBACK.State.NONE and not marker.visible and ui.idle_texture_rect.visible, "Recovery removes the marker and restores the normal pose")
	ui.show_pinned()
	_check(marker.state == FEEDBACK.State.PINNED, "The legacy pinned entry point uses the same cue")
	ui.state_changed(STATES.MoraleState.PANIC)
	_check(marker.state == FEEDBACK.State.NONE and ui.broken_texture_rect.visible, "Routing replaces pinning instead of leaving a stale pinned marker")
	ui.free()


func _test_ribbon_fade() -> void:
	for fps: int in [30, 60, 144]:
		for state: FEEDBACK.State in [FEEDBACK.State.PINNED, FEEDBACK.State.SURRENDERED]:
			var ui: UnitUi = UI_SCENE.instantiate() as UnitUi
			add_child(ui)
			if state == FEEDBACK.State.PINNED:
				ui.show_pinned()
			else:
				ui.surrender()
			var marker: FEEDBACK = ui.get_node("StateFeedback") as FEEDBACK
			marker.advance(FEEDBACK.TRANSITION_SECONDS)
			_check(marker.visible and marker.modulate.a == 1.0, "Status text stays readable before fading at %d FPS" % fps)
			var step: float = 1.0 / float(fps)
			for frame: int in range(roundi(FEEDBACK.FADE_SECONDS * float(fps) * 0.5)):
				marker.advance(step)
			_check(marker.visible and marker.modulate.a > 0.35 and marker.modulate.a < 0.65, "The entire status notification fades gradually at %d FPS" % fps)
			var opacity: float = marker.modulate.a
			marker.set_state(state)
			_check(is_equal_approx(marker.modulate.a, opacity), "Repeated state notifications cannot brighten a fading ribbon")
			marker.advance(FEEDBACK.FADE_SECONDS)
			var ribbon_point: Vector2 = marker.get_global_transform_with_canvas() * FEEDBACK.RIBBON_RECT.get_center()
			_check(not marker.visible and not marker.is_processing() and not ui.contains_battlefield_point(ribbon_point), "An expired ribbon disappears and no longer extends the squad's clickable area")
			marker.set_state(state)
			_check(not marker.visible, "Repeated state notifications cannot revive an expired ribbon")
			ui.free()


func _test_terminal_states() -> void:
	var ui: UnitUi = UI_SCENE.instantiate() as UnitUi
	add_child(ui)
	ui.state_changed(STATES.MoraleState.PINNED)
	ui.surrender()
	var marker: FEEDBACK = ui.get_node("StateFeedback") as FEEDBACK
	_check(marker.state == FEEDBACK.State.SURRENDERED and ui.surrendered_texture_rect.visible, "Surrender replaces the pinned cue with the white flag and surrendered pose")
	marker.advance(0.3)
	ui.surrender()
	_check(is_equal_approx(marker.elapsed, 0.3), "Repeated surrender does not restart its pulse")
	ui.state_changed(STATES.MoraleState.NORMAL)
	ui._show_shooting_status()
	ui._on_timer_timeout()
	ui.started_moving(false, true)
	ui.stopped_moving(false, true)
	ui._on_morale_recovered()
	_check(marker.state == FEEDBACK.State.SURRENDERED and ui.surrendered_texture_rect.visible and not ui.idle_texture_rect.visible, "Surrender survives morale, firing, timer and movement callbacks")
	marker.advance(10.0)
	_check(not marker.visible and ui.surrendered_texture_rect.visible, "The surrender ribbon disappears while the surrendered pose remains")
	ui.show_casualty(2)
	ui.die()
	_check(marker.state == FEEDBACK.State.ELIMINATED and marker.visible and marker.modulate.a == 1.0 and ui.dead.visible, "Complete elimination restores a visible skull marker after the surrender ribbon has faded")
	_check(not ui.unit_status_control.visible and not ui.sprite_node.visible and not ui.rank_texture_rect.visible, "An eliminated squad cannot retain a living pose or command badge")
	var casualties: CASUALTIES = ui.get_node("CasualtyFeedback") as CASUALTIES
	_check(casualties.active and casualties.casualty_count == 2, "Elimination preserves the final casualty count above the state ribbon")
	marker.advance(0.4)
	ui.die()
	ui.surrender()
	ui.state_changed(STATES.MoraleState.PINNED)
	ui._show_shooting_status()
	ui._on_timer_timeout()
	ui._on_morale_recovered()
	_check(marker.state == FEEDBACK.State.ELIMINATED and is_equal_approx(marker.elapsed, 0.4), "Late callbacks cannot revive a squad or replay its elimination")
	marker.advance(10.0)
	_check(marker.is_visible_in_tree() and not marker.is_processing(), "The eliminated marker remains after its pulse finishes")
	ui.mark_exited()
	_check(marker.state == FEEDBACK.State.NONE and not marker.visible, "Leaving the map clears persistent markers")
	ui.show_pinned()
	ui.surrender()
	_check(marker.state == FEEDBACK.State.NONE, "Exited units cannot regain a battlefield state marker")
	ui.free()


func _test_visibility_and_details() -> void:
	var ui: UnitUi = UI_SCENE.instantiate() as UnitUi
	var detail: UnitUi = UI_SCENE.instantiate() as UnitUi
	add_child(ui)
	add_child(detail)
	ui.detail_ui = detail
	ui.hide()
	ui.state_changed(STATES.MoraleState.PINNED)
	var marker: FEEDBACK = ui.get_node("StateFeedback") as FEEDBACK
	_check(not marker.is_visible_in_tree() and not marker.is_processing(), "A hidden state change produces no visible transition")
	ui.show()
	_check(not marker.visible and marker.elapsed == FEEDBACK.LIFETIME_SECONDS and ui.pinned_texture_rect.visible, "Revealing a unit keeps its pinned pose without replaying a hidden notification")
	ui.state_changed(STATES.MoraleState.NORMAL)
	ui.show_pinned()
	ui.hide()
	ui.show()
	_check(not marker.visible and not marker.is_processing() and marker.elapsed == FEEDBACK.LIFETIME_SECONDS, "Hiding a unit cancels its pending notification")
	ui.surrender()
	var detail_marker: FEEDBACK = detail.get_node("StateFeedback") as FEEDBACK
	_check(detail_marker.state == FEEDBACK.State.SURRENDERED and detail.surrendered_texture_rect.visible, "The detailed view mirrors surrender state and pose")
	ui.die()
	_check(detail_marker.state == FEEDBACK.State.ELIMINATED and detail.dead.visible, "The detailed view mirrors complete elimination")
	ui.free()
	detail.free()


func _test_elimination_fade() -> void:
	for fps: int in [30, 60, 144]:
		var ui: UnitUi = UI_SCENE.instantiate() as UnitUi
		add_child(ui)
		ui.die()
		ui._elimination_fade.pause()
		var step: float = 1.0 / float(fps)
		for frame: int in range(3 * fps):
			ui._elimination_fade.custom_step(step)
		_check(ui.modulate.is_equal_approx(Color.WHITE), "Elimination stays prominent for the first three seconds at %d FPS" % fps)
		for frame: int in range(ceili(2.5 * float(fps))):
			ui._elimination_fade.custom_step(step)
		_check(ui.modulate.a < 0.9 and ui.modulate.a > UnitUi.ELIMINATION_REST_COLOR.a, "The whole corpse marker gradually fades at %d FPS" % fps)
		ui.hide()
		ui._elimination_fade.custom_step(3.0)
		ui.show()
		_check(ui.modulate.is_equal_approx(UnitUi.ELIMINATION_REST_COLOR), "A dim remnant remains after eight seconds, including time hidden")
		ui.die()
		_check(ui.modulate.is_equal_approx(UnitUi.ELIMINATION_REST_COLOR), "Repeated death callbacks do not brighten old corpses")
		ui.free()


func _test_unit_events() -> void:
	var previous_ground: HexagonTileMapLayer = LOSHelper.ground_layer
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.pathfinding_enabled = false
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_size = Vector2i(128, 128)
	add_child(ground)
	LOSHelper.ground_layer = ground
	var history: CasualtyHistory = Globals.casualty_history
	var destroyed: UnitsCollection = Globals.units_destroyed
	Globals.casualty_history = CasualtyHistory.new()
	Globals.units_destroyed = UnitsCollection.new()
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	add_child(unit)
	unit.position = ground.map_to_local(unit.current_hex)
	unit.movement.unit = unit
	unit.action_controller.init(unit, unit.movement, unit.squad_fire, unit.stress_system, unit.ui)
	unit._setup_runtime_soldiers(unit.squad_loadout)
	unit.stress_system.state_changed.connect(unit._on_state_changed)
	unit.stress_system._set_state(STATES.MoraleState.PINNED)
	var marker: FEEDBACK = unit.ui.get_node("StateFeedback") as FEEDBACK
	_check(marker.state == FEEDBACK.State.PINNED and unit.ui.pinned_texture_rect.visible, "The actual stress controller drives the pinned cue")
	unit.stress_system._set_state(STATES.MoraleState.CAUTIOUS)
	_check(marker.state == FEEDBACK.State.NONE, "Actual unpinning removes the cue")
	unit.surrender()
	_check(unit.surrendered and marker.state == FEEDBACK.State.SURRENDERED, "The actual surrender event drives the white flag cue")
	unit.die()
	_check(not unit.alive and marker.state == FEEDBACK.State.ELIMINATED and marker.can_process(), "Actual elimination overrides surrender while preserving its presentation node")
	unit.squad_fire.calc.free()
	unit.free()
	Globals.casualty_history = history
	Globals.units_destroyed = destroyed
	LOSHelper.ground_layer = previous_ground
	ground.free()


func _render_preview() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(960, 640)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var ground_scene: HexagonTileMapLayer = (load("res://scenes/world/maps/layers/ground_tile_map_layer.tscn") as PackedScene).instantiate() as HexagonTileMapLayer
	var ground: TileMapLayer = TileMapLayer.new()
	ground.tile_set = ground_scene.tile_set
	ground_scene.free()
	viewport.add_child(ground)
	for x: int in range(-3, 13):
		for y: int in range(-3, 10):
			ground.set_cell(Vector2i(x, y), 1, Vector2i.ZERO)
	var camera: Camera2D = Camera2D.new()
	camera.position = Vector2(480.0, 320.0)
	viewport.add_child(camera)
	_caption(viewport, "PINNED / SURRENDERED / ELIMINATED", Vector2(28.0, 24.0), 20)
	_caption(viewport, "Transition cue", Vector2(28.0, 72.0), 14)
	_caption(viewport, "After the notification fades: poses remain visible", Vector2(28.0, 367.0), 14)
	for row: int in range(2):
		for column: int in range(3):
			var ui: UnitUi = UI_SCENE.instantiate() as UnitUi
			ui.position = Vector2(118.0 + float(column) * 300.0, 155.0 + float(row) * 280.0)
			ui.scale = Vector2(2.0, 2.0)
			viewport.add_child(ui)
			ui.update_team_sprite(row, Globals.SquadType.Rifle)
			match column:
				0:
					ui.state_changed(STATES.MoraleState.PINNED)
				1:
					ui.surrender()
				2:
					if row == 0:
						ui.show_casualty(3)
						var losses: CASUALTIES = ui.get_node("CasualtyFeedback") as CASUALTIES
						losses.advance(0.12)
						losses.set_process(false)
					ui.die()
			var marker: FEEDBACK = ui.get_node("StateFeedback") as FEEDBACK
			if row == 0:
				marker.advance(0.12)
			else:
				marker.advance(2.0)
			marker.set_process(false)
	for zoom: float in [1.0, 0.5, 2.0]:
		camera.zoom = Vector2(zoom, zoom)
		await get_tree().process_frame
		await get_tree().process_frame
		RenderingServer.force_draw(false)
		_check(viewport.get_texture().get_image().save_png("/tmp/acl-unit-states-" + str(zoom) + ".png") == OK, "Render state cues at zoom " + str(zoom))
	await _render_elimination_fade(viewport, camera)
	viewport.free()


func _render_elimination_fade(viewport: SubViewport, camera: Camera2D) -> void:
	for child: Node in viewport.get_children():
		if child is UnitUi or child is Label:
			child.queue_free()
	await get_tree().process_frame
	camera.zoom = Vector2.ONE
	_caption(viewport, "ELIMINATED UNITS FADE OVER TIME", Vector2(28.0, 24.0), 20)
	_caption(viewport, "Full emphasis for 3 seconds / fade over 5 seconds / dim remnant remains", Vector2(28.0, 64.0), 14)
	var ages: Array[float] = [0.0, 5.5, 8.0]
	var captions: Array[String] = ["Just eliminated", "Fading: 5.5 seconds", "Subdued: 8 seconds"]
	for index: int in range(3):
		var ui: UnitUi = UI_SCENE.instantiate() as UnitUi
		ui.position = Vector2(118.0 + float(index) * 300.0, 240.0)
		ui.scale = Vector2(2.0, 2.0)
		viewport.add_child(ui)
		ui.die()
		ui._elimination_fade.pause()
		ui._elimination_fade.custom_step(ages[index])
		var marker: FEEDBACK = ui.get_node("StateFeedback") as FEEDBACK
		marker.advance(maxf(0.12, ages[index]))
		marker.set_process(false)
		_caption(viewport, captions[index], ui.position + Vector2(-12.0, 186.0), 14)
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	_check(viewport.get_texture().get_image().save_png("/tmp/acl-elimination-fade.png") == OK, "Render fresh, fading and subdued corpse markers")


func _caption(parent: Node, text: String, point: Vector2, font_size: int) -> void:
	var label: Label = Label.new()
	label.position = point
	label.text = text
	label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88))
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
