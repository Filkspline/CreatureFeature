# Gameplay pass notes

This covers the combo system, the single special move change, dashes, the crouch block tweak, move renames, and the pause menu fix.

## Combo tracking (new autoload)

New file `scripts/ComboManager.gd`, registered as an autoload in `project.godot`.

It tracks a hit count per defender. `EventBus.player_hit_landed` bumps the count when a non blocked hit lands (blocked hits do not keep a combo going), and `EventBus.player_state_changed` resets it when the defender goes back to NEUTRAL.

It exposes `get_combo_count(defender_id)` and `get_combo_damage_scale(defender_id)`. The damage scale is a multiplier: the first hit of a combo is full damage, each hit after that loses a percentage, down to a floor. It also emits `combo_changed(defender_id, combo_count)` whenever the count changes so the UI can react without polling.

Tunable values on ComboManager:
- `combo_damage_reduction_per_hit` = 0.1 (10% less damage per extra hit)
- `combo_min_damage_scale` = 0.2 (damage never drops below 20% of full)

The scale is applied in `Player._resolve_hit()` as a multiplier on the final damage after the existing bonus and reduction math, so it does not change that order.

## Combo counter in the fight UI

`fight_ui.gd` now builds two runtime labels, one per side, styled to match the retro health bars (white text, dark navy outline). They show the current hit count on the attacking player's side and hide once the combo resets to zero. The attacker is derived from the defender id (it's a two player game, so attacker = 3 minus defender).

## Single selected special move

The Special button no longer does a directional lookup. `Player` now has a `selected_special` MoveData slot. Pressing Special on the ground always performs that move. The aerial special (SA) still works exactly as before and is untouched.

`selected_special` defaults to Bite (S5) in the inspector (`player.tscn`). Picking a special unlock card overwrites it with that card's move. This goes through the existing `unlock_move` flow: `unlock_move` now also sets `selected_special` when the move is a SPECIAL.

The special roster is now three grounded moves plus the aerial:
- Bite (S5), default
- Slam (S8), locked by default
- Uppercut (N8, moved from normals), locked by default
- SA aerial, always available

## Crouching blocks automatically

`Player._is_block_ready()` now returns true for a crouching player without requiring the back direction. Standing still requires back held, same as before. This only changes the crouching branch.

## S4 and S6 are now double tap dashes

S4 (back) and S6 (forward) are no longer specials. They are base kit moves, always available, triggered by double tapping the direction:
- double tap back triggers S4
- double tap forward triggers S6

S4's `fires_projectile` is turned off. Both moves are removed from `locked_move_names` and their unlock cards were moved out of the card pool into `scripts/deprecated_card_files/`.

Double tap window is tunable on Player: `double_tap_window_ms` = 200 (200 milliseconds between taps).

## N8 becomes Uppercut, S5 gets a card

N8 moved out of the normals and into the special roster as Uppercut, locked by default. It got a new unlock card (`N8UnlockCard.tres`). S5 (Bite) also got a card (`S5UnlockCard.tres`) so it can be re selected after picking a different special. The existing S8 card was renamed from "Up Special" to "Slam".

## Move renames

- S8 is now Slam
- S5 is now Bite
- N8 is now Uppercut
- S4 is now BackDash
- S6 is now ForwardDash

The MoveData `move_name` fields and card labels changed. The variable slot names in `testplayer1.gd` (S8, S5, N8, S4, S6) stayed the same to avoid churn.

A note on how this works internally: sprite nodes are looked up by `animation_name`, not `move_name`. I changed `_all_move_sprite_names` and `show_attack_sprite` to use `animation_name`. That means the sprite tree and animation tracks in `player.tscn` did not need renaming at all, only the logical move names changed.

## Pause menu quit fix

`pause.gd` quit to main menu now calls `GameManager.reset_player_select()` and `GameManager.start_match()` before changing scene, same as the end screen restart button. Round counts and picked upgrades now clear properly.

## Judgment calls

- S2 is not part of this pass. It was the crouching directional special and does not fit the single selected special model. Per the task, it will become another pickable special card later. I did not try to force it in.
- The dash moves keep their `advance_speed` and `is_advancing` values from before (backward 600 and forward 1200), since the task said not to touch those.
- Blocked hits do not increment the combo and do not benefit from the combo damage scaling. Only clean hits count.
- The combo counter is derived from the defender id assuming a two player game. If more than two players ever get added, that helper needs a real attacker lookup.

## Files changed

- New: `scripts/ComboManager.gd`, `scripts/ComboManager.gd.uid`, `scripts/card_resource_files/S5UnlockCard.tres`, `scripts/card_resource_files/N8UnlockCard.tres`
- Moved to deprecated: `scripts/card_resource_files/S4UnlockCard.tres`, `scripts/card_resource_files/S6UnlockCard.tres`
- Modified: `project.godot`, `scripts/testplayer1.gd`, `scripts/PlayerVisuals.gd`, `scripts/fight_ui.gd`, `scripts/pause.gd`, `scripts/S4.tres`, `scripts/S6.tres`, `scripts/S5.tres`, `scripts/S8.tres`, `scripts/N8.tres`, `scripts/card_resource_files/S8UnlockCard.tres`, `scenes/player.tscn`
