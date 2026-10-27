extends Node

# Run with: godot --headless --path . tests/weapon_setup_regression.tscn
const DETAILS_SCRIPT: Script = preload("res://scenes/ui/units/unit_details_panel.gd")

class FireProbe extends SquadFireController:
	var shots_fired: int = 0
	var impact_hexes: Array[Vector2i] = []

	func _on_fire_weapon(_weapon: WeaponSpec, _position: Vector2, _auto: bool, _owner_id: int, _owner: Node2D) -> void:
		shots_fired += 1

	func _on_stop_mg_loop(_weapon: WeaponSpec, _position: Vector2, _id: int, _owner: Node2D) -> void:
		pass

	func fire_shots(_soldier: Soldier, shots: int, _rpm: float, _auto: bool, _hex: Vector2i) -> void:
		shots_fired += shots

	func fire_at(_rounds: int, _weapon: WeaponSpec, _grenade: bool, hex: Vector2i, _distance: int, _cover: int, _targets: Array[Unit], _shot_origin: Vector2 = Vector2.INF) -> void:
		impact_hexes.append(hex)


var failures: int = 0
var checks: int = 0
var shooter: Unit
var enemy: Unit
var probe: FireProbe
var gunner: Soldier
var details: PanelContainer


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_child(1)
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	shooter = Globals.get_units()[1]
	enemy = Globals.get_units()[3]
	for unit: Unit in Globals.get_units():
		unit.remove_from_group("units")
	for panel: Node in main.find_children("*", "PanelContainer", true, false):
		if panel.get_script() == DETAILS_SCRIPT:
			details = panel as PanelContainer
			break
	_check(details != null, "Fixture contains the actual soldier task panel")
	var original_fire: SquadFireController = shooter.squad_fire
	probe = FireProbe.new()
	probe.unit = shooter
	probe.stress_controller = shooter.stress_system
	shooter.add_child(probe)
	probe.set_process(false)
	shooter.squad_fire = probe
	shooter.unit_arrived_at_hex.connect(probe._on_unit_arrived_at_hex)
	_set_hex(enemy, Vector2i(20, 20))
	Debug.dont_fire_wepaons = true
	for weapon_path: String in ["res://resources/weapons/mg34_heavy.tres", "res://resources/weapons/mg34.tres"]:
		_prepare_weapon(weapon_path)
		_test_idle_setup()
		_test_movement_and_ineligibility()
		await _test_setup_under_contact()
	_prepare_weapon("res://resources/weapons/kar98.tres")
	_arrive()
	probe._process(0.0)
	_check(gunner.setup_weapon_task.done, "A rifle with no setup duration is immediately ready")
	await _test_crew_effects()
	await _test_personal_defense()
	shooter.squad_fire = original_fire
	probe.calc.free()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Weapon setup regression checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _prepare_weapon(path: String) -> void:
	var weapon: WeaponSpec = (load(path) as WeaponSpec).create_runtime()
	gunner = Soldier.new(999, "Setup probe", RankGrades.Grade.SOLDIER, RankGrades.Role.GUNNER, weapon, shooter, shooter.team)
	probe.soldiers = [gunner]
	shooter.stress_system.state = STATES.MoraleState.NORMAL
	shooter.is_moving = false
	shooter.in_close_combat = false
	shooter.broken = false
	shooter.surrendered = false
	shooter.alive = true
	shooter.setAttackState(Unit.AttackState.AUTO)
	Globals.unit_visible_enemies[shooter] = []
	probe.clear_target()
	if details != null:
		details.show_unit_detail(shooter, false)


func _arrive() -> void:
	_set_hex(shooter, Vector2i.ZERO)
	var path: Array[Vector3i] = [shooter.current_cube, LOSHelper.ground_layer.map_to_cube(Vector2i(1, 0))]
	shooter.movement.follow_cube_path(path)
	shooter.movement._process_movement(100.0)
	_check(not shooter.is_moving and shooter.current_hex == Vector2i(1, 0), "Real movement reaches its destination")
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, gunner.weapon.setup_s), "Arrival starts the weapon's configured setup duration")


func _test_idle_setup() -> void:
	_arrive()
	var duration: float = gunner.weapon.setup_s
	probe._process(1.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 1.0), "A stationary gunner advances setup without any detected enemy")
	_check(probe.target_unit == null and not probe.has_target_hex, "Setup requires no firing target")
	if details != null:
		details._process(0.0)
		var entries: Dictionary = details.soldier_entries_by_soldier[gunner]
		var task: Label = entries[DETAILS_SCRIPT.Entry.TASK]
		var progress: ProgressBar = entries[DETAILS_SCRIPT.Entry.PROGRESS_BAR]
		_check(task.text == "Setting Up" and progress.value > 0.0 and absf(progress.value - 1.0 / duration) <= progress.step, "The actual task progress bar advances before contact: %s, %s" % [task.text, progress.value])
	var ammunition: int = gunner.weapon.ammunition
	probe._process(duration - 1.0)
	_check(gunner.setup_weapon_task.done and is_zero_approx(gunner.setup_weapon_task.remaining_time_s), "Setup finishes at its duration without a UI update or firing attempt")
	_check(gunner.weapon.ammunition == ammunition and probe.shots_fired == 0, "Idle setup spends no ammunition and fires no shots")
	probe._process(10.0)
	_check(gunner.setup_weapon_task.done and is_zero_approx(gunner.setup_weapon_task.remaining_time_s), "Idle readiness stays complete")


func _test_movement_and_ineligibility() -> void:
	_arrive()
	var duration: float = gunner.weapon.setup_s
	shooter.movement.move_to_hex(Vector2i.ZERO)
	probe._process(duration * 2.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration), "Moving cannot advance setup even with no visible enemies")
	shooter.movement._process_movement(100.0)
	probe._process(1.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 1.0), "Setup resumes at the new destination")
	for flag: String in ["in_close_combat", "broken", "surrendered"]:
		shooter.set(flag, true)
		probe._process(1.0)
		_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 1.0), "Setup pauses while " + flag)
		shooter.set(flag, false)
	shooter.alive = false
	probe._process(1.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 1.0), "A dead squad cannot set up")
	shooter.alive = true
	gunner.is_alive = false
	probe._process(1.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 1.0), "A dead gunner cannot set up")
	gunner.is_alive = true
	shooter.stress_system.state = STATES.MoraleState.CAUTIOUS
	probe._process(1.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 1.8), "Setup retains the cautious-state speed")
	shooter.stress_system.state = STATES.MoraleState.PANIC
	probe._process(1.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 1.8), "Panic pauses setup")
	shooter.stress_system.state = STATES.MoraleState.NORMAL
	_arrive()
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration), "Another move resets partial setup at arrival")


func _test_setup_under_contact() -> void:
	gunner.behavior = Soldier.Behavior.ENGAGING
	gunner.behavior_remaining_s = 10.0
	gunner._behavior_morale = STATES.MoraleState.NORMAL
	var duration: float = gunner.weapon.setup_s
	probe._process(1.0)
	_set_hex(enemy, Vector2i(2, 0))
	LOSHelper.los_lookup = {shooter.current_hex: {enemy.current_hex: {"target_cover": 0}}}
	Globals.unit_visible_enemies[shooter] = [enemy]
	shooter.setAttackState(Unit.AttackState.MANUAL_TRACK)
	probe.set_target_unit(enemy)
	gunner.reload_task.done = true
	gunner.aquire_target_task.done = true
	probe._process(1.0)
	_check(is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 2.0), "Target acquisition preserves earlier progress and advances setup only once per frame")
	var shots: int = await probe._try_fire_soldier(1.0, gunner, true, 1, 0, 1, 0)
	_check(shots == 0 and is_equal_approx(gunner.setup_weapon_task.remaining_time_s, duration - 2.0), "Firing cannot complete or advance an unfinished setup task")
	Globals.unit_visible_enemies[shooter] = []
	probe._process(duration)
	_check(gunner.setup_weapon_task.done and probe.target_unit == null, "Setup completes even if contact is lost")
	Globals.unit_visible_enemies[shooter] = [enemy]
	shooter.setAttackState(Unit.AttackState.MANUAL_TRACK)
	probe.set_target_unit(enemy)
	gunner.reload_task.done = true
	gunner.aquire_target_task.done = true
	gunner.weapon.fire_mode = WeaponSpec.FireMode.SINGLE
	gunner.weapon.projectile_speed = 1000000
	Debug.dont_fire_wepaons = false
	var ammunition: int = gunner.weapon.ammunition
	shots = await probe._try_fire_soldier(0.1, gunner, true, 1, 0, 1, 0)
	_check(shots > 0 and gunner.weapon.ammunition == ammunition - shots, "A gun deployed before contact can fire without another setup delay")
	Debug.dont_fire_wepaons = true
	probe.shots_fired = 0
	Globals.unit_visible_enemies[shooter] = []
	probe.clear_target()
	_set_hex(enemy, Vector2i(20, 20))


func _prepare_crew(path: String, loaders: int, assistants: int) -> void:
	_prepare_weapon(path)
	for role: RankGrades.Role in [RankGrades.Role.LOADER, RankGrades.Role.ASSISTANT]:
		var count: int = loaders
		if role == RankGrades.Role.ASSISTANT:
			count = assistants
		for index: int in range(count):
			var helper: Soldier = Soldier.new(1000 + probe.soldiers.size(), "Crew probe", RankGrades.Grade.SOLDIER, role, WeaponSpec.new(), shooter, shooter.team)
			probe.soldiers.append(helper)
	_set_hex(shooter, Vector2i(1, 0))
	_set_hex(enemy, Vector2i(2, 0))
	LOSHelper.los_lookup = {shooter.current_hex: {enemy.current_hex: {"target_cover": 0}}}
	Globals.unit_visible_enemies[shooter] = [enemy]
	shooter.setAttackState(Unit.AttackState.MANUAL_TRACK)
	probe.set_target_unit(enemy)
	gunner.setup_weapon_task.done = true
	gunner.reload_task.done = true
	gunner.aquire_target_task.done = true
	gunner.aim_jitter_s = 0.0
	gunner.weapon.fire_mode = WeaponSpec.FireMode.SINGLE
	gunner.weapon.projectile_speed = 1000000
	gunner.weapon.ammunition = 1000
	probe.shots_fired = 0


func _test_crew_effects() -> void:
	for path: String in ["res://resources/weapons/mg34_heavy.tres", "res://resources/weapons/m1_81mm_mortar.tres"]:
		var weapon: WeaponSpec = load(path) as WeaponSpec
		var required_loaders: int = weapon.crew_required - 1
		var outputs: Array[int] = []
		for crew: Array in [[required_loaders, weapon.support_crew_optimal], [required_loaders, 0], [0, 0]]:
			_prepare_crew(path, crew[0], crew[1])
			Debug.dont_fire_wepaons = false
			seed(814)
			for tick: int in range(300):
				probe._tick_soldiers(0.1)
				await get_tree().process_frame
			outputs.append(probe.shots_fired)
		print(weapon.name, " rounds in 30 seconds, full/reduced/lone: ", outputs)
		_check(outputs[0] > outputs[1] and outputs[1] > outputs[2] and outputs[2] > 0,
			weapon.name + " loses firing output with missing assistants and then missing loaders, but a lone gunner can fire")
		_prepare_crew(path, required_loaders, weapon.support_crew_optimal)
		Debug.dont_fire_wepaons = true
		# Losing and restoring crew must alter work already in progress, without resetting it.
		for task: SoldierTask in [gunner.reload_task, gunner.aquire_target_task]:
			gunner.reload_task.done = true
			gunner.aquire_target_task.done = true
			task.done = false
			task.start_time_s = 100.0
			probe._tick_soldiers(1.0)
			_check(is_equal_approx(task.remaining_time_s, 99.0), weapon.name + " full crew advances one second of " + task.task_name)
			for helper: Soldier in probe.soldiers:
				if helper != gunner:
					helper.is_alive = false
			probe._tick_soldiers(1.0)
			var slowed_remaining: float = task.remaining_time_s
			_check(slowed_remaining > 98.5 and slowed_remaining < 99.0, weapon.name + " dead helpers slow the current task without restarting it")
			for helper: Soldier in probe.soldiers:
				helper.is_alive = true
			probe._tick_soldiers(1.0)
			_check(is_equal_approx(task.remaining_time_s, slowed_remaining - 1.0), weapon.name + " restored crew resumes full work speed")
		shooter.stress_system.state = STATES.MoraleState.CAUTIOUS
		gunner.reload_task.done = false
		gunner.reload_task.start_time_s = 100.0
		probe._tick_soldiers(1.0)
		_check(is_equal_approx(gunner.reload_task.remaining_time_s, 99.05), "Cautious crew handling has one modest slowdown")
	_prepare_crew("res://resources/weapons/kar98.tres", 0, 0)
	gunner.reload_task.done = false
	gunner.reload_task.start_time_s = 100.0
	probe._tick_soldiers(1.0)
	_check(is_equal_approx(gunner.reload_task.remaining_time_s, 99.0), "Personal weapons do not receive a missing-crew penalty")
	Debug.dont_fire_wepaons = true
	probe.clear_target()


func _attempt_personal_fire(soldier: Soldier, target: Unit) -> int:
	soldier.weapon_raised = true
	soldier.raise_remaining_s = 0.0
	soldier.cycle_remaining_s = 0.0
	soldier.reaim_remaining_s = 0.0
	soldier.behavior = Soldier.Behavior.ENGAGING
	soldier.setup_weapon_task.done = true
	soldier.reload_task.done = true
	soldier.aquire_target_task.done = true
	soldier.aquire_target_task.target_id = target
	soldier.weapon.projectile_speed = 1000000
	var shots: int = probe._try_fire_soldier(0.1, soldier, false, 0, 0, 0, 0)
	await get_tree().create_timer(0.02).timeout
	return shots


func _test_personal_defense() -> void:
	var original_type: Globals.SquadType = shooter.squad_type
	var original_enemy_team: Globals.Team = enemy.team
	enemy.team = Globals.get_enemy_team(shooter.team)
	var distant: Unit = Unit.new()
	distant.team = enemy.team
	_set_hex(distant, Vector2i(3, 0))
	for squad_type: Globals.SquadType in [Globals.SquadType.MG, Globals.SquadType.MORTAR, Globals.SquadType.ANTITANK]:
		shooter.squad_type = squad_type
		var weapon_path: String = "res://resources/weapons/mg34_heavy.tres"
		if squad_type == Globals.SquadType.MORTAR:
			weapon_path = "res://resources/weapons/m1_81mm_mortar.tres"
		elif squad_type == Globals.SquadType.ANTITANK:
			weapon_path = "res://resources/weapons/rpzb_54_panzerschreck.tres"
		_prepare_crew(weapon_path, 1, 1)
		var loader: Soldier = probe.soldiers[1]
		var assistant: Soldier = probe.soldiers[2]
		var leader: Soldier = Soldier.new(1100, "Leader", RankGrades.Grade.SQUAD_LEADER, RankGrades.Role.SQUAD_LEADER, WeaponSpec.new(), shooter, shooter.team)
		var rifleman: Soldier = Soldier.new(1101, "Rifleman", RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, WeaponSpec.new(), shooter, shooter.team)
		probe.soldiers.append_array([leader, rifleman])
		Debug.dont_fire_wepaons = false
		_set_hex(enemy, Vector2i(3, 0))
		LOSHelper.los_lookup = {shooter.current_hex: {enemy.current_hex: {"target_cover": 0}, distant.current_hex: {"target_cover": 0}}}
		Globals.unit_visible_enemies[shooter] = [enemy, distant]
		probe.set_target_unit(enemy)
		for soldier: Soldier in [leader, rifleman, assistant, loader]:
			var ammunition: int = soldier.weapon.ammunition
			_check(await _attempt_personal_fire(soldier, enemy) == 0 and soldier.weapon.ammunition == ammunition,
				"Weapon squad personal weapons remain silent beyond one hex")
		_set_hex(enemy, Vector2i(2, 0))
		LOSHelper.los_lookup[shooter.current_hex][enemy.current_hex] = {"target_cover": 0}
		probe.set_target_unit(distant)
		for soldier: Soldier in [leader, rifleman, assistant]:
			probe.impact_hexes.clear()
			_check(await _attempt_personal_fire(soldier, enemy) > 0 and probe.impact_hexes == [enemy.current_hex],
				"Leader, rifleman and assistant shoot an adjacent threat")
			_check(probe.target_unit == distant and probe.target_hex == distant.current_hex,
				"Personal defense preserves the support weapon's distant target")
		probe.impact_hexes.clear()
		_check(await _attempt_personal_fire(gunner, distant) > 0 and probe.impact_hexes == [distant.current_hex],
			"The support weapon still fires at its distant ordered target")
		assistant.aquire_target_task.target_id = null
		assistant.aquire_target_task.done = true
		assistant.aim_jitter_s = 0.0
		_check(await probe._try_fire_soldier(0.0, assistant, false, 0, 0, 0, 0) == 0 and not assistant.aquire_target_task.done,
			"An adjacent threat starts the assistant's normal acquisition delay")
		var acquire_remaining: float = assistant.aquire_target_task.remaining_time_s
		probe.set_target_unit(distant)
		probe.aim_delay()
		_check(assistant.aquire_target_task.target_id == enemy and is_equal_approx(assistant.aquire_target_task.remaining_time_s, acquire_remaining),
			"Support targeting and aiming do not restart independent personal-defense acquisition")
		probe.clear_target()
		_check(await _attempt_personal_fire(assistant, enemy) > 0, "Adjacent personal defense works without a primary weapon target")
		probe.set_target_unit(distant)
		_check(await _attempt_personal_fire(loader, enemy) == 0, "A supplied support weapon keeps its loader on crew duties")
		gunner.reload_task.done = false
		gunner.reload_task.start_time_s = 10.0
		_check(await _attempt_personal_fire(loader, enemy) == 0, "Reloading does not release the loader to fire a rifle")
		gunner.weapon.ammunition = 0
		_check(await _attempt_personal_fire(loader, enemy) > 0, "An ammunition-exhausted support weapon releases its loader for adjacent defense")
		gunner.weapon.ammunition = 100
		gunner.is_alive = false
		_check(await _attempt_personal_fire(loader, enemy) > 0, "An absent active gunner releases the loader for adjacent defense")
		Globals.unit_visible_enemies[shooter] = [distant]
		_check(await _attempt_personal_fire(assistant, enemy) == 0, "Personal defense cannot use an undetected adjacent enemy")
		Globals.unit_visible_enemies[shooter] = [enemy, distant]
		LOSHelper.los_lookup[shooter.current_hex].erase(enemy.current_hex)
		_check(await _attempt_personal_fire(assistant, enemy) == 0, "Personal defense requires current LOS")
		LOSHelper.los_lookup[shooter.current_hex][enemy.current_hex] = {"target_cover": 0}
		shooter.setAttackState(Unit.AttackState.MANUAL_GROUND)
		probe.set_target_hex(distant.current_hex)
		shooter.attack_ground_rounds_budget = 10
		_check(await _attempt_personal_fire(leader, enemy) > 0 and shooter.attack_ground_rounds_budget == 10,
			"Ground-fire orders permit adjacent defense without consuming their round budget")
		_check(probe.target_hex == distant.current_hex, "Adjacent defense preserves the ground-fire destination")
		await _test_personal_ground_order(leader, assistant, loader, distant.current_hex)
	shooter.squad_type = Globals.SquadType.Rifle
	_prepare_crew("res://resources/weapons/kar98.tres", 0, 0)
	_set_hex(enemy, Vector2i(3, 0))
	LOSHelper.los_lookup = {shooter.current_hex: {enemy.current_hex: {"target_cover": 0}}}
	probe.set_target_unit(enemy)
	gunner.role = RankGrades.Role.SOLDIER
	_check(await _attempt_personal_fire(gunner, enemy) > 0, "Ordinary rifle squads retain personal fire beyond one hex")
	probe.clear_target()
	Globals.unit_visible_enemies[shooter] = []
	distant.free()
	shooter.squad_type = original_type
	enemy.team = original_enemy_team
	Debug.dont_fire_wepaons = true


func _test_personal_ground_order(leader: Soldier, assistant: Soldier, loader: Soldier, distant_hex: Vector2i) -> void:
	gunner.is_alive = true
	gunner.weapon.ammunition = 100
	var controller: Node2D = get_tree().root.get_node("Main").world.game_controller
	var previous_selection: Unit = controller.selected_unit
	var previous_enemy_selectable: bool = Debug.enemy_selectable
	Debug.enemy_selectable = true
	controller.selected_unit = shooter
	Globals.unit_visible_enemies[shooter] = []
	var ordered_hex: Vector2i = Vector2i.ZERO
	LOSHelper.los_lookup[shooter.current_hex][ordered_hex] = {"target_cover": 0}
	_check(MatchInteractionHandler.order_via_option_wheel(controller, ordered_hex, WheelOption.Option.FIRE_AT),
		"The Fire wheel accepts an adjacent hex without a detected enemy")
	_check(shooter.attackState == Unit.AttackState.MANUAL_GROUND and probe.target_hex == ordered_hex and probe.target_unit == null,
		"The wheel creates a ground-fire target without inventing an enemy unit")
	for soldier: Soldier in [leader, assistant]:
		probe.impact_hexes.clear()
		_check(await _attempt_personal_fire(soldier, null) == 0 and not soldier.aquire_target_task.done,
			"An ordered adjacent ground hex starts normal personal-weapon acquisition")
		var budget: int = shooter.attack_ground_rounds_budget
		var ammunition: int = soldier.weapon.ammunition
		var shots: int = probe._try_fire_soldier(100.0, soldier, false, 0, 0, 0, 0)
		await get_tree().create_timer(0.02).timeout
		_check(shots > 0 and probe.impact_hexes == [ordered_hex] and soldier.weapon.ammunition == ammunition - shots,
			"Leaders and assistants fire at an ordered adjacent hex without detection")
		_check(shooter.attack_ground_rounds_budget == budget - shots, "Ordered personal fire consumes the ground-fire round budget")
		var cadence_remaining: float = soldier.reaim_remaining_s
		probe._try_fire_soldier(0.1, soldier, false, 0, 0, 0, 0)
		_check(soldier.reaim_remaining_s < cadence_remaining,
			"Repeated ground-fire attempts advance cadence instead of restarting acquisition")
	gunner.is_alive = true
	gunner.weapon.ammunition = 100
	_check(await _attempt_personal_fire(loader, null) == 0, "An explicit ground-fire order still reserves the active weapon's loader")
	shooter.attack_ground_rounds_budget = 1
	leader.weapon.burst_rounds = 3
	leader.rounds_in_mag = 5
	_check(await _attempt_personal_fire(leader, null) == 1 and shooter.attack_ground_rounds_budget == 0,
		"An ordered personal volley cannot exceed the remaining round budget")
	_check(await _attempt_personal_fire(leader, null) == 0, "An exhausted round budget stops ordered personal fire")
	leader.weapon.burst_rounds = 1
	shooter.setAttackState(Unit.AttackState.MANUAL_GROUND)
	LOSHelper.los_lookup[shooter.current_hex].erase(ordered_hex)
	_check(await _attempt_personal_fire(assistant, null) == 0, "Indirect mortar orders do not let personal weapons shoot through blocked LOS")
	LOSHelper.los_lookup[shooter.current_hex][ordered_hex] = {"target_cover": 0}
	probe.clear_target()
	_check(await _attempt_personal_fire(assistant, null) == 0, "Clearing the order removes permission to fire without detection")
	shooter.setAttackState(Unit.AttackState.MANUAL_GROUND)
	probe.set_target_hex(distant_hex)
	_check(await _attempt_personal_fire(assistant, null) == 0, "Ground-fire orders beyond one hex do not release personal weapons")
	controller.selected_unit = previous_selection
	Debug.enemy_selectable = previous_enemy_selectable


func _set_hex(unit: Unit, hex: Vector2i) -> void:
	unit.current_hex = hex
	unit.current_cube = LOSHelper.ground_layer.map_to_cube(hex)
	unit.position = LOSHelper.ground_layer.map_to_local(hex)


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
