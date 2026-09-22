class_name SoundConfig
extends Resource

# ──────────────────────────────────────────────────────────────────
#  SoundConfig
#
#  One sound plus how it should be played, as a Resource so the same
#  config can be shared (every special pointing at one charge-up sound) or
#  overridden per move in the Inspector.
#
#  This only describes a sound. SfxManager does the playing, so there is
#  exactly one implementation of pitch randomisation, volume and pooling in
#  the project.

## The clip to play.
@export var stream: AudioStream
## Volume offset in dB, applied on top of SfxManager's own level.
@export var volume_db: float = 0.0
## Playback rate. In Godot this scales speed AND pitch together, so it is
## both the "this sound should be faster/slower" knob and the pitch knob.
@export var pitch_scale: float = 1.0
## Random spread applied to pitch_scale on every play, as a fraction:
## 0.05 means up to 5% either way. This is what keeps a sound that fires
## constantly (hit impacts especially) from sounding mechanical.
@export_range(0.0, 1.0, 0.01) var pitch_variance: float = 0.0
