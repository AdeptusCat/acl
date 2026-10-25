extends Button
class_name ObjectiveCaptureButton

signal objective_focused(hex: Vector2i)

const CAPTURE_SHADER: Shader = preload("res://assets/shader/objective_capture_button.gdshader")

var condition: OccupyObjectiveCondition
var backgrounds: HBoxContainer
var hexes: Array[Vector2i] = []
var ownership_badge: Label


func setup(source: OccupyObjectiveCondition) -> void:
	condition = source
	text = condition.get_description()
	custom_minimum_size.y = 40.0
	add_theme_font_size_override("font_size", 14)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color.TRANSPARENT
	normal.content_margin_left = 12.0
	normal.content_margin_right = 66.0
	add_theme_stylebox_override("normal", normal)
	for state: String in ["hover", "pressed", "focus"]:
		var highlight: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
		highlight.bg_color = Color(1.0, 1.0, 1.0, 0.08)
		highlight.set_border_width_all(1)
		highlight.border_color = Color(1.0, 0.95, 0.8)
		add_theme_stylebox_override(state, highlight)
	backgrounds = HBoxContainer.new()
	backgrounds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backgrounds.show_behind_parent = true
	backgrounds.add_theme_constant_override("separation", 0)
	add_child(backgrounds)
	backgrounds.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ownership_badge = Label.new()
	ownership_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ownership_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ownership_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ownership_badge.add_theme_font_size_override("font_size", 10)
	add_child(ownership_badge)
	ownership_badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	ownership_badge.offset_left = -60.0
	ownership_badge.offset_right = -8.0
	ownership_badge.offset_top = -10.0
	ownership_badge.offset_bottom = 10.0
	pressed.connect(_focus_objective)
	refresh()


func refresh() -> void:
	if condition.state == null:
		disabled = true
		return
	disabled = condition.state.hexes.is_empty()
	if hexes != condition.state.hexes:
		hexes = condition.state.hexes.duplicate()
		for child: Node in backgrounds.get_children():
			backgrounds.remove_child(child)
			child.queue_free()
		for hex: Vector2i in hexes:
			var background: ColorRect = ColorRect.new()
			background.mouse_filter = Control.MOUSE_FILTER_IGNORE
			background.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var shader_material: ShaderMaterial = ShaderMaterial.new()
			shader_material.shader = CAPTURE_SHADER
			background.material = shader_material
			backgrounds.add_child(background)
	var owner: int = -1
	if not hexes.is_empty():
		owner = condition.state.controlling_teams.get(hexes[0], -1)
	for hex: Vector2i in hexes:
		if int(condition.state.controlling_teams.get(hex, -1)) != owner:
			owner = -2
	var badge_color: Color = ObjectiveAreaOverlay.COLORS[condition.objective_id]
	ownership_badge.text = "NEUTRAL"
	if owner == condition.team:
		ownership_badge.text = "OURS"
		badge_color = ObjectiveAreaOverlay.FRIENDLY_COLOR
	elif owner == Globals.get_enemy_team(condition.team):
		ownership_badge.text = "ENEMY"
		badge_color = ObjectiveAreaOverlay.ENEMY_COLOR
	elif owner == -2:
		ownership_badge.text = "MIXED"
	ownership_badge.add_theme_color_override("font_color", badge_color)
	for index: int in range(hexes.size()):
		var style: Dictionary = ObjectiveAreaOverlay.capture_style(condition, hexes[index])
		var shader_material: ShaderMaterial = (backgrounds.get_child(index) as ColorRect).material as ShaderMaterial
		shader_material.set_shader_parameter("area_color", style["color"])
		shader_material.set_shader_parameter("capture_progress", style["progress"])
		shader_material.set_shader_parameter("capture_color", style["capture_color"])


func _focus_objective() -> void:
	# The panel owns camera navigation; keyboard and mouse activation share this signal.
	if not hexes.is_empty():
		objective_focused.emit(hexes[0])
