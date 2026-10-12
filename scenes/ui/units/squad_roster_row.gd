extends Button
class_name SquadRosterRow

@onready var identity: Label = $Content/Top/Identity
@onready var strength: Label = $Content/Top/Strength/Count
@onready var strength_bar: ProgressBar = $Content/Top/Strength/Bar
@onready var morale: Label = $Content/Status/Morale
@onready var isolation: Label = $Content/Status/Isolation

var unit: Unit


func refresh() -> void:
	if not is_instance_valid(unit):
		return
	var designation: String = unit.ui.unit_designation_label.text.strip_edges()
	if designation.is_empty():
		designation = str(unit.squad)
	identity.text = "%s · %s" % [designation, _short_type(unit.squad_type)]
	var remaining: int = unit.squad_fire.soldiers.size()
	strength.text = "%d/%d" % [remaining, unit.original_size]
	strength_bar.value = float(remaining) / float(maxi(1, unit.original_size))
	morale.text = unit.get_state_name(int(unit.stress_system.state))
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
	isolation.visible = _is_isolated()
	set_pressed_no_signal(unit.selected)
	tooltip_text = "%s · %s\nCompany %s · Platoon %d · Squad %d\nStrength: %d/%d · Morale: %s\nClick to select and center" % [designation, unit.get_squad_type_name(unit.squad_type), Unit.COMPANY_NAMES[unit.company], unit.platoon, unit.squad, remaining, unit.original_size, morale.text]
	if isolation.visible:
		tooltip_text += "\nIsolated: no communication link to an active headquarters"
	else:
		if unit.squad_type != Globals.SquadType.COMPANY_HEADQUARTERS:
			tooltip_text += "\nIn contact with headquarters"


func _is_isolated() -> bool:
	if unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
		return false
	if not is_instance_valid(unit.command_squad) or not unit.command_squad.is_active() or unit.command_squad.surrendered:
		return true
	var link: CommandConnectivity = unit.command_connectivity
	return not (link.los_to_leader or link.voice_range_to_leader or link.runner_chain_to_leader or link.radio_link_to_leader)


func _short_type(type: Globals.SquadType) -> String:
	match type:
		Globals.SquadType.Rifle:
			return "Rifle"
		Globals.SquadType.MG:
			return "MG"
		Globals.SquadType.ANTITANK:
			return "Antitank"
		Globals.SquadType.MORTAR:
			return "Mortar"
		Globals.SquadType.PLATOON_HEADQUARTERS:
			return "Platoon HQ"
		Globals.SquadType.COMPANY_HEADQUARTERS:
			return "Company HQ"
	return "Squad"
