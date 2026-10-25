extends Node

class DetectionProbe extends Node2D:
	var concealment: int = 0

	func _get_concealment(_hex: Vector2i, _enemy: Unit) -> int:
		return concealment


var failures: int = 0


func _ready() -> void:
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ground.tile_set.tile_size = Vector2i(64, 64)
	ground.pathfinding_enabled = false
	add_child(ground)
	LOSHelper.ground_layer = ground
	var unit: Unit = Unit.new()
	unit.current_hex = Vector2i(2, 2)
	unit.position = ground.map_to_local(unit.current_hex)
	unit.movement = UnitMovement.new()
	unit.action_controller = SquadActionController.new()
	unit.squad_ai_controller = SquadAiController.new()
	unit.stress_system = StressController.new()
	unit.combat_stats = UnitCombatStats.new()
	var attention: SquadTacticalState = SquadTacticalState.new()
	unit.tactical_state = attention
	attention.update_attention(unit)
	_check_neutral(attention, "Idle squad without information has neutral coverage")

	var destination: Vector2i = Vector2i(6, 4)
	var expected: Vector2 = unit.position.direction_to(ground.map_to_local(destination))
	unit.goal_hex = destination
	unit.movement.is_moving = true
	attention.update_attention(unit)
	_check(attention.focus_direction.is_equal_approx(expected) and not attention.has_contact, "Movement biases focus before contact")
	_check(attention.focus_strength > 0.0 and attention.attention_width == PI, "No-contact focus has broad directional coverage")
	unit.movement.is_moving = false
	unit.action_controller.action_state = SquadActionController.SquadActionState.MOVING_TO_POSITION
	unit.action_controller.objective_hex = destination
	attention.update_attention(unit)
	_check(attention.focus_direction.is_equal_approx(expected), "Paused player order retains its direction")
	unit.action_controller.action_state = SquadActionController.SquadActionState.NO_ORDER
	var order: AiOrder = AiOrder.new()
	order.order_type = AiOrder.OrderType.ASSAULT
	order.target_hex = destination
	unit.squad_ai_controller.current_order = order
	attention.update_attention(unit)
	_check(attention.focus_direction.is_equal_approx(expected), "AI order supplies pre-movement direction")
	unit.squad_ai_controller.current_order = null
	Globals.objective_hexes[unit.team] = [Vector2i(10, 10), destination]
	attention.update_attention(unit)
	_check(attention.focus_direction.is_equal_approx(expected), "Nearest team objective supplies idle focus")
	Globals.objective_hexes.clear()

	var enemy: Unit = Unit.new()
	enemy.team = Globals.Team.ALLIES
	if enemy.team == unit.team:
		enemy.team = Globals.Team.AXIS
	enemy.position = unit.position + Vector2(100.0, 0.0)
	var track: EnemyTrack = EnemyTrack.new(unit, enemy)
	track.confidence = 0.8
	Globals.unit_enemy_tracks[unit] = {enemy: track}
	enemy.position = unit.position + Vector2(0.0, 100.0)
	attention.update_attention(unit)
	_check(attention.focus_direction.is_equal_approx(Vector2.RIGHT) and not attention.has_contact, "Remembered threat uses recorded position after hidden movement")
	unit.movement.is_moving = true
	unit.goal_hex = destination
	attention.update_attention(unit)
	_check(attention.focus_direction.is_equal_approx((expected + Vector2.RIGHT).normalized()), "Movement and remembered threat blend equally")
	Globals.unit_visible_enemies[unit] = [enemy]
	attention.update_attention(unit)
	_check(attention.has_contact and attention.focus_direction.is_equal_approx(Vector2.DOWN), "Visible contact overrides movement and memory")
	_check(attention.focus_strength == 1.0 and attention.attention_width == PI / 2.0, "Contact narrows and strengthens focus")
	Globals.unit_visible_enemies.clear()
	unit.movement.is_moving = false
	attention.update_attention(unit)
	_check(not attention.has_contact and attention.focus_direction.is_equal_approx(Vector2.RIGHT), "Contact loss restores remembered expectation")
	track.confidence = 0.0
	attention.update_attention(unit)
	_check_neutral(attention, "Expired threat clears old focus")
	Globals.objective_hexes[unit.team] = [unit.current_hex]
	attention.update_attention(unit)
	_check_neutral(attention, "Objective at current position has no direction")
	_test_attention_quality(unit, attention)
	_test_detection(unit, enemy, attention)
	unit.movement.is_moving = true
	unit.surrendered = true
	attention.update_attention(unit)
	_check_neutral(attention, "Surrender clears attention")
	unit.surrendered = false
	unit.alive = false
	attention.update_attention(unit)
	_check_neutral(attention, "Inactive squad has no attention")

	Globals.unit_visible_enemies.clear()
	Globals.unit_enemy_tracks.clear()
	Globals.objective_hexes.clear()
	unit.movement.free()
	unit.action_controller.free()
	unit.squad_ai_controller.free()
	unit.stress_system.free()
	unit.combat_stats.free()
	unit.free()
	enemy.free()
	LOSHelper.ground_layer = null
	ground.free()
	print("Squad attention regression failures: ", failures)
	get_tree().quit(failures)


func _test_attention_quality(unit: Unit, attention: SquadTacticalState) -> void:
	unit.members_alive = 12
	unit.original_size = 12
	attention.update_attention(unit)
	var full_quality: float = attention.attention_quality
	unit.members_alive = 6
	attention.update_attention(unit)
	_check(attention.attention_quality > 0.0 and attention.attention_quality < full_quality, "Casualties reduce observation capacity")
	unit.members_alive = 4
	unit.original_size = 4
	attention.update_attention(unit)
	_check(attention.attention_quality < full_quality, "An intact small team has fewer observers than an intact rifle squad")
	unit.members_alive = 10
	unit.original_size = 10
	var previous_quality: float = full_quality
	for state: STATES.MoraleState in [STATES.MoraleState.CAUTIOUS, STATES.MoraleState.PINNED, STATES.MoraleState.PANIC, STATES.MoraleState.COMBAT_INEFFECTIVE]:
		unit.stress_system.state = state
		attention.update_attention(unit)
		_check(attention.attention_quality > 0.0 and attention.attention_quality < previous_quality, "Worsening morale reduces attention quality: " + str(state))
		previous_quality = attention.attention_quality
	unit.stress_system.state = STATES.MoraleState.NORMAL
	unit.stress_system.S_eff = 70.0
	attention.update_attention(unit)
	_check(attention.attention_quality < full_quality, "Stress reduces quality within a morale state")
	unit.stress_system.S_eff = 0.0
	unit.combat_stats.cohesion_current = 0.2
	attention.update_attention(unit)
	_check(attention.attention_quality < full_quality, "Poor cohesion reduces observation capacity")
	unit.combat_stats.cohesion_current = 1.0
	attention.update_attention(unit)
	_check(is_equal_approx(attention.attention_quality, full_quality), "Recovery restores quality without retaining stale penalties")
	unit.members_alive = 0
	unit.original_size = 0
	attention.update_attention(unit)
	_check(attention.attention_quality == 0.0, "Empty squads have no observation capacity, including uninitialized rosters")
	unit.members_alive = 10
	unit.original_size = 10
	attention.update_attention(unit)


func _test_detection(unit: Unit, enemy: Unit, attention: SquadTacticalState) -> void:
	var controller: DetectionProbe = DetectionProbe.new()
	enemy.squad_fire = SquadFireController.new()
	enemy.is_moving = true
	unit.current_cube = LOSHelper.ground_layer.map_to_cube(unit.current_hex)
	enemy.current_cube = LOSHelper.ground_layer.map_to_cube(unit.current_hex + Vector2i(0, 1))
	enemy.position = unit.position + Vector2.RIGHT * 100.0
	attention.update_attention(unit)
	var neutral: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0)
	attention.focus_direction = Vector2.RIGHT
	attention.focus_strength = 0.6
	attention.attention_width = PI
	var front: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0)
	attention.focus_direction = Vector2.UP
	var side: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0)
	attention.focus_direction = Vector2.LEFT
	var rear: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0)
	_check(front > neutral and neutral > rear and rear > 0.0, "Focus improves forward spotting and reduces rear spotting without blindness")
	_check(side <= neutral and side >= rear, "Peripheral spotting remains bounded by forward and rear spotting")
	attention.focus_direction = Vector2.RIGHT
	var half_tick: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 0.5)
	_check(is_equal_approx(front, 1.0 - pow(1.0 - half_tick, 2.0)), "Attention scales the spotting hazard consistently across time steps")
	_check(MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 0.0) == 0.0, "Zero exposure cannot spot a target")
	attention.focus_direction = Vector2.ZERO
	unit.members_alive = 3
	attention.update_attention(unit)
	var remnant: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0)
	_check(remnant > 0.0 and remnant < neutral, "Fewer observers reduce actual detection probability")
	unit.members_alive = 10
	unit.stress_system.state = STATES.MoraleState.PINNED
	attention.update_attention(unit)
	var pinned: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0)
	_check(pinned > 0.0 and pinned < neutral, "Pinning reduces actual detection probability")
	unit.stress_system.state = STATES.MoraleState.NORMAL
	attention.update_attention(unit)
	controller.concealment = 20
	_check(MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0) == 0.0, "Attention cannot bypass a concealment-suppressed base spotting rate")
	controller.concealment = 0
	unit.surrendered = true
	attention.update_attention(unit)
	_check(attention.attention_quality == 0.0 and MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0) == 0.0, "Surrendered squads cannot spot")
	unit.surrendered = false
	attention.update_attention(unit)
	enemy.squad_fire.free()
	controller.free()


func _check_neutral(attention: SquadTacticalState, message: String) -> void:
	_check(attention.focus_direction == Vector2.ZERO and attention.focus_strength == 0.0 and attention.attention_width == TAU, message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
