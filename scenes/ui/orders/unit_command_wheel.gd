@tool
extends Control

signal cancelled

const ICON_SIZE: Vector2 = Vector2(32.0, 32.0)
const SCREEN_MARGIN: float = 12.0
const STATUS_GAP: float = 8.0

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


func open(event_position: Vector2, restriction_provider: Callable = Callable()) -> void:
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
	set_process(false)
	hide()
	return command


func cancel() -> void:
	if not is_open():
		return
	_active = false
	set_process(false)
	hide()
	cancelled.emit()


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
	if options.size() > 1 and point.length() >= inner_radius and point.length() <= outer_radius:
		var angle: float = fposmod(point.angle() + PI * 7.0 / 6.0, TAU)
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
	elif not reason.is_empty():
		restriction_label.text = reason
		color = Color(0.96, 0.62, 0.43)
	restriction_label.add_theme_color_override("font_color", color)


func _queue_fit() -> void:
	if is_open():
		_fit_wheel.call_deferred()


func _fit_wheel() -> void:
	if not is_open() or status_panel == null:
		return
	status_panel.custom_minimum_size.x = float(outer_radius * 2)
	status_panel.size = Vector2(float(outer_radius * 2), status_panel.get_combined_minimum_size().y)
	status_panel.position = Vector2(-outer_radius, outer_radius + STATUS_GAP)
	var bounds: Vector2 = get_parent().size
	position.x = clampf(_anchor_point.x, outer_radius + SCREEN_MARGIN, maxf(outer_radius + SCREEN_MARGIN, bounds.x - outer_radius - SCREEN_MARGIN))
	position.y = clampf(_anchor_point.y, outer_radius + SCREEN_MARGIN, maxf(outer_radius + SCREEN_MARGIN, bounds.y - outer_radius - STATUS_GAP - status_panel.size.y - SCREEN_MARGIN))


func get_wheel_rect() -> Rect2:
	var height: float = float(outer_radius * 2)
	if status_panel != null:
		height += STATUS_GAP + status_panel.size.y
	return Rect2(position - Vector2(outer_radius, outer_radius), Vector2(float(outer_radius * 2), height))


func get_option_point(index: int) -> Vector2:
	if index == 0 or options.size() < 2:
		return Vector2.ZERO
	var arc: float = TAU / float(options.size() - 1)
	var angle: float = -PI * 7.0 / 6.0 + (float(index) - 0.5) * arc
	return Vector2.from_angle(angle) * float(inner_radius + outer_radius) * 0.5


func _draw() -> void:
	if options.size() < 2:
		return
	var font: Font = get_theme_font("font", "Label")
	var body_size: int = get_theme_font_size("font_size", "Label")
	var secondary_size: int = get_theme_font_size("font_size", "HudSecondary")
	draw_circle(Vector2.ZERO, outer_radius, bkg_color)
	var arc: float = TAU / float(options.size() - 1)
	for index: int in range(1, options.size()):
		var start: float = -PI * 7.0 / 6.0 + float(index - 1) * arc
		if selection == index:
			var points: PackedVector2Array = PackedVector2Array()
			for step: int in range(33):
				points.append(Vector2.from_angle(start + arc * float(step) / 32.0) * inner_radius)
			for step: int in range(32, -1, -1):
				points.append(Vector2.from_angle(start + arc * float(step) / 32.0) * outer_radius)
			draw_colored_polygon(points, highlight_color)
		var edge: Vector2 = Vector2.from_angle(start)
		draw_line(edge * inner_radius, edge * outer_radius, line_color, float(line_width), true)
		var point: Vector2 = get_option_point(index)
		var color: Color = Color(0.93, 0.91, 0.82)
		if not str(_restrictions.get(options[index].option, "")).is_empty():
			color = Color(0.62, 0.63, 0.57)
		draw_texture_rect_region(options[index].atlas, Rect2(point + Vector2(-42.0, -16.0), ICON_SIZE), options[index].region, color)
		draw_string(font, point + Vector2(-4.0, 5.0), str(WheelOption.COMMAND_NAMES.get(options[index].option, "Cancel")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, body_size, color)
	if selection == 0:
		draw_circle(Vector2.ZERO, inner_radius, highlight_color)
	draw_arc(Vector2.ZERO, outer_radius, 0.0, TAU, 96, line_color, float(line_width), true)
	draw_arc(Vector2.ZERO, inner_radius, 0.0, TAU, 64, line_color, float(line_width), true)
	var cancel_width: float = font.get_string_size("Cancel", HORIZONTAL_ALIGNMENT_LEFT, -1.0, secondary_size).x
	draw_string(font, Vector2(-cancel_width * 0.5, 4.0), "Cancel", HORIZONTAL_ALIGNMENT_LEFT, -1.0, secondary_size, Color(0.93, 0.91, 0.82))
