class_name DefensiveContactMemory
extends RefCounted

# Tactical danger persists beyond a firing track. Only captured observations update it.
const CONFIDENCE_DECAY_SECONDS: float = 30.0
const MIN_CONFIDENCE: float = 0.5

var contacts_by_team: Dictionary[int, Dictionary] = {}


func clear() -> void:
	contacts_by_team.clear()


func capture_into(snapshot: InfluenceSnapshot) -> void:
	for team: int in snapshot.maps:
		var remembered: Dictionary = contacts_by_team.get(team, {})
		var observed: Array[Unit] = []
		for contact: InfluenceContact in snapshot.get_contacts(team):
			if not is_instance_valid(contact.unit):
				continue
			var seen_at: float = snapshot.captured_at
			if not contact.observed:
				seen_at -= (1.0 - contact.confidence) * Unit.ENEMY_MEMORY_LIFETIME
			else:
				observed.append(contact.unit)
			if contact.observed or not remembered.has(contact.unit) or seen_at > remembered[contact.unit]["seen_at"] + 0.000001:
				remembered[contact.unit] = {"contact": _copy_contact(contact), "seen_at": seen_at}
		var captured: Array[InfluenceContact] = []
		for key: Variant in remembered.keys():
			if not is_instance_valid(key):
				remembered.erase(key)
				continue
			var unit: Unit = key
			if _reported_destroyed(snapshot, team, unit):
				remembered[unit]["cleared"] = true
				remembered[unit]["seen_at"] = snapshot.captured_at
			if remembered[unit].get("cleared", false):
				continue
			var contact: InfluenceContact = _copy_contact(remembered[unit]["contact"])
			# Physically checking the old hex clears it; loss of LOS alone never does.
			if not observed.has(unit) and _friendly_occupies(snapshot, team, contact.hex):
				remembered[unit]["cleared"] = true
				remembered[unit]["seen_at"] = snapshot.captured_at
				continue
			var age: float = maxf(0.0, snapshot.captured_at - remembered[unit]["seen_at"])
			contact.confidence = maxf(MIN_CONFIDENCE, 1.0 - age / CONFIDENCE_DECAY_SECONDS)
			contact.observed = observed.has(unit)
			captured.append(contact)
		contacts_by_team[team] = remembered
		snapshot.defensive_contacts[team] = captured


static func _friendly_occupies(snapshot: InfluenceSnapshot, team: int, cell: Vector2i) -> bool:
	for unit: Unit in snapshot.positions:
		if snapshot.teams[unit] == team and snapshot.positions[unit] == cell:
			return true
	return false


static func _reported_destroyed(snapshot: InfluenceSnapshot, team: int, enemy: Unit) -> bool:
	for observer: Unit in snapshot.positions:
		if snapshot.teams[observer] == team and Globals.unit_visible_enemies.get(observer, []).has(enemy):
			return not enemy.alive
	return false


static func _copy_contact(source: InfluenceContact) -> InfluenceContact:
	var contact: InfluenceContact = InfluenceContact.new()
	contact.unit = source.unit
	contact.hex = source.hex
	contact.confidence = source.confidence
	contact.firepower = source.firepower
	contact.effectiveness = source.effectiveness
	contact.weapon_range = source.weapon_range
	contact.observed = source.observed
	return contact
