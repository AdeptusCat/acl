class_name UnitCombat
extends Node

# --- STATES (unchanged) ---
enum MoraleState { NORMAL, CAUTIOUS, PINNED, PANIC, COMBAT_INEFFECTIVE }

@export var base_accuracy := 0.35
@export var volley_size := 1               # rounds per burst
@export var seconds_per_volley := 1.2

@export var stress_scale := 1.0             # global tuning
@export var stress_fast_base: float = 8.0       # baseline shock of “being shot at”
@export var stress_fast_hit_factor: float = 12.0# adds with mean p_hit (0..1)
@export var stress_slow_per_round: float = 0.6  # accrues with volume
@export var stress_point_blank_bonus: float = 1.5 # extra fear at 1 hex
@export var stress_crossfire_bonus: float = 0.15    # e.g. 0.15 if multiple sources
@export var stress_max_per_volley: float = 40.0    # safety cap (per volley, per squad) # if this is lower than the kill cap, raise it
@export var weapon_stress_mult: float = 1.0   # MGs 1.2–1.4, rifles 1.0
@export var stress_resilience: float = 1.0    # better-trained squads 0.8–0.9

@export var casualty_scale: float = 0.75      # lower than 1.0 to reduce deaths overall
@export var p_disable_rifle: float = 0.12     # was 0.5; rifles should be low
@export var p_disable_mg: float = 0.18        # MGs a tad higher than rifles
@export var lethality_cap_per_volley: int = 2 # per target, per volley; 1 keeps spikes down
@export var lethality_cover_min: float = 0.6  # cover also reduces *lethality* (not just hit)
@export var lethality_cover_max: float = 1.0  # no cover → 1.0 (full lethality)
@export var lethality_mid_range: float = 0.7  # mid-range lethality multiplier
@export var lethality_far_range: float = 0.45 # far-range lethality multiplier

@export var stress_kill_fast_first: float = 30.0        # first KIA this volley (fast spike)
@export var stress_kill_fast_each: float = 15.0           # each additional KIA (fast spike)
@export var stress_kill_slow_each: float = 10.0           # per KIA (slow dread)
@export var stress_kill_ratio_bonus: float = 0.5         # +50% at 100% losses (scales with loss ratio)
@export var stress_kill_max_per_volley: float = 60.0     # cap for casualty-driven stress per volley

# ---- cover → stress dampening (fast & slow), typed nice and proper ----
@export var stress_cover_fast_min: float = 0.45   # floor at max cover (fast spike never 0)
@export var stress_cover_slow_min: float = 0.65   # floor at max cover (slow dread never 0)
@export var stress_cover_gamma: float = 1.2       # curvature; >1 gives diminishing returns

@export var max_cover_pts: float = 5.0   # stone house is 3; you can raise if needed

@onready var calc: SquadFireCalculator = SquadFireCalculator.new()
var fin: SquadFireCalculator.SquadFireInput = SquadFireCalculator.SquadFireInput.new()

const MIN_HIT_MULT: float = 0.35   # floor at extreme cover
const HALF_POINT: float = 1.5      # cover points to halve the remaining gap to the floor

var can_fire := true
var current_state: int = MoraleState.NORMAL # injected from morale
var cover_bonus := 0.0 # injected from LOS/terrain (0..1)
var accuracy_multiplier: float = 1.0

var fire_timer: float = 0.0
var target_unit

signal shoot(from_pos, target_pos)


func _ready():
	# Define the rifle spec (individual)
	var rifle: SquadFireCalculator.WeaponSpec = SquadFireCalculator.WeaponSpec.new()
	rifle.name = "Bolt-action Rifle"
	rifle.kind = SquadFireCalculator.WeaponKind.INDIVIDUAL
	rifle.practical_rpm = 12.0  # a bit conservative for sustained fire

	# Define the MG (crew-served)
	var mg: SquadFireCalculator.WeaponSpec = SquadFireCalculator.WeaponSpec.new()
	mg.name = "GPMG"
	mg.kind = SquadFireCalculator.WeaponKind.CREW_SERVED
	mg.cyclic_rpm = 700.0
	mg.burst_rounds = 4           # “short bursts”, aye
	mg.burst_pause_s = 0.35
	mg.crew_required = 2          # gunner + loader
	mg.undercrew_penalty_exp = 1.6
	mg.priority = 10              # gets crew before anything else

	# Put one MG in the squad
	var mg_eq: SquadFireCalculator.EquipmentInstance = SquadFireCalculator.EquipmentInstance.new(mg, 1)

	# Build the input for this tick (say dt = 1.0 s, squad state Normal)
	#var fin: SquadFireCalculator.SquadFireInput = SquadFireCalculator.SquadFireInput.new()
	fin.total_soldiers_present = 10
	fin.state_rof_mult = 1.0                    # pull your morale/state ROF multiplier here (e.g. 0.35 if PINNED)
	fin.dt_seconds = 1.0
	fin.individual_weapon = rifle
	#fin.crew_equipment = [] #[mg_eq]

	# Compute volley
	#var volley: SquadFireCalculator.VolleyResult = calc.build_volley(fin)

	# Now you’ve got volley.total_rounds for visuals and distribution,
	# and a breakdown for logs or debug.
	# Example: split total rounds across targets, then call resolve_volley() per target as you already do.

func set_mg(machinge_guns : int):
	for i in machinge_guns:
		# Define the MG (crew-served)
		var mg: SquadFireCalculator.WeaponSpec = SquadFireCalculator.WeaponSpec.new()
		mg.name = "GPMG"
		mg.kind = SquadFireCalculator.WeaponKind.CREW_SERVED
		mg.cyclic_rpm = 700.0
		mg.burst_rounds = 4           # “short bursts”, aye
		mg.burst_pause_s = 0.35
		mg.crew_required = 2          # gunner + loader
		mg.undercrew_penalty_exp = 1.6
		mg.priority = 10              # gets crew before anything else
		var mg_eq: SquadFireCalculator.EquipmentInstance = SquadFireCalculator.EquipmentInstance.new(mg, 1)
		fin.crew_equipment.append(mg_eq)

func _range_lethality_mult(distance_in_hexes: int, max_range: int) -> float:
	# 1 hex: 1.0; <= max_range: mid; <= 2x max: far; else 0 (but you don’t shoot then).
	if distance_in_hexes <= 1:
		return 1.0
	else:
		if distance_in_hexes <= max_range:
			return lethality_mid_range
		else:
			return lethality_far_range

func resolve_volley(target: Node, inputs: Dictionary) -> void:
	# inputs: { distance, target_exposure (0..1), target_cover (0..1),
	#           shooter_stress (0..100), target_state:int, crossfire_bonus:float,
	#           override_rounds:int (optional),
	#           apply_lethality:bool (optional),
	#           stress_spill:float (optional) }

	var state_mod: Dictionary = STATES.STATE_MOD[current_state]
	var acc: float = base_accuracy * float(state_mod.acc)
	acc *= clamp(1.0 - float(inputs.distance) * 0.002, 0.1, 1.0)
	acc *= lerp(0.6, 1.0, 1.0 - cover_bonus)
	acc *= lerp(0.6, 1.0, 1.0 - (float(inputs.shooter_stress) / 100.0) * 0.7)

	var apply_lethality: bool = true
	if inputs.has("apply_lethality"):
		apply_lethality = bool(inputs.apply_lethality)

	var stress_spill: float = 1.0
	if inputs.has("stress_spill"):
		stress_spill = float(inputs.stress_spill)

	# --- effective rounds: override or compute ---
	var effective_rounds: int = 0
	if inputs.has("override_rounds"):
		effective_rounds = int(inputs.override_rounds)
	else:
		var parent_node: Node = get_parent()
		var members_for_output: int = 1
		if parent_node and "members_effective" in parent_node:
			members_for_output = max(1, int(parent_node.members_effective))
		else:
			if parent_node and "members_alive" in parent_node:
				members_for_output = max(1, int(parent_node.members_alive))
		effective_rounds = int(round(volley_size * float(state_mod.rof) * float(members_for_output)))

	if effective_rounds <= 0:
		return

	# --- Hit model ---
	var exposure: float  = clamp(float(inputs.get("target_exposure", 1.0)), 0.1, 1.0)
	var cover_pts: float = max(float(inputs.get("target_cover", 0.0)), 0.0)

	var p_hit_per_round: float = acc * exposure
	p_hit_per_round *= cover_multiplier_exp(cover_pts)

	# Point-blank (1 hex) doubles per-round hit chance
	if int(inputs.distance) == 1:
		p_hit_per_round *= 2.0
	else:
		p_hit_per_round *= 1.0

	p_hit_per_round = clamp(p_hit_per_round, 0.001, 0.95)

	# --- Casualty (only if allowed) ---
	var casualties: int = 0
	if apply_lethality:
		var p_disable_given_hit: float = 0.5
		var p_casualty: float = 1.0 - pow(1.0 - p_hit_per_round * p_disable_given_hit, float(effective_rounds))
		p_casualty *= (1.0 + float(inputs.get("crossfire_bonus", 0.0)))
		p_casualty *= casualty_scale
		p_casualty = clamp(p_casualty, 0.0, 0.99)

		if randf() < p_casualty:
			casualties = 1
		else:
			casualties = 0
	else:
		casualties = 0

	# --- Stress (everyone gets it; bystanders use spill) ---
	var stress_fast: float = (0.8 + p_hit_per_round) * 12.0 * stress_scale * stress_spill
	var stress_slow: float = float(effective_rounds) * 0.6 * lerp(0.4, 1.0, 1.0 - float(inputs.target_cover)) * stress_scale * stress_spill

	target.call_deferred("_on_incoming_fire_effect", casualties, stress_fast, stress_slow, self)



func handle_auto_fire(delta, shooter: Node2D, unit_visible_enemies: Dictionary, current_hex, range, fire_rate, firepower):
	fire_timer -= delta
	if fire_timer > 0.0:
		return  # Still waiting for next shot

	if target_unit:
		if target_unit and target_unit.alive and not target_unit.surrendered:
			var distance = current_hex.distance_to(target_unit.current_hex)
			if distance <= range * 2:
				var cover_map = LOSHelper.los_lookup.get(current_hex, null)
				var targetCover = 0
				if cover_map and cover_map.has(target_unit.current_hex):
					var data = cover_map[target_unit.current_hex]
					targetCover = data["target_cover"]
				
				target_unit.set_cover(targetCover)
				fire_at(shooter, target_unit, current_hex, distance, targetCover, firepower, range, unit_visible_enemies, fire_rate)
				fire_timer = fire_rate
				return
			else:
				target_unit = null
		else:
			target_unit = null
	var visible_enemies: Array = unit_visible_enemies.get(get_parent(), [])
	for enemy in visible_enemies:
		if enemy and enemy.alive and not enemy.surrendered:
			var distance = current_hex.distance_to(enemy.current_hex)
			if distance <= range * 2:
				var cover_map = LOSHelper.los_lookup.get(current_hex, null)
				var targetCover = 0
				if cover_map and cover_map.has(enemy.current_hex):
					var data = cover_map[enemy.current_hex]
					targetCover = data["target_cover"]

				enemy.set_cover(targetCover)
				fire_at(shooter, enemy, current_hex, distance, targetCover, firepower, range, unit_visible_enemies, fire_rate)
				fire_timer = fire_rate
				break

func fire_at(shooter: Node2D, target: Node2D, current_hex, distance_in_hexes: int, terrain_defense_bonus: float, firepower: float, range, unit_visible_enemies: Dictionary, fire_rate) -> void:
	# --- range gating & power falloff ---
	var actual_firepower: float = firepower
	if distance_in_hexes > range:
		if distance_in_hexes <= range * 2:
			actual_firepower = firepower / 2.0
		else:
			return

	# --- collect all enemy squads in the target hex ---
	var target_hex = target.current_hex
	var batch_targets: Array = []
	var visible_enemies: Array = unit_visible_enemies.get(get_parent(), [])
	for u in visible_enemies:
		if is_instance_valid(u):
			if u.alive:
				if not u.surrendered:
					if u.current_hex == target_hex:
						batch_targets.append(u)

	if batch_targets.is_empty():
		target_unit = null
		return

	# --- compute TOTAL rounds once (scaled by members_effective & state) ---
	var state_mod: Dictionary = STATES.STATE_MOD[current_state]
	var parent_node: Node = get_parent()

	#var members_for_output: int = 1
	#if parent_node and "members_effective" in parent_node:
		#members_for_output = max(1, int(parent_node.members_effective))
	#else:
		#if parent_node and "members_alive" in parent_node:
			#members_for_output = max(1, int(parent_node.members_alive))

	#var total_rounds1: int = int(round(volley_size * float(state_mod.rof) * float(members_for_output)))
	# Compute volley
	var volley: SquadFireCalculator.VolleyResult = calc.build_volley(fin)
	
	var total_rounds: int = volley.total_rounds
	var individual_rounds: int = volley.individual_rounds
	var burst_rounds: int = volley.burst_rounds
	var round_multiplier: float = 1.0
	if current_state == MoraleState.CAUTIOUS:
		round_multiplier = 0.9
	elif current_state == MoraleState.PINNED:
		round_multiplier = 0.5
	total_rounds = int(total_rounds * round_multiplier)
	individual_rounds = int(individual_rounds * round_multiplier)
	burst_rounds = int(burst_rounds * round_multiplier)

	# --- prep per-squad data: cover/exposure & hit prob (same maths as resolve_volley) ---
	# We keep exposure simple here (1.0). If you’ve got per-squad exposure, plug it in.
	var acc: float = base_accuracy * float(state_mod.acc)
	acc *= clamp(1.0 - float(distance_in_hexes) * 0.002, 0.1, 1.0)
	acc *= lerp(0.6, 1.0, 1.0 - cover_bonus)
	var shooter_stress: float = 0.0
	if parent_node and "stress_system" in parent_node:
		shooter_stress = float(parent_node.stress_system.S_eff)
	var shooter_stress_multiplier: float = lerp(0.6, 1.0, 1.0 - (shooter_stress / 100.0) * 0.7)
	acc *= shooter_stress_multiplier

	var is_point_blank: bool = int(distance_in_hexes) == 1

	var n_targets: int = batch_targets.size()
	var p_hit_per_target: Array = []
	var target_cover_vals: Array = []
	
	# --- slower recovery while under fire ---
	var pressure_rps: float = float(total_rounds)   # or total_rounds / volley_dt if you track it
	var j: int = 0
	while j < n_targets:
		var u_mark: Node = batch_targets[j]
		if "stress_system" in u_mark:
			var sc: StressController = u_mark.stress_system as StressController
			if sc != null:
				sc.mark_under_fire(pressure_rps)
		j += 1

	var i: int = 0
	while i < n_targets:
		var u: Node = batch_targets[i]
		u.set_cover(terrain_defense_bonus)  # keep your existing hook
		u.receive_fire(actual_firepower, terrain_defense_bonus, unit_visible_enemies)

		var exposure: float = 1.0
		var cover_pts: float = float(terrain_defense_bonus)
		target_cover_vals.append(cover_pts)

		var p_hit_per_round: float = acc * exposure
		p_hit_per_round *= cover_multiplier_exp(cover_pts)

		if is_point_blank:
			p_hit_per_round *= 2.0
		else:
			p_hit_per_round *= 1.0

		p_hit_per_round = clamp(p_hit_per_round, 0.002, 0.95)
		p_hit_per_target.append(p_hit_per_round)
		i += 1

	# --- assign each round to ONE squad and roll the hit there ---
	# Even assignment chance; to weight, build a weight list and roulette-pick.
	var hits_per_target: Array = []
	i = 0
	while i < n_targets:
		hits_per_target.append(0)
		i += 1

	i = 0
	while i < total_rounds:
		# pick recipient squad
		var idx: int = randi() % n_targets
		# roll hit with that squad's p
		var p_hit: float = float(p_hit_per_target[idx])
		if randf() < p_hit:
			hits_per_target[idx] = int(hits_per_target[idx]) + 1
		i += 1

	# --- convert hits → casualties per squad (multi-cas possible, sensible cap) ---
	# Decide per-hit disable based on weapon; here we default to rifle numbers
	var base_p_disable: float = p_disable_rifle
	# If you’ve marked the shooter as MG, flip it:
	if "is_mg_team" in self:
		if bool(self.is_mg_team):
			base_p_disable = p_disable_mg
	else:
		base_p_disable = base_p_disable  # no change

	# Range and cover reduce *lethality* further (separate from hit chance)
	var lethality_range_mult: float = _range_lethality_mult(distance_in_hexes, int(range))
	
	var cover_norm: float = float(terrain_defense_bonus) / max_cover_pts
	if cover_norm > 1.0:
		cover_norm = 1.0
	if cover_norm < 0.0:
		cover_norm = 0.0
	var lethality_cover_mult: float = lerp(lethality_cover_min, lethality_cover_max, 1.0 - cover_norm)

	# Final per-hit disable after all throttles
	var p_disable_final: float = base_p_disable * lethality_range_mult * lethality_cover_mult * casualty_scale
	if p_disable_final < 0.01:
		p_disable_final = 0.01  # tiny floor so hits can still matter

	# Convert hits → casualties with a capped, smooth hazard form
	# lambda = hits * p_disable_final;  p_cas = 1 - exp(-lambda)
	# This scales gently and avoids huge spikes.
	var casualties_per_target: Array = []
	var ii: int = 0
	while ii < n_targets:
		var hits_i: int = int(hits_per_target[ii])
		var casualties_i: int = 0

		if hits_i > 0:
			var lambda_val: float = float(hits_i) * p_disable_final
			var p_cas: float = 1.0 - exp(-lambda_val)

			# Draw casualties with a simple 0/1 cap per volley (recommended for readability)
			if lethality_cap_per_volley <= 1:
				if randf() < p_cas:
					casualties_i = 1	
				else:
					casualties_i = 0
			else:
				# Optional multi-cas draw if you ever raise the cap
				var draws: int = min(lethality_cap_per_volley, hits_i)
				var d: int = 0
				while d < draws:
					if randf() < p_cas:
						casualties_i += 1
					else:
						casualties_i += 0
					d += 1
		else:
			casualties_i = 0

		# Never exceed living heads, if present
		var u_chk: Node = batch_targets[ii]
		if "members_alive" in u_chk:
			if casualties_i > int(u_chk.members_alive):
				casualties_i = int(u_chk.members_alive)

		casualties_per_target.append(casualties_i)
		ii += 1


	# --- compute ONE shared stress payload (equal for all squads) ---
	var mean_p_hit: float = 0.0
	var iii: int = 0
	while iii < n_targets:
		mean_p_hit += float(p_hit_per_target[iii])
		iii += 1
	if n_targets > 0:
		mean_p_hit /= float(n_targets)
	else:
		mean_p_hit = 0.0

	# base fast shock + how “accurate” incoming fire looks
	var s_fast: float = stress_fast_base + mean_p_hit * stress_fast_hit_factor

	# slow stress grows with sheer volume; cover damps it
	var s_slow: float = float(total_rounds) * stress_slow_per_round
	
	# apply cover damp to stress (not boost!)
	s_fast *= _stress_cover_mult(cover_norm, stress_cover_fast_min)
	s_slow *= _stress_cover_mult(cover_norm, stress_cover_slow_min)

	# point-blank fear spike
	if int(distance_in_hexes) == 1:
		s_fast *= stress_point_blank_bonus
		s_slow *= stress_point_blank_bonus
	else:
		s_fast *= 1.0
		s_slow *= 1.0

	# crossfire bonus if you track it outside; else leave 0.0
	if stress_crossfire_bonus > 0.0:
		s_fast *= (1.0 + stress_crossfire_bonus)
		s_slow *= (1.0 + stress_crossfire_bonus)
	else:
		s_fast *= 1.0
		s_slow *= 1.0

	# weapon flavour & global scale
	s_fast *= weapon_stress_mult * stress_scale
	s_slow *= weapon_stress_mult * stress_scale

	# clamp so one volley can’t nuke morale outright
	if s_fast > stress_max_per_volley:
		s_fast = stress_max_per_volley
	if s_slow > stress_max_per_volley:
		s_slow = stress_max_per_volley
	
	
	# --- casualties → extra shock (add to s_fast / s_slow) ---
	var casualties_total: int = 0
	var members_total_before: int = 0
	var kk: int = 0
	while kk < n_targets:
		var c_i: int = int(casualties_per_target[kk])
		casualties_total += c_i

		var u0: Node = batch_targets[kk]
		var heads_before: int = 0
		if "members_alive" in u0:
			# members_alive is after losses; add back this volley’s casualties to estimate pre-volley heads
			heads_before = int(u0.members_alive) + c_i
		else:
			heads_before = 0
		members_total_before += heads_before
		kk += 1

	var kill_fast: float = 0.0
	var kill_slow: float = 0.0
	if casualties_total > 0:
		# fast spike: first KIA hits hardest, the rest add smaller spikes
		kill_fast = stress_kill_fast_first
		if casualties_total > 1:
			kill_fast += float(casualties_total - 1) * stress_kill_fast_each
		# slow dread scales with body count
		kill_slow = float(casualties_total) * stress_kill_slow_each

		# scale by loss ratio (bigger shock for small, mauled groups)
		var ratio: float = 0.0
		if members_total_before > 0:
			ratio = float(casualties_total) / float(members_total_before)
		var ratio_mult: float = 1.0 + ratio * stress_kill_ratio_bonus

		kill_fast *= ratio_mult
		kill_slow *= ratio_mult

		# per-volley casualty shock caps (separate from your general stress clamp)
		if kill_fast > stress_kill_max_per_volley:
			kill_fast = stress_kill_max_per_volley
		if kill_slow > stress_kill_max_per_volley:
			kill_slow = stress_kill_max_per_volley

		# add to the base stress built from rounds/hits
		s_fast += kill_fast
		s_slow += kill_slow

	# --- apply effects to each squad: casualties as rolled, stress equal for all ---
	i = 0
	while i < n_targets:
		var u_apply: Node = batch_targets[i]
		var cas_i: int = int(casualties_per_target[i])

		var rf: float = 1.0
		if "stress_resilience" in u_apply:
			rf = float(u_apply.stress_resilience)

		var s_fast_final: float = s_fast * rf
		var s_slow_final: float = s_slow * rf

		u_apply.call_deferred("_on_incoming_fire_effect", cas_i, s_fast_final, s_slow_final, self)
		i += 1

	# --- visuals use TOTAL rounds so it looks right noisy ---
	fire_burst(shooter, current_hex, batch_targets[0], individual_rounds, fire_rate, unit_visible_enemies)
	animate_mg_bursts(
		shooter,
		target,
		burst_rounds,
		700,
		4,
		0.35,
		"instant",                # or "per_burst" if timing should affect results
		unit_visible_enemies,
		fire_rate
	)


func _stress_cover_mult(cover_norm: float, min_floor: float) -> float:
	# cover_norm: 0 = open, 1 = best cover
	cover_norm = clamp(cover_norm, 0.0, 1.0)
	var expose: float = pow(1.0 - cover_norm, stress_cover_gamma)  # 1 at open, 0 near full cover
	var mult: float = min_floor + (1.0 - min_floor) * expose       # lerp to a floor
	return mult

#func fire_at(shooter: Node2D, target: Node2D, current_hex, distance_in_hexes: int, terrain_defense_bonus: float, firepower : float, range, unit_visible_enemies: Dictionary, fire_rate):
#
	#var actual_firepower = firepower
	#if distance_in_hexes > range:
		#if distance_in_hexes <= range * 2:
			#actual_firepower = firepower / 2
		#else:
			#return
#
	#var target_hex = target.current_hex
	#var batch_targets: Array = []
#
	#var visible_enemies: Array = unit_visible_enemies.get(get_parent(), [])
	#for u in visible_enemies:
		#if is_instance_valid(u) and u.alive and not u.surrendered and u.current_hex == target_hex:
			#batch_targets.append(u)
#
	#if batch_targets.is_empty(): 
		#target_unit = null
		#return
#
	#var casualties = 1
	#var stress_fast = 2.0
	#var stress_slow = 1.0
	#for u in batch_targets:
		#u.set_cover(terrain_defense_bonus)
		#u.receive_fire(actual_firepower, terrain_defense_bonus, unit_visible_enemies)
		#
		##u.call_deferred("_on_incoming_fire_effect", casualties, stress_fast, stress_slow, self)
		#resolve_volley(u, {
			#"distance": distance_in_hexes,
			#"target_exposure": 1,
			#"target_cover": terrain_defense_bonus,
			#"shooter_stress": get_parent().stress_system.S_eff,
			#"target_state": u.stress_system.state,
			#"crossfire_bonus": 0.0   # e.g. +0.15 if ≥2 sources suppressing
		#})
	#fire_burst(shooter, current_hex, batch_targets[0], 8, fire_rate, unit_visible_enemies)


func fire_burst(shooter: Node2D, current_hex, target: Node2D, rounds: int, bullets_per_sec: float, unit_visible_enemies: Dictionary) -> void:
	var interval = bullets_per_sec / rounds
	var from_pos = LOSHelper.ground_layer.map_to_local(current_hex)
	
	for i in range(rounds):
		if not is_instance_valid(shooter) or not is_instance_valid(target):
			target_unit = null
			return
		var visible_enemies: Array = unit_visible_enemies.get(get_parent(), [])
		if not visible_enemies.has(target):
			target_unit = null
			return
		if shooter.broken or shooter.moving or shooter.surrendered:
			target_unit = null
			return
		
		shoot.emit(shooter.global_position, target.global_position)

		await get_tree().create_timer(interval).timeout


func cover_multiplier_exp(cover_pts: float) -> float:
	# Multiplier goes 1.0 → MIN_HIT_MULT with diminishing returns as cover_pts rises
	var k: float = log(2.0) / HALF_POINT
	return MIN_HIT_MULT + (1.0 - MIN_HIT_MULT) * exp(-k * max(cover_pts, 0.0))



# Plan bursts like a proper fire order: e.g. total 7 with burst_size 4 -> [4,3].
func plan_bursts(total_rounds: int, burst_size: int) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	if total_rounds <= 0:
		return result
	
	var rounds_left: int = total_rounds
	var this_size: int
	while rounds_left > 0:
		if rounds_left >= burst_size:
			this_size = burst_size
		else:
			this_size = rounds_left
		result.append(this_size)
		rounds_left -= this_size
	return result


# Animation runner. You can call this after you’ve computed total MG rounds for the volley.
# Two modes:
#   - resolve_mode == "instant": resolve mechanics up-front; this only animates
#   - resolve_mode == "per_burst": call your resolve per burst count
# If you fancy per-shot, call your resolve logic in the inner loop where the 'shoot' signal fires.
func animate_mg_bursts(
		shooter: Node2D,
		target: Node2D,
		total_rounds: int,
		cyclic_rpm: float,
		burst_size: int,
		burst_pause_s: float,
		resolve_mode: String,
		unit_visible_enemies: Dictionary,
		fire_rate: float
	) -> void:
	
	if total_rounds <= 0:
		return
	
	## timing
	#var bullets_per_sec: float = cyclic_rpm / 60.0
	#if bullets_per_sec <= 0.0:
		#bullets_per_sec = 1.0   # safety
	#var seconds_per_bullet: float = 1.0 / bullets_per_sec
	
	# plan the bursts
	var bursts: PackedInt32Array = plan_bursts(total_rounds, burst_size)
	
	# If resolving instantly, do it before we faff about with timers
	#if resolve_mode == "instant":
		#_resolve_mg_effects(shooter, target, total_rounds)  # your existing resolve function
	
	var hex_pos: Vector2 = Vector2.ZERO
	var from_pos: Vector2 = Vector2.ZERO
	var to_pos: Vector2 = Vector2.ZERO
	
	# Pre-calc positions; if you need per-shot sway, recompute inside the loop
	# Replace with your ground-layer mapping if needed.
	if "current_hex" in shooter:
		hex_pos = shooter.current_hex
		from_pos = LOSHelper.ground_layer.map_to_local(hex_pos)
	else:
		from_pos = shooter.global_position
	
	to_pos = target.global_position
	
	# Work through each burst
	for i in range(0, bursts.size()):
		# Bail early if anything’s gone pear-shaped
		if not is_instance_valid(shooter):
			return
		if not is_instance_valid(target):
			return
		if shooter.broken or shooter.moving or shooter.surrendered:
			return
		
		var interval = (fire_rate - (burst_pause_s * bursts.size())) / burst_size / bursts.size() 
		# Visibility sanity (cheap check once per burst)
		#var visible_enemies: Array = unit_visible_enemies.get(shooter.get_parent(), [])
		#if not visible_enemies.has(target):
			#return
		
		var shots_this_burst: int = bursts[i]
		
		# If resolving per-burst, do the mechanics now for this chunk
		#if resolve_mode == "per_burst":
			#_resolve_mg_effects(shooter, target, shots_this_burst)
		
		# Animate each shot in the burst
		for s in range(0, shots_this_burst):
			if not is_instance_valid(shooter) or not is_instance_valid(target):
				return
			if shooter.broken or shooter.moving or shooter.surrendered:
				return
			shoot.emit(shooter.global_position, target.global_position)
			# tracer/muzzle flash VFX play on this signal; sound likewise
			await get_tree().create_timer(interval).timeout
		
		# Pause between bursts unless this was the last one
		if i < bursts.size() - 1:
			await get_tree().create_timer(burst_pause_s).timeout
