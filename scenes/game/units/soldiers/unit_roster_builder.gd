extends RefCounted
class_name UnitRosterBuilder

# Synchronous UnitRosterBuilder operations; state and scene identity stay on the caller.


static func setup_runtime_soldiers(unit: Unit, _squad_loadout: SquadLoadoutSpec) -> void:
	unit.effective_range = 0
	if unit.squad_fire == null:
		return
	if _squad_loadout == null:
		return
	var list: Array[Soldier] = []
	var i: int = 0
	for soldier: SoldierLoadout in _squad_loadout.soldiers:
		var L: SoldierLoadout = soldier
		var spec: WeaponSpec = L.resolve_weapon()
		if spec == null:
			spec = unit.default_rifle
		spec = spec.create_runtime()
		if L.weapon != null and L.weapon.is_built_in():
			# Embedded save definitions must not become references to the save file.
			spec.source_resource_path = L.weapon_resource_path
		var s: Soldier = Soldier.new(
			i,
			L.nickname,
			L.rank_grade,
			L.role,   # if your Soldier.Role differs
			spec,
			unit,
			unit.team
		)
		if s.role == RankGrades.Role.GUNNER:
			unit.machine_guns += 1
		if spec.family == WeaponSpec.Family.MORTAR:
			unit.ui.set_ammunition_left(spec.ammunition)
		s.cadence_phase_s = randf_range(0.0, 3) # up to 0.2 s desync
		list.append(s)
		if spec.range_hexes > unit.effective_range:
			unit.effective_range = spec.range_hexes
		i += 1
	unit.squad_fire.set_soldiers(list)
	unit.squad_fire.casualties.clear()
	unit.casualty_records.clear()
	unit.members_alive = list.size()
	unit.original_size = unit.members_alive
	unit.casualties_taken = 0
	unit.ui.set_members_alive(unit.members_alive)


#func _setup_runtime_soldiers() -> void:
	#effective_range = 0
	#if squad_fire == null:
		#return
	#var list: Array[Soldier] = []
	#var i: int = 0
	#while i < loadouts.size():
		#var L: SoldierLoadout = loadouts[i]
		#var spec: WeaponSpec = L.weapon
		#if spec == null:
			#spec = default_rifle
		#var s: Soldier = Soldier.new(
			#i,
			#L.nickname,
			#L.rank_grade,
			#_map_role(L.role),   # if your Soldier.Role differs
			#spec,
			#self,
			#team
		#)
		#if s.role == RankGrades.Role.GUNNER:
			#machine_guns += 1
		#spec.ammunition = spec.ammunition_start
		#if spec.family == WeaponSpec.Family.MORTAR:
			#ui.set_ammunition_left(spec.ammunition)
		#s.cadence_phase_s = randf_range(0.0, 3) # up to 0.2 s desync
		#list.append(s)
		#if spec.range_hexes > effective_range:
			#effective_range = spec.range_hexes
		#i += 1
	#squad_fire.set_soldiers(list)
