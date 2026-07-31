extends Node2D

@onready var selection_icon = $Control/selection_icon
@onready var anim_player = $AnimationPlayer
@onready var parent_node = self.get_parent()

var currently_highlighted : bool
var is_flipped : bool

func _ready() -> void:
	selection_icon.hide()
	self.material = null


#func _on_texture_rect_mouse_entered() -> void:
#	currently_highlighted = true
#	_handle_highlight()


func _handle_highlight() -> void:
	if  currently_highlighted:
		for card in self.get_parent().get_children():
			if card != self:
				card.currently_highlighted = false
				card.selection_icon.hide()
		selection_icon.show()
		if !is_flipped:
			anim_player.play("card_flip")
			is_flipped = true
		else:
			pass
	else:
		selection_icon.hide()

# TODO change to handle being the currently selected card
#func _on_texture_rect_gui_input(event: InputEvent) -> void:
	# TODO This will need to be edited to handle controller input eventually
#	if event is InputEventMouseButton:
#		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
#			parent_node._handle_clicked_card()

# TODO This should handle the shader stuff if we decide to do that
#func _handle_shader() -> void:
#	self.material.get_shader_parameter("rect_size", Vector2(0, 500))
	
