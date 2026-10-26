extends Control
class_name FireSupportPanel

var support: FireSupportController
var toggle: Button
var tray: PanelContainer
var assets: OptionButton
var mode: OptionButton
var target_label: Label
var status_label: Label
var fire_button: Button
var cease_button: Button
var locate_button: Button
var pick_button: Button
var _refresh_elapsed: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 8
	toggle = Button.new()
	toggle.text = "Fire Support [F]"
	toggle.custom_minimum_size = Vector2(180, 34)
	toggle.pressed.connect(toggle_tray)
	add_child(toggle)
	tray = PanelContainer.new()
	tray.custom_minimum_size.x = 430.0
	tray.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(tray)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	tray.add_child(content)
	var title: Label = Label.new()
	title.text = "Fire support · HE"
	title.theme_type_variation = &"HudHeading"
	content.add_child(title)
	assets = OptionButton.new()
	assets.fit_to_longest_item = false
	assets.clip_text = true
	assets.item_selected.connect(_select_asset)
	content.add_child(assets)
	mode = OptionButton.new()
	for name: String in FireSupportMission.MODE_NAMES:
		mode.add_item(name)
	mode.item_selected.connect(_select_mode)
	content.add_child(mode)
	var actions: HBoxContainer = HBoxContainer.new()
	content.add_child(actions)
	pick_button = Button.new()
	pick_button.text = "Choose target"
	pick_button.pressed.connect(_choose_target)
	actions.add_child(pick_button)
	locate_button = Button.new()
	locate_button.text = "Locate mortar"
	locate_button.pressed.connect(_locate)
	actions.add_child(locate_button)
	target_label = Label.new()
	target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(target_label)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status_label)
	var controls: HBoxContainer = HBoxContainer.new()
	content.add_child(controls)
	fire_button = Button.new()
	fire_button.text = "Fire mission [Enter]"
	fire_button.pressed.connect(_fire)
	controls.add_child(fire_button)
	cease_button = Button.new()
	cease_button.text = "Cease fire"
	cease_button.pressed.connect(_cease)
	controls.add_child(cease_button)
	var close: Button = Button.new()
	close.text = "Close"
	close.pressed.connect(_close)
	controls.add_child(close)
	var hint: Label = Label.new()
	hint.text = "Harassing: one round every 15–25 s until ceased or empty."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.theme_type_variation = &"HudSecondary"
	content.add_child(hint)
	tray.hide()
	get_parent().resized.connect(_layout)
	refresh()
	_layout()

func toggle_tray() -> void:
	if tray.visible:
		_close()
	else:
		tray.show()
		support.choosing_target = not support.has_target and not support.assets.is_empty()
		refresh()

func _close() -> void:
	tray.hide()
	support.choosing_target = false
	support.has_target = false
	LOSHelper.clear_los()
	support.queue_redraw()

func _choose_target() -> void:
	support.choosing_target = true
	support.has_target = false
	refresh()

func _select_asset(index: int) -> void:
	support.selected_asset = index
	refresh()

func _select_mode(index: int) -> void:
	support.selected_mode = index as FireSupportMission.Mode
	refresh()

func _locate() -> void:
	if support.selected_asset < support.assets.size():
		var unit: Unit = support.assets[support.selected_asset]["unit"]
		if is_instance_valid(unit):
			support.host.move_camera(unit.current_hex)

func _fire() -> void:
	if not support.has_target:
		return
	if support.request(support.selected_asset, support.target, support.selected_mode):
		support.host.get_parent().ui.hide_target_hex_cover_distance()
	refresh()

func _cease() -> void:
	support.cease(support.selected_asset)
	refresh()

func refresh() -> void:
	if not is_node_ready():
		return
	var selection: int = support.selected_asset
	if assets.item_count != support.assets.size():
		assets.clear()
		for asset: Dictionary in support.assets:
			assets.add_item(str(asset["name"]))
	for index: int in range(support.assets.size()):
		assets.set_item_text(index, "%s · %s · %d rounds" % [support.assets[index]["name"], support.asset_status(index), support.ammunition(index)])
	if not support.assets.is_empty():
		assets.select(clampi(selection, 0, support.assets.size() - 1))
	assets.disabled = support.assets.is_empty()
	pick_button.disabled = support.assets.is_empty()
	mode.disabled = support.assets.is_empty()
	toggle.text = "Fire Support [F] · %d" % support.assets.size()
	target_label.text = "Click a battlefield hex to choose the target."
	if support.has_target:
		target_label.text = "Target (%d, %d)\n%s" % [support.target.x, support.target.y, support.preview(selection, support.target)]
	elif not support.choosing_target:
		target_label.text = "Choose target to prepare another mission."
	status_label.text = "No fire support assets assigned to this scenario."
	fire_button.disabled = true
	cease_button.disabled = true
	locate_button.disabled = true
	if not support.assets.is_empty():
		var mission: FireSupportMission = support.asset_mission(selection)
		locate_button.disabled = support.assets[selection]["battery"] != null
		status_label.text = "Ready · " + FireSupportMission.MODE_NAMES[support.selected_mode]
		if mission != null:
			status_label.text = "%s\nTarget (%d, %d) · %d fired · %d remaining" % [mission.result, mission.target.x, mission.target.y, mission.fired, mission.remaining]
			if mission.active:
				cease_button.disabled = false
				if mission.next_round > mission.elapsed:
					status_label.text += "\nNext launch in at least %d s" % ceili(mission.next_round - mission.elapsed)
		if support.has_target:
			fire_button.disabled = not support.restriction(selection, support.target).is_empty()
	_layout.call_deferred()

func _layout() -> void:
	if not is_node_ready():
		return
	var area: Vector2 = (get_parent() as Control).size
	toggle.position = Vector2(maxf(12.0, (area.x - toggle.size.x) * 0.5), area.y - toggle.size.y - 12.0)
	tray.size = Vector2(minf(460.0, area.x - 24.0), tray.get_combined_minimum_size().y)
	tray.position = Vector2(maxf(12.0, (area.x - tray.size.x) * 0.5), maxf(12.0, toggle.position.y - tray.size.y - 8.0))

func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.25:
		_refresh_elapsed = 0.0
		refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F:
		toggle_tray()
	elif event.keycode == KEY_ESCAPE and tray.visible:
		_close()
	elif event.keycode == KEY_ENTER and tray.visible and not fire_button.disabled:
		_fire()
	else:
		return
	get_viewport().set_input_as_handled()
