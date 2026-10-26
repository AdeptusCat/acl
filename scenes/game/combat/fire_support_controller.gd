extends Node2D
class_name FireSupportController

const TRACER_SCENE: PackedScene = preload("res://scenes/game/effects/tracer.tscn")

var host: Node2D
var assets: Array[Dictionary] = []
var missions: Array[FireSupportMission] = []
var flights: Array[Dictionary] = []
var selected_asset: int = 0
var selected_mode: FireSupportMission.Mode = FireSupportMission.Mode.QUICK
var choosing_target: bool = false
var has_target: bool = false
var target: Vector2i
var panel: FireSupportPanel

func setup(controller: Node2D) -> void:
	host = controller
	for unit: Unit in Globals.get_units_for_team(Globals.team_player):
		if unit.squad_type == Globals.SquadType.MORTAR:
			assets.append({"id": "unit_%d" % unit.get_instance_id(), "name": unit.get_hud_name() + " · Onboard", "unit": unit, "battery": null})
	for definition: OffboardBattery in Globals.scenario_chosen.offboard_batteries:
		if definition == null or definition.team != Globals.team_player or not definition.is_valid():
			continue
		# Virtual shooters are not battlefield units, objectives, LOS observers or AI assets.
		var source: Unit = Unit.new()
		source.team = definition.team
		source.stress_system = StressController.new()
		source.add_child(source.stress_system)
		source.squad_fire = SquadFireController.new()
		source.squad_fire.unit = source
		source.add_child(source.squad_fire)
		var runtime: WeaponSpec = definition.weapon.create_runtime()
		runtime.ammunition = definition.rounds
		assets.append({"id": "battery_%d" % assets.size(), "name": definition.battery_name + " · Offboard", "unit": source, "battery": definition, "weapon": runtime})
	panel = FireSupportPanel.new()
	panel.name = "FireSupport"
	panel.support = self
	host.get_parent().ui.get_node("Control").add_child(panel)
	queue_redraw()

func _exit_tree() -> void:
	for asset: Dictionary in assets:
		if asset["battery"] != null and is_instance_valid(asset["unit"]):
			(asset["unit"] as Unit).free()

func asset_mission(index: int) -> FireSupportMission:
	if index < 0 or index >= assets.size():
		return null
	for mission: FireSupportMission in missions:
		if mission.asset_id == assets[index]["id"]:
			return mission
	return null

func ammunition(index: int) -> int:
	var asset: Dictionary = assets[index]
	if asset["battery"] != null:
		return (asset["weapon"] as WeaponSpec).ammunition
	var unit: Unit = asset["unit"]
	if not is_instance_valid(unit) or not unit.is_active():
		return 0
	var count: int = 0
	for soldier: Soldier in unit.squad_fire.soldiers:
		if soldier.is_alive and soldier.weapon != null and soldier.weapon.family == WeaponSpec.Family.MORTAR:
			count += soldier.weapon.ammunition
	return count

func asset_status(index: int) -> String:
	var asset: Dictionary = assets[index]
	var mission: FireSupportMission = asset_mission(index)
	if mission != null and mission.active:
		if mission.mode == FireSupportMission.Mode.HARASSING:
			return "Harassing"
		return "Mission active"
	if ammunition(index) <= 0:
		return "Empty / unavailable"
	if asset["battery"] == null:
		var unit: Unit = asset["unit"]
		if not unit.is_active() or unit.broken or unit.surrendered or unit.in_close_combat:
			return "Unavailable"
		if unit.is_moving:
			return "Moving"
		for soldier: Soldier in unit.squad_fire.soldiers:
			if soldier.is_alive and soldier.weapon != null and soldier.weapon.family == WeaponSpec.Family.MORTAR and not soldier.setup_weapon_task.done:
				return "Deploying"
	return "Ready"

func restriction(index: int, cell: Vector2i) -> String:
	if index < 0 or index >= assets.size():
		return "No fire support assets in this scenario."
	if host.end_game_handled and not host.continuing_after_end:
		return "The mission has ended."
	if host.ground_layer.get_cell_source_id(cell) == -1:
		return "Choose a battlefield hex."
	var existing: FireSupportMission = asset_mission(index)
	if existing != null and existing.active:
		return "Battery busy. Cease its current mission first."
	if ammunition(index) <= 0:
		return "No mortar/artillery ammunition remaining."
	var asset: Dictionary = assets[index]
	if asset["battery"] == null:
		var unit: Unit = asset["unit"]
		if not is_instance_valid(unit) or not unit.is_active() or unit.surrendered or unit.broken or unit.in_close_combat:
			return "Mortar squad unavailable."
		var distance: int = host.ground_layer.cube_distance(unit.current_cube, host.ground_layer.map_to_cube(cell))
		var reachable: bool = false
		for soldier: Soldier in unit.squad_fire.soldiers:
			if soldier.is_alive and soldier.weapon != null and soldier.weapon.family == WeaponSpec.Family.MORTAR and soldier.weapon.ammunition > 0 and distance <= soldier.weapon.range_hexes:
				reachable = true
		if not reachable:
			return "Outside this mortar's range."
	return ""

func request(index: int, cell: Vector2i, mode: FireSupportMission.Mode) -> bool:
	var reason: String = restriction(index, cell)
	if not reason.is_empty():
		host.order_feedback.emit(false, "Fire support", reason)
		return false
	var asset: Dictionary = assets[index]
	var mission: FireSupportMission = asset_mission(index)
	if mission != null:
		missions.erase(mission)
	mission = FireSupportMission.new()
	mission.asset_id = asset["id"]
	mission.target = cell
	mission.mode = mode
	mission.remaining = mini(3, ammunition(index))
	if mode == FireSupportMission.Mode.STANDARD:
		mission.remaining = mini(6, ammunition(index))
	elif mode == FireSupportMission.Mode.HARASSING:
		mission.remaining = ammunition(index)
	missions.append(mission)
	var unit: Unit = asset["unit"]
	if asset["battery"] == null:
		unit.clear_orders()
		unit.fire_mortar(cell)
		unit.attack_ground_rounds_budget = mission.remaining
		unit.squad_fire.fire_support_mission = mission
		unit.squad_fire.fire_support_hold = false
	else:
		mission.next_round = (asset["battery"] as OffboardBattery).response_seconds
	choosing_target = false
	has_target = false
	LOSHelper.clear_los()
	host._on_started_moving()
	host.order_feedback.emit(true, "Fire mission", FireSupportMission.MODE_NAMES[mode])
	queue_redraw()
	return true

func cease(index: int) -> void:
	var mission: FireSupportMission = asset_mission(index)
	if mission != null and mission.active:
		mission.stop()
		_release_onboard(assets[index], mission)
	queue_redraw()

func _release_onboard(asset: Dictionary, mission: FireSupportMission) -> void:
	if asset["battery"] != null:
		return
	var unit: Unit = asset["unit"]
	if is_instance_valid(unit) and unit.squad_fire.fire_support_mission == mission:
		unit.squad_fire.fire_support_mission = null
		# Keep a ceased battery silent until the player assigns a new fire order.
		unit.squad_fire.fire_support_hold = true
		unit.squad_fire.clear_target()

func pick_target(screen_point: Vector2) -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	var ground: HexagonTileMapLayer = host.ground_layer
	target = ground.local_to_map(ground.get_global_transform_with_canvas().affine_inverse() * screen_point)
	has_target = true
	choosing_target = false
	LOSHelper.clear_los()
	queue_redraw()
	panel.refresh()

func hover_target(screen_point: Vector2) -> void:
	if selected_asset < 0 or selected_asset >= assets.size():
		return
	var ground: HexagonTileMapLayer = host.ground_layer
	var point: Vector2 = ground.get_global_transform_with_canvas().affine_inverse() * screen_point
	var cell: Vector2i = ground.local_to_map(point)
	if ground.get_cell_source_id(cell) == -1 or get_viewport().gui_get_hovered_control() != null:
		LOSHelper.clear_los()
		return
	var asset: Dictionary = assets[selected_asset]
	if asset["battery"] == null and is_instance_valid(asset["unit"]):
		var unit: Unit = asset["unit"]
		var feedback: Dictionary = MatchInteractionHandler.unit_target_feedback(unit, cell)
		LOSHelper.draw_los(unit.position, point, float(feedback["firepower"]))

func preview(index: int, cell: Vector2i) -> String:
	var reason: String = restriction(index, cell)
	if not reason.is_empty():
		return reason
	var observed: bool = false
	var friends: int = 0
	for unit: Unit in Globals.get_units_for_team(Globals.team_player):
		if not unit.is_active() or unit.surrendered:
			continue
		if unit.current_hex == cell:
			friends += 1
		if LOSHelper.los_lookup.get(unit.current_hex, {}).has(cell):
			observed = true
	var text: String = "Unobserved · map fire"
	if observed:
		text = "Observed by friendly troops"
	var asset: Dictionary = assets[index]
	var eta: float = 0.0
	if asset["battery"] != null:
		var battery: OffboardBattery = asset["battery"]
		eta = battery.response_seconds + battery.flight_seconds
	else:
		var unit: Unit = asset["unit"]
		for soldier: Soldier in unit.squad_fire.soldiers:
			if soldier.is_alive and soldier.weapon != null and soldier.weapon.family == WeaponSpec.Family.MORTAR:
				var setup: float = 0.0
				var reload: float = 0.0
				if not soldier.setup_weapon_task.done:
					setup = soldier.setup_weapon_task.remaining_time_s
				if not soldier.reload_task.done:
					reload = soldier.reload_task.remaining_time_s
				eta = setup + reload + soldier.weapon.raise_s + soldier.weapon.aim_s + unit.global_position.distance_to(host.ground_layer.to_global(host.ground_layer.map_to_local(cell))) / maxf(float(soldier.weapon.projectile_speed), 1.0)
				break
		if unit.is_moving:
			text += "\nMortar will halt and deploy"
	text += "\nEstimated first impact: about %d s" % ceili(eta)
	if friends > 0:
		text += "\nFRIENDLY TROOPS IN TARGET HEX"
	return text

func _process(delta: float) -> void:
	if not is_instance_valid(host):
		return
	if host.end_game_handled and not host.continuing_after_end:
		for index: int in range(assets.size()):
			cease(index)
		flights.clear()
		choosing_target = false
		return
	for mission: FireSupportMission in missions:
		mission.elapsed += delta
	for index: int in range(assets.size()):
		var asset: Dictionary = assets[index]
		var mission: FireSupportMission = asset_mission(index)
		if mission == null:
			continue
		if not mission.active:
			_release_onboard(asset, mission)
			continue
		if ammunition(index) <= 0:
			mission.stop("Ammunition exhausted")
			_release_onboard(asset, mission)
			continue
		if asset["battery"] != null:
			if mission.ready_to_fire():
				_launch_offboard(asset, mission)
		else:
			var unit: Unit = asset["unit"]
			if not is_instance_valid(unit) or not unit.is_active() or unit.broken or unit.surrendered or unit.in_close_combat:
				mission.stop("Interrupted · mortar unavailable")
			elif unit.attackState != Unit.AttackState.MANUAL_GROUND or unit.squad_fire.mortar_target_hex != mission.target or not unit.squad_fire.has_mortar_target_hex:
				mission.stop("Interrupted by another order")
				# Do not clear the replacement order.
				unit.squad_fire.fire_support_mission = null
	for flight: Dictionary in flights.duplicate():
		if flight.has("new"):
			flight.erase("new")
			continue
		flight["time"] = float(flight["time"]) - delta
		if float(flight["time"]) <= 0.0:
			var source: Unit = flight["source"]
			var targets: Array[Unit] = []
			source.squad_fire.fire_at(1, flight["weapon"], false, flight["target"], 0, int(flight["cover"]), targets, flight["origin"])
			flights.erase(flight)
	queue_redraw()

func _launch_offboard(asset: Dictionary, mission: FireSupportMission) -> void:
	var battery: OffboardBattery = asset["battery"]
	var weapon: WeaponSpec = asset["weapon"]
	weapon.ammunition -= 1
	mission.commit_rounds(1)
	if mission.mode != FireSupportMission.Mode.HARASSING:
		mission.next_round = maxf(mission.next_round, mission.elapsed + maxf(weapon.reload_s, 2.0))
	var ground: HexagonTileMapLayer = host.ground_layer
	var finish: Vector2 = ground.to_global(ground.map_to_local(mission.target))
	var origin: Vector2 = finish + Vector2(0.0, -float(weapon.projectile_speed) * battery.flight_seconds)
	var source: Unit = asset["unit"]
	source.position = origin
	flights.append({"source": source, "weapon": weapon, "target": mission.target, "time": battery.flight_seconds, "cover": LOSHelper.is_sample_point_in_building(ground.map_to_local(mission.target)), "origin": origin, "new": true})
	BattlefieldEffects.for_scene(self).fire(origin, finish, weapon, BattlefieldTracer.Kind.MORTAR, TRACER_SCENE)

func _draw() -> void:
	if not is_instance_valid(host) or not is_instance_valid(host.ground_layer):
		return
	for mission: FireSupportMission in missions:
		if mission.active:
			_draw_marker(mission.target, Color(1.0, 0.48, 0.25, 0.8))
	if has_target:
		_draw_marker(target, Color(1.0, 0.85, 0.35, 0.9))

func _draw_marker(cell: Vector2i, color: Color) -> void:
	var center: Vector2 = to_local(host.ground_layer.to_global(host.ground_layer.map_to_local(cell)))
	draw_circle(center, 24.0, Color(color, 0.12))
	draw_arc(center, 24.0, 0.0, TAU, 40, color, 2.0, true)
	draw_line(center - Vector2(32, 0), center + Vector2(32, 0), color, 1.0, true)
	draw_line(center - Vector2(0, 32), center + Vector2(0, 32), color, 1.0, true)
