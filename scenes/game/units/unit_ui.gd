@tool
extends Control

var detail_ui = null

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


# === Nodes ===
@onready var sprite_node: TextureRect = $Sprite2D
@onready var morale_bar: ColorRect = $MoraleBar
@onready var cover_label = $CoverLabel
@onready var cover_container = $Cover
@onready var broken_label = $BrokenLabel
@onready var unit_selected_sprite = $UnitSelectedSprite
@onready var unit_status_control = $UnitStatus
@onready var broken_texture_rect = $UnitStatus/Broken
@onready var moving_texture_rect = $UnitStatus/Moving
@onready var routing_texture_rect = $UnitStatus/Routing
@onready var shooting_texture_rect = $UnitStatus/Shooting
@onready var pinned_texture_rect = $UnitStatus/Pinned
@onready var idle_texture_rect = $UnitStatus/Idle
@onready var surrendered_texture_rect = $UnitStatus/Surrendered
@onready var members_count_label = $MembersCount
@onready var unit_designation_label = $UnitDesignation


func _on_leadership_changed(leadership_bonus: float) -> void:
	var txt: String = "%0.2f" % leadership_bonus
	$LeadershipBonus.text = txt


func set_leadership_rank(rankGrade: RankGrades.Grade) -> void:
	$LeadershipRank.text = RankGrades.TITLES.DE[rankGrade]


func set_support_weapons(support_weapons: int):
	var support_weapon_slots: Array = [$"SupportWeapons/VBoxContainer/SupportWeapon#1", $"SupportWeapons/VBoxContainer/SupportWeapon#2"]
	for i in support_weapons:
		support_weapon_slots[i].show()


func select():
	unit_selected_sprite.visible = true
	if detail_ui:
		detail_ui.select()


func deselect():
	unit_selected_sprite.visible = false
	if detail_ui:
		detail_ui.deselect()


func state_changed(next:int):
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


func update_team_sprite(team : int, leader: bool = false):
	if not sprite_node:
		return
	match team:
		0:
			sprite_node.texture = sprite_team_0
		1:
			sprite_node.texture = sprite_team_1
	unit_status_control.set_status_image(team, leader)
	if detail_ui:
		detail_ui.update_team_sprite(team)


func set_cover(cover_value: int) -> void:
	for child in cover_container.get_children():
		child.queue_free()
	for cover in cover_value:
		var cover_icon: TextureRect = cover_icon_scene.instantiate()
		cover_icon.expand_mode = TextureRect.ExpandMode.EXPAND_FIT_WIDTH_PROPORTIONAL
		cover_container.add_child(cover_icon)
	if detail_ui:
		detail_ui.set_cover(cover_value)


func set_memebers_alive(members_alive: int):
	members_count_label.text = str(members_alive)


func set_unit_designation(designation: String):
	unit_designation_label.text = designation


func _on_unit_arrived_at_hex(hex):
	pass
	if detail_ui:
		pass


func started_moving(broken: bool, surrendered: bool):
	for child in unit_status_control.get_children():
		child.visible = false
	if broken:
		routing_texture_rect.visible = true
	else:
		moving_texture_rect.visible = true
	$Timer.stop()
	if detail_ui:
		detail_ui.started_moving(broken, surrendered)


func stopped_moving(broken: bool, surrendered: bool):
	for child in unit_status_control.get_children():
		child.visible = false
	if broken == true:
		broken_texture_rect.visible = true
	else:
		idle_texture_rect.visible = true
	if surrendered:
		idle_texture_rect.visible = false
		broken_texture_rect.visible = false
		surrendered_texture_rect.visible = true
	
	$Timer.stop()
	if detail_ui:
		detail_ui.stopped_moving(broken, surrendered)


func _on_morale_breaks():
	#broken_label.visible = true
	show_failure()
	for child in unit_status_control.get_children():
		child.visible = false
	broken_texture_rect.visible = true
	$Timer.stop()
	if detail_ui:
		detail_ui._on_morale_breaks()


func _on_morale_recovered():
	#broken_label.visible = false
	show_success()
	for child in unit_status_control.get_children():
		child.visible = false
	idle_texture_rect.visible = true
	if detail_ui:
		detail_ui._on_morale_recovered()


func _on_morale_updated(current, max):
	update_bar(current, max)
	if detail_ui:
		detail_ui._on_morale_updated(current, max)


func _on_morale_failure():
	show_failure()
	if detail_ui:
		detail_ui._on_morale_failure()


func _on_morale_success():
	show_success()
	if detail_ui:
		detail_ui._on_morale_success()


func update_bar(current: int, max: int):
	if morale_bar:
		var ratio = clamp(float(current) / float(max), 0.0, 1.0)
		morale_bar.scale.x = ratio

		if ratio < 0.5:
			morale_bar.color = Color(0, 1, 0)
		elif ratio < 0.8:
			morale_bar.color = Color(1, 1, 0)
		else:
			morale_bar.color = Color(1, 0, 0)
	if detail_ui:
		detail_ui.update_bar(current, max)
		

func _on_cover_updated(cover_value: int) -> void:
	for child in cover_container.get_children():
		child.queue_free()
	for cover in cover_value:
		var cover_icon: TextureRect = cover_icon_scene.instantiate()
		cover_icon.expand_mode = TextureRect.ExpandMode.EXPAND_FIT_WIDTH_PROPORTIONAL
		cover_container.add_child(cover_icon)
	if detail_ui:
		detail_ui._on_cover_updated(cover_value)


func show_failure():
	_spawn_popup("failure")
	_spawn_flash("failure")
	if detail_ui:
		detail_ui.show_failure()


func show_success():
	update_bar(0, 100)
	_spawn_popup("success")
	_spawn_flash("success")
	if detail_ui:
		detail_ui.show_success()


func _spawn_popup(type: String):
	var popup = morale_popup_scene.instantiate()
	add_child(popup)
	popup.position = position + Vector2(0, -20)
	if type == "failure":
		popup.start_failure()
	else:
		popup.start_success()
	if detail_ui:
		detail_ui._spawn_popup(type)


func _spawn_flash(type: String):
	var flash = morale_flash_scene.instantiate()
	add_child(flash)
	flash.position = position
	if type == "failure":
		flash.start_failure()
	else:
		flash.start_success()
	if detail_ui:
		detail_ui._spawn_flash(type)


func shoot(from_pos: Vector2, to_pos):
	var tracer = tracer_scene.instantiate() as Node2D
	tracer.tracer_texture = tracer_texture
	get_tree().current_scene.add_child(tracer)
	for child in unit_status_control.get_children():
		child.visible = false
	shooting_texture_rect.visible = true
	await tracer.shoot(from_pos, to_pos)
	$Timer.start()
	if detail_ui:
		for child in detail_ui.unit_status_control.get_children():
			child.visible = false
		detail_ui.shooting_texture_rect.visible = true


func surrender():
	for child in unit_status_control.get_children():
		child.visible = false
	surrendered_texture_rect.visible = true
	if detail_ui:
		for child in detail_ui.unit_status_control.get_children():
			child.visible = false
		detail_ui.surrendered_texture_rect.visible = true


func die():
	var tween = create_tween()
	tween.tween_property(sprite_node.material, "shader_parameter/dissolve_amount", 1.0, 0.6)
	await tween.finished
	#if detail_ui:
		#detail_ui.queue_free()


func _on_timer_timeout() -> void:
	if surrendered_texture_rect.visible == true or broken_texture_rect.visible:
		return
	for child in unit_status_control.get_children():
		child.visible = false
	idle_texture_rect.visible = true
	if detail_ui:
		detail_ui._on_timer_timeout()
