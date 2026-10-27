class_name AlderbrookRoads
extends RefCounted

const ASSET_DIRECTORY: String = "res://assets/tiles/campaign/roads/"
const PREVIEW_DIRECTORY: String = "res://docs/art/roads/rasters/"
const ATLAS_COLUMNS: int = 8
const VERGE_RADIUS: float = 7.0
const HEX: Array[Vector2] = [
	Vector2(-16, -32), Vector2(16, -32), Vector2(32, 0),
	Vector2(16, 32), Vector2(-16, 32), Vector2(-32, 0),
]
# Knots are (column, continuous row, slope). Unequal distances and tangents
# follow the farms and river crossings rather than the staggered hex centers.
const ROUTES: Array[Array] = [
	[
		[Vector3(-1, 6.0, 0), Vector3(3.5, 5.8, -0.12), Vector3(7, 4.9, -0.08), Vector3(10, 5.1, 0.18), Vector3(16, 5.8, 0)],
	],
	AlderbrookOrchardLayout.ROUTES,
	[
		[Vector3(-1, 7.5, 0), Vector3(4.5, 7.3, -0.2), Vector3(7.5, 6, -0.08), Vector3(12.5, 6.1, 0.1), Vector3(20, 7, 0)],
	],
	AlderbrookCrossingsLayout.ROUTES,
	AlderbrookVillageLayout.ROUTES,
]


func layout(index: int, size: Vector2i) -> Dictionary:
	return layout_for_routes(ROUTES[index], size)


func layout_for_routes(routes: Array, size: Vector2i) -> Dictionary:
	var curves: Array[Curve2D] = []
	var verges: Array[PackedVector2Array] = []
	var paths: Array[String] = []
	for knots: Array in routes:
		var curve: Curve2D = _curve(knots)
		curves.append(curve)
		paths.append(_svg_path(curve))
		verges.append_array(Geometry2D.offset_polyline(curve.tessellate(8, 0.5), VERGE_RADIUS, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND))
	var cells: Dictionary[Vector2i, Vector2i] = {}
	for x: int in range(size.x):
		for y: int in range(size.y):
			var cell: Vector2i = Vector2i(x, y)
			var polygon: PackedVector2Array = PackedVector2Array(HEX)
			var center: Vector2 = cell_center(cell)
			for vertex: int in range(polygon.size()):
				polygon[vertex] += center
			for verge: PackedVector2Array in verges:
				if not Geometry2D.intersect_polygons(polygon, verge).is_empty():
					var tile: int = cells.size()
					cells[cell] = Vector2i(tile % ATLAS_COLUMNS, tile / ATLAS_COLUMNS)
					break
	return {"cells": cells, "curves": curves, "paths": paths}


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(32 + cell.x * 48, 32 + cell.y * 64 + (cell.x % 2) * 32)


static func centerlines(data: Dictionary) -> Array[Array]:
	var lines: Array[Array] = []
	for curve: Curve2D in data["curves"]:
		var points: Array[Array] = []
		for point: Vector2 in curve.tessellate(8, 0.5):
			points.append([point.x * 2.0, point.y * 2.0])
		lines.append(points)
	return lines


func write_assets(id: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ASSET_DIRECTORY))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIRECTORY))
	var cells: Dictionary = data["cells"]
	var rows: int = ceili(float(cells.size()) / float(ATLAS_COLUMNS))
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n' % [ATLAS_COLUMNS * 128, rows * 128, ATLAS_COLUMNS * 64, rows * 64]
	# A subpixel overlap keeps the shared antialiased hex edges from showing seams.
	svg += '<defs><clipPath id="hex"><path d="M15.8 -.35H48.2L64.35 32 48.2 64.35H15.8L-.35 32Z"/></clipPath></defs>\n'
	for cell: Vector2i in cells:
		var tile: Vector2i = cells[cell]
		var origin: Vector2 = cell_center(cell) - Vector2(32, 32)
		svg += '<g transform="translate(%d %d)"><g clip-path="url(#hex)"><g transform="translate(%.3f %.3f)">\n' % [tile.x * 64, tile.y * 64, -origin.x, -origin.y]
		# Draw every verge before any road surface so junctions cannot be painted over.
		svg += '<g fill="none" stroke-linecap="round" stroke-linejoin="round">\n'
		var strokes: Array[String] = [
			'<path d="%s" stroke="#64765d" stroke-width="14" opacity=".7"/>\n',
			'<path d="%s" stroke="#8e8b6a" stroke-width="12"/>\n',
			'<path d="%s" stroke="#c6b999" stroke-width="9"/>\n',
			'<path d="%s" stroke="#b6a783" stroke-width="5" opacity=".45"/>\n',
			'<path d="%s" transform="translate(0 -2.2)" stroke="#a79979" stroke-width=".7" opacity=".65"/>\n',
			'<path d="%s" transform="translate(0 2.2)" stroke="#a79979" stroke-width=".7" opacity=".65"/>\n',
		]
		for stroke: String in strokes:
			for path: String in data["paths"]:
				svg += stroke % path
		svg += '</g>\n'
		svg += '</g></g></g>\n'
	svg += '</svg>\n'
	var path: String = ASSET_DIRECTORY + "road_" + id + ".svg"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(svg)
	file.close()
	var image: Image = Image.new()
	assert(image.load_svg_from_string(svg) == OK, "Road atlas must rasterize successfully")
	assert(image.save_png(PREVIEW_DIRECTORY + "road_" + id + ".png") == OK)
	print("Created ", cells.size(), " connected road variations for ", id)


func _curve(knots: Array) -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	for index: int in range(knots.size()):
		var knot: Vector3 = knots[index]
		var incoming: Vector2 = Vector2.ZERO
		var outgoing: Vector2 = Vector2.ZERO
		if index > 0:
			var previous: Vector3 = knots[index - 1]
			var span: float = (knot.x - previous.x) / 3.0
			incoming = Vector2(-span * 48, -span * knot.z * 64)
		if index + 1 < knots.size():
			var next: Vector3 = knots[index + 1]
			var span: float = (next.x - knot.x) / 3.0
			outgoing = Vector2(span * 48, span * knot.z * 64)
		curve.add_point(Vector2(32 + knot.x * 48, 48 + knot.y * 64), incoming, outgoing)
	return curve


func _svg_path(curve: Curve2D) -> String:
	var start: Vector2 = curve.get_point_position(0)
	var path: String = "M%.3f %.3f" % [start.x, start.y]
	for index: int in range(1, curve.point_count):
		var first: Vector2 = curve.get_point_position(index - 1) + curve.get_point_out(index - 1)
		var second: Vector2 = curve.get_point_position(index) + curve.get_point_in(index)
		var end: Vector2 = curve.get_point_position(index)
		path += " C%.3f %.3f %.3f %.3f %.3f %.3f" % [first.x, first.y, second.x, second.y, end.x, end.y]
	return path
