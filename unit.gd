extends Node2D

@export var firepower: int = 4
@export var range: int = 6
@export var morale: int = 7
@export var has_support_weapon: bool = false

@export var morale_meter_max: int = 100
var morale_meter_current: int = 0


@export var base_death_chance: float = 0.1      # 10% base chance
@export var broken_death_multiplier: float = 2.0  # broken units have double the chance

# the “walkable” hexes in offset coords that we’ll follow
var path_hexes: Array[Vector2i] = []
var path_index: int = 0

var alive: bool = true
var broken: bool = false
@export var recovery_time_max: float = 5.0    # seconds needed to rally
var recovery_timer_current: float = 0.0

# track last known cover bonus so we know when we’re “in cover”
var current_cover_bonus: int = 0

@export var sprite_team_0: Texture2D
@export var sprite_team_1: Texture2D

var current_hex: Vector2i
var selected: bool = false
var moving: bool = false
var target_position: Vector2
var move_speed: float = 100.0
var team: int = 0  # 0 or 1
@export var retreat_distance := 3    # how far to run (hexes)
@export var retreat_speed    := 100.0    # px/sec
var retreating: bool = false            
var retreat_target_hex: Vector2i = Vector2i()


signal moved_to_hex(new_hex: Vector2i)
signal unit_died(unit)
signal retreat_complete(retreat_hex: Vector2i) 

@onready var sprite_node: Sprite2D = $Sprite2D
@onready var morale_bar: ColorRect = $MoraleBar
@onready var cover_label = $CoverLabel
@onready var broken_label = $BrokenLabel
@export var TracerScene: PackedScene  # assign to your Tracer.tscn in the inspector
var hexmap: HexagonTileMapLayer  # drag your HexagonTileMapLayer node here

@export var fire_rate: float = 1.5  # seconds between shots
var fire_timer: float = 0.0

func _ready():
	update_team_sprite()
	connect("retreat_complete", _on_retreat_complete)
	
func set_cover(cover_value: int) -> void:
	if cover_value > 0:
		cover_label.text = str(cover_value)
		cover_label.show()
	else:
		cover_label.hide()

func select():
	selected = true
	modulate = Color(0.5, 1, 0.5)

func deselect():
	selected = false
	modulate = Color(1, 1, 1)

func move_to_hex(new_hex: Vector2i, ground_layer: TileMapLayer):
	current_hex = new_hex
	target_position = ground_layer.map_to_local(current_hex)
	emit_signal("moved_to_hex", self, current_hex)  # 🔥 Notify manager!
	moving = true

func follow_cube_path(cube_path: Array[Vector3i]) -> void:
	path_hexes.clear()
	# convert each cube‐coord to the map’s offset coords
	for c in cube_path:
		path_hexes.append( hexmap.cube_to_map(c) )
	# drop the first element (it’s your current hex)
	if path_hexes.size() > 1:
		path_index = 1
		move_to_hex(path_hexes[path_index], hexmap)

func _process(delta):
	if not alive:
		return
		
	if broken:
		_process_recovery(delta)
		
	if moving:
		var dir    = (target_position - position).normalized()
		var dist   = position.distance_to(target_position)
		var step   = move_speed * delta

		if dist <= step:
			position = target_position
			moving  = false

			# advance to next hex in the path, if any
			if path_index < path_hexes.size() - 1:
				path_index += 1
				move_to_hex(path_hexes[path_index], hexmap)
			else:
				# retreat path is done?
				if retreating:
					retreating = false
					emit_signal("retreat_complete", current_hex)
				# done walking
				path_hexes.clear()
				path_index = 0
		else:
			position += dir * step
		return   # skip auto-fire while moving
	
	# Handle firing
	handle_auto_fire(delta)

func handle_auto_fire(delta):
	if moving or not alive or broken:
		return
	
	fire_timer -= delta
	if fire_timer > 0:
		return  # Still waiting for next shot
	
	# Find visible enemies (replace this with your own visibility system!)
	var visible_enemies = get_visible_enemies()
	
	
	
	for enemy in visible_enemies:
		if enemy and enemy.alive:
			var distance = current_hex.distance_to(enemy.current_hex)
			if distance <= range * 2:  # Can fire at double range (half power)
				# safely grab the inner dict for this shooter-hex
				var cover_map = LOSHelper.los_lookup.get(current_hex, null)
				var targetCover 
				if cover_map and cover_map.has(enemy.current_hex):
					var data        = cover_map[enemy.current_hex]
					targetCover = data["target_cover"]
				else:
					targetCover = 0  # no LOS or no cover entry

				# now display it
				enemy.set_cover(targetCover)
				fire_at(enemy, distance, targetCover)
				fire_timer = fire_rate  # Reset timer after firing
				break  # Only fire at one enemy per cycle

func get_visible_enemies() -> Array:
	var manager = get_parent()  # ⚡ Adjust path!
	return manager.unit_visible_enemies.get(self, [])

func set_team(new_team: int):
	team = new_team
	update_team_sprite()

func update_team_sprite():
	if not sprite_node:
		return

	match team:
		0:
			sprite_node.texture = sprite_team_0
		1:
			sprite_node.texture = sprite_team_1

func fire_at(target: Node2D, distance_in_hexes: int, terrain_defense_bonus: float):
	if not alive:
		return
		
	var actual_firepower = firepower
	
	if distance_in_hexes > range:
		if distance_in_hexes <= range * 2:
			actual_firepower = firepower / 2  # Half firepower at extended range
		else:
			return  # Target too far, can't fire
	
	#target.receive_fire(actual_firepower)
	target.receive_fire(actual_firepower, target.moving, terrain_defense_bonus)
	
	# tracer
	#var tracer = TracerScene.instantiate()  # TracerScene = PackedScene of Tracer.tscn
	#tracer.tracer_texture = preload("res://tracer.png")
	#get_tree().current_scene.add_child(tracer)
	#tracer.shoot(global_position, target.global_position, fire_rate)
	fire_burst(self, target, 8, fire_rate)
	#shooter.play_muzzle_flash()
	#shooter.play_shot_sound()

# how many bullets to fire, and bullets per second
func fire_burst(shooter, target, rounds: int, bullets_per_sec: float) -> void:
	var interval = 1.0 / bullets_per_sec
	var tracer_scene = preload("res://Tracer.tscn")

	# compute world positions once
	var from_pos = global_position
	#var to_pos   = target.global_position
	
	for i in range(rounds):
		if not is_instance_valid(shooter) or not is_instance_valid(target):
			return   # stops the whole burst
		var visible_enemies = get_visible_enemies()
		if not visible_enemies.has(target):
			return
		# 1) spawn & shoot one tracer
		var tracer = tracer_scene.instantiate() as Node2D
		tracer.tracer_texture = preload("res://tracer.png")
		get_tree().current_scene.add_child(tracer)
		tracer.shoot(from_pos, target.global_position)

		# 2) wait until it’s time for the next bullet
		await get_tree().create_timer(interval).timeout


func receive_fire(incoming_firepower: int, is_moving: bool, terrain_defense_bonus: float):
	if not alive:
		return
	
	# reset rally progress if already broken
	if broken:
		recovery_timer_current = 0.0
		
	#broken = true
	#broken_label.visible = true
	#recovery_timer_current = 0.0
	#var visible_enemies = get_visible_enemies()
	#_on_morale_failed(visible_enemies)
	
	cover_label.text = str(terrain_defense_bonus)
	
	# 1. Simulate enemy attack roll (2d6 like ASL)
	var attack_roll = randi_range(2, 12)
	
	# 2. Base morale impact
	var morale_impact = incoming_firepower * 8
	
	# 3. Adjust for attack roll quality
	if attack_roll <= 4:
		morale_impact *= 1.5  # Critical low roll = very effective fire
	elif attack_roll >= 10:
		morale_impact *= 0.5  # Bad roll = less stress inflicted
	
	# 5. Adjust for terrain protection
	if (terrain_defense_bonus > 0):
		morale_impact *= (1/(terrain_defense_bonus*2))
	
	# 4. Adjust if moving
	if is_moving:
		morale_impact *= 1.25  # Moving units are easier to hit
	
	# 6. Apply to morale meter
	morale_meter_current += int(morale_impact)
	morale_meter_current = min(morale_meter_current, morale_meter_max)
	
	update_morale_bar()
	
	if morale_meter_current >= morale_meter_max:
		make_morale_check()
	

func make_morale_check():
	# 1) roll for instant death
	var death_chance = base_death_chance
	if broken:
		death_chance *= broken_death_multiplier

	# randf() returns a float in [0,1)
	if randf() < death_chance:
		die()
		return
	
	# Simple morale check: roll 2d6 (simulate), must be <= morale to survive
	var roll = randi_range(2, 12)  # 2 to 12
	if roll > morale:
		#die()
		_on_morale_failed(get_visible_enemies())
		# enter broken state
		broken = true
		broken_label.visible = true
		recovery_timer_current = 0.0
	else:
		# Reset morale meter on successful check
		morale_meter_current = 0

func die():
	alive = false
	emit_signal("unit_died", self)
	

func update_morale_bar():
	if morale_bar:
		var fill_ratio = float(morale_meter_current) / float(morale_meter_max)
		fill_ratio = clamp(fill_ratio, 0.0, 1.0)
		morale_bar.scale.x = fill_ratio  # Shrinks or grows the bar
		if fill_ratio < 0.5:
			morale_bar.color = Color(0, 1, 0)  # Green
		elif fill_ratio < 0.8:
			morale_bar.color = Color(1, 1, 0)  # Yellow
		else:
			morale_bar.color = Color(1, 0, 0)  # Red

func _on_morale_failed(known_enemies: Array) -> void:
	# compute the best hex to run to
	var retreat_map = compute_retreat_hex(current_hex, known_enemies, retreat_distance)
	# set our retreat flags
	retreating = true                           
	retreat_target_hex = retreat_map            
	# then A* from current_hex → retreat_map
	var from_id = hexmap.pathfinding_get_point_id(current_hex)
	var to_id   = hexmap.pathfinding_get_point_id(retreat_map)
	var id_path = hexmap.astar.get_id_path(from_id, to_id)

	# convert to cube path and follow it
	var cube_path : Array[Vector3i] = []
	for pid in id_path:
		var pos = hexmap.astar.get_point_position(pid)
		cube_path.append( hexmap.local_to_cube(pos) )
	follow_cube_path(cube_path)
#
#func _on_morale_failed(known_enemies: Array) -> void:
	#if known_enemies.is_empty():
		##die()
		#return
#
	## 1) build an Array of enemy offset‐coords (Vector2i)
	#var enemy_maps: Array[Vector2i] = []
	#for e in known_enemies:
		#enemy_maps.append(e.current_hex)
#
	## 2) pick a retreat hex N steps away (still Vector2i)
	#var retreat_map : Vector2i = compute_retreat_hex(current_hex, enemy_maps, retreat_distance)
#
	## 3) sanity‐check it’s on the map
	#if hexmap.get_cell_source_id(retreat_map) == -1:
		##die()
		#return
#
	## 4) A* from your current hex → that retreat_map
	#var from_id = hexmap.pathfinding_get_point_id(current_hex)
	#var to_id   = hexmap.pathfinding_get_point_id(retreat_map)
	#var id_path = hexmap.astar.get_id_path(from_id, to_id)
#
	## 5) convert the ID path into cube coords for your walker
	#var cube_path: Array[Vector3i] = []
	#for pid in id_path:
		#var local_pos = hexmap.astar.get_point_position(pid)
		#cube_path.append( hexmap.local_to_cube(local_pos) )
	## 6) follow it
	#follow_cube_path(cube_path)


func _on_retreat_complete(retreat_hex) -> void:
	# clear the moving flag so auto‐fire can resume (or die, etc.)
	moving = false
	#if LOSHelper.is_sample_point_in_building(retreat_hex):
		#current_cover_bonus = LOSHelper.BUILDING_COVER
	# snap your logical hex to the new spot
	current_hex = retreat_hex
	emit_signal("moved_to_hex", self, current_hex)

	# optionally reset morale_meter_current or cover_label here
	# maybe play a "rally" animation, or after retreat die(), etc.
	#die()


func compute_retreat_hex(origin_hex: Vector2i, known_enemies: Array, steps: int) -> Vector2i:
	# shortcuts
	var map    = hexmap                          # HexagonTileMapLayer reference
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
		die()
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


func _process_recovery(delta: float) -> void:
	# can only recover if actually in cover (bonus > 0)
	#if current_cover_bonus <= 0:
		#return

	## exclude walls: check building_layer’s tile name
	#var build_id = LOSHelper.building_layer.get_cell_source_id(current_hex)
	#if build_id != -1:
		#var tile_name = LOSHelper.building_layer.tile_set.tile_get_name(build_id)
		#if tile_name == "Wall":
			#return   # wall gives no recovery

	# accumulate rally time
	recovery_timer_current += delta
	if recovery_timer_current >= recovery_time_max:
		_recover()

func _recover() -> void:
	broken = false
	broken_label.visible = false
	morale_meter_current = 0
	update_morale_bar()
	# Optionally play a “rally” animation or sound here
