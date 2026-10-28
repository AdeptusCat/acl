extends PanelContainer
class_name SquadRosterPanel

signal unit_selected(unit: Unit)
signal layout_requested

const ROW_SCENE: PackedScene = preload("res://scenes/ui/units/squad_roster_row.tscn")
const PANEL_WIDTH: float = 340.0
const REFRESH_INTERVAL_S: float = 0.25

@onready var section: FoldableContainer = $Roster
@onready var scroll: ScrollContainer = $Roster/Content/Scroll
@onready var groups: VBoxContainer = $Roster/Content/Scroll/Groups

var player_team: Globals.Team = Globals.Team.AXIS
var rows: Dictionary[Unit, SquadRosterRow] = {}
var company_branches: Dictionary[int, FoldableContainer] = {}
var platoon_branches: Dictionary[Vector2i, FoldableContainer] = {}
var _formation_signature: String = ""
var _focused_unit_id: int = 0
var _refresh_elapsed_s: float = 0.0
var _pending_reveal: Unit
var _reveal_queued: bool = false


func _ready() -> void:
	set_process(false)
	section.folding_changed.connect(_on_folding_changed)
	groups.minimum_size_changed.connect(_request_layout)
	minimum_size_changed.connect(_request_layout)


func setup(team: Globals.Team) -> void:
	player_team = team
	_formation_signature = ""
	_focused_unit_id = 0
	_refresh_elapsed_s = 0.0
	section.expand()
	refresh()
	show()
	set_process(true)
	_request_layout()


func _process(delta: float) -> void:
	_refresh_elapsed_s += delta
	if _refresh_elapsed_s >= REFRESH_INTERVAL_S:
		_refresh_elapsed_s = 0.0
		refresh()


func refresh() -> void:
	var units: Array[Unit] = []
	var candidates: Array[Unit] = Globals.get_units()
	for unit: Unit in get_tree().get_nodes_in_group("dead_units"):
		if not candidates.has(unit):
			candidates.append(unit)
	for unit: Unit in candidates:
		if is_instance_valid(unit) and unit.team == player_team and not unit.exited and not unit.is_queued_for_deletion():
			units.append(unit)
	units.sort_custom(_formation_less)
	var signature: String = "empty"
	for unit: Unit in units:
		var group: Vector2i = _group_key(unit)
		signature += ":%d/%d/%d/%d" % [unit.get_instance_id(), group.x, group.y, unit.squad]
	var rebuilt: bool = signature != _formation_signature
	if rebuilt:
		_formation_signature = signature
		_rebuild_groups(units)
	section.title = "Squads · %d" % units.size()
	var selected: Unit
	for unit: Unit in rows:
		rows[unit].refresh()
		if unit.selected and (selected == null or unit.get_instance_id() == _focused_unit_id):
			selected = unit
	if selected != null:
		if rebuilt or selected.get_instance_id() != _focused_unit_id:
			_expand_selected_branch(selected)
	else:
		_focused_unit_id = 0


func get_minimum_height() -> float:
	if section.folded:
		return get_combined_minimum_size().y
	var overhead: float = maxf(0.0, get_combined_minimum_size().y - scroll.get_combined_minimum_size().y)
	var content_height: float = 32.0
	for group: Vector2i in platoon_branches:
		var branch: FoldableContainer = platoon_branches[group]
		if not branch.folded and not company_branches[group.x].folded:
			content_height = maxf(content_height, branch.get_combined_minimum_size().y)
	return overhead + minf(content_height, groups.get_combined_minimum_size().y)


func focus_unit(unit: Unit) -> void:
	if not is_instance_valid(unit) or not unit.is_active() or unit.team != player_team:
		return
	refresh()
	if not rows.has(unit):
		return
	_expand_selected_branch(unit)
	_pending_reveal = unit
	section.expand()
	if not _reveal_queued:
		_reveal_queued = true
		_reveal_selected.call_deferred()


func _reveal_selected() -> void:
	# Folding, roster rebuilds and HUD resizing defer their container layouts.
	await get_tree().process_frame
	await get_tree().process_frame
	_reveal_queued = false
	if is_instance_valid(_pending_reveal) and _pending_reveal.selected and rows.has(_pending_reveal):
		var target: Control = rows[_pending_reveal]
		var group: Vector2i = _group_key(_pending_reveal)
		if _pending_reveal.squad_type != Globals.SquadType.COMPANY_HEADQUARTERS and platoon_branches.has(group):
			var branch: FoldableContainer = platoon_branches[group]
			if branch.size.y <= scroll.size.y:
				target = branch
		scroll.ensure_control_visible(target)
	_pending_reveal = null


func get_preferred_height() -> float:
	if section.folded:
		return get_combined_minimum_size().y
	var overhead: float = maxf(0.0, get_combined_minimum_size().y - scroll.get_combined_minimum_size().y)
	return overhead + groups.get_combined_minimum_size().y


func fit_panel(panel_position: Vector2, max_height: float) -> void:
	if not section.folded:
		var content_height: float = groups.get_combined_minimum_size().y
		# Reserve the actual title, column labels and margins; only the rows scroll.
		var overhead: float = maxf(0.0, get_combined_minimum_size().y - scroll.get_combined_minimum_size().y)
		var scroll_height: float = maxf(0.0, max_height - overhead)
		scroll.custom_minimum_size.y = minf(scroll_height, content_height)
	custom_minimum_size.x = PANEL_WIDTH
	size = Vector2(PANEL_WIDTH, get_combined_minimum_size().y)
	position = panel_position


func _rebuild_groups(units: Array[Unit]) -> void:
	var scroll_position: int = scroll.scroll_vertical
	var expanded_companies: Array[int] = []
	var expanded_platoons: Array[Vector2i] = []
	for company: int in company_branches:
		if not company_branches[company].folded:
			expanded_companies.append(company)
	for group: Vector2i in platoon_branches:
		if not platoon_branches[group].folded:
			expanded_platoons.append(group)
	rows.clear()
	company_branches.clear()
	platoon_branches.clear()
	for child: Node in groups.get_children():
		groups.remove_child(child)
		child.queue_free()
	for unit: Unit in units:
		var group: Vector2i = _group_key(unit)
		if not company_branches.has(group.x):
			var company_branch: FoldableContainer = _create_branch("Company %s" % Unit.COMPANY_NAMES[unit.company], groups)
			company_branch.folded = not expanded_companies.has(group.x)
			company_branches[group.x] = company_branch
			company_branch.folding_changed.connect(_on_company_folding_changed.bind(group.x))
		var row_parent: VBoxContainer = company_branches[group.x].get_node("Indent/Content") as VBoxContainer
		if unit.squad_type != Globals.SquadType.COMPANY_HEADQUARTERS:
			if not platoon_branches.has(group):
				var platoon_branch: FoldableContainer = _create_branch("Platoon %d" % group.y, row_parent)
				platoon_branch.folded = not expanded_platoons.has(group)
				platoon_branches[group] = platoon_branch
				platoon_branch.folding_changed.connect(_on_platoon_folding_changed.bind(group))
			row_parent = platoon_branches[group].get_node("Indent/Content") as VBoxContainer
		var row: SquadRosterRow = ROW_SCENE.instantiate() as SquadRosterRow
		row.unit = unit
		row_parent.add_child(row)
		row.pressed.connect(_on_row_pressed.bind(row))
		rows[unit] = row
	if units.is_empty():
		var empty: Label = Label.new()
		empty.text = "No squads"
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		groups.add_child(empty)
	scroll.set_deferred("scroll_vertical", scroll_position)
	_request_layout()


func _create_branch(title: String, parent: VBoxContainer) -> FoldableContainer:
	var branch: FoldableContainer = FoldableContainer.new()
	branch.title = title
	branch.folded = true
	branch.mouse_filter = Control.MOUSE_FILTER_STOP
	branch.mouse_force_pass_scroll_events = true
	branch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(branch)
	var indent: MarginContainer = MarginContainer.new()
	indent.name = "Indent"
	indent.mouse_filter = Control.MOUSE_FILTER_PASS
	indent.add_theme_constant_override("margin_left", 10)
	branch.add_child(indent)
	var content: VBoxContainer = VBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_theme_constant_override("separation", 2)
	indent.add_child(content)
	return branch


func _expand_selected_branch(unit: Unit) -> void:
	_focused_unit_id = unit.get_instance_id()
	var selected_group: Vector2i = _group_key(unit)
	if _multiple_selection_active():
		company_branches[selected_group.x].expand()
		if platoon_branches.has(selected_group):
			platoon_branches[selected_group].expand()
		_request_layout()
		return
	for company: int in company_branches:
		company_branches[company].folded = company != selected_group.x
	for group: Vector2i in platoon_branches:
		platoon_branches[group].folded = group != selected_group or unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS
	_request_layout()


func _on_company_folding_changed(folded: bool, company: int) -> void:
	if _multiple_selection_active():
		_request_layout()
		return
	if not folded:
		for other: int in company_branches:
			if other != company:
				company_branches[other].fold()
	for group: Vector2i in platoon_branches:
		if (group.x == company and folded) or (group.x != company and not folded):
			platoon_branches[group].fold()
	_request_layout()


func _on_platoon_folding_changed(folded: bool, selected_group: Vector2i) -> void:
	if _multiple_selection_active():
		_request_layout()
		return
	if not folded:
		for group: Vector2i in platoon_branches:
			if group != selected_group:
				platoon_branches[group].fold()
	_request_layout()


func _group_key(unit: Unit) -> Vector2i:
	if unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
		return Vector2i(unit.company, 0)
	return Vector2i(unit.company, unit.platoon)


func _multiple_selection_active() -> bool:
	var count: int = 0
	for member: Unit in rows:
		if is_instance_valid(member) and member.selected:
			count += 1
			if count > 1:
				return true
	return false


func _formation_less(left: Unit, right: Unit) -> bool:
	var left_group: Vector2i = _group_key(left)
	var right_group: Vector2i = _group_key(right)
	if left_group.x != right_group.x:
		return left_group.x < right_group.x
	if left_group.y != right_group.y:
		return left_group.y < right_group.y
	if left.squad != right.squad:
		return left.squad < right.squad
	return left.get_instance_id() < right.get_instance_id()


func _on_row_pressed(row: SquadRosterRow) -> void:
	# A squad can disappear between the last refresh and a button press.
	if not is_instance_valid(row.unit):
		refresh()
		return
	var unit: Unit = row.unit
	if not unit.is_active() or unit.is_queued_for_deletion() or unit.team != player_team:
		refresh()
		return
	unit_selected.emit(unit)
	for member: Unit in rows:
		rows[member].set_pressed_no_signal(member.selected)


func _on_folding_changed(_folded: bool) -> void:
	_request_layout()


func _request_layout() -> void:
	layout_requested.emit()
