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
	track.record_detection()
	Globals.unit_enemy_tracks[unit] = {enemy: track}
	enemy.position = unit.position + Vector2(0.0, 100.0)
	attention.update_attention(unit)
	_check(attention.focus_direction.is_equal_approx(Vector2.RIGHT) and not attention.has_contact, "Remembered threat uses recorded position after hidden movement")
	unit.movement.is_moving = true
	unit.goal_hex = destination
	attention.update_attention(unit)
	_check(attention.focus_direction.dot(Vector2.RIGHT) > expected.dot(Vector2.RIGHT) and attention.focus_direction.dot(expected) > Vector2.RIGHT.dot(expected), "Remembered demand pulls movement focus toward the known threat")
	Globals.unit_visible_enemies[unit] = [enemy]
	attention.update_attention(unit)
	_check(attention.has_contact and attention.focus_direction.is_equal_approx(Vector2.DOWN), "Visible contact overrides movement and memory")
	_check(attention.focus_strength == 1.0 and attention.attention_width == PI / 2.0, "Contact narrows and strengthens focus")
	Globals.unit_visible_enemies.clear()
	unit.movement.is_moving = false
	attention.update_attention(unit)
	_check(not attention.has_contact and attention.focus_direction.is_equal_approx(Vector2.RIGHT), "Contact loss restores remembered expectation")
	track.confidence = 0.0
	track.update_not_seen(11.0)
	attention.update_attention(unit)
	_check(attention.focus_direction.is_equal_approx(Vector2.RIGHT) and not track.should_delete(), "Awareness persists after visual confidence is exhausted")
	track.update_not_seen(20.0)
	attention.update_attention(unit)
	_check_neutral(attention, "Expired threat clears old focus")
	_check(track.should_delete(), "Expired awareness allows an unseen track to be removed")
	Globals.objective_hexes[unit.team] = [unit.current_hex]
	attention.update_attention(unit)
	_check_neutral(attention, "Objective at current position has no direction")
	_test_attention_quality(unit, attention)
	_test_detection(unit, enemy, attention)
	_test_directional_demand(unit, enemy, attention)
	_test_awareness(enemy)
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


func _test_awareness(enemy: Unit) -> void:
	var track: EnemyTrack = EnemyTrack.new(null, enemy)
	var first_position: Vector2 = enemy.position
	enemy.position += Vector2.DOWN * 100.0
	track.update_seen(1.0, 1.0)
	_check(track.awareness == 0.0 and track.last_known_global_position == first_position, "Undetected LOS candidates cannot create awareness or update a known location")
	track.confidence = 0.7
	track.record_detection()
	var detected_position: Vector2 = enemy.position
	var detected_hex: Vector2i = enemy.current_hex
	enemy.position += Vector2.LEFT * 100.0
	enemy.current_hex += Vector2i(1, 1)
	track.update_not_seen(1.0)
	_check(not track.is_visible and not track.has_confirmed_lock and track.awareness > 0.9, "LOS loss clears live visibility while retaining awareness")
	track.update_seen(1.0, 2.0)
	_check(track.last_known_global_position == detected_position and track.last_known_hex == detected_hex, "Returning to LOS cannot update last-seen coordinates before reacquisition")
	var split: EnemyTrack = EnemyTrack.new(null, enemy)
	split.confidence = track.confidence
	split.awareness = 1.0
	for step: int in range(20):
		split.update_not_seen(0.1)
	_check(is_equal_approx(split.awareness, track.awareness), "Awareness decay depends on elapsed time rather than update frequency")
	track.record_detection()
	_check(track.awareness == 1.0 and track.last_known_global_position == enemy.position, "Confirmed reacquisition refreshes awareness and location")
	enemy.position = first_position
	enemy.current_hex = detected_hex


func _test_directional_demand(unit: Unit, enemy: Unit, attention: SquadTacticalState) -> void:
	Globals.unit_enemy_tracks.clear()
	Globals.objective_hexes.clear()
	var other: Unit = Unit.new()
	other.team = enemy.team
	other.position = unit.position + Vector2.LEFT * 100.0
	enemy.position = unit.position + Vector2.RIGHT * 100.0
	enemy.squad_fire = SquadFireController.new()
	Globals.unit_visible_enemies[unit] = [enemy, other]
	attention.update_attention(unit)
	_check(attention.directional_demand[0] > 0.0 and attention.directional_demand[4] > 0.0 and attention.total_directional_demand > 0.0, "Opposing detected contacts retain demand in both directions")
	_check(attention.focus_direction == Vector2.ZERO and attention.has_contact, "Balanced opposing demand produces broad coverage while retaining contact")
	enemy.squad_fire.fire_recent = 1.0
	attention.update_attention(unit)
	_check(attention.focus_direction.is_equal_approx(Vector2.RIGHT) and attention.directional_demand[0] > attention.directional_demand[4], "An enemy firing now pulls focus more strongly")
	enemy.squad_fire.fire_recent = 0.0
	other.position = unit.position + Vector2.LEFT * 1000.0
	attention.update_attention(unit)
	_check(attention.focus_direction.is_equal_approx(Vector2.RIGHT), "Nearer detected contacts create more directional demand")
	Globals.unit_visible_enemies[unit] = [enemy]
	attention.update_attention(unit)
	var visible_demand: float = attention.total_directional_demand
	var track: EnemyTrack = EnemyTrack.new(unit, enemy)
	track.record_detection()
	Globals.unit_enemy_tracks[unit] = {enemy: track}
	attention.update_attention(unit)
	_check(is_equal_approx(attention.total_directional_demand, visible_demand), "A visible contact is counted once even when it also has an awareness track")
	Globals.unit_visible_enemies.clear()
	track.update_not_seen(5.0)
	attention.update_attention(unit)
	var remembered_demand: float = attention.total_directional_demand
	var remembered_strength: float = attention.focus_strength
	enemy.position = unit.position + Vector2.DOWN * 100.0
	track.update_seen(1.0, 1.0)
	attention.update_attention(unit)
	_check(attention.focus_direction.is_equal_approx(Vector2.RIGHT), "Remembered demand cannot follow a hidden enemy's movement")
	track.update_not_seen(10.0)
	attention.update_attention(unit)
	_check(attention.total_directional_demand < remembered_demand and attention.focus_strength < remembered_strength, "Demand and focus strength fade with awareness")
	track.update_not_seen(30.0)
	attention.update_attention(unit)
	_check(attention.total_directional_demand == 0.0, "Forgotten contacts leave no stale directional demand")
	Globals.unit_enemy_tracks.clear()
	enemy.squad_fire.free()
	other.free()


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
	_check(is_equal_approx(side, neutral) and side > rear, "The attention boundary retains neutral observation effectiveness")
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
	var concealed: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0)
	_check(concealed >= 0.0 and concealed < neutral * 0.001, "Deep concealment strongly attenuates acquisition")
	controller.concealment = 0
	_test_detection_factors(controller, unit, enemy, attention, neutral)
	unit.surrendered = true
	attention.update_attention(unit)
	_check(attention.attention_quality == 0.0 and MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0) == 0.0, "Surrendered squads cannot spot")
	unit.surrendered = false
	attention.update_attention(unit)
	enemy.squad_fire.free()
	controller.free()


func _test_detection_factors(controller: DetectionProbe, unit: Unit, enemy: Unit, attention: SquadTacticalState, neutral: float) -> void:
	unit.is_moving = true
	var moving_observer: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0)
	_check(moving_observer < neutral, "Observer movement reduces acquisition")
	unit.is_moving = false
	unit.stress_system.under_fire = true
	var suppressed: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0)
	_check(suppressed > 0.0 and suppressed < neutral, "Suppression reduces spotting without blindness")
	unit.stress_system.under_fire = false
	enemy.is_moving = false
	var stationary: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0)
	_check(stationary < neutral, "Enemy movement increases detectability")
	enemy.squad_fire.fire_recent = 1.0
	_check(MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0) > stationary, "Enemy firing increases detectability")
	enemy.squad_fire.fire_recent = 0.0
	enemy.is_moving = true
	var near_cube: Vector3i = enemy.current_cube
	enemy.current_cube = unit.current_cube + Vector3i(16, -16, 0)
	var distant: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0)
	enemy.current_cube = unit.current_cube + Vector3i(32, -32, 0)
	var farther: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0)
	_check(neutral > distant and distant > farther and farther > 0.0, "Distance smoothly reduces spotting beyond 640 metres without a cutoff")
	enemy.current_cube = near_cube
	for strength: int in [1, 2, 3]:
		controller.concealment = strength
		var concealed: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0)
		_check(concealed > 0.0 and concealed < neutral, "Target concealment reduces spotting at strength " + str(strength))
	controller.concealment = 0
	LOSHelper.los_lookup = {unit.current_hex: {enemy.current_hex: {"target_concealment": 2, "target_cover": 99, "hindrance": 0}}}
	_check(MatchVisibilityCoordinator.get_concealment(controller, unit.current_hex, enemy) == 2, "Detection reads target concealment rather than bullet cover")
	LOSHelper.los_lookup[unit.current_hex][enemy.current_hex] = {"target_cover": 99, "hindrance": 0}
	_check(MatchVisibilityCoordinator.get_concealment(controller, unit.current_hex, enemy) == 0, "Legacy bullet cover does not become concealment")
	var previous: float = neutral
	for count: int in [1, 2, 3]:
		LOSHelper.los_lookup[unit.current_hex][enemy.current_hex]["hindrance"] = count
		var obstructed: float = MatchVisibilityCoordinator.compute_detect_prob_per_tick(controller, unit, enemy, 1.0)
		_check(obstructed > 0.0 and obstructed < previous, "Each crossed concealment hex compounds attenuation")
		previous = obstructed
	LOSHelper.los_lookup.clear()
	attention.focus_direction = Vector2.RIGHT
	attention.focus_strength = 1.0
	attention.attention_width = PI / 2.0
	var centre: float = attention.detection_multiplier(Vector2.RIGHT)
	var inside: float = attention.detection_multiplier(Vector2.RIGHT.rotated(PI / 8.0))
	var boundary: float = attention.detection_multiplier(Vector2.RIGHT.rotated(PI / 4.0))
	var outside: float = attention.detection_multiplier(Vector2.LEFT)
	_check(centre > inside and inside > boundary and is_equal_approx(boundary, attention.attention_quality) and boundary > outside and outside > 0.0, "The whole attention area benefits observation, with penalties only outside")
	attention.update_attention(unit)


func _check_neutral(attention: SquadTacticalState, message: String) -> void:
	_check(attention.focus_direction == Vector2.ZERO and attention.focus_strength == 0.0 and attention.attention_width == TAU, message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
