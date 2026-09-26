// Runner material shared by the whole crowd (MultiMesh) and physics actors.
// Vertex colour alpha selects the colour source (see MeshFactory):
//   a ~ 1.0 -> per-runner tint (shirt / pants / hair)
//   a ~ 0.5 -> per-runner skin tone
//   a ~ 0.0 -> fixed vertex colour (shoes, belt ...)
// MultiMesh instances pass tint in INSTANCE_CUSTOM.rgb and skin index in .a.
// Stand-alone meshes (physics actors) use the uniforms instead.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_disabled;

uniform bool use_instance_custom = true;
uniform vec4 tint_color : source_color = vec4(1.0);
uniform float skin_value = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.22;

varying vec3 v_albedo;

const vec3 SKIN_0 = vec3(1.00, 0.80, 0.66);
const vec3 SKIN_1 = vec3(0.92, 0.67, 0.50);
const vec3 SKIN_2 = vec3(0.70, 0.47, 0.32);
const vec3 SKIN_3 = vec3(0.45, 0.30, 0.21);

void vertex() {
	vec4 custom = use_instance_custom ? INSTANCE_CUSTOM : vec4(tint_color.rgb, skin_value);
	float si = custom.a * 4.0;
	vec3 skin = si < 1.0 ? SKIN_0 : (si < 2.0 ? SKIN_1 : (si < 3.0 ? SKIN_2 : SKIN_3));
	vec3 c = COLOR.rgb;
	if (COLOR.a > 0.75) {
		c = custom.rgb;
	} else if (COLOR.a > 0.25) {
		c = skin;
	}
	// palette colours are authored in sRGB
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	v_albedo = c; // compatibility renderer: colours stay in sRGB space
#else
	v_albedo = pow(c, vec3(2.2));
#endif
}

void fragment() {
	ALBEDO = mix(v_albedo, vec3(1.0), flash);
	ROUGHNESS = 0.85;
	RIM = rim_strength;
	RIM_TINT = 0.3;
}
