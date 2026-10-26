@tool
extends EditorInspectorPlugin

var plugin: EditorPlugin


func _can_handle(object: Object) -> bool:
	return object is Scenario or object is ReinforcementDefinition or (object is Node and (object as Node).name == "Reinforcements")


func _parse_begin(object: Object) -> void:
	if object is ReinforcementDefinition:
		return
	var scenario: Node = object as Node
	if not object is Scenario:
		scenario = scenario.get_parent()
	if not scenario is Scenario:
		return
	var button: Button = Button.new()
	button.text = "Add Reinforcement"
	button.pressed.connect(plugin.add_reinforcement.bind(scenario))
	add_custom_control(button)


func _parse_property(object: Object, _type: Variant.Type, name: String, _hint: PropertyHint, _hint_string: String, _usage: int, _wide: bool) -> bool:
	if not object is ReinforcementDefinition or name != "unit_ids":
		return false
	var property: EditorProperty = preload("res://addons/reinforcements/unit_property.gd").new()
	property.plugin = plugin
	add_property_editor(name, property)
	return true
