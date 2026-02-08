extends Control



@onready var ground_sprite = $GroundSprite
@onready var wall_sprite = $WallSprite
@onready var building_sprite = $BuildingSprite
@onready var terrain_sprite = $TerrainSprite

@onready var wall_n_sprite = $WallNSprite
@onready var wall_ne_sprite = $WallNESprite
@onready var wall_se_sprite = $WallSESprite
@onready var wall_s_sprite = $WallSSprite
@onready var wall_sw_sprite = $WallSWSprite
@onready var wall_nw_sprite = $WallNWSprite


func show_textures(result: Dictionary, detail_zoom_factor: Vector2, tile_size : Vector2i, detail_tile_offset : Vector2):
	
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
		wall_ne_sprite.position.y -= tile_size.y / 2.0 * detail_zoom_factor.y
	else:
		wall_ne_sprite.texture = null
	if not result.wall_se_texture == null:
		wall_se_sprite.texture = result.wall_se_texture
		wall_se_sprite.transform = result.wall_se_texture_transform
		wall_se_sprite.scale = wall_se_sprite.scale * detail_zoom_factor
		wall_se_sprite.position.x += tile_size.x  * detail_zoom_factor.x / 1.5
		wall_se_sprite.position.y += tile_size.y / 2.0 * detail_zoom_factor.y
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
		wall_sw_sprite.position.y += tile_size.y / 2.0 * detail_zoom_factor.y
	else:
		wall_sw_sprite.texture = null
	if not result.wall_nw_texture == null:
		wall_nw_sprite.texture = result.wall_nw_texture
		wall_nw_sprite.transform = result.wall_nw_texture_transform
		wall_nw_sprite.scale = wall_nw_sprite.scale * detail_zoom_factor
		wall_nw_sprite.position.x -= tile_size.x  * detail_zoom_factor.x / 1.5
		wall_nw_sprite.position.y -= tile_size.y / 2.0 * detail_zoom_factor.y
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
		
	for child in get_children():
		child.position += (Vector2(tile_size) * detail_zoom_factor) / 2 + (detail_tile_offset / 2)
