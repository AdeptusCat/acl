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
	_test_terminal_states()
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
	_check(marker.state == FEEDBACK.State.PINNED and marker.is_visible_in_tree(), "Pinning creates the persistent amber marker")
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
	_check(marker.is_visible_in_tree() and not marker.is_processing(), "The pinned marker persists without an idle animation cost")
	ui.state_changed(STATES.MoraleState.CAUTIOUS)
	_check(marker.state == FEEDBACK.State.NONE and not marker.visible and ui.idle_texture_rect.visible, "Recovery removes the marker and restores the normal pose")
	ui.show_pinned()
	_check(marker.state == FEEDBACK.State.PINNED, "The legacy pinned entry point uses the same cue")
	ui.state_changed(STATES.MoraleState.PANIC)
	_check(marker.state == FEEDBACK.State.NONE and ui.broken_texture_rect.visible, "Routing replaces pinning instead of leaving a stale pinned marker")
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
	ui.show_casualty(2)
	ui.die()
	_check(marker.state == FEEDBACK.State.ELIMINATED and ui.dead.visible, "Complete elimination replaces surrender with the skull marker")
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
	_check(marker.is_visible_in_tree() and marker.elapsed == FEEDBACK.TRANSITION_SECONDS, "Revealing a unit shows its current state without replaying a hidden event")
	ui.state_changed(STATES.MoraleState.NORMAL)
	ui.show_pinned()
	ui.hide()
	ui.show()
	_check(not marker.is_processing() and marker.elapsed == FEEDBACK.TRANSITION_SECONDS, "Hiding a unit cancels its pending transition pulse")
	ui.surrender()
	var detail_marker: FEEDBACK = detail.get_node("StateFeedback") as FEEDBACK
	_check(detail_marker.state == FEEDBACK.State.SURRENDERED and detail.surrendered_texture_rect.visible, "The detailed view mirrors surrender state and pose")
	ui.die()
	_check(detail_marker.state == FEEDBACK.State.ELIMINATED and detail.dead.visible, "The detailed view mirrors complete elimination")
	ui.free()
	detail.free()


func _test_unit_events() -> void:
	var history: CasualtyHistory = Globals.casualty_history
	var destroyed: UnitsCollection = Globals.units_destroyed
	Globals.casualty_history = CasualtyHistory.new()
	Globals.units_destroyed = UnitsCollection.new()
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	add_child(unit)
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
	_caption(viewport, "Persistent marker after the pulse finishes", Vector2(28.0, 367.0), 14)
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
	viewport.free()


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
