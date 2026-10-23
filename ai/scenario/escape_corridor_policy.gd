class_name EscapeCorridorPolicy
extends RefCounted

const GUARDED_APPROACH_RADIUS: int = 2


static func blockers(snapshot: InfluenceSnapshot, team: int, cell: Vector2i, policy: EscapeMissionPolicy) -> Array[InfluenceContact]:
	return _blockers(snapshot, team, cell, policy, cell, false)


static func step_is_safe(snapshot: InfluenceSnapshot, team: int, origin: Vector2i, cell: Vector2i, policy: EscapeMissionPolicy) -> bool:
	return _blockers(snapshot, team, cell, policy, origin, true).is_empty()


static func route_visibility(snapshot: InfluenceSnapshot, team: int, cell: Vector2i) -> float:
	var visibility: float = 0.0
	for contact: InfluenceContact in snapshot.get_defensive_contacts(team):
		if contact.observed and not TacticalPositionExecutor.is_active_defender(contact.unit):
			continue
		var distance: int = LOSHelper.get_hex_distance(cell, contact.hex)
		var records: Dictionary = snapshot.los.get(contact.hex, {})
		if distance > contact.weapon_range or not records.has(cell):
			continue
		var record: Dictionary = records[cell]
		var hindrance: float = maxf(0.0, record.get("hindrance", 0.0))
		var concealment: float = maxf(0.0, record.get("target_concealment", 0.0))
		# Near crossings are easier to observe, even when current firepower is low.
		var observation: float = clampf(contact.confidence, 0.0, 1.0) * maxf(0.15, 1.0 - float(distance) / float(maxi(1, contact.weapon_range)))
		visibility = maxf(visibility, observation / (1.0 + hindrance + concealment))
	return visibility


static func _blockers(snapshot: InfluenceSnapshot, team: int, cell: Vector2i, policy: EscapeMissionPolicy, origin: Vector2i, disengaging: bool) -> Array[InfluenceContact]:
	var result: Array[InfluenceContact] = []
	var firing: Array[InfluenceContact] = []
	var incoming: float = 0.0
	var narrow: bool = _is_narrow_passage(snapshot, team, cell)
	var origin_narrow: bool = disengaging and _is_narrow_passage(snapshot, team, origin)
	for contact: InfluenceContact in snapshot.get_defensive_contacts(team):
		if not contact.observed or not TacticalPositionExecutor.is_active_defender(contact.unit):
			continue
		var distance: int = LOSHelper.get_hex_distance(cell, contact.hex)
		var suppressed: bool = TacticalPositionExecutor.is_sufficiently_suppressed(contact.unit)
		if distance == 0 or (distance <= 1 and not suppressed):
			result.append(contact)
		if suppressed or (distance > GUARDED_APPROACH_RADIUS and not narrow):
			continue
		# Seeing an open field makes it costly to cross, not an objective to assault.
		# Effective fire only seals a close guarded gap or a terrain bottleneck.
		var fire: Vector2 = _contact_fire(snapshot, contact, cell)
		if fire.x <= policy.maximum_bypass_visibility:
			continue
		var origin_distance: int = LOSHelper.get_hex_distance(origin, contact.hex)
		if disengaging and (origin_narrow or origin_distance <= GUARDED_APPROACH_RADIUS) and distance > origin_distance:
			var origin_fire: Vector2 = _contact_fire(snapshot, contact, origin)
			if origin_fire.x > policy.maximum_bypass_visibility and fire.x <= origin_fire.x and fire.y <= origin_fire.y:
				# A unit already under observation can leave it by moving away.
				continue
		incoming += fire.y
		firing.append(contact)
	if PositionFeatureEvaluator.risk(incoming) > policy.maximum_bypass_risk:
		for contact: InfluenceContact in firing:
			if not result.has(contact):
				result.append(contact)
	return result


static func _contact_fire(snapshot: InfluenceSnapshot, contact: InfluenceContact, cell: Vector2i) -> Vector2:
	# x is observation confidence; y is effective incoming fire.
	var distance: int = LOSHelper.get_hex_distance(cell, contact.hex)
	if contact.firepower <= 0.0 or contact.effectiveness <= 0.0 or distance > contact.weapon_range:
		return Vector2.ZERO
	var records: Dictionary = snapshot.los.get(contact.hex, {})
	if not records.has(cell):
		return Vector2.ZERO
	var hindrance: float = maxf(0.0, records[cell].get("hindrance", 0.0))
	var visibility: float = contact.confidence * maxf(0.15, 1.0 - float(distance) / float(maxi(1, contact.weapon_range))) / (1.0 + hindrance)
	var pressure: float = LosInfluenceProjector.calculate_los_fire_threat(contact.firepower,
		contact.effectiveness * contact.confidence, 0.0, hindrance, distance)
	return Vector2(visibility, pressure)


static func _is_narrow_passage(snapshot: InfluenceSnapshot, team: int, cell: Vector2i) -> bool:
	if not snapshot.routes.has(team) or not snapshot.point_ids.get(team, {}).has(cell):
		return false
	var graph: AStar2D = snapshot.routes[team]
	var id: int = snapshot.point_ids[team][cell]
	var available: int = 0
	for neighbor: int in graph.get_point_connections(id):
		if not graph.is_point_disabled(neighbor):
			available += 1
			if available > 2:
				return false
	return true
