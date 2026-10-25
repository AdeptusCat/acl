class_name StressController
extends Node

const BALANCE_SAMPLE_SECONDS: float = 0.5
const BALANCE_WINDOW_SAMPLES: int = 4

var _state_mod_dict: Dictionary[STATES.MoraleState, float] = {
		STATES.MoraleState.NORMAL : 1.0,
		STATES.MoraleState.CAUTIOUS : 0.85,
		STATES.MoraleState.PINNED : 0.55,
		STATES.MoraleState.PANIC : 0.3,
		STATES.MoraleState.COMBAT_INEFFECTIVE : 0.0,
	}

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
#@export var L_NORMAL_TO_PANIC: float   = 0.70
@export var L_NORMAL_TO_PANIC: float   = 0.00
@export var L_NORMAL_TO_PINNED: float  = 0.55
@export var L_NORMAL_TO_CAUTIOUS: float= 0.40

# CAUTIOUS →
#@export var L_CAUTIOUS_TO_PANIC: float = 0.60
@export var L_CAUTIOUS_TO_PANIC: float = 0.00
@export var L_CAUTIOUS_TO_PINNED: float= 0.90 # 0.30  # base; scaled by re-pin ramp
@export var L_CAUTIOUS_TO_NORMAL: float= 0.45   # recovery; gets recovery_bias

# PINNED →
#@export var L_PINNED_TO_PANIC: float   = 0.35
@export var L_PINNED_TO_PANIC: float   = 0.00
@export var L_PINNED_TO_CAUTIOUS: float= 0.35   # recovery; ramped, then gets recovery_bias

# PANIC →
@export var L_PANIC_TO_CAUTIOUS: float = 0.1   # recovery; gets recovery_bias

# --- TUNABLES: ramps (seconds to go 0 → 100%) ---
@export var repin_ramp_s: float  = 10.0   # CAUTIOUS→PINNED hazard ramps up after unpin
@export var unpin_ramp_s: float  = 10.0   # PINNED→CAUTIOUS hazard ramps up while pinned
@export var unpin_no_fire_delay_s: float = 3.0 # quiet time after the incoming-fire window expires
@export var rout_ramp_s: float  = 10.0    # ROUT hazard ramps up while pinned

# --- INTERNALS: timers for ramps ---
var _repin_since_unpin: float = 999.0	    # seconds since PINNED→CAUTIOUS; big at start
var _since_pinned: float      = 999.0		# seconds since we entered PINNED
var _since_rout_check: float  = 999.0		# seconds since we checked for rout

# how leaders affect the *rate* the lads get rattled
@export var leader_gain_reduction_max: float = 0.5      # up to 50% less *incoming* stress
@export var leader_decay_boost_max: float = 0.15        # up to 15% faster decay
@export var leader_effect_smooth_s: float = 0.5         # seconds to blend leader influence
@export var command_gain_reduction_max: float = 0.15  # full command presence reduces incoming stress by 15%
@export var min_incoming_gain_mult: float = 0.75      # all leadership protection is capped at 25%
@export var leader_recovery_bonus: float = 0.5        # full presence adds at most 50% recovery
@export var leader_ineffective_recovery: float = 0.3  # limited recovery when no inherent capacity remains

# --- internal accumulator for trial cadence ---
var _trial_bucket_s: float = 0.0
var _leadership_sources: Dictionary = {}  # key: int (source_id), value: LeadershipMod
var _leader_effect: float = 0.0   # 0..1 smoothed from leadership_bonu

# --- NEW: caps & scaling ---
@export var S_CAP: float = 100.0                 # hard ceiling on stress
@export var incoming_stress_scale: float = 1.0   # global multiplier on added stress
@export var recovery_scale: float = 1.0          # >1 faster decay, <1 slower decay (global)
@export var base_recovery_per_second: float = 1.5 # inherent recovery before morale and situational modifiers
@export var hq_recovery_multiplier: float = 2.0
@export var hq_panic_recovery_floor: float = 0.6 # morale recovery factor before base/situational scaling
@export var hq_rally_multiplier: float = 2.0
@export var cohesion_recovery_floor: float = 0.25
@export var casualty_recovery_window_s: float = 120.0
@export var casualty_recovery_slowdown: float = 0.25
@export var casualty_shock_per_loss: float = 0.35
@export var leader_loss_recovery_shock: float = 0.5

# --- NEW: slower recovery while under fire ---
@export var under_fire_window_s: float = 2.0     # seconds considered "under fire" after a volley
@export var pressure_ref_rps: float = 10.0       # rounds/sec counted as "heavy"
@export var slowdown_light: float = 0.65        # retain useful inherent recovery under intermittent fire
@export var slowdown_heavy: float = 0.25        # sustained heavy fire still suppresses recovery
@export var stop_fast_decay_when_heavy: bool = false  # freeze fast-stress decay at heavy pressure

# --- slower recovery when panic ---
@export var panic_decay_mult_slow: float = 1.0            # 0..1; lower = slower recovery while panicking
@export var panic_decay_mult_fast: float = 0.2            # 0..1; lower = slower recovery while panicking
@export var panic_freeze_fast_when_panic: bool = false # if true, fast-stress doesn’t decay in PANIC

# --- STATE ---
var stress_fast: float = 0.0
var stress_slow: float = 0.0
var S_eff: float = 0.0
var state: STATES.MoraleState = STATES.MoraleState.NORMAL
var _since_change: float = 999.0

# --- RUNTIME (under fire) ---
var _how_long_under_fire_s: float = 0.0
var _how_long_under_fire_util_rout_s: float = 4.0
var _under_fire_t: float = 0.0
var _last_pressure_rps: float = 0.0
var _time_without_fire_s: float = 0.0
var _fire_pressure_samples: Array[FirePressureSample] = []
var under_fire: bool = false

# Actual change stays separate from recovery capacity when the stress bins are empty.
var incoming_stress_rate: float = 0.0
var stress_recovery_rate: float = 0.0
var recovery_capacity_rate: float = 0.0
var net_stress_rate: float = 0.0
var balance_sample_duration_s: float = 0.0
var _balance_elapsed_s: float = 0.0
var _balance_stress_added: float = 0.0
var _balance_stress_recovered: float = 0.0
var _balance_recovery_capacity: float = 0.0
var _balance_history: Array[StressBalanceSample] = []

# --- SIGNALS ---
signal state_changed(previous: int, next: int)
signal stress_changed(effective_stress: float)
signal stress_balance_changed(incoming_rate: float, recovery_capacity: float, actual_recovery_rate: float, net_rate: float)
signal leadership_changed(_leadership_bonus: float)

var leader_presence_strength: float = 0.0
var _leadership_cohesion_mult: float = 1.0
var _casualty_recovery_t: float = 0.0
var _casualty_recovery_shock: float = 0.0

class StressGain:
	var fast: float
	var slow: float

	func _init(fast_gain: float, slow_gain: float) -> void:
		fast = fast_gain
		slow = slow_gain

class FirePressureSample:
	var rounds: float
	var age_s: float = 0.0

	func _init(round_count: float) -> void:
		rounds = round_count

class StressBalanceSample:
	var duration_s: float
	var added: float
	var recovered: float
	var capacity: float

	func _init(duration: float, gain: float, recovery: float, available_recovery: float) -> void:
		duration_s = duration
		added = gain
		recovered = recovery
		capacity = available_recovery

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
	#var total_bonus: float = 0.0
	#var total_rally: float = 0.0
	#var total_cohesion_mult: float = 1.0
	var max_total_bonus: float = 0.0
	#var max_rally: float = 0.0
	var max_cohesion_mult: float = 1.0
	for lm: LeadershipMod in _leadership_sources.values():
		if lm.bonus > max_total_bonus:
			max_total_bonus = lm.bonus
		if lm.cohesion_mult > max_cohesion_mult:
			max_cohesion_mult = lm.cohesion_mult
		#total_bonus += lm.bonus
		#total_rally += lm.rally
		#total_cohesion_mult *= lm.cohesion_mult
	#leadership_bonus = total_bonus
	leadership_bonus = max_total_bonus
	#cohesion = clamp(cohesion * total_cohesion_mult, 0.0, 1.5)
	_leadership_cohesion_mult = max_cohesion_mult
	leadership_changed.emit(leadership_bonus)


# Hook this into your recovery rolls (where you already compute recovery chances).
# Example stub you can call inside your recovery logic:
func get_rally_bonus() -> float:
	var s: float = 0.0
	for lm: LeadershipMod in _leadership_sources.values():
		s += lm.rally
	return s


func get_average_stress_rate() -> float:
	return incoming_stress_rate


func _update_effective_stress() -> void:
	# The gameplay meter gives the fast and slow bins equal weight.
	S_eff = clampf((stress_fast + stress_slow) * 0.5, 0.0, S_CAP)


func _sample_stress_balance(delta: float) -> void:
	_balance_elapsed_s += delta
	if _balance_elapsed_s < BALANCE_SAMPLE_SECONDS:
		return
	_balance_history.append(StressBalanceSample.new(_balance_elapsed_s, _balance_stress_added, _balance_stress_recovered, _balance_recovery_capacity))
	if _balance_history.size() > BALANCE_WINDOW_SAMPLES:
		_balance_history.pop_front()
	# Duration-weighted averages preserve the measured gain/loss at varying frame rates.
	balance_sample_duration_s = 0.0
	var added: float = 0.0
	var recovered: float = 0.0
	var capacity: float = 0.0
	for sample: StressBalanceSample in _balance_history:
		balance_sample_duration_s += sample.duration_s
		added += sample.added
		recovered += sample.recovered
		capacity += sample.capacity
	incoming_stress_rate = added / balance_sample_duration_s
	stress_recovery_rate = recovered / balance_sample_duration_s
	recovery_capacity_rate = capacity / balance_sample_duration_s
	net_stress_rate = incoming_stress_rate - stress_recovery_rate
	_balance_elapsed_s = 0.0
	_balance_stress_added = 0.0
	_balance_stress_recovered = 0.0
	_balance_recovery_capacity = 0.0
	stress_balance_changed.emit(incoming_stress_rate, recovery_capacity_rate, stress_recovery_rate, net_stress_rate)


func get_recovery_capacity() -> float:
	var squad_bonus: float = _state_mod_dict[state]
	var leader_presence: float = clampf(leader_presence_strength, 0.0, 1.0)
	# Command improves the squad's own recovery instead of replacing impaired morale.
	var combined: float = squad_bonus * (1.0 + maxf(leader_recovery_bonus, 0.0) * leader_presence)
	if state == STATES.MoraleState.COMBAT_INEFFECTIVE:
		combined = maxf(leader_ineffective_recovery, 0.0) * leader_presence
	if _is_headquarters():
		combined *= maxf(hq_recovery_multiplier, 0.0)
		if state == STATES.MoraleState.PANIC:
			combined = maxf(combined, hq_panic_recovery_floor)
	return combined * maxf(base_recovery_per_second, 0.0) * maxf(recovery_scale, 0.0) * _situational_recovery_multiplier()


func _process(delta: float) -> void:
	_advance_fire_pressure(delta)
	
	# Attention gains enter the same bins and balance sample before recovery/morale.
	_apply_attention_stress(delta)
	match state:
		STATES.MoraleState.CAUTIOUS:
			_repin_since_unpin += delta
		STATES.MoraleState.NORMAL:
			_repin_since_unpin += delta
		STATES.MoraleState.PINNED:
			_since_pinned += delta
			_since_rout_check += delta
			# HACK checking for route should be more complex than this
			if not get_parent().surrendered:
				for _unit: Unit in Globals.get_units():
					if not _unit.alive:
						continue
					if not _unit.team == get_parent().team:
						if _unit.is_good_order():
							if LOSHelper.ground_layer.cube_distance(get_parent().current_cube, _unit.current_cube) <= 1:
								if S_eff >= 90.0:
									if _since_rout_check >= 2.0:
										var roll: float = randf()
										if roll > 0.5:
											_set_state(STATES.MoraleState.PANIC)
										_since_rout_check = 0.0
		STATES.MoraleState.PANIC:
			_since_rout_check += delta
			if not get_parent().surrendered:
				for _unit: Unit in Globals.get_units():
					if not _unit.alive:
						continue
					if not _unit.team == get_parent().team:
						if _unit.is_good_order():
							if LOSHelper.ground_layer.cube_distance(get_parent().current_cube, _unit.current_cube) <= 1:
								if _since_rout_check >= 2.0:
									var roll: float = randf()
									if roll > 0.5:
										get_parent().action_controller._start_rout()
									_since_rout_check = 0.0
			
			
			#if _how_long_under_fire_s > _how_long_under_fire_util_rout_s:
				#state_changed.emit(state, state)
				#_how_long_under_fire_s = 0.0
	#
	#if not state == STATES.MoraleState.PANIC:
		#_how_long_under_fire_s = 0.0
	
	## decay using exponential form so we can scale the *rate* cleanly
	#var ln2: float = 0.69314718056
	#var lambda_fast: float = 0.0
	#var lambda_slow: float = 0.0
#
	#if half_life_fast > 0.0:
		#lambda_fast = ln2 * delta / half_life_fast
	#if half_life_slow > 0.0:
		#lambda_slow = ln2 * delta / half_life_slow
#
	## global recovery scaling
	#if recovery_scale < 0.0:
		#recovery_scale = 0.0
	#lambda_fast *= recovery_scale
	#lambda_slow *= recovery_scale
#
	## slower decay while under fire
	#if _under_fire_t > 0.0:
		#_how_long_under_fire_s += delta
		#var x: float = 0.0
		#if pressure_ref_rps > 0.0:
			#x = clamp(_last_pressure_rps / pressure_ref_rps, 0.0, 1.0)
		## map pressure to a rate multiplier between light and heavy slowdowns
		#var rate_mult: float = lerp(slowdown_light, slowdown_heavy, x)
		#if rate_mult < 0.0:
			#rate_mult = 0.0
		#lambda_fast *= rate_mult
		#lambda_slow *= rate_mult
		## optional: freeze fast-stress under heavy pressure
		#if stop_fast_decay_when_heavy:
			#if _last_pressure_rps >= pressure_ref_rps:
				#lambda_fast = 0.0
#
		#_under_fire_t -= delta
		#if _under_fire_t < 0.0:
			#_under_fire_t = 0.0
#
	## --- panic slows recovery ---
	#if state == STATES.MoraleState.PANIC:
		#var m_slow: float = clamp(panic_decay_mult_slow, 0.0, 1.0)
		#var m_fast: float = clamp(panic_decay_mult_fast, 0.0, 1.0)
		#lambda_slow *= m_slow
		#lambda_fast *= m_fast
		#if panic_freeze_fast_when_panic:
			#lambda_fast = 0.0
		#if get_parent().movement.retreating:
			#lambda_slow = 0.0
			#lambda_fast = 0.0
	## --- leader speeds recovery a touch, still rate-based ---
	#var decay_boost: float = 1.0 + _leader_effect * 10.0
	## turn rates into multipliers
	#var kf: float = 1.0
	#var ks: float = 1.0
	#if lambda_fast > 0.0:
		#lambda_fast *= decay_boost
		#kf = exp(-lambda_fast)
	#if lambda_slow > 0.0:
		#lambda_slow *= decay_boost
		#ks = exp(-lambda_slow)

	
	
	
	# apply decay
	#stress_fast *= (kf * (1.0 - leader_presence_strength)  )
	#stress_slow *= (ks * (1.0 - leader_presence_strength)  )
	#stress_fast *= (kf * 0.9)
	#stress_slow *= (ks * 0.9)
	#stress_fast *= kf
	#stress_slow *= ks
	
	_clamp_bins()
	_update_effective_stress()
	var stress_before_recovery: float = S_eff
	
	# This same capacity drives gameplay decay and the green-arrow magnitude.
	var combined: float = get_recovery_capacity()
	var stress_decay_f_per_second: float = combined
	var stress_decay_s_per_second: float = combined
	#if leader_presence_strength == 0.0:
		#stress_decay_f_per_second = 0.1
		#stress_decay_s_per_second = 0.1
	var stress_decay_f_with_delta: float = stress_decay_f_per_second * delta
	var stress_decay_s_with_delta: float = stress_decay_s_per_second * delta
	stress_fast -= stress_decay_f_with_delta
	stress_slow -= stress_decay_s_with_delta
	_clamp_bins()
	_update_effective_stress()
	_balance_stress_recovered += maxf(0.0, stress_before_recovery - S_eff)
	_balance_recovery_capacity += combined * delta
	_sample_stress_balance(delta)
	
	## --- smooth leader effect so it never steps the meter ---
	#var target_leader: float = clamp(leadership_bonus, 0.0, 1.0)
	#var blend: float = 1.0
	#if leader_effect_smooth_s > 0.0:
		#blend = clamp(delta / leader_effect_smooth_s, 0.0, 1.0)
	#_leader_effect = lerp(_leader_effect, target_leader, blend)
#
	## effective stress with leadership & cohesion softening
	##var softener: float = 1.0 - clamp(0.5 * leadership_bonus + 0.3 * cohesion, 0.0, 0.6)
	#var _softener: float = 1.0 - clamp(0.5 * leadership_bonus, 0.0, 0.6)
	##S_eff = (w_fast * stress_fast + w_slow * stress_slow) # * softener
	##S_eff = stress_fast + stress_slow
	##S_eff *= 4.0
	##S_eff *= leader_presence_strength
	##if (leader_presence_strength > 0.0):
		##print(S_eff)

	#if leadership_bonus > 0.0:
		#pass

	_since_change += delta
	_maybe_transition(delta)
	_casualty_recovery_t = maxf(0.0, _casualty_recovery_t - delta)
	if _casualty_recovery_t <= 0.0:
		_casualty_recovery_shock = 0.0
	stress_changed.emit(S_eff)
	
	

# Final volley gain: existing suppression + surprise + multi-direction pressure
# + casualty shock. Continuous overload/switching enter through the same apply_stress.
# Tactical-condition flags add no second geometry penalty.
static func calculate_incoming_fire_stress(controller: SquadFireController, suppression: StressGain, casualty_shock: StressGain, attention_effects: Vector2) -> StressGain:
	var volley_cap: float = maxf(controller.stress_max_per_volley, 0.0)
	var existing_fast: float = clampf(suppression.fast, 0.0, volley_cap)
	var existing_slow: float = clampf(suppression.slow, 0.0, volley_cap)
	var surprise: float = maxf(controller.stress_surprise_bonus, 0.0) * clampf(attention_effects.x, 0.0, 1.0)
	var multi_direction: float = maxf(controller.stress_crossfire_bonus, 0.0) * clampf(attention_effects.y, 0.0, 1.0)
	var fast: float = minf(existing_fast + existing_fast * surprise + existing_fast * multi_direction, volley_cap)
	var slow: float = minf(existing_slow + existing_slow * multi_direction, volley_cap)
	var casualty_cap: float = maxf(controller.stress_kill_max_per_volley, 0.0)
	return StressGain.new(fast + clampf(casualty_shock.fast, 0.0, casualty_cap), slow + clampf(casualty_shock.slow, 0.0, casualty_cap))


func _apply_attention_stress(delta: float) -> void:
	var unit: Unit = get_parent() as Unit
	if unit == null or not unit.is_active() or unit.surrendered or unit.members_alive <= 0 or unit.tactical_state == null:
		return
	# Advance even with damage disabled so switching recovery/detection keep running.
	var costs: Vector2 = unit.tactical_state.advance_attention(delta)
	if Debug.no_damage or costs.length_squared() <= 0.0:
		return
	# Overload is sustained (both bins); switching is transient (fast bin only).
	apply_stress(costs.x + costs.y, costs.x, "attention")


# All stress sources share gain modifiers, bin caps and actual-gain accounting.
func apply_stress(df: float, ds: float, cause: String = "event") -> void:
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
	var command_presence: float = clampf(leader_presence_strength, 0.0, 1.0)
	leader_mult *= 1.0 - clampf(command_gain_reduction_max, 0.0, 1.0) * command_presence
	if leader_mult < min_incoming_gain_mult:
		leader_mult = min_incoming_gain_mult
	if leader_mult > 1.0:
		leader_mult = 1.0

	var eff_scale: float = base_scale * leader_mult
	_clamp_bins()
	_update_effective_stress()
	var stress_before_gain: float = S_eff
	var bins_before_gain: Vector2 = Vector2(stress_fast, stress_slow)
	var stress_mod: float = remap(S_eff, 0.0, maxf(S_CAP, 0.001), 1.0, 0.5)
	# FIXME cmd stress modifier needs adjustment
	#print(S_eff, " ", stress_mod)
	stress_fast += df_in * eff_scale * stress_mod
	stress_slow += ds_in * eff_scale * stress_mod
	_clamp_bins()
	_update_effective_stress()
	_balance_stress_added += maxf(0.0, S_eff - stress_before_gain)
	if is_instance_valid(Debug.engagement_recorder):
		Debug.engagement_recorder.record_stress_gain(get_parent() as Unit, df_in, ds_in, bins_before_gain, cause)
	stress_changed.emit(S_eff)


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
	if n == 0 and not leader_down:
		return
	_casualty_recovery_t = maxf(casualty_recovery_window_s, 0.0)
	_casualty_recovery_shock += float(n) * maxf(casualty_shock_per_loss, 0.0)
	if leader_down:
		_casualty_recovery_shock += maxf(leader_loss_recovery_shock, 0.0)
	_casualty_recovery_shock = clampf(_casualty_recovery_shock, 0.0, 1.0)
	#stress_fast += 10.0 * float(n) * leader_presence_strength
	#stress_slow += 4.0 * float(n) * leader_presence_strength
	#if leader_down:
		#stress_fast += 20.0 * leader_presence_strength
		#stress_slow += 8.0 * leader_presence_strength
	#_clamp_bins()

# Accept rounds, not a rate: callers can submit individual bullets or whole volleys.
func mark_under_fire(rounds: float) -> void:
	if not is_finite(rounds) or rounds <= 0.0:
		return
	# Coalesce simultaneous impacts without losing their combined volume.
	if not _fire_pressure_samples.is_empty() and _fire_pressure_samples.back().age_s == 0.0:
		_fire_pressure_samples.back().rounds += rounds
	else:
		_fire_pressure_samples.append(FirePressureSample.new(rounds))
	_advance_fire_pressure(0.0)


func _advance_fire_pressure(delta: float) -> void:
	var window_s: float = maxf(under_fire_window_s, 0.0)
	var previous_remaining_s: float = _under_fire_t
	_last_pressure_rps = 0.0
	_under_fire_t = 0.0
	for index: int in range(_fire_pressure_samples.size() - 1, -1, -1):
		var sample: FirePressureSample = _fire_pressure_samples[index]
		sample.age_s += maxf(delta, 0.0)
		if sample.age_s >= window_s:
			_fire_pressure_samples.remove_at(index)
			continue
		var remaining_s: float = window_s - sample.age_s
		# A triangular kernel with unit area preserves rounds/second at steady fire.
		_last_pressure_rps += sample.rounds * 2.0 * remaining_s / (window_s * window_s)
		_under_fire_t = maxf(_under_fire_t, remaining_s)
	under_fire = _under_fire_t > 0.0
	if under_fire:
		_time_without_fire_s = 0.0
	else:
		# Count only the part of this step after the last sample expired.
		_time_without_fire_s += maxf(0.0, delta - maxf(previous_remaining_s, 0.0))

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
		STATES.MoraleState.NORMAL:
			#if s_eff >= panic_threshold:
				#var p: float = _rate_to_prob(L_NORMAL_TO_PANIC, dt_trial)
				#if roll < p:
					#_set_state(STATES.MoraleState.PANIC)
			if s_eff >= pin_threshold:
				if under_fire:
					var p: float = _rate_to_prob(L_NORMAL_TO_PINNED, dt_trial)
					if roll < p:
						_set_state(STATES.MoraleState.PINNED)
			elif s_eff >= pin_threshold * H_CAUTION_FROM_NORMAL:
				if under_fire:
					var p: float = _rate_to_prob(L_NORMAL_TO_CAUTIOUS, dt_trial)
					if roll < p:
						_set_state(STATES.MoraleState.CAUTIOUS)

		STATES.MoraleState.CAUTIOUS:
			#if s_eff >= panic_threshold:
				#var p: float = _rate_to_prob(L_CAUTIOUS_TO_PANIC, dt_trial)
				#if roll < p:
					#_set_state(STATES.MoraleState.PANIC)
			if s_eff >= pin_threshold:
				if under_fire:
					# base hazard is 0.30; ramp it from 0 → 0.30 after unpin
					var repin_ramp_multiplier: float = _repin_ramp_multiplier()
					var lambda: float = L_CAUTIOUS_TO_PINNED * repin_ramp_multiplier
					var rate: float = _rate_to_prob(lambda, dt_trial)
					if roll < rate:
						_set_state(STATES.MoraleState.PINNED)
			elif s_eff < pin_threshold * H_NORMAL_FROM_CAUTION:
				# recovery leg: CAUTIOUS -> NORMAL (apply bias)
				var p: float = _rate_to_prob(_apply_recovery_bias(L_CAUTIOUS_TO_NORMAL), dt_trial)
				if roll < p:
					_set_state(STATES.MoraleState.NORMAL)

		STATES.MoraleState.PINNED:
			# High stress blocks ordinary unpinning under fire. After a quiet
			# interval, allow the existing rally roll without requiring stress
			# to cross 65 first; cautious morale restores useful recovery.
			if s_eff >= panic_threshold and not _can_unpin_after_fire():
				var p: float = _rate_to_prob(L_PINNED_TO_PANIC, dt_trial)
				if roll < p:
					_set_state(STATES.MoraleState.PANIC)
			else:
				# recovery hazard ramps from 0 → base, then gets recovery_bias
				var lambda_unpin: float = L_PINNED_TO_CAUTIOUS * _unpin_ramp_multiplier()
				lambda_unpin = _apply_recovery_bias(lambda_unpin)
				var p_unpin: float = _rate_to_prob(lambda_unpin, dt_trial)
				if roll < p_unpin:
					_set_state(STATES.MoraleState.CAUTIOUS)
		STATES.MoraleState.PANIC:
			# use panic_threshold hysteresis, not pin_threshold
			if s_eff < panic_threshold * H_CAUTION_FROM_PANIC:
				# recovery leg: PANIC -> CAUTIOUS (apply bias)
				var p: float = _rate_to_prob(_apply_recovery_bias(L_PANIC_TO_CAUTIOUS), dt_trial)
				if roll < p:
					_set_state(STATES.MoraleState.CAUTIOUS)
					
					
func _can_unpin_after_fire() -> bool:
	return not under_fire and _time_without_fire_s >= maxf(unpin_no_fire_delay_s, 0.0)


func _rate_to_prob(rate_per_sec: float, dt: float) -> float:
	if rate_per_sec < 0.0:
		rate_per_sec = 0.0
	return 1.0 - exp(-rate_per_sec * dt)

func _set_state(next: int) -> void:
	#return
	if next == state:
		return
	var prev: int = state
	state = next
	_since_change = 0.0
	state_changed.emit(prev, next)
	
	# reset ramp when we unpin (PINNED → CAUTIOUS)
	match next:
		STATES.MoraleState.CAUTIOUS:
			if prev == STATES.MoraleState.PINNED:
				_repin_since_unpin = 0.0
		STATES.MoraleState.PINNED:
			_since_pinned = 0.0


# smooth, frame-rate-friendly ramp 0..1
func _repin_ramp_multiplier() -> float:
	# 1 - exp(-t/τ) rises fast then eases in; τ = repin_ramp_s
	if state != STATES.MoraleState.CAUTIOUS:
		return 1.0
	var tau: float = max(0.001, repin_ramp_s)  # avoid div-by-zero
	#var m: float = 1.0 - exp(-_repin_since_unpin / tau)
	var m: float = _repin_since_unpin / tau
	return clampf(m, 0.0, 1.0)


func _unpin_ramp_multiplier() -> float:
	# Recovery hazard rises linearly with time spent in the current pinned state.
	if state != STATES.MoraleState.PINNED:
		return 1.0
	var tau: float = max(0.001, unpin_ramp_s)  # avoid div-by-zero
	var m: float = _since_pinned / tau
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
	var biased: float = lambda_per_s * recovery_bias * _situational_recovery_multiplier()
	if _is_headquarters():
		biased *= maxf(hq_rally_multiplier, 0.0)
	return max(0.0, biased)


func _is_headquarters() -> bool:
	var unit: Unit = get_parent() as Unit
	return unit != null and HqSupportPositionPolicy.is_headquarters(unit)


func _situational_recovery_multiplier() -> float:
	var multiplier: float = clampf(cohesion * _leadership_cohesion_mult, clampf(cohesion_recovery_floor, 0.0, 1.0), 1.5)
	if _casualty_recovery_t > 0.0 and casualty_recovery_window_s > 0.0:
		var shock: float = _casualty_recovery_shock * clampf(_casualty_recovery_t / casualty_recovery_window_s, 0.0, 1.0)
		multiplier *= lerpf(1.0, clampf(casualty_recovery_slowdown, 0.0, 1.0), shock)
	if _under_fire_t > 0.0:
		var pressure: float = clampf(_last_pressure_rps / maxf(pressure_ref_rps, 0.001), 0.0, 1.0)
		multiplier *= lerpf(clampf(slowdown_light, 0.0, 1.0), clampf(slowdown_heavy, 0.0, 1.0), pressure)
	return multiplier
