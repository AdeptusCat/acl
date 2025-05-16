@tool
extends Node2D
class_name Unit

# === Exported ===
@export var snap_to_grid := true
@export var ground_map: HexagonTileMapLayer

@export var firepower: int = 4
@export var range: int = 6
@export var morale: int = 7
@export var has_support_weapon: bool = false
@export var morale_meter_max: int = 100
@export var base_death_chance: float = 0.1
@export var broken_death_multiplier: float = 2.0
@export var recovery_time_max: float = 5.0
@export var team: int = 0
@export var retreat_distance := 3
@export var retreat_speed := 100.0


@export var fire_rate: float = 1.5

# === Runtime State ===
var morale_meter_current: int = 0
var path_hexes: Array[Vector2i] = []
var path_index: int = 0
var alive: bool = true
var broken: bool = false
var recovery_timer_current: float = 0.0
var current_cover_bonus: int = 0
var current_hex: Vector2i
var selected: bool = false
#var moving: bool = false
var target_position: Vector2
var move_speed: float = 100.0
var retreat_target_hex: Vector2i = Vector2i()
var fire_timer: float = 0.0

# === Signals ===
signal moved_to_hex(new_hex: Vector2i)
signal unit_arrived_at_hex(new_hex: Vector2i)
signal unit_died(unit)
signal retreat_complete(retreat_hex: Vector2i)
signal cover_updated(value: float)

# === Nodes ===
@onready var ui := $UnitUi

# === Classes ===
@onready var morale_system := UnitMorale.new(self)
#@onready var morale_ui := UnitMoraleUI.new(self)
@onready var movement := UnitMovement.new(self)

# === Ready ===
func _ready():
	update_team_sprite(team)
	connect("retreat_complete", _on_retreat_complete)
	morale_system.morale_breaks.connect(_on_morale_breaks)
	morale_system.morale_recovered.connect(_on_morale_recovered)
	#morale_system.unit_recovers.connect(_on_unit_recovers)
	
	morale_system.morale_updated.connect(ui._on_morale_updated)
	morale_system.morale_failure.connect(ui._on_morale_failure)
	morale_system.morale_success.connect(ui._on_morale_success)
	morale_system.morale_recovered.connect(ui._on_morale_recovered)
	morale_system.morale_breaks.connect(ui._on_morale_breaks)
	cover_updated.connect(ui._on_cover_updated)
	#morale_system.morale_recovered.connect(ui._on_morale_recovered)
	
	movement.ground_map = ground_map

func _on_morale_breaks():
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

	morale_system._process_recovery(delta)
	

	movement.process(delta)
	#if moving:
		#_handle_movement(delta)
		#return

	handle_auto_fire(delta)


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

func handle_auto_fire(delta):
	if movement.moving or not alive or broken:
		return

	fire_timer -= delta
	if fire_timer > 0:
		return  # Still waiting for next shot

	var visible_enemies = get_visible_enemies()

	for enemy in visible_enemies:
		if enemy and enemy.alive:
			var distance = current_hex.distance_to(enemy.current_hex)
			if distance <= range * 2:
				var cover_map = LOSHelper.los_lookup.get(current_hex, null)
				var targetCover = 0
				if cover_map and cover_map.has(enemy.current_hex):
					var data = cover_map[enemy.current_hex]
					targetCover = data["target_cover"]

				enemy.set_cover(targetCover)
				fire_at(enemy, distance, targetCover)
				fire_timer = fire_rate
				break


func get_visible_enemies() -> Array:
	var manager = get_parent()
	return manager.unit_visible_enemies.get(self, [])


func set_team(new_team: int):
	team = new_team
	update_team_sprite(team)


func update_team_sprite(team: int):
	ui.update_team_sprite(team)


func fire_at(target: Node2D, distance_in_hexes: int, terrain_defense_bonus: float):
	if not alive:
		return

	var actual_firepower = firepower
	if distance_in_hexes > range:
		if distance_in_hexes <= range * 2:
			actual_firepower = firepower / 2
		else:
			return

	var target_hex = target.current_hex
	var visible = get_visible_enemies()
	var batch_targets: Array = []

	for u in visible:
		if is_instance_valid(u) and u.alive and u.current_hex == target_hex:
			batch_targets.append(u)

	if batch_targets.is_empty():
		return

	for u in batch_targets:
		u.set_cover(terrain_defense_bonus)
		u.receive_fire(actual_firepower, terrain_defense_bonus)

	fire_burst(self, batch_targets[0], 8, fire_rate)


func fire_burst(shooter, target, rounds: int, bullets_per_sec: float) -> void:
	var interval = 1.0 / bullets_per_sec
	var from_pos = global_position

	for i in range(rounds):
		if not is_instance_valid(shooter) or not is_instance_valid(target):
			return
		if not get_visible_enemies().has(target):
			return
		if broken:
			return
		ui.shoot(from_pos, target.global_position)

		await get_tree().create_timer(interval).timeout


func receive_fire(incoming_firepower: int, terrain_defense_bonus: float):
	morale_system.receive_fire(incoming_firepower, movement.moving, terrain_defense_bonus)
	cover_updated.emit(int(terrain_defense_bonus))


func die():
	alive = false
	emit_signal("unit_died", self)
	await ui.die()
	queue_free()


func _on_morale_failed(known_enemies: Array) -> void:
	var retreat_map = compute_retreat_hex(current_hex, known_enemies, retreat_distance)
	movement.retreating = true
	retreat_target_hex = retreat_map

	var from_id = ground_map.pathfinding_get_point_id(current_hex)
	var to_id = ground_map.pathfinding_get_point_id(retreat_map)
	var id_path = ground_map.astar.get_id_path(from_id, to_id)

	var cube_path: Array[Vector3i] = []
	for pid in id_path:
		var pos = ground_map.astar.get_point_position(pid)
		cube_path.append(ground_map.local_to_cube(pos))

	movement.follow_cube_path(cube_path)

func _on_retreat_complete(retreat_hex) -> void:
	movement.moving = false
	current_hex = retreat_hex
	emit_signal("moved_to_hex", self, current_hex)



func compute_retreat_hex(origin_hex: Vector2i, known_enemies: Array, steps: int) -> Vector2i:
	# shortcuts
	var map    = ground_map                          # HexagonTileMapLayer reference
	var ground = LOSHelper.ground_layer          # for map_to_local()
	var build  = LOSHelper.building_layer        # for get_cell_source_id()

	# 1) enemy centroid in pixel‐space
	var centroid = Vector2.ZERO
	var enemy_hexes : Array
	for enemy in known_enemies:
		if not is_instance_valid(enemy):
			continue
		enemy_hexes.append(enemy.current_hex)
	for e_hex in enemy_hexes:
		centroid += ground.map_to_local(e_hex)
	if enemy_hexes.size() > 0:
		centroid /= enemy_hexes.size()

	# 2) all cubes within 'steps'
	var origin_cube = map.map_to_cube(origin_hex)
	var cube_list   = map.cube_range(origin_cube, steps)

	# 3) inline Callable to test “unseen by all enemies”
	var is_unseen = func(test_map_hex: Vector2i) -> bool:
		var tpos = ground.map_to_local(test_map_hex)
		for e_hex in enemy_hexes:
			var epos = ground.map_to_local(e_hex)
			var los  = LOSHelper.check_los(epos, tpos, 1, 0, 1, 0)
			if not los["blocked"]:
				return false
		return true

	# 4) bucket hexes by priority
	var unseen_bld  : Array[Vector2i] = []
	var any_bld     : Array[Vector2i] = []
	var unseen_only : Array[Vector2i] = []
	for c3 in cube_list:
		var m = map.cube_to_map(c3)
		if map.get_cell_source_id(m) == -1:
			continue  # no tile here
		var has_b = build.get_cell_source_id(m) != -1
		var vis   = is_unseen.call(m)
		if has_b and vis:
			unseen_bld.append(m)
		elif has_b:
			any_bld.append(m)
		elif vis:
			unseen_only.append(m)

	# 5) fallback = origin + every reachable hex
	var fallback : Array[Vector2i] = [ origin_hex ]
	for c3 in cube_list:
		fallback.append(map.cube_to_map(c3))

	# 6) choose the pool in priority order
	var pool : Array[Vector2i]
	if unseen_bld.size() > 0:
		pool = unseen_bld
	elif any_bld.size() > 0:
		pool = any_bld
	elif unseen_only.size() > 0:
		pool = unseen_only
	else:
		pool = fallback

	# — new: filter out any hex that is strictly closer to any enemy —
	var safe_pool: Array[Vector2i] = []
	# gather just the enemy hex coords
	enemy_hexes = []
	for e in known_enemies:
		if is_instance_valid(e):
			enemy_hexes.append(e.current_hex)

	for h in pool:
		var moves_closer := false
		for e_hex in enemy_hexes:
			# if h is closer to this enemy than you already are, it's invalid
			if h.distance_to(e_hex) < origin_hex.distance_to(e_hex):
				moves_closer = true
				break
		if not moves_closer:
			safe_pool.append(h)
	# if nothing left, you have no “away” route → die
	if safe_pool.is_empty() or safe_pool[0] == current_hex:
		#die()
		return origin_hex

	# replace pool with safe options
	pool = safe_pool

	# — now pick from pool as before (e.g. farthest from centroid) —
	var best_hex  = origin_hex
	var best_dist = -1.0
	for h in pool:
		var d = (ground.map_to_local(h) - centroid).length()
		if d > best_dist:
			best_dist = d
			best_hex  = h

	return best_hex
