extends Node

class UnitProbe extends Unit:
	var simulation_time: float = 0.0

	func _make_squad() -> void:
		pass

	func _now() -> float:
		return simulation_time


var checks: int = 0
var failures: int = 0


func _ready() -> void:
	var previous_no_damage: bool = Debug.no_damage
	Debug.no_damage = false
	_test_pinned_capacity()
	_test_quiet_timing()
	_test_high_stress_unpin_gate()
	for support: float in [0.0, 1.0]:
		for opposing: bool in [false, true]:
			var unpin_total: float = 0.0
			var normal_total: float = 0.0
			for random_seed: int in range(16):
				var recovery: Vector2 = _test_live_recovery(random_seed, support, opposing)
				unpin_total += recovery.x
				normal_total += recovery.y
			print("Recovery after fire: support=", support, "; opposing=", opposing, "; mean unpin=", unpin_total / 16.0, "; mean normal=", normal_total / 16.0)
	Debug.no_damage = previous_no_damage
	print("Pinning recovery checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _unit() -> UnitProbe:
	var unit: UnitProbe = UnitProbe.new()
	unit.members_alive = 12
	unit.original_size = 12
	unit.tactical_state = SquadTacticalState.new()
	unit.stress_system = StressController.new()
	unit.add_child(unit.stress_system)
	unit.combat_stats = UnitCombatStats.new()
	unit.add_child(unit.combat_stats)
	return unit


func _test_pinned_capacity() -> void:
	var unit: UnitProbe = _unit()
	unit.stress_system.stress_fast = 90.0
	unit.stress_system.stress_slow = 90.0
	unit.stress_system._update_effective_stress()
	unit.tactical_state.update_attention(unit)
	var normal: float = unit.tactical_state.attention_capacity
	unit.stress_system._set_state(STATES.MoraleState.PINNED)
	unit.tactical_state.update_attention(unit)
	_check(is_equal_approx(unit.tactical_state.attention_capacity, normal * 0.8), "Pinning retains 80 percent of the same squad's stressed observation capacity")
	_check(unit.tactical_state.attention_capacity < normal, "Pinning still reduces observation capacity")
	unit.free()


func _test_quiet_timing() -> void:
	for step: float in [0.125, 0.25, 0.5, 0.75]:
		var stress: StressController = StressController.new()
		stress.mark_under_fire(8.0)
		for tick: int in range(roundi(6.0 / step)):
			stress._advance_fire_pressure(step)
		_check(is_equal_approx(stress._time_without_fire_s, 4.0) and stress._can_unpin_after_fire(), "Quiet time starts at actual pressure expiry, including a step that crosses expiry: %s" % step)
		stress.mark_under_fire(1.0)
		_check(stress._time_without_fire_s == 0.0 and not stress._can_unpin_after_fire(), "Renewed fire immediately cancels quiet recovery eligibility")
		stress._advance_fire_pressure(2.0)
		_check(not stress.under_fire and not stress._can_unpin_after_fire(), "Pressure expiry alone does not skip the quiet recovery delay")
		stress._advance_fire_pressure(stress.unpin_no_fire_delay_s)
		_check(stress._can_unpin_after_fire(), "High-stress recovery becomes eligible after the configured quiet delay")
		var quiet: float = stress._time_without_fire_s
		for rounds: float in [0.0, -1.0, INF, NAN]:
			stress.mark_under_fire(rounds)
		_check(stress._time_without_fire_s == quiet, "Invalid or empty impacts do not cancel quiet recovery")
		stress.free()


func _test_high_stress_unpin_gate() -> void:
	var unit: UnitProbe = _unit()
	var stress: StressController = unit.stress_system
	stress.stress_fast = 90.0
	stress.stress_slow = 90.0
	stress._update_effective_stress()
	stress._set_state(STATES.MoraleState.PINNED)
	stress._since_change = 999.0
	stress._since_pinned = stress.unpin_ramp_s
	# Make an eligible roll certain, so this isolates the gate rather than luck.
	stress.L_PINNED_TO_CAUTIOUS = 1000000.0
	stress.L_CAUTIOUS_TO_PINNED = 1000000.0
	stress.mark_under_fire(10.0)
	stress._maybe_transition(0.1)
	_check(stress.state == STATES.MoraleState.PINNED, "High stress remains pinned during actual fire even with a guaranteed recovery roll")
	stress._advance_fire_pressure(stress.under_fire_window_s)
	stress._advance_fire_pressure(stress.unpin_no_fire_delay_s - 0.1)
	stress._maybe_transition(0.1)
	_check(stress.state == STATES.MoraleState.PINNED, "A brief lull cannot unpin maximum-pressure morale immediately")
	stress._advance_fire_pressure(0.2)
	stress._maybe_transition(0.1)
	_check(stress.state == STATES.MoraleState.CAUTIOUS and stress.S_eff == 90.0, "Quiet high-stress squads can unpin before crossing the panic threshold")
	_check(stress._repin_since_unpin == 0.0, "Quiet unpinning retains ordinary repin protection")
	stress._since_change = 999.0
	stress._maybe_transition(0.1)
	_check(stress.state == STATES.MoraleState.CAUTIOUS, "High residual stress alone does not repin a squad when fire has stopped")
	stress._repin_since_unpin = stress.repin_ramp_s
	stress.mark_under_fire(1.0)
	stress._maybe_transition(0.1)
	_check(stress.state == STATES.MoraleState.PINNED and stress._time_without_fire_s == 0.0, "Renewed actual fire can repin a recovered squad and clears quiet time")
	_check(stress._since_pinned == 0.0, "A later pin restarts the unpin ramp")
	unit.free()


func _test_live_recovery(random_seed: int, support: float, opposing: bool) -> Vector2:
	var unit: UnitProbe = _unit()
	var stress: StressController = unit.stress_system
	stress.leader_presence_strength = support
	stress.stress_fast = 100.0
	stress.stress_slow = 100.0
	stress._update_effective_stress()
	stress._set_state(STATES.MoraleState.PINNED)
	var enemies: Array[Unit] = []
	for index: int in range(6):
		var enemy: Unit = Unit.new()
		enemy.team = Globals.get_enemy_team(unit.team)
		var angle: float = deg_to_rad(float(index) * 8.0 - 20.0)
		if opposing and index >= 3:
			angle += PI
		enemy.position = Vector2.from_angle(angle) * 200.0
		enemy.squad_fire = SquadFireController.new()
		enemy.add_child(enemy.squad_fire)
		enemy.squad_fire.fire_recent = 1.0
		enemies.append(enemy)
	Globals.unit_visible_enemies[unit] = enemies
	seed(random_seed)
	var unpinned_during_fire: bool = false
	var unpinned_after: float = -1.0
	var normal_after: float = -1.0
	var unpin_stress: float = 0.0
	for tick: int in range(760):
		unit.simulation_time = float(tick) * 0.25
		var firing: bool = tick < 40
		if firing and tick % 2 == 0:
			stress.mark_under_fire(8.0)
			stress.apply_stress(12.0, 8.0)
			unit.tactical_state.register_incoming_fire(enemies[(tick / 2) % enemies.size()].position, unit.simulation_time)
		for enemy: Unit in enemies:
			if firing:
				enemy.squad_fire.fire_recent = 1.0
			else:
				enemy.squad_fire.update_fire_recent(0.25)
		unit.tactical_state.update_attention(unit)
		stress._process(0.25)
		if firing:
			if stress.state != STATES.MoraleState.PINNED:
				unpinned_during_fire = true
		else:
			var since_stop: float = unit.simulation_time + 0.25 - 10.0
			if unpinned_after < 0.0 and stress.state != STATES.MoraleState.PINNED:
				unpinned_after = since_stop
				unpin_stress = stress.S_eff
			if normal_after < 0.0 and stress.state == STATES.MoraleState.NORMAL:
				normal_after = since_stop
	_check(not unpinned_during_fire, "Sustained heavy fire holds a high-stress squad pinned; seed %d, support %.1f, opposing %s" % [random_seed, support, opposing])
	_check(unpinned_after >= 4.5 and unpinned_after < 30.0 and unpin_stress > stress.panic_threshold, "Intact squads unpin after a real quiet interval while residual stress is above 65; seed %d, support %.1f, opposing %s" % [random_seed, support, opposing])
	_check(normal_after > unpinned_after and normal_after < 150.0 and stress.S_eff < 1.0, "Recovery completes with all six contacts still visible; seed %d, support %.1f, opposing %s" % [random_seed, support, opposing])
	_check(unit.members_alive == 12 and unit.combat_stats.cohesion_current == 1.0, "The recovery fixture retains a full cohesive squad")
	Globals.unit_visible_enemies.erase(unit)
	unit.free()
	for enemy: Unit in enemies:
		enemy.free()
	return Vector2(unpinned_after, normal_after)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
