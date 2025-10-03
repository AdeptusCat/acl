# leader.gd
@tool
extends Node2D
class_name Leader

# === Exported ===
@export var snap_to_grid := true
@export var ground_map: HexagonTileMapLayer
@export var firepower: int = 0
@export var range: int = 0
@export var morale: int = 7
@export var has_support_weapon: bool = false
@export var morale_meter_max: int = 100
@export var base_death_chance: float = 0.1
@export var broken_death_multiplier: float = 2.0
@export var recovery_time_max: float = 5.0
@export var team: int = 0
@export var retreat_distance := 3
@export var retreat_speed := 70.0
@export var machine_guns: int = 0
@export var members_alive := 1

# personal sidearm if you fancy
@export var pistol_firepower: int = 1
@export var pistol_range_hexes: int = 2
@export var fire_rate: float = 1.2

# leadership bits
@export var aura_radius_hexes: int = 2
@export var leadership_bonus: float = 0.15
@export var rally_bonus: float = 0.10
@export var cohesion_mult: float = 1.05

# === Runtime ===
var morale_meter_current: int = 0
var path_hexes: Array[Vector2i] = []
var path_index: int = 0
var alive: bool = true
var surrendered: bool = false
var broken: bool = false
var recovery_timer_current: float = 0.0
var current_cover_bonus: int = 0
var current_hex: Vector2i
var goal_hex: Vector2i
var selected: bool = false
var moving: bool = false
var target_position: Vector2
var retreat_target_hex: Vector2i = Vector2i()
var units: Array[Node2D]

# === Nodes ===
@onready var ui: Node = $UnitUi
@onready var stress_system: StressController = $UnitStressController
@onready var movement: Node = $UnitMovement
@onready var combat: Node = $Combat
@onready var aura: LeaderAura = $LeaderAura

@onready var base_spv: float = combat.seconds_per_volley

#signal leader_killed(leader: Leader)
signal moved_to_hex(new_hex: Vector2i)
signal unit_arrived_at_hex(new_hex: Vector2i)
signal unit_died(unit)
signal retreat_complete(retreat_hex: Vector2i)
signal cover_updated(value: float)
signal deselect_unit(unit)
signal started_moving
signal unit_surrendered
signal unit_entered_new_hex(new_hex: Vector2i)

func _ready() -> void:
	add_to_group("leader")
	if snap_to_grid and ground_map != null and Engine.is_editor_hint():
		_snap_to_hex()
	if aura != null:
		aura.aura_radius_hexes = aura_radius_hexes
		aura.leadership_bonus = leadership_bonus
		aura.rally_bonus = rally_bonus
		aura.cohesion_mult = cohesion_mult
		aura.ground_map = ground_map
	if movement.has_method("set_unit_and_map"):
		movement.call("set_unit_and_map", self, ground_map)
	# leaders fight poorly by design
	if combat.has_method("configure_as_leader"):
		combat.call("configure_as_leader", pistol_firepower, pistol_range_hexes, fire_rate)

	
	update_team_sprite(team, true)
	connect("retreat_complete", _on_retreat_complete)
	#morale_system.morale_breaks.connect(_on_morale_breaks)
	#morale_system.morale_recovered.connect(_on_morale_recovered)
	#morale_system.unit_recovers.connect(_on_unit_recovers)
	
	#morale_system.morale_updated.connect(ui._on_morale_updated)
	#morale_system.morale_failure.connect(ui._on_morale_failure)
	#morale_system.morale_success.connect(ui._on_morale_success)
	#morale_system.morale_recovered.connect(ui._on_morale_recovered)
	#morale_system.morale_breaks.connect(ui._on_morale_breaks)
	cover_updated.connect(ui._on_cover_updated)
	
	unit_arrived_at_hex.connect(ui._on_unit_arrived_at_hex)
	
	#morale_system.morale_recovered.connect(ui._on_morale_recovered)
	
	combat.shoot.connect(ui.shoot)
	
	movement.unit = self
	movement.ground_map = ground_map

	movement.started_moving.connect(_on_started_moving)
	movement.stopped_moving.connect(_on_stopped_moving)
	movement.rout_failed.connect(_on_rout_failed)
	
	stress_system.state_changed.connect(_on_state_changed)
	stress_system.stress_changed.connect(_on_stress_changed)
	
	
	ui.set_support_weapons(machine_guns)
	
	combat.set_mg(machine_guns)

func _snap_to_hex() -> void:
	var map_coords: Vector2i = ground_map.local_to_map(position)
	position = ground_map.map_to_local(map_coords)
	current_hex = map_coords

# === Interface used by aura/other systems ===
func get_current_hex() -> Vector2i:
	return current_hex

func get_team() -> int:
	return team

# === Casualty handling ===
func take_hit() -> void:
	# one-man counter; a single casualty knocks him out
	#_die(false)
	die()

#func _die(surrendered_instead: bool) -> void:
	#if not alive:
		#return
	#alive = false
	#surrendered = surrendered_instead
	#if ui.has_method("die"):
		#await ui.call("die")
	#emit_signal("leader_killed", self)
	## Optional: notify nearby squads for stress spike
	#_notify_nearby_on_leader_death()
	#queue_free()
	


func _notify_nearby_on_leader_death() -> void:
	if ground_map == null:
		return
	var my_hex: Vector2i = current_hex
	var squads: Array = get_tree().get_nodes_in_group("squad")
	for u in squads:
		var unit: Node2D = u
		if not is_instance_valid(unit):
			continue
		if not unit.has_node("UnitStressController"):
			continue
		if not unit.has_method("get_current_hex"):
			continue
		if not _same_team(self, unit):
			continue
		var uh: Vector2i = unit.call("get_current_hex")
		var d: int = $LeaderAura._hex_distance(my_hex, uh)
		var sc: StressController = unit.get_node("UnitStressController") as StressController
		sc.on_nearby_leader_killed(d)

func _same_team(a: Node2D, b: Node2D) -> bool:
	var ta: int = a.call("get_team")
	var tb: int = b.call("get_team")
	if ta == tb:
		return true
	return false
	


func _on_started_moving():
	moving = true
	ui.started_moving(broken, surrendered)
	started_moving.emit()


func _on_stopped_moving():
	moving = false
	ui.stopped_moving(broken, surrendered)


func _on_rout_failed():
	surrender()
	#die()


func _on_morale_breaks():
	if selected:
		deselect_unit.emit(self)
		deselect()
	broken = true


func _on_morale_recovered():
	broken = false


# === Process Loop ===
func _process(delta):
	if Engine.is_editor_hint() and snap_to_grid:
		if ground_map == null:
			return
		snap_to_hex()
		var map_coords = ground_map.local_to_map(position)
		position = ground_map.map_to_local(map_coords)
		current_hex = map_coords
		set_team(team)
		return

	if not alive:
		return

	#morale_system._process_recovery(delta)
	
	#movement.process(delta)


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


func get_visible_enemies(unit_visible_enemies: Dictionary) -> Array:
	return unit_visible_enemies.get(self, [])


func set_team(new_team: int):
	team = new_team
	update_team_sprite(team, true)


func update_team_sprite(team: int, leader: bool = false):
	ui.update_team_sprite(team, true)


func fire_at(target: Node2D, distance_in_hexes: int, terrain_defense_bonus: float, unit_visible_enemies: Dictionary):
	if not alive or surrendered:
		return
	combat.fire_at(self, target, current_hex, distance_in_hexes, terrain_defense_bonus, firepower, range, unit_visible_enemies, fire_rate, )


func receive_fire(incoming_firepower: int, terrain_defense_bonus: float, unit_visible_enemies: Dictionary):
	#morale_system.receive_fire(incoming_firepower, movement.moving, terrain_defense_bonus, unit_visible_enemies)
	cover_updated.emit(int(terrain_defense_bonus))
	#if moving and not broken and not surrendered:
		#movement.recalc_path()

func _on_incoming_fire_effect(casualties:int, df:float, ds:float, source:Node) -> void:
	if casualties > 0:
		_apply_casualties(casualties)
	stress_system.apply_stress(df, ds)
	#emit_signal("stress_applied", df, ds, source)


func _apply_casualties(n:int) -> void:
	members_alive = max(0, members_alive - n)
	var leader_down = false
	#if leader_alive and randf() < 1.0/float(max(1,members_alive+1)): # small chance hit was leader
		#leader_alive = false
		#leader_down = true
		##emit_signal("leader_killed")
		#stress_system.leadership_bonus = 0.0
	stress_system.on_casualty_event(n, leader_down)
	#emit_signal("casualties_taken", original_size - members_alive)
	ui.set_memebers_alive(members_alive)
	if members_alive <= 0:
		_set_combat_ineffective()


func _set_combat_ineffective():
	stress_system.state = StressController.MoraleState.COMBAT_INEFFECTIVE
	ui.state_changed(stress_system.state)
	die()
	#emit_signal("state_changed",
		#StressController.MoraleState.PANIC, stress_system.state)

func surrender():
	movement.move_to_hex(current_hex)
	surrendered = true
	#alive = false
	broken = false
	emit_signal("unit_surrendered", self)
	ui.surrender()


func die():
	alive = false
	emit_signal("unit_died", self)
	await ui.die()
	queue_free()


func _on_morale_failed(_known_enemies: Array) -> void:
	var known_enemies: Array[Node2D]
	for unit in units:
		if not unit.team == team and not unit.surrendered:
			known_enemies.append(unit)
	movement.rout(current_hex, known_enemies, retreat_distance)
	


func _on_retreat_complete(retreat_hex) -> void:
	movement.moving = false
	current_hex = retreat_hex
	moved_to_hex.emit(self, current_hex)
	#emit_signal("moved_to_hex", self, current_hex)


func _on_stress_changed(stress: float):
	ui.update_bar(int(stress), 100)


enum MoraleState { NORMAL, CAUTIOUS, PINNED, PANIC, COMBAT_INEFFECTIVE }
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
	combat.current_state = next
	
	## 2) ROF/accuracy from state table
	var m = STATES.STATE_MOD[next]
	## guard against silly zeros
	var rof_mult: float = max(float(m.rof), 0.05)
	combat.seconds_per_volley = base_spv / rof_mult
	combat.accuracy_multiplier = m.acc

	## 3) Visuals/pose
	ui.state_changed(next)
