extends Node2D
class_name FireSupportController

const TRACER_SCENE: PackedScene = preload("res://scenes/game/effects/tracer.tscn")

var host: Node2D
var assets: Array[Dictionary] = []
var missions: Array[FireSupportMission] = []
var flights: Array[Dictionary] = []
var pending_volley: Array[Dictionary] = []
var selected_asset: int = 0
var selected_length: float = 15.0
var selected_intensity: FireSupportMission.Intensity = FireSupportMission.Intensity.INTENSE
var choosing_target: bool = false
var has_target: bool = false
var target: Vector2i
var selected_shape: FireSupportMission.Shape = FireSupportMission.Shape.POINT
var target_shape: FireSupportMission.Shape = FireSupportMission.Shape.POINT
var target_cells: Array[Vector2i] = []
var target_end: Vector2i
var target_radius: int = 1
var dragging: bool = false
var _drag_start: Vector2
var _drag_area: bool = false
const DRAG_THRESHOLD: float = 10.0
var panel: FireSupportPanel

func setup(controller: Node2D) -> void:
	host = controller
	z_index = 6
	host.get_parent().input_manager.mouse_button_left_released.connect(end_target)
	for unit: Unit in Globals.get_units_for_team(Globals.team_player):
		if unit.squad_type == Globals.SquadType.MORTAR:
			var id: String = "platoon_%d_%d_%d" % [unit.team, unit.company, unit.platoon]
			var group: Dictionary = {}
			for asset: Dictionary in assets:
				if asset["id"] == id:
					group = asset
					break
			if group.is_empty():
				var units: Array[Unit] = []
				group = {"id": id, "name": unit.get_formation_name() + " · Mortar battery · Onboard", "unit": unit, "units": units, "battery": null}
				assets.append(group)
			(group["units"] as Array[Unit]).append(unit)
	for index: int in range(assets.size()):
		assets[index]["selected_guns"] = available_guns(index)
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
		assets.append({"id": "battery_%d" % assets.size(), "name": definition.weapon.name + " · Offboard", "unit": source, "battery": definition, "weapon": runtime, "selected_guns": definition.gun_count})
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

func available_guns(index: int) -> int:
	if index < 0 or index >= assets.size():
		return 1
	var battery: OffboardBattery = assets[index]["battery"]
	if battery != null:
		return battery.gun_count
	var count: int = 0
	for unit: Unit in assets[index]["units"]:
		if not is_instance_valid(unit) or not unit.is_active():
			continue
		for soldier: Soldier in unit.squad_fire.soldiers:
			if soldier.is_alive and soldier.weapon != null and soldier.weapon.family == WeaponSpec.Family.MORTAR:
				count += 1
	return maxi(1, count)

func representative_unit(index: int) -> Unit:
	var asset: Dictionary = assets[index]
	if asset["battery"] == null:
		for unit: Unit in asset["units"]:
			if is_instance_valid(unit) and unit.is_active():
				return unit
	return asset["unit"] as Unit

func eligible_guns(index: int, cells: Array[Vector2i]) -> Array[Soldier]:
	var result: Array[Soldier] = []
	if assets[index]["battery"] != null:
		return result
	for unit: Unit in assets[index]["units"]:
		if not is_instance_valid(unit) or not unit.is_active() or unit.broken or unit.surrendered or unit.in_close_combat:
			continue
		for soldier: Soldier in unit.squad_fire.soldiers:
			if not soldier.is_alive or soldier.weapon == null or soldier.weapon.family != WeaponSpec.Family.MORTAR or soldier.weapon.ammunition <= 0:
				continue
			var reachable: bool = true
			for cell: Vector2i in cells:
				if host.ground_layer.cube_distance(unit.current_cube, host.ground_layer.map_to_cube(cell)) > soldier.weapon.range_hexes:
					reachable = false
					break
			if reachable:
				result.append(soldier)
	return result

func selected_guns(index: int) -> int:
	if index < 0 or index >= assets.size():
		return 1
	return clampi(int(assets[index].get("selected_guns", 1)), 1, available_guns(index))

func asset_weapon(index: int) -> WeaponSpec:
	var asset: Dictionary = assets[index]
	if asset["battery"] != null:
		return asset["weapon"] as WeaponSpec
	for unit: Unit in asset["units"]:
		if not is_instance_valid(unit) or not unit.is_active():
			continue
		for soldier: Soldier in unit.squad_fire.soldiers:
			if soldier.is_alive and soldier.weapon != null and soldier.weapon.family == WeaponSpec.Family.MORTAR:
				return soldier.weapon
	return null

func ammunition(index: int) -> int:
	var asset: Dictionary = assets[index]
	if asset["battery"] != null:
		return (asset["weapon"] as WeaponSpec).ammunition
	var count: int = 0
	for unit: Unit in asset["units"]:
		if not is_instance_valid(unit) or not unit.is_active():
			continue
		for soldier: Soldier in unit.squad_fire.soldiers:
			if soldier.is_alive and soldier.weapon != null and soldier.weapon.family == WeaponSpec.Family.MORTAR:
				count += soldier.weapon.ammunition
	return count

func asset_status(index: int) -> String:
	var asset: Dictionary = assets[index]
	var mission: FireSupportMission = asset_mission(index)
	if mission != null and mission.active:
		if mission.intensity == FireSupportMission.Intensity.HARASSING:
			return "Harassing"
		if mission.intensity == FireSupportMission.Intensity.SPORADIC:
			return "Sporadic"
		return "Mission active"
	if ammunition(index) <= 0:
		return "Empty / unavailable"
	if asset["battery"] == null:
		var pool: Array[Soldier] = eligible_guns(index, [])
		if pool.is_empty():
			return "Unavailable"
		for soldier: Soldier in pool:
			if not soldier.unit.is_moving and soldier.setup_weapon_task.done:
				return "Ready"
		return "Deploying"
	return "Ready"

func asset_launch_progress(index: int) -> Dictionary:
	var mission: FireSupportMission = asset_mission(index)
	if mission == null or not mission.active:
		return {}
	if mission.pending_guns > 0:
		return {"fill": 1.0, "seconds": 0.0, "label": "Firing volley", "clock": "Volley"}
	var wait: float = maxf(0.0, mission.next_round - mission.elapsed)
	var duration: float = maxf(0.0, mission.next_round - mission.last_launch_at)
	var scheduled_duration: float = duration
	var label: String = "Next shell"
	var remaining: float = wait
	if assets[index]["battery"] == null:
		remaining = 0.0
		for soldier: Soldier in mission.onboard_guns:
			if not soldier.is_alive or soldier.weapon == null or soldier.weapon.ammunition <= 0:
				continue
			var unit: Unit = soldier.unit
			if not is_instance_valid(unit) or not unit.is_active() or unit.broken or unit.surrendered or unit.in_close_combat or unit.is_moving:
				return {"fill": 0.0, "seconds": -1.0, "label": "Waiting for battery"}
			var setup_rate: float = maxf(unit.squad_fire.state_acquire_mults[unit.stress_system.state], 0.001)
			var loaders: int = unit.squad_fire._count_role(RankGrades.Role.LOADER)
			var assistants: int = unit.squad_fire._count_role(RankGrades.Role.ASSISTANT)
			var setup: float = 0.0
			var reload: float = 0.0
			var aim: float = 0.0
			var full_setup: float = 0.0
			var full_reload: float = 0.0
			var full_aim: float = 0.0
			if not soldier.setup_weapon_task.done:
				setup = maxf(0.0, soldier.setup_weapon_task.remaining_time_s)
				full_setup = maxf(setup, soldier.setup_weapon_task.start_time_s)
			if not soldier.reload_task.done:
				reload = maxf(0.0, soldier.reload_task.remaining_time_s)
				full_reload = maxf(reload, soldier.reload_task.start_time_s)
			if not soldier.aquire_target_task.done:
				aim = maxf(0.0, soldier.aquire_target_task.remaining_time_s)
				full_aim = maxf(aim, soldier.aquire_target_task.start_time_s)
			var penalty: float = 1.0
			if loaders < soldier.weapon.crew_required - 1:
				penalty = maxf(1.0, soldier.weapon.undercrew_penalty_mult)
			var crew_rate: float = maxf(0.001, setup_rate * unit.squad_fire.compute_support_efficiency(assistants, soldier.weapon.support_crew_optimal) / penalty)
			setup /= setup_rate
			full_setup /= setup_rate
			reload /= crew_rate
			full_reload /= crew_rate
			aim /= crew_rate
			full_aim /= crew_rate
			var work: float = maxf(wait, setup + reload + aim)
			if work >= remaining:
				remaining = work
				duration = maxf(scheduled_duration, full_setup + full_reload + full_aim)
		if not is_finite(remaining):
			return {"fill": 0.0, "seconds": -1.0, "label": "No mortar ready"}
		# Keep completed preparation stages in this launch's denominator.
		mission.launch_work_total = maxf(mission.launch_work_total, maxf(duration, remaining))
		duration = mission.launch_work_total
		label = "Next shell · crew preparation"
	var fill: float = 1.0
	if duration > 0.0:
		fill = clampf(1.0 - remaining / duration, 0.0, 1.0)
	return {"fill": fill, "seconds": remaining, "label": label}

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
		if eligible_guns(index, [cell]).is_empty():
			return "No available mortar can reach this hex."
	return ""

func footprint_restriction(index: int, cells: Array[Vector2i]) -> String:
	if cells.is_empty():
		return "Choose a battlefield target."
	for cell: Vector2i in cells:
		var reason: String = restriction(index, cell)
		if not reason.is_empty():
			return reason
	return ""

func mission_restriction(index: int, cells: Array[Vector2i], guns: int) -> String:
	var reason: String = footprint_restriction(index, cells)
	if not reason.is_empty():
		return reason
	if guns < 1 or guns > available_guns(index):
		return "Choose an available gun count."
	if assets[index]["battery"] == null:
		var count: int = eligible_guns(index, cells).size()
		if count < guns:
			return "Only %d guns can reach the whole footprint." % count
	return ""

func planned_rounds(index: int, length: float, intensity: FireSupportMission.Intensity, guns: int = 1, cells: Array[Vector2i] = []) -> int:
	if index < 0 or index >= assets.size():
		return 0
	var interval: float = FireSupportMission.INTERVALS[intensity]
	var stock: int = ammunition(index)
	if assets[index]["battery"] == null:
		stock = 0
		var pool: Array[Soldier] = eligible_guns(index, cells)
		for gun: int in range(mini(guns, pool.size())):
			stock += pool[gun].weapon.ammunition
			interval = maxf(interval, pool[gun].weapon.reload_s)
	else:
		interval = maxf(interval, (assets[index]["weapon"] as WeaponSpec).reload_s)
	return mini(stock, ceili(length / interval) * clampi(guns, 1, available_guns(index)))

func request(index: int, cell: Vector2i, length: float, intensity: FireSupportMission.Intensity, cells: Array[Vector2i] = [], shape: FireSupportMission.Shape = FireSupportMission.Shape.POINT, end: Vector2i = Vector2i.ZERO, radius: int = 1, guns: int = 1) -> bool:
	if not is_finite(length) or length <= 0.0 or intensity < 0 or intensity >= FireSupportMission.INTERVALS.size():
		return false
	var footprint: Array[Vector2i] = cells.duplicate()
	if footprint.is_empty():
		footprint.append(cell)
	var reason: String = mission_restriction(index, footprint, guns)
	if not reason.is_empty():
		host.order_feedback.emit(false, "Fire support", reason)
		return false
	var asset: Dictionary = assets[index]
	var participants: Array[Soldier] = []
	if asset["battery"] == null:
		participants = eligible_guns(index, footprint)
	var mission: FireSupportMission = asset_mission(index)
	if mission != null:
		missions.erase(mission)
	mission = FireSupportMission.new()
	mission.asset_id = asset["id"]
	mission.target = cell
	mission.cells.assign(footprint)
	mission.shape = shape
	mission.end = end
	mission.radius = radius
	mission.duration_seconds = length
	mission.intensity = intensity
	mission.guns = guns
	mission.planned_rounds = planned_rounds(index, length, intensity, guns, footprint)
	mission.remaining = mission.planned_rounds
	missions.append(mission)
	var unit: Unit = asset["unit"]
	if asset["battery"] == null:
		for gun: int in range(guns):
			mission.onboard_guns.append(participants[gun])
		var assigned: Array[Unit] = []
		for soldier: Soldier in mission.onboard_guns:
			unit = soldier.unit
			if assigned.has(unit):
				continue
			assigned.append(unit)
			unit.clear_orders()
			unit.fire_mortar(cell)
			unit.attack_ground_rounds_budget = mission.remaining
			unit.squad_fire.fire_support_mission = mission
			unit.squad_fire.fire_support_hold = false
	else:
		mission.next_round = (asset["battery"] as OffboardBattery).response_seconds
	asset_launch_progress(index)
	choosing_target = panel != null and panel.tray.visible and not assets.is_empty()
	has_target = false
	dragging = false
	target_cells.clear()
	LOSHelper.clear_los()
	host._on_started_moving()
	host.order_feedback.emit(true, "Fire mission", "%d s · %d guns · %s" % [ceili(length), guns, FireSupportMission.intensity_text(intensity, guns)])
	queue_redraw()
	return true

func cease(index: int) -> void:
	var mission: FireSupportMission = asset_mission(index)
	if mission != null and mission.active:
		mission.stop()
		_cancel_volley(mission)
		_release_onboard(assets[index], mission)
	queue_redraw()

func _release_onboard(asset: Dictionary, mission: FireSupportMission) -> void:
	if asset["battery"] != null:
		return
	mission.onboard_due.clear()
	mission.pending_guns = 0
	for unit: Unit in asset["units"]:
		if is_instance_valid(unit) and unit.squad_fire.fire_support_mission == mission:
			unit.squad_fire.fire_support_mission = null
			unit.squad_fire.fire_support_hold = true
			unit.squad_fire.clear_target()

func preview_marked_hex() -> void:
	var world: Node = host.get_parent()
	if not world.has_inspected_hex:
		return
	var cell: Vector2i = world.selected_hex
	var ground: HexagonTileMapLayer = host.ground_layer
	if ground.get_cell_source_id(cell) == -1:
		return
	pick_target(ground.get_global_transform_with_canvas() * ground.map_to_local(cell))

func pick_target(screen_point: Vector2) -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	var ground: HexagonTileMapLayer = host.ground_layer
	target = ground.local_to_map(ground.get_global_transform_with_canvas().affine_inverse() * screen_point)
	target_shape = FireSupportMission.Shape.POINT
	target_end = target
	target_cells = build_footprint(target, target, target_shape, 1)
	has_target = true
	choosing_target = panel != null and panel.tray.visible and not assets.is_empty()
	LOSHelper.clear_los()
	queue_redraw()
	panel.refresh()

func cancel_preview() -> void:
	dragging = false
	has_target = false
	target_cells.clear()
	LOSHelper.clear_los()
	queue_redraw()
	panel.refresh()

func select_shape(shape: FireSupportMission.Shape) -> void:
	selected_shape = shape
	cancel_preview()

func begin_target(screen_point: Vector2, shift: bool = false) -> void:
	var ground: HexagonTileMapLayer = host.ground_layer
	var cell: Vector2i = ground.local_to_map(ground.get_global_transform_with_canvas().affine_inverse() * screen_point)
	if ground.get_cell_source_id(cell) == -1:
		return
	_drag_start = screen_point
	_drag_area = shift or selected_shape == FireSupportMission.Shape.AREA
	dragging = true
	has_target = false
	target = cell
	target_end = cell
	update_drag(screen_point)

func update_drag(screen_point: Vector2) -> void:
	if not dragging:
		return
	var ground: HexagonTileMapLayer = host.ground_layer
	target_end = ground.local_to_map(ground.get_global_transform_with_canvas().affine_inverse() * screen_point)
	target_shape = FireSupportMission.Shape.POINT
	if _drag_area:
		target_shape = FireSupportMission.Shape.AREA
	elif screen_point.distance_to(_drag_start) >= DRAG_THRESHOLD and target_end != target:
		target_shape = FireSupportMission.Shape.LINE
	var center: Vector2 = ground.to_global(ground.map_to_local(target))
	var edge: Vector2 = ground.to_global(ground.map_to_local(target_end))
	target_radius = clampi(ceili(center.distance_to(edge) / hex_spacing()), 1, 3)
	target_cells = build_footprint(target, target_end, target_shape, target_radius)
	queue_redraw()
	panel.refresh()

func end_target(screen_point: Vector2) -> void:
	if not dragging:
		return
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null and hovered.get_global_rect().has_point(screen_point):
		cancel_preview()
		return
	update_drag(screen_point)
	dragging = false
	has_target = not target_cells.is_empty()
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	LOSHelper.clear_los()
	queue_redraw()
	panel.refresh()

func hex_spacing() -> float:
	var ground: HexagonTileMapLayer = host.ground_layer
	var center: Vector2 = ground.to_global(ground.map_to_local(target))
	var spacing: float = 1.0
	for neighbor: Vector2i in ground.get_surrounding_cells(target):
		spacing = maxf(spacing, center.distance_to(ground.to_global(ground.map_to_local(neighbor))))
	return spacing

func build_footprint(start: Vector2i, end: Vector2i, shape: FireSupportMission.Shape, radius: int) -> Array[Vector2i]:
	var ground: HexagonTileMapLayer = host.ground_layer
	var cells: Array[Vector2i] = []
	if shape == FireSupportMission.Shape.POINT:
		if ground.get_cell_source_id(start) != -1:
			cells.append(start)
	elif shape == FireSupportMission.Shape.LINE:
		var a: Vector3 = Vector3(ground.map_to_cube(start)) + Vector3(0.000001, 0.000002, -0.000003)
		var b: Vector3 = Vector3(ground.map_to_cube(end)) + Vector3(0.000001, 0.000002, -0.000003)
		var steps: int = ground.cube_distance(ground.map_to_cube(start), ground.map_to_cube(end))
		for index: int in range(steps + 1):
			var cell: Vector2i = ground.cube_to_map(ground.cube_round(a.lerp(b, float(index) / float(maxi(steps, 1)))))
			if ground.get_cell_source_id(cell) != -1 and not cells.has(cell):
				cells.append(cell)
	else:
		var center: Vector2 = ground.to_global(ground.map_to_local(start))
		var spacing: float = 1.0
		for neighbor: Vector2i in ground.get_surrounding_cells(start):
			spacing = maxf(spacing, center.distance_to(ground.to_global(ground.map_to_local(neighbor))))
		var distance: float = spacing * float(clampi(radius, 1, 3))
		for cell: Vector2i in ground.get_used_cells():
			if center.distance_to(ground.to_global(ground.map_to_local(cell))) <= distance + 0.01:
				cells.append(cell)
	return cells

func coverage_text() -> String:
	var rounds: int = planned_rounds(selected_asset, selected_length, selected_intensity, selected_guns(selected_asset), target_cells)
	var text: String = "Up to %d rounds across %d hexes" % [rounds, target_cells.size()]
	if rounds < target_cells.size():
		text += " · sparse coverage"
	return text

func hover_target(screen_point: Vector2) -> void:
	if dragging:
		update_drag(screen_point)
		return
	if selected_asset < 0 or selected_asset >= assets.size():
		return
	var ground: HexagonTileMapLayer = host.ground_layer
	var point: Vector2 = ground.get_global_transform_with_canvas().affine_inverse() * screen_point
	var cell: Vector2i = ground.local_to_map(point)
	if ground.get_cell_source_id(cell) == -1 or get_viewport().gui_get_hovered_control() != null:
		LOSHelper.clear_los()
		return
	var asset: Dictionary = assets[selected_asset]
	if asset["battery"] == null and is_instance_valid(representative_unit(selected_asset)):
		var unit: Unit = representative_unit(selected_asset)
		var pool: Array[Soldier] = eligible_guns(selected_asset, [cell])
		if not pool.is_empty():
			unit = pool[0].unit
		var feedback: Dictionary = MatchInteractionHandler.unit_target_feedback(unit, cell)
		LOSHelper.draw_los(unit.position, point, float(feedback["firepower"]))

func preview(index: int, cell: Vector2i, cells: Array[Vector2i] = []) -> String:
	var footprint: Array[Vector2i] = cells
	if footprint.is_empty():
		footprint = [cell]
	var reason: String = footprint_restriction(index, footprint)
	if not reason.is_empty():
		return reason
	var observed_cells: Dictionary[Vector2i, bool] = {}
	var friends: int = 0
	for unit: Unit in Globals.get_units_for_team(Globals.team_player):
		if not unit.is_active() or unit.surrendered:
			continue
		if footprint.has(unit.current_hex):
			friends += 1
		var visibility: Dictionary = LOSHelper.los_lookup.get(unit.current_hex, {})
		for covered: Vector2i in footprint:
			if visibility.has(covered):
				observed_cells[covered] = true
	var text: String = "Unobserved · map fire"
	if observed_cells.size() == footprint.size():
		text = "Observed by friendly troops"
	elif not observed_cells.is_empty():
		text = "Partly observed · %d/%d hexes" % [observed_cells.size(), footprint.size()]
	var asset: Dictionary = assets[index]
	var eta: float = 0.0
	if asset["battery"] != null:
		var battery: OffboardBattery = asset["battery"]
		eta = battery.response_seconds + battery.flight_seconds
	else:
		var pool: Array[Soldier] = eligible_guns(index, footprint)
		var moving: bool = false
		for gun: int in range(mini(selected_guns(index), pool.size())):
			var soldier: Soldier = pool[gun]
			var unit: Unit = soldier.unit
			var setup: float = 0.0
			var reload: float = 0.0
			if not soldier.setup_weapon_task.done:
				setup = soldier.setup_weapon_task.remaining_time_s
			if not soldier.reload_task.done:
				reload = soldier.reload_task.remaining_time_s
			var gun_eta: float = setup + reload + soldier.weapon.raise_s + soldier.weapon.aim_s + unit.global_position.distance_to(host.ground_layer.to_global(host.ground_layer.map_to_local(cell))) / maxf(float(soldier.weapon.projectile_speed), 1.0)
			eta = maxf(eta, gun_eta)
			moving = moving or unit.is_moving
		if moving:
			text += "\nMortar will halt and deploy"
	text += "\nEstimated first impact: about %d s" % ceili(eta)
	if friends > 0:
		text += "\nFRIENDLY TROOPS IN TARGET FOOTPRINT"
	return text

func _process(delta: float) -> void:
	if not is_instance_valid(host):
		return
	if host.end_game_handled and not host.continuing_after_end:
		for index: int in range(assets.size()):
			cease(index)
		flights.clear()
		pending_volley.clear()
		choosing_target = false
		dragging = false
		has_target = false
		return
	for mission: FireSupportMission in missions:
		mission.elapsed += delta
		if mission.active and mission.time_expired():
			mission.stop("Time complete · airborne rounds still land")
	for index: int in range(assets.size()):
		var asset: Dictionary = assets[index]
		var mission: FireSupportMission = asset_mission(index)
		if mission == null:
			continue
		if not mission.active:
			_cancel_volley(mission)
			_release_onboard(asset, mission)
			continue
		if ammunition(index) <= 0:
			mission.stop("Ammunition exhausted")
			_release_onboard(asset, mission)
			continue
		if asset["battery"] != null:
			if mission.ready_to_fire() and mission.pending_guns == 0:
				_begin_volley(asset, mission)
		else:
			_update_onboard(asset, mission)
	for shot: Dictionary in pending_volley.duplicate():
		var mission: FireSupportMission = shot["mission"]
		if not mission.active or mission.time_expired():
			_cancel_volley(mission)
			continue
		if mission.elapsed >= float(shot["at"]):
			pending_volley.erase(shot)
			mission.pending_guns -= 1
			_launch_offboard(shot["asset"], mission, float(shot["volley_at"]))
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

func _update_onboard(asset: Dictionary, mission: FireSupportMission) -> void:
	for soldier: Soldier in mission.onboard_guns.duplicate():
		var unit: Unit = soldier.unit
		var keep: bool = is_instance_valid(unit) and unit.is_active() and not unit.broken and not unit.surrendered and not unit.in_close_combat
		if keep:
			keep = soldier.is_alive and soldier.weapon.ammunition > 0 and unit.squad_fire.fire_support_mission == mission and _has_mission_order(unit, mission)
		if not keep:
			mission.onboard_guns.erase(soldier)
			mission.onboard_due.erase(soldier)
	mission.pending_guns = mission.onboard_due.size()
	for unit: Unit in asset["units"]:
		if not is_instance_valid(unit) or unit.squad_fire.fire_support_mission != mission:
			continue
		var participating: bool = false
		for soldier: Soldier in mission.onboard_guns:
			if soldier.unit == unit:
				participating = true
		if not participating:
			unit.squad_fire.fire_support_mission = null
			if _has_mission_order(unit, mission):
				unit.squad_fire.fire_support_hold = true
				unit.squad_fire.clear_target()
	if mission.onboard_guns.is_empty():
		mission.stop("Interrupted · no participating guns available")
		return
	if mission.guns > 1 and mission.pending_guns == 0 and mission.ready_to_fire():
		for soldier: Soldier in mission.onboard_guns:
			if soldier.unit.is_moving or not _crew_task_ready(soldier.setup_weapon_task) or not _crew_task_ready(soldier.reload_task) or not _crew_task_ready(soldier.aquire_target_task):
				return
		mission.begin_onboard_volley()

func _has_mission_order(unit: Unit, mission: FireSupportMission) -> bool:
	return unit.attackState == Unit.AttackState.MANUAL_GROUND and unit.squad_fire.has_mortar_target_hex and unit.squad_fire.mortar_target_hex == mission.target

func _crew_task_ready(task: SoldierTask) -> bool:
	return task.done or task.remaining_time_s <= 0.0

func _cancel_volley(mission: FireSupportMission) -> void:
	for shot: Dictionary in pending_volley.duplicate():
		if shot["mission"] == mission:
			pending_volley.erase(shot)
	mission.pending_guns = 0

func _begin_volley(asset: Dictionary, mission: FireSupportMission) -> void:
	var count: int = mini(mission.guns, mini(mission.remaining, (asset["weapon"] as WeaponSpec).ammunition))
	if count <= 0:
		return
	var volley_at: float = mission.elapsed
	mission.pending_guns = count - 1
	for gun: int in range(1, count):
		pending_volley.append({"asset": asset, "mission": mission, "at": volley_at + float(gun) / float(count - 1) * 0.45 + randf_range(0.0, 0.05), "volley_at": volley_at})
	_launch_offboard(asset, mission, volley_at)

func _launch_offboard(asset: Dictionary, mission: FireSupportMission, volley_at: float = -1.0) -> void:
	var battery: OffboardBattery = asset["battery"]
	var weapon: WeaponSpec = asset["weapon"]
	if not mission.active or mission.remaining <= 0 or weapon.ammunition <= 0 or mission.time_expired():
		return
	var impact_cell: Vector2i = mission.next_target()
	weapon.ammunition -= 1
	mission.commit_rounds(1)
	mission.next_round = maxf(mission.next_round, mission.elapsed + weapon.reload_s)
	if volley_at >= 0.0:
		mission.last_launch_at = volley_at
		mission.next_round = volley_at + maxf(FireSupportMission.INTERVALS[mission.intensity], weapon.reload_s)
	var ground: HexagonTileMapLayer = host.ground_layer
	var finish: Vector2 = ground.to_global(ground.map_to_local(impact_cell))
	var origin: Vector2 = _offboard_origin(finish, float(weapon.projectile_speed) * battery.flight_seconds)
	var source: Unit = asset["unit"]
	source.position = origin
	flights.append({"source": source, "weapon": weapon, "target": impact_cell, "time": battery.flight_seconds, "cover": LOSHelper.is_sample_point_in_building(ground.map_to_local(impact_cell)), "origin": origin, "new": true})
	var effect: BattlefieldTracer = BattlefieldEffects.for_scene(self).fire(origin, finish, weapon, BattlefieldTracer.Kind.MORTAR, TRACER_SCENE)
	if effect != null:
		# Extending the approach beyond the board must preserve the authored impact time.
		effect.flight_time = battery.flight_seconds
		effect.speed = origin.distance_to(finish) / battery.flight_seconds

func _offboard_origin(finish: Vector2, flight_distance: float) -> Vector2:
	var ground: HexagonTileMapLayer = host.ground_layer
	var scenario: Scenario = Globals.scenario_chosen
	var start: Vector2 = ground.to_global(ground.map_to_local(scenario.start_hex[Globals.team_player]))
	var direction: Vector2 = finish.direction_to(start)
	if direction.is_zero_approx():
		var enemy_start: Vector2 = ground.to_global(ground.map_to_local(scenario.start_hex[Globals.get_enemy_team(Globals.team_player)]))
		direction = enemy_start.direction_to(start)
	if direction.is_zero_approx():
		direction = Vector2.DOWN
	var bounds: Rect2 = Rect2(finish, Vector2.ZERO)
	for cell: Vector2i in ground.get_used_cells():
		bounds = bounds.expand(ground.to_global(ground.map_to_local(cell)))
	# A full tile diagonal keeps the launch outside even the outermost hex corners.
	var margin: float = Vector2(ground.tile_set.tile_size).length() * maxf(ground.global_transform.x.length(), ground.global_transform.y.length())
	bounds = bounds.grow(margin)
	var exit_distance: float = INF
	if direction.x > 0.00001:
		exit_distance = minf(exit_distance, (bounds.end.x - finish.x) / direction.x)
	elif direction.x < -0.00001:
		exit_distance = minf(exit_distance, (bounds.position.x - finish.x) / direction.x)
	if direction.y > 0.00001:
		exit_distance = minf(exit_distance, (bounds.end.y - finish.y) / direction.y)
	elif direction.y < -0.00001:
		exit_distance = minf(exit_distance, (bounds.position.y - finish.y) / direction.y)
	return finish + direction * maxf(flight_distance, exit_distance + margin)

func _draw() -> void:
	if not is_instance_valid(host) or not is_instance_valid(host.ground_layer):
		return
	for mission: FireSupportMission in missions:
		if mission.active:
			_draw_footprint(mission.cells, mission.shape, mission.target, mission.end, mission.radius, Color(1.0, 0.48, 0.25, 0.65))
	if has_target or dragging:
		_draw_footprint(target_cells, target_shape, target, target_end, target_radius, Color(1.0, 0.28, 0.18, 0.9))
		for unit: Unit in Globals.get_units_for_team(Globals.team_player):
			if unit.is_active() and target_cells.has(unit.current_hex):
				var center: Vector2 = to_local(unit.global_position)
				draw_arc(center, 48.0, 0.0, TAU, 40, Color(1.0, 0.78, 0.2), 4.0, true)

func _draw_footprint(cells: Array[Vector2i], shape: FireSupportMission.Shape, start: Vector2i, end: Vector2i, radius: int, color: Color) -> void:
	var ground: HexagonTileMapLayer = host.ground_layer
	var tile_shape: ConvexPolygonShape2D = ground.geometry_tile_shape.shape as ConvexPolygonShape2D
	for cell: Vector2i in cells:
		var points: PackedVector2Array = PackedVector2Array()
		for corner: Vector2 in tile_shape.points:
			points.append(to_local(ground.to_global(ground.map_to_local(cell) + corner * 0.94)))
		draw_colored_polygon(points, Color(color, color.a * 0.16))
		points.append(points[0])
		draw_polyline(points, Color(color, color.a * 0.55), 1.5, true)
	var center: Vector2 = to_local(ground.to_global(ground.map_to_local(start)))
	if shape == FireSupportMission.Shape.LINE:
		var finish: Vector2 = to_local(ground.to_global(ground.map_to_local(end)))
		draw_line(center, finish, color, 3.0, true)
		var arrow: Vector2 = finish.direction_to(center).rotated(0.5) * 16.0
		draw_line(finish, finish + arrow, color, 3.0, true)
		draw_line(finish, finish + arrow.rotated(-1.0), color, 3.0, true)
	elif shape == FireSupportMission.Shape.AREA:
		var spacing: float = 1.0
		for neighbor: Vector2i in ground.get_surrounding_cells(start):
			spacing = maxf(spacing, center.distance_to(to_local(ground.to_global(ground.map_to_local(neighbor)))))
		draw_arc(center, spacing * float(radius), 0.0, TAU, 64, color, 2.0, true)
	_draw_marker(start, color)

func _draw_marker(cell: Vector2i, color: Color) -> void:
	var center: Vector2 = to_local(host.ground_layer.to_global(host.ground_layer.map_to_local(cell)))
	draw_circle(center, 24.0, Color(color, 0.12))
	draw_arc(center, 24.0, 0.0, TAU, 40, color, 2.0, true)
	draw_line(center - Vector2(32, 0), center + Vector2(32, 0), color, 1.0, true)
	draw_line(center - Vector2(0, 32), center + Vector2(0, 32), color, 1.0, true)
