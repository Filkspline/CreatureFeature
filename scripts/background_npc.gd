extends Node2D

@onready var npc_sprite = $npc_sprite

var _rng := RandomNumberGenerator.new()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	EventBus.npc_cheer.connect(_on_event_cheer)
	npc_sprite.play("true_idle")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	await npc_sprite.animation_finished
	var blink_rng = _rng.randi_range(1, 50)
	#print(blink_rng)
	if blink_rng == 1:
		#print_rich("[color=yellow][NPC ANIM] Blink idle played")
		npc_sprite.play("blink_idle")
	else:
		await npc_sprite.animation_finished
		npc_sprite.play("true_idle")
	


func _on_event_cheer() -> void:
	var random_delay = _rng.randf_range(0.0, 0.25)
	await get_tree().create_timer(random_delay).timeout
	npc_sprite.play("cheer")
	
