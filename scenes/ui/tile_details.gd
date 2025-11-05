extends PanelContainer


var ground_layer : HexagonTileMapLayer


@onready var ground_sprite = $FoldableContainer/TileDetails/GroundSprite
@onready var wall_sprite = $FoldableContainer/TileDetails/WallSprite
@onready var building_sprite = $FoldableContainer/TileDetails/BuildingSprite
@onready var terrain_sprite = $FoldableContainer/TileDetails/TerrainSprite

@onready var wall_n_sprite = $FoldableContainer/TileDetails/WallNSprite
@onready var wall_ne_sprite = $FoldableContainer/TileDetails/WallNESprite
@onready var wall_se_sprite = $FoldableContainer/TileDetails/WallSESprite
@onready var wall_s_sprite = $FoldableContainer/TileDetails/WallSSprite
@onready var wall_sw_sprite = $FoldableContainer/TileDetails/WallSWSprite
@onready var wall_nw_sprite = $FoldableContainer/TileDetails/WallNWSprite

@onready var coverHBoxContainer = $FoldableContainer/TileCover/CoverHBoxContainer

@onready var tileDetails = $FoldableContainer/TileDetails


@onready var tile_stats = $FoldableContainer/TileStats


var tile_size : Vector2i 
var detail_zoom_factor : Vector2 = Vector2(2, 2)
var detail_tile_offset : Vector2 
@onready var panel_size_expanded: Vector2 = Vector2.ZERO

	
func set_ground_layer(_ground_layer: HexagonTileMapLayer):
	ground_layer = _ground_layer
	tile_size = ground_layer.tile_set.tile_size
	detail_tile_offset = (Vector2(tile_size) * detail_zoom_factor) * 0.2
	tileDetails.size = Vector2(tile_size) * detail_zoom_factor + detail_tile_offset
	tileDetails.position.y -= tileDetails.size.y + tileDetails.size.x / 10
	tileDetails.position.x += tileDetails.size.x / 5
	$FoldableContainer/TileCover.position.y = tileDetails.position.y + tileDetails.size.y / 2.5
	$FoldableContainer/TileCover.position.x = tileDetails.position.x + tileDetails.size.x / 5
	coverHBoxContainer.scale = detail_zoom_factor * 0.015
	for child in tile_stats.get_children():
		child.scale = detail_zoom_factor * 0.015
	$FoldableContainer/TileStats/Blocked.scale = detail_zoom_factor * 0.02
	$FoldableContainer/TileStats/Hindrance.scale = detail_zoom_factor * 0.02
	$FoldableContainer/TileStats/Blocked.position = tileDetails.position + Vector2(tileDetails.size.x / 2, tileDetails.size.y / 4)
	$FoldableContainer/TileStats/Hindrance.position = tileDetails.position + Vector2(tileDetails.size.x / 2, tileDetails.size.y / 4)
	$FoldableContainer/TileStats/CoverN1.position = tileDetails.position + Vector2(tileDetails.size.x / 2 - tileDetails.size.x / 10, 0)
	$FoldableContainer/TileStats/CoverN2.position = tileDetails.position + Vector2(tileDetails.size.x / 2 + tileDetails.size.x / 10 , 0)
	$FoldableContainer/TileStats/CoverNW1.position = tileDetails.position + Vector2(0, tileDetails.size.y / 4)
	$FoldableContainer/TileStats/CoverNW2.position = tileDetails.position + Vector2(0 + tileDetails.size.x / 7, tileDetails.size.y / 4)
	$FoldableContainer/TileStats/CoverSW1.position = tileDetails.position + Vector2(0, tileDetails.size.y / 4 * 3)
	$FoldableContainer/TileStats/CoverSW2.position = tileDetails.position + Vector2(0 + tileDetails.size.x / 7, tileDetails.size.y / 4 * 3)
	$FoldableContainer/TileStats/CoverS1.position = tileDetails.position + Vector2(tileDetails.size.x / 2 - tileDetails.size.x / 10, tileDetails.size.y)
	$FoldableContainer/TileStats/CoverS2.position = tileDetails.position + Vector2(tileDetails.size.x / 2 + tileDetails.size.x / 10 , tileDetails.size.y)
	$FoldableContainer/TileStats/CoverSE1.position = tileDetails.position + Vector2(tileDetails.size.x / 6 * 5, tileDetails.size.y / 4 * 3)
	$FoldableContainer/TileStats/CoverSE2.position = tileDetails.position + Vector2(tileDetails.size.x / 6 * 5 + tileDetails.size.x / 7, tileDetails.size.y / 4 * 3)
	$FoldableContainer/TileStats/CoverNE1.position = tileDetails.position + Vector2(tileDetails.size.x / 6 * 5, tileDetails.size.y / 4)
	$FoldableContainer/TileStats/CoverNE2.position = tileDetails.position + Vector2(tileDetails.size.x / 6 * 5 + tileDetails.size.x / 7, tileDetails.size.y / 4)
	
	panel_size_expanded = size

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
	
	$FoldableContainer/TileName.text = result.tile_name
	for child in tile_stats.get_children():
		child.visible = false
	
	if result.hindrance == true:
		$FoldableContainer/TileStats/Hindrance.visible = true
	
	if result.blocking == true:
		$FoldableContainer/TileStats/Blocked.visible = true
	
	if result.cover_n == 1:
		$FoldableContainer/TileStats/CoverN1.visible = true
	elif result.cover_n == 2:
		$FoldableContainer/TileStats/CoverN1.visible = true
		$FoldableContainer/TileStats/CoverN2.visible = true
	
	if result.cover_ne == 1:
		$FoldableContainer/TileStats/CoverNE1.visible = true
	elif result.cover_ne == 2:
		$FoldableContainer/TileStats/CoverNE1.visible = true
		$FoldableContainer/TileStats/CoverNE2.visible = true
	
	if result.cover_se == 1:
		$FoldableContainer/TileStats/CoverSE1.visible = true
	elif result.cover_se == 2:
		$FoldableContainer/TileStats/CoverSE1.visible = true
		$FoldableContainer/TileStats/CoverSE2.visible = true
	
	if result.cover_s == 1:
		$FoldableContainer/TileStats/CoverS2.visible = true
	elif result.cover_s == 2:
		$FoldableContainer/TileStats/CoverS1.visible = true
		$FoldableContainer/TileStats/CoverS2.visible = true
	
	if result.cover_sw == 1:
		$FoldableContainer/TileStats/CoverSW2.visible = true
	elif result.cover_sw == 2:
		$FoldableContainer/TileStats/CoverSW1.visible = true
		$FoldableContainer/TileStats/CoverSW2.visible = true
	
	if result.cover_nw == 1:
		$FoldableContainer/TileStats/CoverNW2.visible = true
	elif result.cover_nw == 2:
		$FoldableContainer/TileStats/CoverNW1.visible = true
		$FoldableContainer/TileStats/CoverNW2.visible = true
	
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
	
	for child in tileDetails.get_children():
		child.position += (Vector2(tile_size) * detail_zoom_factor) / 2 + (detail_tile_offset / 2)


func _on_foldable_container_folding_changed(_is_folded: bool) -> void:
	size = Vector2.ZERO
	set_offsets_preset(Control.PRESET_BOTTOM_LEFT)
