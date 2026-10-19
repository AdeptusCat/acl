extends Node2D
class_name CommandConnectivityRenderer

const LINK_WIDTH_PX: float = 3.0
const OUTLINE_WIDTH_PX: float = 6.0
const PULSE_SECONDS: float = 1.15
const CONTACT_WARNING_SECONDS: float = 4.0
const FONT_SIZE: int = 13
const CONNECTED_COLOR: Color = Color("a9dfb5")
const LIMITED_COLOR: Color = Color("ffd078")
const LOST_COLOR: Color = Color("ff9b91")
const INK: Color = Color("101b21")
const HIGHLIGHT: Color = Color("f3e6bb")

class ContactCue extends RefCounted:
	var state: CommandConnectivity.ContactState = CommandConnectivity.ContactState.CONNECTED
	var elapsed: float = PULSE_SECONDS
	var warning_elapsed: float = CONTACT_WARNING_SECONDS
	var hq_lost: bool = false
	var initialized: bool = false
	var was_visible: bool = false
	var commander_id: int = 0


var displayed_links: Array[Unit] = []
var highlighted_units: Dictionary[int, String] = {}
var _cues: Dictionary[int, ContactCue] = {}
var _selected: Unit
var _configured: bool = false
var _links_layer: Node2D


func _ready() -> void:
	z_index = 115
	set_process(false)


func setup() -> void:
	if not is_instance_valid(_links_layer):
		_links_layer = Node2D.new()
		_links_layer.name = "CommandLinkLines"
		get_parent().add_child(_links_layer)
		# Terrain is behind the controller; its unit container follows this child.
		get_parent().move_child(_links_layer, 0)
		_links_layer.draw.connect(_draw_links)
	_cues.clear()
	_configured = true
	show()
	set_process(true)
	refresh(0.0)


func _exit_tree() -> void:
	if is_instance_valid(_links_layer):
		_links_layer.queue_free()


func _process(delta: float) -> void:
	refresh(delta)


func refresh(delta: float) -> void:
	if not _configured:
		return
	var units: Array[Unit] = Globals.get_units()
	displayed_links.clear()
	highlighted_units.clear()
	_selected = null
	var active_ids: Dictionary[int, bool] = {}
	for unit: Unit in units:
		active_ids[unit.get_instance_id()] = true
		if _selected == null and unit.selected and _can_display(unit):
			_selected = unit
	# IDs remain safe dictionary keys after a unit's Node has been freed.
	for stale: int in _cues.keys():
		if not active_ids.has(stale):
			_cues.erase(stale)
	for unit: Unit in units:
		var unit_id: int = unit.get_instance_id()
		if not _cues.has(unit_id):
			_cues[unit_id] = ContactCue.new()
		_update_cue(unit, _cues[unit_id], delta)
		if not _can_display(unit):
			continue
		var related: bool = _is_subordinate_of(unit, _selected)
		if related:
			highlighted_units[unit_id] = ""
		if _selected == unit and CommandConnectivity.has_available_commander(unit) and _can_display(unit.command_squad):
			highlighted_units[unit.command_squad.get_instance_id()] = "HQ"
		if not CommandConnectivity.has_available_commander(unit) or not _can_display(unit.command_squad):
			continue
		if SessionSettings.showCmdConnectivity or unit == _selected or related:
			displayed_links.append(unit)
	_links_layer.visible = is_visible_in_tree()
	_links_layer.queue_redraw()
	queue_redraw()


func _can_display(unit: Unit) -> bool:
	if not is_instance_valid(unit) or not unit.is_active() or unit.surrendered or not unit.is_visible_in_tree():
		return false
	if not is_instance_valid(unit.ui) or not unit.ui.is_visible_in_tree():
		return false
	return unit.team == Globals.team_player or Debug.showEnemyCmdConnectivity


func _is_subordinate_of(unit: Unit, commander: Unit) -> bool:
	if not is_instance_valid(commander) or unit == commander or unit.team != commander.team:
		return false
	if commander.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
		return unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS and unit.command_squad == commander and CommandConnectivity.has_available_commander(unit)
	var seen: Array[Unit] = [unit]
	var current: Unit = unit
	while CommandConnectivity.has_available_commander(current):
		current = current.command_squad
		if not _can_display(current) or seen.has(current):
			return false
		if current == commander:
			return true
		seen.append(current)
	return false


func _update_cue(unit: Unit, cue: ContactCue, delta: float) -> void:
	var state: CommandConnectivity.ContactState = CommandConnectivity.contact_state_for(unit)
	var shown: bool = _can_display(unit)
	if shown:
		shown = get_viewport_rect().intersects(counter_rect(unit).grow(26.0))
	var commander_id: int = 0
	var hq_lost: bool = false
	if is_instance_valid(unit.command_squad):
		commander_id = unit.command_squad.get_instance_id()
		hq_lost = not unit.command_squad.alive
	var changed: bool = cue.state != state or cue.commander_id != commander_id or cue.hq_lost != hq_lost
	if changed and cue.initialized and shown and cue.was_visible:
		cue.elapsed = 0.0
	else:
		cue.elapsed = minf(PULSE_SECONDS, cue.elapsed + maxf(delta, 0.0))
	if shown and state == CommandConnectivity.ContactState.LOST and (not cue.initialized or (changed and cue.was_visible)):
		cue.warning_elapsed = 0.0
	else:
		cue.warning_elapsed = minf(CONTACT_WARNING_SECONDS, cue.warning_elapsed + maxf(delta, 0.0))
	if not shown:
		cue.elapsed = PULSE_SECONDS
		cue.warning_elapsed = CONTACT_WARNING_SECONDS
	cue.state = state
	cue.hq_lost = hq_lost
	cue.commander_id = commander_id
	cue.initialized = true
	cue.was_visible = shown


func counter_rect(unit: Unit) -> Rect2:
	var sprite: TextureRect = unit.ui.sprite_node
	var transform: Transform2D = sprite.get_global_transform_with_canvas()
	return transform * Rect2(Vector2.ZERO, sprite.size)


func link_points(unit: Unit) -> PackedVector2Array:
	var origin: Rect2 = counter_rect(unit)
	var target: Rect2 = counter_rect(unit.command_squad)
	var start: Vector2 = origin.get_center()
	var finish: Vector2 = target.get_center()
	if origin.grow(8.0).intersects(target):
		return PackedVector2Array([start, finish])
	return PackedVector2Array([_edge_port(origin, finish), _edge_port(target, start)])


func _edge_port(rect: Rect2, target: Vector2) -> Vector2:
	var direction: Vector2 = target - rect.get_center()
	var half_size: Vector2 = rect.size * 0.5 + Vector2(5.0, 5.0)
	var fraction: float = INF
	if absf(direction.x) > 0.001:
		fraction = minf(fraction, half_size.x / absf(direction.x))
	if absf(direction.y) > 0.001:
		fraction = minf(fraction, half_size.y / absf(direction.y))
	if not is_finite(fraction):
		return rect.get_center()
	return rect.get_center() + direction * fraction


static func contact_color(state: CommandConnectivity.ContactState) -> Color:
	match state:
		CommandConnectivity.ContactState.CONNECTED:
			return CONNECTED_COLOR
		CommandConnectivity.ContactState.LIMITED:
			return LIMITED_COLOR
	return LOST_COLOR


static func line_pattern(state: CommandConnectivity.ContactState) -> PackedFloat32Array:
	match state:
		CommandConnectivity.ContactState.LIMITED:
			return PackedFloat32Array([14.0, 8.0])
		CommandConnectivity.ContactState.LOST:
			return PackedFloat32Array([4.0, 5.0, 4.0, 17.0])
	return PackedFloat32Array()


func _draw() -> void:
	if not _configured:
		return
	# Viewport coordinates keep widths, patterns and labels stable through zoom.
	draw_set_transform_matrix(get_global_transform_with_canvas().affine_inverse())
	# Contact details live in the squad panel; midpoint labels obscure nearby counters.
	for unit_id: int in highlighted_units:
		if not is_instance_id_valid(unit_id):
			continue
		var unit: Unit = instance_from_id(unit_id) as Unit
		if not _can_display(unit):
			continue
		var frame: Rect2 = counter_rect(unit).grow(4.0)
		draw_rect(frame, INK, false, 6.0)
		draw_rect(frame, HIGHLIGHT, false, 2.0)
	for unit_id: int in _cues:
		if not is_instance_id_valid(unit_id):
			continue
		var unit: Unit = instance_from_id(unit_id) as Unit
		if _can_display(unit):
			_draw_cue(unit, _cues[unit_id])


func _draw_links() -> void:
	_links_layer.draw_set_transform_matrix(_links_layer.get_global_transform_with_canvas().affine_inverse())
	for cached: Variant in displayed_links:
		if not is_instance_valid(cached):
			continue
		var unit: Unit = cached as Unit
		if not _can_display(unit) or not CommandConnectivity.has_available_commander(unit) or not _can_display(unit.command_squad):
			continue
		var emphasized: bool = _selected == null or unit == _selected or highlighted_units.has(unit.get_instance_id())
		_draw_link(link_points(unit), CommandConnectivity.contact_state_for(unit), emphasized)


func _draw_link(points: PackedVector2Array, state: CommandConnectivity.ContactState, emphasized: bool) -> void:
	var color: Color = contact_color(state)
	var outline: Color = INK
	var width: float = LINK_WIDTH_PX
	var outline_width: float = OUTLINE_WIDTH_PX
	if not emphasized:
		color.a = 0.5
		outline.a = 0.7
		width = 2.0
		outline_width = 5.0
	var pattern: PackedFloat32Array = line_pattern(state)
	if pattern.is_empty():
		_links_layer.draw_polyline(points, outline, outline_width, true)
		_links_layer.draw_polyline(points, color, width, true)
		return
	var pattern_index: int = 0
	var remaining: float = pattern[0]
	for index: int in range(1, points.size()):
		var start: Vector2 = points[index - 1]
		var direction: Vector2 = points[index] - start
		var length: float = direction.length()
		if length < 0.001:
			continue
		direction /= length
		var distance: float = 0.0
		while distance < length - 0.001:
			var step: float = minf(remaining, length - distance)
			if pattern_index % 2 == 0:
				var from: Vector2 = start + direction * distance
				var to: Vector2 = from + direction * step
				_links_layer.draw_line(from, to, outline, outline_width, true)
				_links_layer.draw_line(from, to, color, width, true)
			distance += step
			remaining -= step
			if remaining <= 0.001:
				pattern_index = (pattern_index + 1) % pattern.size()
				remaining = pattern[pattern_index]


func _draw_cue(unit: Unit, cue: ContactCue) -> void:
	var rect: Rect2 = counter_rect(unit)
	if not get_viewport_rect().intersects(rect.grow(26.0)):
		return
	var pulse: float = 1.0 - cue.elapsed / PULSE_SECONDS
	var color: Color = contact_color(cue.state)
	if pulse > 0.0:
		var pulse_color: Color = color
		pulse_color.a = pulse * 0.8
		draw_rect(rect.grow(5.0 + cue.elapsed * 14.0), pulse_color, false, 3.0)
	var caption: String = badge_text(unit)
	if caption.is_empty():
		return
	var top: Vector2 = Vector2(rect.get_center().x, rect.position.y - 15.0)
	if is_instance_valid(unit.ui._casualty_feedback) and unit.ui._casualty_feedback.active:
		top.y -= 65.0
	_draw_badge(top, caption, color)


func badge_text(unit: Unit) -> String:
	if not _can_display(unit) or not _cues.has(unit.get_instance_id()):
		return ""
	var unit_id: int = unit.get_instance_id()
	var cue: ContactCue = _cues[unit_id]
	var caption: String = highlighted_units.get(unit_id, "")
	var show_contact: bool = cue.elapsed < PULSE_SECONDS
	if cue.state == CommandConnectivity.ContactState.LOST:
		show_contact = unit.selected or cue.warning_elapsed < CONTACT_WARNING_SECONDS
	if CommandConnectivity.needs_command_contact(unit) and show_contact:
		if not caption.is_empty():
			caption += " · "
		if cue.state == CommandConnectivity.ContactState.LOST and cue.hq_lost:
			caption += "HQ lost"
		else:
			caption += CommandConnectivity.contact_text(cue.state)
	return caption


func _draw_badge(center: Vector2, text: String, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE)
	var size: Vector2 = Vector2(text_size.x + 14.0, 24.0)
	var viewport_size: Vector2 = get_viewport_rect().size
	center.x = clampf(center.x, size.x * 0.5 + 3.0, maxf(size.x * 0.5 + 3.0, viewport_size.x - size.x * 0.5 - 3.0))
	center.y = clampf(center.y, 15.0, maxf(15.0, viewport_size.y - 15.0))
	var rect: Rect2 = Rect2(center - size * 0.5, size)
	draw_rect(rect, INK)
	draw_rect(rect, color, false, 1.0)
	draw_string(font, rect.position + Vector2(7.0, 17.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, color)
