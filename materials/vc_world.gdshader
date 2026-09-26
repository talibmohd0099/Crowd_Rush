// Generic low-poly world material: flat vertex colours, optional per-instance
// tint (MultiMesh INSTANCE_CUSTOM) on faces whose vertex alpha is 1.
// Faces with vertex alpha ~0.5 glow softly (windows, lamps, signs).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_disabled;

uniform bool use_instance_custom = false;
uniform vec4 tint_color : source_color = vec4(1.0);
uniform float emission_strength = 0.6;
uniform float roughness_value = 0.9;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float emission_boost = 0.0;

varying vec3 v_albedo;
varying float v_emit;

void vertex() {
	vec3 tint = use_instance_custom ? INSTANCE_CUSTOM.rgb : tint_color.rgb;
	vec3 c = COLOR.rgb;
	v_emit = 0.0;
	if (COLOR.a > 0.75) {
		c *= tint;
	} else if (COLOR.a > 0.25) {
		v_emit = 1.0;
	}
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	v_albedo = c; // compatibility renderer: colours stay in sRGB space
#else
	v_albedo = pow(c, vec3(2.2));
#endif
}

void fragment() {
	ALBEDO = mix(v_albedo, vec3(1.0), flash);
	ROUGHNESS = roughness_value;
	EMISSION = v_albedo * v_emit * (emission_strength + emission_boost) + vec3(1.0, 0.9, 0.85) * flash * 0.6;
}
