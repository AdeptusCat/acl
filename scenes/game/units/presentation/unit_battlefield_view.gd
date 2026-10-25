@tool
extends Control
class_name UnitUi

const PROJECTILE_EFFECTS: Script = preload("res://scenes/game/effects/battlefield_effects.gd")
const TRACER: Script = preload("res://scenes/game/effects/tracer.gd")
const CASUALTY_FEEDBACK: Script = preload("res://scenes/game/effects/casualty_feedback.gd")
const STATE_FEEDBACK: Script = preload("res://scenes/game/effects/unit_state_feedback.gd")

const MEDIUM_INFLUENCE_RATE: float = 0.5
const STRONG_INFLUENCE_RATE: float = 1.5
const ELIMINATION_HOLD_SECONDS: float = 3.0
const ELIMINATION_FADE_SECONDS: float = 5.0
const ELIMINATION_REST_COLOR: Color = Color(0.60, 0.60, 0.60, 0.24)
const FACING_UPDATE_INTERVAL: float = 0.5

var detail_ui: UnitUi = null

@export var sprite_team_0: Texture2D
@export var sprite_team_1: Texture2D
@export var morale_popup_scene: PackedScene
@export var morale_flash_scene: PackedScene
@export var tracer_scene: PackedScene
@export var cover_icon_scene: PackedScene
@export var cautious_texture: Texture
@export var pinned_texture: Texture
@export var panic_texture: Texture
@export var combat_ineffective_texture: Texture

@export var private_texture: Texture
@export var private_first_class_texture: Texture
@export var corporal_texture: Texture
@export var sergeant_texture: Texture
@export var second_lieutenant_texture: Texture
@export var captain_texture: Texture

# === Nodes ===
@onready var sprite_node: TextureRect = $Sprite2D
@onready var morale_bar: UnitMoraleBar = $MoraleBar
@onready var stress_arrows: Label = $StressLevel
@onready var recovery_arrows: Label = $LeadershipBonus
@onready var cover_label: Label = $CoverLabel
@onready var cover_container: HBoxContainer = $Cover
@onready var broken_label: Label = $BrokenLabel
@onready var unit_selected_sprite: TextureRect = $UnitSelectedSprite
@onready var unit_status_control: Control = $UnitStatus
@onready var broken_texture_rect: TextureRect = $UnitStatus/Broken
@onready var moving_texture_rect: TextureRect = $UnitStatus/Moving
@onready var routing_texture_rect: TextureRect = $UnitStatus/Routing
@onready var shooting_texture_rect: TextureRect = $UnitStatus/Shooting
@onready var pinned_texture_rect: TextureRect = $UnitStatus/Pinned
@onready var idle_texture_rect: TextureRect = $UnitStatus/Idle
@onready var surrendered_texture_rect: TextureRect = $UnitStatus/Surrendered
@onready var members_count_label: Label = $MembersCount
@onready var unit_designation_label: Label = $UnitDesignation
@onready var rank_texture_rect: TextureRect = $Rank
@onready var dead: TextureRect = $Dead
@onready var focus_indicator: Node2D = $FocusIndicator


@onready var soldiers_detail_container: VBoxContainer = $Soldiers/SoldiersContainer
@export var soldier_detail_scene: PackedScene

var _surrendered: bool = false
var _exited: bool = false
var _dead: bool = false
var _morale_state: int = STATES.MoraleState.NORMAL
var _pressure: float = 0.0
var _formation_color: Color = UnitHudStyle.SUPPORT_COLOR
var _formation_key: Vector3i = Vector3i(-1, -1, -1)
var _casualty_feedback: CASUALTY_FEEDBACK
var _state_feedback: STATE_FEEDBACK
var _tactical_feedback: STATE_FEEDBACK
var _elimination_fade: Tween
var _facing_update_remaining: float = 0.0

signal debug_kill_soldier

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	Debug.debug_text_visibility_changed.connect(_set_debug_text_visible)
	_set_debug_text_visible(Debug.show_debug_text)
	_on_stress_balance_changed(0.0, 0.0, 0.0, 0.0)
	update_formation_color()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _dead or _exited or _surrendered:
		return
	_update_focus_indicator()
	_update_tactical_feedback()
	_facing_update_remaining -= delta
	if _facing_update_remaining > 0.0:
		return
	_facing_update_remaining = FACING_UPDATE_INTERVAL
	_update_facing()


func _update_focus_indicator() -> void:
	var unit: Unit = get_parent() as Unit
	if unit == null or not unit.is_active() or unit.surrendered or unit.tactical_state == null:
		focus_indicator.hide()
		return
	var attention: SquadTacticalState = unit.tactical_state
	if attention.focus_direction.is_zero_approx() or attention.focus_strength <= 0.0:
		focus_indicator.hide()
		return
	# Attention uses world space; keep the arrow aligned through parent transforms.
	var local_direction: Vector2 = get_global_transform().affine_inverse().basis_xform(attention.focus_direction).normalized()
	var half_size: Vector2 = sprite_node.size * 0.5
	var edge_distance: float = minf(half_size.x / maxf(absf(local_direction.x), 0.001), half_size.y / maxf(absf(local_direction.y), 0.001))
	focus_indicator.position = sprite_node.position + half_size + local_direction * (edge_distance + 6.0)
	focus_indicator.rotation = local_direction.angle()
	focus_indicator.modulate.a = lerpf(0.5, 1.0, clampf(attention.focus_strength * attention.attention_quality, 0.0, 1.0))
	focus_indicator.show()


func _update_tactical_feedback() -> void:
	var unit: Unit = get_parent() as Unit
	if unit != null and unit.tactical_state != null:
		set_tactical_conditions(unit.tactical_state.flanked, unit.tactical_state.surrounded)


func set_tactical_conditions(flanked: bool, surrounded: bool) -> void:
	if _dead or _exited or _surrendered:
		return
	var state: STATE_FEEDBACK.State = STATE_FEEDBACK.State.NONE
	if surrounded:
		state = STATE_FEEDBACK.State.SURROUNDED
	elif flanked:
		state = STATE_FEEDBACK.State.FLANKED
	if not is_instance_valid(_tactical_feedback) and state != STATE_FEEDBACK.State.NONE:
		_tactical_feedback = STATE_FEEDBACK.new()
		_tactical_feedback.name = "TacticalFeedback"
		_tactical_feedback.ribbon_offset = Vector2(0.0, 20.0)
		add_child(_tactical_feedback)
	if is_instance_valid(_tactical_feedback):
		_tactical_feedback.set_state(state, is_visible_in_tree())
	if is_instance_valid(detail_ui):
		detail_ui.set_tactical_conditions(flanked, surrounded)


func _clear_tactical_feedback() -> void:
	if is_instance_valid(_tactical_feedback):
		_tactical_feedback.set_state(STATE_FEEDBACK.State.NONE)


func _update_facing() -> void:
	if _dead or _exited or _surrendered or shooting_texture_rect.visible:
		return
	var unit: Unit = get_parent() as Unit
	if unit == null or not unit.is_active():
		return
	if unit.movement != null and unit.movement.is_moving:
		var unit_container: Node2D = unit.get_parent() as Node2D
		if unit_container != null:
			_face_direction(unit_container.to_global(unit.movement.target_position) - unit.global_position)
		return
	if idle_texture_rect.visible:
		_face_direction(_general_enemy_direction(unit))


func _general_enemy_direction(unit: Unit) -> Vector2:
	var enemy_position_sum: Vector2 = Vector2.ZERO
	var enemy_count: int = 0
	var visible_enemies: Array = Globals.unit_visible_enemies.get(unit, [])
	for enemy: Unit in visible_enemies:
		if not is_instance_valid(enemy) or not enemy.is_active() or enemy.surrendered or enemy.team == unit.team:
			continue
		enemy_position_sum += enemy.global_position
		enemy_count += 1
	var ground: HexagonTileMapLayer = LOSHelper.ground_layer
	if is_instance_valid(ground):
		var now: float = unit._now()
		for enemy: Unit in unit.enemy_memory:
			if not is_instance_valid(enemy) or visible_enemies.has(enemy):
				continue
			var memory: Dictionary = unit.enemy_memory[enemy]
			var age: float = now - float(memory.get("last_seen_time", -INF))
			if age < 0.0 or age > Unit.ENEMY_MEMORY_LIFETIME:
				continue
			var last_seen_hex: Vector2i = memory.get("last_seen_hex", Vector2i.ZERO)
			enemy_position_sum += ground.to_global(ground.map_to_local(last_seen_hex))
			enemy_count += 1
	if enemy_count > 0:
		return enemy_position_sum / float(enemy_count) - unit.global_position
	# Before contact, use the authored enemy approach rather than hidden live units.
	var scenario: Scenario = Globals.scenario_chosen
	if is_instance_valid(scenario) and is_instance_valid(ground):
		var enemy_team: Globals.Team = Globals.get_enemy_team(unit.team)
		var enemy_start: Vector2i = scenario.start_hex[enemy_team]
		if enemy_start != scenario.start_hex[unit.team]:
			return ground.to_global(ground.map_to_local(enemy_start)) - unit.global_position
	return Vector2.ZERO


func _set_debug_text_visible(enabled: bool) -> void:
	# Stress balance arrows are gameplay indicators, independent of debug text.
	$AmmunitionLeft.visible = enabled and OS.is_debug_build() and not _exited and not dead.visible


func set_ammunition_left(ammo: int) -> void:
	$AmmunitionLeft.text = str(ammo)

func set_loadout(soldiers: Array[Soldier]) -> void:
	if detail_ui:
		soldiers_detail_container.hide()
		detail_ui._set_loadout(soldiers)
	else:
		soldiers_detail_container.hide()


func _set_loadout(soldiers: Array[Soldier]) -> void:
	soldiers_detail_container.show()
	for child: Control in soldiers_detail_container.get_children():
		child.queue_free()
	for i: Soldier in soldiers:
		var soldier: Soldier = i
		var soldier_detail: SoldierDetail = soldier_detail_scene.instantiate()
		soldier_detail.set_soldier_detail(soldier)
		soldiers_detail_container.add_child(soldier_detail)

func _on_stress_balance_changed(incoming_rate: float, recovery_capacity: float, actual_recovery_rate: float, net_rate: float) -> void:
	var counts: Vector2i = stress_balance_arrow_counts(incoming_rate, recovery_capacity)
	stress_arrows.text = "<".repeat(counts.x)
	recovery_arrows.text = ">".repeat(counts.y)
	var explanation: String = "Stress influence · recent average\nIncoming stress: +%.2f/s\nRecovery capacity: %.2f/s\nActual recovery: -%.2f/s\nNet stress change: %+.2f/s\nArrows: 1 ≤0.5/s · 2 ≤1.5/s · 3 >1.5/s" % [incoming_rate, recovery_capacity, actual_recovery_rate, net_rate]
	stress_arrows.tooltip_text = explanation
	recovery_arrows.tooltip_text = explanation
	if detail_ui != null:
		detail_ui._on_stress_balance_changed(incoming_rate, recovery_capacity, actual_recovery_rate, net_rate)


static func stress_balance_arrow_counts(incoming_rate: float, recovery_capacity: float) -> Vector2i:
	return Vector2i(_influence_arrow_count(incoming_rate), _influence_arrow_count(recovery_capacity))


static func _influence_arrow_count(rate: float) -> int:
	if rate <= 0.0:
		return 0
	if rate <= MEDIUM_INFLUENCE_RATE:
		return 1
	if rate <= STRONG_INFLUENCE_RATE:
		return 2
	return 3

func set_leadership_rank(rankGrade: RankGrades.Grade) -> void:
	$LeadershipRank.text = RankGrades.TITLES.DE[rankGrade]
	match rankGrade:
		RankGrades.Grade.SOLDIER:
			rank_texture_rect.texture = private_texture
		RankGrades.Grade.ASSISTANT_TEAM_LEADER:
			rank_texture_rect.texture = private_first_class_texture
		RankGrades.Grade.TEAM_LEADER:
			rank_texture_rect.texture = corporal_texture
		RankGrades.Grade.SQUAD_LEADER:
			rank_texture_rect.texture = sergeant_texture
		RankGrades.Grade.PLATOON_LEADER:
			rank_texture_rect.texture = second_lieutenant_texture
		RankGrades.Grade.COMPANY_LEADER:
			rank_texture_rect.texture = captain_texture



func select() -> void:
	unit_selected_sprite.visible = true
	if detail_ui:
		detail_ui.select()


func deselect() -> void:
	unit_selected_sprite.visible = false
	if detail_ui:
		detail_ui.deselect()


func state_changed(next:int) -> void:
	if _dead or _exited or _surrendered:
		return
	var was_pinned: bool = _morale_state == STATES.MoraleState.PINNED
	_morale_state = next
	match next:
		STATES.MoraleState.NORMAL:
			$UnitStates/StateTexture.hide()
		STATES.MoraleState.CAUTIOUS:
			$UnitStates/StateTexture.show()
			$UnitStates/StateTexture.texture = cautious_texture
		STATES.MoraleState.PINNED:
			$UnitStates/StateTexture.hide()
		STATES.MoraleState.PANIC:
			$UnitStates/StateTexture.show()
			$UnitStates/StateTexture.texture = panic_texture
		STATES.MoraleState.COMBAT_INEFFECTIVE:
			$UnitStates/StateTexture.show()
			$UnitStates/StateTexture.texture = combat_ineffective_texture
	if next == STATES.MoraleState.PINNED:
		_set_state_feedback(STATE_FEEDBACK.State.PINNED)
		$Timer.stop()
		_show_status(pinned_texture_rect)
	else:
		_set_state_feedback(STATE_FEEDBACK.State.NONE)
		if was_pinned:
			$Timer.stop()
			if next == STATES.MoraleState.PANIC:
				_show_status(broken_texture_rect)
			else:
				_show_status(idle_texture_rect)
	if is_instance_valid(detail_ui):
		detail_ui.state_changed(next)


func _set_state_feedback(state: STATE_FEEDBACK.State) -> void:
	if not is_instance_valid(_state_feedback):
		if state == STATE_FEEDBACK.State.NONE:
			return
		_state_feedback = STATE_FEEDBACK.new()
		_state_feedback.name = "StateFeedback"
		add_child(_state_feedback)
	_state_feedback.set_state(state, is_visible_in_tree())


func _show_status(status: TextureRect) -> void:
	for child: Control in unit_status_control.get_children():
		child.hide()
	status.show()


func contains_battlefield_point(screen_point: Vector2) -> bool:
	if _dead or _exited or not is_visible_in_tree():
		return false
	var sprite_point: Vector2 = sprite_node.get_global_transform_with_canvas().affine_inverse() * screen_point
	if sprite_node.is_visible_in_tree() and Rect2(Vector2.ZERO, sprite_node.size).has_point(sprite_point):
		return true
	if is_instance_valid(_state_feedback):
		if _state_feedback.contains_screen_point(screen_point):
			return true
	if is_instance_valid(_tactical_feedback):
		return _tactical_feedback.contains_screen_point(screen_point)
	return false


func _restore_restricted_pose() -> bool:
	if _dead or _exited:
		return true
	if _surrendered:
		_show_status(surrendered_texture_rect)
		return true
	if _morale_state == STATES.MoraleState.PINNED:
		_show_status(pinned_texture_rect)
		return true
	return false


func update_team_sprite(team : int, _squad_type: Globals.SquadType) -> void:
	if not sprite_node:
		return
	match team:
		0:
			sprite_node.texture = sprite_team_0
		1:
			sprite_node.texture = sprite_team_1
	unit_status_control.set_status_image(team, _squad_type)
	if detail_ui:
		detail_ui.update_team_sprite(team, _squad_type)


func set_cover(cover_value: int) -> void:
	for child: Control in cover_container.get_children():
		child.queue_free()
	for cover: int in cover_value:
		var cover_icon: TextureRect = cover_icon_scene.instantiate()
		cover_icon.expand_mode = TextureRect.ExpandMode.EXPAND_FIT_WIDTH_PROPORTIONAL
		cover_container.add_child(cover_icon)
	if detail_ui:
		detail_ui.set_cover(cover_value)


func set_members_alive(members_alive: int) -> void:
	members_count_label.text = str(members_alive)


func set_unit_designation(designation: String) -> void:
	unit_designation_label.text = designation
	update_formation_color()


func update_formation_color() -> void:
	var unit: Unit = get_parent() as Unit
	if unit == null or morale_bar == null:
		return
	var formation: Vector3i = Vector3i(unit.company, unit.platoon, unit.squad_type)
	if formation == _formation_key:
		return
	_formation_key = formation
	_formation_color = UnitHudStyle.formation_color(unit)
	morale_bar.set_morale(_pressure, _formation_color)


func _on_unit_arrived_at_hex(_hex: Vector2i) -> void:
	pass
	if detail_ui:
		pass


func started_moving(broken: bool, surrendered: bool) -> void:
	$Timer.stop()
	if not _restore_restricted_pose():
		if broken:
			_show_status(routing_texture_rect)
		else:
			_show_status(moving_texture_rect)
	_update_facing()
	
	if detail_ui:
		detail_ui.started_moving(broken, surrendered)


func stopped_moving(broken: bool, surrendered: bool) -> void:
	$Timer.stop()
	if not _restore_restricted_pose():
		if broken:
			_show_status(broken_texture_rect)
		else:
			_show_status(idle_texture_rect)
	_update_facing()
	if detail_ui:
		detail_ui.stopped_moving(broken, surrendered)


func _on_morale_breaks() -> void:
	if _dead or _exited or _surrendered:
		return
	$Timer.stop()
	#broken_label.visible = true
	show_broken()
	for child: Control in unit_status_control.get_children():
		child.visible = false
	broken_texture_rect.visible = true
	if detail_ui:
		detail_ui._on_morale_breaks()


func _on_morale_recovered() -> void:
	if _dead or _exited or _surrendered:
		return
	#broken_label.visible = false
	show_success()
	for child: Control in unit_status_control.get_children():
		child.visible = false
	idle_texture_rect.visible = true
	if _surrendered:
		idle_texture_rect.visible = false
		broken_texture_rect.visible = false
		surrendered_texture_rect.visible = true
	if detail_ui:
		detail_ui._on_morale_recovered()


func _on_morale_updated(current: int, _max: int) -> void:
	update_bar(current, _max)
	if detail_ui:
		detail_ui._on_morale_updated(current, _max)


func _on_morale_failure() -> void:
	show_broken()
	if detail_ui:
		detail_ui._on_morale_failure()


func _on_morale_success() -> void:
	show_success()
	if detail_ui:
		detail_ui._on_morale_success()


func update_bar(current: int, _max: int) -> void:
	if morale_bar:
		_pressure = clampf(float(current) / float(maxi(_max, 1)), 0.0, 1.0)
		morale_bar.set_morale(_pressure, _formation_color)
		morale_bar.tooltip_text = "Morale reserve: %d%%\nStress: %d/%d" % [roundi((1.0 - _pressure) * 100.0), current, _max]
	if detail_ui:
		detail_ui.update_bar(current, _max)
		

func _on_cover_updated(cover_value: int) -> void:
	for child: Control in cover_container.get_children():
		child.queue_free()
	for cover: int in cover_value:
		var cover_icon: TextureRect = cover_icon_scene.instantiate()
		cover_icon.expand_mode = TextureRect.ExpandMode.EXPAND_FIT_WIDTH_PROPORTIONAL
		cover_container.add_child(cover_icon)
	if detail_ui:
		detail_ui._on_cover_updated(cover_value)


func show_casualty(count: int = 1) -> void:
	if count <= 0 or _exited or not is_visible_in_tree():
		return
	if not is_instance_valid(_casualty_feedback):
		_casualty_feedback = CASUALTY_FEEDBACK.new()
		_casualty_feedback.name = "CasualtyFeedback"
		add_child(_casualty_feedback)
	_casualty_feedback.show_losses(count)
	if is_instance_valid(detail_ui):
		detail_ui.show_casualty(count)


func show_broken() -> void:
	_spawn_popup("broken")


func show_pinned() -> void:
	state_changed(STATES.MoraleState.PINNED)


func show_success() -> void:
	update_bar(0, 100)
	_spawn_popup("success")
	#_spawn_flash("success")
	#if detail_ui:
		#detail_ui.show_success()


func _spawn_popup(type: String) -> void:
	var popup: Node2D = morale_popup_scene.instantiate()
	add_child(popup)
	#popup.position = position + Vector2(0, -20)
	match type:
		"broken":
			popup.start_broken()
		"pinned":
			popup.start_pinned()
		"casualty":
			popup.start_casualty()
		_:
			popup.start_success()
	#if type == "failure":
		#popup.start_failure()
	#else:
		#popup.start_success()
	if detail_ui:
		detail_ui._spawn_popup(type)


func _spawn_flash(type: String) -> void:
	var flash: Node2D = morale_flash_scene.instantiate()
	add_child(flash)
	flash.position = position
	if type == "failure":
		flash.start_failure()
	else:
		flash.start_success()
	if detail_ui:
		detail_ui._spawn_flash(type)

func shoot_rocket_launcher(from_pos: Vector2, to_pos: Vector2, weapon: WeaponSpec, spawn_offset: Vector2 = Vector2.INF, impact_offset: Vector2 = Vector2.INF) -> void:
	_start_projectile(from_pos, to_pos, weapon, TRACER.Kind.ROCKET, spawn_offset, impact_offset)


func shoot_mortar(from_pos: Vector2, to_pos: Vector2, weapon: WeaponSpec, spawn_offset: Vector2 = Vector2.INF, impact_offset: Vector2 = Vector2.INF) -> void:
	_start_projectile(from_pos, to_pos, weapon, TRACER.Kind.MORTAR, spawn_offset, impact_offset)


func shoot(from_pos: Vector2, to_pos: Vector2, weapon: WeaponSpec, spawn_offset: Vector2 = Vector2.INF, impact_offset: Vector2 = Vector2.INF) -> void:
	_start_projectile(from_pos, to_pos, weapon, TRACER.Kind.BULLET, spawn_offset, impact_offset)


func shoot_riflegrenade(from_pos: Vector2, to_pos: Vector2, weapon: WeaponSpec, spawn_offset: Vector2 = Vector2.INF, impact_offset: Vector2 = Vector2.INF) -> void:
	_start_projectile(from_pos, to_pos, weapon, TRACER.Kind.GRENADE, spawn_offset, impact_offset)


func _start_projectile(from_pos: Vector2, to_pos: Vector2, weapon: WeaponSpec, kind: TRACER.Kind, spawn_offset: Vector2, impact_offset: Vector2) -> void:
	if _exited or _dead or _surrendered:
		return
	_face_direction(to_pos - from_pos)
	var offset: Vector2 = spawn_offset
	if not offset.is_finite():
		offset = TRACER.sample_spawn_offset()
	PROJECTILE_EFFECTS.for_scene(self).fire(from_pos, to_pos, weapon, kind, tracer_scene, offset, impact_offset)
	_show_shooting_status()
	if is_instance_valid(detail_ui):
		detail_ui._show_shooting_status()


func _face_direction(direction: Vector2) -> void:
	# Side-on artwork keeps its previous facing for straight up/down directions.
	if is_zero_approx(direction.x):
		return
	for icon: TextureRect in unit_status_control.get_children():
		icon.flip_h = direction.x < 0.0
	if is_instance_valid(detail_ui):
		detail_ui._face_direction(direction)


func _show_shooting_status() -> void:
	if _restore_restricted_pose():
		return
	for child: Control in unit_status_control.get_children():
		child.visible = false
	shooting_texture_rect.visible = true
	$Timer.start()


func riflegrenade_explosion(_target_pos: Vector2) -> void:
	pass


func surrender() -> void:
	if _dead or _exited or _surrendered:
		return
	_surrendered = true
	_clear_tactical_feedback()
	focus_indicator.hide()
	$Timer.stop()
	$UnitStates.hide()
	_show_status(surrendered_texture_rect)
	_set_state_feedback(STATE_FEEDBACK.State.SURRENDERED)
	if is_instance_valid(detail_ui):
		detail_ui.surrender()


func mark_exited() -> void:
	_exited = true
	_clear_tactical_feedback()
	focus_indicator.hide()
	if _elimination_fade != null and _elimination_fade.is_valid():
		_elimination_fade.kill()
	if is_instance_valid(_casualty_feedback):
		_casualty_feedback.clear()
	_set_state_feedback(STATE_FEEDBACK.State.NONE)
	_set_debug_text_visible(false)
	for child: Control in unit_status_control.get_children():
		child.hide()
	morale_bar.hide()
	$MoraleBarDefault.hide()
	$StressLevel.hide()
	$LeadershipBonus.hide()
	$ColorRect.hide()
	unit_selected_sprite.hide()
	cover_container.hide()
	rank_texture_rect.hide()
	sprite_node.modulate = Color(0.6, 0.6, 0.6, 0.7)
	broken_label.text = "Exited"
	broken_label.show()
	if detail_ui != null:
		detail_ui.mark_exited()


func die() -> void:
	if _dead or _exited:
		return
	_dead = true
	_clear_tactical_feedback()
	focus_indicator.hide()
	$Timer.stop()
	dead.show()
	unit_status_control.hide()
	$UnitStates.hide()
	cover_container.hide()
	rank_texture_rect.hide()
	broken_label.hide()
	_set_state_feedback(STATE_FEEDBACK.State.ELIMINATED)
	_set_debug_text_visible(false)
	$StressLevel.hide()
	$MoraleBar.hide()
	$MoraleBarDefault.hide()
	$ColorRect.hide()
	$LeadershipBonus.hide()
	$Sprite2D.hide()
	$UnitSelectedSprite.hide()
	# Keep the loss conspicuous briefly, then leave a quiet battlefield remnant.
	_elimination_fade = create_tween()
	_elimination_fade.tween_interval(ELIMINATION_HOLD_SECONDS)
	_elimination_fade.tween_property(self, "modulate", ELIMINATION_REST_COLOR, ELIMINATION_FADE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if is_instance_valid(detail_ui):
		detail_ui.die()


func _on_timer_timeout() -> void:
	if _restore_restricted_pose():
		return
	if surrendered_texture_rect.visible == true or broken_texture_rect.visible or routing_texture_rect.visible:
		return
	for child: Control in unit_status_control.get_children():
		child.visible = false
	idle_texture_rect.visible = true
	if _surrendered:
		idle_texture_rect.visible = false
		broken_texture_rect.visible = false
		surrendered_texture_rect.visible = true
	_update_facing()
	if detail_ui:
		detail_ui._on_timer_timeout()


func _on_kill_soldier_pressed() -> void:
	debug_kill_soldier.emit()
