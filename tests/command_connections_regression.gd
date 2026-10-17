extends Node

const UNIT_SCENE: PackedScene = preload("res://scenes/game/units/unit.tscn")
const RENDERER: Script = preload("res://scenes/world/overlays/command_connectivity_renderer.gd")

var checks: int = 0
var failures: int = 0
var units: Array[Unit] = []
var viewport: SubViewport
var battlefield: Node2D
var renderer: CommandConnectivityRenderer
var company: Unit
var headquarters: Unit
var rifle: Unit
var machine_gun: Unit
var isolated: Unit
var enemy_hq: Unit
var enemy: Unit


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--render"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_run.call_deferred()


func _run() -> void:
	name = "Main"
	var audio_world: Node = Node.new()
	audio_world.name = "World"
	add_child(audio_world)
	var audio: AudioPool = AudioPool.new()
	audio.name = "AudioPool"
	audio_world.add_child(audio)
	Globals.team_player = Globals.Team.AXIS
	Debug.showEnemyCmdConnectivity = false
	SessionSettings.showCmdConnectivity = false
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 600)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var background: ColorRect = ColorRect.new()
	background.color = Color("43533a")
	background.size = Vector2(960.0, 600.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(background)
	battlefield = Node2D.new()
	battlefield.name = "World"
	battlefield.position = Vector2(24.0, 18.0)
	viewport.add_child(battlefield)
	company = _unit(Vector2(170.0, 160.0), Globals.SquadType.COMPANY_HEADQUARTERS)
	headquarters = _unit(Vector2(440.0, 160.0), Globals.SquadType.PLATOON_HEADQUARTERS, company)
	rifle = _unit(Vector2(210.0, 390.0), Globals.SquadType.Rifle, headquarters)
	machine_gun = _unit(Vector2(700.0, 360.0), Globals.SquadType.MG, headquarters)
	isolated = _unit(Vector2(780.0, 150.0), Globals.SquadType.Rifle, headquarters)
	_set_contact(isolated, 0.0, 0.0)
	enemy_hq = _unit(Vector2(160.0, 520.0), Globals.SquadType.PLATOON_HEADQUARTERS)
	enemy_hq.team = Globals.Team.ALLIES
	enemy = _unit(Vector2(420.0, 520.0), Globals.SquadType.Rifle, enemy_hq)
	enemy.team = Globals.Team.ALLIES
	renderer = RENDERER.new() as CommandConnectivityRenderer
	battlefield.add_child(renderer)
	renderer.setup()
	renderer.set_process(false)
	_test_selection()
	_test_contact_and_pulses()
	_test_visibility_and_lifecycle()
	_test_geometry()
	_test_roster_contact()
	await _test_settings()
	await _test_freed_units()
	_test_sight_range()
	if OS.get_cmdline_user_args().has("--render"):
		await _render_preview()
	for unit: Unit in units:
		if is_instance_valid(unit.squad_fire.calc):
			unit.squad_fire.calc.free()
	viewport.free()
	print("Command connection checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _unit(point: Vector2, type: Globals.SquadType, commander: Unit = null) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.squad_type = type
	unit.squad = units.size() + 1
	unit.platoon = 1
	unit.position = point
	unit.command_squad = commander
	battlefield.add_child(unit)
	unit.add_to_group("units")
	_freeze(unit)
	unit.ui.update_team_sprite(unit.team, type)
	_set_contact(unit, 0.9, 0.25)
	units.append(unit)
	return unit


func _set_contact(unit: Unit, strength: float, presence: float) -> void:
	unit.command_connectivity.runner_chain_to_leader = true
	unit.command_connectivity.command_link_strength = strength
	unit.command_connectivity.leader_presence_strength = presence


func _test_selection() -> void:
	_check(renderer._links_layer.get_index() < rifle.get_index(), "Command strokes draw behind the counters while badges stay above them")
	_check(renderer.displayed_links.is_empty(), "Unselected relationships stay quiet with command view off")
	_check(renderer.badge_text(isolated) == "No contact", "An unselected isolated squad retains a readable badge")
	_check(renderer.badge_text(company).is_empty(), "The top-level HQ is not falsely marked isolated")
	rifle.select()
	renderer.refresh(0.0)
	_check(renderer.displayed_links == [rifle], "Selecting a squad reveals only its immediate command link")
	_check(renderer.highlighted_units.has(headquarters.get_instance_id()) and renderer.highlighted_units[headquarters.get_instance_id()] == "HQ", "Squad selection highlights its actual commanding HQ")
	_check(renderer.badge_text(headquarters) == "HQ" and renderer.badge_text(rifle).is_empty(), "A stable selected link identifies the HQ without persistent contact text over nearby counters")
	rifle.deselect()
	headquarters.select()
	renderer.refresh(0.0)
	_check(renderer.displayed_links.size() == 4 and renderer.displayed_links.has(rifle) and renderer.displayed_links.has(isolated), "Selecting a platoon HQ reveals its squads and its own superior")
	_check(renderer.highlighted_units.has(rifle.get_instance_id()) and renderer.highlighted_units.has(machine_gun.get_instance_id()), "HQ selection highlights subordinate counters")
	_check(renderer.badge_text(rifle).is_empty() and renderer.badge_text(machine_gun).is_empty(), "Selecting an HQ leaves its connected subordinates free of contact labels")
	headquarters.deselect()
	company.select()
	renderer.refresh(0.0)
	_check(renderer.displayed_links == [headquarters], "Company HQ selection shows only its direct platoon HQ connections")
	_check(renderer.highlighted_units.size() == 1 and renderer.highlighted_units.has(headquarters.get_instance_id()), "Company HQ selection highlights platoon leaders without highlighting their squads")
	SessionSettings.showCmdConnectivity = true
	renderer.refresh(0.0)
	_check(renderer.displayed_links.size() == 4 and renderer.highlighted_units.size() == 1 and renderer.highlighted_units.has(headquarters.get_instance_id()), "Full command view preserves the company selection's platoon-only highlights")
	company.deselect()
	SessionSettings.showCmdConnectivity = true
	renderer.refresh(0.0)
	_check(renderer.displayed_links.size() == 4 and not renderer.displayed_links.has(enemy), "Command view shows the friendly hierarchy without enemy information")
	SessionSettings.showCmdConnectivity = false
	renderer.refresh(0.0)
	_check(renderer.displayed_links.is_empty() and renderer.highlighted_units.is_empty(), "Deselecting clears selection highlights while keeping lost contact badges")


func _test_contact_and_pulses() -> void:
	_check(is_equal_approx(renderer._cues[rifle.get_instance_id()].elapsed, renderer.PULSE_SECONDS), "Initial contact does not generate a false transition pulse")
	_set_contact(rifle, 0.6, 1.0)
	renderer.refresh(0.0)
	_check(CommandConnectivity.contact_state_for(rifle) == CommandConnectivity.ContactState.LIMITED, "Actual communication strength drives contact, independently of strong leadership presence")
	_check(renderer._cues[rifle.get_instance_id()].elapsed == 0.0 and renderer.badge_text(rifle) == "Limited", "A change in contact emits a brief labeled cue")
	renderer.refresh(0.4)
	_check(is_equal_approx(renderer._cues[rifle.get_instance_id()].elapsed, 0.4), "Repeated updates do not restart an unchanged contact pulse")
	_set_contact(rifle, 0.0, 1.0)
	renderer.refresh(0.0)
	renderer.refresh(3.0)
	_check(renderer.badge_text(rifle) == "No contact", "Lost contact remains labeled after its finite pulse finishes")
	_check(renderer._cues[rifle.get_instance_id()].elapsed == renderer.PULSE_SECONDS, "The contact warning does not pulse indefinitely")
	_set_contact(rifle, 0.9, 0.0)
	renderer.refresh(0.0)
	_check(renderer.badge_text(rifle) == "Connected", "Restored contact pulses even when leadership presence is zero")
	renderer.refresh(3.0)
	_check(renderer.badge_text(rifle).is_empty(), "A recovered unselected squad returns to a quiet counter")
	_check(RENDERER.line_pattern(CommandConnectivity.ContactState.CONNECTED).is_empty(), "Connected links use a solid stroke")
	_check(RENDERER.line_pattern(CommandConnectivity.ContactState.LIMITED) != RENDERER.line_pattern(CommandConnectivity.ContactState.LOST), "Limited and lost links have distinct non-color patterns")
	_check(CommandConnectivity.contact_method_for(rifle) == "Runner", "The current contact method is available as readable text")


func _test_visibility_and_lifecycle() -> void:
	SessionSettings.showCmdConnectivity = true
	enemy.hide()
	Debug.showEnemyCmdConnectivity = true
	renderer.refresh(0.0)
	_check(not renderer.displayed_links.has(enemy) and renderer.badge_text(enemy).is_empty(), "Even enemy debug mode does not draw hidden squads")
	enemy.show()
	renderer.refresh(0.0)
	_check(renderer.displayed_links.has(enemy), "Explicit enemy debug mode can display a visible enemy hierarchy")
	enemy_hq.hide()
	renderer.refresh(0.0)
	_check(not renderer.displayed_links.has(enemy), "Visible enemies do not reveal a hidden HQ position")
	enemy_hq.show()
	Debug.showEnemyCmdConnectivity = false
	headquarters.surrendered = true
	renderer.refresh(0.0)
	_check(not renderer.displayed_links.has(rifle) and renderer.badge_text(rifle) == "No contact", "A surrendered HQ stops providing a command link")
	headquarters.surrendered = false
	headquarters.alive = false
	renderer.refresh(0.0)
	_check(renderer.badge_text(machine_gun) == "No contact", "A dead HQ immediately leaves its squads out of contact")
	headquarters.alive = true
	rifle.hide()
	_set_contact(rifle, 0.0, 0.0)
	renderer.refresh(0.0)
	rifle.show()
	renderer.refresh(0.0)
	_check(renderer.badge_text(rifle) == "No contact" and renderer._cues[rifle.get_instance_id()].elapsed == renderer.PULSE_SECONDS, "Revealing a squad shows its state without replaying a hidden contact event")
	_set_contact(rifle, 0.9, 0.25)
	renderer.refresh(3.0)
	var reinforcement: Unit = _unit(Vector2(760.0, 510.0), Globals.SquadType.Rifle, headquarters)
	renderer.refresh(0.0)
	_check(renderer.displayed_links.has(reinforcement), "New squads join the command view after initial setup")
	reinforcement.exited = true
	reinforcement.remove_from_group("units")
	renderer.refresh(0.0)
	_check(not renderer.displayed_links.has(reinforcement) and not renderer._cues.has(reinforcement.get_instance_id()), "Exited squads leave both links and transition tracking")
	SessionSettings.showCmdConnectivity = false


func _test_geometry() -> void:
	rifle.select()
	var saved: Vector2 = rifle.position
	var points: PackedVector2Array
	for offset: Vector2 in [Vector2.ZERO, Vector2(0.0, 32.0), Vector2(128.0, 0.0)]:
		rifle.position = headquarters.position + offset
		renderer.refresh(0.0)
		points = renderer.link_points(rifle)
		_check(points.size() == 2 and points[0].is_equal_approx(renderer.counter_rect(rifle).get_center()) and points[1].is_equal_approx(renderer.counter_rect(headquarters).get_center()), "Stacked and nearby units use a straight center-to-center command link at offset %s" % offset)
	rifle.position = saved
	points = renderer.link_points(rifle)
	_check(not renderer.counter_rect(rifle).has_point(points[0]) and not renderer.counter_rect(headquarters).has_point(points[1]), "Link endpoints stop outside the actual visible counter bounds")
	headquarters.command_squad = rifle
	renderer.refresh(0.0)
	_check(renderer.displayed_links.size() <= units.size(), "An accidental hierarchy cycle terminates safely")
	headquarters.command_squad = company
	rifle.deselect()


func _test_settings() -> void:
	var hud: Control = Control.new()
	hud.size = Vector2(1280.0, 720.0)
	add_child(hud)
	var settings: Control = (load("res://scenes/ui/panels/battle_settings_panel.tscn") as PackedScene).instantiate() as Control
	hud.add_child(settings)
	settings.command_view_button.button_pressed = true
	_check(SessionSettings.showCmdConnectivity and settings.command_links.button_pressed, "The toolbar enables command view and synchronizes Settings")
	settings.command_links.button_pressed = false
	_check(not SessionSettings.showCmdConnectivity and not settings.command_view_button.button_pressed, "The Settings checkbox synchronizes the toolbar without feedback loops")
	SessionSettings.showCmdConnectivity = true
	_check(settings.command_links.button_pressed and settings.command_view_button.button_pressed, "Programmatic session changes keep both command controls synchronized")
	SessionSettings.showCmdConnectivity = false
	hud.queue_free()
	await get_tree().process_frame


func _test_roster_contact() -> void:
	var row: SquadRosterRow = (load("res://scenes/ui/units/squad_roster_row.tscn") as PackedScene).instantiate() as SquadRosterRow
	row.unit = rifle
	add_child(row)
	_set_contact(rifle, 0.0, 1.0)
	row.refresh()
	_check(row.isolation.visible and row.isolation.text == "No contact", "Roster and map use the same explicit lost-contact label")
	_set_contact(rifle, 0.6, 0.0)
	row.refresh()
	_check(not row.isolation.visible and row.tooltip_text.contains("Limited · Runner"), "Runner contact is described separately from leadership support in the roster")
	rifle.command_connectivity.command_unit_state = STATES.MoraleState.PANIC
	row.refresh()
	_check(row.isolation.visible, "Zero effective command strength produces the same status in every view")
	rifle.command_connectivity.command_unit_state = STATES.MoraleState.NORMAL
	row.unit = company
	row.refresh()
	_check(not row.isolation.visible and row.tooltip_text.contains("Top-level headquarters"), "A headquarters without a superior is consistently treated as the top of its hierarchy")
	row.free()


func _test_freed_units() -> void:
	var doomed: Unit = _unit(Vector2(650.0, 510.0), Globals.SquadType.Rifle, headquarters)
	doomed.select()
	renderer.refresh(0.0)
	units.erase(doomed)
	doomed.squad_fire.calc.free()
	doomed.free()
	# A redraw can occur before the renderer's next process tick prunes its cache.
	renderer.queue_redraw()
	renderer._links_layer.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	renderer.refresh(0.0)
	_check(renderer.displayed_links.is_empty() and renderer._cues.size() == Globals.get_units().size(), "Freeing a selected squad between refresh and draw leaves no stale presentation references")


func _test_sight_range() -> void:
	var saved_ground: HexagonTileMapLayer = LOSHelper.ground_layer
	var saved_lookup: Dictionary = LOSHelper.los_lookup
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.pathfinding_enabled = false
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ground.tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	ground.tile_set.tile_size = Vector2i(128, 128)
	battlefield.add_child(ground)
	LOSHelper.ground_layer = ground
	var observer: Unit = _unit(Vector2(200.0, 300.0), Globals.SquadType.Rifle)
	var leader: Unit = _unit(Vector2(600.0, 300.0), Globals.SquadType.PLATOON_HEADQUARTERS)
	observer.command_squad = leader
	observer.current_cube = Vector3i.ZERO
	observer.current_hex = ground.cube_to_map(observer.current_cube)
	leader.stress_system.state = STATES.MoraleState.NORMAL
	var link: CommandConnectivity = observer.command_connectivity
	var directions: Array[Vector3i] = [Vector3i(1, -1, 0), Vector3i(1, 0, -1), Vector3i(0, 1, -1), Vector3i(-1, 1, 0), Vector3i(-1, 0, 1), Vector3i(0, -1, 1)]
	for direction: Vector3i in directions:
		for distance: int in [1, 2, 3, 4]:
			leader.current_cube = direction * distance
			leader.current_hex = ground.cube_to_map(leader.current_cube)
			LOSHelper.los_lookup = {observer.current_hex: {leader.current_hex: {"hindrance": 0}}}
			link.compute_connectivity(observer, leader)
			if distance == 1:
				_check(link.los_to_leader and link.voice_range_to_leader and CommandConnectivity.contact_method_for(observer) == "Voice + sight", "Adjacent unobstructed HQ retains combined voice and sight in direction %s" % direction)
			elif distance <= 3:
				_check(link.los_to_leader and not link.voice_range_to_leader and CommandConnectivity.contact_method_for(observer) == "Sight", "Clear sight provides contact at %d hexes in direction %s" % [distance, direction])
				_check(is_equal_approx(link.command_link_strength, 0.8) and CommandConnectivity.contact_state_for(observer) == CommandConnectivity.ContactState.CONNECTED, "Sight alone provides reliable command contact outside voice range")
				_check(is_equal_approx(link.leader_presence_strength, 0.4), "Distant sight contact keeps its separate lower leadership presence")
			else:
				_check(not link.los_to_leader and CommandConnectivity.contact_method_for(observer) == "Runner", "A visible HQ beyond three hexes falls back to runner contact")
			if distance <= 3:
				for hindrance: int in [1, 2]:
					LOSHelper.los_lookup = {observer.current_hex: {leader.current_hex: {"hindrance": hindrance}}}
					link.compute_connectivity(observer, leader)
					if hindrance == 1:
						_check(link.los_to_leader, "One hindrance still permits sight contact at %d hexes in direction %s" % [distance, direction])
					else:
						_check(not link.los_to_leader and CommandConnectivity.contact_method_for(observer) == "Runner" and is_equal_approx(link.command_link_strength, 0.6), "Two hindrances obstruct sight contact and fall back to runners at %d hexes in direction %s" % [distance, direction])
				# Obstructed paths are absent from the actual baked visibility table.
				LOSHelper.los_lookup = {observer.current_hex: {}}
				link.compute_connectivity(observer, leader)
				_check(not link.los_to_leader and CommandConnectivity.contact_method_for(observer) != "Sight", "An obstruction prevents sight contact at %d hexes in direction %s" % [distance, direction])
	leader.current_cube = directions[0] * 3
	leader.current_hex = ground.cube_to_map(leader.current_cube)
	LOSHelper.los_lookup = {observer.current_hex: {leader.current_hex: {"hindrance": 0}}}
	link.compute_connectivity(observer, leader)
	link.runner_chain_to_leader = false
	_check(CommandConnectivity.contact_method_for(observer) == "Sight" and is_equal_approx(link.command_link_strength, 0.8), "Sight works without any runner or voice channel")
	link.radio_link_to_leader = true
	_check(CommandConnectivity.contact_method_for(observer) == "Radio" and is_equal_approx(link.command_link_strength, 1.0), "Radio remains the preferred contact when available")
	link.radio_link_to_leader = false
	leader.stress_system.state = STATES.MoraleState.PINNED
	link.compute_connectivity(observer, leader)
	_check(CommandConnectivity.contact_method_for(observer) == "Sight" and link.command_link_strength > 0.0 and CommandConnectivity.contact_state_for(observer) == CommandConnectivity.ContactState.LIMITED, "HQ suppression reduces sight contact effectiveness without removing the sight channel")
	leader.stress_system.state = STATES.MoraleState.NORMAL
	leader.current_cube = observer.current_cube
	leader.current_hex = observer.current_hex
	LOSHelper.los_lookup = {}
	link.compute_connectivity(observer, leader)
	_check(link.los_to_leader and CommandConnectivity.contact_method_for(observer) == "Voice + sight", "Squads in the HQ's own hex have sight contact despite the omitted self-LOS entry")
	LOSHelper.ground_layer = saved_ground
	LOSHelper.los_lookup = saved_lookup
	for unit: Unit in [observer, leader]:
		units.erase(unit)
		unit.squad_fire.calc.free()
		unit.free()
	ground.free()
	renderer.refresh(0.0)


func _render_preview() -> void:
	var camera: Camera2D = Camera2D.new()
	camera.position = Vector2(480.0, 300.0)
	viewport.add_child(camera)
	camera.make_current()
	for unit: Unit in units:
		unit.hide()
	rifle.show()
	headquarters.show()
	rifle.position = Vector2(150.0, 300.0)
	headquarters.position = Vector2(760.0, 300.0)
	rifle.select()
	for zoom: float in [0.5, 1.0, 2.0]:
		camera.zoom = Vector2(zoom, zoom)
		await get_tree().process_frame
		await get_tree().process_frame
		for state: int in range(3):
			var strengths: Array[float] = [0.9, 0.6, 0.0]
			_set_contact(rifle, strengths[state], 0.25)
			renderer.refresh(3.0)
			renderer.refresh(3.0)
			await get_tree().process_frame
			await get_tree().process_frame
			RenderingServer.force_draw(false)
			var image: Image = viewport.get_texture().get_image()
			_check(image.save_png("/tmp/acl-command-%s-%s.png" % [str(zoom), str(state)]) == OK, "Capture command state %d at zoom %.1f" % [state, zoom])
			if state == 0:
				var points: PackedVector2Array = renderer.link_points(rifle)
				var point: Vector2i = Vector2i((points[0] + points[1]) * 0.5)
				var width: int = 0
				for y: int in range(point.y - 8, point.y + 9):
					var pixel: Color = image.get_pixel(point.x, y)
					if pixel.g > 0.65 and pixel.r > 0.5 and pixel.b > 0.5:
						width += 1
				_check(width >= 2 and width <= 4, "Rendered link stays three screen pixels wide at zoom %.1f (measured %d)" % [zoom, width])
	camera.zoom = Vector2.ONE
	rifle.position = Vector2(370.0, 300.0)
	rifle.command_connectivity.voice_range_to_leader = true
	rifle.command_connectivity.los_to_leader = true
	_set_contact(rifle, 0.9, 0.25)
	var nearby_offsets: Dictionary[String, Vector2] = {"adjacent": Vector2(128.0, 0.0), "diagonal": Vector2(64.0, -112.0), "shared-hex": Vector2(0.0, -32.0)}
	for arrangement: String in nearby_offsets:
		headquarters.position = rifle.position + nearby_offsets[arrangement]
		renderer.refresh(3.0)
		renderer.refresh(3.0)
		await get_tree().process_frame
		await get_tree().process_frame
		RenderingServer.force_draw(false)
		_check(viewport.get_texture().get_image().save_png("/tmp/acl-command-%s.png" % arrangement) == OK, "Capture nearby HQ without an overlapping connection label: " + arrangement)


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
