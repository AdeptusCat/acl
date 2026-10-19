extends Node

var checks: int = 0
var failures: int = 0
var zoom_events: int = 0
var map_clicks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var panel: SquadRosterPanel = world.ui.squad_roster
	_check(not panel.visible and not panel.is_processing(), "The battle roster stays hidden before starting a match")
	var map: Map = world.maps.get_node("DefaultMap")
	var scenario: Scenario = map.get_scenario(0)
	scenario.axis_ai_status = Scenario.AIStatus.OFF
	scenario.allies_ai_status = Scenario.AIStatus.OFF
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	world.ui.hide_target_hex_cover_distance()
	get_tree().root.size = Vector2i(1440, 900)
	await _settle()
	var players: Array[Unit] = Globals.get_units_for_team(Globals.team_player)
	var enemies: Array[Unit] = Globals.get_units_for_team(Globals.team_enemy)
	_check(panel.visible and panel.rows.size() == players.size(), "Starting the battle lists every active friendly squad")
	_check(not panel.rows.has(enemies[0]), "Enemy squads do not appear in the player's roster")
	_check(is_equal_approx(panel.size.x, SquadRosterPanel.PANEL_WIDTH) and panel.size.y <= world.ui.get_node("Control").size.y * 0.4 + 1.0, "The roster has a compact fixed width and stays within the HUD height limit: %s" % panel.size)
	_check(_clear_of_hud(world), "The roster does not overlap the timer, mission, retry, debug, or selected squad panels")
	var selected: Unit = panel.rows.keys()[0]
	var row: SquadRosterRow = panel.rows[selected]
	_check(panel.company_branches[selected.company].folded and not row.is_visible_in_tree(), "Companies start collapsed before selecting or browsing a squad")
	var company_branch: FoldableContainer = panel.company_branches[selected.company]
	_pointer_event(_screen_rect(company_branch).get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	await _settle()
	if selected.squad_type != Globals.SquadType.COMPANY_HEADQUARTERS:
		var platoon_branch: FoldableContainer = panel.platoon_branches[Vector2i(selected.company, selected.platoon)]
		_pointer_event(_screen_rect(platoon_branch).get_center(), MouseButton.MOUSE_BUTTON_LEFT)
		await _settle()
	_check(row.is_visible_in_tree(), "Company and platoon headings expand through pointer input")
	_check(row.strength.text == "%d/%d" % [selected.squad_fire.soldiers.size(), selected.original_size], "Each row shows remaining and initial soldiers")
	_check(_text_fits(row.identity) and _text_fits(row.strength), "Squad identity and strength fit the row")
	world.input_manager.zoom_in.connect(_on_zoom)
	world.input_manager.zoom_out.connect(_on_zoom)
	world.input_manager.mouse_button_left_pressed.connect(_on_map_click)
	_pointer_event(_screen_rect(row).get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	await _settle()
	_check(world.game_controller.selected_unit == selected and selected.selected, "Clicking an actual roster row selects that squad")
	_check(world.game_controller.camera.position == world.ground_layer.map_to_local(selected.current_hex), "Clicking a row centers the camera on that squad")
	_check(world.ui.unit_details.unit == selected and world.ui.unit_details.visible, "Roster selection opens the existing squad summary")
	_check(map_clicks == 0, "A roster click does not also select a battlefield hex")
	_check(row.button_pressed, "The selected row is highlighted")
	_check(_only_selected_branch_expanded(panel, selected), "Roster selection expands only the selected squad's company and platoon")
	world.game_controller.camera.position += Vector2(200.0, 100.0)
	_pointer_event(_screen_rect(row).get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	await _settle()
	_check(selected.selected and row.button_pressed and world.game_controller.camera.position == world.ground_layer.map_to_local(selected.current_hex), "Clicking the selected row keeps it selected and recenters the camera")
	var rifle: Unit
	for unit: Unit in players:
		if unit.squad_type == Globals.SquadType.Rifle:
			rifle = unit
			break
	var rifle_row: SquadRosterRow = panel.rows[rifle]
	world.game_controller.select_and_center_unit(rifle)
	await _settle()
	_check(not rifle.ui.has_node("FormationMarker"), "Battlefield counters have no separate formation marker")
	var platoon_color: Color = UnitHudStyle.formation_color(rifle)
	_check((rifle.ui.morale_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color == platoon_color, "The morale fill identifies the squad's platoon")
	_check(rifle.ui.morale_bar.fill_mode == ProgressBar.FILL_BEGIN_TO_END and rifle.ui.morale_bar.size.x > rifle.ui.morale_bar.size.y, "Morale uses a single horizontal gauge")
	var gauge_rect: Rect2 = rifle.ui.morale_bar.get_global_rect()
	_check(not gauge_rect.intersects(rifle.ui.idle_texture_rect.get_global_rect()) and rifle.ui.stress_arrows.get_global_rect().end.y <= gauge_rect.position.y and rifle.ui.recovery_arrows.get_global_rect().end.y <= gauge_rect.position.y, "Influence arrows sit above the morale strip and leave the figure unobstructed")
	_check(not rifle.ui.get_node("ColorRect").visible and not rifle.ui.get_node("MoraleBarDefault").visible, "Counters draw a single morale strip without a separate arrow background")
	_check(not rifle_row.rout_available.visible, "Fresh squads have no retreat availability icon")
	var morale_position: Vector2 = rifle_row.morale.position
	var row_size: Vector2 = rifle_row.size
	rifle.stress_system._set_state(STATES.MoraleState.PINNED)
	_check(rifle_row.rout_available.visible and rifle_row.tooltip_text.contains("right click for Rout") and rifle_row.tooltip_text.contains("surrender"), "Pinned squads immediately show a quiet retreat icon with an explanation")
	for transition: int in range(3):
		rifle.stress_system._set_state(STATES.MoraleState.CAUTIOUS)
		_check(not rifle_row.rout_available.visible, "Recovery immediately hides the retreat availability icon")
		await _settle()
		_check(rifle_row.morale.position == morale_position and rifle_row.size == row_size, "Frequent morale transitions do not shift roster text or row size")
		rifle.stress_system._set_state(STATES.MoraleState.PINNED)
		_check((rifle.ui.morale_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color == platoon_color, "Morale transitions preserve the platoon's counter color")
	rifle.in_close_combat = true
	panel.refresh()
	_check(not rifle_row.rout_available.visible, "Close combat suppresses the retreat cue")
	rifle.in_close_combat = false
	panel._process(0.25)
	_check(rifle_row.morale.text == "Pinned" and rifle_row.morale.get_theme_color("font_color").r > 0.9, "Live pinned morale is clearly labeled and colored")
	rifle.command_squad = selected
	rifle.command_connectivity.clear_connectivity()
	panel.refresh()
	_check(rifle_row.isolation.visible, "Squads without a communication link are marked isolated")
	rifle.command_connectivity.command_unit_state = STATES.MoraleState.NORMAL
	rifle.command_connectivity.runner_chain_to_leader = true
	panel.refresh()
	_check(not rifle_row.isolation.visible, "An available runner link clears the isolation indicator")
	rifle.command_connectivity.command_unit_state = STATES.MoraleState.PANIC
	panel.refresh()
	_check(rifle_row.isolation.visible, "An ineffective HQ command link agrees with the battlefield no-contact indicator")
	for unit: Unit in players:
		if unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
			_check(not panel.rows[unit].isolation.visible, "Company headquarters does not need a higher headquarters link")
	var old_count: int = selected.squad_fire.soldiers.size()
	selected.apply_specific_casualty(selected.squad_fire.soldiers[0])
	panel.refresh()
	_check(panel.rows[selected] == row and row.strength.text == "%d/%d" % [old_count - 1, selected.original_size], "A casualty updates strength without rebuilding the row")
	_check(is_equal_approx(row.strength_bar.value, float(old_count - 1) / float(selected.original_size)), "The strength bar tracks the live soldier fraction")
	world.game_controller._select_unit(rifle)
	world.game_controller.show_unit_details_in_ui.emit(rifle)
	panel.refresh()
	_check(rifle_row.button_pressed and not row.button_pressed, "Battlefield selection also updates the roster highlight")
	world.game_controller._deselect_unit(rifle)
	world.game_controller.hide_unit_details_in_ui.emit()
	panel.refresh()
	_check(not rifle_row.button_pressed, "Deselecting clears the roster highlight")
	rifle.stress_system.state = STATES.MoraleState.COMBAT_INEFFECTIVE
	panel.refresh()
	await _settle()
	_check(_text_fits(rifle_row.morale), "The longest morale state remains readable")
	rifle.stress_system._set_state(STATES.MoraleState.PINNED)
	# This scenario has only a few squads; add real units to exercise overflow.
	for index: int in range(12):
		var extra: Unit = world.game_controller.unit_scene.instantiate() as Unit
		extra.team = Globals.team_player
		extra.company = Unit.Company.A
		extra.platoon = 1 + floori(float(index) / 4.0)
		extra.squad = 10 + index
		extra.current_hex = rifle.current_hex
		extra.squad_loadout = rifle.squad_loadout
		world.game_controller.unit_container.add_child(extra)
		extra.setup()
		extra.add_to_group("units")
		extra.ui.unit_designation_label.text = "R%d" % index
		extra.command_squad = rifle
		extra.command_connectivity.runner_chain_to_leader = true
		_freeze(extra)
		players.append(extra)
	panel.refresh()
	await _settle()
	_pointer_event(_screen_rect(panel.rows[rifle]).get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	await _settle()
	_check(panel.rows.size() == players.size() and _clear_of_hud(world), "An expanded platoon grows the roster without overlapping other HUD panels: %s" % panel.size)
	_check(world.game_controller.selected_unit == rifle and _platoon_fully_visible(panel, rifle), "Clicking a squad shows its platoon heading and every squad without manual scrolling")
	_check(panel.size.y > world.ui.get_node("Control").size.y * 0.4, "A large platoon can expand beyond the compact roster height")
	var scrollbar: VScrollBar = panel.scroll.get_v_scroll_bar()
	var can_scroll: bool = scrollbar.max_value > scrollbar.page
	panel.scroll.scroll_vertical = 0
	_pointer_event(_screen_rect(panel.scroll).get_center(), MouseButton.MOUSE_BUTTON_WHEEL_DOWN)
	_check((panel.scroll.scroll_vertical > 0 or not can_scroll) and zoom_events == 0, "Roster wheel input stays within the HUD without zooming the battlefield")
	panel.scroll.scroll_vertical = 0
	var offscreen: Unit = players[players.size() - 1]
	var original_hex: Vector2i = offscreen.current_hex
	var original_position: Vector2 = offscreen.position
	for hex: Vector2i in world.ground_layer.get_used_cells():
		if LOSHelper.find_units_at(hex).is_empty():
			offscreen.current_hex = hex
			break
	offscreen.position = world.ground_layer.map_to_local(offscreen.current_hex)
	world.game_controller.camera.position = offscreen.position
	world.game_controller.camera.reset_smoothing()
	world.game_controller.camera.force_update_scroll()
	var battlefield_point: Vector2 = world.game_controller.get_global_transform_with_canvas() * offscreen.position
	_pointer_event(battlefield_point, MouseButton.MOUSE_BUTTON_LEFT)
	await _settle()
	_check(world.game_controller.selected_unit == offscreen and _platoon_fully_visible(panel, offscreen), "Clicking a battlefield squad reveals its entire platoon rather than only the selected row")
	_check(_only_selected_branch_expanded(panel, offscreen), "Battlefield selection opens its platoon and collapses sibling platoons")
	panel.platoon_branches[Vector2i(offscreen.company, 1)].expand()
	panel.refresh()
	await _settle()
	_check(panel.platoon_branches[Vector2i(offscreen.company, offscreen.platoon)].folded, "Browsing another platoon collapses its sibling and survives periodic refresh")
	world.game_controller.select_and_center_unit(offscreen)
	await _settle()
	_check(_only_selected_branch_expanded(panel, offscreen), "Reselecting a squad restores its branch after manual browsing")
	_check(_platoon_fully_visible(panel, offscreen), "Reselecting a squad restores full platoon visibility after manual browsing")
	offscreen.current_hex = original_hex
	offscreen.position = original_position
	var manual_scroll: int = maxi(0, panel.scroll.scroll_vertical - 30)
	panel.scroll.scroll_vertical = manual_scroll
	panel.refresh()
	await _settle()
	_check(panel.scroll.scroll_vertical == manual_scroll, "Periodic roster refresh leaves manual scrolling under player control")
	panel.section.fold()
	world.game_controller._select_unit(rifle)
	world.game_controller.show_unit_details_in_ui.emit(rifle)
	await _settle()
	_check(not panel.section.folded and panel.scroll.get_global_rect().encloses(panel.rows[rifle].get_global_rect()), "Selecting a squad expands a folded roster and reveals its row")
	_check(_platoon_fully_visible(panel, rifle), "Opening a folded roster fits the whole selected platoon")
	world.game_controller._select_unit(offscreen)
	world.game_controller.show_unit_details_in_ui.emit(offscreen)
	world.game_controller._select_unit(rifle)
	world.game_controller.show_unit_details_in_ui.emit(rifle)
	await _settle()
	_check(panel.scroll.get_global_rect().encloses(panel.rows[rifle].get_global_rect()), "Rapid selections reveal the latest squad rather than an earlier queued selection")
	_check(_only_selected_branch_expanded(panel, rifle), "Rapid selections leave only the latest squad's branch expanded")
	_check(_platoon_fully_visible(panel, rifle), "Rapid selections leave every squad of the latest platoon visible")
	rifle.ui.update_bar(60, 100)
	_check(is_equal_approx(rifle.ui.morale_bar.value, 0.4) and rifle.ui.morale_bar.scale == Vector2.ONE, "Morale reserve falls with stress while the gauge keeps a fixed size")
	_check((rifle.ui.morale_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color == platoon_color and (offscreen.ui.morale_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color != platoon_color, "Different platoons remain distinguishable while morale reserve falls")
	panel.scroll.scroll_vertical = 0
	world.game_controller.select_and_center_unit(rifle)
	world.ui.hide_target_hex_cover_distance()
	panel.refresh()
	var debug_panel: Control = world.ui.get_node("Control/Debug") as Control
	debug_panel.hide()
	await _settle()
	_check(is_equal_approx(panel.position.x, 12.0) and _clear_of_hud(world), "The roster uses the left edge when development controls are hidden")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("release")
	debug_panel.show()
	await _settle()
	if OS.get_cmdline_user_args().has("--capture"):
		panel.refresh()
		await _settle()
		await _capture("wide")
	panel.section.fold()
	await _settle()
	_check(panel.size.y <= 50.0 and not panel.scroll.is_visible_in_tree(), "The roster folds down to a small title bar")
	panel.section.expand()
	await _settle()
	var other: Unit = players[players.size() - 1]
	other.company = Unit.Company.B
	other.platoon = 2
	panel.refresh()
	await _settle()
	var heading: FoldableContainer = panel.rows[other].get_parent().get_parent().get_parent() as FoldableContainer
	_check(heading == panel.platoon_branches[Vector2i(other.company, other.platoon)] and heading.title == "Platoon 2" and panel.company_branches[other.company].title == "Company B", "Changing formation moves a squad under its correct company and platoon")
	world.game_controller.select_and_center_unit(other)
	await _settle()
	_check(_only_selected_branch_expanded(panel, other) and panel.company_branches[rifle.company].folded, "Selecting a squad in another company collapses the previous company and its platoons")
	_check(_platoon_fully_visible(panel, other), "Selecting another company keeps its entire selected platoon visible")
	other.platoon = 3
	panel.refresh()
	await _settle()
	_check(_only_selected_branch_expanded(panel, other) and panel.rows[other].is_visible_in_tree() and not panel.platoon_branches.has(Vector2i(other.company, 2)), "Moving the selected squad rebuilds and expands its new branch without stale platoons")
	panel.company_branches[rifle.company].expand()
	panel.refresh()
	_check(panel.company_branches[other.company].folded and panel.platoon_branches[Vector2i(other.company, other.platoon)].folded, "Manually opening another company collapses the previous company and its platoons")
	var changed_color: Color = UnitHudStyle.formation_color(other)
	_check((other.ui.morale_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color == changed_color, "Changing platoon immediately updates the morale bar's color")
	other.ui.update_bar(100, 100)
	_check(is_zero_approx(other.ui.morale_bar.value) and (other.ui.morale_bar.get_theme_stylebox("background") as StyleBoxFlat).border_color == changed_color, "An empty morale bar retains its platoon-colored outline")
	_check(panel.rows[selected].get_parent() != panel.rows[other].get_parent(), "Different companies do not share a platoon group")
	var reinforcement: Unit = enemies[0]
	reinforcement.team = Globals.team_player
	panel.refresh()
	_check(panel.rows.has(reinforcement) and panel.rows.size() == players.size() + 1, "New friendly squads join the live roster")
	world.game_controller.select_and_center_unit(selected)
	var original_squad_type: Globals.SquadType = selected.squad_type
	selected.squad_type = Globals.SquadType.COMPANY_HEADQUARTERS
	panel.refresh()
	_check(_only_selected_branch_expanded(panel, selected) and panel.rows[selected].get_parent().get_parent().get_parent() == panel.company_branches[selected.company], "Company headquarters sits directly under its company and keeps all platoons collapsed")
	selected.squad_type = original_squad_type
	panel.refresh()
	selected.exit_map(false)
	panel.refresh()
	_check(not panel.rows.has(selected) and world.game_controller.selected_unit == null, "Exited squads leave the roster and release selection")
	var selected_before: Unit = world.game_controller.selected_unit
	world.game_controller.select_and_center_unit(selected)
	world.game_controller.select_and_center_unit(enemies[1])
	_check(world.game_controller.selected_unit == selected_before, "Inactive and enemy squads cannot be selected through the roster action")
	other.die()
	panel.refresh()
	_check(not panel.rows.has(other), "Dead squads leave the roster")
	_check(not other.ui.morale_bar.visible, "Dead squads hide the platoon-colored morale bar")
	reinforcement.queue_free()
	panel.refresh()
	_check(not panel.rows.has(reinforcement), "Queued removal does not leave a clickable stale row")
	await _settle()
	var disappearing: Unit = players[players.size() - 2]
	var stale_row: SquadRosterRow = panel.rows[disappearing]
	disappearing.queue_free()
	await _settle()
	var rows_before: int = panel.rows.size()
	stale_row.pressed.emit()
	_check(panel.rows.size() == rows_before - 1, "Clicking a row after its squad was freed safely clears the stale entry")
	await _settle()
	world.ui.tile_details.show()
	world.game_controller.select_and_center_unit(rifle)
	world.ui.hide_target_hex_cover_distance()
	panel.refresh()
	get_tree().root.size = Vector2i(800, 600)
	await _settle()
	var hud_size: Vector2 = world.ui.get_node("Control").size
	_check(Rect2(Vector2.ZERO, hud_size).encloses(panel.get_rect()), "The roster remains inside the HUD after resizing")
	_check(_clear_of_hud(world), "The roster avoids other HUD panels with tile details visible on a smaller window")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("compact")
	for window_size: Vector2i in [Vector2i(1440, 900), Vector2i(1152, 648), Vector2i(708, 639)]:
		await _check_support_layout(world, window_size)
	for unit: Unit in Globals.get_units_for_team(Globals.team_player):
		unit.exit_map(false)
	panel.refresh()
	await _settle()
	_check(panel.rows.is_empty() and panel.section.title == "Squads · 0", "The roster count clears when no active friendly squads remain")
	panel.setup(Globals.team_enemy)
	_check(not panel.rows.is_empty() and not panel.rows.has(selected), "Reinitializing the panel clears old rows and uses the new player's side")
	main.queue_free()
	await _settle()
	print("Squad roster HUD checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _check_support_layout(world: Node, window_size: Vector2i) -> void:
	get_tree().root.size = window_size
	var hud: CanvasLayer = world.ui
	var roster: SquadRosterPanel = hud.squad_roster
	var terrain: PanelContainer = hud.tile_details
	var debug_panel: PanelContainer = hud.get_node("Control/Debug")
	debug_panel.section.fold()
	terrain.show_tile_data({"hex": Vector2i(9, 11), "tile_name": "Open ground", "cover_ne": 2})
	await _settle()
	var roster_position: Vector2 = roster.position
	_check(is_equal_approx(roster_position.x, 12.0) and is_equal_approx(roster_position.y, 6.0), "The roster stays close to the top-left edge at %s" % window_size)
	terrain.details.expand()
	await _settle()
	_check(debug_panel.section.folded and not terrain.details.folded, "Expanding terrain keeps development controls folded")
	_check(roster.position.is_equal_approx(roster_position) and _clear_of_hud(world) and _support_panels_fit(hud), "Expanded terrain fits below the stationary roster at %s" % window_size)
	_check(terrain.size.y <= hud.get_node("Control").size.y * 0.4 + 1.0 and roster.scroll.size.y >= 32.0, "Terrain overflow stays within the HUD height limit and preserves a usable squad list")
	_check(_platoon_fully_visible(roster, world.game_controller.selected_unit), "The selected platoon remains fully visible beside expanded terrain at %s" % window_size)
	if window_size.x == 1152:
		var scrollbar: VScrollBar = terrain.scroll.get_v_scroll_bar()
		_check(scrollbar.max_value > scrollbar.page, "Terrain details scroll when the left column runs out of space")
		_pointer_event(_screen_rect(terrain.scroll).get_center(), MouseButton.MOUSE_BUTTON_WHEEL_DOWN)
		_check(terrain.scroll.scroll_vertical > 0 and zoom_events == 0, "Scrolling terrain details does not zoom the battlefield")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("terrain-%d" % window_size.x)
	debug_panel.section.expand()
	await _settle()
	_check(terrain.details.folded and not debug_panel.section.folded, "Opening development controls folds terrain details")
	_check(roster.position.is_equal_approx(roster_position) and _clear_of_hud(world) and _support_panels_fit(hud), "Expanded development controls fit below the stationary roster at %s" % window_size)
	_check(debug_panel.axis_ai_status.is_visible_in_tree() and not debug_panel.axis_ai_status.disabled, "The compact development panel preserves usable AI controls")
	_check(_platoon_fully_visible(roster, world.game_controller.selected_unit), "The selected platoon remains fully visible beside expanded development controls at %s" % window_size)
	debug_panel.scroll.scroll_vertical = 0
	_pointer_event(_screen_rect(debug_panel.scroll).get_center(), MouseButton.MOUSE_BUTTON_WHEEL_DOWN)
	_check(debug_panel.scroll.scroll_vertical > 0 and zoom_events == 0, "Development controls scroll without zooming the battlefield")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("debug-%d" % window_size.x)
	terrain.details.expand()
	await _settle()
	_check(debug_panel.section.folded and roster.position.is_equal_approx(roster_position), "Reopening terrain folds development controls without moving the roster")
	terrain.hide_inspection()
	await _settle()
	_check(roster.position.is_equal_approx(roster_position) and _clear_of_hud(world), "Closing inspection keeps the roster anchored")
	debug_panel.section.fold()


func _platoon_fully_visible(panel: SquadRosterPanel, unit: Unit) -> bool:
	var group: Vector2i = Vector2i(unit.company, unit.platoon)
	var branch: FoldableContainer = panel.platoon_branches[group]
	var bounds: Rect2 = panel.scroll.get_global_rect()
	if not branch.is_visible_in_tree() or not bounds.encloses(branch.get_global_rect()):
		return false
	for member: Unit in panel.rows:
		if member.company == unit.company and member.platoon == unit.platoon and member.squad_type != Globals.SquadType.COMPANY_HEADQUARTERS:
			if not panel.rows[member].is_visible_in_tree() or not bounds.encloses(panel.rows[member].get_global_rect()):
				return false
	return true


func _only_selected_branch_expanded(panel: SquadRosterPanel, unit: Unit) -> bool:
	for company: int in panel.company_branches:
		if panel.company_branches[company].folded != (company != unit.company):
			return false
	for group: Vector2i in panel.platoon_branches:
		var should_fold: bool = group != Vector2i(unit.company, unit.platoon) or unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS
		if panel.platoon_branches[group].folded != should_fold:
			return false
	return true


func _support_panels_fit(hud: CanvasLayer) -> bool:
	var bounds: Rect2 = Rect2(Vector2.ZERO, hud.get_node("Control").size)
	var terrain: Control = hud.tile_details
	var debug_panel: Control = hud.get_node("Control/Debug")
	return bounds.encloses(terrain.get_rect()) and bounds.encloses(debug_panel.get_rect()) and not terrain.get_rect().intersects(debug_panel.get_rect())


func _clear_of_hud(world: Node) -> bool:
	var panel_rect: Rect2 = world.ui.squad_roster.get_rect()
	for path: String in ["Countdown", "MissionObjectives", "TryAgain", "Debug", "TileDetails", "UnitDetails"]:
		var other: Control = world.ui.get_node("Control/" + path) as Control
		if other.visible and panel_rect.intersects(other.get_rect()):
			push_error("Roster %s overlaps %s %s" % [panel_rect, path, other.get_rect()])
			return false
	return true


func _pointer_event(point: Vector2, button: MouseButton) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = button
	press.pressed = true
	get_viewport().push_input(press, true)
	var release: InputEventMouseButton = press.duplicate() as InputEventMouseButton
	release.pressed = false
	get_viewport().push_input(release, true)


func _text_fits(label: Label) -> bool:
	return label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.get_theme_font_size("font_size")).x <= label.size.x


func _on_zoom() -> void:
	zoom_events += 1


func _on_map_click(_position: Vector2) -> void:
	map_clicks += 1


func _capture(label: String) -> void:
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/acl-squad-roster-%s.png" % label)


func _settle() -> void:
	for frame: int in range(6):
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


func _screen_rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
