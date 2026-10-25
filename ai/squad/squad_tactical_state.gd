class_name SquadTacticalState
extends RefCounted

var squad: Unit = null
var hex: Vector2i = Vector2i.ZERO

var members_alive: int = 0
var original_size: int = 0

var combat_effectiveness: float = 1.0
var stress_effective: float = 0.0
var cohesion: float = 1.0

var morale_state: STATES.MoraleState = STATES.MoraleState.NORMAL

#var has_mg: bool = false
#var has_leader: bool = false
#var has_radio: bool = false

var current_role: int = PlatoonTypes.Role.NONE
var assigned_task_id: int = -1

# World-space unit direction; zero means broad, neutral coverage.
# Width is in radians. These fields describe attention without affecting combat.
var focus_direction: Vector2 = Vector2.ZERO
var focus_strength: float = 0.0
var attention_width: float = TAU
var has_contact: bool = false


func update_attention(unit: Unit) -> void:
	focus_direction = Vector2.ZERO
	focus_strength = 0.0
	attention_width = TAU
	has_contact = false
	if not unit.is_active() or unit.surrendered:
		return

	var contact_direction: Vector2 = Vector2.ZERO
	var visible: Array = Globals.unit_visible_enemies.get(unit, [])
	for enemy: Unit in visible:
		if not is_instance_valid(enemy) or not enemy.is_active() or enemy.surrendered or enemy.team == unit.team:
			continue
		has_contact = true
		contact_direction += unit.global_position.direction_to(enemy.global_position)
	if has_contact:
		_set_attention(contact_direction, 1.0, PI / 2.0)
		return

	if not is_instance_valid(LOSHelper.ground_layer):
		return
	var movement_order_direction: Vector2 = _movement_order_direction(unit)
	var enemy_direction: Vector2 = Vector2.ZERO
	var tracks: Dictionary = Globals.unit_enemy_tracks.get(unit, {})
	for enemy: Unit in tracks:
		if not is_instance_valid(enemy) or not enemy.is_active() or enemy.surrendered or enemy.team == unit.team:
			continue
		var track: EnemyTrack = tracks[enemy] as EnemyTrack
		if track == null or track.confidence <= EnemyTrack.STALE_CONFIDENCE:
			continue
		# Hidden units contribute only their recorded position, never their live position.
		enemy_direction += unit.global_position.direction_to(track.last_known_global_position) * track.confidence

	var objective_direction: Vector2 = Vector2.ZERO
	var nearest_distance: float = INF
	var objectives: Array = Globals.objective_hexes.get(unit.team, [])
	for objective: Vector2i in objectives:
		var offset: Vector2 = _hex_offset(unit, objective)
		if not offset.is_zero_approx() and offset.length_squared() < nearest_distance:
			nearest_distance = offset.length_squared()
			objective_direction = offset.normalized()

	# Normalize each source so the number of remembered enemies cannot dominate orders.
	var expectation: Vector2 = movement_order_direction * 0.4 + enemy_direction.normalized() * 0.4 + objective_direction * 0.2
	_set_attention(expectation, 0.6, PI)


func _movement_order_direction(unit: Unit) -> Vector2:
	if unit.movement != null and unit.movement.is_moving:
		return _hex_offset(unit, unit.goal_hex).normalized()
	if unit.action_controller != null and unit.action_controller.action_state != SquadActionController.SquadActionState.NO_ORDER:
		var direction: Vector2 = _hex_offset(unit, unit.action_controller.objective_hex).normalized()
		if not direction.is_zero_approx():
			return direction
	if unit.squad_ai_controller != null:
		var order: AiOrder = unit.squad_ai_controller.current_order
		if order != null and order.order_type in [AiOrder.OrderType.MOVE_TO, AiOrder.OrderType.ASSAULT, AiOrder.OrderType.WITHDRAW]:
			return _hex_offset(unit, order.target_hex).normalized()
	return Vector2.ZERO


func _hex_offset(unit: Unit, target: Vector2i) -> Vector2:
	return LOSHelper.ground_layer.to_global(LOSHelper.ground_layer.map_to_local(target)) - unit.global_position


func _set_attention(direction: Vector2, strength: float, width: float) -> void:
	if direction.is_zero_approx():
		return
	focus_direction = direction.normalized()
	focus_strength = strength
	attention_width = width


func configure(
	p_squad: Unit,
	p_hex: Vector2i,
	p_members_alive: int,
	p_original_size: int,
	p_combat_effectiveness: float,
	p_stress_effective: float,
	p_cohesion: float,
	p_morale_state: STATES.MoraleState,
	#p_has_mg: bool,
	#p_has_leader: bool,
	#p_has_radio: bool
) -> void:
	squad = p_squad
	hex = p_hex
	members_alive = p_members_alive
	original_size = p_original_size
	combat_effectiveness = clampf(p_combat_effectiveness, 0.0, 1.0)
	stress_effective = clampf(p_stress_effective, 0.0, 100.0)
	cohesion = clampf(p_cohesion, 0.0, 1.0)

	morale_state = p_morale_state

	#has_mg = p_has_mg
	#has_leader = p_has_leader
	#has_radio = p_has_radio


func is_pinned() -> bool:
	return morale_state == STATES.MoraleState.PINNED


func is_panicking() -> bool:
	return morale_state == STATES.MoraleState.PANIC


func is_combat_ineffective() -> bool:
	return morale_state == STATES.MoraleState.COMBAT_INEFFECTIVE


func can_fire() -> bool:
	if morale_state == STATES.MoraleState.PANIC:
		return false

	if morale_state == STATES.MoraleState.COMBAT_INEFFECTIVE:
		return false

	return true


func can_move_normally() -> bool:
	if morale_state == STATES.MoraleState.PINNED:
		return false

	if morale_state == STATES.MoraleState.PANIC:
		return false

	if morale_state == STATES.MoraleState.COMBAT_INEFFECTIVE:
		return false

	return true
