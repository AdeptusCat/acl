extends CanvasLayer


@onready var timer_label = $HBoxContainer/TimerLabel
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
	print(result)
	result.cover_in_hex
	result.blocking
	result.cover_n
	result.cover_ne
	result.cover_se
	result.cover_s
	result.cover_sw
	result.cover_nw
	result.hindrance
	
	if not result.ground_texture == null:
		$Sprite2D.texture = result.ground_texture
		$Sprite2D.transform = result.ground_texture_transform
		$Sprite2D.position = Vector2(128,128)
		$Sprite2D.scale = Vector2(1.5, 1.5)
	else:
		$Sprite2D.texture = null
	if not result.wall_texture == null:
		$Sprite2D2.texture = result.wall_texture
		$Sprite2D2.transform = result.wall_texture_transform
		$Sprite2D2.position = Vector2(128,128)
		$Sprite2D2.scale = Vector2(1.5, 1.5)
	else:
		$Sprite2D2.texture = null
	if not result.building_texture == null:
		$Sprite2D3.texture = result.building_texture
		$Sprite2D3.transform = result.building_texture_transform
		$Sprite2D3.position = Vector2(128,128)
		$Sprite2D3.scale = Vector2(1.5, 1.5)
	else:
		$Sprite2D3.texture = null
	if not result.terrain_texture == null:
		$Sprite2D4.texture = result.terrain_texture
		$Sprite2D4.transform = result.terrain_texture_transform
		$Sprite2D4.position = Vector2(128,128)
		$Sprite2D4.scale = Vector2(1.5, 1.5)
	else:
		$Sprite2D4.texture = null
