extends CanvasLayer

@export var ground_layer : HexagonTileMapLayer
@export var unit_stats_details_scene : PackedScene

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

@onready var tile_stats = $TileStats
@onready var unit_stats = $UnitStats
@onready var unit_stats_container = $UnitStats/UnitStatsContainer

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
	terrainDetail.position.y -= terrainDetail.size.y + terrainDetail.size.x / 10
	terrainDetail.position.x += terrainDetail.size.x / 5
	$Control.position.y = terrainDetail.position.y + terrainDetail.size.y / 2.5
	$Control.position.x = terrainDetail.position.x + terrainDetail.size.x / 5
	coverHBoxContainer.scale = detail_zoom_factor * 0.015
	for child in tile_stats.get_children():
		child.scale = detail_zoom_factor * 0.015
	$TileStats/Blocked.scale = detail_zoom_factor * 0.02
	$TileStats/Hindrance.scale = detail_zoom_factor * 0.02
	$TileStats/Blocked.position = terrainDetail.position + Vector2(terrainDetail.size.x / 2, terrainDetail.size.y / 4)
	$TileStats/Hindrance.position = terrainDetail.position + Vector2(terrainDetail.size.x / 2, terrainDetail.size.y / 4)
	$TileStats/CoverN1.position = terrainDetail.position + Vector2(terrainDetail.size.x / 2 - terrainDetail.size.x / 10, 0)
	$TileStats/CoverN2.position = terrainDetail.position + Vector2(terrainDetail.size.x / 2 + terrainDetail.size.x / 10 , 0)
	$TileStats/CoverNW1.position = terrainDetail.position + Vector2(0, terrainDetail.size.y / 4)
	$TileStats/CoverNW2.position = terrainDetail.position + Vector2(0 + terrainDetail.size.x / 7, terrainDetail.size.y / 4)
	$TileStats/CoverSW1.position = terrainDetail.position + Vector2(0, terrainDetail.size.y / 4 * 3)
	$TileStats/CoverSW2.position = terrainDetail.position + Vector2(0 + terrainDetail.size.x / 7, terrainDetail.size.y / 4 * 3)
	$TileStats/CoverS1.position = terrainDetail.position + Vector2(terrainDetail.size.x / 2 - terrainDetail.size.x / 10, terrainDetail.size.y)
	$TileStats/CoverS2.position = terrainDetail.position + Vector2(terrainDetail.size.x / 2 + terrainDetail.size.x / 10 , terrainDetail.size.y)
	$TileStats/CoverSE1.position = terrainDetail.position + Vector2(terrainDetail.size.x / 6 * 5, terrainDetail.size.y / 4 * 3)
	$TileStats/CoverSE2.position = terrainDetail.position + Vector2(terrainDetail.size.x / 6 * 5 + terrainDetail.size.x / 7, terrainDetail.size.y / 4 * 3)
	$TileStats/CoverNE1.position = terrainDetail.position + Vector2(terrainDetail.size.x / 6 * 5, terrainDetail.size.y / 4)
	$TileStats/CoverNE2.position = terrainDetail.position + Vector2(terrainDetail.size.x / 6 * 5 + terrainDetail.size.x / 7, terrainDetail.size.y / 4)


func _on_update_timer_label(time_left_seconds : float):
	var minutes = int(time_left_seconds) / 60
	var seconds = int(time_left_seconds) % 60
	timer_label.text = "Time left: %02d:%02d" % [minutes, seconds]


func mouse_event_position_changed(event_pos: Vector2):
	pass


func show_unit_data(map_hex: Vector2i, units: Array):
	for child in unit_stats_container.get_children():
		child.queue_free()
	for unit in units:
		var unit_ui = unit.ui.duplicate()
		unit_stats_container.add_child(unit_ui)
		var unit_stats_details = unit_stats_details_scene.instantiate()
		unit_stats_details.set_details(unit)
		unit_stats_container.add_child(unit_stats_details)
		

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
	
	for child in tile_stats.get_children():
		child.visible = false
	
	if result.hindrance == true:
		$TileStats/Hindrance.visible = true
	
	if result.blocking == true:
		$TileStats/Blocked.visible = true
	
	if result.cover_n == 1:
		$TileStats/CoverN1.visible = true
	elif result.cover_n == 2:
		$TileStats/CoverN1.visible = true
		$TileStats/CoverN2.visible = true
	
	if result.cover_ne == 1:
		$TileStats/CoverNE1.visible = true
	elif result.cover_ne == 2:
		$TileStats/CoverNE1.visible = true
		$TileStats/CoverNE2.visible = true
	
	if result.cover_se == 1:
		$TileStats/CoverSE1.visible = true
	elif result.cover_se == 2:
		$TileStats/CoverSE1.visible = true
		$TileStats/CoverSE2.visible = true
	
	if result.cover_s == 1:
		$TileStats/CoverS2.visible = true
	elif result.cover_s == 2:
		$TileStats/CoverS1.visible = true
		$TileStats/CoverS2.visible = true
	
	if result.cover_sw == 1:
		$TileStats/CoverSW2.visible = true
	elif result.cover_sw == 2:
		$TileStats/CoverSW1.visible = true
		$TileStats/CoverSW2.visible = true
	
	if result.cover_nw == 1:
		$TileStats/CoverNW2.visible = true
	elif result.cover_nw == 2:
		$TileStats/CoverNW1.visible = true
		$TileStats/CoverNW2.visible = true
	
	for child in coverHBoxContainer.get_children():
		child.visible = false
	
	for cover in range(result.cover_in_hex):
		coverHBoxContainer.get_children()[cover].visible = true
		
	
	
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
