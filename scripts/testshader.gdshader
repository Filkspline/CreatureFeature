shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform float curvature : hint_range(0.0, 0.3) = 0.008;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.03;
uniform float scanline_count : hint_range(100, 800) = 500;
uniform float vignette_size : hint_range(0.0, 2.0) = 0.04;
uniform float brightness : hint_range(0.5, 2.0) = 1.3;
uniform float contrast : hint_range(0.5, 2.0) = 1.2;
uniform float saturation : hint_range(0.0, 2.0) = 1.1;
uniform float chromatic_aberration : hint_range(0.0, 0.02) = 0.0004;
uniform float noise_amount : hint_range(0.0, 0.05) = 0.0015;
uniform float flicker : hint_range(0.0, 0.03) = 0.0008;
uniform float distortion : hint_range(0.0, 0.05) = 0.005;

float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    vec2 uv = UV;
    
    // Simple curvature effect
    vec2 curved_uv = uv * 2.0 - 1.0;
    curved_uv *= 1.0 + curvature * (curved_uv.yx * curved_uv.yx);
    curved_uv = curved_uv * 0.5 + 0.5;
    
    vec3 color;
    
    if (curved_uv.x < 0.0 || curved_uv.x > 1.0 || curved_uv.y < 0.0 || curved_uv.y > 1.0) {
        color = vec3(0.0);
    } else {
        // Screen distortion
        float distortion_x = sin(curved_uv.y * 30.0 + TIME * 2.0) * distortion;
        curved_uv.x += distortion_x;
        
        // Chromatic aberration
        float offset = chromatic_aberration * sin(uv.y * 30.0);
        color.r = texture(SCREEN_TEXTURE, curved_uv + vec2(offset, 0.0)).r;
        color.g = texture(SCREEN_TEXTURE, curved_uv).g;
        color.b = texture(SCREEN_TEXTURE, curved_uv - vec2(offset, 0.0)).b;
        
        // Scanlines
        float scanline = sin(curved_uv.y * scanline_count) * 0.5 + 0.5;
        color *= mix(1.0, scanline, scanline_intensity);
        
        // Vignette
        float vignette = 1.0 - length((curved_uv - 0.5) * vignette_size * 2.0);
        color *= clamp(vignette, 0.0, 1.0);
        
        // Contrast, brightness, saturation
        color = (color - 0.5) * contrast + 0.5;
        color *= brightness;
        float gray = dot(color, vec3(0.299, 0.587, 0.114));
        color = mix(vec3(gray), color, saturation);
        
        // Flicker
        color *= 1.0 - (random(vec2(TIME, 0.0)) * flicker);
        
        // Noise
        color += random(uv * TIME) * noise_amount;
    }
    
    COLOR = vec4(color, 1.0);
}