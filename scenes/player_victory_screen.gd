extends Node2D

@onready var p1_win = $p1_win
@onready var p1_win_text = $p1_win/p1_win_text

@onready var p2_win = $p2_win
@onready var p2_win_text = $p2_win/p2_win_text

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	p1_win.hide()
	p2_win.hide()
	_bob_win_text()
	
	_end_screen_update()

func _bob_win_text() -> void:
	# Cast rather than left as Node: get_node_or_null() returns a Node, whose
	# .position has no type for the analyser to infer from.
	var text_array := get_tree().get_nodes_in_group("win_text") as Array[Node]
	if text_array == null:
		return
	for text in text_array:
		var base_y : float = text.position.y
		var tween := create_tween().set_loops()
		tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(text, "position:y", base_y - 3.0, 1.6)
		tween.tween_property(text, "position:y", base_y, 1.6)


func _end_screen_update() -> void:
	match GameManager.win_id:
		1:
			p1_win.show()
		2:
			p2_win.show()


func _on_menu_button_pressed() -> void:
	pass # Replace with function body.
