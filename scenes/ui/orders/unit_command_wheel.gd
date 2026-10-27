@tool
extends Control

signal cancelled

const ICON_SIZE: Vector2 = Vector2(32.0, 32.0)
const SCREEN_MARGIN: float = 12.0
const STATUS_GAP: float = 8.0
const ROUT_COLOR: Color = Color(0.95, 0.65, 0.35)

@export var bkg_color: Color = Color(0.09, 0.1, 0.085, 1.0)
@export var line_color: Color = Color(0.53, 0.54, 0.43)
@export var highlight_color: Color = Color(0.29, 0.28, 0.19)
@export var outer_radius: int = 140
@export var inner_radius: int = 40
@export var line_width: int = 1
@export var options: Array[WheelOption] = []

var selection: int = 0
var status_panel: PanelContainer
var selected_label: Label
var restriction_label: Label
var _active: bool = false
var _anchor_point: Vector2
var _restriction_provider: Callable
var _restrictions: Dictionary[WheelOption.Option, String] = {}
var _refresh_elapsed_s: float = 0.0
var _state_source: StressController


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	if Engine.is_editor_hint():
		return
	status_panel = PanelContainer.new()
	status_panel.custom_minimum_size.y = 100.0
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_panel)
	var content: VBoxContainer = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.add_child(content)
	selected_label = Label.new()
	selected_label.theme_type_variation = &"HudHeading"
	selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selected_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(selected_label)
	restriction_label = Label.new()
	restriction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	restriction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restriction_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(restriction_label)
	var cancel_hint: Label = Label.new()
	cancel_hint.theme_type_variation = &"HudSecondary"
	cancel_hint.text = "Esc or left click: cancel"
	cancel_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(cancel_hint)
	status_panel.minimum_size_changed.connect(_queue_fit)
	get_parent().resized.connect(_queue_fit)
	hide()


func open(event_position: Vector2, restriction_provider: Callable = Callable(), state_source: StressController = null) -> void:
	_disconnect_state_source()
	_state_source = state_source
	if is_instance_valid(_state_source):
		_state_source.state_changed.connect(_on_morale_state_changed)
	_anchor_point = event_position
	_restriction_provider = restriction_provider
	selection = 0
	_active = true
	_refresh_elapsed_s = 0.0
	_refresh_restrictions()
	_update_status()
	show()
	set_process(true)
	_fit_wheel()
	_queue_fit()
	queue_redraw()


func is_open() -> bool:
	return _active and visible


func close() -> WheelOption.Option:
	if not is_open():
		return WheelOption.Option.NONE
	var command: WheelOption.Option = options[selection].option
	_active = false
	_disconnect_state_source()
	set_process(false)
	hide()
	return command


func cancel() -> void:
	if not is_open():
		return
	_active = false
	_disconnect_state_source()
	set_process(false)
	hide()
	cancelled.emit()


func _exit_tree() -> void:
	_disconnect_state_source()


func _disconnect_state_source() -> void:
	if is_instance_valid(_state_source) and _state_source.state_changed.is_connected(_on_morale_state_changed):
		_state_source.state_changed.disconnect(_on_morale_state_changed)
	_state_source = null


func _on_morale_state_changed(_previous: int, _next: int) -> void:
	if is_open():
		_refresh_restrictions()
		_update_status()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index == MouseButton.MOUSE_BUTTON_LEFT):
		cancel()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		select_at(event.position)


func select_at(screen_point: Vector2) -> void:
	_update_selection(get_global_transform_with_canvas().affine_inverse() * screen_point)


func _process(delta: float) -> void:
	if not is_open():
		return
	_refresh_elapsed_s += delta
	if _refresh_elapsed_s >= 0.1:
		_refresh_elapsed_s = 0.0
		_refresh_restrictions()
		_update_status()


func _update_selection(point: Vector2) -> void:
	var next: int = 0
	if point.length() > outer_radius:
		for index: int in range(options.size()):
			if options[index].option == WheelOption.Option.NONE:
				next = index
				break
	elif options.size() > 1 and point.length() >= inner_radius:
		var angle: float = fposmod(_sector_start_angle() - point.angle(), TAU)
		next = 1 + mini(options.size() - 2, floori(angle / TAU * float(options.size() - 1)))
	if selection != next:
		selection = next
		queue_redraw()
	_refresh_restrictions()
	_update_status()


func _refresh_restrictions() -> void:
	for option: WheelOption in options:
		var reason: String = ""
		if option.option != WheelOption.Option.NONE and _restriction_provider.is_valid():
			reason = _restriction_provider.call(option.option)
		if _restrictions.get(option.option, "") != reason:
			_restrictions[option.option] = reason
			queue_redraw()


func _update_status() -> void:
	if selected_label == null or options.is_empty():
		return
	var command: WheelOption.Option = options[selection].option
	selected_label.text = str(WheelOption.COMMAND_NAMES.get(command, "Cancel"))
	var reason: String = _restrictions.get(command, "")
	restriction_label.text = "Release right click to issue this order."
	var color: Color = Color(0.93, 0.91, 0.82)
	if command == WheelOption.Option.NONE:
		restriction_label.text = "Release to cancel."
	elif command == WheelOption.Option.ROUT:
		selected_label.text = "Rout · attempt escape"
		restriction_label.text = "Uncontrolled retreat.\nNo escape route means surrender."
		color = ROUT_COLOR
	elif command == WheelOption.Option.WATCH:
		restriction_label.text = "Watch toward this hex.\nAdjust the arc in squad details."
	if not reason.is_empty():
		restriction_label.text = reason
		color = Color(0.96, 0.62, 0.43)
	selected_label.add_theme_color_override("font_color", _command_color(command))
	restriction_label.add_theme_color_override("font_color", color)


func _command_color(command: WheelOption.Option) -> Color:
	if not str(_restrictions.get(command, "")).is_empty():
		return Color(0.62, 0.63, 0.57)
	if command == WheelOption.Option.ROUT:
		return ROUT_COLOR
	return Color(0.93, 0.91, 0.82)


func _queue_fit() -> void:
	if is_open():
		_fit_wheel.call_deferred()


func _fit_wheel() -> void:
	if not is_open() or status_panel == null:
		return
	status_panel.custom_minimum_size.x = float(outer_radius * 2)
	status_panel.size = Vector2(float(outer_radius * 2), status_panel.get_combined_minimum_size().y)
	var parent: Control = get_parent() as Control
	# Keep Move under the original pointer even when the outer wheel is clipped.
	position = parent.get_global_transform_with_canvas().affine_inverse() * _anchor_point
	var bounds: Vector2 = parent.size
	var status_position: Vector2 = position + Vector2(-status_panel.size.x * 0.5, outer_radius + STATUS_GAP)
	if status_position.y + status_panel.size.y > bounds.y - SCREEN_MARGIN:
		status_position.y = position.y - outer_radius - STATUS_GAP - status_panel.size.y
	status_position.x = clampf(status_position.x, SCREEN_MARGIN, maxf(SCREEN_MARGIN, bounds.x - status_panel.size.x - SCREEN_MARGIN))
	status_position.y = clampf(status_position.y, SCREEN_MARGIN, maxf(SCREEN_MARGIN, bounds.y - status_panel.size.y - SCREEN_MARGIN))
	status_panel.position = status_position - position


func get_wheel_rect() -> Rect2:
	var rect: Rect2 = Rect2(position - Vector2(outer_radius, outer_radius), Vector2.ONE * float(outer_radius * 2))
	if status_panel != null:
		rect = rect.merge(Rect2(position + status_panel.position, status_panel.size))
	return rect


func _sector_start_angle() -> float:
	return -(PI - TAU / float(options.size() - 1)) * 0.5


func get_option_point(index: int) -> Vector2:
	if index == 0 or options.size() < 2:
		return Vector2.ZERO
	var arc: float = TAU / float(options.size() - 1)
	var angle: float = _sector_start_angle() - (float(index) - 0.5) * arc
	return Vector2.from_angle(angle) * float(inner_radius + outer_radius) * 0.5


func _draw() -> void:
	if options.size() < 2:
		return
	var font: Font = get_theme_font("font", "Label")
	var body_size: int = get_theme_font_size("font_size", "Label")
	draw_circle(Vector2.ZERO, outer_radius, bkg_color)
	var arc: float = TAU / float(options.size() - 1)
	for index: int in range(1, options.size()):
		var start: float = _sector_start_angle() - float(index - 1) * arc
		if selection == index:
			var points: PackedVector2Array = PackedVector2Array()
			for step: int in range(33):
				points.append(Vector2.from_angle(start - arc * float(step) / 32.0) * inner_radius)
			for step: int in range(32, -1, -1):
				points.append(Vector2.from_angle(start - arc * float(step) / 32.0) * outer_radius)
			draw_colored_polygon(points, highlight_color)
		var edge: Vector2 = Vector2.from_angle(start)
		draw_line(edge * inner_radius, edge * outer_radius, line_color, float(line_width), true)
		var point: Vector2 = get_option_point(index)
		var color: Color = _command_color(options[index].option)
		var label: String = str(WheelOption.COMMAND_NAMES.get(options[index].option, "Cancel"))
		var label_point: Vector2 = point + Vector2(-4.0, 5.0)
		if options[index].option == WheelOption.Option.NONE:
			label_point.x = point.x - font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, body_size).x * 0.5
		else:
			draw_texture_rect_region(options[index].atlas, Rect2(point + Vector2(-42.0, -16.0), ICON_SIZE), options[index].region, color)
		draw_string(font, label_point, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, body_size, color)
	if selection == 0:
		draw_circle(Vector2.ZERO, inner_radius, highlight_color)
	draw_arc(Vector2.ZERO, outer_radius, 0.0, TAU, 96, line_color, float(line_width), true)
	draw_arc(Vector2.ZERO, inner_radius, 0.0, TAU, 64, line_color, float(line_width), true)
	var center_label: String = str(WheelOption.COMMAND_NAMES.get(options[0].option, "Cancel"))
	var center_color: Color = Color(0.93, 0.91, 0.82)
	if not str(_restrictions.get(options[0].option, "")).is_empty():
		center_color = Color(0.62, 0.63, 0.57)
	var center_label_point: Vector2 = Vector2(-font.get_string_size(center_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, body_size).x * 0.5, 5.0)
	if options[0].option != WheelOption.Option.NONE:
		draw_texture_rect_region(options[0].atlas, Rect2(Vector2(-16.0, -28.0), ICON_SIZE), options[0].region, center_color)
		center_label_point.y = 25.0
	draw_string(font, center_label_point, center_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, body_size, center_color)
