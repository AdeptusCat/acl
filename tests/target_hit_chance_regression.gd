extends Node

# Inspect the probabilities used by the real impact resolver without loading a map.
class TargetProbe extends Unit:
	var casualties_received: int = 0
	var maximum_casualties_received: int = 0

	func set_cover(_value: int) -> void:
		pass

	func receive_fire(_value: float) -> void:
		pass

	func _on_incoming_fire_effect(casualties: int, _fast: float, _slow: float, _source: Node) -> void:
		casualties_received += casualties
		maximum_casualties_received = maxi(maximum_casualties_received, casualties)


class FireProbe extends SquadFireController:
	var observed_chances: Array[float] = []

	func _get_mean_change_to_hit(chances: Array, count: int) -> float:
		observed_chances.assign(chances)
		return super._get_mean_change_to_hit(chances, count)


const TARGET_ORDERS: Array[Array] = [
	[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0],
	[1, 3, 0], [2, 4, 0],
]

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var shooter: TargetProbe = _target(STATES.MoraleState.NORMAL)
	var targets: Array[Unit] = [
		_target(STATES.MoraleState.NORMAL),
		_target(STATES.MoraleState.PANIC),
		_target(STATES.MoraleState.PINNED),
		_target(STATES.MoraleState.PANIC),
		_target(STATES.MoraleState.PINNED),
	]
	var fire: FireProbe = FireProbe.new()
	fire.unit = shooter
	var weapon: WeaponSpec = WeaponSpec.new()
	weapon.range_hexes = 12
	# At six hexes and two cover points, base accuracy is multiplied by 0.5 * 0.4.
	for base_chance: float in [0.1, 0.5, 0.000005]:
		fire.base_accuracy = base_chance * 5.0
		var expected: Array[float] = [
			clampf(base_chance, 0.00001, 0.95),
			clampf(base_chance * 4.0, 0.00001, 0.95),
			clampf(base_chance * 0.2, 0.00001, 0.95),
			clampf(base_chance * 4.0, 0.00001, 0.95),
			clampf(base_chance * 0.2, 0.00001, 0.95),
		]
		for order: Array in TARGET_ORDERS:
			var batch: Array[Unit] = []
			for index: int in order:
				batch.append(targets[index])
			fire.observed_chances.clear()
			# Zero rounds still exercises probability preparation without random casualties.
			fire.fire_at(0, weapon, false, Vector2i.ZERO, 6, 2, batch)
			_check(fire.observed_chances.size() == order.size(), "Every target has an independent hit probability")
			for position: int in range(fire.observed_chances.size()):
				var index: int = order[position]
				_check(absf(fire.observed_chances[position] - expected[index]) < 0.000000001,
					"Target %d retains probability %.8f in order %s at base %.8f" % [index, expected[index], order, base_chance])
			await get_tree().process_frame
	await _check_casualty_scaling(fire, targets[0] as TargetProbe, weapon)
	fire.free()
	shooter.free()
	for target: Unit in targets:
		target.free()
	print("Target hit chance checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _check_casualty_scaling(fire: FireProbe, target: TargetProbe, weapon: WeaponSpec) -> void:
	# Check the production resolver's distribution across volley sizes and modifiers.
	# Large rosters avoid clipping the distribution at the survivor cap.
	var trials: int = 2000
	var batch: Array[Unit] = [target]
	target.members_alive = 100
	fire.base_accuracy = 100.0
	fire.casualty_scale = 1.0
	for mode: int in range(4):
		var cover: int = 0
		var distance: int = 0
		var grenade: bool = false
		var disable_probability: float = 0.18
		weapon.ammo_type = WeaponSpec.AmmoType.BULLET
		if mode == 1:
			cover = 2
			distance = 6
			disable_probability = 0.024
		elif mode == 2:
			weapon.ammo_type = WeaponSpec.AmmoType.HE
			disable_probability = 0.75
		elif mode == 3:
			grenade = true
			cover = 1
			disable_probability = 0.25
		weapon.he_burst_radius = 1.0
		for rounds: int in [0, 1, 10, 30]:
			if mode >= 2 and rounds != 1:
				continue
			# Explosives generate hits from burst radius rather than round count.
			var hit_attempts: int = rounds
			if mode >= 2:
				hit_attempts = 1
			target.casualties_received = 0
			seed(7031 + mode * 100 + rounds)
			for trial: int in range(trials):
				fire.fire_at(rounds, weapon, grenade, Vector2i.ZERO, distance, cover, batch)
			await get_tree().process_frame
			var probability: float = 0.95 * disable_probability
			var attempts: int = trials * hit_attempts
			var expected: float = float(attempts) * probability
			var tolerance: float = 6.0 * sqrt(float(attempts) * probability * (1.0 - probability))
			_check(absf(float(target.casualties_received) - expected) <= tolerance,
				"Independent casualties for mode %d, %d rounds: observed %d, expected %.2f +/- %.2f" % [mode, rounds, target.casualties_received, expected, tolerance])
	# A near-certain volley must still respect the recipient's living roster.
	target.members_alive = 3
	target.maximum_casualties_received = 0
	weapon.ammo_type = WeaponSpec.AmmoType.BULLET
	fire.casualty_scale = 10.0
	for trial: int in range(20):
		fire.fire_at(30, weapon, false, Vector2i.ZERO, 0, 0, batch)
	await get_tree().process_frame
	_check(target.maximum_casualties_received == 3, "Casualties remain capped at living members")


func _target(state: STATES.MoraleState) -> TargetProbe:
	var target: TargetProbe = TargetProbe.new()
	target.members_alive = 10
	target.stress_system = StressController.new()
	target.stress_system.state = state
	target.add_child(target.stress_system)
	return target


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
