extends CanvasLayer


@onready var timer_label = $HBoxContainer/TimerLabel

@onready var ground_sprite = $Node2D/Sprite2D
@onready var wall_sprite = $Node2D/Sprite2D2
@onready var building_sprite = $Node2D/Sprite2D3
@onready var terrain_sprite = $Node2D/Sprite2D4

@onready var coverHBoxContainer = $Node2D/CoverHBoxContainer
@onready var terrainDetail = $Node2D

@onready var cover_icon_scene = preload("res://scenes/ui/cover_icon.tscn")



# Configuration
const TILE_SIZE = Vector2(64, 64)  # Adjust this to your tile size
const HEX_DIRECTIONS = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]

func _on_update_timer_label(time_left_seconds : float):
	var minutes = int(time_left_seconds) / 60
	var seconds = int(time_left_seconds) % 60
	timer_label.text = "Time left: %02d:%02d" % [minutes, seconds]


func mouse_event_position_changed(event_pos: Vector2):
	pass






func show_tile_data(result: Dictionary):
	#print(result)
	result.cover_in_hex
	result.blocking
	result.cover_n
	result.cover_ne
	result.cover_se
	result.cover_s
	result.cover_sw
	result.cover_nw
	result.hindrance
	
	for child in coverHBoxContainer.get_children():
		child.queue_free()
	
	for cover in range(result.cover_in_hex):
		var cover_icon = cover_icon_scene.instantiate()
		coverHBoxContainer.add_child(cover_icon)
		
	
	if not result.ground_texture == null:
		ground_sprite.texture = result.ground_texture
		ground_sprite.transform = result.ground_texture_transform
		ground_sprite.scale = ground_sprite.scale * Vector2(1.5, 1.5)
	else:
		ground_sprite.texture = null
	if not result.wall_texture == null:
		wall_sprite.texture = result.wall_texture
		wall_sprite.transform = result.wall_texture_transform
		wall_sprite.scale = wall_sprite.scale * Vector2(1.5, 1.5)
	else:
		wall_sprite.texture = null
	if not result.building_texture == null:
		building_sprite.texture = result.building_texture
		building_sprite.transform = result.building_texture_transform
		building_sprite.scale = building_sprite.scale * Vector2(1.5, 1.5)
	else:
		building_sprite.texture = null
	if not result.terrain_texture == null:
		terrain_sprite.texture = result.terrain_texture
		terrain_sprite.transform = result.terrain_texture_transform
		terrain_sprite.scale = terrain_sprite.scale * Vector2(1.5, 1.5)
	else:
		terrain_sprite.texture = null
	
