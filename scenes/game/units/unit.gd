# unit.gd
@tool
extends Node2D
class_name Unit


enum Company {
	A,
	B,
	C,
	D,
	E,
	F,
}


const COMPANY_NAMES: Dictionary[Company, String] = {
	Company.A: "A",
	Company.B: "B",
	Company.C: "C",
	Company.D: "D",
	Company.E: "E",
	Company.F: "F",
}

enum AttackState { AUTO, MANUAL_GROUND, MANUAL_TRACK }
var attackState: AttackState = AttackState.AUTO
var attack_ground_rounds_budget: int = 0
var terrain_defense_bonus: int = 0

var close_combat_defense_preparedness: float = 0.0

var position_advice: PositionResult
var influence_map: PackedFloat32Array
var best_index: int = -1

@export var squad: int = 0 : set = set_squad_nr
@export var platoon: int = 0 : set = set_platoon_nr
@export var company: Company = Company.A : set = set_company_nr

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
@export var snap_to_grid: bool = true
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
@export var retreat_speed: float = 70.0
@export var fire_rate: float = 0.75
@export var machine_guns: int = 0


@export var members_alive: int = 10
var original_size: int = 10
var casualties_taken: int = 0
var casualty_records: Array[CasualtyRecord] = []
var embedded_leader_alive: bool = true


@export var loadouts: Array[SoldierLoadout] = []
@export var squad_loadout: SquadLoadoutSpec
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
var is_moving: bool = false
var target_position: Vector2
var retreat_target_hex: Vector2i = Vector2i()
var effective_range: int = 0
var in_close_combat: bool = false

var highest_rank_grade: RankGrades.Grade = RankGrades.Grade.SOLDIER

@export var squads_collection: SquadsCollection
@export var squad_type: Globals.SquadType = Globals.SquadType.Rifle : set = set_squad_type

#@export var make_rifle_squad: bool = false : set = _make_rifle_squad

# === Signals ===
signal unit_entered_hex(new_hex: Vector2i)
signal unit_arrived_at_hex(new_hex: Vector2i)
signal unit_died(unit: Unit)
signal retreat_complete(retreat_hex: Vector2i)
signal cover_updated(value: float)
signal deselect_unit(unit: Unit)
signal started_moving
signal unit_surrendered
signal contacts_reported(unit: Unit, contact: Array[Unit])

# unit details signals
signal soldiers_changed
signal state_changed(state: int)
signal new_target_hex(unit: Unit, hex: Vector2i)

signal draw_command_link_strength(from_hex: Vector2i, to_hex: Vector2i, strength: float)
signal draw_leader_presence_strength(from_hex: Vector2i, to_hex: Vector2i, strength: float)

# === Nodes ===
@onready var ui: UnitUi = $UnitUi
@onready var stress_system: StressController = $UnitStressController
@onready var movement:UnitMovement = $UnitMovement
@onready var leader_aura: LeaderAura = $LeaderAura
@onready var squad_fire: SquadFireController = $SquadFireController
@onready var weapon_audio: WeaponAudio = $WeaponAudio
@onready var action_controller: SquadActionController = $SquadActionController
@onready var command_connectivity: CommandConnectivity = $CommandConnectivity
@onready var enemy_visiblity_checker: EnemyVisibilityChecker = $EnemyVisibilityChecker
@onready var command_connectivity_timer: Timer = $CommandConnectivityTimer
@onready var enemy_visibility_checker_timer: Timer = $EnemyVisibilityCheckerTimer
@onready var combat_stats: UnitCombatStats = $CombatStats
@onready var combat_stats_timer: Timer = $CombatStatsTimer
@onready var squad_ai_controller: SquadAiController = $SquadAiController


# === DEBUG ===
@onready var action_label: Label = $ActionLabel

# === Classes ===
@onready var tactical_state: SquadTacticalState = SquadTacticalState.new()


func _ready() -> void:
	_make_squad()


# === Ready ===
func setup() -> void:
	if Engine.is_editor_hint():
		return
	
	action_controller.init(self, movement, squad_fire, stress_system, ui)
	retreat_complete.connect(_on_retreat_complete)
	cover_updated.connect(ui._on_cover_updated)
	
	current_cube = LOSHelper.ground_layer.map_to_cube(current_hex)
	
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
	#_setup_runtime_soldiers()
	_setup_runtime_soldiers(squad_loadout)
	
	if squad_fire.soldiers.size() <= 0:
		pass
	
	squad_fire.fire_shot.connect(_on_fire_shot)
	squad_fire.fire_riflegrenade.connect(_on_fire_riflegrenade)
	
	_refresh_leader_aura()
	
	ui.set_loadout(squad_fire.soldiers)
	
	update_team_sprite(team, squad_type)
	movement.new_target_hex.connect(_on_new_target_hex)
	
	command_connectivity_timer.start()
	enemy_visibility_checker_timer.start()
	combat_stats.unit = self
	combat_stats_timer.start()
	squad_ai_controller.unit = self


func game_start() -> void:
	command_connectivity_timer.start()
	enemy_visibility_checker_timer.start()
	combat_stats_timer.start()


func update_terrain_defense_bonus() -> void:
	terrain_defense_bonus = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(current_hex))


func setAttackState(_attackState: AttackState) -> void:
	attackState = _attackState
	match attackState:
		AttackState.MANUAL_GROUND:
			attack_ground_rounds_budget = 50

func order(cmd: Globals.UnitCmd, parameter: Variant) -> void:
	if not alive or in_close_combat:
		return
	match cmd:
		Globals.UnitCmd.FIRE_AT_HEX:
			if squad_type == Globals.SquadType.MORTAR:
				if parameter is Unit:
					var enemy_unit: Unit = parameter as Unit
					squad_fire.set_target_unit(enemy_unit)
				else:
					var map_hex: Vector2i = parameter as Vector2i
					fire_mortar(map_hex)
			else:
				var map_hex: Vector2i = parameter as Vector2i
				var units: Array = Globals.unit_visible_enemies.get(self, [])
				var has_target_unit: bool = false
				for unit: Node2D in units:
					if unit.current_hex == map_hex:
						if not unit.team == Globals.team_player or Debug.enemy_selectable:
							var _path: Array[Vector3i] = []
							setAttackState(AttackState.MANUAL_TRACK)
							squad_fire.set_target_unit(unit)
							has_target_unit = true
				if not has_target_unit:
					if attackState == AttackState.MANUAL_GROUND and squad_fire.has_target_hex and squad_fire.target_hex == map_hex:
						return
					setAttackState(AttackState.MANUAL_GROUND)
					squad_fire.set_target_hex(map_hex)
					var target_distance: int = LOSHelper.ground_layer.cube_distance(current_cube, LOSHelper.ground_layer.map_to_cube(map_hex))
					squad_fire.set_soldiers_new_target_task(target_distance)
					
		Globals.UnitCmd.FIRE_AT_UNIT:
			var enemy_unit: Unit = parameter as Unit
			squad_fire.set_target_unit(enemy_unit)
		
		
		#Globals.UnitCmd.ATTACK_UNIT:
			#if squad_type == Globals.SquadType.MORTAR:
				#if parameter is Unit:
					#var enemy_unit: Unit = parameter as Unit
					#squad_fire.set_target_unit(enemy_unit)
				#else:
					#var map_hex: Vector2i = parameter as Vector2i
					#fire_mortar(map_hex)
			#else:
				#var enemy_unit: Unit = parameter as Unit
				#squad_fire.set_target_unit(enemy_unit)
#
		#Globals.UnitCmd.ATTACK_GROUND:
			#if squad_type == Globals.SquadType.MORTAR:
				#if parameter is Unit:
					#var enemy_unit: Unit = parameter as Unit
					#squad_fire.set_target_unit(enemy_unit)
				#else:
					#var map_hex: Vector2i = parameter as Vector2i
					#fire_mortar(map_hex)
			#else:
				#var map_hex: Vector2i = parameter as Vector2i
				#var units: Array[Node2D] = _find_units_at(map_hex)
				#for unit in units:
					#if not unit.team == Globals.team_player or Debug.enemy_selectable:
						#var _path: Array[Vector3i] = []
						#squad_fire.set_target_unit(unit)
		Globals.UnitCmd.MOVE:
			var to_hex: Vector2i = parameter as Vector2i
			if not current_hex == to_hex:
				var path: Array[Vector3i] = MovementSystem._compute_path(current_hex, to_hex, team)
				give_move_to_hex_order(to_hex, path, false)
			else:
				movement.stop()
				#movement.move_to_hex(to_hex)
		Globals.UnitCmd.STOP:
			movement.stop()
			setAttackState(AttackState.AUTO)


func _on_new_target_hex(end_of_path_hex: Vector2i) -> void:
	target_hex = end_of_path_hex
	new_target_hex.emit(self, target_hex)

func _now() -> float:
	return float(Engine.get_physics_frames()) * PHYSICS_DT


func fire_mortar(map_hex: Vector2i) -> void:
	setAttackState(AttackState.MANUAL_GROUND)
	squad_fire.fire_mortar(map_hex)


func is_good_order() -> bool:
	if surrendered or not alive or broken:
		return false
	else:
		return true 


func _on_fire_shot(weapon: WeaponSpec, shot_target_hex: Vector2i) -> void:
	# Use the burst's captured destination even after sight loss clears the target.
	if weapon.family != WeaponSpec.Family.MORTAR:
		var pos: Vector2 = LOSHelper.ground_layer.map_to_local(shot_target_hex)
		match weapon.family: 
			WeaponSpec.Family.SMALL_ARM:
				ui.shoot(global_position, pos, weapon)
			WeaponSpec.Family.ROCKET_LAUNCHER:
				ui.shoot_rocket_launcher(global_position, pos, weapon)
	if weapon.family == WeaponSpec.Family.MORTAR:
		var pos: Vector2 = LOSHelper.ground_layer.map_to_local(shot_target_hex)
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


func _on_fire_riflegrenade(weapon_spec: WeaponSpec) -> void:
	if squad_fire.target_unit:
		ui.shoot_riflegrenade(global_position, squad_fire.target_unit.global_position, weapon_spec)



func _on_new_target_unit(unit: Unit) -> void:
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
	while i < squad_fire.soldiers.size():
		var s: Soldier = squad_fire.soldiers[i]
		if s.is_alive:
			var g: int = _runtime_soldier_grade(s)
			if g > best:
				best = g
		i += 1
	return best

# Adjust this if your Soldier stores the grade underunder a different field.
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


func _setup_runtime_soldiers(_squad_loadout: SquadLoadoutSpec) -> void:
	UnitRosterBuilder.setup_runtime_soldiers(self, _squad_loadout)


func _resize_loadouts(n: int) -> void:
	SquadLoadoutTemplates.resize_loadouts(self, n)


func set_squad_type(_squad_type: Globals.SquadType) -> void:
	squad_type = _squad_type
	_make_squad()


func set_squad_nr(_value: int) -> void:
	squad = _value
	_make_squad()


func set_platoon_nr(_value: int) -> void:
	platoon = _value
	_make_squad()


func set_company_nr(_value: Company) -> void:
	company = _value
	_make_squad()


func _make_squad() -> void:
	match squad_type:
		Globals.SquadType.PLATOON_HEADQUARTERS:
			if not squad == 0:
				squad = 0
		Globals.SquadType.COMPANY_HEADQUARTERS:
			if not squad == 0:
				squad = 0
			if not platoon == 0:
				platoon = 0
	var _squads: Squads = squads_collection.get_squad(team)
	var _squad: SquadLoadoutSpec = _squads.get_squad(squad_type)
	squad_loadout = _squad
	name =   "C" + str(COMPANY_NAMES[company]) + "_P" + str(platoon) + "_S" + str(squad) + "_" + Globals.TEAM_NAMES[team] + "_" + Globals.SQUAD_TYPE_NAMES[squad_type]


# template builders (run in editor by ticking the bool, it resets to false)
func _make_rifle_squad(v: bool) -> void:
	if v:
		squad_type = Globals.SquadType.Rifle
		make_rifle_squad = false
		SquadLoadoutTemplates.make_rifle_squad(self)


func _make_platoon_headquarters_squad(v: bool) -> void:
	if v:
		squad_type = Globals.SquadType.PLATOON_HEADQUARTERS
		make_rifle_squad = false
		SquadLoadoutTemplates.make_platoon_headquarters_squad(self)


func _make_company_headquarters_squad(v: bool) -> void:
	if v:
		squad_type = Globals.SquadType.COMPANY_HEADQUARTERS
		make_rifle_squad = false
		SquadLoadoutTemplates.make_company_headquarters_squad(self)


func _make_light_mg_team(v: bool) -> void:
	if v:
		squad_type = Globals.SquadType.MG
		make_light_mg_team = false
		SquadLoadoutTemplates.make_light_mg_team(self)


func _make_anti_tank_squad(v: bool) -> void:
	if v:
		squad_type = Globals.SquadType.ANTITANK
		make_anti_tank_squad = false
		SquadLoadoutTemplates.make_anti_tank_squad(self)


func _make_light_mortar_squad(v: bool) -> void:
	if v:
		squad_type = Globals.SquadType.MORTAR
		make_light_mortar_squad = false
		SquadLoadoutTemplates.make_light_mortar_squad(self)


func _make_medium_mortar_squad(v: bool) -> void:
	if v:
		squad_type = Globals.SquadType.MORTAR
		make_anti_tank_squad = false
		SquadLoadoutTemplates.make_medium_mortar_squad(self)


func _on_started_moving() -> void:
	setAttackState(Unit.AttackState.AUTO)
	is_moving = true
	ui.started_moving(broken, surrendered)
	started_moving.emit()
	squad_fire.set_target_unit(null)
	action_controller.on_started_moving()


func _on_stopped_moving() -> void:
	is_moving = false
	ui.stopped_moving(broken, surrendered)
	#action_controller.on_stopped_moving()


# FIXME stress > 100 is weird since the player doesnt see stress go down and wonders why the unit wont rally


func _on_unit_arrived_at_hex(new_hex: Vector2i) -> void:
	action_controller.on_reached_hex(new_hex)


func _on_rout_failed() -> void:
	surrender()
	#die()


func _on_morale_breaks() -> void:
	#if selected:
		#deselect_unit.emit(self)
		#deselect()
	broken = true


func _on_morale_recovered() -> void:
	broken = false


# === Process Loop ===

func _process(_delta: float) -> void:
	
	if Engine.is_editor_hint() and snap_to_grid:
		if ground_map == null:
			return
		snap_to_hex()
		var map_coords: Vector2i = ground_map.local_to_map(position)
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

	for unit: Unit in raw:
		if is_instance_valid(unit):
			enemies.append(unit)

	if enemies.is_empty():
		has_reported_contact = false
	else:
		has_reported_contact = true
	
	var _new_enemy: bool = false
	for enemy_squad: Unit in enemies:
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
	info["firepower"] = InfluenceUnitQuery.get_unit_firepower(enemy)
	info["effectiveness"] = InfluenceUnitQuery.get_unit_effectiveness(enemy)
	info["weapon_range"] = InfluenceUnitQuery.get_unit_range(enemy)
	info["crossing_seconds"] = InfluenceUnitQuery.captured_crossing_seconds(enemy)
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
func snap_to_hex() -> void:
	if ground_map:
		var map_coords: Vector2i = ground_map.local_to_map(position)
		position = ground_map.map_to_local(map_coords)


func select() -> void:
	ui.select()
	selected = true


func deselect() -> void:
	ui.deselect()
	selected = false


func set_cover(cover_value: int) -> void:
	ui.set_cover(cover_value)


func get_visible_enemies() -> Array:
	return Globals.unit_visible_enemies.get(self, [])


func set_team(new_team: Globals.Team) -> void:
	team = new_team
	update_team_sprite(team, squad_type)


func update_team_sprite(_team: Globals.Team, _squad_type: Globals.SquadType) -> void:
	ui.update_team_sprite(_team, _squad_type)



#func receive_fire(incoming_firepower: int, terrain_defense_bonus: float, unit_visible_enemies: Dictionary):
func receive_fire(terrain_defense_bonus: float) -> void:
	cover_updated.emit(int(terrain_defense_bonus))
	#if is_moving and not broken and not surrendered:
		#movement.recalc_path()

func _on_incoming_fire_effect(casualties:int, df:float, ds:float, _source:Node) -> void:
	if not alive or Debug.no_damage:
		return
	if casualties > 0:
		_apply_casualties(casualties)
		ui.show_casualty()
		soldiers_changed.emit()
	if not alive:
		return
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
	#ui.set_members_alive(members_alive)
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


func apply_specific_casualty(casualty: Soldier) -> bool:
	return UnitCasualtyHandler.apply_specific_casualty(self, casualty)


func _apply_casualties(n: int) -> void:
	UnitCasualtyHandler.apply_casualties(self, n)


func _promote_new_leader() -> void:
	UnitCasualtyHandler.promote_new_leader(self)


func _assign_gunner_and_loader_for_weapon(wp: WeaponSpec) -> void:
	UnitCasualtyHandler.assign_gunner_and_loader_for_weapon(self, wp)


func _fill_missing_loaders_for_existing_guns() -> void:
	UnitCasualtyHandler.fill_missing_loaders_for_existing_guns(self)


func _index_of_role(role: int) -> int:
	return UnitCasualtyHandler.index_of_role(self, role)


func _has_role(role: int) -> bool:
	return UnitCasualtyHandler.has_role(self, role)


func _find_first_SOLDIER() -> int:
	return UnitCasualtyHandler.find_first_SOLDIER(self)


func _find_first_SOLDIER_OR_ASSISTANT_excluding(exclude: Array[int]) -> int:
	return UnitCasualtyHandler.find_first_SOLDIER_OR_ASSISTANT_excluding(self, exclude)


func remove_indices(target: Array, indices: Array[int]) -> void:
	UnitCasualtyHandler.remove_indices(self, target, indices)


func get_unique_random_ints(n: int, _max: int) -> Array[int]:
	return UnitCasualtyHandler.get_unique_random_ints(self, n, _max)


func _set_combat_ineffective() -> void:
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
		


func get_squad_type_name(type: Globals.SquadType) -> String:
	match type:
		Globals.SquadType.Rifle: return "Rifle Squad"
		Globals.SquadType.MG: return "Machine Gun Squad"
		Globals.SquadType.ANTITANK: return "Antitank Team"
		Globals.SquadType.MORTAR: return "Mortar Squad"
		Globals.SquadType.PLATOON_HEADQUARTERS: return "Platoon Headquarters"
		Globals.SquadType.COMPANY_HEADQUARTERS: return "Company Headquarters"
		_: return "Unknown"
		

func surrender() -> void:
	#return
	#movement.move_to_hex(current_hex)
	#if not team == Globals.team_player:
	var enemy_team: Globals.Team
	if team == Globals.Team.AXIS:
		enemy_team = Globals.Team.ALLIES
	if team == Globals.Team.ALLIES:
		enemy_team = Globals.Team.AXIS
	Globals.units_destroyed.units_collection[enemy_team].units.append(self)
	movement.stop()
	surrendered = true
	#alive = false
	broken = false
	emit_signal("unit_surrendered", self)
	ui.surrender()


func die() -> void:
	if not alive:
		return
	alive = false
	# Direct elimination must retain the remaining men and equipment as casualties.
	for soldier: Soldier in squad_fire.soldiers:
		_record_casualty(soldier)
		if not squad_fire.casualties.has(soldier):
			squad_fire.casualties.append(soldier)
	squad_fire.soldiers.clear()
	members_alive = 0
	casualties_taken = squad_fire.casualties.size()
	ui.set_members_alive(0)
	is_moving = false
	movement.is_moving = false
	action_controller.clear_orders()
	leader_aura.shutdown()
	weapon_audio.shutdown()
	for candidate: Unit in get_tree().get_nodes_in_group("units"):
		if candidate != self and candidate.command_squad == self:
			candidate._on_command_connectivity_timeout()
	set_process(false)
	# Keep controllers owned by the corpse so in-flight projectiles retain valid
	# references. They are freed with the unit when the battlefield is cleared.
	for child: Node in get_children():
		if child != ui:
			_shutdown_controller(child)
	remove_from_group("units")
	add_to_group("dead_units")
	unit_died.emit(self)
	await ui.die()


func _shutdown_controller(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is Timer:
		var timer: Timer = node as Timer
		timer.stop()
	for child: Node in node.get_children():
		_shutdown_controller(child)


func _record_casualty(soldier: Soldier) -> void:
	soldier.is_alive = false
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	var record: CasualtyRecord = Globals.record_casualty(self, soldier)
	if record != null and not casualty_records.has(record):
		casualty_records.append(record)


func _on_retreat_complete(retreat_hex: Vector2i) -> void:
	movement.is_moving = false
	current_hex = retreat_hex
	current_cube = LOSHelper.ground_layer.map_to_cube(retreat_hex)
	unit_entered_hex.emit(self, current_hex)
	#emit_signal("moved_to_hex", self, current_hex)
	action_controller.on_retreat_complete(retreat_hex)


func _on_stress_changed(stress: float) -> void:
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
	var m: Dictionary = STATES.STATE_MOD[next]
	## guard against silly zeros
	var rof_mult: float = max(float(m.rof), 0.05)
	squad_fire.seconds_per_volley = squad_fire.base_seconds_per_volley / rof_mult
	squad_fire.accuracy_multiplier = m.acc

	## 3) Visuals/pose
	ui.state_changed(next)
	
	state_changed.emit(next)
	action_controller.on_morale_state_changed(prev, next)


func _on_unit_ui_debug_kill_soldier() -> void:
	_apply_casualties(1)
	ui.show_casualty()
	soldiers_changed.emit()
	# FIXME stress through casualty from debug kill should not be fixed value
	stress_system.apply_stress(10.0, 10.0)
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
	return squad_type == Globals.SquadType.MG


func _on_command_connectivity_timeout() -> void:
	if is_instance_valid(command_squad):
		command_connectivity.compute_connectivity(self, command_squad)
		draw_command_link_strength.emit(team, self.current_hex, command_squad.current_hex, command_connectivity.command_link_strength)
		draw_leader_presence_strength.emit(team, self.current_hex, command_squad.current_hex, command_connectivity.leader_presence_strength)
	else:
		command_connectivity.clear_connectivity()
	stress_system.leader_presence_strength = command_connectivity.leader_presence_strength


func _on_enemy_visibility_checker_timer_timeout() -> void:
	enemy_visiblity_checker.check_enemy_visibility(self)


func update_close_defense_preparedness(unit: Unit, dt: float) -> void:
	var delta: float = 0.0
	var terrain_mult: float = get_preparedness_terrain_mult(unit.terrain_defense_bonus)
	var morale_mult: float = get_preparedness_morale_mult(unit.stress_system.state)
	#var cohesion_mult: float = clamp(unit.cohesion, 0.0, 1.0)

	if unit.broken:
		delta = -1.8 * dt
	elif unit.is_moving:
		delta = -0.9 * dt
	else:
		delta = 0.25 * dt
		delta *= terrain_mult
		delta *= morale_mult
		#delta *= cohesion_mult

	unit.close_combat_defense_preparedness += delta
	unit.close_combat_defense_preparedness = clamp(unit.close_combat_defense_preparedness, 0.0, 1.0)


func get_preparedness_morale_mult(state: STATES.MoraleState) -> float:
	if state == STATES.MoraleState.NORMAL:
		return 1.0
	if state == STATES.MoraleState.CAUTIOUS:
		return 0.8
	if state == STATES.MoraleState.PINNED:
		return 0.35
	if state == STATES.MoraleState.PANIC:
		return 0.0
	if state == STATES.MoraleState.COMBAT_INEFFECTIVE:
		return 0.0
	return 1.0


func get_preparedness_terrain_mult(defense_bonus: int) -> float:
	return clamp(0.25 + float(defense_bonus) * 0.9, 0.25, 1.35)


func _on_close_combat_defense_preparedness_timer_timeout() -> void:
	update_close_defense_preparedness(self, 0.1)


func create_save_data() -> UnitSaveData:
	return UnitSaveCodec.create_save_data(self)


func apply_save_data(data: UnitSaveData) -> void:
	UnitSaveCodec.apply_save_data(self, data)


func _on_unit_combat_stats_timer_timeout() -> void:
	combat_stats.update_stats(combat_stats_timer.wait_time)


func is_centered_on_hex(hex: Vector2i) -> bool:
	if LOSHelper.ground_layer.map_to_local(hex) == position:
		return true
	return false
