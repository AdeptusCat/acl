extends Node

const SHOOTER_HEX: Vector2i = Vector2i(5, 5)
const CLOSE_HEX: Vector2i = Vector2i(6, 5)
const FRESH_HEX: Vector2i = Vector2i(9, 5)

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_node("DefaultMap")
	var scenario: Scenario = map.get_scenario(0)
	scenario.axis_ai_status = Scenario.AIStatus.ON
	scenario.allies_ai_status = Scenario.AIStatus.ON
	scenario.axis_ai_mode = Scenario.AIMode.DEFEND
	scenario.allies_ai_mode = Scenario.AIMode.DEFEND
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	var no_fire_before: bool = Debug.dont_fire_wepaons
	Debug.dont_fire_wepaons = true
	var original_los: Dictionary = LOSHelper.los_lookup
	for planner: PlatoonAI in [world.game_controller.get_node("PlatoonAi"), world.game_controller.get_node("PlatoonAi2")]:
		_test_defender(planner)
	LOSHelper.los_lookup = original_los
	Debug.dont_fire_wepaons = no_fire_before
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Defensive target checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_defender(planner: PlatoonAI) -> void:
	var shooter: Unit = null
	for unit: Unit in planner.squads:
		if unit.squad_type == Globals.SquadType.Rifle:
			shooter = unit
			break
	var enemies: Array[Unit] = Globals.get_units_for_team(Globals.get_enemy_team(planner.team))
	_check(shooter != null and enemies.size() >= 2, "The match supplies a rifle defender and two enemies for team %d" % planner.team)
	if shooter == null or enemies.size() < 2:
		return
	_check(planner.current_order.position_mode == PositionProfile.Mode.DEFEND and shooter.squad_ai_controller.defensive_mission_controlled, "A real defensive mission enables its target policy")
	var close_enemy: Unit = enemies[0]
	var fresh_enemy: Unit = enemies[1]
	for index: int in range(Globals.get_units().size()):
		_set_hex(Globals.get_units()[index], Vector2i(40 + index, 30))
	_set_hex(shooter, SHOOTER_HEX)
	_set_hex(close_enemy, CLOSE_HEX)
	_set_hex(fresh_enemy, FRESH_HEX)
	shooter.movement.stop()
	shooter.is_moving = false
	shooter.in_close_combat = false
	shooter.stress_system.state = UnitStates.MoraleState.NORMAL
	shooter.stress_system.S_eff = 0.0
	var fire: SquadFireController = shooter.squad_fire
	var original_soldiers: Array[Soldier] = fire.soldiers
	var weapon: WeaponSpec = WeaponSpec.new()
	weapon.range_hexes = 6
	var rifleman: Soldier = Soldier.new(999, "Defensive targeting", RankGrades.Grade.SOLDIER, RankGrades.Role.SOLDIER, weapon, shooter, shooter.team)
	fire.soldiers = [rifleman]
	LOSHelper.los_lookup = {SHOOTER_HEX: {CLOSE_HEX: {"target_cover": 0}, FRESH_HEX: {"target_cover": 4}}}
	Globals.unit_visible_enemies[shooter] = [close_enemy, fresh_enemy]
	close_enemy.stress_system.state = UnitStates.MoraleState.NORMAL
	close_enemy.stress_system.S_eff = 0.0
	fresh_enemy.stress_system.state = UnitStates.MoraleState.NORMAL
	fresh_enemy.stress_system.S_eff = 0.0
	var close_score: float = fire._score_enemy_for_target(shooter, close_enemy, SHOOTER_HEX)["score"]
	var fresh_score: float = fire._score_enemy_for_target(shooter, fresh_enemy, SHOOTER_HEX)["score"]
	_check(is_finite(fresh_score) and close_score > fresh_score, "The nearby exposed enemy is the better firing opportunity before suppression")
	_choose(shooter, close_enemy, "Fresh enemies retain distance and cover priorities")
	close_enemy.stress_system.state = UnitStates.MoraleState.PINNED
	close_enemy.stress_system.S_eff = 80.0
	_choose(shooter, fresh_enemy, "A defender shifts an existing target from a heavily stressed pinned enemy to a fresh enemy")
	Globals.unit_visible_enemies[shooter] = [fresh_enemy, close_enemy]
	rifleman.aquire_target_task.remaining_time_s = 0.25
	_choose(shooter, fresh_enemy, "Fresh-target priority is independent of visibility-list order")
	_check(is_equal_approx(rifleman.aquire_target_task.remaining_time_s, 0.25), "Keeping the selected fresh enemy preserves acquisition progress")
	close_enemy.stress_system.state = UnitStates.MoraleState.NORMAL
	close_enemy.stress_system.S_eff = close_enemy.stress_system.pin_threshold
	_choose(shooter, fresh_enemy, "Stress at the suppression threshold shifts fire before a morale transition")
	close_enemy.stress_system.state = UnitStates.MoraleState.PINNED
	close_enemy.stress_system.S_eff = 0.0
	_choose(shooter, fresh_enemy, "A pinned enemy remains lower priority while its morale state recovers")
	for state: UnitStates.MoraleState in [UnitStates.MoraleState.PANIC, UnitStates.MoraleState.COMBAT_INEFFECTIVE]:
		close_enemy.stress_system.state = state
		_choose(shooter, fresh_enemy, "Broken enemy state %d gives priority to fresh opposition" % state)
	fresh_enemy.stress_system.state = UnitStates.MoraleState.PINNED
	fresh_enemy.stress_system.S_eff = 80.0
	_choose(shooter, close_enemy, "When every enemy is suppressed the defender keeps firing at the best available target")
	close_enemy.stress_system.state = UnitStates.MoraleState.NORMAL
	close_enemy.stress_system.S_eff = close_enemy.stress_system.pin_threshold - 0.1
	_choose(shooter, close_enemy, "A recovered enemy becomes a priority again")
	close_enemy.stress_system.state = UnitStates.MoraleState.PINNED
	close_enemy.stress_system.S_eff = 80.0
	fresh_enemy.stress_system.state = UnitStates.MoraleState.NORMAL
	fresh_enemy.stress_system.S_eff = 0.0
	LOSHelper.los_lookup[SHOOTER_HEX].erase(FRESH_HEX)
	_choose(shooter, close_enemy, "Fresh opposition without current line of sight does not displace a valid suppressed target")
	LOSHelper.los_lookup[SHOOTER_HEX][FRESH_HEX] = {"target_cover": 4}
	Globals.unit_visible_enemies[shooter] = [close_enemy]
	_choose(shooter, close_enemy, "An undetected fresh enemy does not affect target choice")
	Globals.unit_visible_enemies[shooter] = [close_enemy, fresh_enemy]
	_set_hex(fresh_enemy, Vector2i(30, 5))
	LOSHelper.los_lookup[SHOOTER_HEX][fresh_enemy.current_hex] = {"target_cover": 0}
	_choose(shooter, close_enemy, "A fresh enemy outside weapon range does not displace a valid suppressed target")
	_set_hex(fresh_enemy, FRESH_HEX)
	fresh_enemy.surrendered = true
	_choose(shooter, close_enemy, "A surrendered fresh squad is excluded")
	fresh_enemy.surrendered = false
	fresh_enemy.alive = false
	_choose(shooter, close_enemy, "A dead fresh squad is excluded")
	fresh_enemy.alive = true
	var friendly: Unit = planner.squads[0]
	if friendly == shooter:
		friendly = planner.squads[1]
	var friendly_hex: Vector2i = friendly.current_hex
	_set_hex(friendly, FRESH_HEX)
	_choose(shooter, close_enemy, "Friendly occupation prevents shifting fire into a fresh enemy's hex")
	_set_hex(friendly, friendly_hex)
	shooter.setAttackState(Unit.AttackState.MANUAL_TRACK)
	fire.set_target_unit(close_enemy)
	fire.fire_timer = 0.0
	fire._process(0.0)
	_check(fire.target_unit == close_enemy and shooter.attackState == Unit.AttackState.MANUAL_TRACK, "An explicit tracked target remains selected despite a fresh alternative")
	planner.current_order.position_mode = PositionProfile.Mode.ASSAULT
	planner._set_mission_control(true)
	_check(not shooter.squad_ai_controller.defensive_mission_controlled, "An attack mission releases defensive targeting")
	_choose(shooter, close_enemy, "Attack auto-fire retains its existing firing-opportunity ranking")
	planner.current_order.position_mode = PositionProfile.Mode.DEFEND
	planner._set_mission_control(true)
	_choose(shooter, fresh_enemy, "Switching back to defense restores fresh-target priority")
	planner.set_active(false)
	_choose(shooter, close_enemy, "Disabling AI restores the existing player auto-fire policy")
	fire.soldiers = original_soldiers


func _choose(shooter: Unit, expected: Unit, message: String) -> void:
	shooter.setAttackState(Unit.AttackState.AUTO)
	shooter.squad_fire.fire_timer = 0.0
	shooter.squad_fire._process(0.0)
	_check(shooter.squad_fire.target_unit == expected and shooter.squad_fire.has_target_hex and shooter.squad_fire.target_hex == expected.current_hex, message)


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
