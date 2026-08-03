shader_type canvas_item;

uniform vec3 fog_color : source_color = vec3(0.8, 0.85, 0.9);
uniform float opacity : hint_range(0.0, 1.0) = 0.25;
uniform float density : hint_range(0.0, 1.0) = 0.5;
uniform float noise_scale : hint_range(1.0, 50.0) = 8.0;
uniform vec2 scroll_speed = vec2(0.02, 0.005);
uniform float softness : hint_range(0.01, 1.0) = 0.4;

float random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

float value_noise(vec2 uv) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	float a = random(i);
	float b = random(i + vec2(1.0, 0.0));
	float c = random(i + vec2(0.0, 1.0));
	float d = random(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// A few octaves of the noise above, layered — this is what gives fog its
// "wispy" look instead of flat blobby noise.
float fbm(vec2 uv) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * value_noise(uv);
		uv *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 uv = UV * noise_scale + TIME * scroll_speed;
	float n = fbm(uv);
	n = smoothstep(1.0 - density - softness, 1.0 - density + softness, n);
	COLOR = vec4(fog_color, n * opacity);
}
