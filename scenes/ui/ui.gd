extends CanvasLayer

@export var ground_layer : HexagonTileMapLayer

@onready var timer_label = $HBoxContainer/TimerLabel

@onready var ground_sprite = $Node2D/GroundSprite
@onready var wall_sprite = $Node2D/WallSprite
@onready var building_sprite = $Node2D/BuildingSprite
@onready var terrain_sprite = $Node2D/TerrainSprite

@onready var wall_n_sprite = $Node2D/WallNSprite
@onready var wall_ne_sprite = $Node2D/WallNESprite
@onready var wall_se_sprite = $Node2D/WallSESprite
@onready var wall_s_sprite = $Node2D/WallSSprite
@onready var wall_sw_sprite = $Node2D/WallSWSprite
@onready var wall_nw_sprite = $Node2D/WallNWSprite

@onready var coverHBoxContainer = $Control/CoverHBoxContainer

@onready var terrainDetail = $Node2D

@onready var cover_icon_scene = preload("res://scenes/ui/cover_icon.tscn")



# Configuration
const HEX_DIRECTIONS = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]


var tile_size : Vector2i 
var detail_zoom_factor : Vector2 = Vector2(2, 2)
var detail_tile_offset : Vector2 

func _ready() -> void:
	tile_size = ground_layer.tile_set.tile_size
	detail_tile_offset = (Vector2(tile_size) * detail_zoom_factor) * 0.2
	terrainDetail.size = Vector2(tile_size) * detail_zoom_factor + detail_tile_offset
	terrainDetail.position.y -= terrainDetail.size.y
	$Control.position.y = terrainDetail.position.y + terrainDetail.size.y / 2.5
	$Control.position.x = terrainDetail.position.x + terrainDetail.size.x / 5
	coverHBoxContainer.scale = detail_zoom_factor * 0.015


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
		ground_sprite.scale = ground_sprite.scale * detail_zoom_factor
	else:
		ground_sprite.texture = null
	if not result.wall_texture == null:
		wall_sprite.texture = result.wall_texture
		wall_sprite.transform = result.wall_texture_transform
		wall_sprite.scale = wall_sprite.scale * detail_zoom_factor
	else:
		wall_sprite.texture = null
	if not result.wall_n_texture == null:
		wall_n_sprite.texture = result.wall_n_texture
		wall_n_sprite.transform = result.wall_n_texture_transform
		wall_n_sprite.scale = wall_n_sprite.scale * detail_zoom_factor
		wall_n_sprite.position.y -= tile_size.y * detail_zoom_factor.y
	else:
		wall_n_sprite.texture = null
	if not result.wall_ne_texture == null:
		wall_ne_sprite.texture = result.wall_ne_texture
		wall_ne_sprite.transform = result.wall_ne_texture_transform
		wall_ne_sprite.scale = wall_ne_sprite.scale * detail_zoom_factor
		wall_ne_sprite.position.x += tile_size.x * detail_zoom_factor.x / 1.5
		wall_ne_sprite.position.y -= tile_size.y / 2 * detail_zoom_factor.y
	else:
		wall_ne_sprite.texture = null
	if not result.wall_se_texture == null:
		wall_se_sprite.texture = result.wall_se_texture
		wall_se_sprite.transform = result.wall_se_texture_transform
		wall_se_sprite.scale = wall_se_sprite.scale * detail_zoom_factor
		wall_se_sprite.position.x += tile_size.x  * detail_zoom_factor.x / 1.5
		wall_se_sprite.position.y += tile_size.y / 2 * detail_zoom_factor.y
	else:
		wall_se_sprite.texture = null
	if not result.wall_s_texture == null:
		wall_s_sprite.texture = result.wall_s_texture
		wall_s_sprite.transform = result.wall_s_texture_transform
		wall_s_sprite.scale = wall_s_sprite.scale * detail_zoom_factor
		wall_s_sprite.position.y += tile_size.y * detail_zoom_factor.y
	else:
		wall_s_sprite.texture = null
	if not result.wall_sw_texture == null:
		wall_sw_sprite.texture = result.wall_sw_texture
		wall_sw_sprite.transform = result.wall_sw_texture_transform
		wall_sw_sprite.scale = wall_sw_sprite.scale * detail_zoom_factor
		wall_sw_sprite.position.x -= tile_size.x  * detail_zoom_factor.x / 1.5
		wall_sw_sprite.position.y += tile_size.y / 2 * detail_zoom_factor.y
	else:
		wall_sw_sprite.texture = null
	if not result.wall_nw_texture == null:
		wall_nw_sprite.texture = result.wall_nw_texture
		wall_nw_sprite.transform = result.wall_nw_texture_transform
		wall_nw_sprite.scale = wall_nw_sprite.scale * detail_zoom_factor
		wall_nw_sprite.position.x -= tile_size.x  * detail_zoom_factor.x / 1.5
		wall_nw_sprite.position.y -= tile_size.y / 2 * detail_zoom_factor.y
	else:
		wall_nw_sprite.texture = null
	if not result.building_texture == null:
		building_sprite.texture = result.building_texture
		building_sprite.transform = result.building_texture_transform
		building_sprite.scale = building_sprite.scale * detail_zoom_factor
	else:
		building_sprite.texture = null
	if not result.terrain_texture == null:
		terrain_sprite.texture = result.terrain_texture
		terrain_sprite.transform = result.terrain_texture_transform
		terrain_sprite.scale = terrain_sprite.scale * detail_zoom_factor
	else:
		terrain_sprite.texture = null
	
	for child in terrainDetail.get_children():
		child.position += (Vector2(tile_size) * detail_zoom_factor) / 2 + (detail_tile_offset / 2)
