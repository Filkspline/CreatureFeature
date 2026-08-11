extends Node2D

@onready var selection_icon = $Control/selection_icon
@onready var anim_player = $AnimationPlayer
@onready var card_control = $Control
@onready var parent_node = self.get_parent()
@onready var card_shader = preload("res://scripts/card_tear.gdshader")
@onready var fight_scene = preload("res://scenes/test_level.tscn")

var currently_highlighted : bool
var is_flipped : bool
#var assoc_tres_file

# ── Juice settings ──
const IDLE_BOB_AMOUNT := 6.0
const IDLE_BOB_DURATION := 1.4
const HOVER_MULTIPLIER := 1.15
const HOVER_OVERSHOOT := 1.08
const HOVER_DURATION := 0.15

var _base_scale : Vector2
var _hover_tween : Tween

# NOTE cleaned up some of the remaining unused functions here

func _ready() -> void:
	selection_icon.hide()
	self.material = null
	_base_scale = card_control.scale
	_start_idle_bob()


func _start_idle_bob() -> void:
	# Gentle up/down float so cards don't sit dead still. Runs forever,
	# independent of the hover/selection scale tweens below.
	var idle_tween := create_tween().set_loops()
	idle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	idle_tween.tween_property(card_control, "position:y", card_control.position.y - IDLE_BOB_AMOUNT, IDLE_BOB_DURATION)
	idle_tween.tween_property(card_control, "position:y", card_control.position.y, IDLE_BOB_DURATION)


func _handle_highlight() -> void:
	if  currently_highlighted:
		for card in self.get_parent().get_children():
			if card != self:
				card.currently_highlighted = false
				card.selection_icon.hide()
				card._play_unhover_tween()
		_play_selection_icon_pop()
		_play_hover_tween()
		if !is_flipped:
			anim_player.play("card_flip")
			is_flipped = true
		else:
			pass
	else:
		selection_icon.hide()
		_play_unhover_tween()


func _play_hover_tween() -> void:
	# Overshoots slightly past the hover size then settles, for a springy pop
	# instead of a flat linear scale-up.
	if _hover_tween:
		_hover_tween.kill()
	var overshoot := _base_scale * HOVER_MULTIPLIER * HOVER_OVERSHOOT
	var target := _base_scale * HOVER_MULTIPLIER
	_hover_tween = create_tween()
	_hover_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(card_control, "scale", overshoot, HOVER_DURATION)
	_hover_tween.tween_property(card_control, "scale", target, HOVER_DURATION * 0.6)


func _play_unhover_tween() -> void:
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_hover_tween.tween_property(card_control, "scale", _base_scale, HOVER_DURATION)


func _play_selection_icon_pop() -> void:
	# Elastic pop-in instead of a flat show(), then the existing blink anim.
	selection_icon.scale = Vector2.ZERO
	selection_icon.show()
	selection_icon.play("selector_blink")
	var icon_tween := create_tween()
	icon_tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	icon_tween.tween_property(selection_icon, "scale", Vector2(4, 4), 0.5)


# TODO This should handle the shader stuff if we decide to do that
#func _handle_shader() -> void:
	#var shader_material = ShaderMaterial.new()
	#print("\n" + str(shader_material))
	#shader_material.shader = card_shader
	#print(card_shader)
	#print(shader_material.shader)
	#self.material = shader_material
	#print(str(self.material) + "\n")

func _handle_tres_file(tres_file_path : String, p1_selecting : bool) -> void:
	var tres_file = load(tres_file_path)
	## @experimental
	## This is just some bullshit testing, if this works please god do not leave it in
	var player_node
	# TODO this should be edited to handle more than just grabbing the name, to be done later
	if p1_selecting == true:
		UpgradePoolManager.p1_current_upgrades.append(tres_file_path)
		player_node = GameManager.p1_node
	else:
		UpgradePoolManager.p2_current_upgrades.append(tres_file_path)
		player_node = GameManager.p2_node
	
	UpgradePoolManager._remove_from_pool(tres_file_path, p1_selecting)
	
	print(tres_file)
	print(tres_file.name)
	
	
	GameManager.main_scene.add_fight_to_main()
	# TODO Uncomment when the scene change has been done
	tres_file.apply_to(player_node)
	
	# NOTE this is just going to force a transition to the stage for now
	# TODO need to change this to run the transition to the next scene using the main logic
	await get_tree().create_timer(0.75).timeout
	GameManager.main_scene.remove_upgrade_ui()
	#get_tree().change_scene_to_file("res://scenes/test_level.tscn")
