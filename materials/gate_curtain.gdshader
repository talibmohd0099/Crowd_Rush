// Translucent animated gate "curtain". Pattern also encodes the gate type so
// it is readable without relying on colour alone:
//   0 = ADD      : upward chevrons
//   1 = MULTIPLY : sparkling diamonds
//   2 = SUBTRACT : diagonal hazard stripes
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform int pattern = 0;
uniform float intensity = 1.0;
uniform float highlight = 0.0;

void fragment() {
	vec2 uv = UV;
	float ex = abs(uv.x * 2.0 - 1.0);
	float ey = abs(uv.y * 2.0 - 1.0);
	float edge = max(smoothstep(0.86, 1.0, ex), smoothstep(0.86, 1.0, ey));
	float p = 0.0;
	if (pattern == 0) {
		float v = fract(uv.y * 3.0 + abs(uv.x - 0.5) * 1.6 + TIME * 0.9);
		p = smoothstep(0.62, 0.7, v) * (1.0 - smoothstep(0.86, 0.94, v)) * 0.32;
	} else if (pattern == 1) {
		vec2 g = fract(uv * vec2(7.0, 5.0) + vec2(0.0, TIME * 0.4)) - 0.5;
		float d = abs(g.x) + abs(g.y);
		float tw = 0.5 + 0.5 * sin(TIME * 5.0 + floor(uv.x * 7.0) * 2.1 + floor(uv.y * 5.0));
		p = (1.0 - smoothstep(0.12, 0.2, d)) * (0.2 + 0.3 * tw);
	} else {
		float v = fract(uv.x * 5.0 + uv.y * 3.0 - TIME * 0.5);
		p = step(0.5, v) * 0.26;
	}
	float pulse = highlight * (0.5 + 0.5 * sin(TIME * 8.0)) * 0.25;
	// fairly solid, glowing panel (reads like a neon sign on a phone screen):
	// brighter towards the bottom and edges, HDR edges feed the glow pass
	float grad = mix(0.8, 1.15, uv.y);
	ALBEDO = color.rgb * (grad + edge * 1.1 + p * 0.8) + vec3(pulse);
	ALPHA = clamp((0.5 + p + edge * 0.5 + pulse) * intensity, 0.0, 1.0);
}
