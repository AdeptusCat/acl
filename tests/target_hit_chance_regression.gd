extends Node

# Inspect the probabilities used by the real impact resolver without loading a map.
class TargetProbe extends Unit:
	func set_cover(_value: int) -> void:
		pass

	func receive_fire(_value: float) -> void:
		pass

	func _on_incoming_fire_effect(_casualties: int, _fast: float, _slow: float, _source: Node) -> void:
		pass


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
	fire.free()
	shooter.free()
	for target: Unit in targets:
		target.free()
	print("Target hit chance checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


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
