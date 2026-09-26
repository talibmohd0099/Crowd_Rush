// Runner material shared by the whole crowd (MultiMesh) and physics actors.
// Vertex colour alpha selects the colour source (see MeshFactory):
//   a ~ 1.0 -> per-runner tint (shirt / pants / hair)
//   a ~ 0.5 -> per-runner skin tone
//   a ~ 0.2 -> per-runner shoe colour (toe cap, tongue, sole)
//   a ~ 0.0 -> fixed vertex colour (shoe upper, eyes ...)
// MultiMesh instances pass tint in INSTANCE_CUSTOM.rgb and a packed
// (skin + 4 * shoe) index / 16 in .a (see RunnerRig.random_look).
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

const vec3 SHOE_0 = vec3(0.95, 0.22, 0.25);
const vec3 SHOE_1 = vec3(0.55, 0.35, 0.95);
const vec3 SHOE_2 = vec3(0.15, 0.62, 1.00);
const vec3 SHOE_3 = vec3(1.00, 0.62, 0.12);

void vertex() {
	vec4 custom = use_instance_custom ? INSTANCE_CUSTOM : vec4(tint_color.rgb, skin_value);
	float packed = floor(custom.a * 16.0);
	float si = mod(packed, 4.0);
	float shi = floor(packed / 4.0);
	vec3 skin = si < 1.0 ? SKIN_0 : (si < 2.0 ? SKIN_1 : (si < 3.0 ? SKIN_2 : SKIN_3));
	vec3 shoe = shi < 1.0 ? SHOE_0 : (shi < 2.0 ? SHOE_1 : (shi < 3.0 ? SHOE_2 : SHOE_3));
	vec3 c = COLOR.rgb;
	if (COLOR.a > 0.75) {
		c = custom.rgb;
	} else if (COLOR.a > 0.35) {
		c = skin;
	} else if (COLOR.a > 0.1) {
		c = shoe;
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
