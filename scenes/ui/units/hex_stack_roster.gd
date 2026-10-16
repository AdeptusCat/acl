extends PanelContainer
class_name HexStackRoster

signal unit_selected(unit: Unit)

const ROW_SCENE: PackedScene = preload("res://scenes/ui/units/squad_roster_row.tscn")
const PANEL_WIDTH: float = 340.0
const MARGIN: float = 12.0

@onready var heading: Label = $Content/Heading/Title
@onready var hex_label: Label = $Content/Hex
@onready var scroll: ScrollContainer = $Content/Scroll
@onready var row_container: VBoxContainer = $Content/Scroll/Rows

var cell: Vector2i
var rows: Dictionary[int, SquadRosterRow] = {}
var _member_ids: Array[int] = []


func _ready() -> void:
	$Content/Heading/Close.pressed.connect(close)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if not Rect2(Vector2.ZERO, size).has_point(point):
			# Leave this event available for normal HUD or battlefield handling.
			close()


func open(hex: Vector2i, members: Array[Unit]) -> void:
	if not visible or cell != hex:
		scroll.scroll_vertical = 0
	cell = hex
	hex_label.text = "Hex (%d, %d)" % [cell.x, cell.y]
	show()
	refresh_members(members)


func close() -> void:
	hide()
	# Hidden rows must not retain dead or removed Unit references.
	_clear_rows()


func refresh_members(members: Array[Unit]) -> void:
	if members.size() < 2:
		close()
		return
	var ids: Array[int] = []
	for unit: Unit in members:
		ids.append(unit.get_instance_id())
	if ids != _member_ids:
		_clear_rows()
		_member_ids.assign(ids)
		for unit: Unit in members:
			var row: SquadRosterRow = ROW_SCENE.instantiate() as SquadRosterRow
			row.unit = unit
			row.stack_row = true
			row.custom_minimum_size.y = 64.0
			row_container.add_child(row)
			rows[unit.get_instance_id()] = row
			row.pressed.connect(_on_row_pressed.bind(row))
	heading.text = "Squads in hex"
	for row: SquadRosterRow in rows.values():
		row.refresh()


func _clear_rows() -> void:
	rows.clear()
	_member_ids.clear()
	for child: Node in row_container.get_children():
		row_container.remove_child(child)
		child.queue_free()


func fit_to_anchor(screen_rect: Rect2, command_rect: Rect2 = Rect2()) -> void:
	var hud: Control = get_parent() as Control
	var available: Vector2 = hud.size - Vector2(MARGIN, MARGIN) * 2.0
	custom_minimum_size.x = minf(PANEL_WIDTH, maxf(0.0, available.x))
	var overhead: float = maxf(0.0, get_combined_minimum_size().y - scroll.get_combined_minimum_size().y)
	scroll.custom_minimum_size.y = minf(row_container.get_combined_minimum_size().y, maxf(32.0, minf(330.0, available.y - overhead)))
	size = Vector2(custom_minimum_size.x, get_combined_minimum_size().y)
	var screen_to_hud: Transform2D = hud.get_global_transform_with_canvas().affine_inverse()
	var anchor: Rect2 = screen_to_hud * screen_rect
	var avoid: Rect2 = screen_to_hud * command_rect
	var candidates: Array[Vector2] = [
		Vector2(anchor.end.x + MARGIN, anchor.position.y),
		Vector2(anchor.position.x - size.x - MARGIN, anchor.position.y),
		Vector2(anchor.position.x, anchor.end.y + MARGIN),
		Vector2(anchor.position.x, anchor.position.y - size.y - MARGIN),
		Vector2(anchor.end.x + MARGIN, anchor.end.y + MARGIN),
		Vector2(anchor.end.x + MARGIN, anchor.position.y - size.y - MARGIN),
		Vector2(anchor.position.x - size.x - MARGIN, anchor.end.y + MARGIN),
		Vector2(anchor.position.x - size.x - MARGIN, anchor.position.y - size.y - MARGIN),
	]
	var best_counter_overlap: float = INF
	var best_command_overlap: float = INF
	for candidate: Vector2 in candidates:
		candidate.x = clampf(candidate.x, MARGIN, maxf(MARGIN, hud.size.x - size.x - MARGIN))
		candidate.y = clampf(candidate.y, MARGIN, maxf(MARGIN, hud.size.y - size.y - MARGIN))
		var rect: Rect2 = Rect2(candidate, size)
		var counter_overlap: float = rect.intersection(anchor).get_area()
		var command_overlap: float = 0.0
		if command_rect.has_area():
			command_overlap = rect.intersection(avoid).get_area()
		if counter_overlap < best_counter_overlap or (is_equal_approx(counter_overlap, best_counter_overlap) and command_overlap < best_command_overlap):
			best_counter_overlap = counter_overlap
			best_command_overlap = command_overlap
			position = candidate


func _on_row_pressed(row: SquadRosterRow) -> void:
	if is_instance_valid(row.unit) and row.unit.is_active() and not row.unit.is_queued_for_deletion() and row.unit.current_hex == cell:
		unit_selected.emit(row.unit)
