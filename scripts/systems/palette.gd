class_name Palette
extends RefCounted
## Shared colours + shared materials. Everything that can share a material does,
## which keeps draw-call state changes low on mobile GPUs.

const ROAD := Color(0.24, 0.25, 0.29)
const ROAD_LINE := Color(0.97, 0.95, 0.88)
const ROAD_EDGE := Color(1.0, 0.78, 0.2)
const SIDEWALK := Color(0.72, 0.70, 0.68)
const CURB := Color(0.86, 0.84, 0.80)

const POSITIVE := Color(0.18, 0.78, 1.0)   # +N gates : cyan / blue
const MULTIPLY := Color(1.0, 0.72, 0.12)   # xN gates : gold
const NEGATIVE := Color(1.0, 0.22, 0.25)   # -N gates : red + hazard stripes
const DANGER_DARK := Color(0.16, 0.05, 0.06)

const SHIRTS: Array[Color] = [
	Color(0.20, 0.55, 1.00), Color(0.13, 0.78, 0.62), Color(1.00, 0.55, 0.15),
	Color(0.95, 0.30, 0.45), Color(0.55, 0.40, 0.95), Color(0.98, 0.85, 0.25),
	Color(0.20, 0.70, 0.95), Color(0.40, 0.85, 0.35),
]
const PANTS: Array[Color] = [
	Color(0.18, 0.22, 0.38), Color(0.25, 0.25, 0.28), Color(0.36, 0.30, 0.24),
	Color(0.14, 0.30, 0.42), Color(0.42, 0.44, 0.48),
]
const HAIR: Array[Color] = [
	Color(0.12, 0.09, 0.07), Color(0.35, 0.22, 0.12), Color(0.85, 0.65, 0.30),
	Color(0.20, 0.20, 0.22), Color(0.55, 0.20, 0.10),
]
const CAPS: Array[Color] = [
	Color(0.95, 0.25, 0.25), Color(0.15, 0.15, 0.18), Color(1.0, 1.0, 1.0), Color(0.2, 0.5, 0.95),
]

static var _cache: Dictionary = {}


static func runner_crowd_material() -> ShaderMaterial:
	if not _cache.has("runner_mm"):
		var m := ShaderMaterial.new()
		m.shader = load("res://materials/crowd_runner.gdshader")
		m.set_shader_parameter("use_instance_custom", true)
		_cache["runner_mm"] = m
	return _cache["runner_mm"]


## A per-actor material (physics actors need their own tint uniform).
static func runner_actor_material(tint: Color, skin: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://materials/crowd_runner.gdshader")
	m.set_shader_parameter("use_instance_custom", false)
	m.set_shader_parameter("tint_color", tint)
	m.set_shader_parameter("skin_value", skin)
	return m


static func world_material(instanced := false) -> ShaderMaterial:
	var key := "world_mm" if instanced else "world"
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://materials/vc_world.gdshader")
		m.set_shader_parameter("use_instance_custom", instanced)
		_cache[key] = m
	return _cache[key]


static func unshaded(color: Color, transparent := false, additive := false) -> StandardMaterial3D:
	var key := "u_%s_%s_%s" % [color.to_html(), transparent, additive]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		if transparent or additive:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.shadow_to_opacity = false
		if additive:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_cache[key] = m
	return _cache[key]


## Soft round sprite used by particles and blob shadows.
static func soft_circle_texture() -> Texture2D:
	if not _cache.has("soft_circle"):
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.8))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_cache["soft_circle"] = tex
	return _cache["soft_circle"]


static func particle_material(texture: Texture2D = null, additive := false) -> StandardMaterial3D:
	var key := "p_%s_%s" % [texture != null, additive]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if texture:
			m.albedo_texture = texture
		if additive:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_cache[key] = m
	return _cache[key]


static func font() -> Font:
	if not _cache.has("font"):
		_cache["font"] = load("res://assets/fonts/LilitaOne-Regular.ttf")
	return _cache["font"]
