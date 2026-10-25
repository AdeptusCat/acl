extends Node

class UnitProbe extends Unit:
	var simulation_time: float = 0.0

	func _make_squad() -> void:
		pass

	func _now() -> float:
		return simulation_time


var checks: int = 0
var failures: int = 0
var maximum_recovery_s: float = 0.0
var target: UnitProbe
var other_squad: Unit
var enemies: Array[Unit] = []


func _ready() -> void:
	var previous_no_damage: bool = Debug.no_damage
	Debug.no_damage = false
	_test_observation()
	for members: int in [5, 7, 12]:
		for morale: int in [STATES.MoraleState.NORMAL, STATES.MoraleState.CAUTIOUS, STATES.MoraleState.PINNED, STATES.MoraleState.PANIC]:
			for random_seed: int in range(4):
				_test_lull(members, morale, random_seed)
	for window: float in [0.5, 2.0, 4.0]:
		for step: float in [0.125, 0.25, 0.5]:
			_test_pressure_expiry(window, step)
	Debug.no_damage = previous_no_damage
	print("Maximum isolated recovery after crossfire, with observation continuing: ", maximum_recovery_s, " seconds")
	print("Threat relevance checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _fixture(members: int) -> void:
	target = UnitProbe.new()
	target.members_alive = members
	target.original_size = members
	if members == 5:
		target.squad_type = Globals.SquadType.MG
	elif members == 7:
		target.squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
	target.tactical_state = SquadTacticalState.new()
	target.stress_system = StressController.new()
	target.add_child(target.stress_system)
	target.combat_stats = UnitCombatStats.new()
	target.add_child(target.combat_stats)
	other_squad = Unit.new()
	for index: int in range(8):
		var enemy: Unit = Unit.new()
		enemy.team = Globals.get_enemy_team(target.team)
		enemy.position = Vector2.from_angle(TAU * float(index) / 8.0) * 200.0
		enemy.squad_fire = SquadFireController.new()
		enemy.add_child(enemy.squad_fire)
		enemy.squad_fire.fire_recent = 1.0
		enemy.squad_fire.target_unit = other_squad
		enemies.append(enemy)
	Globals.unit_visible_enemies[target] = enemies.duplicate()


func _cleanup() -> void:
	Globals.unit_visible_enemies.erase(target)
	Globals.unit_enemy_tracks.erase(target)
	target.free()
	other_squad.free()
	for enemy: Unit in enemies:
		enemy.free()
	enemies.clear()


func _test_observation() -> void:
	_fixture(12)
	Globals.unit_visible_enemies[target] = [enemies[0]]
	target.tactical_state.update_attention(target)
	var passive: float = target.tactical_state.total_directional_demand
	enemies[0].squad_fire.fire_recent = 0.0
	target.tactical_state.update_attention(target)
	_check(target.tactical_state.total_directional_demand < passive, "Visible firing still increases observation urgency")
	enemies[0].squad_fire.fire_recent = 1.0
	target.tactical_state.update_attention(target)
	target.tactical_state.advance_attention(0.25)
	var forward_detection: float = target.tactical_state.detection_multiplier(Vector2.RIGHT)
	var rear_detection: float = target.tactical_state.detection_multiplier(Vector2.LEFT)
	_check(forward_detection > rear_detection, "Observation focus retains directional spotting")
	Globals.unit_visible_enemies[target] = [enemies[4]]
	target.tactical_state.update_attention(target)
	var costs: Vector2 = target.tactical_state.advance_attention(0.25)
	_check(target.tactical_state.attention_switch_load > 0.0 and costs == Vector2.ZERO, "Watching fire elsewhere changes focus without adding stress")
	_check(target.tactical_state.detection_multiplier(Vector2.LEFT) < forward_detection, "Observation switching still disrupts spotting")
	Globals.unit_visible_enemies[target] = enemies.duplicate()
	target.tactical_state.update_attention(target)
	_check(target.tactical_state.surrounded and target.tactical_state.total_directional_demand > target.tactical_state.attention_capacity, "Dispersed observers retain tactical awareness and raw demand")
	_check(target.tactical_state.required_attention == 0.0, "Fire aimed elsewhere creates no suppression demand")
	_cleanup()


func _test_lull(members: int, morale: int, random_seed: int) -> void:
	_fixture(members)
	seed(random_seed)
	var stress: StressController = target.stress_system
	stress.stress_fast = 100.0
	stress.stress_slow = 100.0
	stress._update_effective_stress()
	stress._set_state(morale)
	var monotonic: bool = true
	var crossfire: bool = false
	var recovered_at: float = -1.0
	for tick: int in range(1000):
		target.simulation_time = float(tick) * 0.25
		if tick < 40 and tick % 2 == 0:
			stress.mark_under_fire(8.0)
			stress.apply_stress(12.0, 8.0)
			target.tactical_state.register_incoming_fire(Vector2.RIGHT, target._now())
			target.tactical_state.register_incoming_fire(Vector2.LEFT, target._now())
		# All enemies keep firing at another squad for the entire recovery period.
		# Alternate observed subsets to exercise persistent focus switching too.
		Globals.unit_visible_enemies[target] = enemies.duplicate()
		if tick % 4 == 0:
			Globals.unit_visible_enemies[target] = [enemies[0], enemies[1], enemies[7]]
		elif tick % 4 == 2:
			Globals.unit_visible_enemies[target] = [enemies[3], enemies[4], enemies[5]]
		target.tactical_state.update_attention(target)
		if tick < 40 and target.tactical_state.attention_stress_rate > 0.0 and target.tactical_state.multi_direction_pressure > 0.0:
			crossfire = true
		var before: float = stress.S_eff
		stress._process(0.25)
		if not stress.under_fire and before > 0.001 and stress.S_eff >= before:
			monotonic = false
		if tick >= 48 and recovered_at < 0.0 and stress.state == STATES.MoraleState.NORMAL and stress.S_eff < 1.0:
			recovered_at = target.simulation_time + 0.25 - 10.0
	maximum_recovery_s = maxf(maximum_recovery_s, recovered_at)
	_check(crossfire, "Actual opposing received fire creates suppression: members %d, morale %d, seed %d" % [members, morale, random_seed])
	_check(monotonic, "Every quiet tick reduces stress despite dispersed enemies firing elsewhere: members %d, morale %d, seed %d" % [members, morale, random_seed])
	_check(recovered_at > 0.0 and recovered_at < 180.0, "Intact isolated squads recover without HQ while observation shifts continue: members %d, morale %d, seed %d" % [members, morale, random_seed])
	_check(stress.leader_presence_strength == 0.0 and target.members_alive == members, "Recovery requires neither command presence nor casualties")
	_cleanup()


func _test_pressure_expiry(window: float, step: float) -> void:
	_fixture(12)
	var stress: StressController = target.stress_system
	stress.under_fire_window_s = window
	stress.stress_fast = 60.0
	stress.stress_slow = 60.0
	stress._update_effective_stress()
	stress.mark_under_fire(8.0)
	target.tactical_state.register_incoming_fire(Vector2.RIGHT, 0.0)
	target.tactical_state.register_incoming_fire(Vector2.LEFT, 0.0)
	for tick: int in range(roundi(window / step)):
		target.simulation_time = float(tick) * step
		target.tactical_state.update_attention(target)
		var before_expiry: float = stress.S_eff
		if tick == roundi(window / step) - 1:
			# Simulate an attention refresh lagging behind pressure expiry.
			target.tactical_state.attention_stress_rate = SquadTacticalState.MAX_ATTENTION_STRESS_RATE
			target.tactical_state.attention_switch_load = 1.0
			target.tactical_state.suppression_activity = 1.0
		stress._process(step)
		if tick == roundi(window / step) - 1:
			_check(stress.S_eff < before_expiry, "The exact pressure-expiry tick ignores stale attention costs")
	_check(not stress.under_fire, "Received pressure expires at its configured window %.3f, step %.3f" % [window, step])
	var before: float = stress.S_eff
	# Deliberately retain the previous attention refresh across the expiry tick.
	stress._process(step)
	_check(stress.S_eff < before, "Stale attention cannot add stress after pressure expiry %.3f, step %.3f" % [window, step])
	target.simulation_time = window
	target.tactical_state.update_attention(target)
	_check(target.tactical_state.required_attention == 0.0 and target.tactical_state.suppression_activity == 0.0, "Suppression demand expires independently of visible fire %.3f, step %.3f" % [window, step])
	if window < 4.0:
		_check(target.tactical_state.incoming_fire_demand[0] > 0.0, "Bearing awareness outlives suppression without preventing recovery")
	stress.mark_under_fire(8.0)
	target.tactical_state.register_incoming_fire(Vector2.RIGHT, target._now())
	target.tactical_state.register_incoming_fire(Vector2.LEFT, target._now())
	target.tactical_state.update_attention(target)
	_check(stress.under_fire and target.tactical_state.attention_stress_rate > 0.0, "Renewed received crossfire immediately restores suppression")
	_cleanup()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
