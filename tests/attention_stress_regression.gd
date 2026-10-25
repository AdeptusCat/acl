extends Node

class AttentionUnitProbe extends Unit:
	func _check_contacts() -> void:
		pass


class TargetProbe extends Unit:
	var received_fast: float = 0.0
	var received_slow: float = 0.0
	var received_casualties: int = 0

	func set_cover(_value: int) -> void:
		pass

	func receive_fire(_value: float) -> void:
		pass

	func _on_incoming_fire_effect(casualties: int, fast: float, slow: float, _source: Node) -> void:
		received_fast = fast
		received_slow = slow
		received_casualties = casualties
		stress_system.apply_stress(fast, slow)


var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_surprise()
	_test_pressure()
	_test_incoming_attention()
	_test_overload_and_conditions()
	_test_switching()
	_test_final_calculation()
	await _test_impacts()
	print("Attention stress checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _focused() -> SquadTacticalState:
	var state: SquadTacticalState = SquadTacticalState.new()
	state.focus_direction = Vector2.RIGHT
	state.focus_strength = 1.0
	state.attention_width = PI / 2.0
	state.attention_quality = 1.0
	return state


func _test_surprise() -> void:
	var front: Vector2 = _focused().register_incoming_fire(Vector2.RIGHT, 0.0)
	var rear: Vector2 = _focused().register_incoming_fire(Vector2.LEFT, 0.0)
	var flank: Vector2 = _focused().register_incoming_fire(Vector2.DOWN, 0.0)
	_check(front.x == 0.0 and rear.x > front.x and flank.x > front.x, "Fire outside current attention produces more surprise than expected frontal fire")
	var state: SquadTacticalState = _focused()
	state.register_incoming_fire(Vector2.LEFT, 0.0)
	_check(state.register_incoming_fire(Vector2.LEFT, 0.0).x == 0.0, "Repeated bursts on a known bearing do not replay full surprise")
	_check(state.register_incoming_fire(Vector2.LEFT, 5.0).x > 0.0, "An expired incoming-fire bearing can surprise the squad again")
	state = SquadTacticalState.new()
	_check(state.register_incoming_fire(Vector2.LEFT, 0.0).x == 0.0, "Neutral all-around coverage has no directional blind side")
	state = _focused()
	state.directional_demand.resize(SquadTacticalState.DEMAND_SECTOR_COUNT)
	state.directional_demand.fill(0.0)
	state.directional_demand[4] = 1.0
	state.total_directional_demand = 1.0
	_check(state.register_incoming_fire(Vector2.LEFT, 0.0).x == 0.0, "A known secondary contact reduces surprise even outside the main focus")
	state.focus_direction = Vector2.ZERO
	state.focus_strength = 0.0
	state.directional_demand[0] = 1.0
	state.total_directional_demand = 2.0
	_check(state.register_incoming_fire(Vector2.UP, 0.0).x > 0.0, "Opposing demand does not falsely imply attention covers the unobserved flank")
	_check(_focused().register_incoming_fire(Vector2.ZERO, 0.0) == Vector2.ZERO, "Same-position attacks do not invent a bearing")


func _test_pressure() -> void:
	var state: SquadTacticalState = _focused()
	for burst: int in range(20):
		state.register_incoming_fire(Vector2.RIGHT, 0.0)
	_check(state.multi_direction_pressure == 0.0, "Additional volume from one direction is not crossfire")
	var right_angle: float = state.register_incoming_fire(Vector2.DOWN, 0.0).y
	_check(right_angle > 0.0, "Separated attack directions create pressure")
	state = _focused()
	state.register_incoming_fire(Vector2.RIGHT, 0.0)
	var opposing: float = state.register_incoming_fire(Vector2.LEFT, 0.0).y
	_check(opposing > right_angle and opposing <= 1.0, "Opposing fire creates stronger bounded pressure than perpendicular fire")
	state.update_fire_pressure(3.0)
	_check(state.multi_direction_pressure > 0.0 and state.multi_direction_pressure < opposing, "Crossfire pressure fades while incoming fire stops")
	state.update_fire_pressure(5.0)
	_check(state.multi_direction_pressure == 0.0, "Expired attack bearings clear pressure")
	state = _focused()
	state.register_incoming_fire(Vector2.from_angle(deg_to_rad(22.4)), 0.0)
	var near_aligned: float = state.register_incoming_fire(Vector2.from_angle(deg_to_rad(22.6)), 0.0).y
	_check(near_aligned < right_angle * 0.01, "A sector boundary cannot turn nearly aligned fire into crossfire")
	state = _focused()
	state.attention_quality = 0.4
	state.register_incoming_fire(Vector2.RIGHT, 0.0)
	_check(state.register_incoming_fire(Vector2.DOWN, 0.0).y >= right_angle, "Reduced squad capacity makes separated bearings harder to manage")
	for index: int in range(SquadTacticalState.DEMAND_SECTOR_COUNT):
		state.register_incoming_fire(Vector2.from_angle(float(index) * TAU / 8.0), 0.0)
	_check(state.multi_direction_pressure <= 1.0, "Surrounding fire cannot grow pressure without bound")


func _test_incoming_attention() -> void:
	var unit: Unit = Unit.new()
	unit.tactical_state = _focused()
	unit.tactical_state.register_incoming_fire(Vector2.LEFT, unit._now())
	unit.tactical_state.update_attention(unit)
	_check(unit.tactical_state.focus_direction.is_equal_approx(Vector2.LEFT), "Incoming fire pulls attention toward its anonymous bearing")
	_check(Globals.unit_visible_enemies.get(unit, []).is_empty() and Globals.unit_enemy_tracks.get(unit, {}).is_empty(), "Incoming direction does not identify a shooter or grant visibility")
	unit.surrendered = true
	unit.tactical_state.update_attention(unit)
	_check(unit.tactical_state.multi_direction_pressure == 0.0 and unit.tactical_state.incoming_fire_demand.count(0.0) == SquadTacticalState.DEMAND_SECTOR_COUNT, "Inactive attention clears recent incoming-fire pressure")
	unit.free()


func _test_overload_and_conditions() -> void:
	var unit: AttentionUnitProbe = AttentionUnitProbe.new()
	unit.tactical_state = SquadTacticalState.new()
	unit.stress_system = StressController.new()
	unit.add_child(unit.stress_system)
	unit.stress_system.refractory_s = 100000.0
	unit.stress_system._since_change = 0.0
	var enemies: Array[Unit] = []
	for index: int in range(3):
		var enemy: Unit = Unit.new()
		enemy.team = Globals.get_enemy_team(unit.team)
		enemy.position = Vector2.RIGHT.rotated(float(index) * TAU / 3.0) * 100.0
		enemies.append(enemy)
	var state: SquadTacticalState = unit.tactical_state
	state.update_attention(unit)
	_check(state.attention_stress_rate == 0.0, "A squad without threats does not generate attention stress")
	Globals.unit_visible_enemies[unit] = [enemies[0]]
	state.update_attention(unit)
	_check(state.attention_deficit == 0.0 and not state.flanked and not state.surrounded, "One manageable threat does not imply overload or flanking")
	enemies[1].position = Vector2.LEFT * 100.0
	Globals.unit_visible_enemies[unit] = [enemies[0], enemies[1]]
	state.update_attention(unit)
	_check(state.flanked and not state.surrounded and state.focus_direction == Vector2.ZERO, "Opposing threats derive flanked without replacing the primary attention data or implying encirclement")
	_check(state.attention_deficit > 0.0 and state.attention_stress_rate > 0.0, "Unmet attention demand generates stress without any incoming volley")
	var no_damage: bool = Debug.no_damage
	Debug.no_damage = false
	unit._process(0.5)
	_check(unit.stress_system.S_eff == 0.0, "The unit attention refresh does not apply a second stress gain")
	unit.stress_system._process(0.5)
	_check(unit.stress_system.S_eff > 0.0, "The stress controller integrates ongoing attention stress before recovery")
	Debug.no_damage = no_damage
	enemies[1].position = Vector2.RIGHT.rotated(TAU / 3.0) * 100.0
	Globals.unit_visible_enemies[unit] = enemies
	state.update_attention(unit)
	_check(state.surrounded and state.flanked, "Three directions enclosing the squad derive a separate surrounded condition")
	unit.stress_system.S_eff = 0.0
	for index: int in range(3):
		enemies[index].position = Vector2.RIGHT.rotated(deg_to_rad(float(index - 1) * 20.0)) * 100.0
	state.update_attention(unit)
	_check(not state.flanked and not state.surrounded and state.attention_stress_rate > 0.0, "Several frontal threats can overload attention without a flank condition")
	var full_squad_rate: float = state.attention_stress_rate
	unit.members_alive = 3
	state.update_attention(unit)
	_check(state.attention_stress_rate > full_squad_rate and state.attention_stress_rate <= SquadTacticalState.MAX_ATTENTION_STRESS_RATE, "Smaller squads have less attention capacity and a bounded overload stress rate")
	Globals.unit_visible_enemies.erase(unit)
	state.update_attention(unit)
	_check(state.attention_stress_rate == 0.0 and not state.flanked and not state.surrounded, "Removing the threat demand clears overload and derived conditions")
	unit.free()
	for enemy: Unit in enemies:
		enemy.free()


func _test_switching() -> void:
	var coarse: SquadTacticalState = _focused()
	var fine: SquadTacticalState = _focused()
	for state: SquadTacticalState in [coarse, fine]:
		state.total_directional_demand = 1.0
		_check(state.advance_attention(0.1) == Vector2.ZERO, "Acquiring an initial focus does not pay a switching cost")
		state.focus_direction = Vector2.LEFT
	var coarse_cost: Vector2 = coarse.advance_attention(1.0)
	var fine_cost: Vector2 = Vector2.ZERO
	for step: int in range(10):
		fine_cost += fine.advance_attention(0.1)
	_check(coarse_cost.is_equal_approx(fine_cost) and coarse_cost.x == 0.0 and coarse_cost.y > 0.0, "Focus switching returns its frame-rate-independent cost separately from overload")
	_check(is_equal_approx(coarse.attention_switch_load, fine.attention_switch_load), "Switch recovery is independent of tick frequency")
	var distracted_detection: float = fine.detection_multiplier(Vector2.LEFT)
	fine.advance_attention(5.0)
	_check(fine.detection_multiplier(Vector2.LEFT) > distracted_detection and fine.switching_stress_rate < 0.01, "A stable focus recovers spotting quality and clears the switching burden")
	var idle: SquadTacticalState = _focused()
	idle.advance_attention(0.1)
	idle.focus_direction = Vector2.LEFT
	_check(idle.advance_attention(0.1) == Vector2.ZERO, "Changing march direction without threat demand does not generate combat stress")
	var unit: Unit = Unit.new()
	unit.tactical_state = SquadTacticalState.new()
	var enemy: Unit = Unit.new()
	enemy.team = Globals.get_enemy_team(unit.team)
	enemy.position = Vector2.RIGHT * 100.0
	Globals.unit_visible_enemies[unit] = [enemy]
	unit.tactical_state.update_attention(unit)
	unit.tactical_state.advance_attention(0.1)
	enemy.position = Vector2.LEFT * 100.0
	for refresh: int in range(20):
		unit.tactical_state.update_attention(unit)
	_check(unit.tactical_state.attention_switch_load == 0.0, "Repeated perception refreshes cannot charge switching cost")
	_check(unit.tactical_state.advance_attention(0.1).y > 0.0, "The simulation tick charges the changed combat focus once")
	unit.surrendered = true
	unit.tactical_state.update_attention(unit)
	_check(unit.tactical_state.attention_switch_load == 0.0 and not unit.tactical_state.flanked and not unit.tactical_state.surrounded, "Inactive squads clear attention burdens and tactical conditions")
	Globals.unit_visible_enemies.erase(unit)
	enemy.free()
	unit.free()


func _test_final_calculation() -> void:
	var fire: SquadFireController = SquadFireController.new()
	fire.stress_surprise_bonus = 0.5
	fire.stress_crossfire_bonus = 0.25
	var gain: StressController.StressGain = StressController.calculate_incoming_fire_stress(fire, StressController.StressGain.new(8.0, 4.0), StressController.StressGain.new(3.0, 2.0), Vector2(1.0, 0.5))
	_check(is_equal_approx(gain.fast, 16.0) and is_equal_approx(gain.slow, 6.5), "Final volley stress adds existing suppression, surprise, crossfire and unamplified casualty shock")
	var capped: StressController.StressGain = StressController.calculate_incoming_fire_stress(fire, StressController.StressGain.new(1000.0, 1000.0), StressController.StressGain.new(1000.0, 1000.0), Vector2.ONE)
	_check(capped.fast == fire.stress_max_per_volley + fire.stress_kill_max_per_volley and capped.slow == capped.fast, "The integrated calculation retains independent suppression and casualty caps")

	var unit: AttentionUnitProbe = AttentionUnitProbe.new()
	var stress: StressController = StressController.new()
	unit.add_child(stress)
	unit.stress_system = stress
	unit.tactical_state = _focused()
	unit.tactical_state.total_directional_demand = 1.0
	unit.tactical_state.advance_attention(0.1)
	unit.tactical_state.focus_direction = Vector2.LEFT
	unit.tactical_state.attention_stress_rate = 2.0
	stress.stress_fast = 20.0
	stress.stress_slow = 40.0
	stress.S_eff = 30.0
	stress.leadership_bonus = 0.4
	stress.incoming_stress_scale = 1.2
	stress.refractory_s = 100000.0
	stress._since_change = 0.0
	var no_damage: bool = Debug.no_damage
	Debug.no_damage = false
	stress.apply_stress(gain.fast, gain.slow)
	_check(is_equal_approx(stress.S_eff, 39.18), "The composed volley receives leadership, incoming scaling and existing-stress resistance once")
	stress._process(0.5)
	# Volley: 11.25 * 1.2 * 0.8 * 0.85 = 9.18 effective gain.
	# Attention: 1 overload + (1 - exp(-0.5)) effective switching, same modifiers.
	var attention_gain: float = (2.0 - exp(-0.5)) * 1.2 * 0.8 * 0.8041
	_check(is_equal_approx(stress.S_eff, 39.18 + attention_gain - 0.75), "All four attention effects enter the existing stress bins with recovery applied once")
	_check(is_equal_approx(stress.incoming_stress_rate, (9.18 + attention_gain) / 0.5) and is_equal_approx(stress.stress_recovery_rate, 1.5), "The stress-rate display accounts for both impact and continuous attention gains")
	_check(is_equal_approx(stress.S_eff - 30.0, stress.net_stress_rate * 0.5), "The complete stress balance explains the final meter change")

	stress.recovery_scale = 0.0
	unit.tactical_state = _focused()
	unit.tactical_state.flanked = true
	unit.tactical_state.surrounded = true
	var before: float = stress.S_eff
	stress._process(0.5)
	_check(stress.S_eff == before, "Derived flanked and surrounded tags do not double-count directional stress")
	unit.tactical_state.attention_stress_rate = 2.0
	unit.tactical_state.attention_switch_load = 1.0
	Debug.no_damage = true
	stress._process(0.5)
	_check(stress.S_eff == before and unit.tactical_state.attention_switch_load < 1.0, "Disabled damage blocks attention gains while switching and detection recover")
	Debug.no_damage = false
	unit.surrendered = true
	stress._process(0.5)
	_check(stress.S_eff == before, "Inactive squads do not accumulate ongoing attention stress")
	unit.surrendered = false
	unit.tactical_state = _focused()
	unit.tactical_state.attention_stress_rate = 4.0
	stress.pin_threshold = stress.S_eff + 0.1
	stress.refractory_s = 0.0
	stress.L_NORMAL_TO_PINNED = 1000.0
	stress.mark_under_fire(1.0)
	stress._process(0.5)
	_check(stress.state == STATES.MoraleState.PINNED, "Morale transitions use the complete attention-adjusted stress in the same tick")
	Debug.no_damage = no_damage
	unit.free()
	fire.free()


func _test_impacts() -> void:
	var shooter: TargetProbe = TargetProbe.new()
	shooter.stress_system = StressController.new()
	var target: TargetProbe = TargetProbe.new()
	target.stress_system = StressController.new()
	var fire: SquadFireController = SquadFireController.new()
	fire.unit = shooter
	fire.base_accuracy = 0.01
	var weapon: WeaponSpec = WeaponSpec.new()
	weapon.range_hexes = 10
	var front: Dictionary = await _impact(fire, target, weapon, Vector2.RIGHT * 100.0, false)
	var rear: Dictionary = await _impact(fire, target, weapon, Vector2.LEFT * 100.0, false)
	_check(float(rear.fast) > float(front.fast) and is_equal_approx(float(rear.slow), float(front.slow)), "Real impacts add surprise to fast shock while retaining the base slow stress")
	_check(rear.casualties == front.casualties and rear.rng_tail == front.rng_tail, "Attention modifiers preserve casualty rolls and random continuation")
	var crossfire: Dictionary = await _impact(fire, target, weapon, Vector2.LEFT * 100.0, true)
	_check(float(crossfire.fast) > float(rear.fast) and float(crossfire.slow) > float(rear.slow), "Real crossfire increases both fast and slow stress")
	_check(float(crossfire.effective_stress) > float(rear.effective_stress), "Contextual modifiers reach the actual stress controller")
	shooter.position = Vector2.RIGHT * 100.0
	var moved_shooter: Dictionary = await _impact(fire, target, weapon, Vector2.LEFT * 100.0, false)
	_check(is_equal_approx(float(moved_shooter.fast), float(rear.fast)), "A captured firing origin survives shooter movement before impact")
	fire.base_accuracy = 0.0
	fire.stress_fast_base = 10000000.0
	var capped: Dictionary = await _impact(fire, target, weapon, Vector2.LEFT * 100.0, true, 200)
	_check(capped.casualties == 0 and float(capped.fast) <= fire.stress_max_per_volley and float(capped.slow) <= fire.stress_max_per_volley, "Surprise and pressure respect the base per-volley stress caps")
	target.stress_system.free()
	target.free()
	shooter.stress_system.free()
	shooter.free()
	fire.free()


func _impact(fire: SquadFireController, target: TargetProbe, weapon: WeaponSpec, shot_origin: Vector2, preceding_fire: bool, rounds: int = 2) -> Dictionary:
	target.tactical_state = _focused()
	target.stress_system.stress_fast = 0.0
	target.stress_system.stress_slow = 0.0
	target.stress_system.S_eff = 0.0
	if preceding_fire:
		target.tactical_state.register_incoming_fire(Vector2.RIGHT, target._now())
	seed(1234)
	fire.fire_at(rounds, weapon, false, target.current_hex, 5, 2, [target], shot_origin)
	var rng_tail: float = randf()
	await get_tree().process_frame
	return {"fast": target.received_fast, "slow": target.received_slow, "casualties": target.received_casualties, "rng_tail": rng_tail, "effective_stress": target.stress_system.S_eff}


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
