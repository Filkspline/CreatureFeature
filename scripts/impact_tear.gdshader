shader_type canvas_item;

// Local-impact version of the screen-tear shader. Dropped from the
// original: full-screen curvature warp, CRT-sync reapplication, the
// motion trail, and the crack overlay — none of those make sense for a
// small, stationary burst at a hit point. What's left is the part that
// actually reads as "impact": glitchy horizontal tear bands + chromatic
// aberration radiating from a point, with a bright core/glow on top.
//
// Meant to run on a small square Control (e.g. ColorRect) sized ~150-220px,
// centered on the impact point. UV spans 0..1 across that node's own rect,
// completely independent of SCREEN_UV (which is used only for sampling the
// actual screen behind it).

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform vec2 impact_pos = vec2(0.5, 0.5);

uniform float core_radius : hint_range(0.0, 0.5) = 0.08;
uniform float glow_radius : hint_range(0.0, 0.5) = 0.35;

uniform vec3 core_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 rim_color : source_color = vec3(1.0, 1.0, 1.0);

uniform float tear_strength : hint_range(0.0, 0.1) = 0.02;
uniform float tear_band_count : hint_range(10.0, 300.0) = 60.0;
uniform float tear_radius : hint_range(0.02, 0.6) = 0.4;
uniform float flicker_speed : hint_range(1.0, 30.0) = 20.0;
uniform float chrom_strength : hint_range(0.0, 0.05) = 0.015;

uniform float fade_start : hint_range(0.0, 0.6) = 0.35;
uniform float fade_end : hint_range(0.0, 0.8) = 0.65;

// Drive this from GDScript (1.0 -> 0.0 over the effect's lifetime) to
// fade the whole thing out with one tween instead of several.
uniform float effect_alpha : hint_range(0.0, 1.0) = 1.0;

float random(vec2 uv) {
	return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 diff = UV - impact_pos;
	float dist = length(diff);

	float tear_influence = smoothstep(tear_radius, 0.0, dist);

	float band = floor(UV.y * tear_band_count);
	float band_rand = random(vec2(band, floor(TIME * flicker_speed)));
	float offset = (band_rand - 0.5) * 2.0 * tear_strength * tear_influence;

	vec2 tear_uv = SCREEN_UV + vec2(offset, 0.0);

	float chrom = chrom_strength * tear_influence;
	vec3 color;
	color.r = texture(SCREEN_TEXTURE, tear_uv + vec2(chrom, 0.0)).r;
	color.g = texture(SCREEN_TEXTURE, tear_uv).g;
	color.b = texture(SCREEN_TEXTURE, tear_uv - vec2(chrom, 0.0)).b;

	float glow = 1.0 - smoothstep(0.0, glow_radius, dist);
	color += rim_color * glow * 0.8;

	float core = 1.0 - smoothstep(core_radius * 0.3, core_radius, dist);
	color = mix(color, core_color, core);

	float edge_fade = (1.0 - smoothstep(fade_start, fade_end, dist)) * effect_alpha;

	vec3 raw_bg = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	color = mix(raw_bg, color, edge_fade);

	COLOR = vec4(color, 1.0);
}
