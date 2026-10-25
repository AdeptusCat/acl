extends Node2D
class_name ObjectiveAreaOverlay

const AREA_SHADER: Shader = preload("res://assets/shader/objective_area.gdshader")
const FRIENDLY_COLOR: Color = Color(0.48, 0.85, 0.60)
const ENEMY_COLOR: Color = Color(0.96, 0.40, 0.30)
const REFRESH_INTERVAL_S: float = 0.05
const FONT: Font = preload("res://assets/fonts/courier_prime/Courier Prime.ttf")
const NAMES: Array[String] = ["EXIT", "A", "B", "C", "START"]
const COLORS: Array[Color] = [Color(0.48, 0.83, 0.85), Color(0.96, 0.75, 0.34), Color(0.70, 0.65, 0.96), Color(0.45, 0.82, 0.72), Color(0.65, 0.72, 0.78)]

var layer: HexagonTileMapLayer
var team: Globals.Team
var markers: Array[Dictionary] = []
var refresh_elapsed: float = 0.0


static func install(target: HexagonTileMapLayer, owner_team: Globals.Team) -> void:
	var overlay: ObjectiveAreaOverlay = target.get_node_or_null("ObjectiveArea") as ObjectiveAreaOverlay
	if overlay == null:
		overlay = ObjectiveAreaOverlay.new()
		overlay.name = "ObjectiveArea"
		target.add_child(overlay)
	overlay.setup(target, owner_team)


func setup(target: HexagonTileMapLayer, owner_team: Globals.Team) -> void:
	layer = target
	team = owner_team
	# Suppress the old tile artwork while retaining authored cells and layer visibility.
	layer.enabled = false
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	markers.clear()
	var shape: ConvexPolygonShape2D = layer.geometry_tile_shape.shape as ConvexPolygonShape2D
	var corners: PackedVector2Array = shape.points
	var capture_span: Vector2 = Vector2(INF, -INF)
	for corner: Vector2 in corners:
		var projection: float = corner.dot(Vector2(0.45, -1.0))
		capture_span.x = minf(capture_span.x, projection)
		capture_span.y = maxf(capture_span.y, projection)
	for hex: Vector2i in layer.get_used_cells():
		var data: TileData = layer.get_cell_tile_data(hex)
		if data == null:
			continue
		var id: int = int(data.get_custom_data("objective_id"))
		if id < 0 or id >= NAMES.size():
			continue
		var center: Vector2 = layer.map_to_local(hex)
		var edges: PackedFloat32Array = PackedFloat32Array()
		var points: PackedVector2Array = PackedVector2Array()
		for index: int in range(corners.size()):
			points.append(center + corners[index])
			var midpoint: Vector2 = (corners[index] + corners[(index + 1) % corners.size()]) * 0.5
			var neighbor: Vector2i = layer.local_to_map(center + midpoint * 1.1)
			var neighbor_data: TileData = layer.get_cell_tile_data(neighbor)
			var exposed: float = 1.0
			if neighbor != hex and neighbor_data != null and int(neighbor_data.get_custom_data("objective_id")) == id:
				exposed = 0.0
			edges.append(exposed)
		var shader_material: ShaderMaterial = ShaderMaterial.new()
		shader_material.shader = AREA_SHADER
		shader_material.set_shader_parameter("corners", corners)
		shader_material.set_shader_parameter("exposed_edges", edges)
		shader_material.set_shader_parameter("center", center)
		shader_material.set_shader_parameter("capture_span", capture_span)
		shader_material.set_shader_parameter("objective_phase", float(id) * 2.1)
		shader_material.set_shader_parameter("area_color", COLORS[id])
		var polygon: Polygon2D = Polygon2D.new()
		polygon.polygon = points
		polygon.material = shader_material
		add_child(polygon)
		markers.append({"hex": hex, "id": id, "center": center, "material": shader_material, "edges": edges})
	_update_colors()
	queue_redraw()


func _process(delta: float) -> void:
	refresh_elapsed += delta
	if refresh_elapsed >= REFRESH_INTERVAL_S:
		refresh_elapsed = 0.0
		_update_colors()


func _update_colors() -> void:
	var collection: VictoryConditionCollection = Globals.victory_conditions.get(team)
	if collection == null:
		return
	for marker: Dictionary in markers:
		var color: Color = COLORS[int(marker["id"])]
		var capture_progress: float = 0.0
		var capture_color: Color = FRIENDLY_COLOR
		for condition: VictoryCondition in collection.victory_conditions:
			if condition is not OccupyObjectiveCondition:
				continue
			var occupy: OccupyObjectiveCondition = condition as OccupyObjectiveCondition
			if occupy.objective_id != int(marker["id"]) or occupy.state == null:
				continue
			var style: Dictionary = capture_style(occupy, marker["hex"])
			color = style["color"]
			if float(style["progress"]) > capture_progress:
				capture_progress = style["progress"]
				capture_color = style["capture_color"]
		var shader_material: ShaderMaterial = marker["material"]
		shader_material.set_shader_parameter("area_color", color)
		shader_material.set_shader_parameter("capture_progress", capture_progress)
		shader_material.set_shader_parameter("capture_color", capture_color)


static func capture_style(occupy: OccupyObjectiveCondition, hex: Vector2i) -> Dictionary:
	var color: Color = COLORS[occupy.objective_id]
	var progress: float = 0.0
	var capture_color: Color = FRIENDLY_COLOR
	if occupy.state == null:
		return {"color": color, "progress": progress, "capture_color": capture_color}
	var owner: int = occupy.state.controlling_teams.get(hex, -1)
	var enemy: Globals.Team = Globals.get_enemy_team(occupy.team)
	if owner == occupy.team:
		color = FRIENDLY_COLOR
	elif owner == enemy:
		color = ENEMY_COLOR
	if occupy.required_time_s > 0.0:
		if owner != occupy.team:
			progress = clampf(occupy.state.required_times_reached_s.get(hex, 0.0) / occupy.required_time_s, 0.0, 1.0)
		if owner != enemy:
			var enemy_progress: float = clampf(occupy.state.enemy_hold_times_s.get(hex, 0.0) / occupy.required_time_s, 0.0, 1.0)
			if enemy_progress > progress:
				progress = enemy_progress
				capture_color = ENEMY_COLOR
	return {"color": color, "progress": progress, "capture_color": capture_color}


func _draw() -> void:
	for marker: Dictionary in markers:
		var text: String = NAMES[int(marker["id"])]
		var center: Vector2 = marker["center"]
		var extent: Vector2 = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13)
		var baseline: Vector2 = center + Vector2(-extent.x * 0.5, 4.0)
		draw_string_outline(FONT, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, 3, Color(0.07, 0.09, 0.08, 0.9))
		draw_string(FONT, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.97, 0.91, 0.73, 0.9))
