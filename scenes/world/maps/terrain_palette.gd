class_name TerrainPalette
extends RefCounted

const CAMPAIGN: String = "Road to Alderbrook"
const PALETTE_PATH: String = "res://assets/palettes/terrain_palettes.json"
const PALETTE: JSON = preload(PALETTE_PATH)
const SHADER: Shader = preload("res://assets/shader/terrain_palette.gdshader")

static var _materials: Dictionary[String, ShaderMaterial] = {}
static var _palettes: Dictionary = {}


static func apply(layer: TileMapLayer) -> void:
	if layer.tile_set == null or layer.get_used_cells().is_empty():
		return
	# Some campaign sources are shared with base maps. Clone the used sources
	# before assigning materials, keeping source textures and metadata intact.
	var original: TileSet = layer.tile_set
	var copy: TileSet = original.duplicate() as TileSet
	var sources: Dictionary[int, bool] = {}
	for cell: Vector2i in layer.get_used_cells():
		var source_id: int = layer.get_cell_source_id(cell)
		if sources.has(source_id):
			continue
		sources[source_id] = true
		var original_source: TileSetAtlasSource = original.get_source(source_id) as TileSetAtlasSource
		var source: TileSetAtlasSource = original_source.duplicate(true) as TileSetAtlasSource
		source.texture = original_source.texture
		copy.remove_source(source_id)
		copy.add_source(source, source_id)
	layer.tile_set = copy
	var visited: Dictionary[TileData, bool] = {}
	for cell: Vector2i in layer.get_used_cells():
		var data: TileData = layer.get_cell_tile_data(cell)
		if data == null or visited.has(data):
			continue
		visited[data] = true
		var source: TileSetAtlasSource = copy.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
		var family: String = family_for_tile(layer.name, data, source.texture.resource_path)
		if not family.is_empty():
			data.material = material_for_family(family, layer.get_viewport().use_hdr_2d)


static func family_for_tile(layer_name: StringName, data: TileData, texture_path: String = "") -> String:
	if layer_name == &"GroundTileMapLayer":
		return "open_ground"
	if data.has_custom_data("art_family"):
		var family: String = str(data.get_custom_data("art_family"))
		if family == "crops":
			return "green_crops"
		if family in ["woods", "orchard", "wheat"]:
			return family
	if "bridge" in texture_path:
		return "bridge"
	if "river" in texture_path:
		return "water"
	if "road" in texture_path and not "connected/maps" in texture_path:
		return "roads"
	if "stubble" in texture_path:
		return "stubble"
	if "ploughed" in texture_path:
		return "ploughed"
	if "green_rows" in texture_path:
		return "green_crops"
	if "wheat" in texture_path:
		return "wheat"
	if data.has_custom_data("name"):
		var label: String = str(data.get_custom_data("name"))
		match label:
			"Woods":
				return "woods"
			"Orchard":
				return "orchard"
			"Road":
				return "roads"
			"Stone Building", "Wall":
				return "stone"
			"Wood Building", "Wooden Building":
				return "timber"
			"Hedge":
				return "hedges"
	return ""


static func material_for_family(family: String, hdr_2d: bool = true) -> ShaderMaterial:
	var key: String = family + "/" + str(hdr_2d)
	if _materials.has(key):
		return _materials[key]
	if _palettes.is_empty():
		_palettes = PALETTE.data["families"]
	var primary: String = family
	if family == "bridge":
		primary = "timber"
	var palette: Dictionary = _palettes[primary]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.resource_name = "Alderbrook palette - " + family
	material.shader = SHADER
	_set_ramp(material, "", palette)
	for secondary: String in ["timber", "clay_roofs", "slate_roofs", "water", "ploughed"]:
		var parameter: String = secondary
		if secondary == "clay_roofs":
			parameter = "clay"
		elif secondary == "slate_roofs":
			parameter = "slate"
		elif secondary == "ploughed":
			parameter = "soil"
		_set_ramp(material, parameter + "_", _palettes[secondary])
	material.set_shader_parameter("fruit_palette", _colors(_palettes["fruit_blossom"]))
	material.set_shader_parameter("grid_ink", _colors(_palettes["grid_fog"])[0])
	var kind: int = int(palette["mode"])
	if family == "bridge":
		kind = 7
	material.set_shader_parameter("material_kind", kind)
	material.set_shader_parameter("hdr_2d", hdr_2d)
	# RD samples linear textures in HDR; Compatibility still samples sRGB.
	material.set_shader_parameter("texture_is_linear", hdr_2d and RenderingServer.get_rendering_device() != null)
	_materials[key] = material
	return material


static func _set_ramp(material: ShaderMaterial, prefix: String, palette: Dictionary) -> void:
	material.set_shader_parameter(prefix + "palette", _colors(palette))
	material.set_shader_parameter(prefix + "levels", PackedFloat32Array(palette["levels"]))


static func _colors(palette: Dictionary) -> PackedVector4Array:
	var colors: PackedVector4Array = PackedVector4Array()
	for value: String in palette["colors"]:
		var color: Color = Color(value)
		colors.append(Vector4(color.r, color.g, color.b, color.a))
	return colors
