extends RefCounted
class_name UnitCasualtyHandler

# Synchronous UnitCasualtyHandler operations; state and scene identity stay on the caller.


static func apply_specific_casualty(unit: Unit, casualty: Soldier) -> bool:
	for soldier: Soldier in unit.squad_fire.soldiers:
		if soldier == casualty:
			var members_alive_before: int = unit.squad_fire.soldiers.size()
			
			var leader_down: bool = false
			
			# record which non-rifle roles were lost and what crew-served weapons got orphaned
			var roles_lost: Array[int] = []
			var dropped_support: Array[WeaponSpec] = []
			if casualty.role != RankGrades.Role.SOLDIER:
				if not roles_lost.has(casualty.role):
					roles_lost.append(casualty.role)
			if casualty.role == RankGrades.Role.GUNNER:
				if casualty.weapon != null:
					dropped_support.append(casualty.weapon)
			
			unit.weapon_audio.stop_mg_loop(casualty.weapon, unit.position, soldier.id, unit)
			unit._record_casualty(casualty)
			unit.squad_fire.casualties.append(casualty)
			unit.casualties_taken = unit.squad_fire.casualties.size()
			unit.combat_stats.notify_casualty_taken(1)
			
			# Editor loadouts are definitions; only the runtime roster loses soldiers.
			unit.squad_fire.soldiers.erase(casualty)
			
			unit.effective_range = 0
			for s: Soldier in unit.squad_fire.soldiers:
				if s.weapon.range_hexes > unit.effective_range:
					unit.effective_range = s.weapon.range_hexes

			## debug
			#if n != casualty_indexes.size():
				#pass

			# book-keeping and UI
			unit.members_alive = unit.squad_fire.soldiers.size()
			
			unit.stress_system.on_casualty_event(1, leader_down)
			unit.ui.set_members_alive(unit.members_alive)

			if members_alive_before == unit.members_alive:
				pass
			# if the whole lot’s gone, we’re done
			if unit.members_alive <= 0:
				
				return true

			# 1) replace leader if needed: ASL first, else any SOLDIER
			if roles_lost.has(RankGrades.Role.SQUAD_LEADER) or leader_down:
				unit._promote_new_leader()
			
			# 2) re-crew any dropped guns (e.g., MG) — loader preferred as new gunner
			var g: int = 0
			while g < dropped_support.size():
				var wp: WeaponSpec = dropped_support[g]
				unit._assign_gunner_and_loader_for_weapon(wp)
				g += 1

			# 3) if we lost a loader but the gun’s still in the squad, top up loaders
			if roles_lost.has(RankGrades.Role.LOADER):
				unit._fill_missing_loaders_for_existing_guns()

			# optional: if you maintain any cached fire stats, rebuild them now
			# squad_fire.rebuild_cached_stats()
			# emit signals as needed
			# emit_signal("casualties_taken", original_size - members_alive)
			
			unit.ui.show_casualty()
			unit.soldiers_changed.emit()
			# FIXME stress through casualty from close combat or other particular event should not be fixed value
			unit.stress_system.apply_stress(10.0, 10.0)
			unit.ui.set_loadout(unit.squad_fire.soldiers)
			unit._refresh_leader_aura()
			unit.leader_aura._affected.erase(unit)
			unit.leader_aura._apply_to(unit)
	return false

# --- casualties, role replacement, and support-weapon re-crewing ---


static func apply_casualties(unit: Unit, n: int) -> void:
	var members_alive_before: int = unit.squad_fire.soldiers.size()
	var casualty_count: int = clampi(n, 0, members_alive_before)
	if casualty_count == 0:
		return
	unit.combat_stats.notify_casualty_taken(casualty_count)
	var casualty_indexes: Array[int] = unit.get_unique_random_ints(casualty_count, members_alive_before)

	var leader_down: bool = false
	#if leader_alive:
		#var denom: int = max(1, members_alive + 1)
		#var p_leader: float = 1.0 / float(denom)
		#if randf() < p_leader:
			#leader_alive = false
			#leader_down = true
			## the old boss is gone; stress bonus collapses until we promote
			#stress_system.leadership_bonus = 0.0

	# capture the actual Soldier objects before we remove them from arrays
	var casualties: Array[Soldier] = []
	var i_idx: int = 0
	while i_idx < casualty_indexes.size():
		var s_idx: int = casualty_indexes[i_idx]
		if s_idx >= 0 and s_idx < unit.squad_fire.soldiers.size():
			var soldier: Soldier = unit.squad_fire.soldiers[s_idx]
			casualties.append(soldier)
		i_idx += 1

	# record which non-rifle roles were lost and what crew-served weapons got orphaned
	var roles_lost: Array[int] = []
	var dropped_support: Array[WeaponSpec] = []
	var c: int = 0
	while c < casualties.size():
		var s: Soldier = casualties[c]
		if s.role != RankGrades.Role.SOLDIER:
			if not roles_lost.has(s.role):
				roles_lost.append(s.role)
		if s.role == RankGrades.Role.GUNNER:
			if s.weapon != null:
				dropped_support.append(s.weapon)
		c += 1
	
	for soldier: Soldier in casualties:
		unit.weapon_audio.stop_mg_loop(soldier.weapon, unit.position, soldier.id, unit)
		unit._record_casualty(soldier)
		# FIXME this should fix the out of bounds
		unit.squad_fire.casualties.append(soldier)
	
	unit.casualties_taken = unit.squad_fire.casualties.size()
	#for index in casualty_indexes:
		# FIXME this tends to be out of bounds
		#if squad_fire.soldiers.size() > index:
			#squad_fire.casualties.append(squad_fire.soldiers[index])
	
	# Editor loadouts are definitions; only the runtime roster loses soldiers.
	unit.remove_indices(unit.squad_fire.soldiers, casualty_indexes)
	
	unit.effective_range = 0
	for soldier: Soldier in unit.squad_fire.soldiers:
		if soldier.weapon.range_hexes > unit.effective_range:
			unit.effective_range = soldier.weapon.range_hexes

	# debug
	if casualty_count != casualty_indexes.size():
		pass

	# book-keeping and UI
	unit.members_alive = unit.squad_fire.soldiers.size()
	
	unit.stress_system.on_casualty_event(casualty_count, leader_down)
	unit.ui.set_members_alive(unit.members_alive)
	
	if members_alive_before == unit.members_alive:
		pass
	# if the whole lot’s gone, we’re done
	if unit.members_alive <= 0:
		unit._set_combat_ineffective()
		return

	# 1) replace leader if needed: ASL first, else any SOLDIER
	if roles_lost.has(RankGrades.Role.SQUAD_LEADER) or leader_down:
		unit.embedded_leader_alive = false
		unit.combat_stats.notify_leader_killed()
		unit._promote_new_leader()
	
	# 2) re-crew any dropped guns (e.g., MG) — loader preferred as new gunner
	var g: int = 0
	while g < dropped_support.size():
		var wp: WeaponSpec = dropped_support[g]
		unit._assign_gunner_and_loader_for_weapon(wp)
		g += 1

	# 3) if we lost a loader but the gun’s still in the squad, top up loaders
	if roles_lost.has(RankGrades.Role.LOADER):
		unit._fill_missing_loaders_for_existing_guns()
	
	# optional: if you maintain any cached fire stats, rebuild them now
	# squad_fire.rebuild_cached_stats()
	# emit signals as needed
	# emit_signal("casualties_taken", original_size - members_alive)



# ---------- helpers (typed, no ternarys) ----------


static func promote_new_leader(unit: Unit) -> void:
	var idx_asl: int = unit._index_of_role(RankGrades.Role.ASSISTANT_SQUAD_LEADER)
	var new_leader_idx: int = idx_asl
	if new_leader_idx == -1:
		new_leader_idx = unit._find_first_SOLDIER()
	if new_leader_idx != -1:
		var s: Soldier = unit.squad_fire.soldiers[new_leader_idx]
		s.role = RankGrades.Role.SQUAD_LEADER
		#leader_alive = true
		
		# if you track graded leadership, update bonus here instead of this placeholder:
		# stress_system.leadership_bonus = _compute_leadership_bonus_for(s)
	else:
		# no one left to lead; keep leader_alive false and bonus at 0
		pass


static func assign_gunner_and_loader_for_weapon(unit: Unit, wp: WeaponSpec) -> void:
	if wp == null:
		return

	# pick gunner: prefer an existing loader, else any SOLDIER
	var gunner_idx: int = unit._index_of_role(RankGrades.Role.LOADER)
	if gunner_idx == -1:
		gunner_idx = unit._find_first_SOLDIER()
	if gunner_idx == -1:
		# no hands left to serve the gun
		return

	var gunner: Soldier = unit.squad_fire.soldiers[gunner_idx]
	gunner.role = RankGrades.Role.GUNNER
	gunner.weapon = wp

	# ensure loader if weapon wants a crew
	if wp.crew_required > 1:
		var loader_idx: int = unit._find_first_SOLDIER_OR_ASSISTANT_excluding([gunner_idx])
		if loader_idx != -1:
			var loader: Soldier = unit.squad_fire.soldiers[loader_idx]
			loader.role = RankGrades.Role.LOADER
			# loaders generally don’t carry the weapon object; the gun sits on the gunner
		else:
			# under-crewed; your fire calc should already scale with wp.undercrew_penalty_exp
			pass
	if wp.support_crew_optimal > 0:
		var support_idx: int = unit._find_first_SOLDIER_OR_ASSISTANT_excluding([gunner_idx])
		if support_idx != -1:
			var support: Soldier = unit.squad_fire.soldiers[support_idx]
			support.role = RankGrades.Role.ASSISTANT
			# loaders generally don’t carry the weapon object; the gun sits on the gunner
		else:
			# under-crewed; your fire calc should already scale with wp.undercrew_penalty_exp
			pass


static func fill_missing_loaders_for_existing_guns(unit: Unit) -> void:
	# for each gunner with a crew-served, ensure there is at least one loader in the squad
	var has_loader: bool = unit._has_role(RankGrades.Role.LOADER)
	if has_loader:
		return

	var i: int = 0
	while i < unit.squad_fire.soldiers.size():
		var s: Soldier = unit.squad_fire.soldiers[i]
		if s.role == RankGrades.Role.GUNNER and not s.weapon == null:
			if s.weapon.crew_required > 1:
				var idx: int = unit._find_first_SOLDIER_OR_ASSISTANT_excluding([i])
				if not idx == -1:
					var loader: Soldier = unit.squad_fire.soldiers[idx]
					loader.role = RankGrades.Role.LOADER
				# if still none, we stay under-crewed
		i += 1


static func index_of_role(unit: Unit, role: int) -> int:
	var i: int = 0
	while i < unit.squad_fire.soldiers.size():
		var s: Soldier = unit.squad_fire.soldiers[i]
		if s.role == role:
			return i
		i += 1
	return -1


static func has_role(unit: Unit, role: int) -> bool:
	var i: int = 0
	while i < unit.squad_fire.soldiers.size():
		var s: Soldier = unit.squad_fire.soldiers[i]
		if s.role == role:
			return true
		i += 1
	return false


static func find_first_SOLDIER(unit: Unit) -> int:
	var i: int = 0
	while i < unit.squad_fire.soldiers.size():
		var s: Soldier = unit.squad_fire.soldiers[i]
		if s.role == RankGrades.Role.SOLDIER:
			if not s.weapon.can_fire_riflegrenades:
				return i
		i += 1
	return -1


static func find_first_SOLDIER_OR_ASSISTANT_excluding(unit: Unit, exclude: Array[int]) -> int:
	var i: int = 0
	while i < unit.squad_fire.soldiers.size():
		if not exclude.has(i):
			var s: Soldier = unit.squad_fire.soldiers[i]
			if s.role == RankGrades.Role.SOLDIER or s.role == RankGrades.Role.ASSISTANT:
				if not s.weapon.can_fire_riflegrenades:
					return i
		i += 1
	return -1


static func remove_indices(unit: Unit, target: Array, indices: Array[int]) -> void:
	# Sort descending so the higher indices go first
	indices.sort()
	indices.reverse()

	var i: int = 0
	while i < indices.size():
		var idx: int = indices[i]
		if idx >= 0 and idx < target.size():
			target.remove_at(idx)
		i += 1


static func get_unique_random_ints(unit: Unit, n: int, _max: int) -> Array[int]:
	var all_nums: Array[int] = []
	var i: int = 0
	while i < _max:
		all_nums.append(i)
		i += 1
	all_nums.shuffle()
	return all_nums.slice(0, n)
