extends Node2D

@onready var selection_icon = $Control/selection_icon
@onready var parent_node = self.get_parent()

var currently_highlighted : bool

func _ready() -> void:
	selection_icon.hide()


func _on_texture_rect_mouse_entered() -> void:
	currently_highlighted = true
	_handle_highlight()


func _handle_highlight() -> void:
	if  currently_highlighted:
		for card in self.get_parent().get_children():
			if card != self:
				card.currently_highlighted = false
				card.selection_icon.hide()
		selection_icon.show()
	else:
		selection_icon.hide()

# TODO change to handle being the currently selected card
func _on_texture_rect_gui_input(event: InputEvent) -> void:
	# TODO This will need to be edited to handle controller input eventually
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			parent_node._handle_clicked_card()
