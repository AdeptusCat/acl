extends Node

class UnitProbe extends Unit:
	func _make_squad() -> void:
		pass


var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_test_unpin_timer()
	_test_pressure_history()
	_test_pressure_timing()
	_test_live_cohesion()
	print("Stress input checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _unit() -> Unit:
	var unit: Unit = UnitProbe.new()
	unit.squad_type = Globals.SquadType.Rifle
	unit.stress_system = StressController.new()
	unit.add_child(unit.stress_system)
	unit.stress_system.refractory_s = 100000.0
	unit.stress_system._since_change = 0.0
	return unit


func _test_unpin_timer() -> void:
	var unit: Unit = _unit()
	var stress: StressController = unit.stress_system
	stress._repin_since_unpin = 999.0
	stress._set_state(STATES.MoraleState.PINNED)
	_check(stress._unpin_ramp_multiplier() == 0.0, "First pin starts its recovery ramp at zero despite long prior good order")
	stress._process(stress.unpin_ramp_s * 0.25)
	_check(is_equal_approx(stress._unpin_ramp_multiplier(), 0.25), "Unpin ramp follows actual time spent pinned")
	stress._set_state(STATES.MoraleState.CAUTIOUS)
	_check(stress._repin_ramp_multiplier() == 0.0, "Unpinning separately resets the repin ramp")
	stress._process(stress.repin_ramp_s * 0.5)
	_check(is_equal_approx(stress._repin_ramp_multiplier(), 0.5), "Time in cautious morale advances repin protection")
	stress._set_state(STATES.MoraleState.PINNED)
	_check(stress._unpin_ramp_multiplier() == 0.0, "A subsequent pin restarts its own recovery ramp")
	stress._repin_since_unpin = 0.0
	stress._process(stress.unpin_ramp_s)
	_check(stress._unpin_ramp_multiplier() == 1.0, "Unpin recovery reaches full strength independently of repin history")
	unit.free()


func _test_pressure_history() -> void:
	var unit: Unit = _unit()
	var stress: StressController = unit.stress_system
	stress.mark_under_fire(10.0)
	_check(stress.under_fire and is_equal_approx(stress._last_pressure_rps, 10.0), "A volley immediately starts normalized pressure tracking")
	stress._process(0.5)
	_check(is_equal_approx(stress._last_pressure_rps, 7.5), "Pressure fades with simulation time between impacts")
	var before_second: float = stress.get_recovery_capacity()
	stress.mark_under_fire(2.0)
	_check(is_equal_approx(stress._last_pressure_rps, 9.5), "A smaller second volley adds to pressure instead of replacing it")
	_check(stress.get_recovery_capacity() < before_second, "Additional incoming fire further slows actual recovery capacity")
	stress._process(0.5)
	_check(is_equal_approx(stress._last_pressure_rps, 6.5), "Separate volleys retain their individual ages")
	stress._process(1.0)
	_check(is_equal_approx(stress._last_pressure_rps, 0.5) and stress.under_fire, "Expiring an older volley preserves a more recent impact")
	var remaining: float = stress._under_fire_t
	for rounds: float in [0.0, -10.0, INF, NAN]:
		stress.mark_under_fire(rounds)
	_check(is_equal_approx(stress._under_fire_t, remaining) and is_equal_approx(stress._last_pressure_rps, 0.5), "Invalid or empty volleys cannot refresh, erase or corrupt pressure")
	stress._process(0.5)
	_check(stress._last_pressure_rps == 0.0 and not stress.under_fire and stress._fire_pressure_samples.is_empty(), "All pressure and fire flags clear when the final sample expires")
	_check(is_equal_approx(stress.get_recovery_capacity(), 1.5), "Recovery returns to baseline after incoming fire stops")
	stress.under_fire_window_s = 0.0
	stress.mark_under_fire(10.0)
	_check(stress._last_pressure_rps == 0.0 and not stress.under_fire, "A disabled fire window cannot divide by zero or retain samples")
	stress.under_fire_window_s = 4.0
	stress.mark_under_fire(10.0)
	_check(is_equal_approx(stress._last_pressure_rps, 5.0), "A longer history normalizes round counts into a rate rather than treating them as rps")
	unit.free()


func _test_pressure_timing() -> void:
	var burst: StressController = StressController.new()
	var bullets: StressController = StressController.new()
	burst.mark_under_fire(10.0)
	for index: int in range(10):
		bullets.mark_under_fire(1.0)
	_check(is_equal_approx(burst._last_pressure_rps, bullets._last_pressure_rps), "Simultaneous attackers and individual bullets contribute the same combined volume")
	_check(bullets._fire_pressure_samples.size() == 1, "Same-tick impacts share one bounded history entry")
	var previous: float = burst._last_pressure_rps
	var integral: float = 0.0
	for index: int in range(16):
		burst._advance_fire_pressure(0.125)
		integral += (previous + burst._last_pressure_rps) * 0.5 * 0.125
		previous = burst._last_pressure_rps
	_check(is_equal_approx(integral, 10.0), "Integrating the pressure rate over its window recovers the actual round count")
	for step: float in [0.125, 0.03125]:
		var stress: StressController = StressController.new()
		stress.mark_under_fire(5.0)
		for tick: int in range(roundi(0.5 / step)):
			stress._advance_fire_pressure(step)
		stress.mark_under_fire(3.0)
		for tick: int in range(roundi(0.5 / step)):
			stress._advance_fire_pressure(step)
		_check(is_equal_approx(stress._last_pressure_rps, 4.75), "An identical fire schedule gives identical pressure at step %s" % step)
		stress.free()
	burst.free()
	bullets.free()


func _test_live_cohesion() -> void:
	var unit: Unit = _unit()
	var stats: UnitCombatStats = UnitCombatStats.new()
	unit.combat_stats = stats
	unit.add_child(stats)
	unit.command_connectivity = CommandConnectivity.new()
	unit.add_child(unit.command_connectivity)
	unit.movement = UnitMovement.new()
	unit.add_child(unit.movement)
	stats.cohesion_current = 0.4
	stats.setup(unit)
	_check(is_equal_approx(unit.stress_system.cohesion, 0.4) and is_equal_approx(unit.stress_system.get_recovery_capacity(), 0.6), "Setup feeds loaded combat cohesion into stress recovery immediately")
	stats.update_stats(1.0)
	_check(stats.cohesion_current > 0.4 and is_equal_approx(unit.stress_system.cohesion, stats.cohesion_current), "Natural combat cohesion recovery updates the stress input")
	unit.stress_system.add_leadership_source(1, 0.1, 0.1, 1.2)
	_check(is_equal_approx(unit.stress_system.get_recovery_capacity(), stats.cohesion_current * 1.2 * 1.5), "Aura cohesion multiplies live cohesion once")
	stats.update_stats(0.0)
	stats.update_stats(0.0)
	_check(is_equal_approx(unit.stress_system.cohesion, stats.cohesion_current), "Repeated updates do not fold aura bonuses into base cohesion")
	stats.cohesion_current = 1.0
	stats.notify_casualty_taken(1)
	stats.update_stats(1.0)
	_check(stats.cohesion_current < 1.0 and is_equal_approx(unit.stress_system.cohesion, stats.cohesion_current), "A casualty-induced cohesion drop reaches stress recovery through the live stats update")
	unit.stress_system.remove_leadership_source(1)
	_check(is_equal_approx(unit.stress_system.get_recovery_capacity(), stats.cohesion_current * 1.5), "Removing an aura restores recovery based on current combat cohesion")
	unit.free()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
