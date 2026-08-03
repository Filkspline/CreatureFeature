extends Node2D

@onready var selection_icon = $Control/selection_icon
@onready var anim_player = $AnimationPlayer
@onready var parent_node = self.get_parent()
@onready var card_shader = preload("res://scripts/card_tear.gdshader")

var currently_highlighted : bool
var is_flipped : bool

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
