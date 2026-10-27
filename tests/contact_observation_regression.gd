extends Node

var checks: int = 0
var failures: int = 0
var world: Node
var friendly: Unit
var enemy: Unit
var controller: Node2D


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
	friendly = Globals.get_units_for_team(Globals.team_player)[0]
	enemy = Globals.get_units_for_team(Globals.team_enemy)[0]
	_set_hex(friendly, Vector2i(2, 2))
	_set_hex(enemy, Vector2i(2, 5))
	LOSHelper.los_lookup = {friendly.current_hex: {enemy.current_hex: {"target_cover": 0, "target_concealment": 0, "hindrance": 0}}}
	Globals.unit_visible_enemies = {friendly: []}
	Globals.unit_enemy_tracks.clear()
	friendly.tactical_state.attention_quality = 1.0
	friendly.tactical_state.focus_direction = Vector2.ZERO
	_test_reacquisition()
	_test_exposure_and_pace()
	_test_information()
	_test_diagnostics_and_controls()
	_test_invalid_roster()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Contact observation checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_reacquisition() -> void:
	var track: EnemyTrack = EnemyTrack.new(friendly, enemy)
	var tracks: Dictionary[Unit, EnemyTrack] = {enemy: track}
	Globals.unit_enemy_tracks[friendly] = tracks
	var baseline: float = MatchVisibilityCoordinator.compute_detect_rate(controller, friendly, enemy)
	track.acquire_detection()
	var known_hex: Vector2i = track.last_known_hex
	var known_position: Vector2 = track.last_known_global_position
	track.update_not_seen(0.1)
	var bonus: float = MatchVisibilityCoordinator.compute_detect_rate(controller, friendly, enemy)
	_check(bonus > baseline * 2.5 and bonus <= baseline * 3.0, "A brief interruption gives a bounded search advantage at the observed location")
	var adjacent: Vector2i = world.ground_layer.cube_to_map(enemy.current_cube + Vector3i(1, -1, 0))
	_check(track.reacquisition_multiplier(adjacent) > 1.0 and track.reacquisition_multiplier(adjacent) < track.reacquisition_multiplier(known_hex), "Searching one adjacent hex is weaker than searching the recorded hex")
	_set_hex(enemy, world.ground_layer.cube_to_map(enemy.current_cube + Vector3i(3, -3, 0)))
	_check(track.reacquisition_multiplier(enemy.current_hex) == 1.0 and track.last_known_hex == known_hex and track.last_known_global_position == known_position, "Search advantage does not follow a hidden unit away from its observed area")
	track.update_seen(EnemyTrack.SEARCH_MEMORY_S, 10.0)
	_check(track.search_remaining_s == 0.0 and track.reacquisition_multiplier(known_hex) == 1.0, "Undetected geometric LOS does not refresh search memory")
	_set_hex(enemy, known_hex)
	track.acquire_detection()
	_check(track.reacquisition_multiplier(known_hex) == 1.0, "Search advantage cannot inflate the tracking rate of an already visible contact")
	Globals.unit_enemy_tracks.clear()


func _test_exposure_and_pace() -> void:
	enemy.is_moving = true
	enemy.movement.is_moving = true
	enemy.movement.move_speed = enemy.movement.base_speed
	enemy.movement.terrain_mult = 1.0
	enemy.squad_fire.fire_recent = 0.0
	for soldier: Soldier in enemy.squad_fire.soldiers:
		soldier.behavior = Soldier.Behavior.ENGAGING
	var rates: Array[float] = []
	var durations: Array[float] = []
	var steps: Array[float] = []
	var start: Vector2 = enemy.position
	for stance: UnitMovement.Stance in [UnitMovement.Stance.CROUCHED, UnitMovement.Stance.STANDING, UnitMovement.Stance.RUNNING]:
		enemy.movement.stance = stance
		rates.append(MatchVisibilityCoordinator.compute_detect_rate(controller, friendly, enemy))
		durations.append(enemy.movement.estimate_travel_seconds(Vector2.ZERO, Vector2(64, 0), 1.0))
		enemy.position = start
		enemy.movement.target_position = start + Vector2.RIGHT * 1000.0
		enemy.movement._process_movement(0.1)
		steps.append(enemy.position.distance_to(start))
	enemy.position = start
	_check(rates[0] < rates[1] and rates[1] < rates[2], "Cautious, normal and fast travel produce increasing actual detection rates")
	_check(durations[0] > durations[1] and durations[1] > durations[2], "Pace affects estimated travel time consistently with movement")
	_check(steps[0] < steps[1] and steps[1] < steps[2], "The live movement step travels farther at faster paces")
	enemy.movement.stance = UnitMovement.Stance.CROUCHED
	var saved: UnitSaveData = enemy.create_save_data()
	_check(saved.movement_stance == UnitMovement.Stance.CROUCHED, "Saving retains the chosen movement pace")
	enemy.movement.stance = UnitMovement.Stance.RUNNING
	enemy.apply_save_data(saved)
	_check(enemy.movement.stance == UnitMovement.Stance.CROUCHED and UnitSaveData.new().movement_stance == UnitMovement.Stance.STANDING, "Loading restores pace while older saves default to normal movement")
	enemy.movement.stance = UnitMovement.Stance.STANDING
	enemy.is_moving = false
	enemy.movement.is_moving = false
	var exposed: float = MatchVisibilityCoordinator.compute_detect_rate(controller, friendly, enemy)
	for soldier: Soldier in enemy.squad_fire.soldiers:
		soldier.behavior = Soldier.Behavior.TAKING_COVER
	var covered: float = MatchVisibilityCoordinator.compute_detect_rate(controller, friendly, enemy)
	for soldier: Soldier in enemy.squad_fire.soldiers:
		soldier.behavior = Soldier.Behavior.COWERING
	var cowering: float = MatchVisibilityCoordinator.compute_detect_rate(controller, friendly, enemy)
	_check(cowering < covered and covered < exposed, "Actual covering and cowering soldiers reduce the squad's silhouette")
	enemy.squad_fire.fire_recent = 1.0
	_check(MatchVisibilityCoordinator.compute_detect_rate(controller, friendly, enemy) > exposed, "A muzzle flash remains a strong cue even when the squad mostly takes cover")
	enemy.squad_fire.fire_recent = 0.0
	for soldier: Soldier in enemy.squad_fire.soldiers:
		soldier.behavior = Soldier.Behavior.ENGAGING


func _test_information() -> void:
	Debug.enemy_selectable = false
	var track: EnemyTrack = EnemyTrack.new(friendly, enemy)
	var tracks: Dictionary[Unit, EnemyTrack] = {enemy: track}
	Globals.unit_enemy_tracks[friendly] = tracks
	Globals.unit_visible_enemies[friendly] = [enemy]
	track.acquire_detection()
	MatchVisibilityCoordinator.show_visible_units(controller)
	var details: Control = world.ui.unit_details
	details.show_unit_detail(enemy, false)
	_check(details.unit_type_label.text == "Unidentified contact" and details.strength_label.text == "Strength unknown", "A first sighting does not expose exact enemy identity or strength")
	_check(not details.roster_section.visible and not details.details_section.visible and details.soldiers.is_empty(), "Enemy inspection cannot build or reveal the live soldier roster and internal combat statistics")
	_check(enemy.ui.members_count_label.text == "?" and not enemy.ui.morale_bar.visible and not enemy.ui.unit_status_control.visible, "The battlefield counter also conceals exact strength, morale and equipment silhouette")
	enemy.ui.set_members_alive(2)
	enemy.ui.set_unit_designation("Private formation name")
	details._on_state_changed(STATES.MoraleState.PANIC)
	_check(enemy.ui.members_count_label.text == "?" and enemy.ui.unit_designation_label.text == "Contact" and details.unit_status_label.text == "Brief sighting", "Live casualty, formation and morale updates cannot bypass observation limits")
	track.observe_details(1.0, 3.1)
	details._process(0.1)
	_check(details.unit_type_label.text == track.observed_type_name and details.strength_label.text == "Strength unknown", "Sustained observation identifies type before estimating strength")
	track.observe_details(1.0, 5.0)
	MatchVisibilityCoordinator.show_visible_units(controller)
	details._process(0.1)
	_check(details.strength_label.text.begins_with("Estimated ") and track.estimated_strength_min <= enemy.members_alive and track.estimated_strength_max >= enemy.members_alive, "Further observation supplies a bounded strength estimate rather than an exact roster")
	_check(details.strength_label.get_theme_font("font").get_string_size(details.strength_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, details.strength_label.get_theme_font_size("font_size")).x <= 276.0, "The estimated strength label fits the squad details column")
	var observed_type: String = track.observed_type_name
	var observed_strength: int = track.estimated_strength_max
	track.update_not_seen(0.1)
	var old_type: Globals.SquadType = enemy.squad_type
	var old_members: int = enemy.members_alive
	enemy.squad_type = Globals.SquadType.MORTAR
	enemy.members_alive = 1
	track.observe_details(100.0, 100.0)
	_check(track.observed_type_name == observed_type and track.estimated_strength_max == observed_strength, "A hidden contact report does not read live type or strength changes")
	enemy.squad_type = old_type
	enemy.members_alive = old_members
	track.acquire_detection()
	Debug.enemy_selectable = true
	details._process(0.1)
	_check(details.roster_section.visible and details.soldiers.size() == enemy.squad_fire.soldiers.size(), "Explicit debug enemy control retains full inspection")
	Debug.enemy_selectable = false
	details.show_unit_detail(friendly, false)
	_check(details.roster_section.visible and details.strength_label.text.contains("/"), "Friendly inspection retains exact strength and its full roster")


func _test_diagnostics_and_controls() -> void:
	var details: Control = world.ui.unit_details
	var debug: Control = world.ui.debug_panel
	_check(not details.spotting_section.visible, "Spotting diagnostics stay out of normal gameplay by default")
	debug.spotting.button_pressed = true
	details._process(0.1)
	_check(Debug.show_spotting_diagnostics and details.spotting_section.visible and details.spotting_target.item_count > 0, "The development checkbox enables a target selector for the selected friendly squad")
	_check(details.spotting_factors.text.contains("Target concealment") and details.spotting_factors.text.contains("Intervening hindrances") and details.spotting_factors.text.contains("Acquisition rate") and details.spotting_factors.text.contains("Tracking:"), "The diagnostic panel exposes the actual spotting factors and tracking allowance")
	var factors: Dictionary = MatchVisibilityCoordinator.detection_breakdown(controller, friendly, enemy)
	_check(is_equal_approx(factors["rate"], MatchVisibilityCoordinator.compute_detect_rate(controller, friendly, enemy)), "Diagnostics and production acquisition use the same calculation")
	details.pace.select(details.pace.get_item_index(UnitMovement.Stance.CROUCHED))
	details.pace.item_selected.emit(details.pace.selected)
	_check(friendly.movement.stance == UnitMovement.Stance.CROUCHED, "The squad details pace control changes actual movement stance")
	debug.spotting.button_pressed = false
	details._process(0.1)
	_check(not details.spotting_section.visible, "Disabling diagnostics removes the development information")
	friendly.movement.stance = UnitMovement.Stance.STANDING


func _test_invalid_roster() -> void:
	var planner: PlatoonAI = PlatoonAI.new()
	var valid: Unit = Unit.new()
	valid.team = planner.team
	var removed: Unit = Unit.new()
	removed.team = planner.team
	var roster: Array[Unit] = [valid, removed, valid]
	removed.free()
	planner.set_squads(roster)
	_check(planner.squads.size() == 1 and planner.squads[0] == valid, "AI registration filters freed entries and duplicate living squads")
	var company: CompanyAI = CompanyAI.new()
	company.owner = planner
	var dropped: Unit = Unit.new()
	company.reservations[dropped] = Vector2i.ZERO
	var shared: Dictionary[Unit, Vector2i] = company.reservations
	dropped.free()
	company._refresh_reservations()
	_check(shared.size() == 1 and shared.has(valid), "Company reservations remove freed keys in place while preserving shared dictionary identity")
	company.owner = null
	planner.free()
	valid.free()


func _set_hex(unit: Unit, cell: Vector2i) -> void:
	unit.current_hex = cell
	unit.current_cube = world.ground_layer.map_to_cube(cell)
	unit.position = world.ground_layer.map_to_local(cell)


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
