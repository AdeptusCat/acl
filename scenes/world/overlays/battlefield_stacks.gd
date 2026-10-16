extends Node2D
class_name BattlefieldStacks

const ROSTER_SCENE: PackedScene = preload("res://scenes/ui/units/hex_stack_roster.tscn")

var controller: Node2D
var roster: HexStackRoster
var _units_by_hex: Dictionary[Vector2i, Array] = {}


func _ready() -> void:
	set_process(false)


func setup(match_controller: Node2D, hud_control: Control) -> void:
	controller = match_controller
	roster = ROSTER_SCENE.instantiate() as HexStackRoster
	hud_control.add_child(roster)
	roster.unit_selected.connect(_on_unit_selected)
	set_process(true)
	refresh()


func _exit_tree() -> void:
	if is_instance_valid(roster):
		roster.queue_free()


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	_units_by_hex.clear()
	if not is_instance_valid(controller) or not is_instance_valid(controller.ground_layer) or controller.end_game_handled:
		roster.close()
		return
	# Keep the existing, slightly offset counters exactly as they are. Only the
	# roster displays additional unit information; it never moves gameplay nodes.
	for unit: Unit in Globals.get_units_for_team(Globals.team_player):
		if not unit.unit_entered_hex.is_connected(_on_unit_entered_hex):
			unit.unit_entered_hex.connect(_on_unit_entered_hex)
		if not _can_show_unit(unit):
			continue
		if not _units_by_hex.has(unit.current_hex):
			_units_by_hex[unit.current_hex] = []
		_units_by_hex[unit.current_hex].append(unit)
	if roster.visible:
		var members: Array[Unit] = _members_at(roster.cell)
		if members.size() < 2 or not _has_selected_member(members):
			roster.close()
		else:
			roster.refresh_members(members)
			_fit_roster(members)


func _members_at(cell: Vector2i) -> Array[Unit]:
	var members: Array[Unit] = []
	members.assign(_units_by_hex.get(cell, []))
	members.sort_custom(_formation_less)
	return members


func open_roster(cell: Vector2i) -> bool:
	refresh()
	var members: Array[Unit] = _members_at(cell)
	if members.size() < 2 or not _has_selected_member(members):
		return false
	roster.open(cell, members)
	_fit_roster(members)
	roster.reveal_unit(controller.selected_unit)
	return true


func cycle_roster(cell: Vector2i, picked: Unit = null) -> bool:
	refresh()
	var members: Array[Unit] = _members_at(cell)
	if members.size() < 2:
		return false
	var index: int = -1
	if is_instance_valid(controller.selected_unit):
		index = members.find(controller.selected_unit)
	if index >= 0:
		index = (index + 1) % members.size()
	else:
		index = maxi(0, members.find(picked))
	# A stack click selects its member before requesting that stack's roster.
	controller._select_unit(members[index])
	controller.show_unit_details_in_ui.emit(members[index])
	LOSHelper.clear_los()
	return open_roster(cell)


func _has_selected_member(members: Array[Unit]) -> bool:
	return is_instance_valid(controller.selected_unit) and members.has(controller.selected_unit)


func _on_unit_entered_hex(unit: Unit, cell: Vector2i) -> void:
	if not _can_show_unit(unit) or unit.current_hex != cell:
		return
	# Opening the roster observes movement; it never selects or orders a squad.
	open_roster(cell)


static func _can_show_unit(unit: Unit) -> bool:
	return is_instance_valid(unit) and unit.is_active() and not unit.is_queued_for_deletion() and unit.team == Globals.team_player and unit.is_visible_in_tree() and is_instance_valid(unit.ui) and unit.ui.is_visible_in_tree()


static func counter_rect(unit: Unit) -> Rect2:
	var sprite: TextureRect = unit.ui.sprite_node
	return sprite.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, sprite.size)


func _fit_roster(members: Array[Unit]) -> void:
	var anchor: Rect2 = counter_rect(members[0])
	var command_rect: Rect2
	for unit: Unit in members:
		anchor = anchor.merge(counter_rect(unit))
		if unit.selected and CommandConnectivity.has_available_commander(unit):
			var commander: Unit = unit.command_squad
			if commander.is_visible_in_tree() and is_instance_valid(commander.ui) and commander.ui.is_visible_in_tree():
				command_rect = counter_rect(unit).merge(counter_rect(commander)).grow(12.0)
				if unit.current_hex == commander.current_hex:
					# Leave space for the renderer's local command loop.
					command_rect.size.x += 70.0
	roster.fit_to_anchor(anchor, command_rect)


func _on_unit_selected(unit: Unit) -> void:
	if not is_instance_valid(unit) or not unit.is_active() or unit.team != Globals.team_player or not roster.visible or unit.current_hex != roster.cell:
		return
	controller._select_unit(unit)
	controller.show_unit_details_in_ui.emit(unit)
	LOSHelper.clear_los()
	refresh()
	roster.reveal_unit(unit)


static func _formation_less(a: Unit, b: Unit) -> bool:
	if a.company != b.company:
		return a.company < b.company
	if a.platoon != b.platoon:
		return a.platoon < b.platoon
	if a.squad != b.squad:
		return a.squad < b.squad
	return a.get_instance_id() < b.get_instance_id()
