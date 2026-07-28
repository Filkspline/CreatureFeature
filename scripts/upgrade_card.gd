extends Node2D

@onready var selection_icon = $Control/selection_icon
@onready var parent_node = self.get_parent()


func _ready() -> void:
	selection_icon.hide()

func _on_texture_rect_mouse_entered() -> void:
	selection_icon.show()
	

func _on_texture_rect_mouse_exited() -> void:
	selection_icon.hide()
 

func _on_texture_rect_gui_input(event: InputEvent) -> void:
	# TODO This will need to be edited to handle controller input eventually
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			parent_node._handle_clicked_card(self)
