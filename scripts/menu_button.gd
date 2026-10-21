extends Button

# ──────────────────────────────────────────────────────────────────
#  MenuButton
#
#  The main menu's button as a reusable node: an invisible Button whose chrome
#  is a child sprite, so the art is sized and positioned in the Inspector and no
#  stylebox ever draws. This is the same construction main_menu.tscn uses, only
#  packaged so the other screens can drop it in instead of restyling a Button
#  three separate times.
#
#  The selector sits dead centre because it is ANCHORED to the middle rather than
#  placed with offsets: the wrapper Control is pinned to the centre of the
#  button, so the sprite's own origin is the centre whatever size the button is.
#
#  pop_in() is the shared "it just appeared" animation, so every screen brings
#  its confirm button on on the same springy beat.
# ──────────────────────────────────────────────────────────────────

## How small the button starts when it pops in, and how long the pop takes.
@export var pop_from_scale : float = 0.6
@export var pop_duration : float = 0.28
## Where the pop scales from. Kept as the authored minimum size rather than
## reading size: at the moment a button is first shown its size can still be
## zero, which would make the pivot the top-left corner and the pop lopsided.
@export var pop_pivot_size : Vector2 = Vector2(200.0, 60.0)

## Where the selector sits relative to the button's centre. The default puts it
## just above the top edge; a screen with no room above the button (the practice
## range one sits against the bottom of the canvas) can move it to the side.
@export var selector_offset : Vector2 = Vector2(0.0, -40.0)

## When true the selector only shows while this button has focus, so a screen
## with several of them shows ONE selector instead of one per button - which is
## what makes it obvious which option is about to be pressed. The main menu works
## the same way: one pointer that follows the focus owner.
@export var selector_follows_focus : bool = false

@onready var selection_pointer : Control = $SelectionPointer

var _pop : Tween


func _ready() -> void:
	# Still anchored: the wrapper is pinned to the middle of the button and only
	# nudged by this offset, so it keeps tracking the centre if the button's size
	# changes and never has to be re-tuned against a hardcoded position.
	selection_pointer.offset_left += selector_offset.x
	selection_pointer.offset_right += selector_offset.x
	selection_pointer.offset_top += selector_offset.y
	selection_pointer.offset_bottom += selector_offset.y

	if selector_follows_focus:
		selection_pointer.hide()
		focus_entered.connect(_set_selector_visible.bind(true))
		focus_exited.connect(_set_selector_visible.bind(false))
		if has_focus():
			selection_pointer.show()


func _set_selector_visible(focused: bool) -> void:
	selection_pointer.visible = focused


## Bounces the button into view. Safe to call every time it is shown: a pop
## already in flight is restarted rather than stacked.
func pop_in() -> void:
	if _pop != null and _pop.is_valid():
		_pop.kill()
	pivot_offset = pop_pivot_size * 0.5
	scale = Vector2.ONE * pop_from_scale
	modulate.a = 0.0
	_pop = create_tween()
	_pop.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop.tween_property(self, "scale", Vector2.ONE, pop_duration)
	_pop.parallel().tween_property(self, "modulate:a", 1.0, pop_duration * 0.6)
