extends CanvasLayer

@export var ground_layer : HexagonTileMapLayer
@export var unit_stats_details_scene : PackedScene

@onready var timer_label = $Control/HBoxContainer/TimerLabel

@onready var ground_sprite = $Control/Node2D/GroundSprite
@onready var wall_sprite = $Control/Node2D/WallSprite
@onready var building_sprite = $Control/Node2D/BuildingSprite
@onready var terrain_sprite = $Control/Node2D/TerrainSprite

@onready var wall_n_sprite = $Control/Node2D/WallNSprite
@onready var wall_ne_sprite = $Control/Node2D/WallNESprite
@onready var wall_se_sprite = $Control/Node2D/WallSESprite
@onready var wall_s_sprite = $Control/Node2D/WallSSprite
@onready var wall_sw_sprite = $Control/Node2D/WallSWSprite
@onready var wall_nw_sprite = $Control/Node2D/WallNWSprite

@onready var coverHBoxContainer = $Control/Control/CoverHBoxContainer

@onready var terrainDetail = $Control/Node2D

@onready var cover_icon_scene = preload("res://scenes/ui/cover_icon.tscn")

@onready var tile_stats = $Control/TileStats
@onready var unit_stats = $Control/UnitStats
@onready var unit_stats_container = $Control/UnitStats/MarginContainer/VBoxContainer/UnitStatsContainer

@onready var target_cover_distance = $Control/TargetCoverDistance
@onready var cover_container = $Control/TargetCoverDistance/VBoxContainer/Cover
@onready var firepower_label = $Control/TargetCoverDistance/VBoxContainer/HBoxContainer/FirepowerLabel
@onready var distance_label = $Control/TargetCoverDistance/VBoxContainer/HBoxContainer2/DistanceLabel

@onready var unit_details = $Control/UnitDetails

signal try_again

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
	$Control/Control.position.y = terrainDetail.position.y + terrainDetail.size.y / 2.5
	$Control/Control.position.x = terrainDetail.position.x + terrainDetail.size.x / 5
	coverHBoxContainer.scale = detail_zoom_factor * 0.015
	for child in tile_stats.get_children():
		child.scale = detail_zoom_factor * 0.015
	$Control/TileStats/Blocked.scale = detail_zoom_factor * 0.02
	$Control/TileStats/Hindrance.scale = detail_zoom_factor * 0.02
	$Control/TileStats/Blocked.position = terrainDetail.position + Vector2(terrainDetail.size.x / 2, terrainDetail.size.y / 4)
	$Control/TileStats/Hindrance.position = terrainDetail.position + Vector2(terrainDetail.size.x / 2, terrainDetail.size.y / 4)
	$Control/TileStats/CoverN1.position = terrainDetail.position + Vector2(terrainDetail.size.x / 2 - terrainDetail.size.x / 10, 0)
	$Control/TileStats/CoverN2.position = terrainDetail.position + Vector2(terrainDetail.size.x / 2 + terrainDetail.size.x / 10 , 0)
	$Control/TileStats/CoverNW1.position = terrainDetail.position + Vector2(0, terrainDetail.size.y / 4)
	$Control/TileStats/CoverNW2.position = terrainDetail.position + Vector2(0 + terrainDetail.size.x / 7, terrainDetail.size.y / 4)
	$Control/TileStats/CoverSW1.position = terrainDetail.position + Vector2(0, terrainDetail.size.y / 4 * 3)
	$Control/TileStats/CoverSW2.position = terrainDetail.position + Vector2(0 + terrainDetail.size.x / 7, terrainDetail.size.y / 4 * 3)
	$Control/TileStats/CoverS1.position = terrainDetail.position + Vector2(terrainDetail.size.x / 2 - terrainDetail.size.x / 10, terrainDetail.size.y)
	$Control/TileStats/CoverS2.position = terrainDetail.position + Vector2(terrainDetail.size.x / 2 + terrainDetail.size.x / 10 , terrainDetail.size.y)
	$Control/TileStats/CoverSE1.position = terrainDetail.position + Vector2(terrainDetail.size.x / 6 * 5, terrainDetail.size.y / 4 * 3)
	$Control/TileStats/CoverSE2.position = terrainDetail.position + Vector2(terrainDetail.size.x / 6 * 5 + terrainDetail.size.x / 7, terrainDetail.size.y / 4 * 3)
	$Control/TileStats/CoverNE1.position = terrainDetail.position + Vector2(terrainDetail.size.x / 6 * 5, terrainDetail.size.y / 4)
	$Control/TileStats/CoverNE2.position = terrainDetail.position + Vector2(terrainDetail.size.x / 6 * 5 + terrainDetail.size.x / 7, terrainDetail.size.y / 4)
	#var db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	##var db = -2
	#var ratio = pow(10.0, db / 20.0)
	#$Control/Settings/FoldableContainer/VBoxContainer/VolumeSlider.value = ratio
	#$Control/Settings/FoldableContainer/VBoxContainer/VolumeSlider2.value = ratio
	
	unit_details.hide()




func show_target_hex_cover_distance(local_event_pos, targetCover, distance, firepower):
	target_cover_distance.show()
	target_cover_distance.position = local_event_pos
	for child in cover_container.get_children():
		child.queue_free()
	for cover in targetCover:
		var cover_icon: TextureRect = cover_icon_scene.instantiate()
		cover_icon.expand_mode = TextureRect.ExpandMode.EXPAND_FIT_WIDTH_PROPORTIONAL
		cover_container.add_child(cover_icon)
	firepower_label.text = str(firepower)
	distance_label.text = str(distance)
	#if detail_ui:
		#detail_ui.set_cover(targetCover)


func hide_target_hex_cover_distance():
	target_cover_distance.hide()


func _on_update_timer_label(time_left_seconds : float):
	$Control/HBoxContainer.visible = true
	var minutes = int(time_left_seconds) / 60
	var seconds = int(time_left_seconds) % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]


func mouse_event_position_changed(event_pos: Vector2):
	pass


func show_unit_data(map_hex: Vector2i, units: Array):
	unit_stats.visible = true
	var unit_detail_counter: int = 0
	for child in unit_stats_container.get_children():
		if "detail_ui" in child:
			child.detail_ui = null
		child.queue_free()
	for unit in units:
		if not LOSHelper.visible_hexes[Globals.team_player].has(unit.current_hex):
			continue
		#var unit_ui = unit.ui.duplicate(Node.DuplicateFlags.DUPLICATE_SIGNALS | Node.DuplicateFlags.DUPLICATE_GROUPS | Node.DuplicateFlags.DUPLICATE_SCRIPTS)
		#unit_stats_container.add_child(unit_ui)
		#var unit_detail_container = unit_ui.soldiers_detail_container.duplicate()
		#unit_stats_container.add_child(unit_detail_container)
		#var unit_stats_details = unit_stats_details_scene.instantiate()
		#unit_stats_details.set_details(unit)
		#unit_stats_container.add_child(unit_stats_details)
		
		#unit.ui.detail_ui = unit_ui
		#unit_ui._set_loadout(unit.squad_fire.soldiers)
		#unit_detail_counter += 1
	if unit_detail_counter == 0:
		unit_stats.visible = false


func _on_show_unit_details(unit: Unit):
	unit_details.show_unit_detail(unit)


func _on_hide_unit_details():
	unit_details.hide_unit_detail()

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
	result.tile_name
	
	$Control/Label.text = result.tile_name
	for child in tile_stats.get_children():
		child.visible = false
	
	if result.hindrance == true:
		$Control/TileStats/Hindrance.visible = true
	
	if result.blocking == true:
		$Control/TileStats/Blocked.visible = true
	
	if result.cover_n == 1:
		$Control/TileStats/CoverN1.visible = true
	elif result.cover_n == 2:
		$Control/TileStats/CoverN1.visible = true
		$Control/TileStats/CoverN2.visible = true
	
	if result.cover_ne == 1:
		$Control/TileStats/CoverNE1.visible = true
	elif result.cover_ne == 2:
		$Control/TileStats/CoverNE1.visible = true
		$Control/TileStats/CoverNE2.visible = true
	
	if result.cover_se == 1:
		$Control/TileStats/CoverSE1.visible = true
	elif result.cover_se == 2:
		$Control/TileStats/CoverSE1.visible = true
		$Control/TileStats/CoverSE2.visible = true
	
	if result.cover_s == 1:
		$Control/TileStats/CoverS2.visible = true
	elif result.cover_s == 2:
		$Control/TileStats/CoverS1.visible = true
		$Control/TileStats/CoverS2.visible = true
	
	if result.cover_sw == 1:
		$Control/TileStats/CoverSW2.visible = true
	elif result.cover_sw == 2:
		$Control/TileStats/CoverSW1.visible = true
		$Control/TileStats/CoverSW2.visible = true
	
	if result.cover_nw == 1:
		$Control/TileStats/CoverNW2.visible = true
	elif result.cover_nw == 2:
		$Control/TileStats/CoverNW1.visible = true
		$Control/TileStats/CoverNW2.visible = true
	
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


func _on_try_again_button_pressed() -> void:
	try_again.emit()


func _db_to_ratio(db: float) -> float:
	# Convert dB (-80..0) to 0–1 range for slider
	return pow(10.0, db / 20.0)

func _ratio_to_db(ratio: float) -> float:
	# Convert slider ratio (0–1) back to dB
	var db: float
	if ratio <= 0.0001:
		db = -80.0
	else:
		db = 20.0 * log(ratio)
	return db
