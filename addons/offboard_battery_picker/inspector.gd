@tool
extends EditorInspectorPlugin

const WEAPON_PROPERTY: Script = preload("res://addons/offboard_battery_picker/weapon_property.gd")


func _can_handle(object: Object) -> bool:
	return object is OffboardBattery


func _parse_property(_object: Object, _type: Variant.Type, name: String, _hint_type: PropertyHint, _hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	if name != "weapon":
		return false
	add_property_editor(name, WEAPON_PROPERTY.new())
	return true
