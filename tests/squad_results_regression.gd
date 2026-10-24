extends Node

class UnitProbe extends Unit:
	func _ready() -> void:
		pass

	func _make_squad() -> void:
		pass


var checks: int = 0
var failures: int = 0
var screen: CanvasLayer
var scenario: Scenario
var units: Array[Unit] = []
var reduced: Unit


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var audio_root: Node = Node.new()
	audio_root.name = "Main"
	get_tree().root.add_child(audio_root)
	var world: Node = Node.new()
	world.name = "World"
	audio_root.add_child(world)
	var audio: AudioPool = AudioPool.new()
	audio.name = "AudioPool"
	world.add_child(audio)
	scenario = Scenario.new()
	scenario.scenario_name = "Quiet Approach"
	Globals.scenario_chosen = scenario
	Globals.team_player = Globals.Team.ALLIES
	Globals.battle_casualties.clear()
	Globals.battle_exits.clear()
	_build_units()
	screen = load("res://scenes/ui/screens/match_result_screen.tscn").instantiate()
	add_child(screen)
	screen._on_show_winner(Globals.Team.ALLIES)
	await _settle()
	_test_squads()
	_test_icons()
	_check(screen.player_casualties.text == "8" and screen.enemy_casualties.text == "12", "Per-squad results preserve soldier casualty totals")
	_check(screen.player_exits.text == "1" and screen.enemy_exits.text == "1" and screen.player_exited_soldiers.text == "2" and screen.enemy_exited_soldiers.text == "4",
		"Exit totals retain both squad counts and surviving soldier counts")
	_check(screen.body.current_tab == 0, "The result opens on the squad icons")
	_check_inside()
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		_check(image.save_png("/tmp/acl-squad-results.png") == OK, "The squad result screen is captured")
	Globals.team_player = Globals.Team.AXIS
	screen._on_show_winner(Globals.Team.AXIS)
	_check((screen.player_squads.get_child(1) as HBoxContainer).strength.text.begins_with("0/10"), "Squad columns follow the player's faction")
	_check(screen.player_squads_heading.text.contains("Axis") and screen.enemy_squads_heading.text.contains("Allies"), "Squad headings identify the correct factions")
	Globals.team_player = Globals.Team.ALLIES
	reduced.members_alive = 7
	screen._on_show_winner(Globals.Team.ALLIES)
	_check(screen.player_squads.get_child_count() == 4 and (screen.player_squads.get_child(1) as HBoxContainer).strength.text == "7/12 soldiers remain · 5 lost",
		"Repeated results replace squad rows with current strength")
	# Reinforcements and large forces must scroll without pushing the actions away.
	for index: int in range(24):
		_unit(Globals.Team.ALLIES, Globals.SquadType.Rifle, index + 4, 10, 10)
	screen._on_show_winner(Globals.Team.ALLIES)
	for resolution: Vector2i in [Vector2i(1024, 600), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		get_tree().root.size = resolution
		await _settle()
		_check_inside()
		var bar: VScrollBar = screen.squads_scroll.get_v_scroll_bar()
		_check(bar.max_value > bar.page, "Large forces scroll within the squad tab")
	# Unit nodes may be freed after a result; displayed rows retain only their snapshot.
	for unit: Unit in units:
		unit.squad_fire.calc.free()
		unit.free()
	units.clear()
	_check((screen.player_squads.get_child(1) as HBoxContainer).strength.text == "7/12 soldiers remain · 5 lost", "A displayed squad result does not depend on a live Unit reference")
	screen._on_show_winner(Globals.Team.ALLIES)
	_check(screen.player_squads.get_child_count() == 0 and screen.enemy_squads.get_child_count() == 0 and screen.no_player_squads.visible and screen.no_enemy_squads.visible,
		"Empty results clear stale icons and show an explicit empty state")
	screen.free()
	Globals.scenario_chosen = null
	Globals.battle_casualties.clear()
	Globals.battle_exits.clear()
	scenario.free()
	audio_root.free()
	print("Squad result checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _build_units() -> void:
	# Create out of order to verify consistent formation ordering.
	_unit(Globals.Team.ALLIES, Globals.SquadType.MORTAR, 3, 3, 2, "Exited")
	reduced = _unit(Globals.Team.ALLIES, Globals.SquadType.Rifle, 1, 12, 8)
	_unit(Globals.Team.ALLIES, Globals.SquadType.PLATOON_HEADQUARTERS, 0, 4, 4)
	var eliminated: Unit = _unit(Globals.Team.ALLIES, Globals.SquadType.MG, 2, 3, 0, "Eliminated")
	eliminated.add_to_group("units")
	_unit(Globals.Team.AXIS, Globals.SquadType.ANTITANK, 2, 6, 4, "Surrendered")
	_unit(Globals.Team.AXIS, Globals.SquadType.PLATOON_HEADQUARTERS, 0, 3, 3)
	_unit(Globals.Team.AXIS, Globals.SquadType.Rifle, 1, 10, 0, "Eliminated")
	_unit(Globals.Team.AXIS, Globals.SquadType.MORTAR, 3, 4, 4, "Exited")


func _unit(team: Globals.Team, type: Globals.SquadType, squad: int, starting: int, remaining: int, state: String = "Intact") -> Unit:
	var unit: Unit = load("res://scenes/game/units/unit.tscn").instantiate()
	unit.set_script(UnitProbe)
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	unit.hide()
	unit.team = team
	unit.squad_type = type
	unit.squad = squad
	unit.platoon = 1
	unit.original_size = starting
	unit.members_alive = remaining
	unit.alive = state != "Eliminated"
	unit.exited = state == "Exited"
	unit.surrendered = state == "Surrendered"
	add_child(unit)
	units.append(unit)
	if unit.exited:
		unit.add_to_group("exited_units")
		var record: UnitExitRecord = UnitExitRecord.new()
		record.team = team
		record.members_alive = remaining
		Globals.battle_exits.append(record)
	elif not unit.alive:
		unit.add_to_group("dead_units")
	else:
		unit.add_to_group("units")
	for index: int in range(starting - remaining):
		var casualty: CasualtyRecord = CasualtyRecord.new()
		casualty.team = team
		Globals.battle_casualties.append(casualty)
	return unit


func _test_squads() -> void:
	_check(screen.player_squads.get_child_count() == 4 and screen.enemy_squads.get_child_count() == 4, "Active, dead, surrendered, and exited squads appear exactly once")
	var intact: HBoxContainer = screen.player_squads.get_child(0)
	var partial: HBoxContainer = screen.player_squads.get_child(1)
	var eliminated: HBoxContainer = screen.player_squads.get_child(2)
	var exited: HBoxContainer = screen.player_squads.get_child(3)
	var surrendered: HBoxContainer = screen.enemy_squads.get_child(2)
	_check(intact.identity.text == "Platoon HQ" and intact.status.text == "Intact" and intact.strength.text == "4/4 soldiers remain · 0 lost", "An intact HQ remains clearly identified")
	_check(partial.status.text == "Reduced" and partial.strength.text == "8/12 soldiers remain · 4 lost", "Individual casualties reduce the squad rather than marking it eliminated")
	_check(partial.formation.text == "Company A · Platoon 1", "Squad identity includes its formation")
	_check(eliminated.status.text == "Eliminated" and eliminated.strength.text == "0/3 soldiers remain · 3 lost", "An eliminated squad shows zero survivors and its full losses")
	_check(eliminated.thumbnail.modulate.a < partial.thumbnail.modulate.a, "An eliminated portrait is dimmed while a reduced portrait remains visible")
	_check(exited.status.text == "Exited · Reduced" and exited.strength.text == "2/3 soldiers remain · 1 lost", "Exiting preserves partial casualties and surviving strength")
	_check(surrendered.status.text == "Surrendered · Reduced" and surrendered.strength.text == "4/6 soldiers remain · 2 lost", "Surrendered survivors are distinguished from eliminated squads")
	_check((screen.enemy_squads.get_child(3) as HBoxContainer).status.text == "Exited", "An intact exited squad is not marked reduced")
	_check(reduced.members_alive == 8 and reduced.original_size == 12, "Reading squad results does not mutate battlefield strength")


func _test_icons() -> void:
	for container: VBoxContainer in [screen.player_squads, screen.enemy_squads]:
		for child: Node in container.get_children():
			var row: HBoxContainer = child as HBoxContainer
			_check(row.thumbnail.texture != null, "Every squad retains an icon, including eliminated squads")
	var allied_mg: HBoxContainer = screen.player_squads.get_child(2)
	var german_hq: HBoxContainer = screen.enemy_squads.get_child(0)
	var german_at: HBoxContainer = screen.enemy_squads.get_child(2)
	_check(allied_mg.thumbnail.texture.resource_path == "res://assets/status/united_states/infantry/mg/idle_us.png", "Eliminated squads retain the icon of their squad type")
	_check(german_hq.thumbnail.texture.resource_path == "res://assets/status/germany/leader/leader_idle_ger.png", "Axis headquarters use the leader icon")
	_check(german_at.thumbnail.texture == units[4].ui.unit_status_control.get("idle_antitank_ger"), "Support squad icons follow faction and role")


func _check_inside() -> void:
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(get_tree().root.size))
	_check(bounds.encloses(screen.panel.get_global_rect()), "The result panel fits the viewport")
	var actions: Control = screen.get_node("Control/CenterContainer/PanelContainer/Content/Actions")
	_check(bounds.encloses(actions.get_global_rect()), "Result actions remain visible below the scrolling squads")


func _settle() -> void:
	for frame: int in range(10):
		await get_tree().process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
