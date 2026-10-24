extends Node2D
class_name BattlefieldStacks

var controller: Node2D


func _ready() -> void:
	set_process(false)


func setup(match_controller: Node2D) -> void:
	controller = match_controller


func cycle_selection(cell: Vector2i, picked: Unit = null) -> bool:
	if not is_instance_valid(controller) or controller.end_game_handled:
		return false
	var members: Array[Unit] = []
	for unit: Unit in Globals.get_units_for_team(Globals.team_player):
		if _can_show_unit(unit) and unit.current_hex == cell:
			members.append(unit)
	if members.size() < 2:
		return false
	members.sort_custom(_formation_less)
	var index: int = -1
	if is_instance_valid(controller.selected_unit):
		index = members.find(controller.selected_unit)
	if index >= 0:
		index = (index + 1) % members.size()
	else:
		index = maxi(0, members.find(picked))
	# Repeated clicks cycle through the existing counters without opening a panel.
	controller._select_unit(members[index])
	controller.show_unit_details_in_ui.emit(members[index])
	LOSHelper.clear_los()
	return true


static func _can_show_unit(unit: Unit) -> bool:
	return is_instance_valid(unit) and unit.is_active() and not unit.is_queued_for_deletion() and unit.team == Globals.team_player and unit.is_visible_in_tree() and is_instance_valid(unit.ui) and unit.ui.is_visible_in_tree()


static func counter_rect(unit: Unit) -> Rect2:
	var sprite: TextureRect = unit.ui.sprite_node
	return sprite.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, sprite.size)


static func _formation_less(a: Unit, b: Unit) -> bool:
	if a.company != b.company:
		return a.company < b.company
	if a.platoon != b.platoon:
		return a.platoon < b.platoon
	if a.squad != b.squad:
		return a.squad < b.squad
	return a.get_instance_id() < b.get_instance_id()
