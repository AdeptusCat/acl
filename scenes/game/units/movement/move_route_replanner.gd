class_name MoveRouteReplanner
extends RefCounted

const OBSERVATION_INTERVAL_SECONDS: float = 0.5
const COOLDOWN_SECONDS: float = 3.0
const MINIMUM_SAVING_SECONDS: float = 2.0
const MINIMUM_SAVING_FRACTION: float = 0.15

var unit: Unit
var destination: Vector2i
var order_id: int
var job: MoveRouteSearch
var pending: bool = false
var last_disposition: String = ""
var _observed: Dictionary[int, Dictionary] = {}
var _observation_elapsed: float = 0.0
var _cooldown: float = 0.0
var _contacts: Array[InfluenceContact] = []


func start(owner: Unit, target: Vector2i) -> void:
	unit = owner
	destination = target
	order_id = unit.action_controller.action_order_id
	_contacts = ThreatMap.capture_contacts(unit.team)
	_observed = _observations(_contacts)


func is_current() -> bool:
	if not is_instance_valid(unit) or not unit.is_active() or unit.surrendered or unit.broken or unit.in_close_combat:
		return false
	var movement: UnitMovement = unit.movement
	return unit.action_controller.action_order_id == order_id and movement.is_moving and not movement.attack_in_progress and not movement.retreating and movement.target_hex == destination and not movement.path_hexes.is_empty()


func observe(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_observation_elapsed += delta
	if _observation_elapsed < OBSERVATION_INTERVAL_SECONDS:
		return
	_observation_elapsed = 0.0
	_contacts = ThreatMap.capture_contacts(unit.team)
	var observed: Dictionary[int, Dictionary] = _observations(_contacts)
	for contact: InfluenceContact in _contacts:
		if not contact.observed or not is_instance_valid(contact.unit):
			continue
		var id: int = contact.unit.get_instance_id()
		if observed[id] != _observed.get(id, {}) and _threatens_remaining_path(contact):
			pending = true
	_observed = observed
	if pending and job == null and _cooldown <= 0.0:
		job = MoveRouteSearch.new()
		job.start(unit.movement, destination, _contacts)
		pending = false
		_cooldown = COOLDOWN_SECONDS


func advance(deadline_usec: int) -> void:
	if job != null and not job.completed:
		job.advance(deadline_usec)


func try_at_boundary() -> bool:
	if job == null or not job.completed or not is_current():
		return false
	if unit.position.distance_to(LOSHelper.ground_layer.map_to_local(unit.current_hex)) > 0.1:
		return false
	if unit.current_hex == destination:
		job = null
		return false
	var candidate_path: Array[Vector2i] = job.path_from(unit.current_hex)
	job = null
	var contacts: Array[InfluenceContact] = ThreatMap.capture_contacts(unit.team)
	var previous_path: Array[Vector2i] = remaining_path()
	var previous: MoveRoutePlanner = MoveRoutePlanner.new()
	previous.evaluate_path(previous_path, unit.team, unit.movement, contacts)
	var candidate: MoveRoutePlanner = MoveRoutePlanner.new()
	candidate.evaluate_path(candidate_path, unit.team, unit.movement, contacts)
	last_disposition = "retained_no_improvement"
	if candidate.path.size() < 2:
		last_disposition = "retained_no_route"
	var improvement: float = previous.cost - candidate.cost
	var required: float = maxf(MINIMUM_SAVING_SECONDS, previous.cost * MINIMUM_SAVING_FRACTION)
	var change: bool = candidate.path.size() >= 2 and not previous.path.is_empty() and improvement >= required and candidate.exposure_seconds < previous.exposure_seconds
	if change:
		last_disposition = "replanned"
		unit.movement.replace_remaining_move_path(candidate_path)
		_cooldown = COOLDOWN_SECONDS
	if is_instance_valid(Debug.engagement_recorder):
		var selected: MoveRoutePlanner = previous
		if change:
			selected = candidate
		Debug.engagement_recorder.record_move_route(unit, destination, selected, contacts, {"reason": "detected_threat", "disposition": last_disposition,
			"previous_cost": previous.cost, "previous_exposure_seconds": previous.exposure_seconds, "candidate_cost": candidate.cost,
			"candidate_exposure_seconds": candidate.exposure_seconds, "previous_path": previous_path, "candidate_path": candidate_path,
			"required_saving_seconds": required})
	return change


func remaining_path() -> Array[Vector2i]:
	var result: Array[Vector2i] = [unit.current_hex]
	for index: int in range(unit.movement.path_index, unit.movement.path_hexes.size()):
		var cell: Vector2i = unit.movement.path_hexes[index]
		if result[-1] != cell:
			result.append(cell)
	return result


func _threatens_remaining_path(contact: InfluenceContact) -> bool:
	for cell: Vector2i in remaining_path():
		if ThreatMap.risk_at(cell, [contact], LOSHelper.los_lookup) > 0.0:
			return true
	return false


func _observations(contacts: Array[InfluenceContact]) -> Dictionary[int, Dictionary]:
	var result: Dictionary[int, Dictionary] = {}
	for contact: InfluenceContact in contacts:
		if not contact.observed or not is_instance_valid(contact.unit):
			continue
		var capability: PackedInt32Array = PackedInt32Array()
		for power: float in contact.movement_firepower_by_range:
			capability.append(roundi(power * contact.effectiveness * 10.0))
		result[contact.unit.get_instance_id()] = {"hex": contact.hex, "range": contact.weapon_range, "capability": capability}
	return result
