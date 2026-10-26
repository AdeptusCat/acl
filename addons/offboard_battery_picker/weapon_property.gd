@tool
extends EditorProperty

var _choices: OptionButton
var _weapons: Array[WeaponSpec] = []


func _init() -> void:
	_choices = OptionButton.new()
	_choices.fit_to_longest_item = false
	_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices.clip_text = true
	_choices.tooltip_text = "Choose a WeaponSpec from the Mortar or Howitzer family."
	_choices.item_selected.connect(_select_weapon)
	_choices.get_popup().about_to_popup.connect(_refresh_choices)
	add_child(_choices)
	add_focusable(_choices)


func _update_property() -> void:
	_refresh_choices()


func _refresh_choices() -> void:
	var battery: OffboardBattery = get_edited_object() as OffboardBattery
	if battery == null:
		return
	_weapons.clear()
	_collect_weapons(EditorInterface.get_resource_filesystem().get_filesystem())
	# Preserve an eligible embedded/custom resource already assigned to this battery.
	if _eligible(battery.weapon) and not _weapons.has(battery.weapon):
		_weapons.append(battery.weapon)
	_weapons.sort_custom(_sort_weapons)
	_choices.clear()
	_choices.add_item("None", 0)
	var selected: int = 0
	for index: int in range(_weapons.size()):
		var weapon: WeaponSpec = _weapons[index]
		_choices.add_item(_label(weapon), index + 1)
		_choices.set_item_tooltip(index + 1, weapon.resource_path)
		if weapon == battery.weapon:
			selected = index + 1
	if battery.weapon != null and selected == 0:
		_choices.add_item("Current: " + battery.weapon.name + " (unsupported family)")
		selected = _choices.item_count - 1
		_choices.set_item_disabled(selected, true)
	_choices.select(selected)
	_choices.disabled = is_read_only()


func _collect_weapons(directory: EditorFileSystemDirectory) -> void:
	for index: int in range(directory.get_subdir_count()):
		_collect_weapons(directory.get_subdir(index))
	for index: int in range(directory.get_file_count()):
		var path: String = directory.get_file_path(index)
		if path.get_extension() != "tres" and path.get_extension() != "res":
			continue
		var dependencies: PackedStringArray = ResourceLoader.get_dependencies(path)
		var is_weapon: bool = false
		for dependency: String in dependencies:
			if dependency.ends_with("/weapon_spec.gd"):
				is_weapon = true
				break
		if not is_weapon:
			continue
		var weapon: WeaponSpec = load(path) as WeaponSpec
		if _eligible(weapon):
			_weapons.append(weapon)


func _eligible(weapon: WeaponSpec) -> bool:
	return weapon != null and (weapon.family == WeaponSpec.Family.MORTAR or weapon.family == WeaponSpec.Family.HOWITZER)


func _label(weapon: WeaponSpec) -> String:
	var family: String = "Mortar"
	if weapon.family == WeaponSpec.Family.HOWITZER:
		family = "Howitzer"
	return family + " · " + weapon.name + " (" + weapon.resource_path.get_file().get_basename() + ")"


func _sort_weapons(left: WeaponSpec, right: WeaponSpec) -> bool:
	return _label(left).naturalnocasecmp_to(_label(right)) < 0


func _select_weapon(index: int) -> void:
	if is_read_only():
		return
	if index == 0:
		emit_changed(get_edited_property(), null)
	elif index <= _weapons.size():
		emit_changed(get_edited_property(), _weapons[index - 1])
