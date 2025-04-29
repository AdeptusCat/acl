extends Node2D

@export var firepower: int = 4
@export var range: int = 6
@export var morale: int = 7
@export var has_support_weapon: bool = false

@export var morale_meter_max: int = 100
var morale_meter_current: int = 0

var alive: bool = true

@export var sprite_team_0: Texture2D
@export var sprite_team_1: Texture2D

var current_hex: Vector2i
var selected: bool = false
var moving: bool = false
var target_position: Vector2
var move_speed: float = 100.0
var team: int = 0  # 0 or 1

signal moved_to_hex(new_hex: Vector2i)
signal unit_died(unit)

@onready var sprite_node: Sprite2D = $Sprite2D
@onready var morale_bar: ColorRect = $MoraleBar
@onready var cover_label = $CoverLabel
@export var TracerScene: PackedScene  # assign to your Tracer.tscn in the inspector

@export var fire_rate: float = 1.5  # seconds between shots
var fire_timer: float = 0.0

func _ready():
	update_team_sprite()
	
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

func _process(delta):
	if moving:
		var direction = (target_position - position).normalized()
		var distance_to_target = position.distance_to(target_position)
		var step = move_speed * delta

		if distance_to_target <= step:
			position = target_position
			moving = false
			
		else:
			position += direction * step
	
	# Handle firing
	handle_auto_fire(delta)

func handle_auto_fire(delta):
	if moving or not alive:
		return  # Can't fire while moving or dead
	
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
	var to_pos   = target.global_position

	for i in range(rounds):
		if not is_instance_valid(shooter) or not is_instance_valid(target):
			return   # stops the whole burst
		# 1) spawn & shoot one tracer
		var tracer = tracer_scene.instantiate() as Node2D
		tracer.tracer_texture = preload("res://tracer.png")
		get_tree().current_scene.add_child(tracer)
		tracer.shoot(from_pos, to_pos)

		# 2) wait until it’s time for the next bullet
		await get_tree().create_timer(interval).timeout

func receive_fire(incoming_firepower: int, is_moving: bool, terrain_defense_bonus: float):
	if not alive:
		return
	
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
	# Simple morale check: roll 2d6 (simulate), must be <= morale to survive
	var roll = randi_range(2, 12)  # 2 to 12
	if roll > morale:
		die()
	else:
		# Reset morale meter on successful check
		morale_meter_current = 0

func die():
	alive = false
	emit_signal("unit_died", self)
	queue_free()

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
