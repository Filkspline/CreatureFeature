class_name ControlScheme
extends RefCounted

# ──────────────────────────────────────────────────────────────────
#  ControlScheme
#
#  Which icon-sheet row belongs to a player's input device, and which frame
#  within that row is which action. Three screens draw these icons (the
#  player-select cursors, the legend under a selected creature, and the
#  pause menu's controls panel), so the mapping lives here once.
#
#  Devices are matched by KIND, never by display_name. A controller reports
#  whatever the OS calls it ("Xbox 360 Controller", "Wireless Controller",
#  "PS4 Controller"...), so matching an exact name string missed every pad
#  and fell through to the first keyboard row - which is why controller
#  users saw WASD icons. Keyboard devices carry the layout they claimed
#  ("P1" = the WASD set, "P2" = the arrow set), which is a value the project
#  itself controls, so that is what is matched on instead.
#
#  The sheet is assets/TempAssets/temp_game_controls.png, sliced into 100x100
#  frames by assets/controls.tres. Row 0 is the WASD scheme, row 1 the
#  arrow-key scheme, row 2 the controller. Each row is a movement icon
#  followed by that scheme's action icons.

enum Scheme { WASD, ARROWS, CONTROLLER }

## The keyboard layout suffix that means "the arrow-key set" (see
## player_select.gd's KEYBOARD_LAYOUTS).
const ARROW_LAYOUT_SUFFIX := "P2"

## Movement icon per scheme: the WASD cluster, the arrow cluster, the pad.
const MOVEMENT_FRAME := {
	Scheme.WASD: 0,
	Scheme.ARROWS: 7,
	Scheme.CONTROLLER: 15,
}

## Attack icon per scheme. The arrow-key row had normal and special the wrong
## way round (each pointing at the other's key); the WASD row was correct. The
## controller's are its A and B buttons.
const NORMAL_FRAME := {
	Scheme.WASD: 5,
	Scheme.ARROWS: 13,
	Scheme.CONTROLLER: 16,
}
const SPECIAL_FRAME := {
	Scheme.WASD: 6,
	Scheme.ARROWS: 12,
	Scheme.CONTROLLER: 17,
}

## Jump only has an icon on the controller row, which is why a legend for a
## keyboard scheme is one row shorter than one for a pad.
const JUMP_FRAME := {
	Scheme.CONTROLLER: 18,
}


## Which sheet row a device draws from.
static func scheme_for(device: PlayerInputDevice) -> int:
	if device == null:
		return Scheme.WASD
	if device.kind == PlayerInputDevice.Kind.KEYBOARD:
		return Scheme.ARROWS if device.native_action_suffix == ARROW_LAYOUT_SUFFIX else Scheme.WASD
	return Scheme.CONTROLLER


static func movement_frame(scheme: int) -> int:
	return MOVEMENT_FRAME.get(scheme, MOVEMENT_FRAME[Scheme.WASD])


static func normal_frame(scheme: int) -> int:
	return NORMAL_FRAME.get(scheme, NORMAL_FRAME[Scheme.WASD])


static func special_frame(scheme: int) -> int:
	return SPECIAL_FRAME.get(scheme, SPECIAL_FRAME[Scheme.WASD])


## Frame for one action key on a scheme, or -1 when that scheme has no icon
## for it (a keyboard row draws no jump key). Action keys are the ones used in
## ControlPrompts' entry tables.
static func frame_for(scheme: int, action_key: String) -> int:
	match action_key:
		"movement":
			return movement_frame(scheme)
		"normal":
			return normal_frame(scheme)
		"special":
			return special_frame(scheme)
		"jump":
			return JUMP_FRAME.get(scheme, -1)
	return -1


## The action name a prompt's input watching should listen to for this action
## key, for a given player ("P1"/"P2"). Empty when the key isn't watched.
static func input_action_for(action_key: String, slot_suffix: String) -> StringName:
	match action_key:
		"normal":
			return StringName("Normal" + slot_suffix)
		"special":
			return StringName("Special" + slot_suffix)
		"jump":
			return StringName("Jump" + slot_suffix)
		"movement":
			return StringName("Left" + slot_suffix)
	return &""


## The rows a legend should show for a scheme, as [frame, label] pairs, in
## the order they are drawn. Movement is not one of them, on purpose: a legend
## is for the action buttons a player has to look up.
static func legend_rows(scheme: int) -> Array:
	var rows := [
		[NORMAL_FRAME.get(scheme, NORMAL_FRAME[Scheme.WASD]), "Normal"],
		[SPECIAL_FRAME.get(scheme, SPECIAL_FRAME[Scheme.WASD]), "Special"],
	]
	if JUMP_FRAME.has(scheme):
		rows.append([JUMP_FRAME[scheme], "Jump"])
	return rows
