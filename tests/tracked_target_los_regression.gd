extends "res://tests/burst_target_regression.gd"

# Reuse the actual match and burst-visual fixture. Exercise the real acquisition,
# movement, visibility publication, and firing paths at an authored LOS boundary.
const OBSERVER_HEX: Vector2i = Vector2i(0, 0)
const VISIBLE_HEX: Vector2i = Vector2i(0, 4)
const HIDDEN_HEX: Vector2i = Vector2i(0, 5)

class FireProbe extends SquadFireController:
	var impact_hexes: Array[Vector2i] = []
	var pending_bursts: int = 0
	signal bursts_complete

	func _on_fire_weapon(_weapon: WeaponSpec, _position: Vector2, _auto: bool, _owner_id: int, _owner: Node2D) -> void:
		pass

	func _on_stop_mg_loop(_weapon: WeaponSpec, _position: Vector2, _owner_id: int, _owner: Node2D) -> void:
		pass

	func fire_at(_rounds: int, _weapon: WeaponSpec, _grenade: bool, hex: Vector2i, _distance: int, _cover: int, _targets: Array[Unit]) -> void:
		impact_hexes.append(hex)

	func fire_shots(s: Soldier, shots: int, rpm: float, auto_fire: bool, shot_target_hex: Vector2i) -> void:
		pending_bursts += 1
		await super.fire_shots(s, shots, rpm, auto_fire, shot_target_hex)
		pending_bursts -= 1
		if pending_bursts == 0:
			bursts_complete.emit()


var alternate_enemy: Unit


func _test_sight_loss(attack_state: Unit.AttackState) -> void:
	for unit: Unit in Globals.get_units():
		if alternate_enemy == null and unit != enemy and unit.team == enemy.team:
			alternate_enemy = unit
		if unit != shooter and unit != enemy:
			unit.remove_from_group("units")
	var original_fire: SquadFireController = shooter.squad_fire
	var probe: FireProbe = FireProbe.new()
	probe.unit = shooter
	probe.stress_controller = shooter.stress_system
	shooter.add_child(probe)
	probe.set_process(false)
	probe.soldiers = [gunner]
	shooter.squad_fire = probe
	probe.fire_shot.connect(shooter._on_fire_shot)
	gunner.weapon.burst_rounds = 3
	gunner.weapon.rpm = 600.0
	gunner.weapon.projectile_speed = 100000
	for path: String in ["burst", "process", "assignment", "observer_move"]:
		await _test_los_transition(probe, attack_state, path)
	await _test_ground_fire(probe)
	_test_auto_selection(probe)
	shooter.squad_fire = original_fire
	probe.calc.free()
	probe.queue_free()
	await get_tree().process_frame


func _test_los_transition(probe: FireProbe, attack_state: Unit.AttackState, path: String) -> void:
	_set_hex(shooter, OBSERVER_HEX)
	_check(LOSHelper.los_lookup[OBSERVER_HEX].has(VISIBLE_HEX) and not LOSHelper.los_lookup[OBSERVER_HEX].has(HIDDEN_HEX), "Authored fixture crosses a visible-to-hidden hex boundary")
	probe.impact_hexes.clear()
	gunner.rounds_in_mag = 30
	gunner.weapon.ammunition = 100
	_prepare_target(VISIBLE_HEX, attack_state)
	LOS.update_all_unit_visibilities()
	var track: EnemyTrack = EnemyTrack.new(shooter, enemy)
	track.confidence = 1.0
	track.currently_in_los = true
	track.is_visible = true
	var tracks: Dictionary[Unit, EnemyTrack] = {enemy: track}
	Globals.unit_enemy_tracks = {shooter: tracks}
	var controller: Node = get_tree().root.get_node("Main").world.game_controller
	controller._on_unit_visibility_checker_timer_timeout()
	_check(Globals.unit_visible_enemies[shooter].has(enemy) and probe.target_unit == enemy, "Fixture starts with a detected and tracked enemy")
	_fire_burst(VISIBLE_HEX)
	_check(visual.destinations.size() == 1, "First shot precedes LOS loss")
	if path == "observer_move":
		var blocked_origin: Vector2i = _find_blocked_origin()
		shooter.position = LOSHelper.ground_layer.map_to_local(blocked_origin)
		shooter.movement._update_current_hex(blocked_origin)
		_check(enemy.current_hex == VISIBLE_HEX and probe.target_hex == VISIBLE_HEX, "Observer movement loses LOS without changing the enemy's hex")
	else:
		enemy.position = LOSHelper.ground_layer.map_to_local(HIDDEN_HEX)
		enemy.movement._update_current_hex(HIDDEN_HEX)
	_check(not Globals.unit_enemies_in_los[shooter].has(enemy) and Globals.unit_visible_enemies[shooter].has(enemy), "Movement removes LOS before the detection timer refreshes")
	if path == "process":
		gunner.setup_weapon_task.done = false
		gunner.setup_weapon_task.remaining_time_s = 1.0
		probe.fire_timer = 0.0
		probe._process(0.0)
		_check(probe.target_unit == null, "Frame processing clears a hidden target while the weapon is unready")
	elif path == "assignment":
		probe.set_target_unit(enemy)
		_check(probe.target_unit == null, "Target assignment rejects an enemy at its hidden new hex")
	_ready_gunner()
	seed(6049)
	var new_shots: int = await probe._try_fire_soldier(0.1, gunner, false, 0, 0, 0, 0)
	_check(new_shots == 0 and gunner.weapon.ammunition == 100, "%s state %d: stale detection cannot start or spend ammunition on a hidden burst" % [path, attack_state])
	_check(probe.target_unit == null and not probe.has_target_hex and not probe.has_mortar_target_hex, "LOS loss clears tracked target flags")
	_check(shooter.attackState == Unit.AttackState.AUTO, "LOS loss ends manual tracking")
	if probe.pending_bursts > 0:
		await probe.bursts_complete
	_check_destinations([VISIBLE_HEX, VISIBLE_HEX, VISIBLE_HEX], "Only the original burst finishes at the last visible hex")
	_check(probe.impact_hexes.is_empty(), "No new damage volley is launched toward the hidden hex")
	probe.set_target_unit(enemy)
	_check(probe.target_unit == null, "A stale detection cannot reacquire the hidden target")
	controller._on_unit_visibility_checker_timer_timeout()
	_check(not Globals.unit_visible_enemies[shooter].has(enemy), "Detection refresh removes the hidden enemy")
	_set_hex(shooter, OBSERVER_HEX)
	_set_hex(enemy, VISIBLE_HEX)
	LOS.update_all_unit_visibilities()
	probe.set_target_unit(enemy)
	_check(probe.target_unit == null, "Returning to LOS also requires detection before reacquisition")
	controller._on_unit_visibility_checker_timer_timeout()
	_check(Globals.unit_visible_enemies[shooter].has(enemy), "Visibility refresh detects the returning enemy")
	shooter.setAttackState(attack_state)
	probe.set_target_unit(enemy)
	_ready_gunner()
	seed(6049)
	var reacquired_shots: int = await probe._try_fire_soldier(0.1, gunner, false, 0, 0, 0, 0)
	_check(reacquired_shots > 0 and probe.target_unit == enemy, "A visible reacquired target can start a new burst")
	if probe.pending_bursts > 0:
		await probe.bursts_complete
	var expected: Array[Vector2i] = [VISIBLE_HEX, VISIBLE_HEX, VISIBLE_HEX]
	for shot: int in range(reacquired_shots):
		expected.append(VISIBLE_HEX)
	_check_destinations(expected, "Reacquired burst uses the visible destination")
	_check(probe.impact_hexes == [VISIBLE_HEX], "Reacquisition launches a damage volley at the visible hex")


func _test_ground_fire(probe: FireProbe) -> void:
	var original_weapon: WeaponSpec = gunner.weapon
	_set_hex(shooter, OBSERVER_HEX)
	Globals.unit_visible_enemies[shooter] = []
	for family: WeaponSpec.Family in [WeaponSpec.Family.SMALL_ARM, WeaponSpec.Family.MORTAR]:
		visual.destinations.clear()
		probe.impact_hexes.clear()
		gunner.weapon = WeaponSpec.new()
		gunner.weapon.family = family
		gunner.weapon.range_hexes = 100
		gunner.weapon.projectile_speed = 100000
		gunner.rounds_in_mag = gunner.weapon.mag_capacity
		shooter.setAttackState(Unit.AttackState.MANUAL_GROUND)
		probe.set_target_hex(HIDDEN_HEX)
		_ready_gunner()
		var ground_shots: int = await probe._try_fire_soldier(0.1, gunner, false, 0, 0, 0, 0)
		_check(ground_shots == 1, "Deliberate ground fire remains available outside LOS for family %d" % family)
		if probe.pending_bursts > 0:
			await probe.bursts_complete
		_check_destinations([HIDDEN_HEX], "Ground-fire visuals retain their explicit destination")
		_check(probe.impact_hexes == [HIDDEN_HEX], "Ground fire launches its original damage volley")
	gunner.weapon = original_weapon


func _test_auto_selection(probe: FireProbe) -> void:
	_check(alternate_enemy != null, "Fixture includes another visible enemy")
	if alternate_enemy == null:
		return
	_set_hex(shooter, OBSERVER_HEX)
	_set_hex(enemy, HIDDEN_HEX)
	_set_hex(alternate_enemy, VISIBLE_HEX)
	alternate_enemy.add_to_group("units")
	var original_entry: Dictionary = LOSHelper.los_lookup[OBSERVER_HEX][VISIBLE_HEX]
	LOSHelper.los_lookup[OBSERVER_HEX][VISIBLE_HEX] = {"target_cover": 4}
	gunner.weapon.range_hexes = 6
	Globals.unit_visible_enemies[shooter] = [enemy, alternate_enemy]
	shooter.setAttackState(Unit.AttackState.AUTO)
	probe.fire_timer = 0.0
	probe.handle_auto_fire(0.0, shooter, shooter.current_hex, 6, 0.75, 1.0)
	_check(probe.target_unit == alternate_enemy, "Auto selection skips a higher-scoring stale hidden enemy and picks the visible enemy")
	gunner.weapon.range_hexes = 100
	LOSHelper.los_lookup[OBSERVER_HEX][VISIBLE_HEX] = original_entry
	alternate_enemy.remove_from_group("units")


func _find_blocked_origin() -> Vector2i:
	for hex: Vector2i in LOSHelper.los_lookup:
		if hex != VISIBLE_HEX and not LOSHelper.los_lookup[hex].has(VISIBLE_HEX):
			return hex
	_check(false, "Authored map includes an observer hex without LOS to the target")
	return OBSERVER_HEX


func _ready_gunner() -> void:
	gunner.setup_weapon_task.done = true
	gunner.reload_task.done = true
	gunner.aquire_target_task.done = true
