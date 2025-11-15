# formation_ai_controller.gd
class_name FormationAIController
extends Node

#const GoapTypes = preload("res://scenes/goap/goap_types.gd")
#const FormationWorldState = preload("res://scenes/goap/formation_world_state.gd")
#const GoapGoal = preload("res://scenes/goap/goap_goal.gd")
#const GoapAction = preload("res://scenes/goap/goap_action.gd")
#const GoapPlanner = preload("res://scenes/goap/goap_planner.gd")
#const SquadOrder = preload("res://scenes/goap/squad_order.gd")

@export var mission_mode: GoapTypes.FormationMissionMode = GoapTypes.FormationMissionMode.DEFEND
@export var formation_id: int = 0

var squads: Array[Unit] = []
var current_goal: GoapGoal = null
var current_plan: Array[GoapAction] = []
var planner: GoapPlanner = GoapPlanner.new()
var replan_cooldown: float = 0.0
var replan_interval: float = 3.0

func _ready() -> void:
	_refresh_squad_list()
	_select_goal(null)

func _process(delta: float) -> void:
	if not Globals.game_started:
		return
	replan_cooldown -= delta
	if replan_cooldown <= 0.0:
		_run_goap_cycle()
		replan_cooldown = replan_interval

func _refresh_squad_list() -> void:
	squads.clear()
	var units: Array[Node] = get_tree().get_nodes_in_group("units")
	for n in units:
		var squad: Node = n
		if squad.has_method("get_formation_id"):
			var f_id: int = squad.get_formation_id()
			if f_id == formation_id:
				squads.append(squad)
	for squad in squads:
		if not is_instance_valid(squad):
			continue
		if not squad.contacts_reported.is_connected(_on_squad_contact_reported):
			squad.contacts_reported.connect(_on_squad_contact_reported)


func _on_squad_contact_reported(unit: Unit, contacts: Array[Unit]):
	if not is_instance_valid(unit):
		return
	if not unit.is_alive():
		return
	
	if contacts.is_empty():
		return
	
	_assign_contact_reaction(unit, contacts[0].current_hex)


func _assign_contact_reaction(bo_f_squad: Unit, contact_hex: Vector2i) -> void:
	if not is_instance_valid(bo_f_squad):
		return
	
	var curr_bof_order: SquadOrder = bo_f_squad.current_order
	var current_bof_order_type: GoapTypes.SquadOrderType = bo_f_squad.current_order.order_type
	
	#BASE_OF_FIRE,  2
	#ASSAULT_ROUTE, 3
	
	if not bo_f_squad.current_order.order_type == GoapTypes.SquadOrderType.BASE_OF_FIRE:
		# 1. Base-of-fire order for reporting squad
		var bof_order: SquadOrder = SquadOrder.new()
		bof_order.target_hexes.clear()
		bof_order.target_hexes.append(contact_hex)
		#bof_order.target_hexes.append(bo_f_squad.get_current_hex())
		#bof_order.fire_arc_center_deg = _compute_fire_arc_towards(bo_f_squad.get_current_hex(), contact_hex)
		#bof_order.fire_arc_width_deg = 90.0
		bof_order.aggressiveness = 1.0

		_set_squad_order(bo_f_squad, GoapTypes.SquadOrderType.BASE_OF_FIRE, bof_order)

	# 2. Find an assault buddy
	var assault_squad: Node = _pick_assault_partner(bo_f_squad)
	if assault_squad == null:
		return
	
	var curr_ass_order: SquadOrder = assault_squad.current_order
	var current_ass_order_type: GoapTypes.SquadOrderType = assault_squad.current_order.order_type
	
	
	if not assault_squad.current_order.order_type == GoapTypes.SquadOrderType.ASSAULT_ROUTE:
		# 3. Build a simple assault route: from assault squad position to objective via cover.
		#var assault_route: Array[Vector2i] = _build_assault_route(assault_squad, contact_hex)

		var assault_order: SquadOrder = SquadOrder.new()
		#assault_order.target_hexes = assault_route
		assault_order.aggressiveness = 1.2

		#_set_squad_order(assault_squad, GoapTypes.SquadOrderType.ASSAULT_ROUTE, assault_order)
		
		assault_order.target_hexes.clear()
		assault_order.target_hexes.append(contact_hex)
		_set_squad_order(assault_squad, GoapTypes.SquadOrderType.BASE_OF_FIRE, assault_order)

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


	if alive_count > 0:
		var avg_E: float = total_E / float(alive_count)
		if avg_E > 0.66:
			s.friendly_E_level = GoapTypes.WorldELevel.HIGH
		elif avg_E > 0.33:
			s.friendly_E_level = GoapTypes.WorldELevel.MED
		else:
			s.friendly_E_level = GoapTypes.WorldELevel.LOW
	else:
		s.friendly_E_level = GoapTypes.WorldELevel.LOW

	if reserve_count > 0:
		s.reserve_present = true
	else:
		s.reserve_present = false

	# Placeholder hooks for now
	s.line_established = true
	s.fallback_line_available = true
	s.base_of_fire_established = false
	
	s.assault_element_ready = false
	for squad in squads:
		if not is_instance_valid(squad):
			break
		if squad.current_order.order_type == GoapTypes.SquadOrderType.ASSAULT_ROUTE:
			s.assault_element_ready = true
	
	s.left_flank_exposed = true
	s.right_flank_exposed = true
	s.contact_uncertain = true
	s.enemy_E_on_main_axis = GoapTypes.WorldELevel.MED
	s.casualty_level = GoapTypes.WorldELevel.LOW
	s.ammo_state_global = GoapTypes.WorldAmmoLevel.OK
	s.time_pressure_high = false
	
	s.objective_clear = false
	s.objective_held = false
	var occupying_units : Array
	for squad in squads:
		if not is_instance_valid(squad):
			break
		if squad.current_hex == Globals.objective_hex:
			occupying_units.append(squad)
	for squad in occupying_units:
		if not squad.is_good_order():
			s.objective_held = true
			s.objective_clear = true
	
	s.objective_contested = false
	
	s.route_to_objective_secure = false
	s.probe_result = GoapTypes.WorldProbeResult.UNKNOWN

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

	var a_def: GoapAction = GoapAction.new()
	a_def.action_id = GoapTypes.FormationActionId.ESTABLISH_DEFENSE_LINE
	a_def.base_cost = 1.0
	actions.append(a_def)

	var a_bof: GoapAction = GoapAction.new()
	a_bof.action_id = GoapTypes.FormationActionId.ASSIGN_BASE_OF_FIRE
	a_bof.base_cost = 1.0
	actions.append(a_bof)

	var a_flank: GoapAction = GoapAction.new()
	a_flank.action_id = GoapTypes.FormationActionId.COVER_FLANK
	a_flank.base_cost = 1.0
	a_flank.flank_side_left = true
	actions.append(a_flank)

	var a_wd: GoapAction = GoapAction.new()
	a_wd.action_id = GoapTypes.FormationActionId.WITHDRAW_TO_FALLBACK
	a_wd.base_cost = 2.0
	actions.append(a_wd)

	var a_reorg: GoapAction = GoapAction.new()
	a_reorg.action_id = GoapTypes.FormationActionId.REORGANIZE_AND_MERGE
	a_reorg.base_cost = 2.0
	actions.append(a_reorg)

	var a_probe: GoapAction = GoapAction.new()
	a_probe.action_id = GoapTypes.FormationActionId.PROBE_AXIS
	a_probe.base_cost = 1.0
	actions.append(a_probe)

	var a_prep: GoapAction = GoapAction.new()
	a_prep.action_id = GoapTypes.FormationActionId.PREPARE_ASSAULT
	a_prep.base_cost = 2.0
	actions.append(a_prep)

	var a_launch: GoapAction = GoapAction.new()
	a_launch.action_id = GoapTypes.FormationActionId.LAUNCH_ASSAULT
	a_launch.base_cost = 4.0
	actions.append(a_launch)

	var a_shift: GoapAction = GoapAction.new()
	a_shift.action_id = GoapTypes.FormationActionId.SHIFT_AXIS
	a_shift.base_cost = 2.0
	actions.append(a_shift)

	var a_commit: GoapAction = GoapAction.new()
	a_commit.action_id = GoapTypes.FormationActionId.COMMIT_RESERVE
	a_commit.base_cost = 3.0
	actions.append(a_commit)

	var a_rotate: GoapAction = GoapAction.new()
	a_rotate.action_id = GoapTypes.FormationActionId.ROTATE_SQUADS_IN_LINE
	a_rotate.base_cost = 1.0
	actions.append(a_rotate)

	var a_rest: GoapAction = GoapAction.new()
	a_rest.action_id = GoapTypes.FormationActionId.REST_AND_RESUPPLY
	a_rest.base_cost = 1.0
	actions.append(a_rest)

	return actions

func _run_goap_cycle() -> void:
	_refresh_squad_list()
	
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
		GoapTypes.FormationActionId.ESTABLISH_DEFENSE_LINE:
			_assign_defense_orders()
		GoapTypes.FormationActionId.ASSIGN_BASE_OF_FIRE:
			_assign_base_of_fire_orders()
		GoapTypes.FormationActionId.COVER_FLANK:
			_assign_cover_flank_orders(action.flank_side_left)
		GoapTypes.FormationActionId.WITHDRAW_TO_FALLBACK:
			_assign_withdraw_orders()
		GoapTypes.FormationActionId.REORGANIZE_AND_MERGE:
			_assign_reorganize_orders()
		GoapTypes.FormationActionId.PROBE_AXIS:
			_assign_probe_orders()
		GoapTypes.FormationActionId.PREPARE_ASSAULT:
			_assign_prepare_assault_orders()
		GoapTypes.FormationActionId.LAUNCH_ASSAULT:
			_assign_launch_assault_orders()
		GoapTypes.FormationActionId.SHIFT_AXIS:
			_assign_shift_axis_orders()
		GoapTypes.FormationActionId.COMMIT_RESERVE:
			_assign_commit_reserve_orders()
		GoapTypes.FormationActionId.ROTATE_SQUADS_IN_LINE:
			_assign_rotate_line_orders()
		GoapTypes.FormationActionId.REST_AND_RESUPPLY:
			_assign_rest_orders()

func _set_squad_order(squad: Node, order_type: int, params: SquadOrder) -> void:
	if not squad.has_method("set_order_resource"):
		return
	params.order_type = order_type
	squad.set_order_resource(params)

func _assign_defense_orders() -> void:
	for squad in squads:
		var order: SquadOrder = SquadOrder.new()
		_set_squad_order(squad, GoapTypes.SquadOrderType.DEFEND_LINE, order)

func _assign_base_of_fire_orders() -> void:
	for squad in squads:
		if squad.has_method("is_mg_team") and squad.is_mg_team():
			var order: SquadOrder = SquadOrder.new()
			order.aggressiveness = 1.0
			_set_squad_order(squad, GoapTypes.SquadOrderType.BASE_OF_FIRE, order)

func _assign_cover_flank_orders(left_side: bool) -> void:
	for squad in squads:
		if squad.has_method("is_reserve_candidate") and squad.is_reserve_candidate():
			var order: SquadOrder = SquadOrder.new()
			_set_squad_order(squad, GoapTypes.SquadOrderType.DEFEND_LINE, order)
			break

func _assign_withdraw_orders() -> void:
	for squad in squads:
		var order: SquadOrder = SquadOrder.new()
		_set_squad_order(squad, GoapTypes.SquadOrderType.WITHDRAW_TO, order)

func _assign_reorganize_orders() -> void:
	for squad in squads:
		var order: SquadOrder = SquadOrder.new()
		_set_squad_order(squad, GoapTypes.SquadOrderType.REORGANIZE_MERGE, order)

func _assign_probe_orders() -> void:
	for squad in squads:
		if squad.has_method("is_probe_candidate") and squad.is_probe_candidate():
			var order: SquadOrder = SquadOrder.new()
			order.aggressiveness = 0.5
			_set_squad_order(squad, GoapTypes.SquadOrderType.SCREEN_AXIS, order)
			break

func _assign_prepare_assault_orders() -> void:
	for squad in squads:
		var order: SquadOrder = SquadOrder.new()
		order.aggressiveness = 0.8
		_set_squad_order(squad, GoapTypes.SquadOrderType.ASSAULT_ROUTE, order)

func _assign_launch_assault_orders() -> void:
	for squad in squads:
		if squad.has_method("has_assault_role") and squad.has_assault_role():
			var order: SquadOrder = SquadOrder.new()
			order.aggressiveness = 1.2
			_set_squad_order(squad, GoapTypes.SquadOrderType.ASSAULT_ROUTE, order)

func _assign_shift_axis_orders() -> void:
	_assign_prepare_assault_orders()

func _assign_commit_reserve_orders() -> void:
	for squad in squads:
		if squad.has_method("is_reserve_candidate") and squad.is_reserve_candidate():
			var order: SquadOrder = SquadOrder.new()
			order.aggressiveness = 1.2
			_set_squad_order(squad, GoapTypes.SquadOrderType.ASSAULT_ROUTE, order)

func _assign_rotate_line_orders() -> void:
	# Placeholder: swap tired vs fresh squads on line
	pass

func _assign_rest_orders() -> void:
	for squad in squads:
		if squad.has_method("is_tired") and squad.is_tired():
			var order: SquadOrder = SquadOrder.new()
			order.aggressiveness = 0.0
			_set_squad_order(squad, GoapTypes.SquadOrderType.REST, order)
