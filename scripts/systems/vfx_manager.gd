class_name VFXManager
extends Node3D
## Lightweight pooled VFX: one-shot CPUParticles3D bursts, shockwave rings and
## floating 3D pop text. CPU particles are cheap for these small counts and run
## identically on every renderer / Android GPU.

const POOL_PER_KIND := 4

var _pools: Dictionary = {}
var _pool_idx: Dictionary = {}
var _rings: Array[MeshInstance3D] = []
var _ring_idx := 0
var _texts: Array[Label3D] = []
var _text_idx := 0
var _motes: CPUParticles3D


func _ready() -> void:
	_make_kind(&"gate", 44, 0.8, _cfg_gate)
	_make_kind(&"sparkle", 26, 0.9, _cfg_sparkle)
	_make_kind(&"multiply", 80, 1.0, _cfg_multiply)
	_make_kind(&"negative", 34, 0.7, _cfg_negative)
	_make_kind(&"dust", 26, 1.4, _cfg_dust)
	_make_kind(&"hit", 10, 0.35, _cfg_hit)
	_make_kind(&"confetti", 140, 3.0, _cfg_confetti)
	_make_kind(&"poof", 8, 0.45, _cfg_poof)
	_make_kind(&"spawn", 7, 0.4, _cfg_spawn)
	_make_kind(&"debris", 18, 1.0, _cfg_debris)
	for i in 6:
		var mi := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.82
		torus.outer_radius = 1.0
		torus.rings = 24
		torus.ring_segments = 3
		mi.mesh = torus
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_rings.append(mi)
	for i in 6:
		var l := Label3D.new()
		l.font = Palette.font()
		l.font_size = 150
		l.pixel_size = 0.01
		l.outline_size = 28
		l.outline_modulate = Color(0.05, 0.05, 0.12, 0.9)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = false
		l.render_priority = 10
		l.outline_render_priority = 9
		l.visible = false
		add_child(l)
		_texts.append(l)


# ------------------------------------------------------------------ API
func burst(kind: StringName, pos: Vector3, color := Color(0, 0, 0, 0), amount_scale := 1.0) -> void:
	if not _pools.has(kind):
		return
	var pool: Array = _pools[kind]
	var i: int = _pool_idx[kind]
	_pool_idx[kind] = (i + 1) % pool.size()
	var p: CPUParticles3D = pool[i]
	p.global_position = pos
	if color.a > 0.0:
		p.color = color
	var base: int = p.get_meta(&"base_amount", p.amount)
	var want := maxi(1, int(base * clampf(amount_scale, 0.05, 1.0)))
	if p.amount != want:
		p.amount = want
	p.restart()
	p.emitting = true


func ring(pos: Vector3, color: Color, radius: float, duration := 0.5) -> void:
	var mi := _rings[_ring_idx]
	_ring_idx = (_ring_idx + 1) % _rings.size()
	var m := mi.material_override as StandardMaterial3D
	m.albedo_color = color
	mi.global_position = pos
	mi.scale = Vector3(0.3, 0.15, 0.3)
	mi.visible = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.15, radius), duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: mi.visible = false)


## Big readable number/word that pops above the crowd ("x2!", "+10").
func pop_text(pos: Vector3, text: String, color: Color, size := 1.0, duration := 0.9) -> void:
	var l := _texts[_text_idx]
	_text_idx = (_text_idx + 1) % _texts.size()
	l.text = text
	l.modulate = color
	l.outline_modulate.a = 0.9
	l.global_position = pos
	l.scale = Vector3.ONE * 0.3 * size
	l.visible = true
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector3.ONE * 1.25 * size, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE * size, 0.12)
	tw.parallel().tween_property(l, "position:y", pos.y + 1.6, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(0.0, duration - 0.5))
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void: l.visible = false)


## Tiny floating dust motes that follow the camera (ambient life, ~24 quads).
func attach_ambient_motes(target: Node3D) -> void:
	if _motes:
		return
	_motes = CPUParticles3D.new()
	_motes.amount = 24
	_motes.lifetime = 5.0
	_motes.preprocess = 5.0
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(6, 3, 8)
	_motes.direction = Vector3(0.2, 1, 0)
	_motes.spread = 40.0
	_motes.gravity = Vector3(0, 0.05, 0)
	_motes.initial_velocity_min = 0.05
	_motes.initial_velocity_max = 0.3
	_motes.scale_amount_min = 0.04
	_motes.scale_amount_max = 0.09
	_motes.color = Color(1, 0.97, 0.85, 0.5)
	_motes.color_ramp = _fade_ramp(Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	_motes.mesh = _quad(Palette.particle_material(Palette.soft_circle_texture(), true))
	_motes.local_coords = false
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target.add_child(_motes)
	# keep them well in front of the lens: close to it they turn into big
	# blurry blobs that cover the (narrow, portrait) screen
	_motes.position = Vector3(0, -2, -18)


# ------------------------------------------------------------------ configs
func _make_kind(kind: StringName, amount: int, lifetime: float, cfg: Callable) -> void:
	var arr: Array = []
	for i in POOL_PER_KIND:
		var p := CPUParticles3D.new()
		p.amount = amount
		p.lifetime = lifetime
		p.one_shot = true
		p.explosiveness = 0.95
		p.emitting = false
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.scale_amount_curve = _shrink_curve()
		cfg.call(p)
		p.set_meta(&"base_amount", p.amount)
		add_child(p)
		arr.append(p)
	_pools[kind] = arr
	_pool_idx[kind] = 0


func _cfg_gate(p: CPUParticles3D) -> void:
	p.mesh = _quad(Palette.particle_material(Palette.soft_circle_texture(), true))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(3.0, 1.8, 0.2)
	p.direction = Vector3(0, 0.6, 1)
	p.spread = 70.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -6, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.2
	p.scale_amount_max = 0.45
	p.color = Palette.POSITIVE


func _cfg_sparkle(p: CPUParticles3D) -> void:
	p.mesh = _quad(Palette.particle_material(Palette.soft_circle_texture(), true))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.5
	p.direction = Vector3(0, 1, 0)
	p.spread = 90.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -1.5, 0)
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.24
	p.color = Color(1.0, 0.95, 0.6)


func _cfg_multiply(p: CPUParticles3D) -> void:
	p.mesh = _quad(Palette.particle_material(Palette.soft_circle_texture(), true))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.2
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 11.0
	p.gravity = Vector3(0, -7, 0)
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.scale_amount_min = 0.18
	p.scale_amount_max = 0.42
	p.color = Palette.MULTIPLY


func _cfg_negative(p: CPUParticles3D) -> void:
	p.mesh = _box(Palette.particle_material(null, false), 0.22)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(2.5, 1.2, 0.5)
	p.direction = Vector3(0, 1, 0.3)
	p.spread = 60.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -14, 0)
	p.angular_velocity_min = -400
	p.angular_velocity_max = 400
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	p.color = Palette.NEGATIVE


func _cfg_dust(p: CPUParticles3D) -> void:
	p.mesh = _quad(Palette.particle_material(Palette.soft_circle_texture(), false))
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 1.5
	p.emission_ring_inner_radius = 0.5
	p.emission_ring_height = 0.2
	p.direction = Vector3(0, 0.3, 0)
	p.spread = 180.0
	p.flatness = 0.8
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.damping_min = 4.0
	p.damping_max = 6.0
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.6
	p.scale_amount_curve = _grow_curve()
	p.color = Color(0.82, 0.76, 0.66, 0.7)
	p.color_ramp = _fade_ramp(Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0))


func _cfg_hit(p: CPUParticles3D) -> void:
	p.mesh = _quad(Palette.particle_material(Palette.soft_circle_texture(), true))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3.ZERO
	p.damping_min = 8.0
	p.damping_max = 10.0
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.3
	p.color = Color(1.0, 0.95, 0.75)


func _cfg_confetti(p: CPUParticles3D) -> void:
	p.mesh = _quad(Palette.particle_material(null, false), Vector2(0.18, 0.1))
	p.explosiveness = 0.85
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(5, 0.5, 3)
	p.direction = Vector3(0, 1, 0)
	p.spread = 35.0
	p.initial_velocity_min = 9.0
	p.initial_velocity_max = 15.0
	p.gravity = Vector3(0, -7, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.angle_min = 0
	p.angle_max = 360
	p.angular_velocity_min = -540
	p.angular_velocity_max = 540
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	p.scale_amount_curve = null
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	g.colors = PackedColorArray([Color(1, 0.3, 0.35), Color(1, 0.8, 0.2), Color(0.3, 0.85, 0.4), Color(0.25, 0.6, 1), Color(0.75, 0.4, 1), Color(1, 1, 1)])
	p.color_initial_ramp = g


func _cfg_poof(p: CPUParticles3D) -> void:
	p.mesh = _quad(Palette.particle_material(Palette.soft_circle_texture(), false))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.spread = 180.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, 1.0, 0)
	p.damping_min = 3.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.6
	p.color = Color(0.95, 0.95, 1.0, 0.75)


func _cfg_spawn(p: CPUParticles3D) -> void:
	p.mesh = _quad(Palette.particle_material(Palette.soft_circle_texture(), true))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3.ZERO
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.scale_amount_min = 0.14
	p.scale_amount_max = 0.26
	p.color = Color(0.7, 0.95, 1.0)


func _cfg_debris(p: CPUParticles3D) -> void:
	p.mesh = _box(Palette.particle_material(null, false), 0.16)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(2.0, 0.6, 0.3)
	p.direction = Vector3(0, 1, -0.6)
	p.spread = 50.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0, -16, 0)
	p.angular_velocity_min = -600
	p.angular_velocity_max = 600
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.scale_amount_curve = null
	p.color = Color(0.72, 0.5, 0.3)


# ------------------------------------------------------------------ helpers
func _quad(mat: Material, size := Vector2(1, 1)) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	q.material = mat
	return q


func _box(mat: Material, s: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(s, s, s)
	b.material = mat
	return b


func _shrink_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(0.6, 0.8))
	c.add_point(Vector2(1, 0))
	return c


func _grow_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1))
	return c


func _fade_ramp(a: Color, b: Color, c: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([a, b, c])
	return g
