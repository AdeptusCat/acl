class_name UnitCombat
extends Node

var fire_timer: float = 0.0

signal shoot(from_pos, target_pos)


func handle_auto_fire(delta, shooter: Node2D, unit_visible_enemies: Dictionary, current_hex, range, fire_rate, firepower):
	fire_timer -= delta
	if fire_timer > 0:
		return  # Still waiting for next shot

	var visible_enemies: Array = unit_visible_enemies.get(get_parent(), [])
	for enemy in visible_enemies:
		if enemy and enemy.alive:
			var distance = current_hex.distance_to(enemy.current_hex)
			if distance <= range * 2:
				var cover_map = LOSHelper.los_lookup.get(current_hex, null)
				var targetCover = 0
				if cover_map and cover_map.has(enemy.current_hex):
					var data = cover_map[enemy.current_hex]
					targetCover = data["target_cover"]

				enemy.set_cover(targetCover)
				fire_at(shooter, enemy, current_hex, distance, targetCover, firepower, range, unit_visible_enemies, fire_rate)
				fire_timer = fire_rate
				break

func fire_at(shooter: Node2D, target: Node2D, current_hex, distance_in_hexes: int, terrain_defense_bonus: float, firepower : float, range, unit_visible_enemies: Dictionary, fire_rate):

	var actual_firepower = firepower
	if distance_in_hexes > range:
		if distance_in_hexes <= range * 2:
			actual_firepower = firepower / 2
		else:
			return

	var target_hex = target.current_hex
	var batch_targets: Array = []

	var visible_enemies: Array = unit_visible_enemies.get(get_parent(), [])
	for u in visible_enemies:
		if is_instance_valid(u) and u.alive and u.current_hex == target_hex:
			batch_targets.append(u)

	if batch_targets.is_empty():
		return

	for u in batch_targets:
		u.set_cover(terrain_defense_bonus)
		u.receive_fire(actual_firepower, terrain_defense_bonus, unit_visible_enemies)

	fire_burst(shooter, current_hex, batch_targets[0], 8, fire_rate, unit_visible_enemies)


func fire_burst(shooter: Node2D, current_hex, target: Node2D, rounds: int, bullets_per_sec: float, unit_visible_enemies: Dictionary) -> void:
	var interval = 1.0 / bullets_per_sec
	var from_pos = LOSHelper.ground_layer.map_to_local(current_hex)
	
	for i in range(rounds):
		if not is_instance_valid(shooter) or not is_instance_valid(target):
			return
		var visible_enemies: Array = unit_visible_enemies.get(get_parent(), [])
		if not visible_enemies.has(target):
			return
		if shooter.broken or shooter.moving:
			return
		
		shoot.emit(shooter.global_position, target.global_position)

		await get_tree().create_timer(interval).timeout
