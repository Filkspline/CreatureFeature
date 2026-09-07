shader_type canvas_item;
render_mode blend_mix;

// Simple hit-spark particle. Outputs the particle's modulate color
// (CPUParticles2D.color) directly with normal alpha blending. The old
// screen-tear shader sampled SCREEN_TEXTURE and mixed toward the
// background, which effectively erased a near-black burst; drawing the
// dark color straight on top makes it visible instead.

void fragment() {
	COLOR = vec4(COLOR.rgb, COLOR.a);
}
