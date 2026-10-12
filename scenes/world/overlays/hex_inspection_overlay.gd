extends Node2D
class_name HexInspectionOverlay

signal edge_hovered(direction: int, cover: int, screen_point: Vector2)
signal edge_left

const DIRECTIONS: Array[TileSet.CellNeighbor] = [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE]
const EDGE_KEYS: Array[String] = ["cover_n", "cover_ne", "cover_se", "cover_s", "cover_sw", "cover_nw"]
const FONT: Font = preload("res://assets/fonts/courier_prime/Courier Prime.ttf")

var ground_layer: HexagonTileMapLayer
var segments: Array[Dictionary] = []
var hovered_direction: int = -1
var _hover_point: Vector2 = Vector2.INF


func _ready() -> void:
	hide()
	set_process(false)


func inspect(layer: HexagonTileMapLayer, result: Dictionary) -> void:
	ground_layer = layer
	global_transform = layer.global_transform
	segments.clear()
	_clear_hover()
	var hex: Vector2i = result["hex"]
	var center: Vector2 = layer.map_to_local(hex)
	var cube: Vector3i = layer.map_to_cube(hex)
	var polygon: ConvexPolygonShape2D = layer.geometry_tile_shape.shape as ConvexPolygonShape2D
	var corners: PackedVector2Array = polygon.points
	for index: int in range(DIRECTIONS.size()):
		var cover: int = int(result.get(EDGE_KEYS[index], 0))
		if cover <= 0:
			continue
		var neighbor: Vector2 = layer.cube_to_local(cube + layer.cube_direction(DIRECTIONS[index]))
		var outward: Vector2 = (neighbor - center).normalized()
		var best_edge: int = 0
		var best_projection: float = -INF
		for edge: int in range(corners.size()):
			var midpoint: Vector2 = (corners[edge] + corners[(edge + 1) % corners.size()]) * 0.5
			var projection: float = midpoint.dot(outward)
			if projection > best_projection:
				best_projection = projection
				best_edge = edge
		var first: Vector2 = corners[best_edge]
		var second: Vector2 = corners[(best_edge + 1) % corners.size()]
		var label: Vector2 = center + (first + second) * 0.36
		var extent: Vector2 = FONT.get_string_size(str(cover), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12)
		var badge: Rect2 = Rect2(label - Vector2(extent.x * 0.5 + 2.0, 7.0), Vector2(extent.x + 4.0, 14.0))
		segments.append({"direction": index, "cover": cover, "start": center + first * 0.9, "end": center + second * 0.9, "label": label, "extent": extent, "badge": badge})
	show()
	set_process(true)
	queue_redraw()


func clear_inspection() -> void:
	segments.clear()
	_clear_hover()
	hide()
	set_process(false)
	queue_redraw()


func _process(_delta: float) -> void:
	if get_viewport().gui_get_hovered_control() != null:
		_clear_hover()
		return
	update_hover(get_local_mouse_position(), get_viewport().get_mouse_position())


func update_hover(local_point: Vector2, screen_point: Vector2) -> void:
	var hit: int = -1
	var nearest: float = INF
	var hit_radius: float = 8.0 / maxf(0.1, get_global_transform_with_canvas().get_scale().x)
	for index: int in range(segments.size()):
		var segment: Dictionary = segments[index]
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(local_point, segment["start"], segment["end"])
		var distance: float = closest.distance_to(local_point)
		var badge: Rect2 = segment["badge"]
		if badge.has_point(local_point):
			distance = 0.0
		if distance <= hit_radius and distance < nearest:
			nearest = distance
			hit = index
	if hit == -1:
		_clear_hover()
		return
	var segment: Dictionary = segments[hit]
	var direction: int = int(segment["direction"])
	if hovered_direction == direction and _hover_point == screen_point:
		return
	_hover_point = screen_point
	if hovered_direction != direction:
		hovered_direction = direction
		queue_redraw()
	edge_hovered.emit(direction, int(segment["cover"]), screen_point)


func _clear_hover() -> void:
	_hover_point = Vector2.INF
	if hovered_direction != -1:
		hovered_direction = -1
		edge_left.emit()
		queue_redraw()


func _draw() -> void:
	for segment: Dictionary in segments:
		var cover: int = int(segment["cover"])
		var color: Color = Color(0.75, 0.81, 0.44)
		if cover >= 2:
			color = Color(0.42, 0.83, 0.78)
		if int(segment["direction"]) == hovered_direction:
			color = Color(1.0, 0.9, 0.6)
		draw_line(segment["start"], segment["end"], Color(0.06, 0.06, 0.05), 5.0, true)
		draw_line(segment["start"], segment["end"], color, 2.0, true)
		var label: Vector2 = segment["label"]
		var text: String = str(cover)
		var extent: Vector2 = segment["extent"]
		draw_rect(segment["badge"], Color(0.06, 0.06, 0.05))
		draw_string(FONT, label + Vector2(-extent.x * 0.5, 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, color)
