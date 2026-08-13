extends Control
@onready var tab_container = $TabContainer

func _process(_delta):
	if Input.is_action_just_pressed("MenuTabLeft"):
		tab_container.current_tab -= 1
		
		if tab_container.current_tab < 0:
			tab_container.current_tab = tab_container.get_tab_count() - 1


	if Input.is_action_just_pressed("MenuTabRight"):
		tab_container.current_tab += 1
		
		if tab_container.current_tab >= tab_container.get_tab_count():
			tab_container.current_tab = 0
