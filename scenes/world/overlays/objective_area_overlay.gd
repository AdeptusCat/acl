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


static func install_enemy_exits(target: HexagonTileMapLayer, owner_team: Globals.Team) -> void:
	# Enemy capture markers stay hidden; exit routes remain visible on their own canvas item.
	var parent: Node = target.get_parent()
	var overlay: ObjectiveAreaOverlay = parent.get_node_or_null("EnemyExitArea") as ObjectiveAreaOverlay
	if overlay == null:
		overlay = ObjectiveAreaOverlay.new()
		overlay.name = "EnemyExitArea"
		parent.add_child(overlay)
	overlay.setup(target, owner_team, true)
	overlay.global_transform = target.global_transform


static func get_exit_hexes(target: HexagonTileMapLayer, owner_team: Globals.Team) -> Array[Vector2i]:
	var exit_hexes: Array[Vector2i] = []
	for hex: Vector2i in target.get_used_cells():
		var data: TileData = target.get_cell_tile_data(hex)
		if data != null and int(data.get_custom_data("objective_id")) == ExitUnitsCondition.ObjectiveId.EXIT:
			exit_hexes.append(hex)
	for condition_team: Globals.Team in Globals.victory_conditions:
		var collection: VictoryConditionCollection = Globals.victory_conditions[condition_team]
		for condition: VictoryCondition in collection.victory_conditions:
			var cells: Array[Vector2i] = []
			if condition is ExitUnitsCondition and condition.team == owner_team:
				var exit: ExitUnitsCondition = condition as ExitUnitsCondition
				if exit.state != null:
					cells = exit.state.exit_hexes
			elif condition is PreventEnemyExitCondition and Globals.get_enemy_team(condition.team) == owner_team:
				var prevention: PreventEnemyExitCondition = condition as PreventEnemyExitCondition
				if prevention.state != null:
					cells = prevention.state.exit_hexes
			for hex: Vector2i in cells:
				if not exit_hexes.has(hex):
					exit_hexes.append(hex)
	return exit_hexes


func setup(target: HexagonTileMapLayer, owner_team: Globals.Team, exits_only: bool = false) -> void:
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
	var exit_hexes: Array[Vector2i] = get_exit_hexes(layer, team)
	var visible_cells: Array[Vector2i] = layer.get_used_cells()
	if exits_only:
		visible_cells = exit_hexes
	for hex: Vector2i in visible_cells:
		var data: TileData = layer.get_cell_tile_data(hex)
		if data == null:
			continue
		var id: int = int(data.get_custom_data("objective_id"))
		if id < 0 or id >= NAMES.size():
			continue
		var is_exit: bool = exit_hexes.has(hex)
		var center: Vector2 = layer.map_to_local(hex)
		var edges: PackedFloat32Array = PackedFloat32Array()
		var points: PackedVector2Array = PackedVector2Array()
		for index: int in range(corners.size()):
			points.append(center + corners[index])
			var midpoint: Vector2 = (corners[index] + corners[(index + 1) % corners.size()]) * 0.5
			var neighbor: Vector2i = layer.local_to_map(center + midpoint * 1.1)
			var neighbor_data: TileData = layer.get_cell_tile_data(neighbor)
			var exposed: float = 1.0
			if neighbor != hex and visible_cells.has(neighbor) and neighbor_data != null and int(neighbor_data.get_custom_data("objective_id")) == id and exit_hexes.has(neighbor) == is_exit:
				exposed = 0.0
			edges.append(exposed)
		var shader_material: ShaderMaterial = ShaderMaterial.new()
		shader_material.shader = AREA_SHADER
		shader_material.set_shader_parameter("corners", corners)
		shader_material.set_shader_parameter("exposed_edges", edges)
		shader_material.set_shader_parameter("center", center)
		shader_material.set_shader_parameter("capture_span", capture_span)
		shader_material.set_shader_parameter("objective_phase", float(id) * 2.1)
		var color: Color = COLORS[id]
		if is_exit:
			color = COLORS[ExitUnitsCondition.ObjectiveId.EXIT]
		shader_material.set_shader_parameter("area_color", color)
		var polygon: Polygon2D = Polygon2D.new()
		polygon.polygon = points
		polygon.material = shader_material
		add_child(polygon)
		var activity_label: Label = Label.new()
		activity_label.position = center + Vector2(-52.0, 13.0)
		activity_label.size = Vector2(104.0, 18.0)
		activity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		activity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		activity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		activity_label.add_theme_font_override("font", FONT)
		activity_label.add_theme_font_size_override("font_size", 10)
		activity_label.add_theme_constant_override("outline_size", 3)
		activity_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.02))
		activity_label.z_index = 1
		activity_label.hide()
		add_child(activity_label)
		markers.append({"hex": hex, "id": id, "center": center, "material": shader_material, "edges": edges, "is_exit": is_exit, "activity_label": activity_label})
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
		if bool(marker["is_exit"]):
			color = COLORS[ExitUnitsCondition.ObjectiveId.EXIT]
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
		var activity_label: Label = marker["activity_label"]
		activity_label.visible = capture_progress > 0.0 and capture_progress < 1.0
		if activity_label.visible:
			var action: String = "CAPTURING"
			if capture_color == ENEMY_COLOR:
				action = "LOSING"
			activity_label.text = "%s %d%%" % [action, clampi(floori(capture_progress * 100.0), 1, 99)]
			activity_label.add_theme_color_override("font_color", capture_color)


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
		if bool(marker["is_exit"]) and int(marker["id"]) != ExitUnitsCondition.ObjectiveId.EXIT:
			text = "EXIT " + text
		var center: Vector2 = marker["center"]
		var extent: Vector2 = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13)
		var baseline: Vector2 = center + Vector2(-extent.x * 0.5, 4.0)
		draw_string_outline(FONT, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, 3, Color(0.07, 0.09, 0.08, 0.9))
		draw_string(FONT, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(0.97, 0.91, 0.73, 0.9))
