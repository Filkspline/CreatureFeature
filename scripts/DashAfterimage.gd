extends Sprite2D

# ──────────────────────────────────────────────────────────────────
#  DashAfterimage
#
#  One ghost frame of a dash trail. PlayerVisuals instantiates one of
#  these per spawn, hands it the source sprite's current frame through
#  appear_from(), and this node fades itself out and frees itself, the
#  same lifecycle hit particles use.
#
#  How a single ghost LOOKS lives here (tint, fade curve). How OFTEN one
#  spawns and how many may exist at once live on PlayerVisuals, because
#  those are properties of the emitter, not of any one ghost.
#
#  Nothing here holds a reference to the player, so N ghosts from both
#  players can be fading at the same time without interfering.

## Color and starting opacity of every ghost. The alpha here is the
## ghost's opacity the moment it spawns; the fade below takes it to 0.
@export var ghost_tint : Color = Color(1.0, 1.0, 1.0, 0.451)
## Seconds for a ghost to fade from ghost_tint.a down to invisible, after
## which it frees itself. Keep this longer than the dash itself so the last
## few ghosts are still trailing as the move ends.
@export var fade_duration : float = 0.3
## Easing of the fade. EASE_IN (the default) hangs around and then drops
## off, which reads as a trail; EASE_OUT snaps away early instead.
@export var fade_transition : Tween.TransitionType = Tween.TRANS_SINE
@export var fade_ease : Tween.EaseType = Tween.EASE_IN

var _fade_tween : Tween


## Copies one frame of `source` onto this ghost and starts the fade. The
## caller should have parented this node already, so that the global
## transform below resolves against the same canvas the player is in.
func appear_from(source: Sprite2D) -> void:
	texture = source.texture
	hframes = source.hframes
	vframes = source.vframes
	frame = source.frame
	region_enabled = source.region_enabled
	region_rect = source.region_rect
	offset = source.offset
	centered = source.centered
	flip_h = source.flip_h
	flip_v = source.flip_v
	# global_scale carries the player's facing, since PlayerVisuals flips
	# its own scale.x for that rather than flipping each sprite. Copying the
	# global transform is what makes a left-facing dash trail face the same
	# way without this node knowing anything about the player.
	global_position = source.global_position
	global_rotation = source.global_rotation
	global_scale = source.global_scale
	# Multiplied rather than replaced, so a sprite that's already tinted
	# (a hit flash, say) keeps its colour and just picks up the ghost tint.
	modulate = ghost_tint * source.modulate
	_fade_out()


func _fade_out() -> void:
	if fade_duration <= 0.0 or is_zero_approx(modulate.a):
		queue_free()
		return

	_fade_tween = create_tween()
	_fade_tween.set_trans(fade_transition).set_ease(fade_ease)
	_fade_tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	_fade_tween.tween_callback(queue_free)
