extends PanelContainer

@export var soldier_detail_row_scene: PackedScene

const PANEL_WIDTH: float = 300.0
const HUD_MARGIN: float = 12.0
const REFRESH_INTERVAL_S: float = 0.1

enum Entry { NAME, ROLE, RANK, WEAPON, TASK, PROGRESS_BAR }

@onready var unit_type_label: Label = $Scroll/Summary/Identity
@onready var formation_label: Label = $Scroll/Summary/Formation
@onready var command_label: Label = $Scroll/Summary/Command
@onready var strength_label: Label = $Scroll/Summary/Status/Strength
@onready var unit_status_label: Label = $Scroll/Summary/Status/Morale
@onready var order_label: Label = $Scroll/Summary/Order
@onready var cohesion: Label = $Scroll/Summary/Details/Content/Readiness/Cohesion
@onready var effectiveness: Label = $Scroll/Summary/Details/Content/Readiness/Effectiveness
@onready var cohesion_bar: ProgressBar = $Scroll/Summary/Details/Content/Readiness/CohesionBar
@onready var effectiveness_bar: ProgressBar = $Scroll/Summary/Details/Content/Readiness/EffectivenessBar
@onready var details_section: FoldableContainer = $Scroll/Summary/Details
@onready var roster_section: FoldableContainer = $Scroll/Summary/Roster
@onready var roster_scroll: ScrollContainer = $Scroll/Summary/Roster/Scroll
@onready var roster_container: VBoxContainer = $Scroll/Summary/Roster/Scroll/Rows
@onready var casualty_shock: Label = $Scroll/Summary/Details/Content/Stats/CasualtyShock
@onready var leadership_bonus_label: Label = $Scroll/Summary/Details/Content/Stats/LeadershipBonus
@onready var leadership_presence_label: Label = $Scroll/Summary/Details/Content/Stats/LeadershipPresence
@onready var debug_actions: HFlowContainer = $Scroll/Summary/Details/Content/DebugActions
@onready var rout_button: RoutButton = $Scroll/Summary/Rout
@onready var rout_explanation: Label = $Scroll/Summary/RoutExplanation
@onready var hud_control: Control = get_parent() as Control
@onready var summary_scroll: ScrollContainer = $Scroll
@onready var summary: VBoxContainer = $Scroll/Summary

var unit: Unit
var soldiers: Array[Soldier] = []
var casualties: Array[Soldier] = []
var soldier_entries_by_soldier: Dictionary[Soldier, Dictionary] = {}
var casualty_entries_by_casualty: Dictionary[Soldier, Dictionary] = {}
var soldiers_entries: Array[Dictionary] = []
var opacity_tween: Tween
var _roster_rows: Array[Control] = []
var _refresh_elapsed_s: float = 0.0


func _ready() -> void:
	minimum_size_changed.connect(_queue_fit)
	summary.minimum_size_changed.connect(_queue_fit)
	if hud_control != null:
		hud_control.resized.connect(_fit_panel)
		for path: String in ["MissionObjectives", "OrderFeedback", "Settings", "Settings/Menu", "Settings/Controls"]:
			var panel: Control = hud_control.get_node_or_null(path) as Control
			if panel != null:
				panel.item_rect_changed.connect(_queue_fit)
				panel.visibility_changed.connect(_queue_fit)
	else:
		get_viewport().size_changed.connect(_fit_panel)
	details_section.folding_changed.connect(_on_details_folding_changed)
	roster_section.folding_changed.connect(_on_roster_folding_changed)
	debug_actions.visible = OS.is_debug_build()
	rout_button.set_rout_available(false)
	set_process(false)
	_fit_panel()


func _exit_tree() -> void:
	_disconnect_unit()


func _queue_fit() -> void:
	_fit_panel.call_deferred()


func _fit_panel() -> void:
	if not is_node_ready() or is_queued_for_deletion():
		return
	var hud_size: Vector2 = get_viewport().get_visible_rect().size
	if hud_control != null:
		hud_size = hud_control.size
	var panel_width: float = minf(PANEL_WIDTH, maxf(0.0, hud_size.x - HUD_MARGIN * 2.0))
	custom_minimum_size.x = panel_width
	var top: float = HUD_MARGIN
	if hud_control != null:
		var column_left: float = hud_size.x - panel_width - HUD_MARGIN
		for path: String in ["MissionObjectives", "OrderFeedback", "Countdown", "TryAgain", "Settings", "Settings/Menu", "Settings/Controls"]:
			var panel: Control = hud_control.get_node_or_null(path) as Control
			if panel != null and panel.is_visible_in_tree():
				var rect: Rect2 = hud_control.get_global_transform().affine_inverse() * panel.get_global_rect()
				if rect.end.x > column_left:
					top = maxf(top, rect.end.y + HUD_MARGIN)
	var margins: float = get_theme_stylebox("panel").get_minimum_size().y
	var height_limit: float = floorf(minf(hud_size.y / 3.0, maxf(0.0, hud_size.y - top - HUD_MARGIN)))
	if not roster_section.folded:
		var summary_overhead: float = maxf(0.0, summary.get_combined_minimum_size().y - roster_scroll.get_combined_minimum_size().y)
		roster_scroll.custom_minimum_size.y = minf(roster_container.get_combined_minimum_size().y, maxf(48.0, height_limit - margins - summary_overhead))
	summary_scroll.custom_minimum_size.y = minf(summary.get_combined_minimum_size().y, maxf(0.0, height_limit - margins))
	size = Vector2(panel_width, get_combined_minimum_size().y)
	position = hud_size - size - Vector2(HUD_MARGIN, HUD_MARGIN)


func _process(delta: float) -> void:
	if not is_instance_valid(unit):
		return
	_refresh_elapsed_s += delta
	if _refresh_elapsed_s >= REFRESH_INTERVAL_S or delta <= 0.0:
		_refresh_elapsed_s = 0.0
		_refresh_summary()
		_refresh_roster_tasks()


func show_unit_detail(selected_unit: Unit, tween_on: bool = true) -> void:
	var selection_changed: bool = unit != selected_unit
	if selection_changed:
		_disconnect_unit()
		unit = selected_unit
		unit.soldiers_changed.connect(_on_soldiers_changed)
		unit.state_changed.connect(_on_state_changed)
		unit.unit_died.connect(_on_unit_removed)
		unit.unit_exited.connect(_on_unit_removed)
		unit.stress_system.leadership_changed.connect(_on_leadership_changed)
		unit.action_controller.action_state_changed.connect(_on_action_state_changed)
		details_section.folded = true
		roster_section.folded = true
		roster_scroll.scroll_vertical = 0
	_rebuild_roster()
	_refresh_summary()
	_refresh_roster_tasks()
	show()
	set_process(true)
	if tween_on:
		modulate.a = 0.0
		tween_opacity(1.0)
	else:
		if opacity_tween != null:
			opacity_tween.kill()
		modulate.a = 1.0
	_queue_fit()


func hide_unit_detail() -> void:
	_disconnect_unit()
	soldiers.clear()
	casualties.clear()
	soldier_entries_by_soldier.clear()
	casualty_entries_by_casualty.clear()
	set_process(false)
	tween_opacity(0.0).finished.connect(_finish_hiding, CONNECT_ONE_SHOT)


func _finish_hiding() -> void:
	if unit == null:
		hide()


func _disconnect_unit() -> void:
	if is_instance_valid(unit):
		unit.soldiers_changed.disconnect(_on_soldiers_changed)
		unit.state_changed.disconnect(_on_state_changed)
		unit.unit_died.disconnect(_on_unit_removed)
		unit.unit_exited.disconnect(_on_unit_removed)
		unit.stress_system.leadership_changed.disconnect(_on_leadership_changed)
		unit.action_controller.action_state_changed.disconnect(_on_action_state_changed)
	unit = null


func _rebuild_roster() -> void:
	soldiers.assign(unit.squad_fire.soldiers)
	casualties.assign(unit.squad_fire.casualties)
	var total: int = soldiers.size() + casualties.size()
	while soldiers_entries.size() < total:
		var row: Control = soldier_detail_row_scene.instantiate()
		roster_container.add_child(row)
		_roster_rows.append(row)
		var entries: Dictionary[Entry, Control] = {
			Entry.NAME: row.get_node("Identity/Name"),
			Entry.ROLE: row.get_node("Identity/Role"),
			Entry.WEAPON: row.get_node("Activity/Weapon"),
			Entry.TASK: row.get_node("Activity/Task/Label"),
			Entry.PROGRESS_BAR: row.get_node("Activity/Task/Progress"),
		}
		soldiers_entries.append(entries)
	soldier_entries_by_soldier.clear()
	casualty_entries_by_casualty.clear()
	var index: int = 0
	for soldier: Soldier in soldiers:
		_set_roster_row(index, soldier)
		soldier_entries_by_soldier[soldier] = soldiers_entries[index]
		index += 1
	for casualty: Soldier in casualties:
		_set_roster_row(index, casualty)
		casualty_entries_by_casualty[casualty] = soldiers_entries[index]
		index += 1
	for row_index: int in range(index, _roster_rows.size()):
		_roster_rows[row_index].hide()
	roster_section.title = "Soldier roster (%d)" % total


func _set_roster_row(index: int, soldier: Soldier) -> void:
	var entries: Dictionary = soldiers_entries[index]
	entries[Entry.NAME].text = soldier.name
	entries[Entry.ROLE].text = RankGrades.get_role_name(soldier.role)
	entries[Entry.WEAPON].text = soldier.weapon.name
	for key: Entry in [Entry.NAME, Entry.ROLE, Entry.WEAPON]:
		var label: Label = entries[key] as Label
		label.tooltip_text = label.text
	_roster_rows[index].show()


func _refresh_summary() -> void:
	unit_type_label.text = unit.get_hud_name()
	unit_type_label.tooltip_text = unit_type_label.text
	formation_label.text = unit.get_formation_name()
	formation_label.tooltip_text = formation_label.text
	_refresh_command_summary()
	strength_label.text = "%d/%d soldiers" % [unit.squad_fire.soldiers.size(), unit.original_size]
	strength_label.tooltip_text = strength_label.text
	_on_state_changed(unit.stress_system.state)
	order_label.text = "Order: " + _current_order_text()
	order_label.tooltip_text = order_label.text
	cohesion_bar.value = clampf(unit.combat_stats.cohesion_current, 0.0, 1.0)
	effectiveness_bar.value = clampf(unit.combat_stats.combat_effectiveness, 0.0, 1.0)
	cohesion.text = "%.0f%%" % (cohesion_bar.value * 100.0)
	effectiveness.text = "%.0f%%" % (effectiveness_bar.value * 100.0)
	casualty_shock.text = "%.0f%%" % (unit.combat_stats.recent_casualty_shock * 100.0)
	_on_leadership_changed(unit.stress_system.leadership_bonus)


func _refresh_command_summary() -> void:
	var contact: CommandConnectivity.ContactState = CommandConnectivity.contact_state_for(unit)
	command_label.text = "Contact: " + CommandConnectivity.contact_text(contact)
	if not CommandConnectivity.needs_command_contact(unit):
		command_label.text = "Command: Top-level HQ"
	command_label.add_theme_color_override("font_color", CommandConnectivityRenderer.contact_color(contact))
	var commander_name: String = "Unavailable"
	if is_instance_valid(unit.command_squad):
		commander_name = unit.command_squad.get_hud_name() + " · " + unit.command_squad.get_formation_name()
	var presence: float = 0.0
	if CommandConnectivity.has_available_commander(unit):
		presence = unit.command_connectivity.leader_presence_strength
	leadership_presence_label.text = "%d%%" % roundi(clampf(presence, 0.0, 1.0) * 100.0)
	leadership_presence_label.tooltip_text = "Nearby leadership support, separate from communication quality."
	command_label.tooltip_text = "%s\nHQ: %s\nContact method: %s\nLeadership support: %s" % [command_label.text, commander_name, CommandConnectivity.contact_method_for(unit), leadership_presence_label.text]


func _current_order_text() -> String:
	if unit.surrendered:
		return "Surrendered"
	if unit.in_close_combat:
		return "Close combat"
	var actions: SquadActionController = unit.action_controller
	if unit.movement.retreating or actions.action_state == SquadActionController.SquadActionState.ROUTING:
		return "Rout"
	if unit.is_moving or unit.movement.is_moving:
		var destination: Vector2i = unit.movement.target_hex
		var command: String = "Move"
		if actions.has_withdraw_flag:
			command = "Withdraw"
		elif actions.has_attack_flag:
			command = "Attack"
		elif actions.has_take_and_hold_flag:
			command = "Move and hold"
		return "%s to (%d, %d)" % [command, destination.x, destination.y]
	if unit.attackState != Unit.AttackState.AUTO or actions.has_attack_flag:
		if unit.squad_fire.has_target_hex or unit.squad_fire.has_mortar_target_hex:
			var target: Vector2i = unit.squad_fire.target_hex
			if unit.squad_type == Globals.SquadType.MORTAR:
				target = unit.squad_fire.mortar_target_hex
			return "Fire at (%d, %d)" % [target.x, target.y]
	match actions.action_state:
		SquadActionController.SquadActionState.ESTABLISHING_POSITION:
			return "Secure position"
		SquadActionController.SquadActionState.REGROUPING:
			return "Regroup"
		SquadActionController.SquadActionState.NO_ORDER:
			return "No order"
	return "Hold position"


func _refresh_roster_tasks() -> void:
	for soldier: Soldier in soldiers:
		if unit.surrendered:
			set_progress_bar(soldier, "Surrendered", 0.0, 0.0)
		elif not unit.is_good_order():
			set_progress_bar(soldier, unit.get_state_name(int(unit.stress_system.state)), 0.0, 0.0)
		elif unit.is_moving:
			set_progress_bar(soldier, "Moving", 0.0, 0.0)
		elif unit.in_close_combat:
			set_progress_bar(soldier, soldier.close_combat_task.task_name, 0.0, 0.0)
		elif not soldier.setup_weapon_task.done and soldier.setup_weapon_task.remaining_time_s > 0.0:
			_set_soldier_task(soldier, soldier.setup_weapon_task)
		elif not soldier.reload_task.done and soldier.reload_task.remaining_time_s > 0.0:
			_set_soldier_task(soldier, soldier.reload_task)
		elif not soldier.aquire_target_task.done and soldier.aquire_target_task.remaining_time_s > 0.0:
			_set_soldier_task(soldier, soldier.aquire_target_task)
		elif soldier.role == RankGrades.Role.LOADER or soldier.role == RankGrades.Role.ASSISTANT:
			set_progress_bar(soldier, soldier.assist_task.task_name, 0.0, 0.0)
		else:
			set_progress_bar(soldier, "Idle", 0.0, 0.0)
	for casualty: Soldier in casualties:
		_set_task_progress(casualty_entries_by_casualty[casualty], "Incapacitated", 0.0, 0.0)
		casualty_entries_by_casualty[casualty][Entry.TASK].add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))


func _set_soldier_task(soldier: Soldier, task: SoldierTask) -> void:
	set_progress_bar(soldier, task.task_name, task.start_time_s, task.remaining_time_s)


func set_progress_bar(soldier: Soldier, task_name: String, duration_s: float, remaining_s: float) -> void:
	_set_task_progress(soldier_entries_by_soldier[soldier], task_name, duration_s, remaining_s)


func _set_task_progress(entries: Dictionary, task_name: String, duration_s: float, remaining_s: float) -> void:
	var progress: ProgressBar = entries[Entry.PROGRESS_BAR]
	progress.value = 0.0
	progress.visible = duration_s > 0.0
	if duration_s > 0.0:
		progress.value = clampf((duration_s - remaining_s) / duration_s, 0.0, 1.0)
	var label: Label = entries[Entry.TASK]
	label.remove_theme_color_override("font_color")
	label.text = task_name
	label.tooltip_text = task_name


func _on_soldiers_changed() -> void:
	if not is_instance_valid(unit):
		return
	_rebuild_roster()
	_refresh_summary()
	_refresh_roster_tasks()


func _on_state_changed(state: int) -> void:
	if not is_instance_valid(unit):
		return
	unit_status_label.text = unit.get_state_name(state)
	if state == STATES.MoraleState.COMBAT_INEFFECTIVE:
		unit_status_label.text = "Ineffective"
	unit_status_label.tooltip_text = "%s\nStress: %.2f/%.0f\nIncoming stress: +%.2f/s\nRecovery capacity: %.2f/s\nActual recovery: -%.2f/s\nNet stress change: %+.2f/s\nAveraged over the last %.2f s." % [unit_status_label.text, unit.stress_system.S_eff, unit.stress_system.S_CAP, unit.stress_system.incoming_stress_rate, unit.stress_system.recovery_capacity_rate, unit.stress_system.stress_recovery_rate, unit.stress_system.net_stress_rate, unit.stress_system.balance_sample_duration_s]
	var color: Color = Color(0.65, 0.85, 0.55)
	match state:
		STATES.MoraleState.CAUTIOUS:
			color = Color(0.9, 0.78, 0.4)
		STATES.MoraleState.PINNED:
			color = Color(1.0, 0.6, 0.3)
		STATES.MoraleState.PANIC:
			color = Color(1.0, 0.45, 0.45)
		STATES.MoraleState.COMBAT_INEFFECTIVE:
			color = Color(0.75, 0.6, 1.0)
	unit_status_label.add_theme_color_override("font_color", color)
	var rout_available: bool = unit.can_rout()
	if rout_button.disabled == rout_available:
		rout_button.set_rout_available(rout_available)
	rout_explanation.visible = state == STATES.MoraleState.PINNED and not unit.surrendered
	rout_explanation.text = "Pinned: normal movement blocked.\nRout risks surrender."
	if unit.in_close_combat:
		rout_explanation.text = "Pinned in close combat.\nRout is unavailable during this fight."


func _on_leadership_changed(bonus: float) -> void:
	var text: String = "None"
	if bonus >= RankGrades.GRADE_PARAMS[RankGrades.Grade.COMPANY_LEADER].lead:
		text = "+++"
	elif bonus >= RankGrades.GRADE_PARAMS[RankGrades.Grade.PLATOON_LEADER].lead:
		text = "++"
	elif bonus >= RankGrades.GRADE_PARAMS[RankGrades.Grade.SQUAD_LEADER].lead:
		text = "+"
	leadership_bonus_label.text = text


func _on_action_state_changed(_previous: int, _next: int) -> void:
	if is_instance_valid(unit):
		_refresh_summary()


func _on_unit_removed(_removed_unit: Unit) -> void:
	if _removed_unit == unit:
		hide_unit_detail()


func _on_details_folding_changed(is_folded: bool) -> void:
	if not is_folded:
		roster_section.folded = true
	_queue_fit()


func _on_roster_folding_changed(is_folded: bool) -> void:
	if not is_folded:
		details_section.folded = true
	_queue_fit()


func tween_opacity(target: float) -> Tween:
	if opacity_tween != null:
		opacity_tween.kill()
	opacity_tween = create_tween()
	opacity_tween.tween_property(self, "modulate:a", target, 0.15)
	return opacity_tween


func _on_kill_pressed() -> void:
	if is_instance_valid(unit):
		Debug.units_to_kill.append(unit)


func _on_kill_soldier_pressed() -> void:
	if is_instance_valid(unit):
		Debug.units_soldier_to_kill.append(unit)


func _on_surrender_pressed() -> void:
	if is_instance_valid(unit):
		Debug.units_to_surrender.append(unit)


func _on_rout_pressed() -> void:
	if is_instance_valid(unit):
		unit.request_rout()
