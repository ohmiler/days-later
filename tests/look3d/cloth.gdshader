shader_type spatial;
render_mode cull_disabled;
// Cloth made in code: a colour, a pattern, dirt and blood. UV: x goes around
// the body (0..1), y is metres along the limb or up the body.

uniform vec3 col : source_color = vec3(0.3, 0.4, 0.6);
uniform vec3 col2 : source_color = vec3(0.9);
uniform int pattern = 0;  // 0 plain, 1 stripes, 2 plaid, 3 dots, 4 camo, 5 print on the chest
uniform float grime = 0.0;
uniform float blood = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.0) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return noise(p) * 0.55 + noise(p * 2.1) * 0.28 + noise(p * 4.3) * 0.17; }

void fragment() {
	vec2 m = vec2(UV.x * 0.85, UV.y);  // roughly metres both ways
	vec3 c = col;
	if (pattern == 1) {
		c = mix(col, col2, step(0.5, fract(m.y * 14.0)));
	} else if (pattern == 2) {
		float a = step(0.62, fract(m.x * 9.0));
		float b = step(0.62, fract(m.y * 9.0));
		c = mix(col, col2, clamp(a * 0.55 + b * 0.55, 0.0, 1.0));
		c = mix(c, col * 0.6, step(0.93, fract(m.x * 9.0 + 0.3)) * 0.5);
	} else if (pattern == 3) {
		vec2 g = fract(m * 22.0) - 0.5;
		c = mix(col, col2, step(length(g), 0.18));
	} else if (pattern == 4) {
		float n = fbm(m * 7.0);
		c = n < 0.42 ? col * 0.55 : (n < 0.58 ? col : col2);
	} else if (pattern == 5) {
		// A print on the front: a round logo of the second colour.
		float front = abs(UV.x - 0.25);
		c = mix(col, col2, step(length(vec2(front * 3.0, (m.y - 0.3) * 1.2)), 0.08));
	}
	// Weave, and the cloth going darker in its folds.
	float weave = noise(m * 260.0);
	c *= 0.93 + weave * 0.1;
	c *= 0.9 + fbm(m * 9.0) * 0.18;
	// Dirt: patches, heavier low down.
	float d = fbm(m * 5.0 + 3.0);
	c = mix(c, c * vec3(0.45, 0.4, 0.33), clamp((d - 0.55 + grime * 0.5) * 2.0, 0.0, 1.0) * grime);
	// Blood: dark red splashes.
	float bl = fbm(m * 8.0 + 11.0);
	c = mix(c, vec3(0.22, 0.02, 0.02), smoothstep(0.66, 0.72, bl + blood * 0.1) * step(0.01, blood));
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.3;
}
