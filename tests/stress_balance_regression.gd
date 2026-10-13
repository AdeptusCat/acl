extends Node

class UnitProbe extends Unit:
	func _make_squad() -> void:
		pass

var checks: int = 0
var failures: int = 0
var probes: Array[Unit] = []
var view: UnitUi


func _ready() -> void:
	view = load("res://scenes/game/units/presentation/unit_battlefield_view.tscn").instantiate() as UnitUi
	add_child(view)
	_check(view.stress_arrows.text.is_empty() and view.recovery_arrows.text.is_empty(), "Idle squads start without placeholder arrows")
	_check_modifiers_and_expiry()
	_check_weak_and_balanced_incoming()
	_check_caps_and_empty_bins()
	_check_situational_recovery()
	_check_successive_hits()
	var coarse: StressController = _simulate_volley_series(0.125)
	var fine: StressController = _simulate_volley_series(0.03125)
	_check(is_equal_approx(coarse.S_eff, fine.S_eff) and is_equal_approx(coarse.incoming_stress_rate, fine.incoming_stress_rate) and is_equal_approx(coarse.stress_recovery_rate, fine.stress_recovery_rate), "The same volley schedule has the same stress and balance at different frame rates")
	for rates: Vector2 in [Vector2(1.0, 1.0001), Vector2(1.0001, 1.0), Vector2(0.01, 1.0), Vector2(1.0, 0.01)]:
		var counts: Vector2i = UnitUi.stress_balance_arrow_counts(rates.x, rates.y)
		_check(signi(counts.x - counts.y) == signf(rates.x - rates.y), "Arrow rounding preserves which influence outweighs the other: %s" % rates)
	for probe: Unit in probes:
		probe.free()
	print("Stress balance checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _create_stress(fast: float, slow: float) -> StressController:
	var probe: Unit = UnitProbe.new()
	probe.squad_type = Globals.SquadType.Rifle
	probes.append(probe)
	var stress: StressController = StressController.new()
	probe.add_child(stress)
	stress.stress_fast = fast
	stress.stress_slow = slow
	stress.S_eff = (fast + slow) * 0.5
	# Isolate the balance arithmetic from probabilistic morale transitions.
	stress.refractory_s = 100000.0
	stress._since_change = 0.0
	stress.stress_balance_changed.connect(view._on_stress_balance_changed)
	return stress


func _check_modifiers_and_expiry() -> void:
	var stress: StressController = _create_stress(60.0, 20.0)
	stress.leadership_bonus = 0.18
	stress.cohesion = 0.8
	stress.mark_under_fire(5.0)
	stress.apply_stress(10.0, 4.0)
	# 40 stress gives a 0.8 gain modifier; leadership gives 0.91.
	_check(is_equal_approx(stress.S_eff, 45.096), "A hit immediately updates effective stress using the actual leadership and stress modifiers")
	stress._process(0.5)
	_check(is_equal_approx(stress.incoming_stress_rate, 10.192), "Incoming rate counts weighted, modified gain rather than raw fast-plus-slow damage")
	_check(is_equal_approx(stress.stress_recovery_rate, 0.2) and is_equal_approx(stress.net_stress_rate, 9.992), "Recovery uses the real cohesion and fire-pressure slowdown in the same units as incoming stress")
	_check(is_equal_approx(stress.S_eff - 40.0, stress.net_stress_rate * stress.balance_sample_duration_s), "The measured net rate exactly explains the stress meter's change")
	_check(view.stress_arrows.text.length() > view.recovery_arrows.text.length(), "Increasing stress shows more red arrows than green arrows")
	_check(view.stress_arrows.tooltip_text.contains("+10.19/s") and view.recovery_arrows.tooltip_text.contains("-0.20/s"), "Both arrow tooltips explain the measured numerical balance")
	var before_recovery: float = stress.S_eff
	stress._process(0.5)
	_check(stress.incoming_stress_rate == 0.0 and stress.net_stress_rate < 0.0 and stress.S_eff < before_recovery, "The first sample without a new hit reports only real recovery")
	_check(stress.S_eff > 40.0 and view.stress_arrows.text.is_empty() and view.recovery_arrows.text == ">>>", "Red arrows disappear even when accumulated stress remains high")
	_check(is_equal_approx(stress.get_average_stress_rate(), stress.incoming_stress_rate), "The incoming-rate accessor reports the corrected effective rate")


func _check_weak_and_balanced_incoming() -> void:
	var weak: StressController = _create_stress(50.0, 50.0)
	weak.apply_stress(0.2, 0.2)
	weak._process(0.5)
	_check(is_equal_approx(weak.incoming_stress_rate, 0.3) and is_equal_approx(weak.stress_recovery_rate, 1.0) and is_equal_approx(weak.net_stress_rate, -0.7), "Weak incoming stress can be outweighed by recovery")
	_check(view.stress_arrows.text.length() > 0 and view.recovery_arrows.text.length() > view.stress_arrows.text.length(), "Falling stress under light incoming stress still shows more green arrows")
	var balanced: StressController = _create_stress(50.0, 50.0)
	balanced.apply_stress(2.0 / 3.0, 2.0 / 3.0)
	balanced._process(0.5)
	_check(is_equal_approx(balanced.S_eff, 50.0) and is_zero_approx(balanced.net_stress_rate), "Equal gain and recovery leave the stress meter unchanged")
	_check(view.stress_arrows.text == "<<" and view.recovery_arrows.text == ">>", "A balanced influence has equal arrow counts")


func _check_caps_and_empty_bins() -> void:
	var capped: StressController = _create_stress(99.9, 100.0)
	capped.recovery_scale = 0.0
	capped.apply_stress(100.0, 100.0)
	capped._process(0.5)
	_check(is_equal_approx(capped.S_eff, 100.0) and is_equal_approx(capped.incoming_stress_rate, 0.1), "Incoming rate counts only the gain that fits below the stress cap")
	capped.apply_stress(100.0, 100.0)
	capped._process(0.5)
	_check(capped.incoming_stress_rate == 0.0 and view.stress_arrows.text.is_empty() and view.recovery_arrows.text.is_empty(), "A capped meter with no recovery does not claim an impossible stress increase")
	var partial: StressController = _create_stress(0.0, 1.0)
	partial._process(0.5)
	_check(is_equal_approx(partial.S_eff, 0.25) and is_equal_approx(partial.stress_recovery_rate, 0.5), "An empty fast bin contributes no fictional recovery to the effective rate")
	_check(partial.leadership_bonus == 0.0 and view.recovery_arrows.text == ">>>", "Natural recovery shows green arrows without a leader")
	partial._process(0.5)
	partial._process(0.5)
	_check(partial.S_eff == 0.0 and partial.stress_recovery_rate == 0.0 and view.stress_arrows.text.is_empty() and view.recovery_arrows.text.is_empty(), "Recovery and arrows stop once both stress bins are empty")
	partial.apply_stress(-10.0, -10.0)
	partial._process(0.5)
	_check(partial.incoming_stress_rate == 0.0 and partial.S_eff == 0.0, "Negative stress inputs cannot create false incoming influence")


func _check_situational_recovery() -> void:
	var stress: StressController = _create_stress(40.0, 40.0)
	var headquarters: Unit = stress.get_parent() as Unit
	headquarters.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
	stress.state = STATES.MoraleState.PINNED
	stress.leader_presence_strength = 0.5
	stress.recovery_scale = 1.2
	stress.cohesion = 0.4
	stress.add_leadership_source(1, 0.1, 0.1, 1.2)
	stress.on_casualty_event(1)
	stress.mark_under_fire(stress.pressure_ref_rps)
	stress.incoming_stress_scale = 2.0
	stress.apply_stress(1.0, 0.5)
	stress._process(0.5)
	# Recovery: (0.35 + 0.65 * 0.5) * 2 * 1.2 * 0.48 * 0.7375 * 0.1.
	_check(is_equal_approx(stress.stress_recovery_rate, 0.057348), "Recovery rate includes pinned morale, headquarters, leadership presence, cohesion, casualty shock and heavy fire")
	_check(is_equal_approx(stress.incoming_stress_rate, 2.28), "Incoming scaling and leader protection affect the measured gain")
	_check(is_equal_approx(stress.S_eff - 40.0, stress.net_stress_rate * 0.5), "The complete situational balance agrees with the actual meter change")


func _check_successive_hits() -> void:
	var stress: StressController = _create_stress(20.0, 20.0)
	stress.recovery_scale = 0.0
	stress.apply_stress(10.0, 10.0)
	stress.apply_stress(10.0, 10.0)
	stress._process(0.5)
	_check(is_equal_approx(stress.S_eff, 37.55) and is_equal_approx(stress.incoming_stress_rate, 35.1), "Successive hits use the current stress modifier instead of stale stress from the previous frame")


func _simulate_volley_series(step: float) -> StressController:
	var stress: StressController = _create_stress(20.0, 20.0)
	var frames_per_sample: int = roundi(0.5 / step)
	for sample: int in range(4):
		var before: float = stress.S_eff
		stress.apply_stress(2.0, 1.0)
		for frame: int in range(frames_per_sample):
			stress._process(step)
		_check(is_equal_approx(stress.S_eff - before, stress.net_stress_rate * stress.balance_sample_duration_s), "Sampled influence explains a multi-frame volley interval at step %s" % step)
	return stress


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
