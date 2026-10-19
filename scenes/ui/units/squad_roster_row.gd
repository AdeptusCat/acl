extends Button
class_name SquadRosterRow

@onready var identity: Label = $Content/Top/Identity
@onready var strength: Label = $Content/Top/Strength/Count
@onready var strength_bar: ProgressBar = $Content/Top/Strength/Bar
@onready var morale: Label = $Content/Status/Morale
@onready var rout_available: TextureRect = $Content/Status/RoutSlot/RoutAvailable
@onready var isolation: Label = $Content/Status/Isolation

var unit: Unit
var stack_row: bool = false


func _ready() -> void:
	$Content.minimum_size_changed.connect(_fit_content)
	$Content/Status.visible = not stack_row
	strength_bar.visible = not stack_row
	_fit_content()
	if is_instance_valid(unit):
		unit.stress_system.state_changed.connect(_on_morale_state_changed)


func _fit_content() -> void:
	var minimum_height: float = 44.0
	if stack_row:
		minimum_height = 28.0
	custom_minimum_size.y = maxf(minimum_height, $Content.get_combined_minimum_size().y + 6.0)


func _on_morale_state_changed(_previous: int, _next: int) -> void:
	refresh()


func refresh() -> void:
	if not is_instance_valid(unit):
		return
	disabled = not unit.is_active()
	modulate = Color.WHITE
	if not unit.alive:
		modulate = Color(0.65, 0.65, 0.65, 1.0)
	identity.text = unit.get_hud_name()
	if stack_row:
		identity.text = "%s/%d/%d · %s" % [Unit.COMPANY_NAMES[unit.company], unit.platoon, unit.squad, Globals.SQUAD_TYPE_NAMES[unit.squad_type]]
	var remaining: int = unit.squad_fire.soldiers.size()
	if not unit.alive:
		remaining = 0
	strength.text = "%d/%d" % [remaining, unit.original_size]
	strength_bar.value = float(remaining) / float(maxi(1, unit.original_size))
	set_pressed_no_signal(unit.selected)
	if stack_row:
		tooltip_text = "%s\n%s" % [unit.get_hud_name(), unit.get_formation_name()]
		return
	if not unit.alive:
		morale.text = "Eliminated"
		morale.add_theme_color_override("font_color", Color(0.7, 0.67, 0.6))
		rout_available.hide()
		isolation.hide()
		tooltip_text = "%s\n%s\nStrength: 0/%d · Eliminated" % [identity.text, unit.get_formation_name(), unit.original_size]
		return
	morale.text = unit.get_state_name(int(unit.stress_system.state))
	if unit.stress_system.state == STATES.MoraleState.COMBAT_INEFFECTIVE:
		morale.text = "Ineffective"
	var morale_color: Color = Color(0.66, 0.8, 0.56)
	match unit.stress_system.state:
		STATES.MoraleState.CAUTIOUS:
			morale_color = Color(0.86, 0.76, 0.46)
		STATES.MoraleState.PINNED:
			morale_color = Color(0.95, 0.65, 0.35)
		STATES.MoraleState.PANIC, STATES.MoraleState.COMBAT_INEFFECTIVE:
			morale_color = Color(0.96, 0.45, 0.38)
	if unit.broken:
		morale.text = "Routed"
		morale_color = Color(0.96, 0.45, 0.38)
	if unit.surrendered:
		morale.text = "Surrendered"
		morale_color = Color(0.7, 0.67, 0.6)
	morale.add_theme_color_override("font_color", morale_color)
	rout_available.visible = unit.can_rout()
	isolation.visible = _is_isolated()
	tooltip_text = "%s\n%s\nStrength: %d/%d · Morale: %s\nClick to select and center" % [identity.text, unit.get_formation_name(), remaining, unit.original_size, morale.text]
	if rout_available.visible:
		tooltip_text += "\nRout available: select this squad, then right click for Rout.\nAn uncontrolled retreat; no escape route means surrender."
	if _is_isolated():
		tooltip_text += "\nNo contact: no effective command link to an active headquarters"
	else:
		if CommandConnectivity.needs_command_contact(unit):
			tooltip_text += "\n%s · %s" % [CommandConnectivity.contact_text(CommandConnectivity.contact_state_for(unit)), CommandConnectivity.contact_method_for(unit)]
		else:
			tooltip_text += "\nTop-level headquarters"


func _is_isolated() -> bool:
	return CommandConnectivity.needs_command_contact(unit) and CommandConnectivity.contact_state_for(unit) == CommandConnectivity.ContactState.LOST
