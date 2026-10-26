@tool
extends EditorProperty

var plugin: EditorPlugin
var _rows: VBoxContainer = VBoxContainer.new()


func _init() -> void:
	add_child(_rows)
	set_bottom_editor(_rows)


func _update_property() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var definition: ReinforcementDefinition = get_edited_object() as ReinforcementDefinition
	if definition == null or definition.get_parent() == null:
		return
	var scenario: Node = definition.get_parent().get_parent()
	var units: Node = scenario.get_node_or_null("Units")
	var hint: Label = Label.new()
	hint.text = "Create units under Mission / Units first.\nArrival uses each unit's map position."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(hint)
	if units == null:
		return
	var claimed: Dictionary[String, bool] = {}
	for sibling: Node in definition.get_parent().get_children():
		if sibling is ReinforcementDefinition and sibling != definition:
			for id: String in (sibling as ReinforcementDefinition).unit_ids:
				claimed[id] = true
	for child: Node in units.get_children():
		var unit: Unit = child as Unit
		if unit == null or unit.team != definition.team:
			continue
		var row: HBoxContainer = HBoxContainer.new()
		_rows.add_child(row)
		var check: CheckBox = CheckBox.new()
		check.text = str(unit.name)
		check.tooltip_text = unit.map_unit_id
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.button_pressed = definition.unit_ids.has(unit.map_unit_id)
		check.disabled = unit.map_unit_id.is_empty() or claimed.has(unit.map_unit_id)
		if claimed.has(unit.map_unit_id):
			check.text += " (assigned)"
		check.toggled.connect(_toggle.bind(unit.map_unit_id))
		row.add_child(check)
		var locate: Button = Button.new()
		locate.text = "Locate"
		locate.pressed.connect(_locate.bind(unit))
		row.add_child(locate)


func _toggle(selected: bool, id: String) -> void:
	var definition: ReinforcementDefinition = get_edited_object() as ReinforcementDefinition
	var ids: PackedStringArray = definition.unit_ids.duplicate()
	if selected and not ids.has(id):
		ids.append(id)
	elif not selected:
		var index: int = ids.find(id)
		if index >= 0:
			ids.remove_at(index)
	emit_changed(get_edited_property(), ids)


func _locate(unit: Unit) -> void:
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(unit)
	EditorInterface.edit_node(unit)
