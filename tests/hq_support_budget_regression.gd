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
	_test_budget_matrix()
	_test_support_loss()
	_test_panic_rally_gate()
	_test_recovery_profiles()
	Debug.no_damage = previous_no_damage
	print("HQ support budget checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _unit() -> UnitProbe:
	var unit: UnitProbe = UnitProbe.new()
	unit.members_alive = 12
	unit.original_size = 12
	unit.stress_system = StressController.new()
	unit.add_child(unit.stress_system)
	unit.tactical_state = SquadTacticalState.new()
	return unit


func _presence(mode: int) -> float:
	var link: CommandConnectivity = CommandConnectivity.new()
	link.command_unit_state = STATES.MoraleState.NORMAL
	if mode == 1:
		link.radio_link_to_leader = true
	if mode >= 2:
		link.los_to_leader = true
		link.voice_range_to_leader = true
	var value: float = link.leader_presence_strength
	link.free()
	return value


func _support(unit: Unit, mode: int) -> void:
	var grade: RankGrades.Grade = RankGrades.Grade.SQUAD_LEADER
	if mode == 2:
		grade = RankGrades.Grade.PLATOON_LEADER
	if mode == 3:
		grade = RankGrades.Grade.COMPANY_LEADER
	var parameters: Dictionary = RankGrades.GRADE_PARAMS[grade]
	unit.stress_system.add_leadership_source(1, float(parameters.lead), float(parameters.rally), float(parameters.coh_mult))
	unit.stress_system.leader_presence_strength = _presence(mode)


func _test_budget_matrix() -> void:
	for state: STATES.MoraleState in [STATES.MoraleState.NORMAL, STATES.MoraleState.CAUTIOUS, STATES.MoraleState.PINNED, STATES.MoraleState.PANIC]:
		for base_cohesion: float in [0.25, 0.5, 1.0]:
			for rounds: float in [0.0, 10.0]:
				for losses: int in [0, 2]:
					var unit: UnitProbe = _unit()
					var stress: StressController = unit.stress_system
					stress.state = state
					stress.cohesion = base_cohesion
					stress.on_casualty_event(losses)
					stress.mark_under_fire(rounds)
					var baseline: float = stress.get_recovery_capacity()
					var previous: float = 0.0
					for mode: int in range(4):
						_support(unit, mode)
						var capacity: float = stress.get_recovery_capacity()
						_check(capacity >= previous and capacity <= baseline * 1.5 + 0.00001, "Real radio/nearby/rank support is ordered and stays within the shared recovery budget")
						previous = capacity
					# Deliberately extreme configured bonuses must not bypass budgets.
					stress.leader_recovery_bonus = 100.0
					stress.add_leadership_source(2, 1.0, 1.0, 10.0)
					stress.add_leadership_source(3, 1.0, 1.0, 10.0)
					var supported: float = stress.get_recovery_capacity()
					_check(supported <= baseline * 1.5 + 0.00001, "Aura cohesion and command presence cannot compound beyond 50 percent recovery")
					stress.remove_leadership_source(3)
					_check(is_equal_approx(stress.get_recovery_capacity(), supported), "Overlapping HQ auras do not compound recovery")
					var rally: float = stress._apply_recovery_bias(0.1)
					var baseline_rally: float = 0.1 * stress.recovery_bias * stress._situational_recovery_multiplier(false)
					_check(rally <= baseline_rally * 1.5 + 0.00001, "A strong aura cannot bypass situational rally limits at poor cohesion")
					unit.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
					stress.hq_recovery_multiplier = 100.0
					stress.hq_panic_recovery_floor = 100.0
					stress.hq_rally_multiplier = 100.0
					_check(stress.get_recovery_capacity() <= supported * 1.5 + 0.00001, "HQ personal recovery and panic floor cannot exceed the separate 50 percent cap")
					_check(stress._apply_recovery_bias(0.1) <= rally * 1.5 + 0.00001, "HQ personal rally remains bounded with extreme configured values")
					unit.free()


func _test_support_loss() -> void:
	var unit: UnitProbe = _unit()
	_support(unit, 0)
	var isolated: float = unit.stress_system.get_recovery_capacity()
	unit.stress_system.leader_presence_strength = _presence(1)
	_check(unit.stress_system.get_recovery_capacity() > isolated, "Radio reassurance improves recovery without requiring a nearby aura")
	var link: CommandConnectivity = CommandConnectivity.new()
	link.radio_link_to_leader = true
	link.command_unit_state = STATES.MoraleState.PANIC
	unit.stress_system.leader_presence_strength = link.leader_presence_strength
	_check(is_equal_approx(unit.stress_system.get_recovery_capacity(), isolated), "A panicked remote commander supplies no command recovery; embedded leadership remains")
	link.free()
	unit.free()


func _test_panic_rally_gate() -> void:
	var unit: UnitProbe = _unit()
	var stress: StressController = unit.stress_system
	stress.stress_fast = 90.0
	stress.stress_slow = 90.0
	stress._update_effective_stress()
	stress._set_state(STATES.MoraleState.PANIC)
	stress._since_change = 999.0
	stress.L_PANIC_TO_CAUTIOUS = 1000000.0
	stress.mark_under_fire(8.0)
	stress._maybe_transition(0.1)
	_check(stress.state == STATES.MoraleState.PANIC, "High-stress panic cannot rally through sustained incoming fire")
	stress._advance_fire_pressure(stress.under_fire_window_s)
	stress._advance_fire_pressure(stress.unpin_no_fire_delay_s - 0.1)
	stress._maybe_transition(0.1)
	_check(stress.state == STATES.MoraleState.PANIC, "A panicked squad cannot skip the quiet recovery interval")
	stress.mark_under_fire(1.0)
	stress._maybe_transition(0.1)
	_check(stress.state == STATES.MoraleState.PANIC and stress._time_without_fire_s == 0.0, "New fire interrupts a panicked squad's developing recovery")
	stress._advance_fire_pressure(stress.under_fire_window_s + stress.unpin_no_fire_delay_s)
	stress._maybe_transition(0.1)
	_check(stress.state == STATES.MoraleState.CAUTIOUS and stress.S_eff == 90.0, "Quiet high-stress panic can rally before passive contacts lock stress above the hysteresis threshold")
	unit.free()


func _test_recovery_profiles() -> void:
	for state: STATES.MoraleState in [STATES.MoraleState.PINNED, STATES.MoraleState.PANIC]:
		for losses: int in [0, 2]:
			var previous: float = INF
			var isolated: float = 0.0
			for mode: int in range(4):
				var total: float = 0.0
				for random_seed: int in range(4):
					total += _recover(state, losses, mode, random_seed)
				var mean: float = total / 4.0
				if mode == 0:
					isolated = mean
				_check(mean <= previous + 2.0 and mean >= isolated * 0.5, "Command improves average recovery without an excessive recovery-time advantage")
				previous = mean
				print("Recovery profile: morale=", state, "; losses=", losses, "; support=", mode, "; mean normal_s=", mean)


func _recover(state: STATES.MoraleState, losses: int, mode: int, random_seed: int) -> float:
	var unit: UnitProbe = _unit()
	_support(unit, mode)
	var stress: StressController = unit.stress_system
	if losses > 0:
		unit.members_alive -= losses
		stress.cohesion = 0.8
	stress.on_casualty_event(losses)
	stress.stress_fast = 90.0
	stress.stress_slow = 90.0
	stress._update_effective_stress()
	stress._set_state(state)
	stress.mark_under_fire(8.0)
	var enemies: Array[Unit] = []
	for index: int in range(6):
		var enemy: Unit = Unit.new()
		enemy.team = Globals.get_enemy_team(unit.team)
		enemy.position = Vector2.from_angle(deg_to_rad(float(index) * 8.0 - 20.0)) * 200.0
		enemies.append(enemy)
	Globals.unit_visible_enemies[unit] = enemies
	seed(random_seed)
	var recovery: float = -1.0
	for tick: int in range(960):
		unit.simulation_time = float(tick) * 0.25
		unit.tactical_state.update_attention(unit)
		stress._process(0.25)
		if stress.state == STATES.MoraleState.NORMAL:
			recovery = unit.simulation_time + 0.25
			break
	_check(recovery > 0.0 and recovery <= 210.0, "Isolated and supported squads recover from shock with visible contacts, including two losses")
	_check(stress.S_eff >= 0.0 and stress.S_eff < 21.0, "Completed recovery reaches the ordinary normal-morale threshold")
	Globals.unit_visible_enemies.erase(unit)
	unit.free()
	for enemy: Unit in enemies:
		enemy.free()
	return recovery


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
