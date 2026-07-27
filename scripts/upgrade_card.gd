extends Node2D

@export var distance : int = 20

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	pass



func _on_texture_rect_mouse_entered() -> void:
	self.position.y -= 20
	pass


func _on_texture_rect_mouse_exited() -> void:
	self.position.y += 20
	pass
