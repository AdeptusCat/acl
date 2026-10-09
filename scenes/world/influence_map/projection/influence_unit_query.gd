class_name InfluenceUnitQuery
extends RefCounted


static func get_config_units(team: int, group_name: String) -> Array[Unit]:
	var result: Array[Unit] = []
	var units: Array[Unit] = Globals.get_units_for_team(team)

	for unit: Unit in units:
		if not is_valid_living_unit(unit):
			continue

		if group_name != "":
			if not unit.is_in_group(group_name):
				continue

		result.append(unit)

	return result


static func is_valid_living_unit(unit: Unit) -> bool:
	if not is_instance_valid(unit):
		return false

	if not unit.alive:
		return false

	return true


static func get_unit_firepower(unit: Unit) -> float:
	return get_firepower_at_range(unit, 0)


static func get_defensive_mount(unit: Unit) -> WeaponSpec.Mount:
	var mount: WeaponSpec.Mount = WeaponSpec.Mount.NONE
	if not is_valid_living_unit(unit):
		return mount
	# Runtime equipment is authoritative after casualties and weapon transfers.
	# A jam or reload must not rotate the platoon's stationary guard.
	if unit.squad_fire != null:
		for soldier: Soldier in unit.squad_fire.soldiers:
			if soldier.is_alive:
				mount = _stronger_mg_mount(mount, soldier.weapon)
		return mount
	var loadouts: Array[SoldierLoadout] = unit.loadouts
	if unit.squad_loadout != null:
		loadouts = unit.squad_loadout.soldiers
	for loadout: SoldierLoadout in loadouts:
		if loadout != null:
			mount = _stronger_mg_mount(mount, loadout.resolve_weapon())
	return mount


static func _stronger_mg_mount(current: WeaponSpec.Mount, weapon: WeaponSpec) -> WeaponSpec.Mount:
	if weapon == null or weapon.type != WeaponSpec.WeaponType.MG:
		return current
	if weapon.mount > current:
		return weapon.mount
	return current


static func get_firepower_at_range(unit: Unit, distance: int) -> float:
	if not is_valid_living_unit(unit) or unit.surrendered:
		return 0.0
	if unit.squad_fire == null:
		if distance > unit.weapon_range:
			return 0.0
		return float(unit.firepower) / 4.0
	var power: float = 0.0
	for soldier: Soldier in unit.squad_fire.soldiers:
		if not soldier.is_alive or soldier.weapon == null or soldier.jammed:
			continue
		var weapon: WeaponSpec = soldier.weapon
		if weapon.ammunition <= 0 or distance > weapon.range_hexes:
			continue
		var rounds: float = float(maxi(weapon.burst_rounds, 1))
		var cycle: float = rounds * 60.0 / maxf(weapon.rpm, 1.0) + weapon.burst_pause_s
		cycle += rounds * weapon.reload_s / float(maxi(weapon.mag_capacity, 1))
		var crew_factor: float = 1.0
		if weapon.crew_required > 1:
			crew_factor = minf(1.0, float(unit.members_alive) / float(weapon.crew_required))
		power += minf(rounds / maxf(cycle, 0.1), 8.0) * clampf(weapon.accuracy_base, 0.0, 1.0) * crew_factor
	return power / 4.0


static func get_unit_range(unit: Unit) -> int:
	if unit.squad_fire == null:
		return unit.weapon_range
	var result: int = 0
	for soldier: Soldier in unit.squad_fire.soldiers:
		if soldier.is_alive and soldier.weapon != null and soldier.weapon.ammunition > 0:
			result = maxi(result, soldier.weapon.range_hexes)
	return result


static func get_unit_effectiveness(unit: Unit) -> float:
	if unit.combat_stats != null:
		return clampf(unit.combat_stats.combat_effectiveness, 0.0, 1.0)
	if unit.stress_system != null:
		return clampf(1.0 - unit.stress_system.S_eff / 100.0, 0.0, 1.0)
	return 1.0


static func capture_contacts(team: int, policy: int) -> Array[InfluenceContact]:
	var known: Dictionary = {}
	var now: float = float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)
	for observer: Unit in get_config_units(team, ""):
		for enemy: Unit in observer.enemy_memory:
			if not is_instance_valid(enemy):
				continue
			var memory: Dictionary = observer.enemy_memory[enemy]
			var age: float = now - float(memory.get("last_seen_time", -INF))
			if age < 0.0 or age > Unit.ENEMY_MEMORY_LIFETIME:
				continue
			var contact: InfluenceContact = InfluenceContact.new()
			contact.unit = enemy
			contact.hex = memory.get("last_seen_hex", Vector2i.ZERO)
			contact.confidence = 1.0 - age / Unit.ENEMY_MEMORY_LIFETIME
			contact.last_seen_at = memory.get("last_seen_time", now)
			contact.crossing_seconds = memory.get("crossing_seconds", 2.0)
			# Memory uses captured capability, never a hidden live loadout/state.
			contact.firepower = memory.get("firepower", 1.0)
			contact.effectiveness = memory.get("effectiveness", 1.0)
			contact.weapon_range = memory.get("weapon_range", 6)
			if not known.has(enemy) or contact.confidence > known[enemy].confidence:
				known[enemy] = contact
	var observed: Array = []
	for observer: Unit in get_config_units(team, ""):
		for enemy: Unit in Globals.unit_visible_enemies.get(observer, []):
			if not observed.has(enemy):
				observed.append(enemy)
	if policy == 1:
		observed = Globals.get_units_for_team(Globals.get_enemy_team(team))
	for enemy: Unit in observed:
		if not is_valid_living_unit(enemy) or enemy.team == team:
			continue
		var contact: InfluenceContact = InfluenceContact.new()
		contact.unit = enemy
		contact.hex = enemy.current_hex
		contact.firepower = get_unit_firepower(enemy)
		contact.effectiveness = get_unit_effectiveness(enemy)
		contact.weapon_range = get_unit_range(enemy)
		contact.observed = true
		contact.last_seen_at = now
		contact.crossing_seconds = captured_crossing_seconds(enemy)
		known[enemy] = contact
	var result: Array[InfluenceContact] = []
	for contact: InfluenceContact in known.values():
		result.append(contact)
	return result


static func captured_crossing_seconds(unit: Unit) -> float:
	if unit.movement == null or not is_instance_valid(LOSHelper.ground_layer):
		return 2.0
	var origin: Vector2 = LOSHelper.ground_layer.map_to_local(unit.current_hex)
	var neighbor: Vector2i = LOSHelper.get_hex_neighbors(unit.current_hex)[0]
	return unit.movement.estimate_travel_seconds(origin, LOSHelper.ground_layer.map_to_local(neighbor), 1.0)


static func get_squad_type_priority(squad_type: Globals.SquadType) -> int:
	if squad_type == Globals.SquadType.MG:
		return 0

	if squad_type == Globals.SquadType.Rifle:
		return 1

	if squad_type == Globals.SquadType.PLATOON_HEADQUARTERS:
		return 2

	if squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
		return 3

	if squad_type == Globals.SquadType.ANTITANK:
		return 4

	if squad_type == Globals.SquadType.MORTAR:
		return 5

	return 999


static func compare_units_by_squad_type_priority(unit_a: Unit, unit_b: Unit) -> bool:
	var priority_a: int = get_squad_type_priority(unit_a.squad_type)
	var priority_b: int = get_squad_type_priority(unit_b.squad_type)

	if priority_a == priority_b:
		return unit_a.get_instance_id() < unit_b.get_instance_id()

	return priority_a < priority_b
