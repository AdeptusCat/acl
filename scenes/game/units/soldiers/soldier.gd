# Soldier.gd (plain class)
class_name Soldier
extends RefCounted


var tasks: Array[SoldierTask]
var target_id: Unit = null
var target_acquired: bool = false

var setup_weapon_task: SoldierTask = SoldierTask.new(SoldierTask.SoldierAction.SETUP_WEAPON)
var aquire_target_task: SoldierTask = SoldierTask.new(SoldierTask.SoldierAction.ACQUIRE_TARGET)
var reload_task: SoldierTask = SoldierTask.new(SoldierTask.SoldierAction.RELOAD)
var fire_weapon_task: SoldierTask = SoldierTask.new(SoldierTask.SoldierAction.FIRE_WEAPON)
var assist_task: SoldierTask = SoldierTask.new(SoldierTask.SoldierAction.ASSIST)
var close_combat_task: SoldierTask = SoldierTask.new(SoldierTask.SoldierAction.CLOSE_COMBAT)

var unit: Unit
var team: Globals.Team

var id: int
var name: String
var rank_grade: RankGrades.Grade
var role: RankGrades.Role
var weapon: WeaponSpec
var is_alive: bool = true
var casualty_record_id: String = ""

# ammo & readiness
var rounds_in_mag: int
var jammed: bool = false
var next_ready_s: float = 0.0       # simulation time when he can act again
var next_ready_delta_s: float = 0.0
var next_ready_start_s: float = 0.0

# cached multipliers (state/leadership may change these each tick)
var rof_mult: float = 1.0
var acc_mult: float = 1.0

var now_s: float = 0.0
var acquire_start_s: float = 0.0
var acquire_target_s: float = 0.0
var acquire_ready_s: float = 0.0
var last_target_hex: Vector2i = Vector2i(-9999, -9999)

# per-soldier constants (can be exported where your Soldier is created)
var base_acquire_s: float = 0.35      # default settle time for rifles
var aim_jitter_s: float = 0.2        # extra random on each target pick
var cadence_phase_s: float = 0.0      # fixed per-soldier desync in cadence

# Behavior controls willingness to expose; handling controls the physical weapon.
enum Behavior { ENGAGING, TAKING_COVER, COWERING, RECOVERING }
enum WeaponState { LOWERED, READY, PREPARING, FIRING, CYCLING, REAIMING, RELOADING, SETTING_UP, OBSERVING, COOLING, CHANGING_BARREL }

var behavior: Behavior = Behavior.ENGAGING
var weapon_state: WeaponState = WeaponState.READY
var behavior_remaining_s: float = 0.0
var reaction_tendency: float = 0.5
var weapon_raised: bool = true
var raise_remaining_s: float = 0.0
var cycle_remaining_s: float = 0.0
var reaim_remaining_s: float = 0.0
var burst_active: bool = false
var has_engagement: bool = false
var barrel_change_assisting: bool = false
var barrel_change_worked: bool = false
var _behavior_morale: int = -1
var _combat_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _reload_rounds: int = 0
var _reload_grenade: bool = false


func update_behavior(delta: float, morale: int, under_fire: bool) -> void:
	if not is_alive:
		return
	var remaining_delta: float = maxf(delta, 0.0)
	if _behavior_morale != morale:
		_behavior_morale = morale
		if morale >= STATES.MoraleState.PANIC:
			_set_behavior(Behavior.COWERING, _combat_rng.randf_range(1.5, 4.0))
		elif morale == STATES.MoraleState.PINNED:
			_choose_pressure_behavior(morale, under_fire)
	# Consume boundaries rather than rolling once per frame.
	for transition: int in range(32):
		if behavior_remaining_s > remaining_delta:
			behavior_remaining_s -= remaining_delta
			return
		remaining_delta -= behavior_remaining_s
		if morale >= STATES.MoraleState.PANIC:
			_set_behavior(Behavior.COWERING, _combat_rng.randf_range(1.5, 4.0))
		elif behavior == Behavior.TAKING_COVER or behavior == Behavior.COWERING:
			_set_behavior(Behavior.RECOVERING, _combat_rng.randf_range(0.25, 0.8))
		elif behavior == Behavior.RECOVERING:
			_set_behavior(Behavior.ENGAGING, _combat_rng.randf_range(0.6, 1.8))
		else:
			_choose_pressure_behavior(morale, under_fire)
		if remaining_delta <= 0.0:
			return


func _choose_pressure_behavior(morale: int, under_fire: bool) -> void:
	var roll: float = _combat_rng.randf()
	if morale == STATES.MoraleState.PINNED:
		if roll < 0.3:
			_set_behavior(Behavior.COWERING, _combat_rng.randf_range(1.5, 3.5))
		elif roll < 0.75:
			_set_behavior(Behavior.TAKING_COVER, _combat_rng.randf_range(0.6, 1.6))
		else:
			_set_behavior(Behavior.ENGAGING, _combat_rng.randf_range(0.6, 1.8))
	elif under_fire and roll < 0.15 + float(morale) * 0.15:
		_set_behavior(Behavior.TAKING_COVER, _combat_rng.randf_range(0.4, 1.2))
	else:
		_set_behavior(Behavior.ENGAGING, _combat_rng.randf_range(0.8, 2.0))


func _set_behavior(next: Behavior, duration: float) -> void:
	var was_exposed: bool = behavior == Behavior.ENGAGING
	behavior = next
	behavior_remaining_s = duration
	if was_exposed and next != Behavior.ENGAGING and has_engagement:
		# Preserve the contact and mechanical work, but restore the sight picture on return.
		aquire_target_task.done = false
		aquire_target_task.start_time_s = maxf(aquire_target_task.remaining_time_s, 0.15 + reaction_tendency * 0.25)


func lower_weapon() -> void:
	weapon_raised = false
	raise_remaining_s = weapon.raise_s
	weapon_state = WeaponState.LOWERED
	lose_contact()


func lose_contact() -> void:
	has_engagement = false
	aquire_target_task.target_id = null
	aquire_target_task.done = false
	aquire_target_task.start_time_s = 0.0


func begin_engagement(enemy: Unit, cell: Vector2i, distance: int, alignment: float) -> void:
	if has_engagement and aquire_target_task.target_id == enemy:
		if enemy != null or last_target_hex == cell:
			return
	var switching: bool = has_engagement
	var turn: float = 0.0
	if switching and is_instance_valid(LOSHelper.ground_layer):
		var previous_direction: Vector2 = LOSHelper.ground_layer.map_to_local(last_target_hex) - unit.position
		var next_direction: Vector2 = LOSHelper.ground_layer.map_to_local(cell) - unit.position
		turn = absf(previous_direction.angle_to(next_direction)) / PI
	has_engagement = true
	aquire_target_task.target_id = enemy
	last_target_hex = cell
	var urgency: float = 1.0
	if distance <= 2:
		urgency = 0.4
	elif distance <= 5:
		urgency = 0.7
	var attention_delay: float = lerpf(1.6, 1.0, clampf(alignment, 0.0, 1.0))
	var reaction: float = (0.25 + pow(reaction_tendency, 1.6) * 1.3) * attention_delay
	reaction *= _combat_rng.randf_range(0.9, 1.1)
	if distance > 2:
		reaction *= 1.35
	if switching:
		reaction *= lerpf(0.55, 1.1, turn)
	var aim: float = weapon.aim_s * urgency * attention_delay
	aim *= _combat_rng.randf_range(1.0 - weapon.aim_variation, 1.0 + weapon.aim_variation)
	if switching:
		aim *= lerpf(0.5, 1.3, turn)
	if weapon.riflegrenade_loaded or _reload_grenade:
		aim = weapon.raise_riflegrenade_s + weapon.aim_riflegrenade_s
	# Recognition overlaps raising/aiming instead of adding a full second delay.
	aquire_target_task.done = false
	aquire_target_task.start_time_s = maxf(reaction, raise_remaining_s + aim)
	weapon_state = WeaponState.PREPARING


func start_reload(grenade: bool = false) -> void:
	if not reload_task.done and reload_task.remaining_time_s > 0.0:
		return
	_reload_grenade = grenade
	_reload_rounds = weapon.mag_capacity
	var duration: float = weapon.reload_s
	if grenade:
		duration = weapon.reload_riflegrenade_s
		_reload_rounds = 1
	reload_task.done = false
	reload_task.start_time_s = duration
	weapon_state = WeaponState.RELOADING


func finish_burst() -> void:
	burst_active = false
	cycle_remaining_s = weapon.cycle_s
	reaim_remaining_s = weapon.reaim_s * _combat_rng.randf_range(1.0 - weapon.aim_variation, 1.0 + weapon.aim_variation)
	if weapon.fire_mode == WeaponSpec.FireMode.BURST:
		reaim_remaining_s = maxf(reaim_remaining_s, weapon.burst_pause_s)
	elif cycle_remaining_s <= 0.0:
		reaim_remaining_s = maxf(reaim_remaining_s, 60.0 / maxf(weapon.rpm, 1.0))
	weapon_state = WeaponState.REAIMING
	if cycle_remaining_s > 0.0:
		weapon_state = WeaponState.CYCLING
	if rounds_in_mag <= 0:
		cycle_remaining_s = 0.0


func advance_handling(delta: float, speed: float) -> bool:
	if barrel_change_assisting or barrel_change_worked or weapon.automatic_fire.swap_barrel >= 0:
		weapon_state = WeaponState.CHANGING_BARREL
		return false
	if burst_active:
		weapon_state = WeaponState.FIRING
		return false
	if behavior != Behavior.ENGAGING:
		return false
	var work: float = maxf(delta * speed, 0.0)
	if not reload_task.done:
		var reload_work: float = minf(maxf(reload_task.remaining_time_s, 0.0), work)
		reload_task.remaining_time_s -= reload_work
		work -= reload_work
		weapon_state = WeaponState.RELOADING
		if reload_task.remaining_time_s > 0.0:
			return false
		reload_task.done = true
		if _reload_rounds > 0:
			rounds_in_mag = mini(_reload_rounds, weapon.ammunition)
			weapon.riflegrenade_loaded = _reload_grenade
			_reload_rounds = 0
		# Observation is retained during reload; only a brief final correction remains.
		if has_engagement:
			var correction: float = 0.15 + reaction_tendency * 0.25
			if weapon.riflegrenade_loaded:
				correction = weapon.aim_riflegrenade_s
			aquire_target_task.remaining_time_s = minf(aquire_target_task.remaining_time_s, correction)
	var cycle_work: float = minf(cycle_remaining_s, work)
	cycle_remaining_s -= cycle_work
	work -= cycle_work
	if cycle_remaining_s > 0.0:
		weapon_state = WeaponState.CYCLING
		return false
	var reaim_work: float = minf(reaim_remaining_s, work)
	reaim_remaining_s -= reaim_work
	work -= reaim_work
	if reaim_remaining_s > 0.0:
		weapon_state = WeaponState.REAIMING
		return false
	if not aquire_target_task.done:
		aquire_target_task.remaining_time_s = maxf(aquire_target_task.remaining_time_s - work, 0.0)
		aquire_target_task.done = aquire_target_task.remaining_time_s <= 0.0
		if not aquire_target_task.done:
			weapon_state = WeaponState.PREPARING
			return false
	if not weapon_raised:
		weapon_state = WeaponState.LOWERED
		return false
	weapon_state = WeaponState.READY
	return true


func automatic_burst_size(rapid: bool) -> int:
	var nominal: int = weapon.burst_rounds
	if rapid:
		nominal = weapon.rapid_burst_rounds
	if weapon.automatic_fire.heat() >= weapon.heat_soft_limit:
		nominal = maxi(2, int(float(nominal) * 0.65))
	return clampi(nominal + _combat_rng.randi_range(-1, 1), 1, rounds_in_mag)


func finish_automatic_burst(rapid: bool, suppressed: bool) -> void:
	weapon.automatic_fire.finish_burst(weapon, rapid, suppressed, _combat_rng.randf_range(0.85, 1.15))


func combat_status() -> String:
	match behavior:
		Behavior.TAKING_COVER:
			return "Taking cover"
		Behavior.COWERING:
			return "Cowering"
		Behavior.RECOVERING:
			return "Recovering"
	if barrel_change_assisting or barrel_change_worked or weapon.automatic_fire.swap_barrel >= 0:
		return "Changing barrel"
	match weapon_state:
		WeaponState.FIRING:
			return "Firing"
		WeaponState.CYCLING:
			return "Cycling action"
		WeaponState.REAIMING:
			return "Restoring aim"
		WeaponState.OBSERVING:
			return "Observing between bursts"
		WeaponState.COOLING:
			return "Cooling barrel"
	return "Ready"


# close combat
var is_attacker: bool = false
var is_defender: bool = false

var base_attack: float = 1.0
var base_defense: float = 1.0

var weapon_attack: float = 0.0
var weapon_defense: float = 0.0
var weapon_shock: float = 0.0
var attack_interval: float = 0.5

var morale_attack_mult: float = 1.0
var morale_defense_mult: float = 1.0

var location_attack_mult: float = 1.0
var location_defense_mult: float = 1.0

var side_attack_bonus: float = 0.0
var side_defense_bonus: float = 0.0

var cooldown_remaining: float = 0.0
var stunned_time: float = 0.0

func _init(_id: int, _name: String, _rank_grade: RankGrades.Grade, _role: RankGrades.Role, _weapon: WeaponSpec, _unit: Unit, _team: Globals.Team) -> void:
	id = _id
	name = _name
	rank_grade = _rank_grade
	role = _role
	weapon = _weapon
	rounds_in_mag = weapon.mag_capacity
	reload_task.done = true
	aquire_target_task.done = true
	setup_weapon_task.done = weapon.setup_s <= 0.0
	setup_weapon_task.start_time_s = weapon.setup_s
	assist_task.done = true
	unit = _unit
	team = _team
	_combat_rng.seed = absi(hash(str(_team) + ":" + str(_id) + ":" + _name))
	reaction_tendency = _combat_rng.randf()
	


func is_weapon_setup_done(delta: float) -> bool:
	if setup_weapon_task.done:
		return true
	setup_weapon_task.remaining_time_s = maxf(0.0, setup_weapon_task.remaining_time_s - delta)
	setup_weapon_task.done = setup_weapon_task.remaining_time_s <= 0.0
	return setup_weapon_task.done


func is_weapon_reload_done(delta: float) -> bool:
	if reload_task.done:
		return true
	if reload_task.remaining_time_s <= 0:
		reload_task.done = true
		return true
	reload_task.remaining_time_s -= delta
	return false


func is_acquiring_target_done(delta: float) -> bool:
	if aquire_target_task.done:
		return true
	if aquire_target_task.remaining_time_s <= 0:
		aquire_target_task.done = true
		return true
	aquire_target_task.remaining_time_s -= delta
	return false


func create_save_data() -> SoldierLoadout:
	var data: SoldierLoadout = SoldierLoadout.new()

	#data.id = id
	data.nickname = name
	data.rank_grade = rank_grade
	data.role = role

	if weapon != null:
		data.weapon_resource_path = weapon.source_resource_path
		if data.weapon_resource_path.is_empty():
			data.weapon_resource_path = weapon.resource_path
		# Built-in or anonymous weapons have no standalone asset to reference.
		if data.weapon_resource_path.is_empty() or data.weapon_resource_path.contains("::") or not ResourceLoader.exists(data.weapon_resource_path):
			data.weapon = weapon.duplicate() as WeaponSpec
	else:
		data.weapon_resource_path = ""

	#data.is_alive = is_alive
	#data.rounds_in_mag = rounds_in_mag
	#data.jammed = jammed

	#data.base_attack = base_attack
	#data.base_defense = base_defense

	return data


#static func create_from_save_data(
	#data: SoldierSaveData,
	#_unit: Unit,
	#_team: Globals.Team
#) -> Soldier:
	#var loaded_resource: Resource = load(data.loadout_resource_path)
#
	#if data == null:
		#push_error("Could not load SoldierLoadout: %s" % data.loadout_resource_path)
		#return null
#
	##var loadout: SoldierLoadout = data as SoldierLoadout
##
	##if loadout == null:
		##push_error("Loaded resource is not SoldierLoadout: %s" % data.loadout_resource_path)
		##return null
#
	#var soldier: Soldier = Soldier.new(
		#data.soldier_id,
		#data.soldier_name, 
		#data.rank_grade, 
		#data.role, 
		#data.weapon, 
		#data.unit, 
		#data.team
	#)
#
	#soldier.name = data.soldier_name
#
	#soldier.is_alive = data.is_alive
	#soldier.rounds_in_mag = data.rounds_in_mag
	#soldier.jammed = data.jammed
#
	#soldier.experience = data.experience
	#soldier.fatigue = data.fatigue
	#soldier.wounded = data.wounded
#
	#soldier.base_attack = data.base_attack
	#soldier.base_defense = data.base_defense
#
	#soldier.reset_runtime_state()
#
	#return soldier
