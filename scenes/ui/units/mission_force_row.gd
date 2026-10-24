extends HBoxContainer
class_name MissionForceRow

const HUD_THEME: Theme = preload("res://resources/theme/battle_hud_theme.tres")
const THUMBNAIL_SIZE: float = 40.0
const CARD_WIDTH: float = 320.0

var thumbnail: TextureRect
var squad_name: String
var formation: String
var role: String
var strength_text: String
var equipment_summary: String
var _picture: Texture2D
var _headquarters: bool = false


func setup(unit: Unit) -> void:
	custom_minimum_size.y = THUMBNAIL_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_force_pass_scroll_events = true
	add_theme_constant_override("separation", 12)
	squad_name = unit.get_hud_name()
	formation = unit.get_formation_name()
	role = unit.get_squad_type_name(unit.squad_type)
	strength_text = "Strength unknown"
	if unit.squad_loadout != null:
		var soldiers: int = unit.squad_loadout.soldiers.size()
		strength_text = "%d soldiers" % soldiers
		if soldiers == 1:
			strength_text = "1 soldier"
	equipment_summary = _equipment_summary(unit.squad_loadout)
	_headquarters = unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS or unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS
	_picture = idle_picture(unit)
	var frame: PanelContainer = _make_picture(THUMBNAIL_SIZE)
	frame.name = "Picture"
	thumbnail = frame.get_node("Image") as TextureRect
	add_child(frame)
	var identity: Label = Label.new()
	identity.name = "Identity"
	identity.text = squad_name
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.clip_text = true
	identity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(identity)
	var strength: Label = Label.new()
	strength.name = "Strength"
	strength.text = strength_text
	strength.theme_type_variation = &"HudSecondary"
	strength.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strength)
	tooltip_text = "%s\n%s\nRole: %s\nStrength: %s\nEquipment: %s" % [squad_name, formation, role, strength_text, equipment_summary]


static func idle_picture(unit: Unit) -> Texture2D:
	if not is_instance_valid(unit.ui) or not is_instance_valid(unit.ui.unit_status_control):
		return null
	var icons: Control = unit.ui.unit_status_control
	var property: String = "idle_"
	match unit.squad_type:
		Globals.SquadType.MG:
			property = "idle_mg_"
		Globals.SquadType.ANTITANK:
			property = "idle_antitank_"
		Globals.SquadType.MORTAR:
			property = "idle_mortar_"
	if unit.team == Globals.Team.AXIS:
		if unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS or unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
			var leader: Texture2D = icons.get("idle_leader_ger") as Texture2D
			if leader != null:
				return leader
		property += "ger"
	else:
		property += "us"
	return icons.get(property) as Texture2D


func _equipment_summary(loadout: SquadLoadoutSpec) -> String:
	if loadout == null:
		return "Not specified"
	var names: Array[String] = []
	for soldier: SoldierLoadout in loadout.soldiers:
		if soldier == null:
			continue
		var weapon: WeaponSpec = soldier.resolve_weapon()
		if weapon != null and not names.has(weapon.name):
			names.append(weapon.name)
	if names.is_empty():
		return "Not specified"
	names.sort()
	return ", ".join(names)


func _make_picture(picture_size: float) -> PanelContainer:
	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(picture_size, picture_size)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.32, 0.34, 0.28, 1.0)
	style.border_color = Color(0.53, 0.54, 0.43, 1.0)
	style.set_border_width_all(1)
	style.set_content_margin_all(2.0)
	style.set_corner_radius_all(2)
	frame.add_theme_stylebox_override("panel", style)
	var picture: TextureRect = TextureRect.new()
	picture.name = "Image"
	picture.texture = _picture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(picture)
	if _headquarters:
		var badge: Label = Label.new()
		badge.text = "HQ"
		badge.theme_type_variation = &"HudSecondary"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_color_override("font_color", Color(0.98, 0.89, 0.65))
		badge.add_theme_color_override("font_outline_color", Color(0.08, 0.09, 0.07))
		badge.add_theme_constant_override("outline_size", 2)
		frame.add_child(badge)
	return frame


func _make_custom_tooltip(_for_text: String) -> Object:
	var card: PanelContainer = PanelContainer.new()
	card.name = "SquadHoverCard"
	card.theme = HUD_THEME
	card.theme_type_variation = &"TooltipPanel"
	var width: float = minf(CARD_WIDTH, get_viewport().get_visible_rect().size.x - 32.0)
	var content_width: float = width - 30.0
	var identity_width: float = content_width - 76.0
	card.custom_minimum_size.x = width
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	card.add_child(content)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	header.add_child(_make_picture(64.0))
	var identity: VBoxContainer = VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 4)
	header.add_child(identity)
	var title: Label = _card_label(squad_name, identity_width, &"HudHeading")
	title.name = "Identity"
	identity.add_child(title)
	identity.add_child(_card_label(formation, identity_width, &"HudSecondary"))
	identity.add_child(_card_label("Strength: " + strength_text, identity_width, &"HudSecondary"))
	content.add_child(_card_label("Role: " + role, content_width))
	content.add_child(_card_label("Equipment: " + equipment_summary, content_width))
	card.size = card.get_combined_minimum_size()
	return card


func _card_label(text_value: String, width: float, variation: StringName = &"") -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Tooltip windows measure controls before their first container layout.
	label.custom_minimum_size.x = width
	label.size.x = width
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
