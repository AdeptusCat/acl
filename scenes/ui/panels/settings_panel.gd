extends Control

const CONTROL_HINTS: Dictionary[String, String] = {
	"Left click": "Select / deselect squad",
	"Roster row": "Select and center squad",
	"Hold right click": "Open the order wheel",
	"Release right click": "Issue the selected order",
	"WASD / arrows": "Move the camera",
	"Mouse wheel": "Zoom the battlefield",
	"Esc": "Close the open panel",
}

@onready var settings_button: Button = $Toolbar/SettingsButton
@onready var controls_button: Button = $Toolbar/ControlsButton
@onready var menu: PanelContainer = $Menu
@onready var controls_panel: PanelContainer = $Controls
@onready var s1: HSlider = $Menu/Content/VolumeSlider
@onready var s2: HSlider = $Menu/Content/VolumeSlider2
@onready var master_label: Label = $Menu/Content/MasterLabel
@onready var music_label: Label = $Menu/Content/MusicLabel
@onready var command_links: CheckBox = $Menu/Content/ShowCmdConnectivity
@onready var control_rows: VBoxContainer = $Controls/Content/Rows
@onready var hud_control: Control = get_parent() as Control


func _ready() -> void:
	settings_button.toggled.connect(_on_settings_toggled)
	controls_button.toggled.connect(_on_controls_toggled)
	$Menu/Content/Heading/Close.pressed.connect(close_panels)
	$Controls/Content/Heading/Close.pressed.connect(close_panels)
	s1.value_changed.connect(_on_volume_slider_value_changed)
	s2.value_changed.connect(_on_volume_slider_2_value_changed)
	command_links.toggled.connect(_on_check_box_toggled)
	command_links.set_pressed_no_signal(SessionSettings.showCmdConnectivity)
	SessionAudio.sync_sliders([s1, s2])
	_update_volume_labels()
	_build_controls()
	menu.minimum_size_changed.connect(_queue_fit)
	controls_panel.minimum_size_changed.connect(_queue_fit)
	hud_control.resized.connect(_queue_fit)
	close_panels()
	_queue_fit()


func _input(event: InputEvent) -> void:
	if not menu.visible and not controls_panel.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_panels()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var point: Vector2 = event.position
		var open_panel: Control = menu
		if controls_panel.visible:
			open_panel = controls_panel
		if not $Toolbar.get_global_rect().has_point(point) and not open_panel.get_global_rect().has_point(point):
			close_panels()


func close_panels() -> void:
	menu.hide()
	controls_panel.hide()
	settings_button.set_pressed_no_signal(false)
	controls_button.set_pressed_no_signal(false)


func _on_settings_toggled(open: bool) -> void:
	close_panels()
	if open:
		SessionAudio.sync_sliders([s1, s2])
		_update_volume_labels()
		command_links.set_pressed_no_signal(SessionSettings.showCmdConnectivity)
		menu.show()
		settings_button.set_pressed_no_signal(true)
		_queue_fit()


func _on_controls_toggled(open: bool) -> void:
	close_panels()
	if open:
		controls_panel.show()
		controls_button.set_pressed_no_signal(true)
		_queue_fit()


func _build_controls() -> void:
	for binding: String in CONTROL_HINTS:
		var row: HBoxContainer = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 12)
		control_rows.add_child(row)
		var key: Label = Label.new()
		key.custom_minimum_size.x = 154.0
		key.text = binding
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key.add_theme_color_override("font_color", Color(0.86, 0.73, 0.5))
		row.add_child(key)
		var action: Label = Label.new()
		action.text = CONTROL_HINTS[binding]
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		action.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(action)


func _queue_fit() -> void:
	_fit_panels.call_deferred()


func _fit_panels() -> void:
	if not is_node_ready() or is_queued_for_deletion():
		return
	for panel: PanelContainer in [menu, controls_panel]:
		var width: float = 260.0
		if panel == controls_panel:
			width = 388.0
		panel.custom_minimum_size.x = minf(width, hud_control.size.x - 24.0)
		panel.size = Vector2(panel.custom_minimum_size.x, panel.get_combined_minimum_size().y)
		panel.position = Vector2(size.x - panel.size.x, size.y + 8.0)


func _update_volume_labels() -> void:
	master_label.text = "Master volume · %d%%" % roundi(s1.value * 100.0)
	music_label.text = "Music volume · %d%%" % roundi(s2.value * 100.0)

func _on_volume_slider_value_changed(value: float) -> void:
	if SessionAudio.updating_ui:
		return
	SessionAudio.set_master_linear(value)
	SessionAudio.sync_sliders([s1, s2])
	_update_volume_labels()


func _on_volume_slider_2_value_changed(value: float) -> void:
	if SessionAudio.updating_ui:
		return
	SessionAudio.set_music_linear(value)
	SessionAudio.sync_sliders([s1, s2])
	_update_volume_labels()


func _on_check_box_toggled(toggled_on: bool) -> void:
	SessionSettings.showCmdConnectivity = toggled_on
