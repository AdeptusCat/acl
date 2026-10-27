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
const INCOMING_FIRE_WINDOW_SECONDS: float = 4.0
const RETURN_FIRE_WINDOW_SECONDS: float = 8.0
const RETURN_FIRE_HALF_ANGLE: float = PI / 6.0
const FULL_ATTENTION_CAPACITY: float = 2.0
const DEFAULT_SUPPRESSION_WINDOW_SECONDS: float = 2.0
const INCOMING_SUPPRESSION_DEMAND: float = 2.0
const CLUSTER_DEMAND_LIMIT: float = 1.5
const MAX_ATTENTION_STRESS_RATE: float = 4.0
const SWITCH_STRESS_RATE: float = 2.0
const SWITCH_RECOVERY_SECONDS: float = 1.0

# World-space unit direction; zero means broad, neutral coverage.
# Width is in radians. Quality is observation capacity, separate from directional focus.
var focus_direction: Vector2 = Vector2.ZERO
var focus_strength: float = 0.0
var attention_width: float = TAU
var attention_quality: float = 0.0
var has_contact: bool = false
var watch_focus_active: bool = false
var watch_diverted: bool = false
var focus_detection_multiplier: float = FOCUSED_DETECTION_MULTIPLIER
var peripheral_detection_multiplier: float = PERIPHERAL_DETECTION_MULTIPLIER
# Raw demand, clockwise from world-space east. Opposing contacts remain separate.
var directional_demand: PackedFloat32Array = PackedFloat32Array()
var total_directional_demand: float = 0.0
var last_attack_surprise: float = 0.0
var multi_direction_pressure: float = 0.0
var incoming_fire_demand: PackedFloat32Array = PackedFloat32Array()
var _incoming_fire_times: PackedFloat64Array = PackedFloat64Array()
var _incoming_fire_directions: PackedVector2Array = PackedVector2Array()
var attention_capacity: float = 0.0
var attention_deficit: float = 0.0
var required_attention: float = 0.0
var suppression_activity: float = 0.0
var attention_stress_rate: float = 0.0
var attention_switch_load: float = 0.0
var switching_stress_rate: float = 0.0
var flanked: bool = false
var surrounded: bool = false
var _last_focus_direction: Vector2 = Vector2.ZERO
var _suppression_bearings: PackedVector3Array = PackedVector3Array()
var _suppression_window_s: float = DEFAULT_SUPPRESSION_WINDOW_SECONDS
var _threat_angles: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	incoming_fire_demand.resize(DEMAND_SECTOR_COUNT)
	incoming_fire_demand.fill(0.0)
	_incoming_fire_times.resize(DEMAND_SECTOR_COUNT)
	_incoming_fire_times.fill(-INF)
	_incoming_fire_directions.resize(DEMAND_SECTOR_COUNT)


func update_attention(unit: Unit) -> void:
	_suppression_bearings.clear()
	_threat_angles.clear()
	_update_focus(unit)
	_update_attention_load()
	_update_tactical_conditions()


func _update_focus(unit: Unit) -> void:
	focus_direction = Vector2.ZERO
	focus_strength = 0.0
	attention_width = TAU
	attention_quality = 0.0
	has_contact = false
	watch_focus_active = false
	watch_diverted = false
	focus_detection_multiplier = FOCUSED_DETECTION_MULTIPLIER
	peripheral_detection_multiplier = PERIPHERAL_DETECTION_MULTIPLIER
	directional_demand.resize(DEMAND_SECTOR_COUNT)
	directional_demand.fill(0.0)
	total_directional_demand = 0.0
	if not unit.is_active() or unit.surrendered or unit.members_alive <= 0:
		_incoming_fire_times.fill(-INF)
		incoming_fire_demand.fill(0.0)
		multi_direction_pressure = 0.0
		suppression_activity = 0.0
		last_attack_surprise = 0.0
		attention_switch_load = 0.0
		switching_stress_rate = 0.0
		_last_focus_direction = Vector2.ZERO
		return
	attention_quality = _attention_quality(unit)
	_suppression_window_s = DEFAULT_SUPPRESSION_WINDOW_SECONDS
	if unit.stress_system != null:
		_suppression_window_s = maxf(unit.stress_system.under_fire_window_s, 0.0)
	update_fire_pressure(unit._now())

	var contact_direction: Vector2 = Vector2.ZERO
	var watching_order: bool = unit.has_watch_order() and not unit.broken
	var urgent_direction: Vector2 = Vector2.ZERO
	var urgent_weight: float = 0.0
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
		var firing: float = 0.0
		if enemy.squad_fire != null:
			firing = clampf(enemy.squad_fire.fire_recent, 0.0, 1.0)
			urgency += firing
		contact_direction += _add_directional_demand(enemy.global_position - unit.global_position, urgency)
		if watching_order and is_instance_valid(LOSHelper.ground_layer):
			var distance: int = LOSHelper.get_hex_distance(unit.current_hex, enemy.current_hex)
			var weight: float = urgency * float(3 - distance)
			if distance <= 2 and weight > urgent_weight and not enemy.global_position.is_equal_approx(unit.global_position):
				urgent_weight = weight
				urgent_direction = unit.global_position.direction_to(enemy.global_position)

	var enemy_direction: Vector2 = Vector2.ZERO
	for index: int in range(DEMAND_SECTOR_COUNT):
		if incoming_fire_demand[index] > 0.0:
			# Incoming fire provides a bearing, without identifying or revealing its source.
			var suppression: float = _suppression_weight(index, unit._now()) * INCOMING_SUPPRESSION_DEMAND
			enemy_direction += _add_directional_weight(_incoming_fire_directions[index], incoming_fire_demand[index], suppression)
			var weight: float = incoming_fire_demand[index] * 3.0
			if incoming_fire_demand[index] >= 0.15 and weight > urgent_weight:
				urgent_weight = weight
				urgent_direction = _incoming_fire_directions[index]
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
	if watching_order:
		if unit.attackState != Unit.AttackState.AUTO and is_instance_valid(unit.squad_fire) and unit.squad_fire.has_target_hex and is_instance_valid(LOSHelper.ground_layer):
			var fire_direction: Vector2 = _hex_offset(unit, unit.squad_fire.target_hex).normalized()
			if not fire_direction.is_zero_approx():
				urgent_direction = fire_direction
		if not urgent_direction.is_zero_approx():
			watch_diverted = true
			_set_attention(urgent_direction, 1.0, PI / 2.0)
			return
		if not unit.in_close_combat:
			var strength: float = 1.0
			if unit.is_moving or (is_instance_valid(unit.movement) and unit.movement.is_moving):
				strength = 0.45
			if has_contact:
				strength *= 0.8
			watch_focus_active = true
			focus_detection_multiplier = lerpf(1.65, 1.15, float(unit.watch_width) / 2.0)
			peripheral_detection_multiplier = lerpf(0.3, 0.65, float(unit.watch_width) / 2.0)
			_set_attention(unit.watch_direction, strength, unit.watch_arc_radians())
			return
		watch_diverted = true
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
	var distance_factor: float = 1.0 / (1.0 + offset.length() / hex_size * 0.15)
	return _add_directional_weight(offset.normalized(), urgency * distance_factor)


func _add_directional_weight(direction: Vector2, weight: float, suppression_weight: float = 0.0) -> Vector2:
	var sector: float = fposmod(direction.angle(), TAU) / TAU * float(DEMAND_SECTOR_COUNT)
	var index: int = int(floorf(sector)) % DEMAND_SECTOR_COUNT
	var fraction: float = sector - floorf(sector)
	directional_demand[index] += weight * (1.0 - fraction)
	directional_demand[(index + 1) % DEMAND_SECTOR_COUNT] += weight * fraction
	total_directional_demand += weight
	if suppression_weight > 0.0:
		_suppression_bearings.append(Vector3(direction.x, direction.y, suppression_weight))
	# Ignore nearly expired memories when deriving current tactical conditions.
	if weight >= 0.15:
		_threat_angles.append(fposmod(direction.angle(), TAU))
	return direction * weight


func _update_attention_load() -> void:
	attention_capacity = FULL_ATTENTION_CAPACITY * attention_quality
	var demand: float = 0.0
	var resultant: Vector2 = Vector2.ZERO
	# Only received fire creates suppression demand. Visible firing elsewhere and
	# remembered contacts retain observation/focus demand without an overload tax.
	for contact: Vector3 in _suppression_bearings:
		var overlapping: float = 0.0
		for other: Vector3 in _suppression_bearings:
			var alignment: float = maxf(contact.x * other.x + contact.y * other.y, 0.0)
			var alignment_squared: float = alignment * alignment
			overlapping += other.z * alignment_squared * alignment_squared
		var effective: float = contact.z / (1.0 + overlapping / CLUSTER_DEMAND_LIMIT)
		demand += effective
		resultant += Vector2(contact.x, contact.y) * effective
	var dispersion: float = 0.0
	if demand > 0.0:
		dispersion = clampf(1.0 - resultant.length() / demand, 0.0, 1.0)
	required_attention = demand * (1.0 + dispersion)
	attention_deficit = maxf(required_attention - attention_capacity, 0.0)
	attention_stress_rate = MAX_ATTENTION_STRESS_RATE * clampf(attention_deficit / maxf(attention_capacity, 0.25), 0.0, 1.0)


func _update_tactical_conditions() -> void:
	var flank_angle: float = PI / 2.0
	if flanked:
		flank_angle = PI * 5.0 / 12.0
	var max_gap: float = TAU
	if _threat_angles.size() >= 2:
		_threat_angles.sort()
		max_gap = _threat_angles[0] + TAU - _threat_angles[-1]
		for index: int in range(1, _threat_angles.size()):
			max_gap = maxf(max_gap, _threat_angles[index] - _threat_angles[index - 1])
	flanked = _threat_angles.size() >= 2 and TAU - max_gap >= flank_angle
	var surround_gap: float = PI * 17.0 / 18.0
	if surrounded:
		surround_gap = PI
	surrounded = _threat_angles.size() >= 3 and max_gap < surround_gap


# Tick once per simulation frame; return separate overload and switching costs.
# The stress controller owns their final fast/slow composition and application.
func advance_attention(delta: float) -> Vector2:
	if delta <= 0.0 or attention_quality <= 0.0:
		return Vector2.ZERO
	if not focus_direction.is_zero_approx():
		if not _last_focus_direction.is_zero_approx() and total_directional_demand > 0.0:
			var turn: float = absf(_last_focus_direction.angle_to(focus_direction)) / PI
			attention_switch_load = minf(attention_switch_load + turn, 1.0)
		_last_focus_direction = focus_direction
	elif total_directional_demand <= 0.0:
		_last_focus_direction = Vector2.ZERO
	# Integrate decay exactly so a discrete switch has the same cost at any frame rate.
	var decay: float = exp(-delta / SWITCH_RECOVERY_SECONDS)
	var switch_stress: float = attention_switch_load * SWITCH_RECOVERY_SECONDS * (1.0 - decay) * SWITCH_STRESS_RATE * suppression_activity
	attention_switch_load *= decay
	if is_zero_approx(attention_switch_load):
		attention_switch_load = 0.0
	switching_stress_rate = attention_switch_load * SWITCH_STRESS_RATE * suppression_activity
	var overload_stress: float = attention_stress_rate * delta
	return Vector2(overload_stress, switch_stress)


# Returns normalized surprise and crossfire pressure for this attack, before attention reacts.
func register_incoming_fire(direction: Vector2, now_seconds: float) -> Vector2:
	update_fire_pressure(now_seconds)
	if direction.is_zero_approx():
		last_attack_surprise = 0.0
		return Vector2.ZERO
	direction = direction.normalized()
	var surprise: float = _unattended_fraction(direction)
	for index: int in range(DEMAND_SECTOR_COUNT):
		# Repeated bursts on the same bearing refresh pressure without replaying surprise.
		var familiarity: float = pow(maxf(direction.dot(_incoming_fire_directions[index]), 0.0), 8.0)
		surprise *= 1.0 - familiarity * incoming_fire_demand[index]
	var sector: int = roundi(fposmod(direction.angle(), TAU) / TAU * float(DEMAND_SECTOR_COUNT)) % DEMAND_SECTOR_COUNT
	_incoming_fire_times[sector] = now_seconds
	_incoming_fire_directions[sector] = direction
	update_fire_pressure(now_seconds)
	last_attack_surprise = clampf(surprise, 0.0, 1.0)
	return Vector2(last_attack_surprise, multi_direction_pressure)


func has_recent_fire_from(direction: Vector2, now_seconds: float) -> bool:
	if not direction.is_finite() or direction.is_zero_approx():
		return false
	var bearing: Vector2 = direction.normalized()
	for index: int in range(DEMAND_SECTOR_COUNT):
		var age: float = now_seconds - _incoming_fire_times[index]
		if age >= 0.0 and age < RETURN_FIRE_WINDOW_SECONDS and bearing.dot(_incoming_fire_directions[index]) >= cos(RETURN_FIRE_HALF_ANGLE):
			return true
	return false


func update_fire_pressure(now_seconds: float) -> void:
	suppression_activity = 0.0
	var total: float = 0.0
	var resultant: Vector2 = Vector2.ZERO
	var active_directions: int = 0
	for index: int in range(DEMAND_SECTOR_COUNT):
		suppression_activity = maxf(suppression_activity, _suppression_weight(index, now_seconds))
		var age: float = maxf(now_seconds - _incoming_fire_times[index], 0.0)
		var weight: float = clampf(1.0 - age / INCOMING_FIRE_WINDOW_SECONDS, 0.0, 1.0)
		incoming_fire_demand[index] = weight
		if weight > 0.0:
			active_directions += 1
			total += weight
			resultant += _incoming_fire_directions[index] * weight
	multi_direction_pressure = 0.0
	if active_directions > 1:
		# Aligned fire adds volume, while separated bearings stretch the squad's capacity.
		multi_direction_pressure = clampf((total - resultant.length()) / maxf(attention_quality, 0.25), 0.0, 1.0)


func _suppression_weight(index: int, now_seconds: float) -> float:
	if _suppression_window_s <= 0.0:
		return 0.0
	var age: float = maxf(now_seconds - _incoming_fire_times[index], 0.0)
	return clampf(1.0 - age / _suppression_window_s, 0.0, 1.0)


func _unattended_fraction(direction: Vector2) -> float:
	if focus_direction.is_zero_approx() and total_directional_demand <= 0.0:
		return 0.0
	var coverage: float = 0.0
	if not focus_direction.is_zero_approx():
		var angle: float = absf(focus_direction.angle_to(direction))
		coverage = 1.0 - smoothstep(0.0, clampf(attention_width * 0.5, 0.001, PI), angle)
	var peak_demand: float = 0.0
	var known_coverage: float = 0.0
	for index: int in range(directional_demand.size()):
		peak_demand = maxf(peak_demand, directional_demand[index])
		var sector_direction: Vector2 = Vector2.from_angle(float(index) * TAU / float(DEMAND_SECTOR_COUNT))
		known_coverage += directional_demand[index] * pow(maxf(direction.dot(sector_direction), 0.0), 4.0)
	var commitment: float = focus_strength
	if peak_demand > 0.0:
		coverage = maxf(coverage, clampf(known_coverage / peak_demand, 0.0, 1.0))
		commitment = maxf(commitment, minf(total_directional_demand, 1.0))
	return (1.0 - coverage) * commitment


func detection_multiplier(direction: Vector2) -> float:
	var detection_quality: float = attention_quality * lerpf(1.0, 0.65, attention_switch_load)
	if focus_direction.is_zero_approx() or direction.is_zero_approx():
		return detection_quality
	var angle: float = absf(focus_direction.angle_to(direction))
	var half_width: float = clampf(attention_width * 0.5, 0.001, PI)
	var directional_rate: float = 1.0
	if angle <= half_width:
		directional_rate = lerpf(focus_detection_multiplier, 1.0, smoothstep(0.0, half_width, angle))
	else:
		directional_rate = lerpf(1.0, peripheral_detection_multiplier, smoothstep(half_width, PI, angle))
	return detection_quality * lerpf(1.0, directional_rate, focus_strength)


static func watch_reaction_alignment(direction: Vector2, focus: Vector2, width: float, strength: float) -> float:
	if direction.is_zero_approx() or focus.is_zero_approx():
		return 0.5
	var angle: float = absf(focus.angle_to(direction))
	var coverage: float = 1.0 - smoothstep(clampf(width * 0.5, 0.001, PI - 0.001), PI, angle)
	return lerpf(0.5, coverage, clampf(strength, 0.0, 1.0))


func _attention_quality(unit: Unit) -> float:
	# Small teams have fewer observers; casualties also reduce larger squads' capacity.
	var expected_size: int = maxi(unit.original_size, FULL_ATTENTION_MEMBERS)
	var quality: float = sqrt(clampf(float(unit.members_alive) / float(expected_size), 0.0, 1.0))
	if unit.combat_stats != null:
		quality *= lerpf(0.75, 1.0, clampf(unit.combat_stats.cohesion_current, 0.0, 1.0))
	if unit.stress_system != null:
		quality *= lerpf(1.0, 0.9, clampf(unit.stress_system.S_eff / 100.0, 0.0, 1.0))
		match unit.stress_system.state:
			STATES.MoraleState.CAUTIOUS:
				quality *= 0.9
			STATES.MoraleState.PINNED:
				quality *= 0.8
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
