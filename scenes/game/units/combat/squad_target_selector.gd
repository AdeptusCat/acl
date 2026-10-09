extends RefCounted
class_name SquadTargetSelector

# Synchronous SquadTargetSelector operations; state and scene identity stay on the caller.


static func handle_auto_fire(controller: SquadFireController, 
	delta: float,
	_shooter: Node2D,
	current_hex: Variant,
	_range: int,
	fire_rate: float,
	_firepower: float
) -> void:
	if controller.unit.ai_support_only:
		return
	controller.fire_timer -= delta
	if controller.fire_timer > 0.0:
		return

	var visible_enemies: Array = Globals.unit_visible_enemies.get(controller.unit, [])
	if visible_enemies.is_empty():
		return

	var best_enemy: Node = null
	var best_score: float = -INF
	var best_cover: int = 0

	for enemy: Unit in visible_enemies:
		if not controller._can_track_target(enemy):
			continue
		
		var units_in_enemy_hex: Array[Unit] = LOSHelper.find_units_at(enemy.current_hex)
		var has_friendly_in_target_hex: bool = false
		for _unit: Unit in units_in_enemy_hex:
			if _unit.team == controller.unit.team and not _unit.surrendered:
				has_friendly_in_target_hex = true
				break
		if has_friendly_in_target_hex:
			continue
		
		var score_pack: Dictionary = controller._score_enemy_for_target(controller.unit, enemy, current_hex)
		var score: float = float(score_pack["score"])
		
		if score > best_score:
			best_score = score
			best_enemy = enemy
			best_cover = int(score_pack["cover"])

	if best_enemy == null:
		if not controller.unit.squad_fire.target_unit == null:
			controller.target_unit = null
			controller.unit.order(Globals.UnitCmd.FIRE_AT_UNIT, controller.target_unit)
		return
	
	controller.unit.order(Globals.UnitCmd.FIRE_AT_UNIT, best_enemy)
	best_enemy.set_cover(best_cover)
	controller.fire_timer = fire_rate


static func score_enemy_for_target(controller: SquadFireController, shooter_unit: Unit, enemy: Unit, current_hex: Vector2i) -> Dictionary:
	var distance: int = LOSHelper.ground_layer.cube_distance(shooter_unit.current_cube, enemy.current_cube)
	if distance < 0:
		distance = 0

	var best_ratio: float = 0.0
	var has_range: bool = false

	for soldier: Soldier in shooter_unit.squad_fire.soldiers:
		var w_range: int = int(soldier.weapon.range_hexes)
		if w_range >= distance:
			has_range = true

			var ratio: float = float(w_range) / float(distance) # bigger is better
			if ratio > best_ratio:
				best_ratio = ratio

	if not has_range:
		return {"score": -INF, "cover": 0}

	var cover_map: Dictionary = LOSHelper.los_lookup.get(current_hex, {})
	var targetCover: int = 0
	if cover_map and cover_map.has(enemy.current_hex):
		var data: Dictionary = cover_map[enemy.current_hex]
		targetCover = data["target_cover"]
	enemy.set_cover(targetCover)
	var cover_val: int = targetCover
	var cover_penalty: float = float(cover_val) # tune weights below to match your cover scale

	var move_bonus: float = 0.0
	if enemy.is_moving:
		move_bonus = 1.0

	# weights (tune)
	var w_range_ratio: float = 10.0
	var w_move: float = 2.0
	var w_cover: float = 3.0

	var score: float = 0.0
	score += best_ratio * w_range_ratio
	score += move_bonus * w_move
	score -= cover_penalty * w_cover

	return {"score": score, "cover": cover_val}
