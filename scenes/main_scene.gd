extends Node2D

const FIGHT_SCENE = preload("res://scenes/test_level.tscn")
const UPGRADE_SCENE = preload("res://scenes/upgrade_card_ui.tscn")
var fight = FIGHT_SCENE.instantiate()
var upgrade = UPGRADE_SCENE.instantiate()
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GameManager.main_scene = self
	# NOTE This is currently a temp system that can eventually hold other scenes to be added
	self.add_child(fight)

## Transitions to the card ui using the main structure scene
func transition_to_card_ui() -> void:
	self.remove_child(fight)
	self.add_child(upgrade)
	self.move_child(upgrade, 0)

func add_fight_to_main() -> void:
	self.add_child(fight)
	self.move_child(fight, 1)
	self.get_child(1).process_mode = Node.PROCESS_MODE_DISABLED
	self.get_child(1).hide()

func remove_upgrade_ui() -> void:
	self.move_child(fight, 0)
	self.get_child(0).show()
	self.remove_child(upgrade)
	self.get_child(0).process_mode = Node.PROCESS_MODE_ALWAYS
