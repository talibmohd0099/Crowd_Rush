class_name EnvironmentBuilder
extends Node3D
## Builds the whole stylized urban-industrial street procedurally:
## lighting/sky/fog, road + markings, sidewalks, modular buildings, skyline,
## streetlights, props, parked cars, drifting clouds and simple colliders.
## Repeated objects are MultiMeshes (one draw call per kind) with per-instance
## tint via INSTANCE_CUSTOM, so the whole city costs only a few dozen draw calls.

@export var start_d := -90.0
@export var end_d := 455.0 ## where the street hands over to the boss arena
@export var road_half_width := 7.0
@export var sidewalk_width := 4.5
@export var seed_value := 20240601
@export var enable_shadows := true

var sun: DirectionalLight3D
var world_env: WorldEnvironment

var _rng := RandomNumberGenerator.new()
var _clouds: MultiMeshInstance3D
var _time := 0.0

const WALL_TINTS: Array[Color] = [
	Color(0.93, 0.84, 0.72), Color(0.85, 0.55, 0.45), Color(0.62, 0.74, 0.78),
	Color(0.95, 0.92, 0.84), Color(0.72, 0.42, 0.36), Color(0.55, 0.62, 0.78),
	Color(0.88, 0.76, 0.52), Color(0.7, 0.78, 0.66),
]
const CAR_TINTS: Array[Color] = [
	Color(0.9, 0.2, 0.2), Color(0.2, 0.45, 0.9), Color(0.95, 0.95, 0.95),
	Color(0.15, 0.15, 0.18), Color(0.95, 0.75, 0.15), Color(0.3, 0.7, 0.5),
]


func _ready() -> void:
	_rng.seed = seed_value
	_build_lighting()
	_build_ground()
	_build_markings()
	_build_buildings()
	_build_skyline()
	_build_streetlights()
	_build_props()
	_build_clouds()
	_build_boss_sign(300.0)


func _process(delta: float) -> void:
	_time += delta
	if _clouds:
		_clouds.position.x = sin(_time * 0.02) * 20.0


static func z_of(d: float) -> float:
	return -d


# ------------------------------------------------------------------ lighting
func _build_lighting() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.52, 0.9)
	sky_mat.sky_horizon_color = Color(0.78, 0.86, 0.95)
	sky_mat.ground_horizon_color = Color(0.78, 0.86, 0.95)
	sky_mat.ground_bottom_color = Color(0.35, 0.38, 0.42)
	sky_mat.sun_angle_max = 20.0
	sky_mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.ambient_light_sky_contribution = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.8, 0.86, 0.95)
	env.fog_density = 0.0024
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.2
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, -32, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = enable_shadows
	sun.shadow_blur = 1.2
	sun.shadow_opacity = 0.75
	# one shadow cascade over a short range: a second cascade re-renders the
	# whole street into the shadow map every frame, which phones feel
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_bias = 0.08
	add_child(sun)


# ------------------------------------------------------------------ ground
func _build_ground() -> void:
	var F := MeshFactory
	var length := end_d - start_d
	var mid := z_of((start_d + end_d) * 0.5)
	var st := F.begin()
	# road
	F.box_at(st, Vector3(0, -0.1, mid), Vector3(road_half_width * 2.0, 0.2, length), F.col(Palette.ROAD))
	# sidewalks + curbs
	for side in [-1.0, 1.0]:
		var sx: float = side * (road_half_width + sidewalk_width * 0.5)
		F.box_at(st, Vector3(sx, 0.0, mid), Vector3(sidewalk_width, 0.36, length), F.col(Palette.SIDEWALK))
		F.box_at(st, Vector3(side * (road_half_width + 0.15), 0.02, mid), Vector3(0.3, 0.36, length), F.col(Palette.CURB))
	# far ground plane
	F.box_at(st, Vector3(0, -0.25, mid), Vector3(260, 0.3, length + 400), F.col(Color(0.5, 0.52, 0.5)))
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = F.commit(st)
	mi.material_override = Palette.world_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	# colliders (world layer 1) for knocked runners + debris
	var body := StaticBody3D.new()
	body.name = "GroundCollider"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1.0, length + 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, mid)
	body.add_child(cs)
	for side in [-1.0, 1.0]:
		var cs2 := CollisionShape3D.new()
		var b2 := BoxShape3D.new()
		b2.size = Vector3(sidewalk_width, 0.36, length)
		cs2.shape = b2
		cs2.position = Vector3(side * (road_half_width + sidewalk_width * 0.5), 0.0, mid)
		body.add_child(cs2)
	add_child(body)


func _build_markings() -> void:
	var F := MeshFactory
	var st := F.begin()
	var d := start_d
	while d < end_d:
		# centre dashes: they line up with the gates' centre post (left / right choice)
		F.flat_quad(st, Vector3(0, 0.005, z_of(d)), Vector2(0.22, 2.6), F.col(Palette.ROAD_LINE))
		d += 6.0
	for side in [-1.0, 1.0]:
		F.flat_quad(st, Vector3(side * (road_half_width - 0.3), 0.005, z_of((start_d + end_d) * 0.5)), Vector2(0.18, end_d - start_d), F.col(Palette.ROAD_EDGE))
	# asphalt patches + manholes for texture
	for i in 40:
		var pd := _rng.randf_range(start_d, end_d)
		var px := _rng.randf_range(-5.5, 5.5)
		F.flat_quad(st, Vector3(px, 0.003, z_of(pd)), Vector2(_rng.randf_range(1.5, 3.5), _rng.randf_range(1.5, 4.0)), F.col(Palette.ROAD.darkened(0.12)))
	for i in 12:
		var md := _rng.randf_range(start_d, end_d)
		F.prism(st, F.xform(Vector3(_rng.randf_range(-4.5, 4.5), -0.02, z_of(md))), 0.45, 0.45, 0.03, 10, F.col(Color(0.17, 0.17, 0.19)))
	# checkered start line
	for i in 14:
		for j in 2:
			var c := Color(0.95, 0.95, 0.95) if (i + j) % 2 == 0 else Color(0.12, 0.12, 0.14)
			F.flat_quad(st, Vector3(-6.5 + i * 1.0, 0.006, 3.0 + j * 1.0), Vector2(1.0, 1.0), F.col(c))
	# sidewalk tile seams
	for side in [-1.0, 1.0]:
		var sd := start_d
		while sd < end_d:
			F.box_at(st, Vector3(side * (road_half_width + sidewalk_width * 0.5 + 0.15), 0.185, z_of(sd)), Vector3(sidewalk_width - 0.3, 0.01, 0.06), F.col(Palette.SIDEWALK.darkened(0.12)))
			sd += 3.0
	var mi := MeshInstance3D.new()
	mi.name = "Markings"
	mi.mesh = F.commit(st)
	mi.material_override = Palette.world_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ------------------------------------------------------------------ buildings
func _build_buildings() -> void:
	var meshes: Array[Mesh] = [_apartment_mesh(), _office_mesh(), _shop_mesh(), _warehouse_mesh()]
	var footprints := [Vector2(10, 10), Vector2(11, 11), Vector2(9, 8), Vector2(15, 13)]
	var placements: Array = [[], [], [], []]
	for side in [-1.0, 1.0]:
		var d := start_d
		while d < end_d + 10.0:
			var v := _rng.randi_range(0, 3)
			# more warehouses near the industrial end
			if d > 250.0 and _rng.randf() < 0.35:
				v = 3
			var fp: Vector2 = footprints[v]
			var sy := _rng.randf_range(0.8, 1.3) if v < 2 else _rng.randf_range(0.9, 1.1)
			var x: float = side * (road_half_width + sidewalk_width + 0.4 + fp.x * 0.5)
			var xf := Transform3D(Basis.from_scale(Vector3(1, sy, 1)), Vector3(x, 0.0, z_of(d + fp.y * 0.5)))
			placements[v].append([xf, WALL_TINTS[_rng.randi() % WALL_TINTS.size()]])
			d += fp.y + _rng.randf_range(0.4, 2.2)
	for v in 4:
		_add_multimesh("Buildings%d" % v, meshes[v], placements[v], true)


func _build_skyline() -> void:
	var st := MeshFactory.begin()
	MeshFactory.box_at(st, Vector3(0, 0.5, 0), Vector3(1, 1, 1), MeshFactory.col(Color.WHITE, MeshFactory.TINT))
	var mesh := MeshFactory.commit(st)
	var list: Array = []
	for side in [-1.0, 1.0]:
		var d := start_d - 60.0
		while d < end_d + 200.0:
			var w := _rng.randf_range(10, 22)
			var h := _rng.randf_range(22, 65)
			var x: float = side * _rng.randf_range(34, 70)
			var xf := Transform3D(Basis.from_scale(Vector3(w, h, _rng.randf_range(10, 20))), Vector3(x, 0, z_of(d)))
			var t := _rng.randf_range(0.0, 1.0)
			list.append([xf, Color(0.62, 0.68, 0.8).lerp(Color(0.75, 0.78, 0.85), t)])
			d += w * 0.8
	var mmi := _add_multimesh("Skyline", mesh, list, false)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _apartment_mesh() -> Mesh:
	var F := MeshFactory
	var st := F.begin()
	var w := 10.0
	var h := 18.0
	var tint := F.col(Color.WHITE, F.TINT)
	var trim := F.col(Color(0.85, 0.85, 0.85), F.TINT)
	var glass := F.col(Color(0.36, 0.48, 0.6))
	var lit := F.col(Color(1.0, 0.85, 0.55), 0.5)
	F.box_at(st, Vector3(0, h * 0.5, 0), Vector3(w, h, w), tint)
	F.box_at(st, Vector3(0, h + 0.3, 0), Vector3(w + 0.3, 0.6, w + 0.3), trim)
	F.box_at(st, Vector3(0, 0.6, 0), Vector3(w + 0.2, 1.2, w + 0.2), F.col(Color(0.4, 0.4, 0.44)))
	var floors := 5
	for f in floors:
		var y := 2.8 + f * 3.1
		for i in 4:
			var o := -3.6 + i * 2.4
			var c := lit if _rng.randf() < 0.12 else glass
			for sd in [-1.0, 1.0]:
				F.box_at(st, Vector3(o, y, sd * (w * 0.5 + 0.02)), Vector3(1.3, 1.6, 0.1), c)
				F.box_at(st, Vector3(sd * (w * 0.5 + 0.02), y, o), Vector3(0.1, 1.6, 1.3), c)
			# balconies on road facing sides
			if i % 2 == 0:
				for sd2 in [-1.0, 1.0]:
					F.box_at(st, Vector3(sd2 * (w * 0.5 + 0.45), y - 0.9, o + 1.2), Vector3(0.9, 0.15, 2.2), F.col(Color(0.8, 0.8, 0.82)))
					F.box_at(st, Vector3(sd2 * (w * 0.5 + 0.88), y - 0.45, o + 1.2), Vector3(0.06, 0.8, 2.2), F.col(Color(0.3, 0.32, 0.36)))
	# roof details
	F.prism(st, F.xform(Vector3(2.2, h + 0.6, 2.0)), 1.1, 1.1, 1.8, 8, F.col(Color(0.55, 0.45, 0.38)))
	F.prism(st, F.xform(Vector3(2.2, h + 2.4, 2.0)), 1.2, 0.2, 0.7, 8, F.col(Color(0.45, 0.35, 0.3)))
	F.box_at(st, Vector3(-2.5, h + 1.0, -2.0), Vector3(1.6, 0.9, 1.2), F.col(Color(0.7, 0.72, 0.75)))
	return F.commit(st)


func _office_mesh() -> Mesh:
	var F := MeshFactory
	var st := F.begin()
	var w := 11.0
	var h := 28.0
	var glass := F.col(Color(0.42, 0.6, 0.78))
	var tint := F.col(Color.WHITE, F.TINT)
	F.box_at(st, Vector3(0, h * 0.5, 0), Vector3(w, h, w), glass)
	var k := -w * 0.5
	while k <= w * 0.5 + 0.01:
		for sd in [-1.0, 1.0]:
			F.box_at(st, Vector3(k, h * 0.5, sd * (w * 0.5 + 0.1)), Vector3(0.28, h, 0.25), tint)
			F.box_at(st, Vector3(sd * (w * 0.5 + 0.1), h * 0.5, k), Vector3(0.25, h, 0.28), tint)
		k += 1.83
	var y := 3.5
	while y < h:
		F.box_at(st, Vector3(0, y, 0), Vector3(w + 0.3, 0.35, w + 0.3), tint)
		y += 3.5
	F.box_at(st, Vector3(0, h + 1.0, 0), Vector3(w * 0.6, 2.0, w * 0.6), tint)
	F.box_at(st, Vector3(0, 1.6, 0), Vector3(w + 0.4, 3.2, w + 0.4), F.col(Color(0.25, 0.27, 0.3)))
	F.box_at(st, Vector3(0, h + 2.4, 0), Vector3(0.3, 2.0, 0.3), F.col(Color(1.0, 0.25, 0.2), 0.5))
	return F.commit(st)


func _shop_mesh() -> Mesh:
	var F := MeshFactory
	var st := F.begin()
	var w := 9.0
	var dd := 8.0
	var h := 8.0
	var tint := F.col(Color.WHITE, F.TINT)
	F.box_at(st, Vector3(0, h * 0.5, 0), Vector3(w, h, dd), tint)
	F.box_at(st, Vector3(0, h + 0.25, 0), Vector3(w + 0.3, 0.5, dd + 0.3), F.col(Color(0.9, 0.9, 0.9), F.TINT))
	var awning_cols := [Color(0.95, 0.3, 0.3), Color(0.2, 0.6, 0.9), Color(0.25, 0.75, 0.45), Color(1.0, 0.7, 0.2)]
	var ac: Color = awning_cols[_rng.randi() % awning_cols.size()]
	var sign_col: Color = awning_cols[_rng.randi() % awning_cols.size()]
	for sd in [-1.0, 1.0]:
		# shop window, door, awning stripes, glowing sign
		F.box_at(st, Vector3(sd * (w * 0.5 + 0.03), 1.6, -1.2), Vector3(0.1, 2.4, 4.4), F.col(Color(0.3, 0.42, 0.52)))
		F.box_at(st, Vector3(sd * (w * 0.5 + 0.03), 1.3, 2.4), Vector3(0.1, 2.6, 1.4), F.col(Color(0.35, 0.25, 0.2)))
		for s in 6:
			var c := ac if s % 2 == 0 else Color(0.97, 0.97, 0.95)
			F.box(st, F.xform(Vector3(sd * (w * 0.5 + 0.7), 3.35, -3.4 + s * 1.2), Vector3(0, 0, sd * 0.35)), Vector3(1.4, 0.12, 1.2), F.col(c))
		F.box_at(st, Vector3(sd * (w * 0.5 + 0.12), 4.6, 0), Vector3(0.2, 1.0, 5.0), F.col(sign_col, 0.5))
		for i in 3:
			F.box_at(st, Vector3(sd * (w * 0.5 + 0.02), 6.3, -2.6 + i * 2.6), Vector3(0.1, 1.4, 1.2), F.col(Color(0.36, 0.48, 0.6)))
	for i in 3:
		for sd2 in [-1.0, 1.0]:
			F.box_at(st, Vector3(-2.6 + i * 2.6, 5.0, sd2 * (dd * 0.5 + 0.02)), Vector3(1.4, 1.6, 0.1), F.col(Color(0.36, 0.48, 0.6)))
	F.box_at(st, Vector3(1.5, h + 0.9, 1.0), Vector3(1.8, 0.8, 1.4), F.col(Color(0.72, 0.74, 0.78)))
	return F.commit(st)


func _warehouse_mesh() -> Mesh:
	var F := MeshFactory
	var st := F.begin()
	var w := 15.0
	var dd := 13.0
	var h := 9.0
	var tint := F.col(Color.WHITE, F.TINT)
	var rib := F.col(Color(0.82, 0.82, 0.82), F.TINT)
	F.box_at(st, Vector3(0, h * 0.5, 0), Vector3(w, h, dd), tint)
	var z := -dd * 0.5 + 0.4
	while z < dd * 0.5:
		for sd in [-1.0, 1.0]:
			F.box_at(st, Vector3(sd * (w * 0.5 + 0.06), h * 0.5, z), Vector3(0.12, h, 0.25), rib)
		z += 0.9
	var x := -w * 0.5 + 0.4
	while x < w * 0.5:
		for sd in [-1.0, 1.0]:
			F.box_at(st, Vector3(x, h * 0.5, sd * (dd * 0.5 + 0.06)), Vector3(0.25, h, 0.12), rib)
		x += 0.9
	# pitched roof
	for sd in [-1.0, 1.0]:
		F.box(st, F.xform(Vector3(sd * w * 0.25, h + 0.9, 0), Vector3(0, 0, -sd * 0.23)), Vector3(w * 0.53, 0.3, dd + 0.4), F.col(Color(0.45, 0.47, 0.5)))
	# roll-up doors with hazard stripes, road facing sides
	for sd in [-1.0, 1.0]:
		F.box_at(st, Vector3(sd * (w * 0.5 + 0.1), 2.4, -2.0), Vector3(0.12, 4.8, 4.2), F.col(Color(0.55, 0.57, 0.6)))
		for k in 7:
			var c := Color(1.0, 0.8, 0.1) if k % 2 == 0 else Color(0.12, 0.12, 0.12)
			F.box_at(st, Vector3(sd * (w * 0.5 + 0.14), 4.95, -3.8 + k * 0.6), Vector3(0.1, 0.3, 0.6), F.col(c))
		F.box_at(st, Vector3(sd * (w * 0.5 + 0.1), 6.8, 3.2), Vector3(0.14, 0.6, 3.0), F.col(Color(1.0, 0.95, 0.8), 0.5))
		# pipes along the wall
		F.box_at(st, Vector3(sd * (w * 0.5 + 0.35), 7.6, 0), Vector3(0.35, 0.35, dd), F.col(Color(0.85, 0.45, 0.15)))
	F.prism(st, F.xform(Vector3(3.0, h + 1.2, 2.0)), 0.5, 0.5, 2.5, 8, F.col(Color(0.6, 0.6, 0.62)))
	F.prism(st, F.xform(Vector3(-3.5, h + 1.0, -3.0)), 0.7, 0.4, 1.6, 8, F.col(Color(0.6, 0.6, 0.62)))
	return F.commit(st)


# ------------------------------------------------------------------ street furniture
func _build_streetlights() -> void:
	var F := MeshFactory
	var st := F.begin()
	var metal := F.col(Color(0.3, 0.32, 0.36))
	F.prism(st, F.xform(Vector3.ZERO), 0.16, 0.11, 6.4, 6, metal)
	F.box_at(st, Vector3(0.0, 0.2, 0), Vector3(0.5, 0.4, 0.5), metal)
	F.box(st, F.xform(Vector3(0.9, 6.35, 0), Vector3(0, 0, -0.12)), Vector3(1.9, 0.12, 0.14), metal)
	F.box_at(st, Vector3(1.75, 6.25, 0), Vector3(0.8, 0.22, 0.4), metal)
	F.box_at(st, Vector3(1.75, 6.12, 0), Vector3(0.66, 0.06, 0.3), F.col(Color(1.0, 0.95, 0.8), 0.5))
	var mesh := F.commit(st)
	var list: Array = []
	var d := start_d + 5.0
	var i := 0
	while d < end_d:
		for side in [-1.0, 1.0]:
			var basis := Basis() if side < 0 else Basis(Vector3.UP, PI)
			list.append([Transform3D(basis, Vector3(side * (road_half_width + 0.7), 0.18, z_of(d + (13.0 if side > 0 else 0.0)))), Color.WHITE])
		d += 26.0
		i += 1
	_add_multimesh("Streetlights", mesh, list, false)


func _build_props() -> void:
	var F := MeshFactory
	# --- parked cars (tinted body)
	var st := F.begin()
	var body := F.col(Color.WHITE, F.TINT)
	var glass := F.col(Color(0.2, 0.28, 0.36))
	var black := F.col(Color(0.1, 0.1, 0.11))
	F.box_at(st, Vector3(0, 0.62, 0), Vector3(1.9, 0.7, 4.2), body)
	F.box(st, F.xform(Vector3(0, 1.25, 0.2)), Vector3(1.7, 0.6, 2.3), body, Vector2(0.85, 0.8))
	F.box(st, F.xform(Vector3(0, 1.25, 0.2)), Vector3(1.74, 0.46, 2.1), glass, Vector2(0.85, 0.8))
	for wx in [-0.9, 0.9]:
		for wz in [-1.35, 1.35]:
			F.prism(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(wx - 0.14, 0.36, wz)), 0.36, 0.36, 0.28, 8, black)
	F.box_at(st, Vector3(0.6, 0.7, -2.11), Vector3(0.35, 0.18, 0.05), F.col(Color(1, 0.97, 0.85), 0.5))
	F.box_at(st, Vector3(-0.6, 0.7, -2.11), Vector3(0.35, 0.18, 0.05), F.col(Color(1, 0.97, 0.85), 0.5))
	F.box_at(st, Vector3(0.6, 0.7, 2.11), Vector3(0.35, 0.15, 0.05), F.col(Color(0.9, 0.1, 0.1), 0.5))
	F.box_at(st, Vector3(-0.6, 0.7, 2.11), Vector3(0.35, 0.15, 0.05), F.col(Color(0.9, 0.1, 0.1), 0.5))
	var car_mesh := F.commit(st)
	var cars: Array = []
	var d := start_d + 12.0
	while d < end_d - 10.0:
		if _rng.randf() < 0.55:
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			var yaw := _rng.randf_range(-0.05, 0.05) + (PI if _rng.randf() < 0.5 else 0.0)
			cars.append([Transform3D(Basis(Vector3.UP, yaw), Vector3(side * (road_half_width + 2.6), 0.18, z_of(d))), CAR_TINTS[_rng.randi() % CAR_TINTS.size()]])
		d += _rng.randf_range(14.0, 26.0)
	_add_multimesh("ParkedCars", car_mesh, cars, true)

	# --- small props: cones, crates, jersey barriers, bins, pipe stacks
	var cone := F.begin()
	F.box_at(cone, Vector3(0, 0.04, 0), Vector3(0.55, 0.08, 0.55), F.col(Color(0.15, 0.15, 0.15)))
	F.prism(cone, F.xform(Vector3(0, 0.08, 0)), 0.22, 0.05, 0.7, 8, F.col(Color(1.0, 0.42, 0.08)))
	F.prism(cone, F.xform(Vector3(0, 0.38, 0)), 0.14, 0.11, 0.12, 8, F.col(Color(0.97, 0.97, 0.97)))
	var crate := F.begin()
	F.box_at(crate, Vector3(0, 0.45, 0), Vector3(0.9, 0.9, 0.9), F.col(Color(0.72, 0.52, 0.3)))
	F.box_at(crate, Vector3(0.1, 1.2, 0.05), Vector3(0.7, 0.6, 0.7), F.col(Color(0.62, 0.44, 0.26)))
	var jersey := F.begin()
	F.box(jersey, F.xform(Vector3(0, 0.45, 0)), Vector3(0.7, 0.9, 2.4), F.col(Color(0.82, 0.8, 0.76)), Vector2(0.45, 1.0))
	F.box_at(jersey, Vector3(0, 0.7, 0), Vector3(0.52, 0.18, 2.42), F.col(Color(0.9, 0.2, 0.2)))
	var bin := F.begin()
	F.prism(bin, F.xform(Vector3.ZERO), 0.3, 0.33, 0.9, 8, F.col(Color(0.2, 0.5, 0.35)))
	F.prism(bin, F.xform(Vector3(0, 0.9, 0)), 0.36, 0.3, 0.1, 8, F.col(Color(0.15, 0.35, 0.25)))
	var pipes := F.begin()
	for k in 3:
		var px := -0.45 + k * 0.45
		F.prism(pipes, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(px, 0.22, -1.8)), 0.22, 0.22, 3.6, 8, F.col(Color(0.85, 0.45, 0.15)))
	F.prism(pipes, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.22, 0.6, -1.8)), 0.22, 0.22, 3.6, 8, F.col(Color(0.6, 0.62, 0.66)))
	F.prism(pipes, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.22, 0.6, -1.8)), 0.22, 0.22, 3.6, 8, F.col(Color(0.6, 0.62, 0.66)))
	var kinds: Array[Mesh] = [F.commit(cone), F.commit(crate), F.commit(jersey), F.commit(bin), F.commit(pipes)]
	var lists: Array = [[], [], [], [], []]
	d = start_d + 6.0
	while d < end_d:
		var side2 := -1.0 if _rng.randf() < 0.5 else 1.0
		var k2 := _rng.randi_range(0, 4)
		var x := side2 * (road_half_width + _rng.randf_range(1.2, 3.8))
		var n := 1 if k2 >= 2 else _rng.randi_range(1, 3)
		for j in n:
			lists[k2].append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU if k2 < 2 or k2 == 3 else 0.0), Vector3(x + j * 0.7 * -side2, 0.18, z_of(d + j * 0.6))), Color.WHITE])
		d += _rng.randf_range(5.0, 11.0)
	for k3 in kinds.size():
		_add_multimesh("Props%d" % k3, kinds[k3], lists[k3], false)


func _build_clouds() -> void:
	var st := MeshFactory.begin()
	MeshFactory.sphere(st, MeshFactory.xform(Vector3.ZERO), Vector3(1, 0.45, 0.8), 4, 7, MeshFactory.col(Color(1, 1, 1)))
	MeshFactory.sphere(st, MeshFactory.xform(Vector3(0.9, 0.1, 0.1)), Vector3(0.7, 0.4, 0.6), 3, 6, MeshFactory.col(Color(0.96, 0.97, 1)))
	MeshFactory.sphere(st, MeshFactory.xform(Vector3(-0.8, 0.05, -0.1)), Vector3(0.6, 0.35, 0.55), 3, 6, MeshFactory.col(Color(0.96, 0.97, 1)))
	var mesh := MeshFactory.commit(st)
	var list: Array = []
	for i in 16:
		var s := _rng.randf_range(12, 26)
		var xf := Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(_rng.randf_range(-160, 160), _rng.randf_range(75, 110), z_of(_rng.randf_range(start_d - 100, end_d + 250))))
		list.append([xf, Color.WHITE])
	_clouds = _add_multimesh("Clouds", mesh, list, false)
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Overhead gantry: "BOSS AHEAD" - builds anticipation before the arena.
func _build_boss_sign(d: float) -> void:
	var F := MeshFactory
	var st := F.begin()
	var metal := F.col(Color(0.3, 0.32, 0.36))
	for side in [-1.0, 1.0]:
		F.box_at(st, Vector3(side * 7.6, 4.8, 0), Vector3(0.35, 9.6, 0.35), metal)
	F.box_at(st, Vector3(0, 9.4, 0), Vector3(15.6, 0.4, 0.5), metal)
	F.box_at(st, Vector3(0, 8.3, 0), Vector3(6.4, 1.8, 0.2), F.col(Color(0.75, 0.1, 0.1)))
	F.box_at(st, Vector3(0, 8.3, 0.08), Vector3(6.1, 1.5, 0.1), F.col(Color(0.95, 0.2, 0.15), 0.5))
	var mi := MeshInstance3D.new()
	mi.mesh = F.commit(st)
	mi.material_override = Palette.world_material()
	mi.position = Vector3(0, 0, z_of(d))
	add_child(mi)
	var l := Label3D.new()
	l.text = "BOSS AHEAD"
	l.font = Palette.font()
	l.font_size = 120
	l.pixel_size = 0.01
	l.outline_size = 20
	l.outline_modulate = Color(0.3, 0.02, 0.02)
	l.position = Vector3(0, 8.3, z_of(d) + 0.2)
	add_child(l)


# ------------------------------------------------------------------ helpers
## placements: Array of [Transform3D, Color tint]
func _add_multimesh(n: String, mesh: Mesh, placements: Array, tinted: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = placements.size()
	for i in placements.size():
		mm.set_instance_transform(i, placements[i][0])
		var c: Color = placements[i][1]
		mm.set_instance_custom_data(i, c)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	mmi.material_override = Palette.world_material(true)
	add_child(mmi)
	return mmi
