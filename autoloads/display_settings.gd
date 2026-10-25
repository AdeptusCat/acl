extends Node

signal ui_scale_changed(value: float)
signal settings_changed

const DESIGN_SIZE: Vector2i = Vector2i(1280, 720)
const BASE_UI_SCALE: float = 0.75
const MIN_UI_SCALE: float = 0.75
const MAX_UI_SCALE: float = 1.25
const UI_SCALE_STEP: float = 0.01
const WINDOW_PRESETS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1920, 1200),
	Vector2i(2560, 1600), Vector2i(2560, 1080), Vector2i(3440, 1440),
]

var ui_scale: float = 1.0
var windowed_size: Vector2i = DESIGN_SIZE
var window_mode: Window.Mode = Window.MODE_FULLSCREEN
var preferences_path: String = "user://display.cfg"
var _resize_timer: Timer
var _web_fullscreen_pending: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resize_timer = Timer.new()
	_resize_timer.one_shot = true
	_resize_timer.wait_time = 0.3
	add_child(_resize_timer)
	_resize_timer.timeout.connect(_remember_window_size)
	if not OS.has_feature("web"):
		get_window().min_size = DESIGN_SIZE
	get_window().unresizable = false
	# Regression runs must not read or overwrite the player's preferences.
	if DisplayServer.get_name() == "headless":
		preferences_path = ""
	else:
		load_preferences()
		if OS.has_feature("web") and window_mode == Window.MODE_FULLSCREEN:
			# Browser fullscreen must start inside a user input callback.
			_web_fullscreen_pending = get_window().mode != Window.MODE_FULLSCREEN
		else:
			_apply_window()
	get_window().size_changed.connect(_on_window_resized)
	get_window().close_requested.connect(_remember_window_size)


func _input(event: InputEvent) -> void:
	if not _web_fullscreen_pending:
		return
	if event is InputEventMouseButton:
		if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
			return
	elif event is InputEventKey:
		if not event.pressed or event.echo or event.keycode == KEY_ESCAPE:
			return
	elif event is InputEventScreenTouch:
		if not event.pressed:
			return
	else:
		return
	_apply_window()


func set_ui_scale(value: float) -> void:
	if not is_finite(value):
		return
	var next_scale: float = _normalize_ui_scale(value)
	if is_equal_approx(ui_scale, next_scale):
		return
	ui_scale = next_scale
	ui_scale_changed.emit(ui_scale)
	settings_changed.emit()
	save_preferences()


func _normalize_ui_scale(value: float) -> float:
	return snappedf(clampf(value, MIN_UI_SCALE, MAX_UI_SCALE), UI_SCALE_STEP)


func get_hud_scale() -> float:
	return BASE_UI_SCALE * ui_scale


func set_window_mode(value: Window.Mode) -> void:
	if value != Window.MODE_WINDOWED and value != Window.MODE_FULLSCREEN:
		return
	if window_mode == value:
		return
	if get_window().mode == Window.MODE_WINDOWED:
		windowed_size = get_window().size.max(DESIGN_SIZE)
	window_mode = value
	_apply_window()
	settings_changed.emit()
	save_preferences()


func set_windowed_size(value: Vector2i) -> void:
	windowed_size = value.max(DESIGN_SIZE)
	if window_mode == Window.MODE_WINDOWED:
		_apply_window()
	settings_changed.emit()
	save_preferences()


func _apply_window() -> void:
	_web_fullscreen_pending = false
	var window: Window = get_window()
	window.mode = window_mode
	# Adaptive web exports take their size and position from the browser frame.
	if OS.has_feature("web"):
		return
	if window_mode == Window.MODE_WINDOWED:
		var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
		var target: Vector2i = windowed_size
		if usable.has_area():
			target = target.min(usable.size).max(DESIGN_SIZE)
		window.size = target
		windowed_size = target
		if usable.has_area():
			window.position = usable.position + (usable.size - target) / 2
	# Fullscreen uses the desktop video mode; never apply a window preset to it.


func _on_window_resized() -> void:
	_resize_timer.start()


func _remember_window_size() -> void:
	if get_window().mode != Window.MODE_WINDOWED or window_mode != Window.MODE_WINDOWED:
		return
	windowed_size = get_window().size.max(DESIGN_SIZE)
	settings_changed.emit()
	save_preferences()


func load_preferences() -> void:
	if preferences_path.is_empty():
		return
	var config: ConfigFile = ConfigFile.new()
	if config.load(preferences_path) != OK:
		return
	var saved_scale: Variant = config.get_value("display", "ui_scale", "")
	# Older preferences store the absolute scale; preserve their displayed size.
	var saved_base: Variant = config.get_value("display", "ui_scale_base", 1.0)
	if (saved_scale is float or saved_scale is int) and is_finite(float(saved_scale)):
		if (saved_base is float or saved_base is int) and is_finite(float(saved_base)) and float(saved_base) > 0.0:
			ui_scale = _normalize_ui_scale(float(saved_scale) * float(saved_base) / BASE_UI_SCALE)
	var saved_size: Variant = config.get_value("display", "windowed_size", DESIGN_SIZE)
	if saved_size is Vector2i:
		windowed_size = saved_size.max(DESIGN_SIZE)
	var saved_mode: Variant = config.get_value("display", "fullscreen", true)
	window_mode = Window.MODE_FULLSCREEN
	if saved_mode is bool and not saved_mode:
		window_mode = Window.MODE_WINDOWED
	ui_scale_changed.emit(ui_scale)
	settings_changed.emit()


func save_preferences() -> void:
	if preferences_path.is_empty():
		return
	var config: ConfigFile = ConfigFile.new()
	config.set_value("display", "ui_scale", ui_scale)
	config.set_value("display", "ui_scale_base", BASE_UI_SCALE)
	config.set_value("display", "windowed_size", windowed_size)
	config.set_value("display", "fullscreen", window_mode == Window.MODE_FULLSCREEN)
	var error: Error = config.save(preferences_path)
	if error != OK:
		push_warning("Could not save display preferences: %s" % error_string(error))
