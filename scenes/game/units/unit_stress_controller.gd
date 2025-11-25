class_name StressController
extends Node


# --- STATES (unchanged) ---
enum MoraleState { NORMAL, CAUTIOUS, PINNED, PANIC, COMBAT_INEFFECTIVE }

# --- TUNABLES ---
@export var half_life_fast: float = 4.0          
# seconds for the "fast stress" bin to halve
# (short-term panic spikes, quick recovery)
@export var half_life_slow: float = 28.0         
# seconds for the "slow stress" bin to halve
# (long-term pressure, sluggish recovery)
@export var w_fast: float = 0.6                  
# weight of fast stress in S_eff (0..1, higher = more sensitive to sudden spikes)
@export var w_slow: float = 0.4                  
# weight of slow stress in S_eff (0..1, higher = more dominated by long pressure)
@export var refractory_s: float = 1.2            
# seconds after a morale state change during which no new change can occur
# (prevents flip-flopping)
@export var leadership_bonus: float = 0.0        
# 0..1 factor representing leadership presence/quality
# (reduces effective stress, boosts stability)
@export var cohesion: float = 1.0                
# 0..1 factor for squad cohesion/formation tightness
# (reduces effective stress, weaker if dispersed)
@export var transition_trial_interval_s: float = 0.10 # how often to roll the dice for state transitions ---  # 100 ms

# --- TUNABLES: thresholds & bias ---
@export var pin_threshold: float = 35.0  	# effective stress level at which squad becomes "Pinned"
@export var panic_threshold: float = 65.0	# effective stress level at which squad enters "Panic"
@export var recovery_bias: float = 1.15     # >1.0 makes recovery easier; =1.0 neutral; <1.0 harder

# --- TUNABLES: hysteresis multipliers (typed) ---
@export var H_CAUTION_FROM_NORMAL: float = 0.70   # getting worse
@export var H_NORMAL_FROM_CAUTION: float = 0.60   # getting better
@export var H_CAUTION_FROM_PINNED: float = 0.60   # getting better
@export var H_CAUTION_FROM_PANIC: float = 0.70    # getting better


# --- TUNABLES: hazard rates λ (per second) for each leg ---
# NORMAL →
@export var L_NORMAL_TO_PANIC: float   = 0.70
@export var L_NORMAL_TO_PINNED: float  = 0.55
@export var L_NORMAL_TO_CAUTIOUS: float= 0.40

# CAUTIOUS →
@export var L_CAUTIOUS_TO_PANIC: float = 0.60
@export var L_CAUTIOUS_TO_PINNED: float= 0.30   # base; scaled by re-pin ramp
@export var L_CAUTIOUS_TO_NORMAL: float= 0.45   # recovery; gets recovery_bias

# PINNED →
@export var L_PINNED_TO_PANIC: float   = 0.35
@export var L_PINNED_TO_CAUTIOUS: float= 0.35   # recovery; ramped, then gets recovery_bias

# PANIC →
@export var L_PANIC_TO_CAUTIOUS: float = 0.1   # recovery; gets recovery_bias

# --- TUNABLES: ramps (seconds to go 0 → 100%) ---
@export var repin_ramp_s: float  = 10.0   # CAUTIOUS→PINNED hazard ramps up after unpin
@export var unpin_ramp_s: float  = 10.0   # PINNED→CAUTIOUS hazard ramps up while pinned

# --- INTERNALS: timers for ramps ---
var _repin_since_unpin: float = 999.0	    # seconds since PINNED→CAUTIOUS; big at start
var _since_pinned: float      = 999.0		# seconds since we entered PINNED

# how leaders affect the *rate* the lads get rattled
@export var leader_gain_reduction_max: float = 0.5      # up to 50% less *incoming* stress
@export var leader_decay_boost_max: float = 0.15        # up to 15% faster decay
@export var leader_effect_smooth_s: float = 0.5         # seconds to blend leader influence
@export var min_incoming_gain_mult: float = 0.4         # floor; never invincible

# --- internal accumulator for trial cadence ---
var _trial_bucket_s: float = 0.0
var _leadership_sources: Dictionary = {}  # key: int (source_id), value: LeadershipMod
var _leader_effect: float = 0.0   # 0..1 smoothed from leadership_bonu

# --- NEW: caps & scaling ---
@export var S_CAP: float = 100.0                 # hard ceiling on stress
@export var incoming_stress_scale: float = 1.0   # global multiplier on added stress
@export var recovery_scale: float = 1.0          # >1 faster decay, <1 slower decay (global)

# --- NEW: slower recovery while under fire ---
@export var under_fire_window_s: float = 2.0     # seconds considered "under fire" after a volley
@export var pressure_ref_rps: float = 10.0       # rounds/sec counted as "heavy"
@export var slowdown_light: float = 0.4         # decay-rate multiplier at light pressure
@export var slowdown_heavy: float = 0.1         # decay-rate multiplier at heavy pressure
@export var stop_fast_decay_when_heavy: bool = false  # freeze fast-stress decay at heavy pressure

# --- slower recovery when panic ---
@export var panic_decay_mult_slow: float = 1.0            # 0..1; lower = slower recovery while panicking
@export var panic_decay_mult_fast: float = 0.2            # 0..1; lower = slower recovery while panicking
@export var panic_freeze_fast_when_panic: bool = false # if true, fast-stress doesn’t decay in PANIC

# --- STATE ---
var stress_fast: float = 0.0
var stress_slow: float = 0.0
var S_eff: float = 0.0
var state: int = MoraleState.NORMAL
var _since_change: float = 999.0

# --- RUNTIME (under fire) ---
var _how_long_under_fire_s: float = 0.0
var _how_long_under_fire_util_rout_s: float = 4.0
var _under_fire_t: float = 0.0
var _last_pressure_rps: float = 0.0

# --- SIGNALS ---
signal state_changed(previous: int, next: int)
signal stress_changed(effective_stress: float)
signal leadership_changed(_leadership_bonus: float)

class LeadershipMod:
	var bonus: float
	var rally: float
	var cohesion_mult: float
	func _init(b: float, r: float, c: float) -> void:
		bonus = b
		rally = r
		cohesion_mult = c

func add_leadership_source(source_id: int, bonus: float, rally: float, cohesion_mult: float) -> void:
	var lm: LeadershipMod = LeadershipMod.new(bonus, rally, cohesion_mult)
	_leadership_sources[source_id] = lm
	_recompute_leadership()

func remove_leadership_source(source_id: int) -> void:
	if _leadership_sources.has(source_id):
		_leadership_sources.erase(source_id)
		_recompute_leadership()

func _recompute_leadership() -> void:
	var total_bonus: float = 0.0
	var total_rally: float = 0.0
	var total_cohesion_mult: float = 1.0
	var max_total_bonus: float = 0.0
	var max_rally: float = 0.0
	var max_cohesion_mult: float = 1.0
	for lm in _leadership_sources.values():
		if lm.bonus > max_total_bonus:
			max_total_bonus = lm.bonus
		if lm.cohesion_mult > max_total_bonus:
			max_cohesion_mult = lm.cohesion_mult
		total_bonus += lm.bonus
		total_rally += lm.rally
		total_cohesion_mult *= lm.cohesion_mult
	#leadership_bonus = total_bonus
	leadership_bonus = max_total_bonus
	#cohesion = clamp(cohesion * total_cohesion_mult, 0.0, 1.5)
	cohesion = clamp(cohesion * max_cohesion_mult, 0.0, 1.5)
	leadership_changed.emit(leadership_bonus)


# Hook this into your recovery rolls (where you already compute recovery chances).
# Example stub you can call inside your recovery logic:
func get_rally_bonus() -> float:
	var s: float = 0.0
	for lm in _leadership_sources.values():
		s += lm.rally
	return s


func _physics_process(delta: float) -> void:
	match state:
		MoraleState.CAUTIOUS:
			_repin_since_unpin += delta
		MoraleState.PINNED:
			_since_pinned += delta
		MoraleState.PANIC:
			if _how_long_under_fire_s > _how_long_under_fire_util_rout_s:
				state_changed.emit(state, state)
				_how_long_under_fire_s = 0.0
	
	if not state == MoraleState.PANIC:
		_how_long_under_fire_s = 0.0
	
	# decay using exponential form so we can scale the *rate* cleanly
	var ln2: float = 0.69314718056
	var lambda_fast: float = 0.0
	var lambda_slow: float = 0.0

	if half_life_fast > 0.0:
		lambda_fast = ln2 * delta / half_life_fast
	if half_life_slow > 0.0:
		lambda_slow = ln2 * delta / half_life_slow

	# global recovery scaling
	if recovery_scale < 0.0:
		recovery_scale = 0.0
	lambda_fast *= recovery_scale
	lambda_slow *= recovery_scale

	# slower decay while under fire
	if _under_fire_t > 0.0:
		_how_long_under_fire_s += delta
		var x: float = 0.0
		if pressure_ref_rps > 0.0:
			x = clamp(_last_pressure_rps / pressure_ref_rps, 0.0, 1.0)
		# map pressure to a rate multiplier between light and heavy slowdowns
		var rate_mult: float = lerp(slowdown_light, slowdown_heavy, x)
		if rate_mult < 0.0:
			rate_mult = 0.0
		lambda_fast *= rate_mult
		lambda_slow *= rate_mult
		# optional: freeze fast-stress under heavy pressure
		if stop_fast_decay_when_heavy:
			if _last_pressure_rps >= pressure_ref_rps:
				lambda_fast = 0.0

		_under_fire_t -= delta
		if _under_fire_t < 0.0:
			_under_fire_t = 0.0

	# --- panic slows recovery ---
	if state == MoraleState.PANIC:
		var m_slow: float = clamp(panic_decay_mult_slow, 0.0, 1.0)
		var m_fast: float = clamp(panic_decay_mult_fast, 0.0, 1.0)
		lambda_slow *= m_slow
		lambda_fast *= m_fast
		if panic_freeze_fast_when_panic:
			lambda_fast = 0.0
		if get_parent().movement.retreating:
			lambda_slow = 0.0
			lambda_fast = 0.0
	# --- leader speeds recovery a touch, still rate-based ---
	var decay_boost: float = 1.0 + _leader_effect * 10.0
	# turn rates into multipliers
	var kf: float = 1.0
	var ks: float = 1.0
	if lambda_fast > 0.0:
		lambda_fast *= decay_boost
		kf = exp(-lambda_fast)
	if lambda_slow > 0.0:
		lambda_slow *= decay_boost
		ks = exp(-lambda_slow)

	# apply decay
	stress_fast *= kf
	stress_slow *= ks
	_clamp_bins()
	
	# --- smooth leader effect so it never steps the meter ---
	var target_leader: float = clamp(leadership_bonus, 0.0, 1.0)
	var blend: float = 1.0
	if leader_effect_smooth_s > 0.0:
		blend = clamp(delta / leader_effect_smooth_s, 0.0, 1.0)
	_leader_effect = lerp(_leader_effect, target_leader, blend)

	# effective stress with leadership & cohesion softening
	#var softener: float = 1.0 - clamp(0.5 * leadership_bonus + 0.3 * cohesion, 0.0, 0.6)
	var softener: float = 1.0 - clamp(0.5 * leadership_bonus, 0.0, 0.6)
	S_eff = (w_fast * stress_fast + w_slow * stress_slow) # * softener
	if S_eff < 0.0:
		S_eff = 0.0
	if S_eff > S_CAP:
		S_eff = S_CAP

	if leadership_bonus > 0.0:
		pass

	_since_change += delta
	_maybe_transition(delta)
	stress_changed.emit(S_eff)
	
	

# add stress from events/volleys — throttled by leadership
func apply_stress(df: float, ds: float) -> void:
	var df_in: float = df
	var ds_in: float = ds
	if df_in < 0.0:
		df_in = 0.0
	if ds_in < 0.0:
		ds_in = 0.0

	var base_scale: float = incoming_stress_scale
	if base_scale < 0.0:
		base_scale = 0.0

	var L: float = _get_current_leader_effect()
	var leader_mult: float = 1.0 - leader_gain_reduction_max * L
	if leader_mult < min_incoming_gain_mult:
		leader_mult = min_incoming_gain_mult
	if leader_mult > 1.0:
		leader_mult = 1.0

	var eff_scale: float = base_scale * leader_mult

	stress_fast += df_in * eff_scale
	stress_slow += ds_in * eff_scale
	_clamp_bins()


func _get_current_leader_effect() -> float:
	var L: float = leadership_bonus
	if L < 0.0:
		L = 0.0
	if L > 1.0:
		L = 1.0
	return L


## add stress from events/volleys
#func apply_stress(df: float, ds: float) -> void:
	#if df < 0.0:
		#df = 0.0
	#if ds < 0.0:
		#ds = 0.0
	#var scale: float = incoming_stress_scale
	#if scale < 0.0:
		#scale = 0.0
	#stress_fast += df * scale
	#stress_slow += ds * scale
	#_clamp_bins()

# casualty shock (kept yours, can be tuned)
func on_casualty_event(n: int, leader_down: bool = false) -> void:
	if n < 0:
		n = 0
	stress_fast += 18.0 * float(n)
	stress_slow += 6.0 * float(n)
	if leader_down:
		stress_fast += 22.0
		stress_slow += 10.0
	_clamp_bins()

# call this whenever rounds crack overhead (per volley)
func mark_under_fire(pressure_rps: float) -> void:
	if pressure_rps < 0.0:
		pressure_rps = 0.0
	_last_pressure_rps = pressure_rps
	_under_fire_t = under_fire_window_s

# state machine (unchanged logic)
#func _maybe_transition(delta: float) -> void:
	#if _since_change < refractory_s:
		#return
#
	#var roll: float = randf()
#
	#match state:
		#MoraleState.NORMAL:
			#if S_eff >= panic_threshold and roll < _rate_to_prob(0.7, delta):
				#_set_state(MoraleState.PANIC)
			#elif S_eff >= pin_threshold and roll < _rate_to_prob(0.55, delta):
				#_set_state(MoraleState.PINNED)
			#elif S_eff >= pin_threshold * 0.7 and roll < _rate_to_prob(0.4, delta):
				#_set_state(MoraleState.CAUTIOUS)
#
		#MoraleState.CAUTIOUS:
			#if S_eff >= panic_threshold and roll < _rate_to_prob(0.6, delta):
				#_set_state(MoraleState.PANIC)
			#elif S_eff < pin_threshold * 0.6 and roll < _rate_to_prob(0.45 * recovery_bias, delta):
				#_set_state(MoraleState.NORMAL)
			#elif S_eff >= pin_threshold and roll < _rate_to_prob(0.3, delta):
				#_set_state(MoraleState.PINNED)
#
		#MoraleState.PINNED:
			#if S_eff >= panic_threshold and roll < _rate_to_prob(0.35, delta):
				#_set_state(MoraleState.PANIC)
			#elif S_eff < pin_threshold * 0.6 and roll < _rate_to_prob(0.90 * recovery_bias, delta):
				#_set_state(MoraleState.CAUTIOUS)
#
		#MoraleState.PANIC:
			#if S_eff < panic_threshold * 0.7 and roll < _rate_to_prob(0.28 * recovery_bias, delta):
				#_set_state(MoraleState.CAUTIOUS)


func _maybe_transition(delta: float) -> void:
	# accumulate time and only attempt a transition every 100 ms (by default)
	_trial_bucket_s += delta
	if _trial_bucket_s < transition_trial_interval_s:
		return
	
	var dt_trial: float = _trial_bucket_s
	_trial_bucket_s = 0.0
	
	if _since_change < refractory_s:
		return

	var roll: float = randf()
	#RollsStats.sample(roll)  # record the roll distribution
	
	var s_eff: float = S_eff

	match state:
		MoraleState.NORMAL:
			if s_eff >= panic_threshold:
				var p: float = _rate_to_prob(L_NORMAL_TO_PANIC, dt_trial)
				if roll < p:
					_set_state(MoraleState.PANIC)
			elif s_eff >= pin_threshold:
				var p: float = _rate_to_prob(L_NORMAL_TO_PINNED, dt_trial)
				if roll < p:
					_set_state(MoraleState.PINNED)
			elif s_eff >= pin_threshold * H_CAUTION_FROM_NORMAL:
				var p: float = _rate_to_prob(L_NORMAL_TO_CAUTIOUS, dt_trial)
				if roll < p:
					_set_state(MoraleState.CAUTIOUS)

		MoraleState.CAUTIOUS:
			if s_eff >= panic_threshold:
				var p: float = _rate_to_prob(L_CAUTIOUS_TO_PANIC, dt_trial)
				if roll < p:
					_set_state(MoraleState.PANIC)
			elif s_eff >= pin_threshold:
				# base hazard is 0.30; ramp it from 0 → 0.30 after unpin
				var lambda: float = L_CAUTIOUS_TO_PINNED * _repin_ramp_multiplier()
				if roll < _rate_to_prob(lambda, dt_trial):
					_set_state(MoraleState.PINNED)
			elif s_eff < pin_threshold * H_NORMAL_FROM_CAUTION:
				# recovery leg: CAUTIOUS -> NORMAL (apply bias)
				var p: float = _rate_to_prob(_apply_recovery_bias(L_CAUTIOUS_TO_NORMAL), dt_trial)
				if roll < p:
					_set_state(MoraleState.NORMAL)

		MoraleState.PINNED:
			if s_eff >= panic_threshold:
				var p: float = _rate_to_prob(L_PINNED_TO_PANIC, dt_trial)
				if roll < p:
					_set_state(MoraleState.PANIC)
			#elif s_eff < pin_threshold * H_CAUTION_FROM_PINNED:
			#else: # make recovery possible even tho S_eff is high
				## recovery leg: PINNED -> CAUTIOUS (apply bias)
				#var p: float = _rate_to_prob(_apply_recovery_bias(0.50), dt_trial)
				#if roll < p:
					#_set_state(MoraleState.CAUTIOUS)
			else:
				# recovery hazard ramps from 0 → base, then gets recovery_bias
				var lambda_unpin: float = L_PINNED_TO_CAUTIOUS * _unpin_ramp_multiplier()
				lambda_unpin = _apply_recovery_bias(lambda_unpin)
				var p_unpin: float = _rate_to_prob(lambda_unpin, dt_trial)
				if roll < p_unpin:
					_set_state(MoraleState.CAUTIOUS)
		MoraleState.PANIC:
			# use panic_threshold hysteresis, not pin_threshold
			if s_eff < panic_threshold * H_CAUTION_FROM_PANIC:
				# recovery leg: PANIC -> CAUTIOUS (apply bias)
				var p: float = _rate_to_prob(_apply_recovery_bias(L_PANIC_TO_CAUTIOUS), dt_trial)
				if roll < p:
					_set_state(MoraleState.CAUTIOUS)
					
					
func _rate_to_prob(rate_per_sec: float, dt: float) -> float:
	if rate_per_sec < 0.0:
		rate_per_sec = 0.0
	return 1.0 - exp(-rate_per_sec * dt)

func _set_state(next: int) -> void:
	return
	if next == state:
		return
	var prev: int = state
	state = next
	_since_change = 0.0
	state_changed.emit(prev, next)
	
	# reset ramp when we unpin (PINNED → CAUTIOUS)
	match next:
		MoraleState.CAUTIOUS:
			if prev == MoraleState.PINNED:
				_repin_since_unpin = 0.0
		MoraleState.PINNED:
			_since_pinned = 0.0


# smooth, frame-rate-friendly ramp 0..1
func _repin_ramp_multiplier() -> float:
	# 1 - exp(-t/τ) rises fast then eases in; τ = repin_ramp_s
	if state != MoraleState.CAUTIOUS:
		return 1.0
	var tau: float = max(0.001, repin_ramp_s)  # avoid div-by-zero
	#var m: float = 1.0 - exp(-_repin_since_unpin / tau)
	var m: float = _repin_since_unpin / tau
	return clampf(m, 0.0, 1.0)


func _unpin_ramp_multiplier() -> float:
	# 1 - exp(-t/τ): rises quick, eases in; τ = unpin_ramp_s
	if state != MoraleState.PINNED:
		return 1.0
	var tau: float = max(0.001, unpin_ramp_s)  # avoid div-by-zero
	#var m: float = 1.0 - exp(-_since_pinned / tau)
	var m: float = _repin_since_unpin / tau
	return clampf(m, 0.0, 1.0)


func _clamp_bins() -> void:
	if stress_fast < 0.0:
		stress_fast = 0.0
	if stress_slow < 0.0:
		stress_slow = 0.0
	if stress_fast > S_CAP:
		stress_fast = S_CAP
	if stress_slow > S_CAP:
		stress_slow = S_CAP

func _apply_recovery_bias(lambda_per_s: float) -> float:
	# >1.0 makes recovery faster; =1.0 neutral; <1.0 slower
	var biased: float = lambda_per_s * recovery_bias
	return max(0.0, biased)
