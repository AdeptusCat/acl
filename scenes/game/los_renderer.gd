extends Node2D

var lines = []  # {from, to, timer, duration}

func _ready():
	$"../CombatSystem".connect("visibility_changed", self, "_on_vis")

func _on_vis(shooter, enemies):
	for e in enemies:
		lines.append({
			"from": $"../GroundLayer".map_to_local(shooter.current_hex),
			"to":   $"../GroundLayer".map_to_local(e.current_hex),
			"timer":0, "duration":2
		})

func _process(dt):
	for l in lines: l.timer += dt
	lines = lines.filter(func(l): l.timer < l.duration)
	update()

func _draw():
	for l in lines:
		draw_line(l.from, l.to, Color.blue, 2)
