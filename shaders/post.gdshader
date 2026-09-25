shader_type canvas_item;
// Whole-screen film look: muted colours, grade, contrast, vignette, grain.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float saturation = 0.8;
uniform vec3 tint = vec3(1.08, 1.06, 0.96);
uniform float contrast = 1.05;
uniform float vignette = 0.9;
uniform float grain = 0.035;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(g), c, saturation) * tint;
	c = (c - 0.5) * contrast + 0.5;
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - dot(d, d) * vignette;
	float n = fract(sin(dot(SCREEN_UV * 1000.0 + fract(TIME) * 37.0, vec2(12.9898, 78.233))) * 43758.5453);
	c += (n - 0.5) * grain;
	COLOR = vec4(c, 1.0);
}
