class_name UnitCombat
extends Node

# --- STATES (unchanged) ---
enum MoraleState { NORMAL, CAUTIOUS, PINNED, PANIC, COMBAT_INEFFECTIVE }

@export var base_accuracy := 0.35
@export var volley_size := 1               # rounds per burst
@export var seconds_per_volley := 1.2
@export var base_seconds_per_volley := 1.2

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
signal new_target_unit(unit: Unit)

func _ready():
	# Define the rifle spec (individual)
	var rifle: WeaponSpec = WeaponSpec.new()
	rifle.name = "Bolt-action Rifle"
	rifle.kind = WeaponSpec.WeaponKind.PERSONAL
	rifle.rpm = 12.0  # a bit conservative for sustained fire

	# Define the MG (crew-served)
	var mg: WeaponSpec = WeaponSpec.new()
	mg.name = "GPMG"
	mg.kind = WeaponSpec.WeaponKind.CREW_SERVED
	mg.rpm = 700.0
	mg.burst_rounds = 4           # “short bursts”, aye
	mg.burst_pause_s = 0.35
	mg.crew_required = 2          # gunner + loader
	mg.undercrew_penalty_mult = 1.6
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
		var mg: WeaponSpec = WeaponSpec.new()
		mg.name = "GPMG"
		mg.kind = WeaponSpec.WeaponKind.CREW_SERVED
		mg.rpm = 700.0
		mg.burst_rounds = 4           # “short bursts”, aye
		mg.burst_pause_s = 0.35
		mg.crew_required = 2          # gunner + loader
		mg.undercrew_penalty_mult = 1.6
		mg.priority = 10              # gets crew before anything else
		var mg_eq: SquadFireCalculator.EquipmentInstance = SquadFireCalculator.EquipmentInstance.new(mg, 1)
		fin.crew_equipment.append(mg_eq)



func set_target_unit(unit: Unit):
	target_unit = unit
	new_target_unit.emit(unit)
