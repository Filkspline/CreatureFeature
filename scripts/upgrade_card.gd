extends Node2D

@onready var selection_icon = $Control/selection_icon
@onready var anim_player = $AnimationPlayer
@onready var parent_node = self.get_parent()
@onready var card_shader = preload("res://scripts/card_tear.gdshader")
#@onready var fight_scene = preload("res://scenes/test_level.tscn")

var currently_highlighted : bool
var is_flipped : bool
#var assoc_tres_file

# NOTE cleaned up some of the remaining unused functions here

func _ready() -> void:
	selection_icon.hide()
	self.material = null


func _handle_highlight() -> void:
	if  currently_highlighted:
		for card in self.get_parent().get_children():
			if card != self:
				card.currently_highlighted = false
				card.selection_icon.hide()
		selection_icon.show()
		selection_icon.play("selector_blink")
		if !is_flipped:
			anim_player.play("card_flip")
			is_flipped = true
		else:
			pass
	else:
		selection_icon.hide()

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
	# TODO this should be edited to handle more than just grabbing the name, to be done later
	if p1_selecting == true:
		UpgradePoolManager.p1_current_upgrades.append(tres_file_path)
	else:
		UpgradePoolManager.p2_current_upgrades.append(tres_file_path)
	
	UpgradePoolManager._remove_from_pool(tres_file_path, p1_selecting)
	
	print(tres_file)
	print(tres_file.name)
	
	# NOTE this is just going to force a transition to the stage for now
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://scenes/test_level.tscn")
