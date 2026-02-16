# unit.gd
@tool
extends Node2D
class_name Unit


enum SquadType {
	Rifle,
	MG,
	ANTITANK,
	MORTAR,
	PLATOON_HEADQUARTERS,
	COMPANY_HEADQUARTERS,
}

enum Company {
	A,
	B,
	C,
	D,
	E,
	F,
}

@export var squad: int = 0
@export var platoon: int = 0
@export var company: Company = Company.A

enum MoraleState { NORMAL, CAUTIOUS, PINNED, PANIC, COMBAT_INEFFECTIVE }

const ENEMY_MEMORY_LIFETIME: float = 6.0
var enemy_memory: Dictionary[Unit, Dictionary] = {}
# key: Unit
# value: {
#   "last_seen_time": float,
#   "last_seen_hex": Vector2i,
# }

const PHYSICS_DT: float = 1.0 / 60.0

# === Exported ===
@export var snap_to_grid := true
@export var ground_map: HexagonTileMapLayer
@export var firepower: int = 4
@export var weapon_range: int = 6
@export var morale: int = 7
@export var has_support_weapon: bool = false
@export var morale_meter_max: int = 100
@export var base_death_chance: float = 0.1
@export var broken_death_multiplier: float = 2.0
@export var recovery_time_max: float = 5.0
@export var team: Globals.Team = Globals.Team.AXIS
@export var retreat_speed := 70.0
@export var fire_rate: float = 0.75
@export var machine_guns: int = 0
@export var members_alive := 10
@export var loadouts: Array[SoldierLoadout] = []
@export var command_squad: Unit = null

# optional defaults to speed setup (assign in the inspector)
@export var default_rifle: WeaponSpec
@export var default_smg: WeaponSpec
@export var default_mg: WeaponSpec

# convenience buttons (toggle to run in-editor)
@export var make_rifle_squad: bool = false : set = _make_rifle_squad
@export var make_platoon_headquarters_squad: bool = false : set = _make_platoon_headquarters_squad
@export var make_company_headquarters_squad: bool = false : set = _make_company_headquarters_squad
@export var make_light_mg_team: bool = false : set = _make_light_mg_team
@export var make_anti_tank_squad: bool = false : set = _make_anti_tank_squad
@export var make_light_mortar_squad: bool = false : set = _make_light_mortar_squad
@export var make_medium_mortar_squad: bool = false : set = _make_medium_mortar_squad


# === GOAP ===
var enemies_reported: Array[Unit]
var enemies_reported_from_formation: Array[Unit]
var has_reported_contact: bool = false
@export var formation_id: int = 0
var current_order: SquadOrder = SquadOrder.new()
var current_order_status: int = GoapTypes.SquadOrderStatus.IDLE

# === Runtime State ===
var morale_meter_current: int = 0
var path_hexes: Array[Vector2i] = []
var path_index: int = 0
var alive: bool = true
var surrendered: bool = false
var broken: bool = false
var recovery_timer_current: float = 0.0
var current_cover_bonus: int = 0
var current_hex: Vector2i
var current_cube: Vector3i
var goal_hex: Vector2i
var target_hex: Vector2i # where the movement will end e.g. end of path
var formation_squads: Array[Unit]
var selected: bool = false
var moving: bool = false
var target_position: Vector2
var retreat_target_hex: Vector2i = Vector2i()
var effective_range: int = 0

var highest_rank_grade: RankGrades.Grade = RankGrades.Grade.SOLDIER

var original_size := 10
var leader_alive := true


@export var squadType: SquadType = SquadType.Rifle

# === Signals ===
signal unit_entered_hex(new_hex: Vector2i)
signal unit_arrived_at_hex(new_hex: Vector2i)
signal unit_died(unit)
signal retreat_complete(retreat_hex: Vector2i)
signal cover_updated(value: float)
signal deselect_unit(unit)
signal started_moving
signal unit_surrendered
signal contacts_reported(unit: Unit, contact: Array[Unit])

# unit details signals
signal soldiers_changed
signal state_chaged(state: int)
signal new_target_hex(unit: Unit, hex: Vector2i)

signal draw_command_link_strength(from_hex: Vector2i, to_hex: Vector2i, strength: float)
signal draw_leader_presence_strength(from_hex: Vector2i, to_hex: Vector2i, strength: float)


# === Nodes ===
@onready var ui := $UnitUi
@onready var stress_system: StressController = $UnitStressController
@onready var movement:UnitMovement = $UnitMovement
@onready var leader_aura: LeaderAura = $LeaderAura
@onready var squad_fire: SquadFireController = $SquadFireController
@onready var weapon_audio: WeaponAudio = $WeaponAudio
@onready var action_controller: SquadActionController = $SquadActionController
@onready var command_connectivity: CommandConnectivity = $CommandConnectivity
@onready var enemy_visiblity_checker: EnemyVisibilityChecker = $EnemyVisibilityChecker


# === DEBUG ===
@onready var action_label := $ActionLabel

# === Classes ===
@onready var tactical_state: SquadTacticalState = SquadTacticalState.new()




# === Ready ===
func _ready():
	if Engine.is_editor_hint():
		return
	
	action_controller.init(self, movement, squad_fire, stress_system, ui)
	retreat_complete.connect(_on_retreat_complete)
	cover_updated.connect(ui._on_cover_updated)
	
	current_cube = ground_map.map_to_cube(current_hex)
	
	unit_arrived_at_hex.connect(ui._on_unit_arrived_at_hex)
	unit_arrived_at_hex.connect(squad_fire._on_unit_arrived_at_hex)
	unit_arrived_at_hex.connect(_on_unit_arrived_at_hex)
	
	movement.unit = self

	movement.started_moving.connect(_on_started_moving)
	movement.stopped_moving.connect(_on_stopped_moving)
	action_controller.rout_failed.connect(_on_rout_failed)
	
	stress_system.state_changed.connect(_on_state_changed)
	stress_system.stress_changed.connect(_on_stress_changed)
	stress_system.stress_changed.connect(ui._on_stress_changed)
	
	
	
	stress_system.leadership_changed.connect(ui._on_leadership_changed)
	
	squad_fire.set_mg(machine_guns)
	
	#_resize_loadouts(members_count)
	_setup_runtime_soldiers()
	
	squad_fire.fire_shot.connect(_on_fire_shot)
	squad_fire.fire_riflegrenade.connect(_on_fire_riflegrenade)
	
	members_alive = loadouts.size()
	ui.set_memebers_alive(loadouts.size())
	
	_refresh_leader_aura()
	
	ui.set_loadout(squad_fire.soldiers)
	
	update_team_sprite(team, squadType)
	movement.new_target_hex.connect(_on_new_target_hex)


func order(cmd: Globals.UnitCmd, parameter):
	match cmd:
		Globals.UnitCmd.ATTACK:
			if squadType == Unit.SquadType.MORTAR:
				if parameter is Unit:
					var enemy_unit: Unit = parameter as Unit
					squad_fire.set_target_unit(enemy_unit)
				else:
					var map_hex: Vector2i = parameter as Vector2i
					fire_mortar(map_hex)
			else:
				var enemy_unit: Unit = parameter as Unit
				squad_fire.set_target_unit(enemy_unit)
				
		Globals.UnitCmd.MOVE:
			var to_hex: Vector2i = parameter as Vector2i
			if not current_hex == to_hex:
				var path: Array[Vector3i] = MovementSystem._compute_path(current_hex, to_hex, team)
				give_move_to_hex_order(to_hex, path, false)
			else:
				movement.move_to_hex(to_hex)


func _on_new_target_hex(end_of_path_hex: Vector2i):
	target_hex = end_of_path_hex
	new_target_hex.emit(self, target_hex)

func _now() -> float:
	return float(Engine.get_physics_frames()) * PHYSICS_DT


func fire_mortar(map_hex: Vector2i):
	squad_fire.fire_mortar(map_hex)


func is_good_order() -> bool:
	if surrendered or not alive or broken:
		return false
	else:
		return true 


func _on_fire_shot(weapon: WeaponSpec, mortar_target_hex: Vector2i):
	#if squad_fire.target_unit:
	if squad_fire.target_hex:
		var pos: Vector2 = LOSHelper.ground_layer.map_to_local(squad_fire.target_hex)
		match weapon.family: 
			WeaponSpec.Family.SMALL_ARM:
				ui.shoot(global_position, pos, weapon)
			WeaponSpec.Family.ROCKET_LAUNCHER:
				ui.shoot_rocket_launcher(global_position, pos, weapon)
	if not mortar_target_hex == Vector2i.ZERO:
		var pos: Vector2 = LOSHelper.ground_layer.map_to_local(mortar_target_hex)
		if weapon.family == WeaponSpec.Family.MORTAR:
				ui.set_ammunition_left(weapon.ammunition)
				ui.shoot_mortar(global_position, pos, weapon)
		#match weapon.family: 
			#WeaponSpec.Family.SMALL_ARM:
				#ui.shoot(global_position, squad_fire.target_unit.global_position, weapon)
			#WeaponSpec.Family.ROCKET_LAUNCHER:
				#ui.shoot_rocket_launcher(global_position, squad_fire.target_unit.global_position, weapon)
			#WeaponSpec.Family.MORTAR:
				#ui.shoot(global_position, squad_fire.target_unit.global_position, weapon)


func _on_fire_riflegrenade(weapon_spec: WeaponSpec):
	if squad_fire.target_unit:
		ui.shoot_riflegrenade(global_position, squad_fire.target_unit.global_position, weapon_spec)



func _on_new_target_unit(unit: Unit):
	squad_fire.set_target_unit(unit)


# Call this after casualties or when loadouts/runtime roster changes.
func _refresh_leader_aura() -> void:
	if leader_aura == null:
		return

	var grade: int = -1
	var found: bool = false

	# 1) Prefer runtime soldiers (alive only)
	#if squad_fire != null:
		#if squad_fire.soldiers.size() > 0:
	grade = _highest_grade_from_runtime()
	highest_rank_grade = grade as RankGrades.Grade
	#grade = _highest_grade_from_loadouts()
	if grade >= 0:
		found = true

	# 2) Fallback to editor loadouts
	# doesnt make sense. when there are no soldiers with rank in runtime, then they are dead
	#if not found:
		#grade = _highest_grade_from_loadouts()
		#if grade >= 0:
			#found = true

	if not found:
		return

	if RankGrades.GRADE_PARAMS.has(grade):
		var p: Dictionary = RankGrades.GRADE_PARAMS[grade]
		var lead: float = float(p["lead"])
		var rally: float = float(p["rally"])
		var radius: int = int(p["radius"])
		var coh: float = float(p["coh_mult"])

		leader_aura.aura_radius_hexes = radius
		leader_aura.leadership_bonus = lead
		leader_aura.rally_bonus = rally
		leader_aura.cohesion_mult = coh
	
	#var rank: RankGrades.Grade = _highest_grade_from_loadouts()
	ui.set_leadership_rank(grade)


func _highest_grade_from_runtime() -> int:
	var best: int = -1
	var i: int = 0
	while i < loadouts.size():
		var s: Soldier = squad_fire.soldiers[i]
		if s.is_alive:
			var g: int = _runtime_soldier_grade(s)
			if g > best:
				best = g
		i += 1
	return best

# Adjust this if your Soldier stores the grade under a different field.
# Assumes Soldier.rank (or .rank_grade) is aligned to RankGrades.Grade ordering.
func _runtime_soldier_grade(s: Soldier) -> int:
	var g: int = -1
	# If you use 'rank_grade' on Soldier, uncomment the next two lines and comment the 'rank' line.
	# g = int(s.rank_grade)
	# return g
	g = int(s.rank_grade)           # Soldier.Rank should map to RankGrades.Grade in order
	return g

func _highest_grade_from_loadouts() -> int:
	var best: int = -1
	var i: int = 0
	while i < loadouts.size():
		var L: SoldierLoadout = loadouts[i]
		var g: int = int(L.rank_grade)
		if g > best:
			best = g
		i += 1
	return best
	
func _setup_runtime_soldiers() -> void:
	effective_range = 0
	if squad_fire == null:
		return
	var list: Array[Soldier] = []
	var i: int = 0
	while i < loadouts.size():
		var L: SoldierLoadout = loadouts[i]
		var spec: WeaponSpec = L.weapon
		if spec == null:
			spec = default_rifle
		var s: Soldier = Soldier.new(
			i,
			L.nickname,
			L.rank_grade,
			_map_role(L.role),   # if your Soldier.Role differs
			spec
		)
		if s.role == RankGrades.Role.GUNNER:
			machine_guns += 1
		spec.ammunition = spec.ammunition_start
		if spec.family == WeaponSpec.Family.MORTAR:
			ui.set_ammunition_left(spec.ammunition)
		s.cadence_phase_s = randf_range(0.0, 3) # up to 0.2 s desync
		list.append(s)
		if spec.range_hexes > effective_range:
			effective_range = spec.range_hexes
		i += 1
	squad_fire.set_soldiers(list)

# map editor roles to runtime Soldier.Role if they differ
func _map_role(r: int) -> int:
	return r  # replace if your enums aren’t identical


func _resize_loadouts(n: int) -> void:
	# grow
	var i: int = loadouts.size()
	while i < n:
		var L: SoldierLoadout = SoldierLoadout.new()
		L.nickname = "Man %d" % int(i + 1)
		if default_rifle != null:
			L.weapon = default_rifle
		# sensible first two slots for MG team if MG exists
		if i == 0:
			if default_mg != null:
				L.role = RankGrades.Role.GUNNER
				L.nickname = "Gunner"
				L.weapon = default_mg
				L.is_key_role = true
		if i == 1:
			L.role = RankGrades.Role.LOADER
			L.nickname = "Loader"
			L.is_key_role = true
		loadouts.append(L)
		i += 1
	# shrinkf
	while loadouts.size() > n:
		loadouts.pop_back()

# template builders (run in editor by ticking the bool, it resets to false)
func _make_rifle_squad(v: bool) -> void:
	if v:
		squadType = SquadType.Rifle
		make_rifle_squad = false
		if team == 0:
			var group_size: int = 10
			var rifle: WeaponSpec
			var smg: WeaponSpec
			var mg: WeaponSpec
			rifle = preload("res://resources/weapons/kar98.tres")
			var riflegrenade: WeaponSpec = preload("res://resources/weapons/kar98_riflegrenade.tres")
			smg = preload("res://resources/weapons/mp40.tres")
			mg = preload("res://resources/weapons/mg34.tres")
			_resize_loadouts(group_size)
			var i: int = 0
			var leader: SoldierLoadout = loadouts[i]
			leader.role = RankGrades.Role.SQUAD_LEADER
			leader.nickname = "Squad Leader"
			leader.rank_grade = RankGrades.Grade.SQUAD_LEADER
			leader.weapon = smg
			i += 1
			var assistant_leader: SoldierLoadout = loadouts[i]
			assistant_leader.role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
			assistant_leader.nickname = "Ass. Squad Leader"
			assistant_leader.rank_grade = RankGrades.Grade.TEAM_LEADER
			assistant_leader.weapon = smg
			i += 1
			var gunner: SoldierLoadout = loadouts[i]
			gunner.role = RankGrades.Role.GUNNER
			gunner.nickname = "Gunner"
			gunner.rank_grade = RankGrades.Grade.SOLDIER
			gunner.weapon = mg
			i += 1
			var loader: SoldierLoadout = loadouts[i]
			loader.role = RankGrades.Role.LOADER
			loader.nickname = "Loader"
			loader.rank_grade = RankGrades.Grade.SOLDIER
			loader.weapon = rifle
			i += 1
			var riflegrenadier: SoldierLoadout = loadouts[i]
			riflegrenadier.role = RankGrades.Role.SOLDIER
			riflegrenadier.nickname = "Riflegrenadier"
			riflegrenadier.rank_grade = RankGrades.Grade.SOLDIER
			riflegrenadier.weapon = riflegrenade
			i += 1
			while i < group_size:
				var L: SoldierLoadout = loadouts[i]
				L.role = RankGrades.Role.SOLDIER
				L.nickname = "Rifle %d" % int(i + 1)
				L.rank_grade = RankGrades.Grade.SOLDIER
				L.weapon = rifle
				i += 1
		else:
			var group_size: int = 12
			var rifle: WeaponSpec
			var _smg: WeaponSpec
			var mg: WeaponSpec
			rifle = preload("res://resources/weapons/m1_garand.tres")
			var riflegrenade: WeaponSpec = preload("res://resources/weapons/springfield_1903_riflegrenade.tres")
			_smg = preload("res://resources/weapons/m3_grease_gun.tres")
			mg = preload("res://resources/weapons/m1918a1_bar.tres")
			_resize_loadouts(group_size)
			var i: int = 0
			var leader: SoldierLoadout = loadouts[i]
			leader.role = RankGrades.Role.SQUAD_LEADER
			leader.nickname = "Squad Leader"
			leader.rank_grade = RankGrades.Grade.SQUAD_LEADER
			leader.weapon = rifle
			i += 1
			var assistant_leader: SoldierLoadout = loadouts[i]
			assistant_leader.role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
			assistant_leader.nickname = "Ass. Squad Leader"
			assistant_leader.rank_grade = RankGrades.Grade.TEAM_LEADER
			assistant_leader.weapon = rifle
			i += 1
			var gunner: SoldierLoadout = loadouts[i]
			gunner.role = RankGrades.Role.GUNNER
			gunner.nickname = "Gunner"
			gunner.rank_grade = RankGrades.Grade.SOLDIER
			gunner.weapon = mg
			i += 1
			var loader: SoldierLoadout = loadouts[i]
			loader.role = RankGrades.Role.LOADER
			loader.nickname = "Loader"
			loader.rank_grade = RankGrades.Grade.SOLDIER
			loader.weapon = rifle
			i += 1
			var riflegrenadier: SoldierLoadout = loadouts[i]
			riflegrenadier.role = RankGrades.Role.SOLDIER
			riflegrenadier.nickname = "Riflegrenadier"
			riflegrenadier.rank_grade = RankGrades.Grade.SOLDIER
			riflegrenadier.weapon = riflegrenade
			i += 1
			while i < group_size:
				var L: SoldierLoadout = loadouts[i]
				L.role = RankGrades.Role.SOLDIER
				L.nickname = "Rifle %d" % int(i + 1)
				L.rank_grade = RankGrades.Grade.SOLDIER
				L.weapon = rifle
				i += 1
		notify_property_list_changed()


func _make_platoon_headquarters_squad(v: bool) -> void:
	if v:
		squadType = SquadType.PLATOON_HEADQUARTERS
		make_rifle_squad = false
		if team == 0:
			var group_size: int = 7
			var rifle: WeaponSpec = preload("res://resources/weapons/kar98.tres")
			var smg: WeaponSpec = preload("res://resources/weapons/mp40.tres")
			#var mg: WeaponSpec = preload("res://resources/weapons/mg34.tres")
			#var riflegrenade: WeaponSpec = preload("res://resources/weapons/kar98_riflegrenade.tres")
			_resize_loadouts(group_size)
			var i: int = 0
			var leader: SoldierLoadout = loadouts[i]
			leader.role = RankGrades.Role.SQUAD_LEADER
			leader.nickname = "Zugführer"
			leader.rank_grade = RankGrades.Grade.PLATOON_LEADER
			leader.weapon = smg
			i += 1
			var platoon_seargeant: SoldierLoadout = loadouts[i]
			platoon_seargeant.role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
			platoon_seargeant.nickname = "Zugtruppführer"
			platoon_seargeant.rank_grade = RankGrades.Grade.SQUAD_LEADER
			platoon_seargeant.weapon = smg
			i += 1
			var platoon_guide: SoldierLoadout = loadouts[i]
			platoon_guide.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
			platoon_guide.nickname = "Melder"
			platoon_guide.rank_grade = RankGrades.Grade.SQUAD_LEADER
			platoon_guide.weapon = rifle
			i += 1
			var platoon_guide1: SoldierLoadout = loadouts[i]
			platoon_guide1.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
			platoon_guide1.nickname = "Sanitäter"
			platoon_guide1.rank_grade = RankGrades.Grade.TEAM_LEADER
			platoon_guide1.weapon = rifle
			i += 1
			var platoon_guide2: SoldierLoadout = loadouts[i]
			platoon_guide2.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
			platoon_guide2.nickname = "Funker"
			platoon_guide2.rank_grade = RankGrades.Grade.SOLDIER
			platoon_guide2.weapon = rifle
			i += 1
			while i < group_size:
				var L: SoldierLoadout = loadouts[i]
				L.role = RankGrades.Role.SOLDIER
				L.nickname = "Messenger %d" % int(i + 1)
				L.rank_grade = RankGrades.Grade.SOLDIER
				L.weapon = rifle
				i += 1
		else:
			var group_size: int = 5
			var rifle: WeaponSpec = preload("res://resources/weapons/m1_garand.tres")
			var carbine: WeaponSpec = preload("res://resources/weapons/m1_carbine.tres")
			var riflegrenade: WeaponSpec = preload("res://resources/weapons/springfield_1903_riflegrenade.tres")
			#var smg: WeaponSpec = preload("res://resources/weapons/m3_grease_gun.tres")
			#var mg: WeaponSpec = preload("res://resources/weapons/m1918a1_bar.tres")
			_resize_loadouts(group_size)
			var i: int = 0
			var leader: SoldierLoadout = loadouts[i]
			leader.role = RankGrades.Role.SQUAD_LEADER
			leader.nickname = "Platoon Leader"
			leader.rank_grade = RankGrades.Grade.PLATOON_LEADER
			leader.weapon = carbine
			i += 1
			var platoon_seargeant: SoldierLoadout = loadouts[i]
			platoon_seargeant.role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
			platoon_seargeant.nickname = "Platoon Seargeant"
			platoon_seargeant.rank_grade = RankGrades.Grade.SQUAD_LEADER
			platoon_seargeant.weapon = rifle
			i += 1
			var platoon_guide: SoldierLoadout = loadouts[i]
			platoon_guide.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
			platoon_guide.nickname = "Platoon Guide"
			platoon_guide.rank_grade = RankGrades.Grade.SQUAD_LEADER
			platoon_guide.weapon = riflegrenade
			i += 1
			while i < group_size:
				var L: SoldierLoadout = loadouts[i]
				L.role = RankGrades.Role.SOLDIER
				L.nickname = "Messenger %d" % int(i + 1)
				L.rank_grade = RankGrades.Grade.SOLDIER
				L.weapon = rifle
				i += 1
		notify_property_list_changed()


func _make_company_headquarters_squad(v: bool) -> void:
	if v:
		squadType = SquadType.COMPANY_HEADQUARTERS
		make_rifle_squad = false
		if team == 0:
			var group_size: int = 7
			var rifle: WeaponSpec = preload("res://resources/weapons/kar98.tres")
			var smg: WeaponSpec = preload("res://resources/weapons/mp40.tres")
			#var mg: WeaponSpec = preload("res://resources/weapons/mg34.tres")
			#var riflegrenade: WeaponSpec = preload("res://resources/weapons/kar98_riflegrenade.tres")
			_resize_loadouts(group_size)
			var i: int = 0
			var leader: SoldierLoadout = loadouts[i]
			leader.role = RankGrades.Role.SQUAD_LEADER
			leader.nickname = "Kompaniechef"
			leader.rank_grade = RankGrades.Grade.COMPANY_LEADER
			leader.weapon = smg
			i += 1
			var platoon_seargeant: SoldierLoadout = loadouts[i]
			platoon_seargeant.role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
			platoon_seargeant.nickname = "Zugführer"
			platoon_seargeant.rank_grade = RankGrades.Grade.PLATOON_LEADER
			platoon_seargeant.weapon = smg
			i += 1
			var platoon_guide: SoldierLoadout = loadouts[i]
			platoon_guide.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
			platoon_guide.nickname = "Hauptfeldwebel"
			platoon_guide.rank_grade = RankGrades.Grade.SQUAD_LEADER
			platoon_guide.weapon = smg
			i += 1
			var platoon_guide2: SoldierLoadout = loadouts[i]
			platoon_guide2.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
			platoon_guide2.nickname = "Melderführer"
			platoon_guide2.rank_grade = RankGrades.Grade.SQUAD_LEADER
			platoon_guide2.weapon = smg
			i += 1
			var platoon_guide3: SoldierLoadout = loadouts[i]
			platoon_guide3.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
			platoon_guide3.nickname = "Funker"
			platoon_guide3.rank_grade = RankGrades.Grade.TEAM_LEADER
			platoon_guide3.weapon = rifle
			i += 1
			while i < group_size:
				var L: SoldierLoadout = loadouts[i]
				L.role = RankGrades.Role.SOLDIER
				L.nickname = "Messenger %d" % int(i + 1)
				L.rank_grade = RankGrades.Grade.SOLDIER
				L.weapon = rifle
				i += 1
		else:
			var group_size: int = 8
			#var rifle: WeaponSpec = preload("res://resources/weapons/m1_garand.tres")
			var carbine: WeaponSpec = preload("res://resources/weapons/m1_carbine.tres")
			var riflegrenade: WeaponSpec = preload("res://resources/weapons/springfield_1903_riflegrenade.tres")
			#var smg: WeaponSpec = preload("res://resources/weapons/m3_grease_gun.tres")
			#var mg: WeaponSpec = preload("res://resources/weapons/m1918a1_bar.tres")
			_resize_loadouts(group_size)
			var i: int = 0
			var leader: SoldierLoadout = loadouts[i]
			leader.role = RankGrades.Role.SQUAD_LEADER
			leader.nickname = "Company Commander"
			leader.rank_grade = RankGrades.Grade.COMPANY_LEADER
			leader.weapon = carbine
			i += 1
			var company_executive_officer: SoldierLoadout = loadouts[i]
			company_executive_officer.role = RankGrades.Role.ASSISTANT_SQUAD_LEADER
			company_executive_officer.nickname = "Executive Officer"
			company_executive_officer.rank_grade = RankGrades.Grade.PLATOON_LEADER
			company_executive_officer.weapon = carbine
			i += 1
			var company_first_sergeant: SoldierLoadout = loadouts[i]
			company_first_sergeant.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
			company_first_sergeant.nickname = "First Sergeant"
			company_first_sergeant.rank_grade = RankGrades.Grade.SQUAD_LEADER
			company_first_sergeant.weapon = carbine
			i += 1
			var communications_sergeant: SoldierLoadout = loadouts[i]
			communications_sergeant.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
			communications_sergeant.nickname = "First Sergeant"
			communications_sergeant.rank_grade = RankGrades.Grade.SQUAD_LEADER
			communications_sergeant.weapon = riflegrenade
			i += 1
			var bugler: SoldierLoadout = loadouts[i]
			bugler.role = RankGrades.Role.ASSISTANT_TEAM_LEADER
			bugler.nickname = "Bugler"
			bugler.rank_grade = RankGrades.Grade.ASSISTANT_TEAM_LEADER
			bugler.weapon = riflegrenade
			i += 1
			while i < group_size:
				var L: SoldierLoadout = loadouts[i]
				L.role = RankGrades.Role.SOLDIER
				L.nickname = "Messenger %d" % int(i + 1)
				L.rank_grade = RankGrades.Grade.SOLDIER
				L.weapon = carbine
				i += 1
		notify_property_list_changed()


func _make_light_mg_team(v: bool) -> void:
	if v:
		squadType = SquadType.MG
		make_light_mg_team = false
		if team == 0:
			var group_size: int = 7
			var rifle: WeaponSpec
			var smg: WeaponSpec
			var mg: WeaponSpec
			rifle = preload("res://resources/weapons/kar98.tres")
			smg = preload("res://resources/weapons/mp40.tres")
			mg = preload("res://resources/weapons/mg34_heavy.tres")
			_resize_loadouts(group_size)
			var i: int = 0
			var leader: SoldierLoadout = loadouts[i]
			leader.role = RankGrades.Role.SQUAD_LEADER
			leader.nickname = "Squad Leader"
			leader.rank_grade = RankGrades.Grade.SQUAD_LEADER
			leader.weapon = smg
			i += 1
			var gunner: SoldierLoadout = loadouts[i]
			gunner.role = RankGrades.Role.GUNNER
			gunner.nickname = "Gunner"
			gunner.rank_grade = RankGrades.Grade.SOLDIER
			gunner.weapon = mg
			i += 1
			var loader: SoldierLoadout = loadouts[i]
			loader.role = RankGrades.Role.LOADER
			loader.nickname = "Loader"
			loader.rank_grade = RankGrades.Grade.SOLDIER
			loader.weapon = rifle
			i += 1
			while i < group_size - 1:
				var assistant: SoldierLoadout = loadouts[i]
				assistant.role = RankGrades.Role.ASSISTANT
				assistant.nickname = "Ass. %d" % int(i + 1)
				assistant.rank_grade = RankGrades.Grade.SOLDIER
				assistant.weapon = rifle
				i += 1
			var L: SoldierLoadout = loadouts[i]
			L.role = RankGrades.Role.SOLDIER
			L.nickname = "Rifle %d" % int(i + 1)
			L.rank_grade = RankGrades.Grade.SOLDIER
			L.weapon = rifle
			i += 1
		else:
			var group_size: int = 5
			var rifle: WeaponSpec
			var mg: WeaponSpec
			rifle = preload("res://resources/weapons/m1_carbine.tres")
			mg = preload("res://resources/weapons/m1919a4.tres")
			_resize_loadouts(group_size)
			var i: int = 0
			var leader: SoldierLoadout = loadouts[i]
			leader.role = RankGrades.Role.SQUAD_LEADER
			leader.nickname = "Squad Leader"
			leader.rank_grade = RankGrades.Grade.SQUAD_LEADER
			leader.weapon = rifle
			i += 1
			var gunner: SoldierLoadout = loadouts[i]
			gunner.role = RankGrades.Role.GUNNER
			gunner.nickname = "Gunner"
			gunner.rank_grade = RankGrades.Grade.SOLDIER
			gunner.weapon = mg
			i += 1
			var loader: SoldierLoadout = loadouts[i]
			loader.role = RankGrades.Role.LOADER
			loader.nickname = "Loader"
			loader.rank_grade = RankGrades.Grade.SOLDIER
			loader.weapon = rifle
			i += 1
			while i < group_size:
				var L: SoldierLoadout = loadouts[i]
				L.role = RankGrades.Role.ASSISTANT
				L.nickname = "Ass. %d" % int(i + 1)
				L.rank_grade = RankGrades.Grade.SOLDIER
				L.weapon = rifle
				i += 1
		notify_property_list_changed()


func _make_anti_tank_squad(v: bool) -> void:
	if v:
		squadType = SquadType.ANTITANK
		make_anti_tank_squad = false
		if team == 0:
			var group_size: int = 2
			var rifle: WeaponSpec = preload("res://resources/weapons/kar98.tres")
			#var smg: WeaponSpec = preload("res://resources/weapons/mp40.tres")
			var antitank_weapon: WeaponSpec = preload("res://resources/weapons/rpzb_54_panzerschreck.tres")
			_resize_loadouts(group_size)
			var i: int = 0
			var gunner: SoldierLoadout = loadouts[i]
			gunner.role = RankGrades.Role.GUNNER
			gunner.nickname = "Gunner"
			gunner.rank_grade = RankGrades.Grade.ASSISTANT_TEAM_LEADER
			gunner.weapon = antitank_weapon
			i += 1
			var loader: SoldierLoadout = loadouts[i]
			loader.role = RankGrades.Role.LOADER
			loader.nickname = "Loader"
			loader.rank_grade = RankGrades.Grade.SOLDIER
			loader.weapon = rifle
			i += 1
		else:
			var group_size: int = 2
			var rifle: WeaponSpec = preload("res://resources/weapons/m1_carbine.tres")
			#var smg: WeaponSpec = preload("res://resources/weapons/m3_grease_gun.tres")
			var antitank_weapon: WeaponSpec = preload("res://resources/weapons/m1a1_bazooka.tres")
			_resize_loadouts(group_size)
			var i: int = 0
			var gunner: SoldierLoadout = loadouts[i]
			gunner.role = RankGrades.Role.GUNNER
			gunner.nickname = "Gunner"
			gunner.rank_grade = RankGrades.Grade.ASSISTANT_TEAM_LEADER
			gunner.weapon = antitank_weapon
			i += 1
			var loader: SoldierLoadout = loadouts[i]
			loader.role = RankGrades.Role.LOADER
			loader.nickname = "Loader"
			loader.rank_grade = RankGrades.Grade.SOLDIER
			loader.weapon = rifle
			i += 1
		notify_property_list_changed()


func _make_light_mortar_squad(v: bool) -> void:
	if v:
		squadType = SquadType.MORTAR
		make_anti_tank_squad = false
		if team == 0:
			var group_size: int = 5
			var rifle: WeaponSpec = preload("res://resources/weapons/kar98.tres")
			#var smg: WeaponSpec = preload("res://resources/weapons/mp40.tres")
			var mortar: WeaponSpec = preload("res://resources/weapons/granatwerfer_36.tres")
			_resize_loadouts(group_size)
			var i: int = 0
			var leader: SoldierLoadout = loadouts[i]
			leader.role = RankGrades.Role.TEAM_LEADER
			leader.nickname = "Squad Leader"
			leader.rank_grade = RankGrades.Grade.TEAM_LEADER
			leader.weapon = rifle
			i += 1
			var gunner: SoldierLoadout = loadouts[i]
			gunner.role = RankGrades.Role.GUNNER
			gunner.nickname = "Gunner"
			gunner.rank_grade = RankGrades.Grade.ASSISTANT_TEAM_LEADER
			gunner.weapon = mortar
			i += 1
			var loader: SoldierLoadout = loadouts[i]
			loader.role = RankGrades.Role.LOADER
			loader.nickname = "Loader"
			loader.rank_grade = RankGrades.Grade.SOLDIER
			loader.weapon = rifle
			i += 1
			while i < group_size:
				var L: SoldierLoadout = loadouts[i]
				L.role = RankGrades.Role.ASSISTANT
				L.nickname = "Ass. %d" % int(i + 1)
				L.rank_grade = RankGrades.Grade.SOLDIER
				L.weapon = rifle
				i += 1
		else:
			var group_size: int = 3
			var rifle: WeaponSpec = preload("res://resources/weapons/m1_carbine.tres")
			#var smg: WeaponSpec = preload("res://resources/weapons/m3_grease_gun.tres")
			var mortar: WeaponSpec = preload("res://resources/weapons/m2_60mm_mortar.tres")
			_resize_loadouts(group_size)
			var i: int = 0
			var leader: SoldierLoadout = loadouts[i]
			leader.role = RankGrades.Role.TEAM_LEADER
			leader.nickname = "Squad Leader"
			leader.rank_grade = RankGrades.Grade.TEAM_LEADER
			leader.weapon = rifle
			i += 1
			var gunner: SoldierLoadout = loadouts[i]
			gunner.role = RankGrades.Role.GUNNER
			gunner.nickname = "Gunner"
			gunner.rank_grade = RankGrades.Grade.ASSISTANT_TEAM_LEADER
			gunner.weapon = mortar
			i += 1
			var loader: SoldierLoadout = loadouts[i]
			loader.role = RankGrades.Role.LOADER
			loader.nickname = "Loader"
			loader.rank_grade = RankGrades.Grade.SOLDIER
			loader.weapon = rifle
			i += 1
			while i < group_size:
				var L: SoldierLoadout = loadouts[i]
				L.role = RankGrades.Role.ASSISTANT
				L.nickname = "Ass. %d" % int(i + 1)
				L.rank_grade = RankGrades.Grade.SOLDIER
				L.weapon = rifle
				i += 1
		notify_property_list_changed()


func _make_medium_mortar_squad(v: bool) -> void:
	if v:
		squadType = SquadType.MORTAR
		make_anti_tank_squad = false
		if team == 0:
			var group_size: int = 8
			var rifle: WeaponSpec = preload("res://resources/weapons/kar98.tres")
			#var smg: WeaponSpec = preload("res://resources/weapons/mp40.tres")
			var mortar: WeaponSpec = preload("res://resources/weapons/granatwerfer_34.tres")
			_resize_loadouts(group_size)
			var i: int = 0
			var leader: SoldierLoadout = loadouts[i]
			leader.role = RankGrades.Role.SQUAD_LEADER
			leader.nickname = "Squad Leader"
			leader.rank_grade = RankGrades.Grade.SQUAD_LEADER
			leader.weapon = rifle
			i += 1
			var gunner: SoldierLoadout = loadouts[i]
			gunner.role = RankGrades.Role.GUNNER
			gunner.nickname = "Gunner"
			gunner.rank_grade = RankGrades.Grade.ASSISTANT_TEAM_LEADER
			gunner.weapon = mortar
			i += 1
			var loader: SoldierLoadout = loadouts[i]
			loader.role = RankGrades.Role.LOADER
			loader.nickname = "Loader"
			loader.rank_grade = RankGrades.Grade.SOLDIER
			loader.weapon = rifle
			i += 1
			while i < group_size:
				var L: SoldierLoadout = loadouts[i]
				L.role = RankGrades.Role.ASSISTANT
				L.nickname = "Ass. %d" % int(i + 1)
				L.rank_grade = RankGrades.Grade.SOLDIER
				L.weapon = rifle
				i += 1
		else:
			var group_size: int = 9
			var rifle: WeaponSpec = preload("res://resources/weapons/m1_carbine.tres")
			#var smg: WeaponSpec = preload("res://resources/weapons/m3_grease_gun.tres")
			var mortar: WeaponSpec = preload("res://resources/weapons/m1_81mm_mortar.tres")
			_resize_loadouts(group_size)
			var i: int = 0
			var leader: SoldierLoadout = loadouts[i]
			leader.role = RankGrades.Role.SQUAD_LEADER
			leader.nickname = "Squad Leader"
			leader.rank_grade = RankGrades.Grade.SQUAD_LEADER
			leader.weapon = rifle
			i += 1
			var gunner: SoldierLoadout = loadouts[i]
			gunner.role = RankGrades.Role.GUNNER
			gunner.nickname = "Gunner"
			gunner.rank_grade = RankGrades.Grade.ASSISTANT_TEAM_LEADER
			gunner.weapon = mortar
			i += 1
			var loader: SoldierLoadout = loadouts[i]
			loader.role = RankGrades.Role.LOADER
			loader.nickname = "Loader"
			loader.rank_grade = RankGrades.Grade.SOLDIER
			loader.weapon = rifle
			i += 1
			while i < group_size:
				var L: SoldierLoadout = loadouts[i]
				L.role = RankGrades.Role.ASSISTANT
				L.nickname = "Ass. %d" % int(i + 1)
				L.rank_grade = RankGrades.Grade.SOLDIER
				L.weapon = rifle
				i += 1
		notify_property_list_changed()


func _on_started_moving():
	moving = true
	ui.started_moving(broken, surrendered)
	started_moving.emit()
	squad_fire.set_target_unit(null)
	action_controller.on_started_moving()


func _on_stopped_moving():
	moving = false
	ui.stopped_moving(broken, surrendered)
	action_controller.on_stopped_moving()
	


func _on_unit_arrived_at_hex(new_hex: Vector2i):
	action_controller.on_reached_hex(new_hex)


func _on_rout_failed():
	surrender()
	#die()


func _on_morale_breaks():
	#if selected:
		#deselect_unit.emit(self)
		#deselect()
	broken = true


func _on_morale_recovered():
	broken = false
	_on_new_order_received()


# === Process Loop ===

func _process(_delta):
	
	if Engine.is_editor_hint() and snap_to_grid:
		if ground_map == null:
			return
		snap_to_hex()
		var map_coords = ground_map.local_to_map(position)
		position = ground_map.map_to_local(map_coords)
		current_hex = map_coords
		if not Engine.is_editor_hint():
			current_cube = ground_map.map_to_cube(map_coords)
		set_team(team)
		return
	
	
	_check_contacts()
	if not alive:
		return




func _check_contacts() -> void:
	cleanup_enemy_memory()
	if not is_good_order():
		return
	var raw: Array = Globals.unit_visible_enemies.get(self, [])
	
	var enemies: Array[Unit] = []

	for unit in raw:
		if is_instance_valid(unit):
			enemies.append(unit)

	if enemies.is_empty():
		has_reported_contact = false
	else:
		has_reported_contact = true
	
	var _new_enemy: bool = false
	for enemy_squad in enemies:
		if not enemy_squad in enemies_reported and not enemy_memory.has(enemy_squad):
			_new_enemy = true
		remember_enemy(enemy_squad)
	
	#if not enemies_reported == enemies:
	#if new_enemy and not team == Globals.team_player:
		#movement.stop()
	enemies_reported = enemies
	
	# Option: halt movement temporarily until formation reacts
	#if action_controller.action_state == SquadActionController.SquadActionState.ADVANCING:
		#action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION

	contacts_reported.emit(self, enemies)

func remember_enemy(enemy: Unit) -> void:
	var info: Dictionary = {}
	info["last_seen_time"] = _now()
	info["last_seen_hex"] = enemy.current_hex
	enemy_memory[enemy] = info


func cleanup_enemy_memory() -> void:
	var new_memory: Dictionary[Unit, Dictionary] = {}
	var now: float = _now()
	var keys: Array = enemy_memory.keys()
	var count: int = keys.size()
	var i: int = 0

	while i < count:
		if is_instance_valid(keys[i]):
			var unit: Unit = keys[i]
			var info: Dictionary = enemy_memory.get(unit, null)
			if info != null:
				var age: float = now - float(info["last_seen_time"])
				if age <= ENEMY_MEMORY_LIFETIME:
					new_memory[unit] = info
		i += 1

func _get_enemy_hex_for_cover(enemy: Unit) -> Vector2i:
	# Use live hex if available in LOS map
	if LOSHelper.los_lookup.has(enemy.current_hex):
		return enemy.current_hex
	
	# Fallback: last known hex from memory, if present
	if enemy_memory.has(enemy):
		var info: Dictionary = enemy_memory[enemy]
		var mem_hex: Vector2i = info["last_seen_hex"]
		if LOSHelper.los_lookup.has(mem_hex):
			return mem_hex
	
	# If still nothing, return an invalid hex marker you handle elsewhere
	return Vector2i(-9999, -9999)
	
# === Utility ===
func snap_to_hex():
	if ground_map:
		var map_coords = ground_map.local_to_map(position)
		position = ground_map.map_to_local(map_coords)


func select():
	ui.select()
	selected = true


func deselect():
	ui.deselect()
	selected = false


func set_cover(cover_value: int) -> void:
	ui.set_cover(cover_value)


func get_visible_enemies() -> Array:
	return Globals.unit_visible_enemies.get(self, [])


func set_team(new_team: Globals.Team):
	team = new_team
	update_team_sprite(team, squadType)


func update_team_sprite(_team: Globals.Team, _squadType: SquadType):
	ui.update_team_sprite(_team, _squadType)



#func receive_fire(incoming_firepower: int, terrain_defense_bonus: float, unit_visible_enemies: Dictionary):
func receive_fire(terrain_defense_bonus: float):
	cover_updated.emit(int(terrain_defense_bonus))
	#if moving and not broken and not surrendered:
		#movement.recalc_path()

func _on_incoming_fire_effect(casualties:int, df:float, ds:float, _source:Node) -> void:
	if Debug.no_damage:
		return
	if casualties > 0:
		_apply_casualties(casualties)
		ui.show_casualty()
		soldiers_changed.emit()
	stress_system.apply_stress(df, ds)
	ui.set_loadout(squad_fire.soldiers)
	_refresh_leader_aura()
	leader_aura._affected.erase(self)
	leader_aura._apply_to(self)
	#emit_signal("stress_applied", df, ds, source)


#func _apply_casualties(n:int) -> void:
	#var casualty_indexes: Array[int] =  get_unique_random_ints(n, members_alive)
	#members_alive = max(0, members_alive - n)
	#var leader_down = false
	#if leader_alive and randf() < 1.0/float(max(1,members_alive+1)): # small chance hit was leader
		#leader_alive = false
		#leader_down = true
		##emit_signal("leader_killed")
		#stress_system.leadership_bonus = 0.0
	#stress_system.on_casualty_event(n, leader_down)
	##emit_signal("casualties_taken", original_size - members_alive)
	#ui.set_memebers_alive(members_alive)
	#var casualties: Array[Soldier]
	#for i in casualty_indexes:
		#var soldier: Soldier = squad_fire.soldiers[i]
		#casualties.append(soldier)
	#remove_indices(loadouts, casualty_indexes)
	#remove_indices(squad_fire.soldiers, casualty_indexes)
	#var casualty_roles: Array[RankGrades.Role]
	#for i in casualties:
		#casualty_roles.append(casualties[i].role)
	#
	#
	#if members_alive <= 0:
		#_set_combat_ineffective()


# --- casualties, role replacement, and support-weapon re-crewing ---
func _apply_casualties(n: int) -> void:
	var casualty_indexes: Array[int] = get_unique_random_ints(n, members_alive)
	var members_alive_before: int = members_alive
	members_alive = max(0, members_alive - n)
	if n == 0:
		pass

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
		if s_idx >= 0 and s_idx < squad_fire.soldiers.size():
			var soldier: Soldier = squad_fire.soldiers[s_idx]
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
	
	for soldier in casualties:
		weapon_audio.stop_mg_loop(soldier.weapon, position, soldier.id, self)
	
	# physically remove the fallen from our parallel arrays
	remove_indices(loadouts, casualty_indexes)
	remove_indices(squad_fire.soldiers, casualty_indexes)
	
	effective_range = 0
	for soldier in squad_fire.soldiers:
		if soldier.weapon.range_hexes > effective_range:
			effective_range = soldier.weapon.range_hexes

	# debug
	if n != casualty_indexes.size():
		pass

	# book-keeping and UI
	members_alive = squad_fire.soldiers.size()
	stress_system.on_casualty_event(n, leader_down)
	ui.set_memebers_alive(members_alive)

	if members_alive_before == members_alive:
		pass
	# if the whole lot’s gone, we’re done
	if members_alive <= 0:
		_set_combat_ineffective()
		return

	# 1) replace leader if needed: ASL first, else any SOLDIER
	if roles_lost.has(RankGrades.Role.SQUAD_LEADER) or leader_down:
		_promote_new_leader()
	
	# 2) re-crew any dropped guns (e.g., MG) — loader preferred as new gunner
	var g: int = 0
	while g < dropped_support.size():
		var wp: WeaponSpec = dropped_support[g]
		_assign_gunner_and_loader_for_weapon(wp)
		g += 1

	# 3) if we lost a loader but the gun’s still in the squad, top up loaders
	if roles_lost.has(RankGrades.Role.LOADER):
		_fill_missing_loaders_for_existing_guns()

	# optional: if you maintain any cached fire stats, rebuild them now
	# squad_fire.rebuild_cached_stats()
	# emit signals as needed
	# emit_signal("casualties_taken", original_size - members_alive)



# ---------- helpers (typed, no ternarys) ----------

func _promote_new_leader() -> void:
	var idx_asl: int = _index_of_role(RankGrades.Role.ASSISTANT_SQUAD_LEADER)
	var new_leader_idx: int = idx_asl
	if new_leader_idx == -1:
		new_leader_idx = _find_first_SOLDIER()
	if new_leader_idx != -1:
		var s: Soldier = squad_fire.soldiers[new_leader_idx]
		s.role = RankGrades.Role.SQUAD_LEADER
		leader_alive = true
		
		# if you track graded leadership, update bonus here instead of this placeholder:
		# stress_system.leadership_bonus = _compute_leadership_bonus_for(s)
	else:
		# no one left to lead; keep leader_alive false and bonus at 0
		pass

func _assign_gunner_and_loader_for_weapon(wp: WeaponSpec) -> void:
	if wp == null:
		return

	# pick gunner: prefer an existing loader, else any SOLDIER
	var gunner_idx: int = _index_of_role(RankGrades.Role.LOADER)
	if gunner_idx == -1:
		gunner_idx = _find_first_SOLDIER()
	if gunner_idx == -1:
		# no hands left to serve the gun
		return

	var gunner: Soldier = squad_fire.soldiers[gunner_idx]
	gunner.role = RankGrades.Role.GUNNER
	gunner.weapon = wp

	# ensure loader if weapon wants a crew
	if wp.crew_required > 1:
		var loader_idx: int = _find_first_SOLDIER_OR_ASSISTANT_excluding([gunner_idx])
		if loader_idx != -1:
			var loader: Soldier = squad_fire.soldiers[loader_idx]
			loader.role = RankGrades.Role.LOADER
			# loaders generally don’t carry the weapon object; the gun sits on the gunner
		else:
			# under-crewed; your fire calc should already scale with wp.undercrew_penalty_exp
			pass
	if wp.support_crew_optimal > 0:
		var support_idx: int = _find_first_SOLDIER_OR_ASSISTANT_excluding([gunner_idx])
		if support_idx != -1:
			var support: Soldier = squad_fire.soldiers[support_idx]
			support.role = RankGrades.Role.ASSISTANT
			# loaders generally don’t carry the weapon object; the gun sits on the gunner
		else:
			# under-crewed; your fire calc should already scale with wp.undercrew_penalty_exp
			pass

func _fill_missing_loaders_for_existing_guns() -> void:
	# for each gunner with a crew-served, ensure there is at least one loader in the squad
	var has_loader: bool = _has_role(RankGrades.Role.LOADER)
	if has_loader:
		return

	var i: int = 0
	while i < squad_fire.soldiers.size():
		var s: Soldier = squad_fire.soldiers[i]
		if s.role == RankGrades.Role.GUNNER and not s.weapon == null:
			if s.weapon.crew_required > 1:
				var idx: int = _find_first_SOLDIER_OR_ASSISTANT_excluding([i])
				if not idx == -1:
					var loader: Soldier = squad_fire.soldiers[idx]
					loader.role = RankGrades.Role.LOADER
				# if still none, we stay under-crewed
		i += 1

func _index_of_role(role: int) -> int:
	var i: int = 0
	while i < squad_fire.soldiers.size():
		var s: Soldier = squad_fire.soldiers[i]
		if s.role == role:
			return i
		i += 1
	return -1

func _has_role(role: int) -> bool:
	var i: int = 0
	while i < squad_fire.soldiers.size():
		var s: Soldier = squad_fire.soldiers[i]
		if s.role == role:
			return true
		i += 1
	return false

func _find_first_SOLDIER() -> int:
	var i: int = 0
	while i < squad_fire.soldiers.size():
		var s: Soldier = squad_fire.soldiers[i]
		if s.role == RankGrades.Role.SOLDIER:
			if not s.weapon.can_fire_riflegrenades:
				return i
		i += 1
	return -1


func _find_first_SOLDIER_OR_ASSISTANT_excluding(exclude: Array[int]) -> int:
	var i: int = 0
	while i < squad_fire.soldiers.size():
		if not exclude.has(i):
			var s: Soldier = squad_fire.soldiers[i]
			if s.role == RankGrades.Role.SOLDIER or s.role == RankGrades.Role.ASSISTANT:
				if not s.weapon.can_fire_riflegrenades:
					return i
		i += 1
	return -1


func remove_indices(target: Array, indices: Array[int]) -> void:
	# Sort descending so the higher indices go first
	indices.sort()
	indices.reverse()

	var i: int = 0
	while i < indices.size():
		var idx: int = indices[i]
		if idx >= 0 and idx < target.size():
			target.remove_at(idx)
		i += 1

func get_unique_random_ints(n: int, _max: int) -> Array[int]:
	var all_nums: Array[int] = []
	var i: int = 0
	while i < _max:
		all_nums.append(i)
		i += 1
	all_nums.shuffle()
	return all_nums.slice(0, n)

func _set_combat_ineffective():
	stress_system.state = STATES.MoraleState.COMBAT_INEFFECTIVE
	ui.state_changed(stress_system.state)
	die()
	#emit_signal("state_changed",
		#StressController.MoraleState.PANIC, stress_system.state)

func get_state_name(state: MoraleState) -> String:
	match state:
		MoraleState.NORMAL: return "Ok"
		MoraleState.CAUTIOUS: return "Cautious"
		MoraleState.PINNED: return "Pinned"
		MoraleState.PANIC: return "Panic"
		MoraleState.COMBAT_INEFFECTIVE: return "Combat Ineffective"
		_: return "Unknown"
		


func get_squad_type_name(type: SquadType) -> String:
	match type:
		SquadType.Rifle: return "Rifle Squad"
		SquadType.MG: return "Machine Gun Squad"
		SquadType.ANTITANK: return "Antitank Team"
		SquadType.MORTAR: return "Mortar Squad"
		SquadType.PLATOON_HEADQUARTERS: return "Platoon Headquarters"
		SquadType.COMPANY_HEADQUARTERS: return "Company Headquarters"
		_: return "Unknown"
		

func surrender():
	#return
	movement.move_to_hex(current_hex)
	surrendered = true
	#alive = false
	broken = false
	emit_signal("unit_surrendered", self)
	ui.surrender()


func die():
	alive = false
	unit_died.emit(self)
	await ui.die()
	queue_free()


func _on_retreat_complete(retreat_hex) -> void:
	movement.moving = false
	current_hex = retreat_hex
	current_cube = LOSHelper.ground_layer.map_to_cube(retreat_hex)
	unit_entered_hex.emit(self, current_hex)
	#emit_signal("moved_to_hex", self, current_hex)
	action_controller.on_retreat_complete(retreat_hex)


func _on_stress_changed(stress: float):
	ui.update_bar(int(stress), 100)



# Single, merged handler — keep ONLY this one in unit.gd
func _on_state_changed(prev:int, next:int) -> void:
	
	if next == MoraleState.PANIC:
		ui._on_morale_breaks()
		_on_morale_breaks()
	if prev == MoraleState.PANIC && next != MoraleState.PANIC:
		ui._on_morale_recovered()
		_on_morale_recovered()
	# 1) Movement & internal combat state
	movement.state_changed(next)
	
	## 2) ROF/accuracy from state table
	var m = STATES.STATE_MOD[next]
	## guard against silly zeros
	var rof_mult: float = max(float(m.rof), 0.05)
	squad_fire.seconds_per_volley = squad_fire.base_seconds_per_volley / rof_mult
	squad_fire.accuracy_multiplier = m.acc

	## 3) Visuals/pose
	ui.state_changed(next)
	
	state_chaged.emit(next)
	action_controller.on_morale_state_changed(prev, next)


func _on_unit_ui_debug_kill_soldier() -> void:
	_apply_casualties(1)
	#stress_system.apply_stress(df, ds)
	ui.set_loadout(squad_fire.soldiers)
	_refresh_leader_aura()
	leader_aura._affected.erase(self)
	leader_aura._apply_to(self)



# Thin forwarding API for higher-level AI / UI:

func give_defend_area_order(_target_hex: Vector2i, path: Array[Vector3i]) -> void:
	action_controller.give_defend_area_order(_target_hex, path)
	#action_label.text = "defend"


func give_move_to_hex_order(_target_hex: Vector2i, path: Array[Vector3i], take_and_hold: bool) -> void:
	action_controller.give_move_to_hex_order(_target_hex, path, take_and_hold)
	#action_label.text = "move"


func give_attack_hex_order(_target_hex: Vector2i, covered_path: Array[Vector3i], exposed_segment: Array[Vector3i]) -> void:
	action_controller.give_attack_hex_order(_target_hex, covered_path, exposed_segment)
	#action_label.text = "attack"


func give_withdraw_to_hex_order(_target_hex: Vector2i, path: Array[Vector3i]) -> void:
	action_controller.give_withdraw_to_hex_order(_target_hex, path)
	#action_label.text = "withdraw"


func give_hold_order() -> void:
	action_controller.give_hold_order()
	#action_label.text = "hold"


func clear_orders() -> void:
	action_controller.clear_orders()
	#action_label.text = "clear order"


# === GOAP ===


func set_order_resource(_order: SquadOrder) -> void:
	current_order = _order
	current_order_status = GoapTypes.SquadOrderStatus.IN_PROGRESS
	_on_new_order_received()

func _on_new_order_received() -> void:
	match current_order.order_type:
		GoapTypes.SquadOrderType.DEFEND_POSITION:
			_start_defend_position()
		GoapTypes.SquadOrderType.DEFEND_OBJECTIVE:
			_start_defend_objective()
		GoapTypes.SquadOrderType.MOVE_TO:
			_start_move_to()
		GoapTypes.SquadOrderType.BASE_OF_FIRE:
			_start_base_of_fire()
		GoapTypes.SquadOrderType.ASSAULT_ROUTE:
			_start_assault_route()
		GoapTypes.SquadOrderType.SCREEN_AXIS:
			pass
			#_start_screen_axis()
		GoapTypes.SquadOrderType.REST:
			#_start_rest()
			pass
		GoapTypes.SquadOrderType.REORGANIZE_MERGE:
			#_start_reorganize()
			pass
		_:
			current_order_status = GoapTypes.SquadOrderStatus.IDLE
			action_controller.action_state = SquadActionController.SquadActionState.NO_ORDER


func _start_defend_line() -> void:
	# Use current_order.target_hexes or line/sector mapping to hexes
	var defend_hex: Vector2i = Vector2i.ZERO#_pick_defend_hex_for_this_squad()
	movement.set_path_to_hex(defend_hex)
	action_controller.action_state = SquadActionController.SquadActionState.MOVING_TO_POSITION
	
func _start_defend_position():
	pass


func  _start_defend_objective():
	pass


func _start_move_to() -> void:
	# current_order.target_hexes should hold route
	if current_order.target_hexes.is_empty():
		# optional: derive a simple fallback from current position if formation gave no path
		#var fallback_route: Array[Vector2i] = _compute_simple_fallback_route()
		#movement.set_route(fallback_route)
		
		current_order.target_hexes.append(Globals.objective_hexes[team][0])
	if moving == false and current_order.target_hexes[0] == current_hex:
		return
	if not movement.path_hexes.is_empty():
		if not movement.path_hexes[-1] == current_order.target_hexes[0]:
			var path: Array[Vector3i] = MovementSystem._compute_path(current_hex, current_order.target_hexes[0], team)
			give_move_to_hex_order(current_order.target_hexes[0], path, false)
			action_controller.action_state = SquadActionController.SquadActionState.MOVING_TO_POSITION
	else:
		if not current_hex == current_order.target_hexes[0]:
			var path: Array[Vector3i] = MovementSystem._compute_path(current_hex, current_order.target_hexes[0], team)
			give_move_to_hex_order(current_order.target_hexes[0], path, false)
			action_controller.action_state = SquadActionController.SquadActionState.MOVING_TO_POSITION
	action_label.text = "move to" + str(current_order.target_hexes[0])

func _start_base_of_fire() -> void:
	#var visible_hexes_by_enemy: Array[Vector2i] = LOSHelper.los_lookup.get(enemies_reported[0].current_hex, [])
	var enemies: Array[Unit] = []
	
	if not enemy_memory.is_empty():
		enemies = enemy_memory.keys()
	
	if not enemies_reported.is_empty():
		for enemy in enemies_reported:
			if is_instance_valid(enemy):
				if not enemies.has(enemy):
					enemies.append(enemy)
	else:
		for enemy in enemies_reported_from_formation:
			if is_instance_valid(enemy):
				if not enemies.has(enemy):
						enemies.append(enemy)
	
	if enemies.is_empty():
		return
	
	var closest_distance_to_cover: int = 1000
	var closest_hex: Vector2i
	
	var closest_enemy: Unit
	var closest_distance_to_enemy: int = 1000
	for enemy in enemies:
		if is_instance_valid(enemy):
			var distance_to_enemy: int = LOSHelper.ground_layer.cube_distance(current_cube, enemy.current_cube)
			if distance_to_enemy <= closest_distance_to_enemy:
			
				closest_distance_to_enemy = distance_to_enemy
				
				var visible_hexes_by_enemy: Dictionary = LOSHelper.los_lookup.get(enemy.current_hex, [])
	
				for hex in visible_hexes_by_enemy.keys():
					var cube: Vector3i = LOSHelper.ground_layer.map_to_cube(hex)
					var distance_to_cover: int = LOSHelper.ground_layer.cube_distance(current_cube, cube)
					if visible_hexes_by_enemy[hex]["target_cover"] > 0: # visible_hexes_by_enemy[hex]["shooter_cover"]
						var hex_already_taken_by_squad_mate: bool = false
						for squad in formation_squads:
							if is_instance_valid(squad):
								if not squad == self:
									if squad.target_hex == hex:
										hex_already_taken_by_squad_mate = true
						if distance_to_cover < closest_distance_to_cover and distance_to_enemy <= effective_range and not hex_already_taken_by_squad_mate:
							closest_distance_to_cover = distance_to_cover
							closest_hex = LOSHelper.ground_layer.cube_to_map(cube)
							closest_enemy = enemy
	
	if not closest_enemy:
		return
	
	if not LOSHelper.los_lookup.has(closest_enemy.current_hex):
		return
	
	#var enemy_hex: Vector2i = _get_enemy_hex_for_cover(enemies[0])
	#if enemy_hex.x == -9999:
		#return
	#var visible_hexes_by_enemy: Dictionary = LOSHelper.los_lookup.get(enemy_hex, {})
	
	
	
	if not moving and current_hex == closest_hex:
		return
	if not movement.path_hexes.is_empty():
		if not movement.path_hexes[-1] == closest_hex:
			var path: Array[Vector3i] = MovementSystem._compute_path(current_hex, closest_hex, team)
			give_move_to_hex_order(closest_hex, path, false)
	else:
		if not current_hex == closest_hex:
			var path: Array[Vector3i] = MovementSystem._compute_path(current_hex, closest_hex, team)
			give_move_to_hex_order(closest_hex, path, false)
	action_label.text = "base of fire" + str(closest_hex)
	#return
	#if current_order.target_hexes.is_empty():
		#return
	#var firebase_hex: Vector2i
	#var visible_hexes_to_target = LOSHelper.los_lookup.get(current_order.target_hexes[0], [])
	#var closest_distance: int = 1000
	#for hex in visible_hexes_to_target:
		#var target_cube: Vector3i = LOSHelper.ground_layer.map_to_cube(hex)
		#var distance: int = LOSHelper.ground_layer.cube_distance(current_cube, target_cube)
		#if distance < closest_distance:
			#closest_distance = distance
			#firebase_hex = hex
	#current_order.target_hexes.append(firebase_hex)
	#var path: Array[Vector3i] = Globals.movement_system._compute_path(current_hex, firebase_hex, team)
	#give_move_to_hex_order(firebase_hex, path, false)
	#action_controller.action_state = SquadActionController.SquadActionState.MOVING_TO_POSITION


func _start_assault_route() -> void:
	# current_order.target_hexes should hold route
	if current_order.target_hexes.is_empty():
		# optional: derive a simple fallback from current position if formation gave no path
		#var fallback_route: Array[Vector2i] = _compute_simple_fallback_route()
		#movement.set_route(fallback_route)
		current_order.target_hexes.append(Globals.objective_hexes[team][0])
	var path: Array[Vector3i] = MovementSystem._compute_path(current_hex, current_order.target_hexes[0], team)
	give_move_to_hex_order(current_order.target_hexes[0], path, false)
	
	action_controller.action_state = SquadActionController.SquadActionState.MOVING_TO_POSITION


func _complete_order_success() -> void:
	current_order_status = GoapTypes.SquadOrderStatus.ACHIEVED
	action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION

func _fail_order() -> void:
	current_order_status = GoapTypes.SquadOrderStatus.FAILED

func _break_order() -> void:
	current_order_status = GoapTypes.SquadOrderStatus.BROKEN

func get_formation_id() -> int:
	return formation_id

func get_effectiveness() -> float:
	# Plug in your existing E calculation
	var combat_effectiveness: float = 1.0
	return combat_effectiveness

func is_alive() -> bool:
	return members_alive > 0

func is_reserve_candidate() -> bool:
	# Simple version: any alive squad not currently in heavy contact
	var in_front_line: bool = false
	return not in_front_line

func is_probe_candidate() -> bool:
	# Pick light infantry with decent E
	return is_alive() and not is_mg_team()

func is_mg_team() -> bool:
	return squadType == Unit.SquadType.MG


func _on_command_connectivity_timeout() -> void:
	if is_instance_valid(command_squad):
		command_connectivity.compute_connectivity(self, command_squad)
		draw_command_link_strength.emit(team, self.current_hex, command_squad.current_hex, command_connectivity.command_link_strength)
		draw_leader_presence_strength.emit(team, self.current_hex, command_squad.current_hex, command_connectivity.leader_presence_strength)
		stress_system.leader_presence_strength = command_connectivity.leader_presence_strength


func _on_enemy_visibility_checker_timer_timeout() -> void:
	enemy_visiblity_checker.check_enemy_visibility(self)
