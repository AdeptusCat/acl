class_name AlderbrookCrossingsRiver
extends RefCounted

const DIRECTORY: String = "res://assets/tiles/campaign/crossings/"
const COLUMNS: int = 8
const RADIUS: float = 11.0

var coordinates: AlderbrookRoads = AlderbrookRoads.new()


func layout(roads: Dictionary) -> Dictionary:
	var knots: Array[Vector2] = [coordinates.cell_center(Vector2i(14, -1))]
	for cell: Vector2i in AlderbrookCrossingsLayout.CHANNEL:
		knots.append(coordinates.cell_center(cell))
	knots.append(coordinates.cell_center(Vector2i(14, 20)))
	var curve: Curve2D = Curve2D.new()
	for index: int in range(knots.size()):
		var previous: Vector2 = knots[maxi(0, index - 1)]
		var next: Vector2 = knots[mini(knots.size() - 1, index + 1)]
		var tangent: Vector2 = (next - previous) / 6.0
		curve.add_point(knots[index], -tangent, tangent)
	var polygons: Array[PackedVector2Array] = Geometry2D.offset_polyline(curve.tessellate(8, 0.5), RADIUS, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
	assert(polygons.size() == 1, "The river must remain a single continuous channel")
	var cells: Dictionary[Vector2i, Vector2i] = {}
	var bridges: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in AlderbrookCrossingsLayout.CHANNEL:
		var tile: int = cells.size()
		cells[cell] = Vector2i(tile % COLUMNS, tile / COLUMNS)
		if AlderbrookCrossingsLayout.BRIDGES.has(cell):
			assert(roads["cells"].has(cell), "Each single-hex bridge must join a road")
			bridges[cell] = true
	return {"cells": cells, "bridges": bridges, "curve": curve, "polygon": polygons[0]}


func write_assets(data: Dictionary, roads: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var curve: Curve2D = data["curve"]
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [AlderbrookCrossingsLayout.SIZE.x * 96 + 64, AlderbrookCrossingsLayout.SIZE.y * 128 + 128, AlderbrookCrossingsLayout.SIZE.x * 48 + 32, AlderbrookCrossingsLayout.SIZE.y * 64 + 64]
	var outline: String = ""
	for point: Vector2 in data["polygon"]:
		outline += "%.3f,%.3f " % [point.x, point.y]
	svg += '<polygon points="%s" fill="#477d8c" stroke="#a59d72" stroke-width="5" stroke-linejoin="round"/>' % outline
	var river_path: String = coordinates._svg_path(curve)
	svg += '<path d="%s" fill="none" stroke="#3e7185" stroke-width="10" opacity=".35"/>' % river_path
	for shift: int in [-4, 5]:
		svg += '<path d="%s" transform="translate(%d 0)" fill="none" stroke="#a0c0c0" stroke-width=".9" opacity=".3" stroke-dasharray="24 33 11 57"/>' % [river_path, shift]
	# Roads touching a bank corner remain visible without widening the river hexes.
	for path: String in roads["paths"]:
		svg += '<path d="%s" fill="none" stroke="#8e8b6a" stroke-width="12"/>' % path
		svg += '<path d="%s" fill="none" stroke="#c6b999" stroke-width="9"/>' % path
	var water: Image = Image.new()
	assert(water.load_svg_from_string(svg + "</svg>") == OK)
	var spans: String = svg
	# The approach curves are straight across the water; continuous planks meet them.
	for index: int in range(2):
		var path: String = roads["paths"][index]
		spans += '<path d="%s" fill="none" stroke="#514b3c" stroke-width="23"/>' % path
		spans += '<path d="%s" fill="none" stroke="#b3a281" stroke-width="19"/>' % path
		spans += '<path d="%s" fill="none" stroke="#796e57" stroke-width="18" stroke-dasharray=".8 4"/>' % path
	var bridge: Image = Image.new()
	assert(bridge.load_svg_from_string(spans + "</svg>") == OK)
	var rows: int = ceili(float(data["cells"].size()) / COLUMNS)
	var channel_atlas: Image = Image.create(COLUMNS * 128, rows * 128, false, Image.FORMAT_RGBA8)
	var span_atlas: Image = Image.create(COLUMNS * 128, rows * 128, false, Image.FORMAT_RGBA8)
	var grass: Image = (load("res://assets/tiles/vegetation/open_ground_green_02.png") as Texture2D).get_image()
	grass.convert(Image.FORMAT_RGBA8)
	grass.resize(128, 128)
	_color_grass(grass)
	for cell: Vector2i in data["cells"]:
		var origin: Vector2i = Vector2i(coordinates.cell_center(cell) * 2.0) - Vector2i(64, 64)
		var channel_tile: Image = grass.duplicate() as Image
		channel_tile.blend_rect(water, Rect2i(origin, Vector2i(128, 128)), Vector2i.ZERO)
		var span_tile: Image = grass.duplicate() as Image
		span_tile.blend_rect(bridge, Rect2i(origin, Vector2i(128, 128)), Vector2i.ZERO)
		for y: int in range(128):
			for x: int in range(128):
				if not ConnectedTerrainBaker.inside_hex(Vector2(x + 0.5 - 64, y + 0.5 - 64)):
					channel_tile.set_pixel(x, y, Color.TRANSPARENT)
					span_tile.set_pixel(x, y, Color.TRANSPARENT)
		var atlas: Vector2i = data["cells"][cell]
		channel_atlas.blit_rect(channel_tile, Rect2i(0, 0, 128, 128), atlas * 128)
		span_atlas.blit_rect(span_tile, Rect2i(0, 0, 128, 128), atlas * 128)
	assert(channel_atlas.save_png(DIRECTORY + "channel.png") == OK)
	assert(span_atlas.save_png(DIRECTORY + "spans.png") == OK)
	print("Created connected river artwork: ", data["cells"].size(), " water cells, ", data["bridges"].size(), " bridge cells.")


func _color_grass(image: Image) -> void:
	# Bank pixels share the meadow palette; channel/spans already contain final colors.
	var palette: Dictionary = TerrainPalette.PALETTE.data["families"]["open_ground"]
	var colors: Array[Color] = []
	for html: String in palette["colors"]:
		colors.append(Color(html))
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var original: Color = image.get_pixel(x, y)
			var brightness: float = original.r * 0.2126 + original.g * 0.7152 + original.b * 0.0722
			var color: Color = colors[0]
			for index: int in range(1, colors.size()):
				var first: float = float(palette["levels"][index - 1])
				var last: float = float(palette["levels"][index])
				color = color.lerp(colors[index], clampf((brightness - first) / (last - first), 0.0, 1.0))
			color.a = original.a
			image.set_pixel(x, y, color)


func tile_set(data: Dictionary) -> TileSet:
	var tiles: TileSet = TileSet.new()
	tiles.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	tiles.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	tiles.tile_size = Vector2i(128, 128)
	for kind: int in range(2):
		var source: TileSetAtlasSource = TileSetAtlasSource.new()
		var image: String = "channel.png"
		if kind == 1:
			image = "spans.png"
		source.texture = load(DIRECTORY + image) as Texture2D
		assert(source.texture != null, "Generate and import the connected river atlases first")
		source.texture_region_size = Vector2i(128, 128)
		for cell: Vector2i in data["cells"]:
			source.create_tile(data["cells"][cell])
		tiles.add_source(source, kind)
	return tiles
