extends Node2D

@export var firepower: int = 4
@export var range: int = 6
@export var morale: int = 7
@export var has_support_weapon: bool = false

@export var sprite_team_0: Texture2D
@export var sprite_team_1: Texture2D

var current_hex: Vector2i
var selected: bool = false
var moving: bool = false
var target_position: Vector2
var move_speed: float = 200.0
var team: int = 0  # 0 or 1

signal moved_to_hex(new_hex: Vector2i)

@onready var sprite_node: Sprite2D = $Sprite2D

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
