extends Node

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
	var attention: SquadTacticalState = SquadTacticalState.new()
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
	unit.free()
	enemy.free()
	LOSHelper.ground_layer = null
	ground.free()
	print("Squad attention regression failures: ", failures)
	get_tree().quit(failures)


func _check_neutral(attention: SquadTacticalState, message: String) -> void:
	_check(attention.focus_direction == Vector2.ZERO and attention.focus_strength == 0.0 and attention.attention_width == TAU, message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
