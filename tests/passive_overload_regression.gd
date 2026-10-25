extends Node

class UnitProbe extends Unit:
	var simulation_time: float = 0.0

	func _make_squad() -> void:
		pass

	func _now() -> float:
		return simulation_time


var checks: int = 0
var failures: int = 0
var target: UnitProbe
var enemies: Array[Unit] = []


func _ready() -> void:
	var previous_no_damage: bool = Debug.no_damage
	Debug.no_damage = false
	_test_contact_geometry()
	_test_incoming_bearings()
	_test_passive_memory()
	for support: float in [0.0, 1.0]:
		for random_seed: int in range(4):
			_test_sustained_contacts(random_seed, support, false)
			_test_sustained_contacts(random_seed, support, true)
	Debug.no_damage = previous_no_damage
	print("Passive overload checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _fixture(firing: float) -> void:
	target = UnitProbe.new()
	target.members_alive = 12
	target.original_size = 12
	target.tactical_state = SquadTacticalState.new()
	target.stress_system = StressController.new()
	target.add_child(target.stress_system)
	target.combat_stats = UnitCombatStats.new()
	target.add_child(target.combat_stats)
	for index: int in range(6):
		var enemy: Unit = Unit.new()
		enemy.team = Globals.get_enemy_team(target.team)
		enemy.squad_fire = SquadFireController.new()
		enemy.add_child(enemy.squad_fire)
		enemy.squad_fire.fire_recent = firing
		enemies.append(enemy)
	_layout(0.0, false)
	Globals.unit_visible_enemies[target] = enemies.duplicate()


func _layout(rotation: float, opposed: bool) -> void:
	for index: int in range(enemies.size()):
		var angle: float = deg_to_rad(float(index) * 8.0 - 20.0) + rotation
		if opposed and index >= 3:
			angle += PI
		enemies[index].position = Vector2.from_angle(angle) * 200.0


func _cleanup() -> void:
	Globals.unit_visible_enemies.erase(target)
	Globals.unit_enemy_tracks.erase(target)
	target.free()
	for enemy: Unit in enemies:
		enemy.free()
	enemies.clear()


func _test_contact_geometry() -> void:
	_fixture(0.0)
	var attention: SquadTacticalState = target.tactical_state
	attention.update_attention(target)
	_check(attention.has_contact and attention.focus_strength == 1.0 and attention.total_directional_demand > attention.attention_capacity, "Passive contacts retain full observation information without charging their raw demand as overload")
	_check(attention.attention_stress_rate == 0.0, "Six passive frontal contacts do not overload an intact isolated squad")
	target.stress_system.stress_fast = 100.0
	target.stress_system.stress_slow = 100.0
	target.stress_system._update_effective_stress()
	target.stress_system._set_state(STATES.MoraleState.PINNED)
	attention.update_attention(target)
	_check(attention.attention_stress_rate == 0.0, "Passive frontal contacts do not maintain overload in an intact squad already pinned at maximum stress")
	target.stress_system.stress_fast = 0.0
	target.stress_system.stress_slow = 0.0
	target.stress_system._update_effective_stress()
	target.stress_system._set_state(STATES.MoraleState.NORMAL)
	for enemy: Unit in enemies:
		enemy.squad_fire.fire_recent = 1.0
	attention.update_attention(target)
	var clustered: float = attention.required_attention
	_check(attention.attention_stress_rate == 0.0, "Six clustered frontal firing contacts share observation effort within intact capacity")
	for rotation: float in [PI / 8.0, 1.23, PI, TAU - 0.01]:
		_layout(rotation, false)
		attention.update_attention(target)
		_check(is_equal_approx(attention.required_attention, clustered), "Rotating a contact cluster across sector boundaries preserves overload demand")
	var reversed_contacts: Array = enemies.duplicate()
	reversed_contacts.reverse()
	Globals.unit_visible_enemies[target] = reversed_contacts
	attention.update_attention(target)
	_check(is_equal_approx(attention.required_attention, clustered), "Contact enumeration order does not change shared attention effort")
	_layout(0.0, true)
	attention.update_attention(target)
	_check(attention.required_attention > clustered and attention.attention_stress_rate > 0.0 and attention.flanked, "Opposing active groups retain stronger overload and flanking than the same frontal contact count")
	var opposing: float = attention.required_attention
	_layout(PI / 8.0, true)
	attention.update_attention(target)
	_check(is_equal_approx(attention.required_attention, opposing), "Separated firing directions retain their demand when rotated")
	print("Attention geometry: frontal required=", clustered, "; opposing required=", opposing, "; opposing overload/s=", attention.attention_stress_rate)
	_cleanup()


func _test_incoming_bearings() -> void:
	_fixture(1.0)
	var attention: SquadTacticalState = target.tactical_state
	attention.register_incoming_fire(Vector2.RIGHT, 0.0)
	attention.update_attention(target)
	_check(attention.attention_stress_rate == 0.0, "A known frontal shooter and its incoming bearing do not become independent full overload threats")
	Globals.unit_visible_enemies.erase(target)
	attention = SquadTacticalState.new()
	target.tactical_state = attention
	attention.register_incoming_fire(Vector2.RIGHT, 0.0)
	attention.register_incoming_fire(Vector2.LEFT, 0.0)
	attention.update_attention(target)
	_check(attention.attention_stress_rate > 0.0 and attention.multi_direction_pressure > 0.0, "Anonymous opposing incoming fire still generates overload and crossfire")
	target.simulation_time = 5.0
	attention.update_attention(target)
	_check(attention.attention_stress_rate == 0.0 and attention.required_attention == 0.0, "Expired incoming fire leaves no stale overload demand")
	_cleanup()


func _test_passive_memory() -> void:
	_fixture(0.0)
	Globals.unit_visible_enemies.erase(target)
	var tracks: Dictionary = {}
	for enemy: Unit in enemies:
		var track: EnemyTrack = EnemyTrack.new(target, enemy)
		track.record_detection()
		tracks[enemy] = track
	Globals.unit_enemy_tracks[target as Unit] = tracks
	var attention: SquadTacticalState = target.tactical_state
	attention.update_attention(target)
	var remembered: float = attention.required_attention
	var focus: Vector2 = attention.focus_direction
	for enemy: Unit in enemies:
		enemy.position = Vector2.LEFT * 200.0
	attention.update_attention(target)
	_check(is_equal_approx(attention.required_attention, remembered) and attention.focus_direction.is_equal_approx(focus), "Hidden movement cannot update remembered overload or focus")
	for track: EnemyTrack in tracks.values():
		track.update_not_seen(15.0)
	attention.update_attention(target)
	_check(attention.required_attention < remembered and attention.attention_stress_rate == 0.0, "Remembered passive demand fades without sustained overload")
	for track: EnemyTrack in tracks.values():
		track.update_not_seen(20.0)
	attention.update_attention(target)
	_check(attention.required_attention == 0.0, "Expired memory removes all overload contributions")
	_cleanup()


func _test_sustained_contacts(random_seed: int, support: float, initially_pinned: bool) -> void:
	_fixture(0.0)
	seed(random_seed)
	target.stress_system.leader_presence_strength = support
	if initially_pinned:
		target.stress_system.stress_fast = 100.0
		target.stress_system.stress_slow = 100.0
		target.stress_system._update_effective_stress()
		target.stress_system._set_state(STATES.MoraleState.PINNED)
	var peak: float = 0.0
	var unpinned_at: float = -1.0
	for step: int in range(720):
		target.simulation_time = float(step) * 0.25
		target.tactical_state.update_attention(target)
		target.stress_system._process(0.25)
		peak = maxf(peak, target.stress_system.S_eff)
		if unpinned_at < 0.0 and target.stress_system.state == STATES.MoraleState.NORMAL:
			unpinned_at = target.simulation_time + 0.25
	_check(target.stress_system.S_eff < 21.0 and target.stress_system.state == STATES.MoraleState.NORMAL, "Six contacts remain visible for 180 seconds without a permanent pin loop; seed %d, support %.1f, initially pinned %s" % [random_seed, support, initially_pinned])
	if not initially_pinned:
		_check(peak < 24.5, "Passive observation cannot push a fresh intact squad above caution")
	else:
		_check(unpinned_at > 0.0 and unpinned_at < 150.0, "Maximum-stress intact squad returns to normal with contacts still visible")
	if random_seed == 0:
		print("Passive sustained: support=", support, "; initially pinned=", initially_pinned, "; peak=", peak, "; normal at=", unpinned_at, "; end stress=", target.stress_system.S_eff)
	_cleanup()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
