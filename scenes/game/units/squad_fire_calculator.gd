extends Node
class_name SquadFireCalculator

# --- High-level idea, mate ---
# 1) Allocate available soldiers to crew-served weapons (MGs first by default).
# 2) Compute expected rounds over a time slice (dt) for each piece:
#    - Individual weapons: shooters * rpm
#    - Crew-served: burst model + cyclic cap, scaled by crew fraction and ROF state.
# 3) Return a combined volley with a breakdown, ready for your resolve_volley().

enum WeaponKind {
	INDIVIDUAL,    # 1 shooter per weapon (e.g., bolt-action rifle)
	CREW_SERVED    # needs crew (e.g., MG, mortar, HMG)
}

# A concrete piece of equipment held by the squad.
class EquipmentInstance:
	var spec: WeaponSpec
	var assigned_crew: int
	var count: int                        # How many copies of this spec (e.g., 1x MG, or 2x MGs)

	func _init(p_spec: WeaponSpec, p_count: int) -> void:
		spec = p_spec
		assigned_crew = 0
		count = p_count

# Input structure for a squad this tick.
class SquadFireInput:
	var total_soldiers_present: int
	var state_rof_mult: float             # From morale/state (e.g., Normal=1.0, Cautious=0.7, Pinned=0.3)
	var dt_seconds: float
	var individual_weapon: WeaponSpec     # The default rifle/SMG spec carried by ordinary shooters
	var crew_equipment: Array[EquipmentInstance]

	func _init() -> void:
		total_soldiers_present = 10
		state_rof_mult = 1.0
		dt_seconds = 1.0
		individual_weapon = WeaponSpec.new()
		individual_weapon.name = "Bolt-action Rifle"
		individual_weapon.kind = WeaponSpec.WeaponKind.PERSONAL
		individual_weapon.rpm = 15.0
		crew_equipment = []

# Output of the calculator.
class VolleyResult:
	var total_rounds: int
	var individual_rounds: int
	var burst_rounds: int
	var by_source: Array[Dictionary]  # Each: { "name": String, "rounds": int, "meta": Dictionary }

	func _init() -> void:
		total_rounds = 0
		individual_rounds = 0
		burst_rounds = 0
		by_source = []

# --- Public entry point ---
func build_volley(input: SquadFireInput) -> VolleyResult:
	var result: VolleyResult = VolleyResult.new()

	# 1) Crew allocation to crew-served weapons by priority, then fill remainder as riflemen.
	var remaining_men: int = input.total_soldiers_present
	remaining_men = _allocate_crew(input.crew_equipment, remaining_men)

	var individual_rounds: int = 0
	# 2) Individual fire (whoever isn’t crewing).
	if input.individual_weapon != null:
		if input.individual_weapon.kind == WeaponKind.INDIVIDUAL:
			individual_rounds = _expected_individual_rounds(input.individual_weapon, remaining_men, input.state_rof_mult, input.dt_seconds)
			if individual_rounds > 0:
				result.by_source.append({
					"name": "%s x %d" % [input.individual_weapon.name, remaining_men],
					"rounds": individual_rounds,
					"meta": {
						"shooters": remaining_men,
						"rpm_each": input.individual_weapon.rpm,
						"state_mult": input.state_rof_mult
					}
				})

	# 3) Crew-served fire for each equipment instance.
	var mg_total: int = 0
	for i in input.crew_equipment.size():
		var eq: EquipmentInstance = input.crew_equipment[i]
		var per_item_rounds: int = 0
		if eq.spec != null:
			if eq.spec.kind == WeaponKind.CREW_SERVED:
				for j in eq.count:
					var crew_for_this: int = int(floor(float(eq.assigned_crew) / float(eq.count)))
					var rounds_j: int = _expected_crew_served_rounds(eq.spec, crew_for_this, input.state_rof_mult, input.dt_seconds)
					per_item_rounds += rounds_j
		if per_item_rounds > 0:
			mg_total += per_item_rounds
			result.by_source.append({
				"name": "%s x %d" % [eq.spec.name, eq.count],
				"rounds": per_item_rounds,
				"meta": {
					"assigned_crew_total": eq.assigned_crew,
					"per_item_assigned": int(floor(float(eq.assigned_crew) / float(eq.count))),
					"crew_required": eq.spec.crew_required,
					"burst_rounds": eq.spec.burst_rounds,
					"burst_pause_s": eq.spec.burst_pause_s,
					"rpm": eq.spec.rpm,
					"state_mult": input.state_rof_mult
				}
			})

	# 4) Sum up.
	result.total_rounds = individual_rounds + mg_total
	result.individual_rounds = individual_rounds
	result.burst_rounds = mg_total
	return result

# --- Crew allocation: highest priority first ---
func _allocate_crew(crew_eq: Array[EquipmentInstance], available: int) -> int:
	if crew_eq.is_empty():
		return available

	crew_eq.sort_custom(_cmp_priority_desc)
	for idx in crew_eq.size():
		var eq: EquipmentInstance = crew_eq[idx]
		eq.assigned_crew = 0

	for i in crew_eq.size():
		var eq_i: EquipmentInstance = crew_eq[i]
		var needed_per_item: int = eq_i.spec.crew_required
		for t in eq_i.count:
			if available <= 0:
				break
			# Assign as much as we can up to crew_required for this item, but allow partial manning.
			var to_assign: int = needed_per_item
			if to_assign > available:
				to_assign = available
			eq_i.assigned_crew += to_assign
			available -= to_assign

	return available

func _cmp_priority_desc(a: EquipmentInstance, b: EquipmentInstance) -> bool:
	if a.spec.priority > b.spec.priority:
		return true
	else:
		if a.spec.priority < b.spec.priority:
			return false
		else:
			return a.spec.name < b.spec.name

# --- INDIVIDUAL weapons rounds ---
func _expected_individual_rounds(spec: WeaponSpec, shooters: int, rof_mult: float, dt: float) -> int:
	if shooters <= 0:
		return 0
	var rpm_each: float = spec.rpm * rof_mult
	if rpm_each < 0.0:
		rpm_each = 0.0
	var rounds_f: float = float(shooters) * rpm_each * (dt / 60.0)
	if rounds_f < 0.0:
		rounds_f = 0.0
	return int(round(rounds_f))

# --- CREW-SERVED weapons rounds ---
func _expected_crew_served_rounds(spec: WeaponSpec, assigned_crew: int, rof_mult: float, dt: float) -> int:
	if assigned_crew <= 0:
		return 0

	# Crew effectiveness curve:
	#   full crew => 1.0
	#   under-crewed => (assigned/required) ^ undercrew_penalty_exp   (harsher than linear if exp > 1)
	var crew_frac: float = 1.0
	if spec.crew_required > 0:
		crew_frac = float(assigned_crew) / float(spec.crew_required)
	if crew_frac > 1.0:
		crew_frac = 1.0
	if crew_frac < 0.0:
		crew_frac = 0.0

	var crew_eff: float = pow(crew_frac, spec.undercrew_penalty_mult)

	# Burst model to get expected bursts over dt.
	var cyclic_rps: float = spec.rpm / 60.0
	if cyclic_rps < 0.0001:
		cyclic_rps = 0.0001

	var burst_time_s: float = float(spec.burst_rounds) / cyclic_rps
	var cycle_time_s: float = burst_time_s + spec.burst_pause_s
	if cycle_time_s <= 0.0:
		cycle_time_s = burst_time_s

	var bursts_expected: float = dt / cycle_time_s
	if bursts_expected < 0.0:
		bursts_expected = 0.0

	var rounds_expected_f: float = bursts_expected * float(spec.burst_rounds)

	# Apply crew effectiveness and state ROF multiplier.
	rounds_expected_f *= crew_eff * rof_mult

	# Safety clamp to cyclic ceiling over dt (can happen with tiny pause/big dt combos).
	var absolute_max: float = spec.rpm * (dt / 60.0)
	if rounds_expected_f > absolute_max:
		rounds_expected_f = absolute_max
	if rounds_expected_f < 0.0:
		rounds_expected_f = 0.0

	return int(round(rounds_expected_f))
