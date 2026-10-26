extends Control
class_name FireSupportPanel

const MORTAR_ICON: Texture2D = preload("res://assets/ui/hud/units/mortar.svg")
const HOWITZER_ICON: Texture2D = preload("res://assets/ui/hud/units/howitzer.svg")
const STACK_LAYERS: int = 3
const STACK_OFFSET: int = 4

var support: FireSupportController
var icon_bar: ScrollContainer
var icon_row: HBoxContainer
var asset_buttons: Array[Button] = []
var card_slots: Array[MarginContainer] = []
var stack_edges: Array[Panel] = []
var launch_bars: Array[ProgressBar] = []
var launch_clocks: Array[Label] = []
var tray: PanelContainer
var asset_label: Label
var length: OptionButton
var intensity: OptionButton
var guns: SpinBox
var target_label: Label
var status_label: Label
var fire_button: Button
var cease_button: Button
var locate_button: Button
var shape_buttons: Array[Button] = []
var gesture_hint: Label
var _refresh_elapsed: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 8
	icon_bar = ScrollContainer.new()
	icon_bar.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	icon_bar.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(icon_bar)
	icon_row = HBoxContainer.new()
	icon_row.add_theme_constant_override("separation", 6)
	icon_bar.add_child(icon_row)
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
	asset_label = Label.new()
	asset_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(asset_label)
	var settings: GridContainer = GridContainer.new()
	settings.columns = 2
	settings.add_theme_constant_override("h_separation", 12)
	content.add_child(settings)
	var length_label: Label = Label.new()
	length_label.text = "Length"
	settings.add_child(length_label)
	var intensity_label: Label = Label.new()
	intensity_label.text = "Intensity"
	settings.add_child(intensity_label)
	length = OptionButton.new()
	for name: String in FireSupportMission.LENGTH_NAMES:
		length.add_item(name)
	length.item_selected.connect(_select_length)
	length.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(length)
	intensity = OptionButton.new()
	for name: String in FireSupportMission.INTENSITY_NAMES:
		intensity.add_item(name)
	intensity.item_selected.connect(_select_intensity)
	intensity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(intensity)
	var gun_row: HBoxContainer = HBoxContainer.new()
	content.add_child(gun_row)
	var gun_label: Label = Label.new()
	gun_label.text = "Guns firing"
	gun_row.add_child(gun_label)
	guns = SpinBox.new()
	guns.min_value = 1.0
	guns.step = 1.0
	guns.custom_minimum_size.x = 110.0
	guns.value_changed.connect(_select_guns)
	gun_row.add_child(guns)
	var shapes: HBoxContainer = HBoxContainer.new()
	content.add_child(shapes)
	for index: int in range(FireSupportMission.SHAPE_NAMES.size()):
		var button: Button = Button.new()
		button.text = FireSupportMission.SHAPE_NAMES[index]
		button.toggle_mode = true
		button.pressed.connect(_select_shape.bind(index))
		shapes.add_child(button)
		shape_buttons.append(button)
	gesture_hint = Label.new()
	gesture_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gesture_hint.theme_type_variation = &"HudSecondary"
	content.add_child(gesture_hint)
	var actions: HBoxContainer = HBoxContainer.new()
	content.add_child(actions)
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
	hint.text = "Length starts at first launch. Crew and reload may delay shots."
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
		support.choosing_target = not support.assets.is_empty()
		refresh()

func _close() -> void:
	tray.hide()
	support.choosing_target = false
	support.cancel_preview()
	LOSHelper.clear_los()
	support.queue_redraw()
	_refresh_icons()

func _open_asset(index: int) -> void:
	if tray.visible and support.selected_asset == index:
		_close()
		return
	support.selected_asset = index
	support.dragging = false
	tray.show()
	support.choosing_target = true
	refresh()

func _refresh_icons() -> void:
	if asset_buttons.size() != support.assets.size():
		for slot: MarginContainer in card_slots:
			icon_row.remove_child(slot)
			slot.queue_free()
		asset_buttons.clear()
		card_slots.clear()
		stack_edges.clear()
		launch_bars.clear()
		launch_clocks.clear()
		for index: int in range(support.assets.size()):
			var slot: MarginContainer = MarginContainer.new()
			slot.mouse_filter = Control.MOUSE_FILTER_STOP
			slot.add_theme_constant_override("margin_top", STACK_LAYERS * STACK_OFFSET)
			slot.add_theme_constant_override("margin_right", STACK_LAYERS * STACK_OFFSET)
			icon_row.add_child(slot)
			card_slots.append(slot)
			var button: Button = Button.new()
			button.custom_minimum_size = Vector2(88, 128)
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 64)
			button.toggle_mode = true
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			button.pressed.connect(_open_asset.bind(index))
			slot.add_child(button)
			asset_buttons.append(button)
			for layer: int in range(STACK_LAYERS, 0, -1):
				var edge: Panel = Panel.new()
				edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
				edge.show_behind_parent = true
				edge.set_meta("asset_index", index)
				edge.set_meta("layer", layer)
				var card_style: StyleBoxFlat = StyleBoxFlat.new()
				card_style.bg_color = Color(0.12, 0.13, 0.09)
				card_style.set_border_width_all(1)
				card_style.border_color = Color(0.55, 0.55, 0.39)
				edge.add_theme_stylebox_override("panel", card_style)
				button.add_child(edge)
				edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				var offset: float = float(layer * STACK_OFFSET)
				edge.offset_left = offset
				edge.offset_right = offset
				edge.offset_top = -offset
				edge.offset_bottom = -offset
				stack_edges.append(edge)
			var bar: ProgressBar = ProgressBar.new()
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.show_percentage = false
			bar.max_value = 1.0
			bar.step = 0.001
			var background: StyleBoxFlat = StyleBoxFlat.new()
			background.bg_color = Color.TRANSPARENT
			var fill: StyleBoxFlat = StyleBoxFlat.new()
			fill.bg_color = Color(1.0, 0.74, 0.27, 0.22)
			fill.border_width_bottom = 3
			fill.border_color = Color(1.0, 0.78, 0.35, 0.95)
			bar.add_theme_stylebox_override("background", background)
			bar.add_theme_stylebox_override("fill", fill)
			button.add_child(bar)
			bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			launch_bars.append(bar)
			var clock: Label = Label.new()
			clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			clock.add_theme_font_size_override("font_size", 12)
			clock.add_theme_constant_override("outline_size", 3)
			clock.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.03))
			button.add_child(clock)
			clock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			clock.offset_left = -52.0
			clock.offset_right = -4.0
			clock.offset_top = 3.0
			clock.offset_bottom = 21.0
			launch_clocks.append(clock)
	for index: int in range(asset_buttons.size()):
		var button: Button = asset_buttons[index]
		var weapon: WeaponSpec = support.asset_weapon(index)
		button.icon = MORTAR_ICON
		var weapon_name: String = "Mortar"
		if weapon != null:
			weapon_name = weapon.name
			if weapon.family == WeaponSpec.Family.HOWITZER:
				button.icon = HOWITZER_ICON
			if weapon.hud_icon != null:
				button.icon = weapon.hud_icon
		button.text = str(support.ammunition(index))
		button.set_pressed_no_signal(tray.visible and support.selected_asset == index)
		button.tooltip_text = "%s\n%s · %s\n%d rounds · Fire support [F]" % [support.assets[index]["name"], weapon_name, support.asset_status(index), support.ammunition(index)]
		button.tooltip_text += "\nGuns selected: %d/%d" % [support.selected_guns(index), support.available_guns(index)]
		button.set_meta("asset_tooltip", button.tooltip_text)
		var mission: FireSupportMission = support.asset_mission(index)
		button.self_modulate = Color.WHITE
		if mission != null and mission.active:
			button.self_modulate = Color(1.0, 0.78, 0.42)
		elif support.ammunition(index) <= 0:
			button.self_modulate = Color(0.55, 0.55, 0.55)
	for edge: Panel in stack_edges:
		var index: int = int(edge.get_meta("asset_index"))
		edge.visible = support.available_guns(index) > int(edge.get_meta("layer"))
	icon_bar.visible = not asset_buttons.is_empty()
	_refresh_launch_progress()

func _refresh_launch_progress() -> void:
	for index: int in range(launch_bars.size()):
		var progress: Dictionary = support.asset_launch_progress(index)
		launch_bars[index].visible = not progress.is_empty()
		launch_clocks[index].visible = not progress.is_empty()
		asset_buttons[index].tooltip_text = str(asset_buttons[index].get_meta("asset_tooltip", ""))
		var mission: FireSupportMission = support.asset_mission(index)
		asset_buttons[index].text = "Ammo %d" % support.ammunition(index)
		if mission != null:
			var total: int = mission.planned_rounds
			asset_buttons[index].text = "%d/%d\nAmmo %d" % [mission.remaining, total, support.ammunition(index)]
			asset_buttons[index].tooltip_text += "\nMission rounds remaining: %d/%d" % [mission.remaining, total]
		if progress.is_empty():
			continue
		launch_bars[index].value = float(progress["fill"])
		var seconds: float = float(progress["seconds"])
		launch_clocks[index].text = "Waiting"
		if seconds == 0.0:
			launch_clocks[index].text = "Ready"
		elif seconds > 0.0:
			launch_clocks[index].text = "%ds" % ceili(seconds)
		if progress.has("clock"):
			launch_clocks[index].text = str(progress["clock"])
		asset_buttons[index].tooltip_text += "\n%s · %s" % [progress["label"], launch_clocks[index].text]

func _select_length(index: int) -> void:
	support.selected_length = FireSupportMission.LENGTHS[index]
	refresh()

func _select_intensity(index: int) -> void:
	support.selected_intensity = index as FireSupportMission.Intensity
	refresh()

func _select_guns(value: float) -> void:
	if support.selected_asset >= 0 and support.selected_asset < support.assets.size():
		support.assets[support.selected_asset]["selected_guns"] = int(value)
	refresh()

func _select_shape(index: int) -> void:
	support.select_shape(index as FireSupportMission.Shape)

func _cancel_or_close() -> void:
	if support.has_target or support.dragging:
		support.cancel_preview()
	else:
		_close()

func _locate() -> void:
	if support.selected_asset < support.assets.size():
		var unit: Unit = support.representative_unit(support.selected_asset)
		if is_instance_valid(unit):
			support.host.move_camera(unit.current_hex)

func _fire() -> void:
	if not support.has_target:
		return
	if support.request(support.selected_asset, support.target, support.selected_length, support.selected_intensity, support.target_cells, support.target_shape, support.target_end, support.target_radius, support.selected_guns(support.selected_asset)):
		support.host.get_parent().ui.hide_target_hex_cover_distance()
	refresh()

func _cease() -> void:
	support.cease(support.selected_asset)
	refresh()

func refresh() -> void:
	if not is_node_ready():
		return
	var selection: int = support.selected_asset
	asset_label.text = "No fire support assets assigned to this scenario."
	if not support.assets.is_empty():
		asset_label.text = "%s\n%s · %d rounds" % [support.assets[selection]["name"], support.asset_status(selection), support.ammunition(selection)]
	length.disabled = support.assets.is_empty()
	intensity.disabled = support.assets.is_empty()
	length.select(FireSupportMission.LENGTHS.find(support.selected_length))
	intensity.select(support.selected_intensity)
	guns.set_block_signals(true)
	guns.max_value = support.available_guns(selection)
	guns.set_value_no_signal(support.selected_guns(selection))
	guns.suffix = " / %d" % support.available_guns(selection)
	guns.set_block_signals(false)
	guns.editable = not support.assets.is_empty() and support.available_guns(selection) > 1
	for index: int in range(FireSupportMission.INTENSITY_NAMES.size()):
		intensity.set_item_text(index, FireSupportMission.intensity_text(index as FireSupportMission.Intensity, support.selected_guns(selection)))
	var shown_shape: FireSupportMission.Shape = support.selected_shape
	if support.has_target or support.dragging:
		shown_shape = support.target_shape
	for index: int in range(shape_buttons.size()):
		shape_buttons[index].set_pressed_no_signal(index == shown_shape)
		shape_buttons[index].disabled = support.assets.is_empty()
	gesture_hint.text = "Click: point · Drag: line · Shift-drag: area"
	if support.selected_shape == FireSupportMission.Shape.LINE:
		gesture_hint.text = "Drag from start to end · Click: point · Shift-drag: area"
	elif support.selected_shape == FireSupportMission.Shape.AREA:
		gesture_hint.text = "Drag from center to edge · Radius: 1–3 hexes"
	_refresh_icons()
	target_label.text = "Click a battlefield hex to choose the target."
	if support.has_target or support.dragging:
		target_label.text = "%s target (%d, %d) · %s\n%s" % [FireSupportMission.SHAPE_NAMES[support.target_shape], support.target.x, support.target.y, support.coverage_text(), support.preview(selection, support.target, support.target_cells)]
		if support.dragging:
			target_label.text += "\nRelease to prepare · Enter to confirm · Escape to cancel"
	status_label.text = "No fire support assets assigned to this scenario."
	var fire_disabled: bool = true
	var cease_disabled: bool = true
	var locate_disabled: bool = true
	var fire_reason: String = "Choose a target hex or drag a footprint first."
	if not support.assets.is_empty():
		var mission: FireSupportMission = support.asset_mission(selection)
		locate_disabled = support.assets[selection]["battery"] != null
		status_label.text = "Ready · %d guns · %d s · %s" % [support.selected_guns(selection), ceili(support.selected_length), FireSupportMission.intensity_text(support.selected_intensity, support.selected_guns(selection))]
		if mission != null:
			status_label.text = "%s\n%d guns · %s · %d hexes · %d fired · %d remaining" % [mission.result, mission.guns, FireSupportMission.SHAPE_NAMES[mission.shape], mission.cells.size(), mission.fired, mission.remaining]
			if mission.active:
				status_label.text += "\n%d s remaining · %s" % [ceili(mission.seconds_left()), FireSupportMission.intensity_text(mission.intensity, mission.guns)]
				cease_disabled = false
				if mission.next_round > mission.elapsed:
					status_label.text += "\nNext launch in at least %d s" % ceili(mission.next_round - mission.elapsed)
		if support.has_target:
			fire_reason = support.mission_restriction(selection, support.target_cells, support.selected_guns(selection))
			fire_disabled = not fire_reason.is_empty()
	# Toggling disabled on and off cancels a mouse press held across this refresh.
	if fire_button.disabled != fire_disabled:
		fire_button.disabled = fire_disabled
	if cease_button.disabled != cease_disabled:
		cease_button.disabled = cease_disabled
	if locate_button.disabled != locate_disabled:
		locate_button.disabled = locate_disabled
	fire_button.tooltip_text = fire_reason
	_layout.call_deferred()

func _layout() -> void:
	if not is_node_ready():
		return
	var area: Vector2 = (get_parent() as Control).size
	icon_bar.size = Vector2(minf(icon_row.get_combined_minimum_size().x, area.x - 24.0), 160.0)
	icon_bar.position = Vector2(maxf(12.0, (area.x - icon_bar.size.x) * 0.5), area.y - icon_bar.size.y - 12.0)
	tray.size = Vector2(minf(460.0, area.x - 24.0), tray.get_combined_minimum_size().y)
	tray.position = Vector2(maxf(12.0, (area.x - tray.size.x) * 0.5), maxf(12.0, icon_bar.position.y - tray.size.y - 8.0))

func _process(delta: float) -> void:
	_refresh_launch_progress()
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
		_cancel_or_close()
	elif event.keycode == KEY_ENTER and tray.visible and not fire_button.disabled:
		_fire()
	else:
		return
	get_viewport().set_input_as_handled()
