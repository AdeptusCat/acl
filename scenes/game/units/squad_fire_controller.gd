# SquadFireController.gd
extends Node
class_name SquadFireController

# Wiring
@export var unit: Unit
@export var combat: UnitCombat
@export var stress_controller: StressController

# Timing
@export var burst_window_s: float = 0.10      # batch rounds within this window per hex
@export var max_shots_per_tick: int = 128

## State influence (from your STATES table)
#@export var state_acc_mults: PackedFloat32Array = PackedFloat32Array([1.0, 0.9, 0.5, 0.0, 0.0])
#@export var state_rof_mults: PackedFloat32Array = PackedFloat32Array([1.0, 0.85, 0.35, 0.0, 0.0])

# NEW: state influence on target acquisition time (Normal..CombatIneffective)
@export var state_acquire_mults: PackedFloat32Array = PackedFloat32Array([1.0, 1.15, 1.6, 9999.0, 9999.0])
# panic/CI effectively “never acquire”

# Crew-served behaviour
@export var crew_idle_to_loader: bool = true

@export var max_cover_pts: float = 5.0   # stone house is 3; you can raise if needed

@onready var calc: SquadFireCalculator = SquadFireCalculator.new()
var fin: SquadFireCalculator.SquadFireInput = SquadFireCalculator.SquadFireInput.new()


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

const MIN_HIT_MULT: float = 0.1   # floor at extreme cover
const HALF_POINT: float = 1.5      # cover points to halve the remaining gap to the floor

# Soldiers
var soldiers: Array[Soldier] = []
var _now_s: float = 0.0
var _accum_window_s: float = 0.0

# Targeting
var target_hex: Vector2i
var target_cover: float
var target_unit: Unit
var target_distance: int
var _pending_rounds_by_hex: Dictionary = {}    # Vector2i -> int
var unit_visible_enemies: Dictionary

signal fire_shot
signal fire_riflegrenade


#func _ready() -> void:
	#var cover: float = 0.0 
	#cover = cover_multiplier_exp(1.0)
	#cover = cover_multiplier_exp(2.0)
	#cover = cover_multiplier_exp(3.0)
	#cover = cover_multiplier_exp(4.0)
	#cover = cover_multiplier_exp(5.0)


func set_soldiers(list: Array[Soldier]) -> void:
	soldiers = list

#var cover_map = LOSHelper.los_lookup.get(current_hex, null)
				#var targetCover = 0
#if cover_map and cover_map.has(enemy.current_hex):
					#var data = cover_map[enemy.current_hex]
					#targetCover = data["target_cover"]
					
func set_target_unit(targetUnit: Unit) -> void:
	var hex: Vector2i = Vector2i.ZERO
	target_cover = 0
	if targetUnit:
		hex = targetUnit.current_hex
		var cover_map = LOSHelper.los_lookup.get(unit.current_hex, null)
		if cover_map and cover_map.has(targetUnit.current_hex):
			var data = cover_map[targetUnit.current_hex]
			target_cover = data["target_cover"]
		target_distance = LOSHelper.ground_layer.cube_distance(unit.current_cube, targetUnit.current_cube)
		if not target_unit == targetUnit:
			#_prime_acquisition_for_new_target()
			aim_delay()
			target_unit = targetUnit
	else:
		target_unit = null
	target_hex = hex

func _physics_process(delta: float) -> void:
	_now_s += delta
	_accum_window_s += delta

	_update_state_multipliers()
	_tick_soldiers(delta)
	if target_unit:
		target_distance = LOSHelper.ground_layer.cube_distance(unit.current_cube, target_unit.current_cube)

	if _accum_window_s >= burst_window_s:
		_flush_burst_window()

func _update_state_multipliers() -> void:
	var state_idx: int = stress_controller.state
	var acc_mult: float = 1.0
	var rof_mult: float = 1.0
	acc_mult = UnitStates.STATE_MOD[stress_controller.state]["acc"]
	rof_mult = UnitStates.STATE_MOD[stress_controller.state]["rof"]

	var i: int = 0
	while i < soldiers.size():
		var s: Soldier = soldiers[i]
		if s.is_alive:
			s.acc_mult = acc_mult
			s.rof_mult = rof_mult
		i += 1

var fire_timer: float = 0.0
func handle_auto_fire(delta, shooter: Node2D, unit_visible_enemies: Dictionary, current_hex, range, fire_rate, firepower):
	fire_timer -= delta
	if fire_timer > 0.0:
		return  # Still waiting for next shot

	if target_unit:
		var visible_enemies: Array = unit_visible_enemies.get(get_parent(), [])
		if not visible_enemies.has(target_unit):
			target_unit = null
			set_target_unit(target_unit)
			return
		if target_unit and target_unit.alive and not target_unit.surrendered:
			#var distance = current_hex.distance_to(target_unit.current_hex)
			var distance: int = LOSHelper.ground_layer.cube_distance(unit.current_cube, target_unit.current_cube)
			var has_range: bool = false
			for soldier: Soldier in unit.squad_fire.soldiers:
				if soldier.weapon.range_hexes >= distance:
					has_range = true
			if has_range:
				var cover_map = LOSHelper.los_lookup.get(current_hex, null)
				var targetCover = 0
				if cover_map and cover_map.has(target_unit.current_hex):
					var data = cover_map[target_unit.current_hex]
					targetCover = data["target_cover"]
				
				target_unit.set_cover(targetCover)
				#fire_at(shooter, target_unit, current_hex, distance, targetCover, firepower, range, unit_visible_enemies, fire_rate)
				fire_timer = fire_rate
				return
			else:
				target_unit = null
				set_target_unit(target_unit)
		else:
			target_unit = null
			set_target_unit(target_unit)
	var visible_enemies: Array = unit_visible_enemies.get(get_parent(), [])
	for enemy in visible_enemies:
		if enemy and enemy.alive and not enemy.surrendered:
			var distance: int = LOSHelper.ground_layer.cube_distance(unit.current_cube, enemy.current_cube)
			var has_range: bool = false
			for soldier: Soldier in unit.squad_fire.soldiers:
				if soldier.weapon.range_hexes >= distance:
					has_range = true
			if has_range:
				var cover_map = LOSHelper.los_lookup.get(current_hex, null)
				var targetCover = 0
				if cover_map and cover_map.has(enemy.current_hex):
					var data = cover_map[enemy.current_hex]
					targetCover = data["target_cover"]
				
				set_target_unit(enemy)
				enemy.set_cover(targetCover)
				#fire_at(shooter, enemy, current_hex, distance, targetCover, firepower, range, unit_visible_enemies, fire_rate)
				fire_timer = fire_rate
				
				break


func _tick_soldiers(delta: float) -> void:
	var rounds_emitted: int = 0

	# count available crew for MGs
	var crew_available: int = _count_role(RankGrades.Role.LOADER)
	var support_crew_available: int = _count_role(RankGrades.Role.ASSISTANT)
	var gunners: Array[int] = _indices_with_role(RankGrades.Role.GUNNER)

	# handle gunners first (crew-served)
	var j: int = 0
	while j < gunners.size():
		var idx: int = gunners[j]
		var s: Soldier = soldiers[idx]
		if s.is_alive:
			rounds_emitted += await _try_fire_soldier(s, true, crew_available, support_crew_available)
			if rounds_emitted > 0:
				pass
			if rounds_emitted >= max_shots_per_tick:
				return
		j += 1

	# then everyone else
	var i: int = 0
	while i < soldiers.size():
		var s2: Soldier = soldiers[i]
		if s2.is_alive:
			if s2.role != RankGrades.Role.GUNNER:
				rounds_emitted += await _try_fire_soldier(s2, false, 0, 0)
				if rounds_emitted >= max_shots_per_tick:
					return
		i += 1

func _try_fire_soldier(s: Soldier, is_crew_served: bool, crew_available: int, support_crew_available: int) -> int:
	s.now_s = _now_s
	if target_hex == Vector2i.ZERO:
		return 0
	
	var batch_targets: Array = []
	var visible_enemies: Array = unit_visible_enemies.get(get_parent(), [])
	for u in visible_enemies:
		if is_instance_valid(u):
			if u.alive:
				if not u.surrendered:
					if u.current_hex == target_hex:
						batch_targets.append(u)
	if batch_targets.is_empty():
		set_target_unit(null)
		return 0
	
	# Loader dont fire their weapon
	if s.role == RankGrades.Role.LOADER or s.role == RankGrades.Role.ASSISTANT:
		return 0
	
	if target_distance > s.weapon.range_hexes * 2:
		#set_target_unit(null) # this should only happen if none have range
		return 0
	
	var long_range: bool = false
	if target_distance > s.weapon.range_hexes:
		long_range = true
	
	# acquisition gate: don’t shoot until settled on the new target
	if _now_s < s.acquire_ready_s and not s.acquire_ready_s == INF:
		return 0
	
	if s.jammed:
		# simple unjam: use reload time as clear jam delay
		if s.next_ready_s <= _now_s:
			s.jammed = false
			s.next_ready_delta_s = s.weapon.reload_s / s.rof_mult
			s.next_ready_s = _now_s + s.next_ready_delta_s
			s.next_ready_start_s = _now_s
		return 0

	if s.next_ready_s > _now_s:
		return 0
	
	var riflegrenade: bool = false
	if s.weapon.riflegrenade_loaded == true:
		riflegrenade = true
		s.weapon.riflegrenade_loaded = false

	# check crew requirement
	var crew_mult: float = 1.0
	if is_crew_served:
		if s.weapon.crew_required > 1:
			var ok: bool = crew_available >= (s.weapon.crew_required - 1)
			if not ok:
				crew_mult = s.weapon.undercrew_penalty_mult
	var efficiency_mult: float = compute_support_efficiency(support_crew_available, s.weapon.support_crew_optimal)
	if efficiency_mult < 1.0:
		pass

	# determine burst size for this weapon
	var rounds_in_mag: int = s.rounds_in_mag
	var shots: int = determine_burst_size(s.weapon, s.rounds_in_mag)
	
	if shots <= 0:
		# reload
		if s.weapon.can_fire_riflegrenades and target_distance <= s.weapon.riflegrenade_range * 2:
			s.next_ready_delta_s = s.weapon.reload_riflegrenade_s / s.rof_mult
			s.next_ready_s = _now_s + s.next_ready_delta_s
			s.next_ready_start_s = _now_s
			s.rounds_in_mag = 1
			s.weapon.riflegrenade_loaded = true
		else:
			s.next_ready_delta_s = s.weapon.reload_s / s.rof_mult
			s.next_ready_s = _now_s + s.next_ready_delta_s
			s.next_ready_start_s = _now_s
			s.rounds_in_mag = s.weapon.mag_capacity
		return 0
	
	if shots > 1:
		pass

	# emit shots immediately into current window
	_add_rounds_to_hex(target_hex, shots)
	#fire_shot.emit()
	var auto_fire: bool = false
	if s.weapon.fire_mode == WeaponSpec.FireMode.BURST:
		auto_fire = true
	_on_fire_weapon(s.weapon, unit.position, auto_fire, s.id, unit)
	
	var dist: float = unit.position.distance_to(target_unit.position)
	var life: float = dist / s.weapon.projectile_speed      # seconds
	if riflegrenade == true:
		life = dist / s.weapon.riflegrenade_projectile_speed      # seconds
		fire_riflegrenades(s)
	else:
		fire_shots(s, shots, s.weapon.rpm, auto_fire)
	
	

	# apply jam chance
	var k: int = 0
	var jammed_now: bool = false
	while k < shots:
		var r: float = randf()
		if r < s.weapon.jam_per_shot:
			jammed_now = true
		k += 1
	if jammed_now:
		s.jammed = true

	# spend ammo
	s.rounds_in_mag -= shots
	
	# cadence to next burst (respect soldier’s rof and crew)
	var rps: float = s.weapon.rpm / 60.0
	if rps < 1.0:
		rps = 1.0
	var fire_time_s: float = float(shots) / rps
	var pause_s: float = s.weapon.burst_pause_s
	var total_cadence_s: float = (fire_time_s + pause_s) / (s.rof_mult)

	# keep a little persistent desync in the rhythm
	var phase_bump: float = s.cadence_phase_s * 0.20  # small influence after first burst
	
	
	var state_idx: int = stress_controller.state
	var acquire_mult: float = 1.0
	if state_idx >= 0 and state_idx < state_acquire_mults.size():
		acquire_mult = state_acquire_mults[state_idx]
	var settle_s: float = _calc_acquire_delay(s) * acquire_mult
	
	if riflegrenade == true:
		settle_s += s.weapon.reload_riflegrenade_s
	
	var reload_time_s: float = 0
	if s.rounds_in_mag <= 0:
		reload_time_s = s.weapon.reload_s
		s.rounds_in_mag = s.weapon.mag_capacity
	
	if s.weapon.can_fire_riflegrenades and target_distance <= s.weapon.riflegrenade_range * 2:
		s.next_ready_delta_s = (total_cadence_s + phase_bump + settle_s + reload_time_s) / efficiency_mult / crew_mult
		s.next_ready_s = _now_s + s.next_ready_delta_s
		s.next_ready_start_s = _now_s
		s.rounds_in_mag += 1
		s.weapon.riflegrenade_loaded = true
	else:
		s.next_ready_delta_s = (total_cadence_s + phase_bump + settle_s + reload_time_s) / efficiency_mult / crew_mult
		s.next_ready_s = _now_s + s.next_ready_delta_s
		s.next_ready_start_s = _now_s
	
	var delta: float = s.next_ready_s - _now_s # debug
	
	await get_tree().create_timer(life).timeout
	fire_at(shots, long_range, s.weapon, riflegrenade)
	return shots


func compute_support_efficiency(support_crew_available: int, support_crew_optimal: int) -> float:
	var ratio: float = 1.0
	if support_crew_optimal > 0:
		ratio = float(support_crew_available) / float(support_crew_optimal)
	
	# clamp ratio to [0, 1]
	if ratio < 0.0:
		ratio = 0.0
	else:
		if ratio > 1.0:
			ratio = 1.0
	
	# 0 helpers -> 0.5, full helpers -> 1.0
	var multiplier: float = 0.5 + 0.5 * ratio
	return multiplier

# Util: returns a single normally-distributed sample (mean 0, stddev 1)
func _rand_normal() -> float:
	var u1: float = 0.0
	var u2: float = 0.0
	# avoid log(0)
	u1 = randf()
	while u1 <= 0.0:
		u1 = randf()
	u2 = randf()
	var z0: float = sqrt(-2.0 * log(u1)) * cos(2.0 * PI * u2)
	return z0


# Determine burst size with sensible variance and clamping
func determine_burst_size(weapon: WeaponSpec, rounds_in_mag: int) -> int:
	# base nominal
	var base: int = int(weapon.burst_rounds)
	if base < 1:
		base = 1

	var shots: int = base
	if weapon.fire_mode == WeaponSpec.FireMode.BURST:
		# choose variance fraction by weapon class (tune these constants as you wish)
		var variance_fraction: float = 0.25        # default: ±25%
		if weapon.fire_mode == WeaponSpec.FireMode.BURST:
			variance_fraction = 0.35               # SMGs are a bit more 'spray-y'
		#elif weapon.type == WeaponSpec.WeaponType.MG:
			#variance_fraction = 0.40               # MGs have larger variability

		# compute stddev in rounds (at least 1 round)
		var stddev: float = max(1.0, float(base) * variance_fraction)

		# draw a gaussian offset, round to integer
		var gauss: float = _rand_normal()
		var sample: float = float(base) + gauss * stddev
		shots = int(round(sample))
		
		# small chance to produce a sustained longer burst (suppression)
		var r: float = randf()
		if r < 0.10: # 10% chance
			shots = min(rounds_in_mag, shots + int(round(float(weapon.burst_rounds) * 0.75)))

	# clamp to sensible bounds
	if shots < 1:
		shots = 1
	if shots > rounds_in_mag:
		shots = rounds_in_mag
			
	return shots


func aim_delay():
	var state_idx: int = stress_controller.state
	var acquire_mult: float = 1.0
	if state_idx >= 0 and state_idx < state_acquire_mults.size():
		acquire_mult = state_acquire_mults[state_idx]
	for s in soldiers:
		var settle_s: float = _calc_acquire_delay(s) * acquire_mult
		s.next_ready_delta_s = settle_s
		s.next_ready_s = _now_s + s.next_ready_delta_s
		s.next_ready_start_s = _now_s
		# ensure we don’t fire before we’ve acquired, even if next_ready_s was in the past
		if s.next_ready_s < s.acquire_ready_s and not s.acquire_ready_s == INF:
			s.next_ready_s = s.acquire_ready_s
			s.next_ready_start_s = _now_s
			s.next_ready_delta_s = s.acquire_ready_s - _now_s 
		


func fire_shots(s: Soldier, shots: int, rpm: float, auto_fire: bool):
	var interval: float = 60.0 / rpm
	for shot in range(shots):
		fire_shot.emit(s.weapon)
		await get_tree().create_timer(interval).timeout
	if auto_fire:
		_on_stop_mg_loop(s.weapon, unit.position, s.id, unit)


func fire_riflegrenades(s: Soldier):
	fire_riflegrenade.emit(s.weapon)


func fire_at(total_rounds: int, long_range: bool, weapon: WeaponSpec, riflegrenade: bool) -> void:
	#return
	var terrain_defense_bonus: float = target_cover
	# --- range gating & power falloff ---

	# --- collect all enemy squads in the target hex ---
	var batch_targets: Array = []
	var visible_enemies: Array = unit_visible_enemies.get(get_parent(), [])
	for u in visible_enemies:
		if is_instance_valid(u):
			if u.alive:
				if not u.surrendered:
					if u.current_hex == target_hex:
						batch_targets.append(u)
	if batch_targets.is_empty():
		return
	
	var cover_norm: float = float(terrain_defense_bonus) / max_cover_pts
	if cover_norm > 1.0:
		cover_norm = 1.0
	if cover_norm < 0.0:
		cover_norm = 0.0
	
	# the idea here is that hard cover also modifies lethallity and not just accuracy, but needs rework
	#var lethality_cover_mult: float = lerp(lethality_cover_min, lethality_cover_max, 1.0 - cover_norm)
	var lethality_cover_mult: float = 1.0
	lethality_cover_mult *= lerp(0.6, 1.0, 1.0 - (target_cover / 5)) # what does this?
	
	# --- prep per-squad data: cover/exposure & hit prob (same maths as resolve_volley) ---
	# We keep exposure simple here (1.0). If you’ve got per-squad exposure, plug it in.
	var base_accuracy := 0.35
	var state_mod: Dictionary = STATES.STATE_MOD[unit.stress_system.state]
	var acc: float = base_accuracy * float(state_mod.acc)
	acc *= clamp(1.0 - float(target_distance) * 0.002, 0.1, 1.0)
	acc *= lerp(0.6, 1.0, 1.0 - (target_cover / 10)) # what does this?
	var shooter_stress: float = 0.0
	if unit and "stress_system" in unit:
		shooter_stress = float(unit.stress_system.S_eff)
	var shooter_stress_multiplier: float = lerp(0.6, 1.0, 1.0 - (shooter_stress / 100.0) * 0.7)
	acc *= shooter_stress_multiplier
	if long_range:
		acc *= 0.5

	var is_point_blank: bool = target_distance == 1

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
		u.receive_fire(terrain_defense_bonus)

		var exposure: float = 1.0
		var cover_pts: float = float(terrain_defense_bonus)
		target_cover_vals.append(cover_pts)

		var p_hit_per_round: float = acc * exposure
		var cover_multiplier: float = cover_multiplier_exp(cover_pts)
		p_hit_per_round *= cover_multiplier

		if is_point_blank:
			p_hit_per_round *= 2.0
		else:
			p_hit_per_round *= 1.0
		
		var state: STATES.MoraleState = u.stress_system.state
		if state == STATES.MoraleState.PANIC:
			p_hit_per_round *= 4
		
		if riflegrenade == true:
			if target_distance <= weapon.riflegrenade_range:
				p_hit_per_round *= 4
			else:
				p_hit_per_round *= 2
		
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
	if riflegrenade == true:
		while i < n_targets:
			var ii: int = 0
			while ii < 4:
				var p_hit: float = float(p_hit_per_target[i])
				if randf() < p_hit:
					hits_per_target[i] = int(hits_per_target[i]) + 1
				ii += 1
			i += 1
	else:
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
	var base_p_disable: float = 0.12
	if riflegrenade == true:
		base_p_disable = 0.5

	# Range and cover reduce *lethality* further (separate from hit chance)
	# this should not matter when firing explosives
	var lethality_range_mult: float = _range_lethality_mult(target_distance, int(unit.range))
	if riflegrenade == true:
		lethality_range_mult = 1.0

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

			var d: int = 0
			while d < hits_i:
				if randf() < p_cas:
					casualties_i += 1
				else:
					casualties_i += 0
				d += 1

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
	if int(target_distance) == 1:
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
		
		# debug, or rather balance?
		s_fast_final *= 0.2
		s_slow_final *= 0.2
		
		s_fast_final *= total_rounds
		s_slow_final *= total_rounds

		u_apply.call_deferred("_on_incoming_fire_effect", cas_i, s_fast_final, s_slow_final, self)
		i += 1

func _range_lethality_mult(distance_in_hexes: int, max_range: int) -> float:
	# 1 hex: 1.0; <= max_range: mid; <= 2x max: far; else 0 (but you don’t shoot then).
	if distance_in_hexes <= 1:
		return 1.0
	else:
		if distance_in_hexes <= max_range:
			return lethality_mid_range
		else:
			return lethality_far_range


func cover_multiplier_exp(cover_pts: float) -> float:
	# Multiplier goes 1.0 → MIN_HIT_MULT with diminishing returns as cover_pts rises
	var k: float = log(2.0) / HALF_POINT
	return MIN_HIT_MULT + (1.0 - MIN_HIT_MULT) * exp(-k * max(cover_pts, 0.0))



func _add_rounds_to_hex(hx: Vector2i, n: int) -> void:
	var cur: int = 0
	if _pending_rounds_by_hex.has(hx):
		cur = int(_pending_rounds_by_hex[hx])
	_pending_rounds_by_hex[hx] = cur + n

func _flush_burst_window() -> void:
	_accum_window_s = 0.0
	for hx in _pending_rounds_by_hex.keys():
		var rounds: int = int(_pending_rounds_by_hex[hx])
		if rounds > 0:
			_emit_burst_to_combat(hx, rounds)
	_pending_rounds_by_hex.clear()

func _emit_burst_to_combat(hx: Vector2i, rounds: int) -> void:
	if combat == null:
		return
	# Call your existing burst/volley entrypoint.
	# Expectation from earlier: resolve TOTAL rounds once per volley for that hex.
	if combat.has_method("fire_burst_total_rounds"):
		combat.call("fire_burst_total_rounds", unit, hx, rounds)
		return
	# Fallback: if you only have fire_at(), you can adapt it or add a proper method.


func _stress_cover_mult(cover_norm: float, min_floor: float) -> float:
	# cover_norm: 0 = open, 1 = best cover
	cover_norm = clamp(cover_norm, 0.0, 1.0)
	var expose: float = pow(1.0 - cover_norm, stress_cover_gamma)  # 1 at open, 0 near full cover
	var mult: float = min_floor + (1.0 - min_floor) * expose       # lerp to a floor
	return mult

func _count_role(role: int) -> int:
	var c: int = 0
	var i: int = 0
	while i < soldiers.size():
		if soldiers[i].is_alive:
			if int(soldiers[i].role) == role:
				c += 1
		i += 1
	return c

func _indices_with_role(role: int) -> Array[int]:
	var res: Array[int] = []
	var i: int = 0
	while i < soldiers.size():
		if soldiers[i].is_alive:
			if int(soldiers[i].role) == role:
				res.append(i)
		i += 1
	return res

func _on_unit_arrived_at_hex(new_hex: Vector2i):
	_prime_acquisition_for_new_target()

func _prime_acquisition_for_new_target() -> void:
	# called whenever target_hex changes
	var state_idx: int = stress_controller.state
	var acquire_mult: float = 1.0
	if state_idx >= 0 and state_idx < state_acquire_mults.size():
		acquire_mult = state_acquire_mults[state_idx]

	var i: int = 0
	while i < soldiers.size():
		var s: Soldier = soldiers[i]
		if s.is_alive:
			if s.weapon.can_fire_riflegrenades and target_distance <= s.weapon.riflegrenade_range * 2:
				var settle_s: float = _calc_acquire_delay(s) * acquire_mult
				settle_s += s.weapon.setup_riflegrenade_s
				settle_s *= acquire_mult
				# add the soldier's fixed cadence phase so first bursts don’t sync
				settle_s += s.cadence_phase_s
				s.acquire_start_s = _now_s
				s.next_ready_delta_s = settle_s / s.rof_mult
				s.acquire_ready_s = _now_s + s.next_ready_delta_s
				s.last_target_hex = target_hex
				# ensure we don’t fire before we’ve acquired, even if next_ready_s was in the past
				if s.next_ready_s < s.acquire_ready_s:
					s.next_ready_s = s.acquire_ready_s
					s.next_ready_start_s = _now_s
				s.weapon.riflegrenade_loaded = true
			else:
				var settle_s: float = _calc_acquire_delay(s) * acquire_mult
				settle_s += s.weapon.setup_s
				settle_s *= acquire_mult
				# add the soldier's fixed cadence phase so first bursts don’t sync
				settle_s += s.cadence_phase_s
				s.acquire_start_s = _now_s
				s.next_ready_delta_s = settle_s / s.rof_mult
				s.acquire_ready_s = _now_s + s.next_ready_delta_s
				s.last_target_hex = target_hex
				# ensure we don’t fire before we’ve acquired, even if next_ready_s was in the past
				if s.next_ready_s < s.acquire_ready_s:
					s.next_ready_s = s.acquire_ready_s
					s.next_ready_start_s = _now_s
		i += 1


func _calc_acquire_delay(s: Soldier) -> float:
	# prefer weapon raise/aim timings if available; else use soldier base
	var base: float = s.base_acquire_s
	if s.weapon != null:
		if s.weapon.riflegrenade_loaded == true:
			var has_raise: bool = s.weapon.raise_riflegrenade_s > 0.0
			var has_aim: bool = s.weapon.aim_riflegrenade_s > 0.0
			if has_raise or has_aim:
				base = s.weapon.raise_riflegrenade_s + s.weapon.aim_riflegrenade_s
		else:
			var has_raise: bool = s.weapon.raise_s > 0.0
			var has_aim: bool = s.weapon.aim_s > 0.0
			if has_raise or has_aim:
				base = s.weapon.raise_s + s.weapon.aim_s
	# add a random bit per target switch
	var jitter: float = randf_range(0.0, s.aim_jitter_s)
	return base + jitter

func _on_fire_weapon(weapon_spec: WeaponSpec, pos: Vector2, is_auto: bool, owner_id: int, position_node: Node2D) -> void:
	if is_auto:
		# start loop when begins firing
		$"../WeaponAudio".start_mg_loop(owner_id, weapon_spec, position_node)
		# each volley still spawns muzzle puffs/visuals and optional short bursts
		$"../WeaponAudio".play_shot(weapon_spec, pos, false)
	else:
		$"../WeaponAudio".play_shot(weapon_spec, pos, false)

func _on_stop_mg_loop(weapon_spec: WeaponSpec, position: Vector2, owner_id: int, position_node: Node2D):
	$"../WeaponAudio".stop_mg_loop(weapon_spec, position, owner_id, position_node)
	
