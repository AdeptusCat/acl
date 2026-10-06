@tool
extends Control


const SPRITE_SIZE: Vector2 = Vector2(64, 64)


@export var bkg_color: Color
@export var line_color: Color
@export var highlight_color: Color

@export var outer_radius: int = 256
@export var inner_radius: int = 64
@export var line_width: int = 4

@export var options: Array[WheelOption] = []

var selection: int = 0

func open(event_position: Vector2) -> void:
	position = event_position
	show()


func close() -> WheelOption.Option:
	hide()
	return options[selection].option


func _draw() -> void:
	var offset: Vector2 = SPRITE_SIZE / -2
	var rad_offset: float = (PI - (TAU / (options.size() - 1))) / 2
	
	draw_circle(Vector2.ZERO, outer_radius, bkg_color)
	draw_arc(Vector2.ZERO, inner_radius, 0, TAU, 128, line_color, line_width, true)
	
	if options.size() >= 3:
		for i: int in range(options.size() -1):
			var rads: float = (TAU * i / (options.size() - 1)) - rad_offset
			var point: Vector2 = Vector2.from_angle(rads)
			draw_line(
				point * inner_radius,
				point * outer_radius,
				line_color,
				line_width,
				true
			)
		
		if selection == 0:
			draw_circle(Vector2.ZERO, inner_radius, highlight_color)
	
		draw_texture_rect_region(
			options[0].atlas,
			Rect2(offset, SPRITE_SIZE),
			options[0].region
		)
		
		for i: int in range(1, options.size()):
			var start_rads: float = (TAU * (i-1)) / (options.size() - 1)  + rad_offset
			var end_rads: float = (TAU * i) / (options.size() - 1)  + rad_offset
			var mid_rads: float = (start_rads + end_rads) / 2.0 * -1.0  + rad_offset
			var radius_mid: float = (inner_radius + outer_radius) / 2.0
			
			if selection == i:
				var points_per_arc: int = 32
				var points_inner: PackedVector2Array = PackedVector2Array()
				var points_outer: PackedVector2Array = PackedVector2Array()
				
				for j: int in range(points_per_arc+1):
					var angle: float = start_rads + j * (end_rads - start_rads) / points_per_arc
					points_inner.append(inner_radius * Vector2.from_angle(TAU-angle))
					points_outer.append(outer_radius * Vector2.from_angle(TAU-angle))
				
				points_outer.reverse()
				draw_polygon(
					points_inner + points_outer,
					PackedColorArray([highlight_color])
				)
			
			var draw_pos: Vector2 = radius_mid * Vector2.from_angle(mid_rads - rad_offset) + offset
			draw_texture_rect_region(
			options[i].atlas,
			Rect2(draw_pos, SPRITE_SIZE),
			options[i].region
		)

func _process(delta: float) -> void:
	var mouse_position: Vector2 = get_local_mouse_position()
	var mouse_radius: float = mouse_position.length()
	
	if mouse_radius < inner_radius:
		selection = 0
	else:
		var mouse_rads: float = fposmod(mouse_position.angle() * -1, TAU)
		selection = ceil(((mouse_rads) / TAU) * (options.size() - 1))
	
	queue_redraw()
