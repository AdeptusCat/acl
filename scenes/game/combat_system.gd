extends Node

@onready var container = $"../UnitContainer"

var visible_enemies = {}  # unit -> [enemies]

func _ready():
	# whenever any unit moves, recheck
	for u in container.get_children():
		u.connect("moved_to_hex", self, "_on_unit_moved")

func _on_unit_moved(u, _):
	_update_visibility_for(u)
	# optional immediate shots…
	for enemy in visible_enemies[u]:
		if not enemy.movement.moving:
			u.fire_at(enemy, u.current_hex.distance_to(enemy.current_hex), _cover(u,enemy))
	emit_signal("visibility_changed", u, visible_enemies[u])

func _update_visibility_for(u):
	var vis = LOSHelper.los_lookup.get(u.current_hex, [])
	visible_enemies[u] = container.get_children().filter(func(e):
		return e.team!=u.team and e.current_hex in vis
	)

func _cover(u,e):
	var m = LOSHelper.los_lookup.get(e.current_hex, {})
	return m.get(u.current_hex, {}).get("target_cover", 0)
