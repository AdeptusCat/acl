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
	var no_damage: bool = Debug.no_damage
	Debug.no_damage = false
	_test_capacity_and_limits()
	_test_live_attention()
	Debug.no_damage = no_damage
	print("Stress resilience checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _unit() -> UnitProbe:
	var unit: UnitProbe = UnitProbe.new()
	unit.squad_type = Globals.SquadType.Rifle
	unit.members_alive = 10
	unit.original_size = 10
	unit.stress_system = StressController.new()
	unit.add_child(unit.stress_system)
	unit.tactical_state = SquadTacticalState.new()
	return unit


func _support(unit: Unit, grade: RankGrades.Grade) -> void:
	var parameters: Dictionary = RankGrades.GRADE_PARAMS[grade]
	unit.stress_system.add_leadership_source(1, float(parameters.lead), float(parameters.rally), float(parameters.coh_mult))
	if grade >= RankGrades.Grade.PLATOON_LEADER:
		unit.stress_system.leader_presence_strength = 1.0


func _test_capacity_and_limits() -> void:
	var unit: Unit = _unit()
	var stress: StressController = unit.stress_system
	for state: STATES.MoraleState in [STATES.MoraleState.NORMAL, STATES.MoraleState.CAUTIOUS, STATES.MoraleState.PINNED, STATES.MoraleState.PANIC]:
		stress.state = state
		stress.leader_presence_strength = 0.0
		var alone: float = stress.get_recovery_capacity()
		if state == STATES.MoraleState.NORMAL:
			_check(is_equal_approx(alone, 1.5), "Unsupported normal squads recover 1.5 stress per second")
		if state == STATES.MoraleState.PINNED:
			_check(alone >= 0.8, "Unsupported pinned squads retain useful inherent recovery")
		if state == STATES.MoraleState.PANIC:
			_check(alone >= 0.4, "Unsupported panicked squads can recover without mandatory HQ assistance")
		stress.leader_presence_strength = 1.0
		_check(stress.get_recovery_capacity() > alone and stress.get_recovery_capacity() <= alone * 1.5 + 0.00001, "Command recovery is useful and bounded in morale state %d" % state)
	stress.state = STATES.MoraleState.NORMAL
	stress.stress_fast = 0.0
	stress.stress_slow = 0.0
	stress.apply_stress(10.0, 10.0)
	_check(is_equal_approx(stress.S_eff, 8.5), "Full command presence provides 15 percent gain protection even before an aura")
	stress.add_leadership_source(1, 1.0, 1.0, 1.05)
	stress.add_leadership_source(2, 1.0, 1.0, 1.05)
	stress.stress_fast = 0.0
	stress.stress_slow = 0.0
	stress.apply_stress(10.0, 10.0)
	_check(is_equal_approx(stress.S_eff, 7.5), "Overlapping powerful leaders cannot exceed the 25 percent incoming protection cap")
	var capacity: float = stress.get_recovery_capacity()
	stress.remove_leadership_source(2)
	_check(is_equal_approx(stress.get_recovery_capacity(), capacity), "Overlapping auras do not compound recovery")
	stress.mark_under_fire(100.0)
	_check(stress.get_recovery_capacity() < capacity, "HQ recovery remains vulnerable to heavy fire")
	unit.free()


func _test_live_attention() -> void:
	var isolated_total: float = 0.0
	var supported_total: float = 0.0
	var isolated_recovery: float = 0.0
	var supported_recovery: float = 0.0
	for random_seed: int in range(8):
		var isolated: Vector3 = _simulate(random_seed, RankGrades.Grade.SQUAD_LEADER, 2, false)
		var supported: Vector3 = _simulate(random_seed, RankGrades.Grade.PLATOON_LEADER, 2, false)
		isolated_total += isolated.x
		supported_total += supported.x
		isolated_recovery += isolated.y
		supported_recovery += supported.y
		_check(supported.x < isolated.x, "HQ reduces live stress with directional attention and morale enabled, seed %d" % random_seed)
		_check(isolated.y >= 0.0, "An isolated squad recovers below caution within 90 seconds after threats stop, seed %d" % random_seed)
		_check(supported.y >= 0.0 and supported.y <= isolated.y, "HQ shortens recovery after directional pressure stops, seed %d" % random_seed)
	var manageable: Vector3 = _simulate(1234, RankGrades.Grade.SQUAD_LEADER, 1, false)
	_check(manageable.x < 24.5 and manageable.z == 0.0, "One frontal threat and intermittent rifle pressure do not pin an isolated intact squad")
	var overwhelming: Vector3 = _simulate(1234, RankGrades.Grade.COMPANY_LEADER, 3, true)
	_check(overwhelming.x > 65.0 and overwhelming.z > 0.0, "Concentrated multidirectional fire still overwhelms company-supported squads")
	print("Live attention balance, 8 seeds, stress at 30s: isolated=", isolated_total / 8.0, "; platoon HQ=", supported_total / 8.0)
	print("Mean seconds to recover below caution: isolated=", isolated_recovery / 8.0, "; platoon HQ=", supported_recovery / 8.0)


# Returns stress after 30 seconds, recovery time after threats stop, time pinned.
# Real contacts, incoming bearings, attention updates and stochastic morale stay active.
func _simulate(random_seed: int, grade: RankGrades.Grade, directions: int, heavy: bool) -> Vector3:
	var unit: UnitProbe = _unit()
	_support(unit, grade)
	var fire: SquadFireController = SquadFireController.new()
	var enemies: Array[Unit] = []
	for index: int in range(directions):
		var enemy: UnitProbe = _unit()
		enemy.team = Globals.get_enemy_team(unit.team)
		enemy.position = Vector2.RIGHT.rotated(float(index) * TAU / float(directions)) * 100.0
		enemies.append(enemy)
	Globals.unit_visible_enemies[unit] = enemies
	var pinned_time: float = 0.0
	var interval: int = 8
	if heavy:
		interval = 2
	seed(random_seed)
	for tick: int in range(120):
		unit.simulation_time = float(tick) * 0.25
		unit.tactical_state.update_attention(unit)
		if tick % interval == 0:
			var bearing: Vector2 = enemies[(tick / interval) % directions].position
			var effects: Vector2 = unit.tactical_state.register_incoming_fire(bearing, unit.simulation_time)
			var suppression: StressController.StressGain = StressController.StressGain.new(2.0, 1.0)
			var rounds: float = 1.0
			if heavy:
				suppression = StressController.StressGain.new(12.0, 8.0)
				rounds = 8.0
			var gain: StressController.StressGain = StressController.calculate_incoming_fire_stress(fire, suppression, StressController.StressGain.new(0.0, 0.0), effects)
			unit.stress_system.mark_under_fire(rounds)
			unit.stress_system.apply_stress(gain.fast, gain.slow)
		unit.stress_system._process(0.25)
		if unit.stress_system.state == STATES.MoraleState.PINNED:
			pinned_time += 0.25
	var end: float = unit.stress_system.S_eff
	Globals.unit_visible_enemies.erase(unit)
	var recovery_time: float = -1.0
	if end < 21.0:
		recovery_time = 0.0
	for tick: int in range(360):
		unit.simulation_time = 30.0 + float(tick) * 0.25
		unit.tactical_state.update_attention(unit)
		unit.stress_system._process(0.25)
		if recovery_time < 0.0 and unit.stress_system.S_eff < 21.0:
			recovery_time = float(tick + 1) * 0.25
	unit.free()
	for enemy: Unit in enemies:
		enemy.free()
	fire.free()
	return Vector3(end, recovery_time, pinned_time)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
