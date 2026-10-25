extends RefCounted
class_name SquadHitResolver

# Synchronous SquadHitResolver operations; state and scene identity stay on the caller.


static func fire_at(controller: SquadFireController, total_rounds: int, weapon: WeaponSpec, riflegrenade: bool, _target_hex: Vector2i, target_distance: int, target_cover: int, batch_targets: Array[Unit], shot_origin: Vector2 = Vector2.INF) -> void:
	# debug
	#return
	#if not riflegrenade:
		#return
	#if not weapon.family == WeaponSpec.Family.ROCKET_LAUNCHER:
		#return
	#if not weapon.ammo_type == WeaponSpec.AmmoType.HE and not riflegrenade:
		#return
	# FIXME units should not break when pinned but stress level not full
	# TODO refactor fire functions
	# TODO riflegrenate hits instant?
	controller.add_fire_impulse(total_rounds, 10)
	if not shot_origin.is_finite():
		shot_origin = controller.unit.global_position
	var terrain_defense_bonus: float = target_cover
	if weapon.family == WeaponSpec.Family.MORTAR:
		terrain_defense_bonus = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(_target_hex))

	# --- collect all enemy squads in the target hex ---
	#var batch_targets: Array = []
	#batch_targets = LOSHelper.find_units_at(_target_hex)

	
	#var visible_enemies: Array = Globals.unit_visible_enemies.get(get_parent(), [])
	#if weapon.family == WeaponSpec.Family.MORTAR:
		#for u in Globals.units:
			#if is_instance_valid(u):
				#if u.alive:
					#if not u.surrendered:
						#if u.current_hex == _mortar_target_hex:
							#batch_targets.append(u)
	#else:
		#for u in visible_enemies:
			#if is_instance_valid(u):
				#if u.alive:
					#if not u.surrendered:
						#if u.current_hex == target_hex:
							#batch_targets.append(u)
	
	# FIXME units that are not seen should not be as easily hit
	if controller.unit.team == Globals.Team.ALLIES:
		pass
	for _unit: Unit in Globals.get_units():
		if _unit.current_hex == _target_hex:
			if not batch_targets.has(_unit):
				batch_targets.append(_unit)
	# Projectiles retain their original target list while flying.
	for target: Unit in batch_targets.duplicate():
		if not is_instance_valid(target) or not target.is_active():
			batch_targets.erase(target)
	
	if batch_targets.is_empty():
		# no enemys to be hit
		return
	
	# --- prep per-squad data: cover/exposure & hit prob (same maths as resolve_volley) ---
	# We keep exposure simple here (1.0). If you’ve got per-squad exposure, plug it in.
	var _base_accuracy: float = 0.35
	
	var state_mod: Dictionary = STATES.STATE_MOD[controller.unit.stress_system.state]
	var state_acc_mod: float = state_mod.acc
	
	#var to_hit_distance_mod: float = clamp(1.0 - float(target_distance) * 0.002, 0.1, 1.0)
	var to_hit_distance_mod: float = float(target_distance) / float(weapon.range_hexes)
	to_hit_distance_mod = clamp(1.0 - to_hit_distance_mod, 0.0, 1.0)
	
	var cover_mod: float = SquadFireMath.hit_cover_multiplier(terrain_defense_bonus, weapon.family == WeaponSpec.Family.MORTAR)
	
	var shooter_stress: float = 0.0
	if controller.unit and "stress_system" in controller.unit:
		shooter_stress = float(controller.unit.stress_system.S_eff)
	
	var shooter_stress_mod: float = lerp(0.4, 1.0, 1.0 - (shooter_stress / 100.0))
	
	var chance_to_hit: float = controller.base_accuracy * state_acc_mod
	chance_to_hit *= to_hit_distance_mod
	chance_to_hit *= cover_mod
	chance_to_hit *= shooter_stress_mod
	chance_to_hit *= SquadFireMath.point_blank_hit_multiplier(target_distance)
	if riflegrenade == true:
		if target_distance <= weapon.riflegrenade_range:
			chance_to_hit *= 4
		else:
			chance_to_hit *= 2
	if weapon.family == WeaponSpec.Family.SPIGOT_LAUNCHER or weapon.family == WeaponSpec.Family.ROCKET_LAUNCHER or weapon.family == WeaponSpec.Family.MORTAR:
		if target_distance <= weapon.range_hexes:
			chance_to_hit *= 4
		else:
			chance_to_hit *= 2
	
	var n_targets: int = batch_targets.size()
	var chance_to_hit_per_target: Array = []
	
	# --- slower recovery while under fire ---
	var incoming_rounds: float = float(total_rounds)
	var j: int = 0
	while j < n_targets:
		var u_mark: Node = batch_targets[j]
		if "stress_system" in u_mark:
			var sc: StressController = u_mark.stress_system as StressController
			if sc != null:
				sc.mark_under_fire(incoming_rounds)
		j += 1

	var i: int = 0
	while i < n_targets:
		var u: Unit = batch_targets[i]
		
		# only visual update
		u.set_cover(int(terrain_defense_bonus))
		u.receive_fire(terrain_defense_bonus)
		
		var state: STATES.MoraleState = u.stress_system.state
		var target_chance_to_hit: float = chance_to_hit
		if state == STATES.MoraleState.PANIC:
			target_chance_to_hit *= 4
		if state == STATES.MoraleState.PINNED:
			target_chance_to_hit *= 0.2
		
		target_chance_to_hit = clampf(target_chance_to_hit, 0.00001, 0.95)
		chance_to_hit_per_target.append(target_chance_to_hit)
		i += 1

	# --- assign each round to ONE squad and roll the hit there ---
	# Even assignment chance; to weight, build a weight list and roulette-pick.
	var hits_per_target: Array = []
	i = 0
	while i < n_targets:
		hits_per_target.append(0)
		i += 1
	
	#var enclosure_factor: float = 1.0
	i = 0
	if riflegrenade == true or weapon.ammo_type == WeaponSpec.AmmoType.HE:
		if weapon.type == WeaponSpec.Family.MORTAR:
			if terrain_defense_bonus == 1: # reflects airbursts in wood # TODO reflect airbursts betterds
				cover_mod = 1.5
		#var max_possible_casualties: float = weapon.he_burst_radius # * cover_mod #* burst_quality
		# TODO HE weapons should hit multiple target but a bit more elaborate
		var max_possible_casualties: float = weapon.he_burst_radius
		#if riflegrenade:
			#max_possible_casualties
		while i < n_targets:
			var ii: int = 0
			while ii < max_possible_casualties:
				var p_hit: float = float(chance_to_hit_per_target[i])
				p_hit = p_hit - (randf_range(0.01, p_hit * 0.1) * ii)
				p_hit = clamp(p_hit, 0.00001, 0.95)
				var roll : float = randf()
				if roll < p_hit:
					hits_per_target[i] = int(hits_per_target[i]) + 1
				ii += 1
			i += 1
	else:
		i = 0
		while i < total_rounds:
			# pick recipient squad
			var idx: int = randi() % n_targets
			# roll hit with that squad's p
			var p_hit: float = float(chance_to_hit_per_target[idx])
			var roll : float = randf()
			if roll < p_hit:
				hits_per_target[idx] = int(hits_per_target[idx]) + 1
			i += 1
	
	if target_cover == 0.0:
		pass
	
	# --- convert hits → casualties per squad (multi-cas possible, sensible cap) ---
	# Decide per-hit disable based on weapon; here we default to rifle numbers
	var chance_to_disable: float = 0.12
	if riflegrenade == true or weapon.ammo_type == WeaponSpec.AmmoType.HE:
		chance_to_disable = 0.5

	# Range and cover reduce *lethality* further (separate from hit chance)
	# this should not matter when firing explosives
	#var lethality_range_mult: float = _range_lethality_mult(target_distance, int(unit.weapon_range))
	var lethality_range_mod: float = float(target_distance) / float(weapon.range_hexes)
	lethality_range_mod = clamp(1.0 - lethality_range_mod, 0.0, 1.0)
	if riflegrenade == true or weapon.ammo_type == WeaponSpec.AmmoType.HE:
		lethality_range_mod = 1.0

	# the idea here is that hard cover also modifies lethallity and not just accuracy, but needs rework
	#var lethality_cover_mult: float = lerp(lethality_cover_min, lethality_cover_max, 1.0 - cover_norm)
	#var lethality_cover_mult: float = lerp(0.6, 1.0, 1.0 - (target_cover / 5)) # what does this?
	var lethality_cover_mult: float = controller.cover_multiplier_exp(terrain_defense_bonus)
	#lethality_cover_mult *= lethality_cover_mult

	# Final per-hit disable after all throttles
	chance_to_disable = chance_to_disable * lethality_range_mod * lethality_cover_mult * controller.casualty_scale
	if chance_to_disable < 0.01:
		chance_to_disable = 0.01  # tiny floor so hits can still matter

	# Convert hits → casualties with a capped, smooth hazard form
	# lambda = hits * p_disable_final;  p_cas = 1 - exp(-lambda)
	# This scales gently and avoids huge spikes.
	var casualties_per_target: Array = []
	var target_i: int = 0
	while target_i < n_targets:
		var hits_i: int = int(hits_per_target[target_i])
		var casualties_i: int = 0

		if hits_i > 0:
			var lambda_val: float = float(hits_i) * chance_to_disable
			var p_cas: float = 1.0 - exp(-lambda_val)
			
			var d: int = 0
			while d < hits_i:
				if randf() < p_cas:
					casualties_i += 1
				else:
					casualties_i += 0
				d += 1

		# Never exceed living heads, if present
		var u_chk: Node = batch_targets[target_i]
		if "members_alive" in u_chk:
			if casualties_i > int(u_chk.members_alive):
				casualties_i = int(u_chk.members_alive)
	
		#casualties_i = u_chk.members_alive
		casualties_per_target.append(casualties_i)
		target_i += 1


	# --- shared base stress, before each squad's attention modifiers ---
	var mean_chance_to_hit: float = controller._get_mean_change_to_hit(chance_to_hit_per_target, n_targets)

	# base fast shock + how “accurate” incoming fire looks
	var s_fast: float = mean_chance_to_hit * (controller.stress_fast_hit_factor + controller.stress_fast_base) * float(total_rounds)
	#var s_fast: float = stress_fast_base + mean_chance_to_hit * stress_fast_hit_factor * float(total_rounds)

	# slow stress grows with sheer volume; cover damps it
	var s_slow: float = float(total_rounds) #* stress_slow_per_round
	
	# apply cover damp to stress (not boost!)
	var stress_cover_mod: float = controller.cover_multiplier_exp(terrain_defense_bonus) # 1 cover = 1.0; 3 cover = 0.63
	#if riflegrenade or weapon.family == WeaponSpec.Family.MORTAR:
		
	if weapon.ammo_type == WeaponSpec.AmmoType.HE or riflegrenade:
		
		var stress_mod: float = remap(controller.unit.stress_system.S_eff, 0.0, 100.0, 1.0, 0.2)
		s_fast = controller.stress_fast_base * stress_mod * 0.3 + mean_chance_to_hit * weapon.he_suppression_power
		s_slow = controller.stress_fast_base * stress_mod * 0.3 + mean_chance_to_hit * weapon.he_suppression_power
		pass
		#stress_cover_mod = weapon.he_suppression_power
		#stress_cover_mod = stress_cover_mod * 4.0
	
	#var stress_cover_fast_mod: float = _stress_cover_mult(cover_norm, stress_cover_fast_min) # 1 cover = 1.0; 3 cover = 0.63
	#var stress_cover_slow_mod: float = _stress_cover_mult(cover_norm, stress_cover_slow_min) # 1 cover = 1.0; 3 cover = 0.76
	if not weapon.ammo_type == WeaponSpec.AmmoType.HE and not riflegrenade:
		s_fast *= stress_cover_mod
		s_slow *= stress_cover_mod

	# point-blank fear spike
	if int(target_distance) == 1:
		s_fast *= controller.stress_point_blank_bonus
		s_slow *= controller.stress_point_blank_bonus
	
	# distance mod
	if not weapon.ammo_type == WeaponSpec.AmmoType.HE and not riflegrenade:
		var stress_distance_mod: float = float(target_distance) / float(weapon.range_hexes)
		stress_distance_mod = 1.0 - 0.5 * stress_distance_mod
		s_fast *= stress_distance_mod
		s_slow *= stress_distance_mod
	
	## weapon flavour & global scale
	#s_fast *= weapon_stress_mult * stress_scale
	#s_slow *= weapon_stress_mult * stress_scale
	
	var suppression: StressController.StressGain = StressController.StressGain.new(s_fast, s_slow)
	# Preserve the existing shared casualty shock for squads in the struck hex.
	var casualties_total: int = 0
	for casualties: int in casualties_per_target:
		casualties_total += casualties
	var casualty_shock: StressController.StressGain = StressController.StressGain.new(float(casualties_total) * controller.stress_kill_fast_each, float(casualties_total) * controller.stress_kill_slow_each)

	# --- apply effects to each squad: casualties as rolled, stress follows its attention ---
	i = 0
	while i < n_targets:
		var u_apply: Unit = batch_targets[i]
		var cas_i: int = int(casualties_per_target[i])
		var attention_effects: Vector2 = Vector2.ZERO
		if total_rounds > 0 and u_apply.tactical_state != null:
			var direction: Vector2 = shot_origin - u_apply.global_position
			attention_effects = u_apply.tactical_state.register_incoming_fire(direction, u_apply._now())
		var stress: StressController.StressGain = StressController.calculate_incoming_fire_stress(controller, suppression, casualty_shock, attention_effects)
		u_apply.call_deferred("_on_incoming_fire_effect", cas_i, stress.fast, stress.slow, controller)
		i += 1
