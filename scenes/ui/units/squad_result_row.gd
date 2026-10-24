extends HBoxContainer

const SKULL: Texture2D = preload("res://assets/effects/skull.png")
const INTACT_COLOR: Color = Color(0.65, 0.85, 0.55)
const REDUCED_COLOR: Color = Color(0.96, 0.77, 0.43)
const ELIMINATED_COLOR: Color = Color(1.0, 0.55, 0.45)
const EXITED_COLOR: Color = Color(0.64, 0.8, 0.91)

var thumbnail: TextureRect
var identity: Label
var formation: Label
var status: Label
var strength: Label


func setup(unit: Unit) -> void:
	# Copy the result into controls so the row does not retain battlefield nodes.
	var remaining: int = maxi(0, unit.members_alive)
	if not unit.alive:
		remaining = 0
	var starting: int = maxi(unit.original_size, remaining)
	var lost: int = starting - remaining
	var eliminated: bool = remaining == 0
	var status_text: String = "Intact"
	var status_color: Color = INTACT_COLOR
	if lost > 0:
		status_text = "Reduced"
		status_color = REDUCED_COLOR
	if unit.exited:
		status_text = "Exited"
		status_color = EXITED_COLOR
		if lost > 0:
			status_text += " · Reduced"
	elif unit.surrendered:
		status_text = "Surrendered"
		status_color = REDUCED_COLOR
		if lost > 0:
			status_text += " · Reduced"
	if eliminated:
		status_text = "Eliminated"
		status_color = ELIMINATED_COLOR
	custom_minimum_size.y = 66.0
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_make_picture(unit, eliminated))
	var details: VBoxContainer = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 2)
	add_child(details)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	details.add_child(header)
	identity = _label(unit.get_hud_name())
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.clip_text = true
	identity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(identity)
	status = _label(status_text)
	status.add_theme_color_override("font_color", status_color)
	status.add_theme_font_size_override("font_size", 14)
	header.add_child(status)
	formation = _label(unit.get_formation_name(), &"HudSecondary")
	details.add_child(formation)
	strength = _label("%d/%d soldiers remain · %d lost" % [remaining, starting, lost], &"HudSecondary")
	details.add_child(strength)
	tooltip_text = "%s\n%s\n%s\n%s" % [identity.text, formation.text, status.text, strength.text]


func _make_picture(unit: Unit, eliminated: bool) -> PanelContainer:
	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(52.0, 52.0)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.32, 0.34, 0.28)
	style.border_color = Color(0.53, 0.54, 0.43)
	style.set_border_width_all(1)
	style.set_content_margin_all(2.0)
	style.set_corner_radius_all(2)
	frame.add_theme_stylebox_override("panel", style)
	thumbnail = TextureRect.new()
	thumbnail.texture = MissionForceRow.idle_picture(unit)
	thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(thumbnail)
	if unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS or unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
		var badge: Label = _label("HQ", &"HudSecondary")
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		badge.add_theme_color_override("font_color", Color(0.98, 0.89, 0.65))
		badge.add_theme_color_override("font_outline_color", Color(0.08, 0.09, 0.07))
		badge.add_theme_constant_override("outline_size", 2)
		frame.add_child(badge)
	if eliminated:
		thumbnail.modulate = Color(0.6, 0.6, 0.6, 0.5)
		var overlay: MarginContainer = MarginContainer.new()
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(overlay)
		var skull: TextureRect = TextureRect.new()
		skull.texture = SKULL
		skull.custom_minimum_size = Vector2(20.0, 20.0)
		skull.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		skull.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		skull.size_flags_horizontal = Control.SIZE_SHRINK_END
		skull.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		skull.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(skull)
	return frame


func _label(value: String, variation: StringName = &"") -> Label:
	var label: Label = Label.new()
	label.text = value
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
