extends PanelContainer
class_name SquadRosterPanel

signal unit_selected(unit: Unit)
signal layout_requested

const ROW_SCENE: PackedScene = preload("res://scenes/ui/units/squad_roster_row.tscn")
const PANEL_WIDTH: float = 252.0
const SCROLL_HEIGHT: float = 176.0
const REFRESH_INTERVAL_S: float = 0.25

@onready var section: FoldableContainer = $Roster
@onready var scroll: ScrollContainer = $Roster/Content/Scroll
@onready var groups: VBoxContainer = $Roster/Content/Scroll/Groups

var player_team: Globals.Team = Globals.Team.AXIS
var rows: Dictionary[Unit, SquadRosterRow] = {}
var _formation_signature: String = ""
var _refresh_elapsed_s: float = 0.0


func _ready() -> void:
	set_process(false)
	section.folding_changed.connect(_on_folding_changed)
	minimum_size_changed.connect(_request_layout)


func setup(team: Globals.Team) -> void:
	player_team = team
	_formation_signature = ""
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
	for unit: Unit in Globals.get_units_for_team(player_team):
		if unit.is_active() and not unit.is_queued_for_deletion():
			units.append(unit)
	units.sort_custom(_formation_less)
	var signature: String = "empty"
	for unit: Unit in units:
		var group: Vector2i = _group_key(unit)
		signature += ":%d/%d/%d/%d" % [unit.get_instance_id(), group.x, group.y, unit.squad]
	if signature != _formation_signature:
		_formation_signature = signature
		_rebuild_groups(units)
	section.title = "Squads · %d" % units.size()
	for unit: Unit in rows:
		rows[unit].refresh()


func fit_panel(panel_position: Vector2, max_height: float) -> void:
	var content_height: float = groups.get_combined_minimum_size().y
	# Reserve the actual title, column labels and margins; only the rows scroll.
	var overhead: float = maxf(0.0, get_combined_minimum_size().y - scroll.get_combined_minimum_size().y)
	var scroll_height: float = minf(SCROLL_HEIGHT, maxf(32.0, max_height - overhead))
	scroll.custom_minimum_size.y = minf(scroll_height, content_height)
	custom_minimum_size.x = PANEL_WIDTH
	size = Vector2(PANEL_WIDTH, get_combined_minimum_size().y)
	position = panel_position


func _rebuild_groups(units: Array[Unit]) -> void:
	var scroll_position: int = scroll.scroll_vertical
	rows.clear()
	for child: Node in groups.get_children():
		groups.remove_child(child)
		child.queue_free()
	var previous_group: Vector2i = Vector2i(-1, -1)
	var platoon_rows: VBoxContainer
	for unit: Unit in units:
		var group: Vector2i = _group_key(unit)
		if group != previous_group:
			previous_group = group
			platoon_rows = VBoxContainer.new()
			platoon_rows.mouse_filter = Control.MOUSE_FILTER_PASS
			platoon_rows.add_theme_constant_override("separation", 2)
			groups.add_child(platoon_rows)
			var heading: Label = Label.new()
			heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
			heading.add_theme_color_override("font_color", Color(0.8, 0.65, 0.45))
			heading.add_theme_font_size_override("font_size", 11)
			heading.text = "Company %s · Platoon %d" % [Unit.COMPANY_NAMES[unit.company], group.y]
			if group.y == 0:
				heading.text = "Company %s · Headquarters" % Unit.COMPANY_NAMES[unit.company]
			platoon_rows.add_child(heading)
		var row: SquadRosterRow = ROW_SCENE.instantiate() as SquadRosterRow
		row.unit = unit
		platoon_rows.add_child(row)
		row.pressed.connect(_on_row_pressed.bind(row))
		rows[unit] = row
	if units.is_empty():
		var empty: Label = Label.new()
		empty.text = "No active squads"
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		groups.add_child(empty)
	scroll.set_deferred("scroll_vertical", scroll_position)
	_request_layout()


func _group_key(unit: Unit) -> Vector2i:
	if unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
		return Vector2i(unit.company, 0)
	return Vector2i(unit.company, unit.platoon)


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
