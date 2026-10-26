extends Node

const FEEDBACK: Script = preload("res://scenes/game/effects/close_combat_feedback.gd")
const UI_SCENE: PackedScene = preload("res://scenes/game/units/presentation/unit_battlefield_view.tscn")

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--render"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_run.call_deferred()


func _marker(parent: Node, location: Vector2) -> FEEDBACK:
	var marker: FEEDBACK = FEEDBACK.new()
	marker.visibility_test = func() -> bool: return true
	parent.add_child(marker)
	marker.global_position = location
	marker.set_force(Globals.Team.ALLIES, 12, "ATTACKING")
	marker.set_force(Globals.Team.AXIS, 10, "DEFENDING")
	marker.set_process(false)
	return marker


func _run() -> void:
	var marker: FEEDBACK = _marker(self, Vector2.ZERO)
	seed(892)
	var expected_random: float = randf()
	seed(892)
	marker.record_exchange(Globals.Team.ALLIES, Globals.Team.AXIS, false)
	_check(randf() == expected_random, "Cosmetic attack variation does not consume combat RNG")
	_check(marker.recent_losses[Globals.Team.AXIS] == 0, "An attack flash does not imply a casualty")
	marker.record_exchange(Globals.Team.ALLIES, Globals.Team.AXIS, true)
	marker.record_exchange(Globals.Team.ALLIES, Globals.Team.AXIS, true)
	_check(marker.recent_losses[Globals.Team.AXIS] == 2, "Rapid confirmed losses combine in one side-specific cue")
	for strike: int in range(100):
		marker.record_exchange(Globals.Team.AXIS, Globals.Team.ALLIES, true)
	_check(marker.strikes.size() == FEEDBACK.MAX_STRIKES, "Dense close combat keeps a bounded effect budget")
	marker.advance(FEEDBACK.STRIKE_SECONDS)
	_check(marker.strikes.is_empty(), "Attack flashes and dust expire")
	marker.advance(FEEDBACK.LOSS_SECONDS)
	_check(marker.recent_losses[Globals.Team.ALLIES] == 0 and marker.recent_losses[Globals.Team.AXIS] == 0, "Casualty cues expire without changing the living roster")
	marker.visibility_test = func() -> bool: return false
	marker.advance(0.0)
	marker.record_exchange(Globals.Team.ALLIES, Globals.Team.AXIS, true)
	_check(not marker.visible and marker.strikes.is_empty() and marker.recent_losses[Globals.Team.AXIS] == 0, "Hidden encounters discard attack and loss notifications")
	marker.visibility_test = func() -> bool: return true
	marker.advance(0.0)
	_check(marker.visible and marker.strikes.is_empty(), "A later reveal does not replay hidden combat")
	marker.set_force(Globals.Team.AXIS, -1, "ENGAGED")
	marker.record_exchange(Globals.Team.ALLIES, Globals.Team.AXIS, true)
	_check(marker.recent_losses[Globals.Team.AXIS] == 0, "Unknown enemy losses stay unconfirmed")
	marker.set_force(Globals.Team.AXIS, 0, "ENGAGED")
	marker.finish()
	_check(marker.resolved and marker.result_text == "US HOLDS HEX", "A single remaining side receives an outcome")
	marker.advance(FEEDBACK.RESULT_SECONDS - 0.3)
	_check(marker.modulate.a > 0.0 and marker.modulate.a < 1.0, "The result fades before cleanup")
	marker.advance(0.31)
	_check(marker.is_queued_for_deletion(), "Completed results release their node")
	for fps: int in [30, 60, 144]:
		var ended: FEEDBACK = _marker(self, Vector2.ZERO)
		ended.finish()
		_check(ended.result_text == "COMBAT ENDED", "Ending an encounter with both sides present does not invent a winner")
		for frame: int in range(ceili((FEEDBACK.RESULT_SECONDS + 0.01) * float(fps))):
			ended.advance(1.0 / float(fps))
		_check(ended.is_queued_for_deletion(), "Results expire at %d FPS" % fps)
	if OS.get_cmdline_user_args().has("--render"):
		await _render_preview()
	print("Close combat feedback checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _render_preview() -> void:
	var previous_player: Globals.Team = Globals.team_player
	Globals.team_player = Globals.Team.ALLIES
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1120, 720)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var ground: HexagonTileMapLayer = (load("res://scenes/world/maps/layers/ground_tile_map_layer.tscn") as PackedScene).instantiate() as HexagonTileMapLayer
	viewport.add_child(ground)
	for x: int in range(-2, 12):
		for y: int in range(-2, 9):
			ground.set_cell(Vector2i(x, y), 1, Vector2i.ZERO)
	var camera: Camera2D = Camera2D.new()
	camera.position = Vector2(560.0, 360.0)
	viewport.add_child(camera)
	var title: Label = Label.new()
	title.text = "CLOSE COMBAT / LIVE EXCHANGES, CONFIRMED LOSSES, OUTCOME"
	title.position = Vector2(28.0, 24.0)
	viewport.add_child(title)
	var markers: Array[FEEDBACK] = []
	var captions: Array[String] = ["CONTACT", "CASUALTIES", "RESOLVED"]
	for index: int in range(3):
		var center: Vector2 = ground.map_to_local(Vector2i(1 + index * 3, 3))
		var marker: FEEDBACK = _marker(viewport, center)
		var shape: ConvexPolygonShape2D = ground.geometry_tile_shape.shape as ConvexPolygonShape2D
		marker.outline = shape.points
		markers.append(marker)
		if index == 1:
			marker.set_force(Globals.Team.AXIS, 7, "DEFENDING")
		for team: Globals.Team in [Globals.Team.ALLIES, Globals.Team.AXIS]:
			if index == 2 and team == Globals.Team.AXIS:
				continue
			var ui: UnitUi = UI_SCENE.instantiate() as UnitUi
			viewport.add_child(ui)
			ui.update_team_sprite(team, Globals.SquadType.Rifle)
			ui.set_members_alive(marker.counts[team])
			ui.position = center + Vector2(-48.0, -10.0)
			if team == Globals.Team.AXIS:
				ui.position = center + Vector2(4.0, -10.0)
			ui.set_process(false)
			if (index == 1 and team == Globals.Team.AXIS) or (index == 2 and team == Globals.Team.ALLIES):
				var losses: int = 1
				if index == 1:
					losses = 3
				ui.show_casualty(losses)
				ui._casualty_feedback.suppress_badge()
				ui._casualty_feedback.set_process(false)
		for strike: int in range(5):
			marker.advance(0.08)
			marker.record_exchange(Globals.Team.ALLIES, Globals.Team.AXIS, index == 1 and strike >= 2)
			marker.record_exchange(Globals.Team.AXIS, Globals.Team.ALLIES, false)
		if index == 1:
			marker.set_force(Globals.Team.AXIS, 7, "DEFENDING")
		elif index == 2:
			marker.set_force(Globals.Team.AXIS, 0, "ENGAGED")
			marker.finish()
		var label: Label = Label.new()
		label.text = captions[index]
		label.position = center + Vector2(-45.0, 100.0)
		viewport.add_child(label)
	for zoom: float in [1.0, 0.6, 1.5]:
		camera.zoom = Vector2.ONE * zoom
		for marker: FEEDBACK in markers:
			marker.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
		RenderingServer.force_draw(false)
		var preview: Image = viewport.get_texture().get_image()
		_check(preview.save_png("/tmp/acl-close-combat-feedback-" + str(zoom) + ".png") == OK, "Render close combat at zoom " + str(zoom))
	camera.zoom = Vector2.ONE
	for marker: FEEDBACK in markers:
		marker.hide()
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var baseline: Image = viewport.get_texture().get_image()
	for marker: FEEDBACK in markers:
		marker.show()
		marker.visibility_test = func() -> bool: return false
		marker.queue_redraw()
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	_check(viewport.get_texture().get_image().get_data() == baseline.get_data(), "Hidden combat overlays contribute no rendered pixels")
	viewport.free()
	Globals.team_player = previous_player


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
