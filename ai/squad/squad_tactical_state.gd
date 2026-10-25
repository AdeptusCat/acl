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

const FULL_ATTENTION_MEMBERS: int = 10
const FOCUSED_DETECTION_MULTIPLIER: float = 1.35
const PERIPHERAL_DETECTION_MULTIPLIER: float = 0.35
const DEMAND_SECTOR_COUNT: int = 8

# World-space unit direction; zero means broad, neutral coverage.
# Width is in radians. Quality is observation capacity, separate from directional focus.
var focus_direction: Vector2 = Vector2.ZERO
var focus_strength: float = 0.0
var attention_width: float = TAU
var attention_quality: float = 0.0
var has_contact: bool = false
# Raw demand, clockwise from world-space east. Opposing contacts remain separate.
var directional_demand: PackedFloat32Array = PackedFloat32Array()
var total_directional_demand: float = 0.0


func update_attention(unit: Unit) -> void:
	focus_direction = Vector2.ZERO
	focus_strength = 0.0
	attention_width = TAU
	attention_quality = 0.0
	has_contact = false
	directional_demand.resize(DEMAND_SECTOR_COUNT)
	directional_demand.fill(0.0)
	total_directional_demand = 0.0
	if not unit.is_active() or unit.surrendered or unit.members_alive <= 0:
		return
	attention_quality = _attention_quality(unit)

	var contact_direction: Vector2 = Vector2.ZERO
	var visible: Array = Globals.unit_visible_enemies.get(unit, [])
	var tracks: Dictionary = Globals.unit_enemy_tracks.get(unit, {})
	var observed: Array[Unit] = []
	for enemy: Unit in visible:
		if not is_instance_valid(enemy) or not enemy.is_active() or enemy.surrendered or enemy.team == unit.team:
			continue
		if Globals.unit_enemies_in_los.has(unit) and not Globals.unit_enemies_in_los[unit].has(enemy):
			continue
		observed.append(enemy)
		has_contact = true
		var urgency: float = 1.0
		if enemy.squad_fire != null:
			urgency += clampf(enemy.squad_fire.fire_recent, 0.0, 1.0)
		contact_direction += _add_directional_demand(enemy.global_position - unit.global_position, urgency)

	var enemy_direction: Vector2 = Vector2.ZERO
	for enemy: Unit in tracks:
		if not is_instance_valid(enemy) or not enemy.is_active() or enemy.surrendered or enemy.team == unit.team:
			continue
		if observed.has(enemy):
			continue
		var track: EnemyTrack = tracks[enemy] as EnemyTrack
		if track == null or track.awareness <= 0.0:
			continue
		# Hidden units contribute only their recorded position, never their live position.
		enemy_direction += _add_directional_demand(track.last_known_global_position - unit.global_position, track.awareness * 0.5)
	if has_contact:
		_set_attention(contact_direction + enemy_direction, 1.0, PI / 2.0)
		return

	if not is_instance_valid(LOSHelper.ground_layer):
		_set_attention(enemy_direction, minf(total_directional_demand, 0.6), PI)
		return
	var movement_order_direction: Vector2 = _movement_order_direction(unit)
	var objective_direction: Vector2 = Vector2.ZERO
	var nearest_distance: float = INF
	var objectives: Array = Globals.objective_hexes.get(unit.team, [])
	for objective: Vector2i in objectives:
		var offset: Vector2 = _hex_offset(unit, objective)
		if not offset.is_zero_approx() and offset.length_squared() < nearest_distance:
			nearest_distance = offset.length_squared()
			objective_direction = offset.normalized()

	# Remembered demand fades gradually, letting movement and objectives regain attention.
	var expectation: Vector2 = movement_order_direction * 0.4 + enemy_direction.limit_length(1.0) * 0.8 + objective_direction * 0.2
	var strength: float = 0.6
	if movement_order_direction.is_zero_approx() and objective_direction.is_zero_approx():
		strength = minf(total_directional_demand * 1.2, 0.6)
	_set_attention(expectation, strength, PI)


func _add_directional_demand(offset: Vector2, urgency: float) -> Vector2:
	if offset.is_zero_approx():
		return Vector2.ZERO
	var hex_size: float = 64.0
	if is_instance_valid(LOSHelper.ground_layer) and LOSHelper.ground_layer.tile_set != null:
		hex_size = maxf(float(LOSHelper.ground_layer.tile_set.tile_size.x), 1.0)
	var weight: float = urgency / (1.0 + offset.length() / hex_size * 0.15)
	var sector: float = fposmod(offset.angle(), TAU) / TAU * float(DEMAND_SECTOR_COUNT)
	var index: int = int(floorf(sector)) % DEMAND_SECTOR_COUNT
	var fraction: float = sector - floorf(sector)
	directional_demand[index] += weight * (1.0 - fraction)
	directional_demand[(index + 1) % DEMAND_SECTOR_COUNT] += weight * fraction
	total_directional_demand += weight
	return offset.normalized() * weight


func detection_multiplier(direction: Vector2) -> float:
	if focus_direction.is_zero_approx() or direction.is_zero_approx():
		return attention_quality
	var angle: float = absf(focus_direction.angle_to(direction))
	var half_width: float = clampf(attention_width * 0.5, 0.001, PI)
	var alignment: float = 1.0 - smoothstep(0.0, half_width, angle)
	var directional_rate: float = lerpf(PERIPHERAL_DETECTION_MULTIPLIER, FOCUSED_DETECTION_MULTIPLIER, alignment)
	return attention_quality * lerpf(1.0, directional_rate, focus_strength)


func _attention_quality(unit: Unit) -> float:
	# Small teams have fewer observers; casualties also reduce larger squads' capacity.
	var expected_size: int = maxi(unit.original_size, FULL_ATTENTION_MEMBERS)
	var quality: float = sqrt(clampf(float(unit.members_alive) / float(expected_size), 0.0, 1.0))
	if unit.combat_stats != null:
		quality *= lerpf(0.5, 1.0, clampf(unit.combat_stats.cohesion_current, 0.0, 1.0))
	if unit.stress_system != null:
		quality *= lerpf(1.0, 0.75, clampf(unit.stress_system.S_eff / 100.0, 0.0, 1.0))
		match unit.stress_system.state:
			STATES.MoraleState.CAUTIOUS:
				quality *= 0.9
			STATES.MoraleState.PINNED:
				quality *= 0.55
			STATES.MoraleState.PANIC:
				quality *= 0.25
			STATES.MoraleState.COMBAT_INEFFECTIVE:
				quality *= 0.15
	return clampf(quality, 0.0, 1.0)


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
