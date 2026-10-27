extends Node

const LINES: Script = preload("res://scenes/world/overlays/tactical_lines_overlay.gd")

class ImpactProbe extends Unit:
	var effects: Array[Dictionary] = []

	func _make_squad() -> void:
		pass

	func set_cover(value: int) -> void:
		current_cover_bonus = value

	func receive_fire(_cover: float) -> void:
		pass

	func _on_incoming_fire_effect(casualties: int, fast: float, slow: float, _source: Node) -> void:
		effects.append({"casualties": casualties, "fast": fast, "slow": slow})

class FireProbe extends SquadFireController:
	var cells: Array[Vector2i] = []
	var times: Array[float] = []
	var first_shots: Dictionary[int, float] = {}
	var loops_stopped: int = 0
	var resolve_impacts: bool = false

	func _on_fire_weapon(_weapon: WeaponSpec, _position: Vector2, _automatic: bool, _id: int, _owner: Node2D) -> void:
		pass

	func _on_stop_mg_loop(_weapon: WeaponSpec, _position: Vector2, _id: int, _owner: Node2D) -> void:
		loops_stopped += 1

	func _resolve_area_round(weapon: WeaponSpec, cell: Vector2i, distance: int, cover: int, origin: Vector2, life: float) -> void:
		if resolve_impacts:
			await super._resolve_area_round(weapon, cell, distance, cover, origin, life)

	func observe_shot(weapon: WeaponSpec, cell: Vector2i, _origin: Vector2, _impact: Vector2) -> void:
		cells.append(cell)
		times.append(_now_s)
		if not first_shots.has(weapon.get_instance_id()):
			first_shots[weapon.get_instance_id()] = _now_s

var checks: int = 0
var failures: int = 0
var main: Node
var world: Node
var controller: Node2D
var shooter: Unit
var ally: Unit
var receiver: ImpactProbe
var entrant: ImpactProbe
var fire: FireProbe
var cell: Vector2i


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
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
	shooter = Globals.get_units_for_team(Globals.team_player)[1]
	ally = Globals.get_units_for_team(Globals.team_player)[2]
	for unit: Unit in Globals.get_units():
		_set_hex(unit, Vector2i(100, 100))
	_set_hex(shooter, Vector2i(2, 2))
	cell = world.ground_layer.cube_to_map(shooter.current_cube + Vector3i(3, -3, 0))
	receiver = _create_receiver("Receiver")
	entrant = _create_receiver("Entrant")
	var original: SquadFireController = shooter.squad_fire
	fire = FireProbe.new()
	fire.unit = shooter
	fire.stress_controller = shooter.stress_system
	add_child(fire)
	fire.set_process(false)
	fire.fire_shot.connect(fire.observe_shot)
	shooter.squad_fire = fire
	_test_order_and_cadence()
	_test_reactions_and_ammunition()
	_test_safety_and_cancellation()
	_test_weapons_and_grenades()
	await _test_impacts()
	await _test_controls_and_overlay()
	fire.set_soldiers([])
	shooter.squad_fire = original
	fire.calc.free()
	fire.free()
	main.queue_free()
	receiver.queue_free()
	entrant.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Area suppression checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _prepare(path: String = "res://resources/weapons/m1_garand.tres", role: RankGrades.Role = RankGrades.Role.SOLDIER) -> Soldier:
	shooter.setAttackState(Unit.AttackState.AUTO)
	fire.set_soldiers([])
	fire.clear_target()
	fire.cells.clear()
	fire.times.clear()
	fire.first_shots.clear()
	fire.loops_stopped = 0
	fire.resolve_impacts = false
	fire._now_s = 0.0
	shooter.squad_type = Globals.SquadType.Rifle
	shooter.fire_discipline = Unit.FireDiscipline.HOLD_FIRE
	shooter.is_moving = false
	shooter.movement.is_moving = false
	shooter.broken = false
	shooter.surrendered = false
	shooter.in_close_combat = false
	shooter.stress_system.state = STATES.MoraleState.NORMAL
	shooter.stress_system.S_eff = 0.0
	shooter.stress_system.under_fire = false
	_set_hex(ally, Vector2i(100, 100))
	_set_hex(receiver, cell)
	_set_hex(entrant, Vector2i(100, 100))
	receiver.effects.clear()
	entrant.effects.clear()
	Globals.unit_visible_enemies = {shooter: []}
	Globals.unit_enemy_tracks.clear()
	LOSHelper.los_lookup = {shooter.current_hex: {cell: {"target_cover": 0, "target_concealment": 0, "hindrance": 0}}}
	var soldier: Soldier = _soldier(path, role, 0)
	fire.set_soldiers([soldier])
	return soldier


func _soldier(path: String, role: RankGrades.Role, index: int) -> Soldier:
	var weapon: WeaponSpec = (load(path) as WeaponSpec).create_runtime()
	weapon.ammunition = 300
	var soldier: Soldier = Soldier.new(index, "Suppress probe", RankGrades.Grade.SOLDIER, role, weapon, shooter, shooter.team)
	soldier.setup_weapon_task.done = true
	soldier.reload_task.done = true
	return soldier


func _simulate(seconds: float) -> void:
	for frame: int in range(ceili(seconds * 60.0)):
		fire._process(1.0 / 60.0)


func _test_order_and_cadence() -> void:
	var gunner: Soldier = _prepare("res://resources/weapons/mg34.tres", RankGrades.Role.GUNNER)
	shooter.attack_ground_rounds_budget = 0
	_check(fire.start_area_suppression(cell), "An unobserved occupied hex accepts an explicit suppression order")
	_check(shooter.attackState == Unit.AttackState.AREA_SUPPRESSION and fire.target_unit == null and fire.target_hex == cell, "Suppression stores the area without acquiring a hidden unit")
	_check(shooter.fire_discipline == Unit.FireDiscipline.HOLD_FIRE and fire.has_fire_order_override(), "Suppression temporarily overrides hold fire without changing the saved setting")
	_simulate(45.0)
	_check(fire.cells.size() > 50 and gunner.weapon.ammunition == 300 - fire.cells.size(), "Suppression spends real ammunition and continues beyond the ordinary fifty-round ground-fire budget")
	_check(fire.cells.count(cell) == fire.cells.size() and shooter.attack_ground_rounds_budget == 0, "Every round remains in the chosen area without consuming the ordinary ground-fire budget")
	var longest_gap: float = 0.0
	for index: int in range(1, fire.times.size()):
		longest_gap = maxf(longest_gap, fire.times[index] - fire.times[index - 1])
	_check(longest_gap > 1.0 and gunner.weapon.automatic_fire.heat() > 0.0, "Area fire retains controlled automatic pauses, reloading and physical barrel heat")
	_set_hex(receiver, world.ground_layer.cube_to_map(shooter.current_cube + Vector3i(1, 0, -1)))
	Globals.unit_visible_enemies[shooter] = [receiver]
	fire.set_target_unit(receiver)
	_simulate(1.0)
	_check(fire.target_unit == null and fire.target_hex == cell and fire.cells.count(cell) == fire.cells.size(), "A newly observed contact cannot redirect suppression away from its ordered hex")
	_check(Globals.unit_enemy_tracks.is_empty(), "Suppressing unseen terrain does not create a detection or identification record")


func _test_reactions_and_ammunition() -> void:
	_prepare()
	var roster: Array[Soldier] = []
	for index: int in range(12):
		roster.append(_soldier("res://resources/weapons/m1_garand.tres", RankGrades.Role.SOLDIER, index))
	fire.set_soldiers(roster)
	fire.start_area_suppression(cell)
	_simulate(5.0)
	var times: Array = fire.first_shots.values()
	times.sort()
	_check(times.size() == 12 and float(times[-1]) - float(times[0]) > 0.3, "Suppressing soldiers retain individual reaction times instead of firing together")
	var soldier: Soldier = _prepare()
	soldier.weapon.ammunition = 3
	soldier.rounds_in_mag = 3
	fire.start_area_suppression(cell)
	_simulate(15.0)
	_check(fire.cells.size() == 3 and soldier.weapon.ammunition == 0 and shooter.attackState == Unit.AttackState.AUTO, "Exhausted ammunition ends suppression without overspending rounds")
	_check(shooter.fire_discipline == Unit.FireDiscipline.HOLD_FIRE and not fire.has_fire_order_override(), "Completing suppression restores the selected fire discipline")


func _test_safety_and_cancellation() -> void:
	var soldier: Soldier = _prepare("res://resources/weapons/mg34.tres", RankGrades.Role.GUNNER)
	fire.start_area_suppression(cell)
	soldier.aquire_target_task.done = true
	_simulate(0.02)
	var ammo: int = soldier.weapon.ammunition
	_set_hex(ally, cell)
	_simulate(0.1)
	_check(soldier.weapon.ammunition == ammo and shooter.attackState == Unit.AttackState.AUTO and not soldier.burst_active and fire.loops_stopped == 1, "Friendlies entering the area cease further rounds, cancel the order and stop burst audio")
	_check(not fire.start_area_suppression(cell) and fire.suppression_restriction(cell).contains("Friendly"), "A friendly-occupied area cannot be ordered suppressed")
	_prepare()
	LOSHelper.los_lookup[shooter.current_hex] = {}
	_check(not fire.start_area_suppression(cell), "Suppression requires current line of sight even without a contact")
	_prepare()
	fire.start_area_suppression(cell)
	LOSHelper.los_lookup[shooter.current_hex] = {}
	_simulate(0.1)
	_check(shooter.attackState == Unit.AttackState.AUTO and fire.cells.is_empty(), "Lost line of sight ends the order before firing")
	_prepare()
	_check(not fire.start_area_suppression(shooter.current_hex) and not fire.start_area_suppression(Vector2i(-100, -100)), "The squad's own hex and off-map areas are rejected")
	shooter.is_moving = true
	_check(not fire.start_area_suppression(cell), "A moving squad cannot begin suppression")
	_prepare()
	fire.start_area_suppression(cell)
	shooter.order(Globals.UnitCmd.STOP, null)
	_check(shooter.attackState == Unit.AttackState.AUTO and not fire.has_target_hex, "Stop removes suppression and its area target")
	_prepare()
	fire.start_area_suppression(cell)
	shooter._on_morale_breaks()
	_check(shooter.attackState == Unit.AttackState.AUTO and not fire.has_target_hex, "Routing clears suppression immediately")
	_prepare()
	fire.start_area_suppression(cell)
	Globals.unit_visible_enemies[shooter] = [receiver]
	shooter.order(Globals.UnitCmd.FIRE_AT_HEX, cell)
	_check(shooter.attackState == Unit.AttackState.MANUAL_TRACK and fire.target_unit == receiver, "A replacement Fire order cancels area suppression and acquires its explicit target")


func _test_weapons_and_grenades() -> void:
	var soldier: Soldier = _prepare("res://resources/weapons/m2_60mm_mortar.tres", RankGrades.Role.GUNNER)
	_check(not fire.start_area_suppression(cell), "Mortars use their fire missions rather than direct small-arms suppression")
	soldier = _prepare()
	soldier.weapon.range_hexes = 1
	_check(not fire.start_area_suppression(cell), "Suppression respects the range of usable participating small arms")
	soldier = _prepare("res://resources/weapons/kar98.tres")
	soldier.weapon.can_fire_riflegrenades = true
	soldier.weapon.riflegrenade_loaded = true
	soldier.rounds_in_mag = 1
	fire.start_area_suppression(cell)
	_check(not soldier.weapon.riflegrenade_loaded and not soldier.reload_task.done, "A loaded rifle grenade is replaced through a real ball-ammunition reload")
	_simulate(15.0)
	_check(fire.cells.size() > 1 and not soldier.weapon.riflegrenade_loaded and not soldier._reload_grenade, "Area suppression continues using ordinary bullets through subsequent reloads")
	var gunner: Soldier = _prepare("res://resources/weapons/mg34_heavy.tres", RankGrades.Role.GUNNER)
	shooter.squad_type = Globals.SquadType.MG
	var loader: Soldier = _soldier("res://resources/weapons/kar98.tres", RankGrades.Role.LOADER, 1)
	fire.set_soldiers([gunner, loader])
	fire.start_area_suppression(cell)
	_simulate(5.0)
	_check(gunner.weapon.ammunition < 300 and loader.weapon.ammunition == 300, "A dedicated MG crew serves the gun without firing loader sidearms at a distant area")


func _test_impacts() -> void:
	var soldier: Soldier = _prepare()
	fire.resolve_impacts = true
	fire.start_area_suppression(cell)
	soldier.aquire_target_task.done = true
	_simulate(0.02)
	shooter.order(Globals.UnitCmd.STOP, null)
	await get_tree().create_timer(0.3).timeout
	await get_tree().process_frame
	_check(receiver.effects.size() == 1 and receiver.stress_system.under_fire and float(receiver.effects[0]["slow"]) > 0.0, "A real airborne area round applies incoming pressure and stress to an unseen occupant")
	_check(shooter.attackState == Unit.AttackState.AUTO and fire.cells.size() == 1, "A round launched by the actual scheduler still lands after Stop cancels suppression")
	_check(Globals.unit_visible_enemies[shooter].is_empty() and Globals.unit_enemy_tracks.is_empty(), "An impact does not reveal the hidden receiver to its shooter")
	receiver.effects.clear()
	entrant.effects.clear()
	fire._resolve_area_round(soldier.weapon, cell, 3, 0, shooter.global_position, 0.03)
	_set_hex(receiver, Vector2i(100, 100))
	_set_hex(entrant, cell)
	await get_tree().create_timer(0.07).timeout
	await get_tree().process_frame
	_check(receiver.effects.is_empty() and entrant.effects.size() == 1, "Airborne area rounds hit current occupants rather than following units that left the hex")
	entrant.effects.clear()
	_set_hex(entrant, Vector2i(100, 100))
	_set_hex(receiver, cell)
	receiver.members_alive = 100000
	fire.base_accuracy = 0.8
	seed(77)
	SquadHitResolver.fire_at(fire, 4000, soldier.weapon, false, cell, 3, 0, [], shooter.global_position)
	await get_tree().process_frame
	var aimed: Dictionary = receiver.effects.back()
	seed(77)
	SquadHitResolver.fire_at(fire, 4000, soldier.weapon, false, cell, 3, 0, [], shooter.global_position, true)
	await get_tree().process_frame
	var area: Dictionary = receiver.effects.back()
	_check(int(area["casualties"]) < int(aimed["casualties"]) * 0.5, "Area fire produces substantially fewer aimed casualties for the same incoming volume")
	_check(is_equal_approx(float(area["slow"]), float(aimed["slow"])), "Reduced casualty accuracy does not remove volume-based suppression")
	receiver.stress_system.state = STATES.MoraleState.PANIC
	seed(77)
	SquadHitResolver.fire_at(fire, 4000, soldier.weapon, false, cell, 1, 0, [], shooter.global_position)
	await get_tree().process_frame
	aimed = receiver.effects.back()
	seed(77)
	SquadHitResolver.fire_at(fire, 4000, soldier.weapon, false, cell, 1, 0, [], shooter.global_position, true)
	await get_tree().process_frame
	area = receiver.effects.back()
	_check(int(area["casualties"]) < int(aimed["casualties"]) * 0.5, "Point-blank and panic accuracy bonuses cannot bypass area fire's reduced precision")
	receiver.stress_system.state = STATES.MoraleState.NORMAL
	fire.base_accuracy = 0.35


func _test_controls_and_overlay() -> void:
	_prepare()
	controller._select_unit(shooter)
	_check(controller.order_via_option_wheel(cell, WheelOption.Option.SUPPRESS), "The actual command handler accepts Suppress on unobserved terrain")
	var details: Control = world.ui.unit_details
	details.show_unit_detail(shooter, false)
	_check(details.order_label.text.contains("Suppress") and details.fire_discipline_status.text == "Suppress order overrides discipline", "Squad details display the area order and its discipline override")
	var lines: Node2D = LINES.new()
	world.add_child(lines)
	lines.set_process(false)
	var points: PackedVector2Array = lines._suppression_area_points(shooter)
	_check(points.size() == 6 and not Geometry2D.triangulate_polygon(points).is_empty(), "The selected suppression marker follows the actual target-hex geometry")
	lines.queue_redraw()
	await get_tree().process_frame
	shooter.selected = false
	_check(lines._suppression_area_points(shooter).is_empty(), "Deselecting a squad hides its suppression marker")
	shooter.selected = true
	controller.end_game_handled = true
	_check(not controller.order_via_option_wheel(cell, WheelOption.Option.SUPPRESS), "Mission completion blocks suppression orders")
	controller.end_game_handled = false
	controller.selected_unit = receiver
	Debug.enemy_selectable = false
	_check(not controller.order_via_option_wheel(cell, WheelOption.Option.SUPPRESS), "Inspected enemies cannot receive suppression orders")
	controller.selected_unit = shooter
	controller.order_via_option_wheel(cell, WheelOption.Option.STOP)
	_check(lines._suppression_area_points(shooter).is_empty() and not fire.has_target_hex, "Stop clears both the suppression target and its marker")
	lines.free()


func _create_receiver(label: String) -> ImpactProbe:
	var unit: Unit = load("res://scenes/game/units/unit.tscn").instantiate() as Unit
	unit.set_script(ImpactProbe)
	var probe: ImpactProbe = unit as ImpactProbe
	probe.name = label
	probe.team = Globals.team_enemy
	add_child(probe)
	_freeze(probe)
	probe.add_to_group("units")
	return probe


func _set_hex(unit: Unit, hex: Vector2i) -> void:
	unit.current_hex = hex
	unit.current_cube = world.ground_layer.map_to_cube(hex)
	unit.global_position = world.ground_layer.to_global(world.ground_layer.map_to_local(hex))


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
