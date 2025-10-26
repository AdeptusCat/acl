extends PanelContainer

#[img]res://assets/status/idle.png[/ing]

const CURSOR_GAP: int = 12
const OFFSET: Vector2 = Vector2.ONE * 60.0
var opacity_tween: Tween = null

func _ready() -> void:
	TooltipSignals.mouse_entered.connect(toggle_on)
	TooltipSignals.mouse_exited.connect(toggle_off)
	hide()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if visible and event is InputEventMouseMotion:
		_update_follow_position()

func _update_follow_position() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var mouse: Vector2 = get_global_mouse_position()

	var panel_size: Vector2 = size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		panel_size = get_combined_minimum_size()

	var x: float = mouse.x + CURSOR_GAP
	if mouse.x + panel_size.x + CURSOR_GAP > vp_size.x:
		x = mouse.x - panel_size.x - CURSOR_GAP
	if x < 0.0:
		x = 0.0
	if x + panel_size.x > vp_size.x:
		x = vp_size.x - panel_size.x

	var y: float = mouse.y + CURSOR_GAP
	if mouse.y + panel_size.y + CURSOR_GAP > vp_size.y:
		y = mouse.y - panel_size.y - CURSOR_GAP
	if y < 0.0:
		y = 0.0
	if y + panel_size.y > vp_size.y:
		y = vp_size.y - panel_size.y

	global_position = Vector2(x, y)

func toggle_on(tooltip: TooltipSignals.Tooltip):
	var header: String = ""
	var text: String = ""
	match tooltip:
		TooltipSignals.Tooltip.UNIT_TYPE:
			header = "Unit Type"
			text = "Defines the squad’s primary role and equipment"
		TooltipSignals.Tooltip.UNIT_STATUS:
			header = "Unit Status"
			text = "Current morale and combat state of the squad"
		TooltipSignals.Tooltip.LEADERSHIP_BONUS:
			header = "Leadership Bonus"
			text = "Represents morale and coordination influence from nearby leaders"
	$VBoxContainer/HBoxContainer/TooltipHeader.text = header
	$VBoxContainer/TooltipText.text = text
	show()
	modulate.a = 0.0
	tween_opacity(1.0)
	await get_tree().process_frame
	reset_size()

func toggle_off():
	await tween_opacity(0.0).finished
	hide()
		

func tween_opacity(to: float):
	if opacity_tween: 
		opacity_tween.kill()
	opacity_tween = get_tree().create_tween()
	opacity_tween.tween_property(self, 'modulate:a', to, 0.3)
	return opacity_tween
