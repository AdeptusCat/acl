extends PanelContainer

@onready var heading: Label = $Content/Heading
@onready var detail: Label = $Content/Detail
@onready var extra: Label = $Content/Extra
@onready var hud_control: Control = get_parent() as Control

var anchor_point: Vector2

const HUD_PANELS: Array[String] = ["UnitDetails", "TileDetails", "SquadRoster", "Debug", "MissionObjectives", "Countdown", "TryAgain", "Settings", "Settings/Menu", "Settings/Controls"]


func _ready() -> void:
	minimum_size_changed.connect(_queue_fit)
	hud_control.resized.connect(_queue_fit)
	for path: String in HUD_PANELS:
		var panel: Control = hud_control.get_node_or_null(path) as Control
		if panel != null:
			panel.item_rect_changed.connect(_queue_fit)
			panel.visibility_changed.connect(_queue_fit)


func show_hint(point: Vector2, title: String, description: String, additional: String = "", color: Color = Color(0.9, 0.87, 0.77)) -> void:
	anchor_point = point
	heading.text = title
	heading.add_theme_color_override("font_color", color)
	detail.text = description
	extra.text = additional
	extra.visible = not additional.is_empty()
	show()
	_fit_panel()
	_queue_fit()


func _queue_fit() -> void:
	_fit_panel.call_deferred()


func _fit_panel() -> void:
	if not is_node_ready() or is_queued_for_deletion() or not visible:
		return
	size = Vector2(240.0, get_combined_minimum_size().y)
	var candidates: Array[Vector2] = [anchor_point + Vector2(18.0, 12.0), anchor_point + Vector2(-size.x - 18.0, 12.0), anchor_point + Vector2(18.0, -size.y - 12.0), anchor_point - size - Vector2(18.0, 12.0)]
	var blockers: Array[Rect2] = []
	for path: String in HUD_PANELS:
		var panel: Control = hud_control.get_node_or_null(path) as Control
		if panel == null or not panel.is_visible_in_tree():
			continue
		var rect: Rect2 = panel.get_global_rect()
		blockers.append(rect)
		candidates.append(Vector2(anchor_point.x - size.x - 18.0, rect.position.y - size.y - 12.0))
		candidates.append(Vector2(rect.position.x - size.x - 12.0, anchor_point.y + 12.0))
	var best_overlap: float = INF
	for candidate: Vector2 in candidates:
		candidate.x = clampf(candidate.x, 12.0, maxf(12.0, hud_control.size.x - size.x - 12.0))
		candidate.y = clampf(candidate.y, 12.0, maxf(12.0, hud_control.size.y - size.y - 12.0))
		var overlap: float = 0.0
		var hint_rect: Rect2 = Rect2(candidate, size)
		for blocker: Rect2 in blockers:
			var intersection: Rect2 = hint_rect.intersection(blocker)
			overlap += maxf(0.0, intersection.size.x) * maxf(0.0, intersection.size.y)
		if overlap < best_overlap:
			best_overlap = overlap
			position = candidate
		if is_zero_approx(overlap):
			break
