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
var move_speed: float = 200.0
var team: int = 0  # 0 or 1

signal moved_to_hex(new_hex: Vector2i)
signal unit_died(unit)

@onready var sprite_node: Sprite2D = $Sprite2D
@onready var morale_bar: ColorRect = $MoraleBar

@export var fire_rate: float = 1.5  # seconds between shots
var fire_timer: float = 0.0

func _ready():
	update_team_sprite()

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
				fire_at(enemy, distance)
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

func fire_at(target: Node2D, distance_in_hexes: int):
	if not alive:
		return
		
	var actual_firepower = firepower
	
	if distance_in_hexes > range:
		if distance_in_hexes <= range * 2:
			actual_firepower = firepower / 2  # Half firepower at extended range
		else:
			return  # Target too far, can't fire
	
	#target.receive_fire(actual_firepower)
	target.receive_fire(actual_firepower, target.moving, 0.75)

func receive_fire(incoming_firepower: int, is_moving: bool, terrain_defense_bonus: float):
	if not alive:
		return
	
	# 1. Simulate enemy attack roll (2d6 like ASL)
	var attack_roll = randi_range(2, 12)
	
	# 2. Base morale impact
	var morale_impact = incoming_firepower * 8
	
	# 3. Adjust for attack roll quality
	if attack_roll <= 4:
		morale_impact *= 1.5  # Critical low roll = very effective fire
	elif attack_roll >= 10:
		morale_impact *= 0.5  # Bad roll = less stress inflicted
	
	# 4. Adjust if moving
	if is_moving:
		morale_impact *= 1.25  # Moving units are easier to hit
	
	# 5. Adjust for terrain protection (e.g., Woods = 0.75, Open Ground = 1.0)
	morale_impact *= terrain_defense_bonus
	
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
