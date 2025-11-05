extends PanelContainer


var ground_layer : HexagonTileMapLayer



@onready var coverHBoxContainer = $FoldableContainer/VBoxContainer/HBoxContainer/TileCover/CoverHBoxContainer

@onready var tile_textures = $FoldableContainer/VBoxContainer/Tile/TileTextures


@onready var tile_stats = $FoldableContainer/VBoxContainer/Tile/TileStats


var tile_size : Vector2i 
var detail_zoom_factor : Vector2 = Vector2(2, 2)
var detail_tile_offset : Vector2 
@onready var panel_size_expanded: Vector2 = Vector2.ZERO

	
func set_ground_layer(_ground_layer: HexagonTileMapLayer):
	ground_layer = _ground_layer
	tile_size = ground_layer.tile_set.tile_size
	detail_tile_offset = (Vector2(tile_size) * detail_zoom_factor) * 0.2
	tile_textures.size = Vector2(tile_size) * detail_zoom_factor + detail_tile_offset
	#tileDetails.position.y -= tileDetails.size.y + tileDetails.size.x / 10
	#tileDetails.position.x += tileDetails.size.x / 5
	#$FoldableContainer/TileCover.position.y = tileDetails.position.y + tileDetails.size.y / 2.5
	#$FoldableContainer/TileCover.position.x = tileDetails.position.x + tileDetails.size.x / 5
	coverHBoxContainer.scale = detail_zoom_factor * 0.015
	for child in tile_stats.get_children():
		child.scale = detail_zoom_factor * 0.015
	var offset: Vector2 = (Vector2(tile_size) * detail_zoom_factor / 2) + (detail_tile_offset / 2)
	tile_stats.set_offset_position(offset, Vector2.ZERO, detail_zoom_factor)
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
	
	$FoldableContainer/VBoxContainer/TileName.text = result.tile_name
	
	tile_stats.show_stats(result)
	
	
	for child in coverHBoxContainer.get_children():
		child.visible = false
	
	for cover in range(result.cover_in_hex):
		coverHBoxContainer.get_children()[cover].visible = true
		
	
	tile_textures.show_textures(result, detail_zoom_factor, tile_size, detail_tile_offset)
	


func _on_foldable_container_folding_changed(_is_folded: bool) -> void:
	size = Vector2.ZERO
	set_offsets_preset(Control.PRESET_BOTTOM_LEFT)
