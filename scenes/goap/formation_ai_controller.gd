# formation_ai_controller.gd
class_name FormationAIController
extends Node

#const GoapTypes = preload("res://scenes/goap/goap_types.gd")
#const FormationWorldState = preload("res://scenes/goap/formation_world_state.gd")
#const GoapGoal = preload("res://scenes/goap/goap_goal.gd")
#const GoapAction = preload("res://scenes/goap/goap_action.gd")
#const GoapPlanner = preload("res://scenes/goap/goap_planner.gd")
#const SquadOrder = preload("res://scenes/goap/squad_order.gd")

@export var active: bool = 0
@export var mission_mode: GoapTypes.FormationMissionMode = GoapTypes.FormationMissionMode.DEFEND
@export var team: Globals.Team = Globals.Team.AXIS
@export var formation_id: int = 0

var squads: Array[Unit] = []
var current_goal: GoapGoal = null
var current_plan: Array[GoapAction] = []
var planner: GoapPlanner = GoapPlanner.new()
var replan_cooldown: float = 0.0
var replan_interval: float = 3.0

var enemy_contacts: Array[Unit]


func _ready() -> void:
	_refresh_squad_list()
	_select_goal(null)

func _process(delta: float) -> void:
	if not active:
		return
	if not Globals.game_started:
		return
	replan_cooldown -= delta
	if replan_cooldown <= 0.0:
		_refresh_squad_list()
		_run_goap_cycle()
		replan_cooldown = replan_interval
		

func _refresh_squad_list() -> void:
	squads.clear()
	var units: Array[Node] = get_tree().get_nodes_in_group("units")
	var has_unit_in_formation: bool = false
	for n in units:
		var squad: Node = n
		if squad.has_method("get_formation_id"):
			var f_id: int = squad.get_formation_id()
			var s_team: Globals.Team = squad.team
			if f_id == formation_id and s_team == team:
				has_unit_in_formation = true
				if squad.is_good_order():
					squads.append(squad)
	if not has_unit_in_formation:
		queue_free()
	for squad in squads:
		if not is_instance_valid(squad):
			continue
		if not squad.contacts_reported.is_connected(_on_squad_contact_reported):
			squad.contacts_reported.connect(_on_squad_contact_reported)
		if not squad.new_target_hex.is_connected(_on_new_target_hex):
			squad.new_target_hex.connect(_on_new_target_hex)
		squad.formation_squads = squads.duplicate()


func _on_new_target_hex(unit: Unit, end_of_path_hex: Vector2i):
	return


func _refresh_enemy_contacts() -> void:
	enemy_contacts.clear()
	for squad in squads:
		for enemy_contact in squad.enemies_reported:
			if not enemy_contacts.has(enemy_contact) and enemy_contact.is_good_order():
				enemy_contacts.append(enemy_contact)
	for squad in squads:
		squad.enemies_reported_from_formation = enemy_contacts

func _on_squad_contact_reported(unit: Unit, contacts: Array[Unit]):
	if not is_instance_valid(unit):
		return
	if not unit.is_alive():
		return
	
	if contacts.is_empty():
		return
	
	#for contact in contacts:
		#if not enemy_contacts.has(contact):
			#enemy_contacts.append(contact)
	
	_assign_contact_reaction(unit, contacts[0].current_hex)


func _assign_contact_reaction(bo_f_squad: Unit, contact_hex: Vector2i) -> void:
	if not is_instance_valid(bo_f_squad):
		return
	
	var curr_bof_order: SquadOrder = bo_f_squad.current_order
	var current_bof_order_type: GoapTypes.SquadOrderType = bo_f_squad.current_order.order_type
	
	#BASE_OF_FIRE,  2
	#ASSAULT_ROUTE, 3
	
	#if bo_f_squad.tactical_state.is_free():
		## 1. Base-of-fire order for reporting squad
		#bo_f_squad.tactical_state.formation_role = bo_f_squad.tactical_state.FormationRole.BASE_OF_FIRE
		#
		#var bof_order: SquadOrder = SquadOrder.new()
		#bof_order.target_hexes.clear()
		#bof_order.target_hexes.append(contact_hex)
		##bof_order.target_hexes.append(bo_f_squad.get_current_hex())
		##bof_order.fire_arc_center_deg = _compute_fire_arc_towards(bo_f_squad.get_current_hex(), contact_hex)
		##bof_order.fire_arc_width_deg = 90.0
		#bof_order.aggressiveness = 1.0
#
		#_set_squad_order(bo_f_squad, GoapTypes.SquadOrderType.BASE_OF_FIRE, bof_order)
#
	## 2. Find an assault buddy
	#var assault_squad: Unit = _pick_assault_partner(bo_f_squad)
	#if assault_squad == null:
		#return
	#
	#var curr_ass_order: SquadOrder = assault_squad.current_order
	#var current_ass_order_type: GoapTypes.SquadOrderType = assault_squad.current_order.order_type
	#
	#
	#if assault_squad.tactical_state.is_free():
		## 3. Build a simple assault route: from assault squad position to objective via cover.
		##var assault_route: Array[Vector2i] = _build_assault_route(assault_squad, contact_hex)
		#assault_squad.tactical_state.formation_role = assault_squad.tactical_state.FormationRole.ASSAULT
#
		#var assault_order: SquadOrder = SquadOrder.new()
		##assault_order.target_hexes = assault_route
		#assault_order.aggressiveness = 1.2
#
		##_set_squad_order(assault_squad, GoapTypes.SquadOrderType.ASSAULT_ROUTE, assault_order)
		#
		#assault_order.target_hexes.clear()
		#assault_order.target_hexes.append(contact_hex)
		#_set_squad_order(assault_squad, GoapTypes.SquadOrderType.BASE_OF_FIRE, assault_order)

func _pick_assault_partner(bo_f_squad: Node) -> Node:
	var best_squad: Node = null
	var best_score: float = -1.0

	for squad in squads:
		if not is_instance_valid(squad):
			continue
		if not squad.is_alive():
			continue
		if squad == bo_f_squad:
			continue
		if squad.team != bo_f_squad.team:
			continue

		# Avoid pinned / routing squads
		#if squad.is_pinned_or_worse():
			#continue

		# Prefer squads already on ASSAULT_ROUTE or ADVANCING
		var score: float = 0.0

		if squad.current_order.order_type == GoapTypes.SquadOrderType.ASSAULT_ROUTE:
			score += 2.0

		# this is not hex distance, change that
		var d: float = bo_f_squad.current_hex.distance_to(squad.current_hex)
		if d > 0.0:
			score += 1.0 / d

		if best_squad == null or score > best_score:
			best_squad = squad
			best_score = score

	return best_squad


#func _compute_fire_arc_towards(from_hex: Vector2i, to_hex: Vector2i) -> float:
	#var from_world: Vector2 = _hex_to_world(from_hex)
	#var to_world: Vector2 = _hex_to_world(to_hex)
	#var dir: Vector2 = to_world - from_world
	#if dir.length_squared() == 0.0:
		#return 0.0
	#return dir.angle() * 180.0 / PI
	


func _build_world_state() -> FormationWorldState:
	var s: FormationWorldState = FormationWorldState.new()
	s.mission_mode = mission_mode

	var total_E: float = 0.0
	var alive_count: int = 0
	var reserve_count: int = 0
	var low_E_count: int = 0

	for squad in squads:
		if not is_instance_valid(squad):
			squads.erase(squad)
			continue
		if not squad.has_method("is_alive") or not squad.is_alive():
			continue

		alive_count += 1

		if squad.has_method("get_effectiveness"):
			var e_value: float = squad.get_effectiveness()
			total_E += e_value
			if e_value < 0.3:
				low_E_count += 1

		if squad.has_method("is_reserve_candidate") and squad.is_reserve_candidate():
			reserve_count += 1

	s.has_enemy_contacts = false
	if not enemy_contacts.is_empty():
		s.has_enemy_contacts = true
	
	#s.base_of_fire_established = false
	#for squad in squads:
		#if squad.tactical_state:
			#if squad.tactical_state.formation_role == squad.tactical_state.FormationRole.BASE_OF_FIRE:
				#s.base_of_fire_established = true
	
	s.assault_plan_ready = false
	for squad in squads:
		if not is_instance_valid(squad):
			continue
		if squad.current_order.order_type == GoapTypes.SquadOrderType.ASSAULT_ROUTE:
			s.assault_plan_ready = true
	
	s.objective_held = false
	var occupying_units : Array
	for squad in Globals.units:
		if not is_instance_valid(squad):
			continue
		if not squad.team == team:
			continue
		if Globals.objective_hexes.has(squad.team):
			if not Globals.objective_hexes[squad.team].is_empty():
				if squad.current_hex == Globals.objective_hexes[squad.team][0]:
					occupying_units.append(squad)
	for squad in occupying_units:
		if squad.is_good_order():
			s.objective_held = true

	return s

func _select_goal(state: FormationWorldState) -> void:
	var st: FormationWorldState = state
	if st == null:
		st = _build_world_state()

	var goals: Array[GoapGoal] = []

	var g_def: GoapGoal = GoapGoal.new()
	g_def.goal_id = GoapTypes.FormationGoalId.MAINTAIN_DEFENSE
	g_def.base_priority = 5.0
	goals.append(g_def)

	var g_att: GoapGoal = GoapGoal.new()
	g_att.goal_id = GoapTypes.FormationGoalId.CAPTURE_OBJECTIVE
	g_att.base_priority = 5.0
	goals.append(g_att)

	var g_delay: GoapGoal = GoapGoal.new()
	g_delay.goal_id = GoapTypes.FormationGoalId.DELAY_ENEMY
	g_delay.base_priority = 3.0
	goals.append(g_delay)

	var g_info: GoapGoal = GoapGoal.new()
	g_info.goal_id = GoapTypes.FormationGoalId.GAIN_INFORMATION
	g_info.base_priority = 2.0
	goals.append(g_info)

	var g_improve: GoapGoal = GoapGoal.new()
	g_improve.goal_id = GoapTypes.FormationGoalId.IMPROVE_SITUATION
	g_improve.base_priority = 1.0
	goals.append(g_improve)

	var best_goal: GoapGoal = goals[0]
	var best_score: float = goals[0].compute_dynamic_priority(st)

	var i: int = 1
	var size: int = goals.size()
	while i < size:
		var g: GoapGoal = goals[i]
		var score: float = g.compute_dynamic_priority(st)
		if score > best_score:
			best_score = score
			best_goal = g
		i += 1

	current_goal = best_goal

func _build_action_set(state: FormationWorldState) -> Array[GoapAction]:
	var actions: Array[GoapAction] = []
	
	var a_def_pos: GoapAction = GoapAction.new()
	a_def_pos.action_id = GoapTypes.FormationActionId.DEFEND_POSITION
	a_def_pos.base_cost = 2.0
	actions.append(a_def_pos)
	
	var a_def_obj: GoapAction = GoapAction.new()
	a_def_obj.action_id = GoapTypes.FormationActionId.DEFEND_OBJECTIVE
	a_def_obj.base_cost = 2.0
	actions.append(a_def_obj)

	var a_move: GoapAction = GoapAction.new()
	a_move.action_id = GoapTypes.FormationActionId.MOVE_TO_OBJECTIVE
	a_move.base_cost = 2.0
	actions.append(a_move)

	var a_prep: GoapAction = GoapAction.new()
	a_prep.action_id = GoapTypes.FormationActionId.PREPARE_ASSAULT
	a_prep.base_cost = 2.0
	actions.append(a_prep)
	
	var a_bof: GoapAction = GoapAction.new()
	a_bof.action_id = GoapTypes.FormationActionId.POSITION_BASE_OF_FIRE
	a_bof.base_cost = 2.0
	actions.append(a_bof)

	var a_ass: GoapAction = GoapAction.new()
	a_ass.action_id = GoapTypes.FormationActionId.POSITION_ASSAULT_ELEMENT
	a_ass.base_cost = 2.0
	actions.append(a_ass)

	var a_fs: GoapAction = GoapAction.new()
	a_fs.action_id = GoapTypes.FormationActionId.GAIN_FIRE_SUPERIORITY
	a_fs.base_cost = 3.0
	actions.append(a_fs)

	var a_launch: GoapAction = GoapAction.new()
	a_launch.action_id = GoapTypes.FormationActionId.LAUNCH_ASSAULT
	a_launch.base_cost = 4.0
	actions.append(a_launch)

	return actions

func _run_goap_cycle() -> void:
	_refresh_squad_list()
	_refresh_enemy_contacts()
	
	var state: FormationWorldState = _build_world_state()

	_select_goal(state)

	var actions: Array[GoapAction] = _build_action_set(state)
	current_plan = planner.plan(state, current_goal, actions)

	if current_plan.size() == 0:
		return

	var first_action: GoapAction = current_plan[0]
	_dispatch_action(first_action)

func _dispatch_action(action: GoapAction) -> void:
	match action.action_id:
		#GoapTypes.FormationActionId.ESTABLISH_DEFENSE_LINE:
			#_assign_defense_orders()
		#GoapTypes.FormationActionId.ASSIGN_BASE_OF_FIRE:
			#_assign_base_of_fire_orders()
		#GoapTypes.FormationActionId.COVER_FLANK:
			#_assign_cover_flank_orders(action.flank_side_left)
		#GoapTypes.FormationActionId.WITHDRAW_TO_FALLBACK:
			#_assign_withdraw_orders()
		#GoapTypes.FormationActionId.REORGANIZE_AND_MERGE:
			#_assign_reorganize_orders()
		#GoapTypes.FormationActionId.PROBE_AXIS:
			#_assign_probe_orders()
		GoapTypes.FormationActionId.DEFEND_OBJECTIVE:
			_assign_defend_objective()
		GoapTypes.FormationActionId.DEFEND_POSITION:
			_assign_defend_position()
		GoapTypes.FormationActionId.MOVE_TO_OBJECTIVE:
			_assign_move_to_objective()
		GoapTypes.FormationActionId.PREPARE_ASSAULT:
			_assign_prepare_assault_orders()
		GoapTypes.FormationActionId.POSITION_BASE_OF_FIRE:
			_assign_position_base_of_fire()
		GoapTypes.FormationActionId.POSITION_ASSAULT_ELEMENT:
			_assign_position_assault_element()
		GoapTypes.FormationActionId.GAIN_FIRE_SUPERIORITY:
			_assign_gain_fire_superiority()
		GoapTypes.FormationActionId.LAUNCH_ASSAULT:
			_assign_launch_assault_orders()
		#GoapTypes.FormationActionId.SHIFT_AXIS:
			#_assign_shift_axis_orders()
		#GoapTypes.FormationActionId.COMMIT_RESERVE:
			#_assign_commit_reserve_orders()
		#GoapTypes.FormationActionId.ROTATE_SQUADS_IN_LINE:
			#_assign_rotate_line_orders()
		#GoapTypes.FormationActionId.REST_AND_RESUPPLY:
			#_assign_rest_orders()

func _set_squad_order(squad: Unit, order_type: int, params: SquadOrder) -> void:
	if not squad.has_method("set_order_resource"):
		return
	params.order_type = order_type
	squad.set_order_resource(params)


func _assign_prepare_assault_orders() -> void:
	var i: int = 0
	for squad in squads:
		if not squad.is_good_order():
			continue
		if i == 0:
			var order: SquadOrder = SquadOrder.new()
			order.aggressiveness = 0.8
			# need to set order.target_hexes here so the squad knows where to go and start firing
			_set_squad_order(squad, GoapTypes.SquadOrderType.BASE_OF_FIRE, order)
		else:
			#if not squad.has_reported_contact:
			var order: SquadOrder = SquadOrder.new()
			order.aggressiveness = 0.8
			_set_squad_order(squad, GoapTypes.SquadOrderType.BASE_OF_FIRE, order)
			#_set_squad_order(squad, GoapTypes.SquadOrderType.ASSAULT_ROUTE, order)
		i += 1

func _assign_position_base_of_fire() -> void:
	return
	var base_of_fire_squads: Array[Unit]
	for squad in squads:
		if not squad.is_good_order():
			continue
		if squad.current_order.order_type == GoapTypes.SquadOrderType.BASE_OF_FIRE:
			base_of_fire_squads.append(squad)
	var visible_hexes_by_enemy: Array[Vector2i] = LOSHelper.los_lookup.get(enemy_contacts[0].current_hex, [])
	for squad in base_of_fire_squads:
		var closest_distance: int = 1000
		var closest_hex: Vector2i
		for hex in visible_hexes_by_enemy:
			var cube: Vector3i = LOSHelper.ground_layer.map_to_cube(hex)
			var distance: int = LOSHelper.ground_layer.cube_distance(squad.current_cube, cube)
			if distance < closest_distance:
				closest_distance = distance
				closest_hex = LOSHelper.ground_layer.cube_to_map(cube)
		var order: SquadOrder = SquadOrder.new()
		_set_squad_order(squad, GoapTypes.SquadOrderType.MOVE_TO, order)

func _assign_position_assault_element() -> void:
	pass

func _assign_gain_fire_superiority() -> void:
	pass



func _assign_defend_objective():
	var i: int = 0
	for squad in squads:
		if not squad.is_good_order():
			continue
		if i == 0:
			var order: SquadOrder = SquadOrder.new()
			order.aggressiveness = 0.8
			# need to set order.target_hexes here so the squad knows where to go and start firing
			_set_squad_order(squad, GoapTypes.SquadOrderType.DEFEND_POSITION, order)
		i += 1


func _assign_defend_position():
	var i: int = 0
	for squad in squads:
		if not squad.is_good_order():
			continue
		if i == 0:
			var order: SquadOrder = SquadOrder.new()
			order.aggressiveness = 0.8
			# need to set order.target_hexes here so the squad knows where to go and start firing
			_set_squad_order(squad, GoapTypes.SquadOrderType.DEFEND_OBJECTIVE, order)
		i += 1


func _assign_move_to_objective() -> void:
	#return
	for squad in squads:
		if not squad.is_good_order():
			continue
		#if squad.tactical_state.is_free():
		var order: SquadOrder = SquadOrder.new()
		order.aggressiveness = 0.8
		_set_squad_order(squad, GoapTypes.SquadOrderType.MOVE_TO, order)




func _assign_launch_assault_orders() -> void:
	for squad in squads:
		if not squad.is_good_order():
			continue
		if squad.tactical_state.formation_role == squad.tactical_state.FormationRole.ASSAULT:
			var order: SquadOrder = SquadOrder.new()
			order.aggressiveness = 1.2
			_set_squad_order(squad, GoapTypes.SquadOrderType.ASSAULT_ROUTE, order)

#func _assign_base_of_fire_orders() -> void:
	#for squad in squads:
		##if squad.has_method("is_mg_team") and squad.is_mg_team():
		#if squad.tactical_state.is_free():
			#var order: SquadOrder = SquadOrder.new()
			#order.aggressiveness = 1.0
			#_set_squad_order(squad, GoapTypes.SquadOrderType.BASE_OF_FIRE, order)
			#break
