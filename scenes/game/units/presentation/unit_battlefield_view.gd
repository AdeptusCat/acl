@tool
extends Control
class_name UnitUi

var detail_ui: UnitUi = null

@export var sprite_team_0: Texture2D
@export var sprite_team_1: Texture2D
@export var morale_popup_scene: PackedScene
@export var morale_flash_scene: PackedScene
@export var tracer_scene: PackedScene
@export var tracer_texture: Texture
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
@onready var morale_bar: ColorRect = $MoraleBar
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


@onready var soldiers_detail_container: VBoxContainer = $Soldiers/SoldiersContainer
@export var soldier_detail_scene: PackedScene

var _surrendered: bool = false
var _exited: bool = false

signal debug_kill_soldier

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	Debug.debug_text_visibility_changed.connect(_set_debug_text_visible)
	_set_debug_text_visible(Debug.show_debug_text)
	_on_stress_balance_changed(0.0, 0.0, 0.0)


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

func _on_stress_balance_changed(incoming_rate: float, recovery_rate: float, net_rate: float) -> void:
	var counts: Vector2i = stress_balance_arrow_counts(incoming_rate, recovery_rate)
	stress_arrows.text = "<".repeat(counts.x)
	recovery_arrows.text = ">".repeat(counts.y)
	var explanation: String = "Recent stress balance\nIncoming stress: +%.2f/s\nRecovery: -%.2f/s\nNet stress: %+.2f/s\nMore arrows show the stronger influence." % [incoming_rate, recovery_rate, net_rate]
	stress_arrows.tooltip_text = explanation
	recovery_arrows.tooltip_text = explanation
	if detail_ui != null:
		detail_ui._on_stress_balance_changed(incoming_rate, recovery_rate, net_rate)


static func stress_balance_arrow_counts(incoming_rate: float, recovery_rate: float) -> Vector2i:
	var incoming: float = maxf(0.0, incoming_rate)
	var recovery: float = maxf(0.0, recovery_rate)
	if incoming == 0.0 and recovery == 0.0:
		return Vector2i.ZERO
	if is_equal_approx(incoming, recovery):
		return Vector2i(2, 2)
	if incoming > recovery:
		var green_count: int = 0
		if recovery > 0.0:
			green_count = clampi(roundi(3.0 * recovery / incoming), 1, 2)
		return Vector2i(3, green_count)
	var red_count: int = 0
	if incoming > 0.0:
		red_count = clampi(roundi(3.0 * incoming / recovery), 1, 2)
	return Vector2i(red_count, 3)

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
	match next:
		STATES.MoraleState.NORMAL:
			$UnitStates/StateTexture.hide()
		STATES.MoraleState.CAUTIOUS:
			$UnitStates/StateTexture.show()
			$UnitStates/StateTexture.texture = cautious_texture
		STATES.MoraleState.PINNED:
			$UnitStates/StateTexture.show()
			$UnitStates/StateTexture.texture = pinned_texture
		STATES.MoraleState.PANIC:
			$UnitStates/StateTexture.show()
			$UnitStates/StateTexture.texture = panic_texture
		STATES.MoraleState.COMBAT_INEFFECTIVE:
			$UnitStates/StateTexture.show()
			$UnitStates/StateTexture.texture = combat_ineffective_texture


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


func _on_unit_arrived_at_hex(_hex: Vector2i) -> void:
	pass
	if detail_ui:
		pass


func started_moving(broken: bool, surrendered: bool) -> void:
	$Timer.stop()
	for child: Control in unit_status_control.get_children():
		child.visible = false
	if broken:
		routing_texture_rect.visible = true
	else:
		moving_texture_rect.visible = true
	
	if detail_ui:
		detail_ui.started_moving(broken, surrendered)


func stopped_moving(broken: bool, surrendered: bool) -> void:
	$Timer.stop()
	for child: Control in unit_status_control.get_children():
		child.visible = false
	if broken == true:
		broken_texture_rect.visible = true
	else:
		idle_texture_rect.visible = true
	if _surrendered:
		idle_texture_rect.visible = false
		broken_texture_rect.visible = false
		surrendered_texture_rect.visible = true
	if detail_ui:
		detail_ui.stopped_moving(broken, surrendered)


func _on_morale_breaks() -> void:
	$Timer.stop()
	#broken_label.visible = true
	show_broken()
	for child: Control in unit_status_control.get_children():
		child.visible = false
	broken_texture_rect.visible = true
	if detail_ui:
		detail_ui._on_morale_breaks()


func _on_morale_recovered() -> void:
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
		var ratio: float = clamp(float(current) / float(_max), 0.0, 1.0)
		morale_bar.scale.x = ratio

		#morale_bar.color = Color(1, 0, 0)
		#if ratio < 0.5:
			#morale_bar.color = Color(0, 1, 0)
		#elif ratio < 0.8:
			#morale_bar.color = Color(1, 1, 0)
		#else:
			#morale_bar.color = Color(1, 0, 0)
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


func show_casualty() -> void:
	_spawn_popup("casualty")


func show_broken() -> void:
	_spawn_popup("broken")


func show_pinned() -> void:
	_spawn_popup("pinned")
	#_spawn_flash("failure")
	#if detail_ui:
		#detail_ui.show_failure()


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

func shoot_rocket_launcher(from_pos: Vector2, to_pos: Vector2, weapon: WeaponSpec) -> void:
	if _exited:
		return
	var tracer: Node2D = tracer_scene.instantiate() as Node2D
	tracer.speed = weapon.projectile_speed
	tracer.tracer_texture = tracer_texture
	get_tree().current_scene.add_child(tracer)
	for child: Control in unit_status_control.get_children():
		child.visible = false
	shooting_texture_rect.visible = true
	await tracer.shoot_rocket_launcher(from_pos, to_pos, weapon)
	if _exited:
		return
	$Timer.start()
	if detail_ui:
		for child: Control in detail_ui.unit_status_control.get_children():
			child.visible = false
		detail_ui.shooting_texture_rect.visible = true


func shoot_mortar(from_pos: Vector2, to_pos: Vector2, weapon: WeaponSpec) -> void:
	if _exited:
		return
	var tracer: Node2D = tracer_scene.instantiate() as Node2D
	tracer.speed = weapon.projectile_speed
	tracer.tracer_texture = tracer_texture
	get_tree().current_scene.add_child(tracer)
	for child: Control in unit_status_control.get_children():
		child.visible = false
	shooting_texture_rect.visible = true
	await tracer.shoot_rocket_launcher(from_pos, to_pos, weapon)
	if _exited:
		return
	$Timer.start()
	if detail_ui:
		for child: Control in detail_ui.unit_status_control.get_children():
			child.visible = false
		detail_ui.shooting_texture_rect.visible = true



func shoot(from_pos: Vector2, to_pos: Vector2, weapon: WeaponSpec) -> void:
	if _exited:
		return
	var tracer: Node2D = tracer_scene.instantiate() as Node2D
	tracer.speed = weapon.projectile_speed
	tracer.tracer_texture = tracer_texture
	get_tree().current_scene.add_child(tracer)
	for child: Control in unit_status_control.get_children():
		child.visible = false
	shooting_texture_rect.visible = true
	await tracer.shoot(from_pos, to_pos, weapon)
	if _exited:
		return
	$Timer.start()
	if detail_ui:
		for child: Control in detail_ui.unit_status_control.get_children():
			child.visible = false
		detail_ui.shooting_texture_rect.visible = true


func shoot_riflegrenade(from_pos: Vector2, to_pos: Vector2, weapon: WeaponSpec) -> void:
	if _exited:
		return
	var tracer: Node2D = tracer_scene.instantiate() as Node2D
	tracer.speed = weapon.riflegrenade_projectile_speed
	tracer.tracer_texture = tracer_texture
	get_tree().current_scene.add_child(tracer)
	for child: Control in unit_status_control.get_children():
		child.visible = false
	shooting_texture_rect.visible = true
	await tracer.shoot(from_pos, to_pos, weapon, true)
	if _exited:
		return
	$Timer.start()
	if detail_ui:
		for child: Control in detail_ui.unit_status_control.get_children():
			child.visible = false
		detail_ui.shooting_texture_rect.visible = true


func riflegrenade_explosion(_target_pos: Vector2) -> void:
	pass


func surrender() -> void:
	for child: Control in unit_status_control.get_children():
		child.visible = false
	surrendered_texture_rect.visible = true
	_surrendered = true
	if detail_ui:
		for child: Control in detail_ui.unit_status_control.get_children():
			child.visible = false
		detail_ui.surrendered_texture_rect.visible = true


func mark_exited() -> void:
	_exited = true
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
	dead.show()
	_set_debug_text_visible(false)
	$StressLevel.hide()
	$MoraleBar.hide()
	$MoraleBarDefault.hide()
	$ColorRect.hide()
	$LeadershipBonus.hide()
	$Sprite2D.hide()
	$UnitSelectedSprite.hide()
	pass
	#var tween = create_tween()
	#tween.tween_property(sprite_node.material, "shader_parameter/dissolve_amount", 1.0, 0.6)
	#await tween.finished
	#if detail_ui:
		#detail_ui.queue_free()


func _on_timer_timeout() -> void:
	if surrendered_texture_rect.visible == true or broken_texture_rect.visible or routing_texture_rect.visible:
		return
	for child: Control in unit_status_control.get_children():
		child.visible = false
	idle_texture_rect.visible = true
	if _surrendered:
		idle_texture_rect.visible = false
		broken_texture_rect.visible = false
		surrendered_texture_rect.visible = true
	if detail_ui:
		detail_ui._on_timer_timeout()


func _on_kill_soldier_pressed() -> void:
	debug_kill_soldier.emit()
