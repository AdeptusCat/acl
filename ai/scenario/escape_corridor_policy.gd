class_name EscapeCorridorPolicy
extends RefCounted


static func blockers(snapshot: InfluenceSnapshot, team: int, cell: Vector2i, policy: EscapeMissionPolicy) -> Array[InfluenceContact]:
	var result: Array[InfluenceContact] = []
	var firing: Array[InfluenceContact] = []
	var incoming: float = 0.0
	for contact: InfluenceContact in snapshot.get_defensive_contacts(team):
		if not contact.observed or not TacticalPositionExecutor.is_active_defender(contact.unit):
			continue
		var distance: int = LOSHelper.get_hex_distance(cell, contact.hex)
		var suppressed: bool = TacticalPositionExecutor.is_sufficiently_suppressed(contact.unit)
		if distance == 0 or (distance <= 1 and not suppressed):
			result.append(contact)
		if suppressed or contact.firepower <= 0.0 or contact.effectiveness <= 0.0 or distance > contact.weapon_range:
			continue
		var records: Dictionary = snapshot.los.get(contact.hex, {})
		if not records.has(cell):
			continue
		var hindrance: float = maxf(0.0, records[cell].get("hindrance", 0.0))
		var visibility: float = contact.confidence * maxf(0.15, 1.0 - float(distance) / float(maxi(1, contact.weapon_range))) / (1.0 + hindrance)
		if visibility > policy.maximum_bypass_visibility and not result.has(contact):
			result.append(contact)
		incoming += LosInfluenceProjector.calculate_los_fire_threat(contact.firepower,
			contact.effectiveness * contact.confidence, 0.0, hindrance, distance)
		firing.append(contact)
	if PositionFeatureEvaluator.risk(incoming) > policy.maximum_bypass_risk:
		for contact: InfluenceContact in firing:
			if not result.has(contact):
				result.append(contact)
	return result
