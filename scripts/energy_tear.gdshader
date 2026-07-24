shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform vec2 rect_size = vec2(220.0, 220.0);
uniform vec2 ball_pos = vec2(0.5, 0.5);

uniform float ball_core_radius : hint_range(0.0, 0.5) = 0.06;
uniform float ball_glow_radius : hint_range(0.0, 0.5) = 0.3;

uniform vec3 core_color : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 rim_color : source_color = vec3(0, 0, 0);
uniform vec3 trail_color : source_color = vec3(0, 0, 0);

uniform float tear_strength : hint_range(0.0, 0.1) = 0.02;
uniform float tear_band_count : hint_range(10.0, 300.0) = 40.0;
uniform float tear_radius : hint_range(0.02, 0.6) = 0.4;
uniform float tear_falloff : hint_range(0.5, 20.0) = 5.0;
uniform float flicker_speed : hint_range(1.0, 30.0) = 18.0;

uniform float chrom_strength : hint_range(0.0, 0.05) = 0.019;
uniform float crack_amount : hint_range(0.0, 1.0) = 0.0;

uniform float trail_length : hint_range(0.0, 1.0) = 0.4;
uniform float trail_height : hint_range(1.0, 30.0) = 4.0;

uniform float fade_start : hint_range(0.0, 0.6) = 0.35;
uniform float fade_end : hint_range(0.0, 0.8) = 0.65;

// --- CRT-matching params. KEEP THESE IN SYNC with your CRT shader's current values. ---
uniform float crt_curvature : hint_range(0.0, 0.3) = 0.008;
uniform float crt_scanline_intensity : hint_range(0.0, 1.0) = 0.06;
uniform float crt_scanline_count : hint_range(100.0, 800.0) = 650.0;
uniform float crt_vignette_size : hint_range(0.0, 2.0) = 0.12;
uniform float crt_brightness : hint_range(0.5, 2.0) = 1.04;
uniform float crt_contrast : hint_range(0.5, 2.0) = 1.03;
uniform float crt_saturation : hint_range(0.0, 2.0) = 1.04;
uniform float crt_flicker : hint_range(0.0, 0.03) = 0.0015;
uniform float crt_noise_amount : hint_range(0.0, 0.05) = 0.03;

float random(vec2 uv) {
	return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

// Same barrel-warp math as the CRT shader, so this patch samples the
// same screen pixels the CRT shader would have sampled at this UV.
vec2 apply_curvature(vec2 uv) {
	vec2 curved_uv = uv * 2.0 - 1.0;
	curved_uv *= 1.0 + crt_curvature * (curved_uv.yx * curved_uv.yx);
	curved_uv = curved_uv * 0.5 + 0.5;
	return curved_uv;
}

// Reapplies just the procedural (non-warping) parts of the CRT look,
// so this patch matches the surrounding CRT'd screen exactly.
vec3 reapply_crt_style(vec3 base_color, vec2 screen_uv) {
	vec3 c = base_color;

	float scanline = sin(screen_uv.y * crt_scanline_count) * 0.5 + 0.5;
	c *= mix(1.0, scanline, crt_scanline_intensity);

	float vignette = 1.0 - length((screen_uv - 0.5) * crt_vignette_size * 2.0);
	c *= clamp(vignette, 0.0, 1.0);

	c = (c - 0.5) * crt_contrast + 0.5;
	c *= crt_brightness;
	float gray = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(gray), c, crt_saturation);

	c *= 1.0 - (random(vec2(TIME, 0.0)) * crt_flicker);
	c += random(screen_uv * TIME) * crt_noise_amount;

	return c;
}

void fragment() {
	vec2 uv = UV;

	float aspect = rect_size.y / rect_size.x;
	vec2 diff = uv - ball_pos;
	diff.x /= aspect;
	float dist = length(diff);

	float tear_influence = smoothstep(tear_radius, 0.0, dist);
	tear_influence = pow(tear_influence, tear_falloff * 0.2);

	float band = floor(uv.y * tear_band_count);
	float band_rand = random(vec2(band, floor(TIME * flicker_speed)));
	float offset = (band_rand - 0.5) * 2.0 * tear_strength * tear_influence;

	// Curvature applied once, up front — everything downstream (tear
	// offset, chromatic split, background sample) now reads from the
	// same warped coordinate space the CRT shader uses.
	vec2 screen_uv = apply_curvature(SCREEN_UV);
	vec2 tear_uv = screen_uv + vec2(offset, 0.0);

	float chrom = chrom_strength * tear_influence;
	vec3 color;
	color.r = texture(SCREEN_TEXTURE, tear_uv + vec2(chrom, 0.0)).r;
	color.g = texture(SCREEN_TEXTURE, tear_uv).g;
	color.b = texture(SCREEN_TEXTURE, tear_uv - vec2(chrom, 0.0)).b;

	float crack_noise = random(vec2(band, uv.x * 50.0));
	float crack_mask = step(1.0 - crack_amount * tear_influence, crack_noise) * tear_influence;
	color = mix(color, trail_color, crack_mask * 0.6);

	float trail = 0.0;
	if (uv.x < ball_pos.x) {
		float trail_dist = ball_pos.x - uv.x;
		trail = exp(-trail_dist / max(trail_length, 0.001)) * exp(-abs(diff.y) * trail_height);
	}
	color += trail_color * trail * 0.5;

	float glow = 1.0 - smoothstep(0.0, ball_glow_radius, dist);
	color += rim_color * glow * 0.8;

	float core = 1.0 - smoothstep(ball_core_radius * 0.3, ball_core_radius, dist);
	color = mix(color, core_color, core);

	float core_add = 1.0 - smoothstep(0.0, ball_core_radius * 1.5, dist);
	color += core_color * core_add * 0.5;

	float edge_fade = 1.0 - smoothstep(fade_start, fade_end, dist);

	vec3 raw_bg = texture(SCREEN_TEXTURE, screen_uv).rgb;
	raw_bg = reapply_crt_style(raw_bg, screen_uv);

	color = mix(raw_bg, color, edge_fade);

	COLOR = vec4(color, 1.0);
}