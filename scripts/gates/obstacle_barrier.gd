class_name ObstacleBarrier
extends Node3D
## A row of construction barricades across the road (+ cones and crates).
## Pieces are frozen RigidBody3D until the crowd hits: the ones in the crowd's
## path are unfrozen and kicked forward (lightweight scripted destruction),
## the rest shake. After a few seconds everything is frozen again so the
## physics cost drops back to zero. Max ~12 dynamic bodies.

signal smashed

const LAYER_WORLD := 1
const LAYER_PROPS := 2
const LAYER_ACTORS := 4
const SEGMENTS := 6
const SEG_WIDTH := 2.3

var is_smashed := false
var _segments: Array[RigidBody3D] = []
var _props: Array[RigidBody3D] = []


func _ready() -> void:
	_build()


func smash(crowd_x: float, crowd_half_width: float) -> void:
	if is_smashed:
		return
	is_smashed = true
	var lo := crowd_x - crowd_half_width - 0.8
	var hi := crowd_x + crowd_half_width + 0.8
	for seg in _segments:
		var x := seg.global_position.x
		if x + SEG_WIDTH * 0.5 > lo and x - SEG_WIDTH * 0.5 < hi:
			_kick(seg, Vector3(randf_range(-2.0, 2.0) + (x - crowd_x) * 0.8, randf_range(4.5, 7.0), -randf_range(7.0, 11.0)), 6.0)
		else:
			var tw := create_tween()
			var r0 := seg.rotation
			tw.tween_property(seg, "rotation:z", r0.z + 0.12, 0.06)
			tw.tween_property(seg, "rotation:z", r0.z - 0.08, 0.08)
			tw.tween_property(seg, "rotation:z", r0.z, 0.2).set_trans(Tween.TRANS_ELASTIC)
	for p in _props:
		if absf(p.global_position.x - crowd_x) < crowd_half_width + 2.5:
			_kick(p, Vector3(randf_range(-3, 3), randf_range(3, 6), -randf_range(5, 9)), 8.0)
	smashed.emit()
	get_tree().create_timer(4.0).timeout.connect(_settle)


func _kick(body: RigidBody3D, vel: Vector3, spin: float) -> void:
	body.freeze = false
	body.sleeping = false
	body.linear_velocity = vel
	body.angular_velocity = Vector3(randf_range(-spin, spin), randf_range(-spin, spin) * 0.5, randf_range(-spin, spin))


func _settle() -> void:
	for b in _segments + _props:
		if is_instance_valid(b):
			b.freeze = true


func _build() -> void:
	var F := MeshFactory
	# ---- barricade segment mesh (A-frame legs, striped planks, amber lamp)
	var st := F.begin()
	var wood := F.col(Color(0.55, 0.38, 0.22))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			F.box(st, F.xform(Vector3(sx * 0.95, 0.55, sz * 0.18), Vector3(sz * 0.3, 0, 0)), Vector3(0.12, 1.15, 0.12), wood)
	for row in 2:
		var y := 0.55 + row * 0.42
		var stripes := 7
		for k in stripes:
			var c := Color(0.95, 0.35, 0.12) if k % 2 == 0 else Color(0.97, 0.97, 0.95)
			var w := SEG_WIDTH / stripes
			F.box_at(st, Vector3(-SEG_WIDTH * 0.5 + w * (k + 0.5), y, -0.02), Vector3(w + 0.001, 0.26, 0.1), F.col(c))
	F.box_at(st, Vector3(0.8, 1.2, 0), Vector3(0.18, 0.12, 0.12), F.col(Color(0.2, 0.2, 0.2)))
	F.sphere(st, F.xform(Vector3(0.8, 1.33, 0)), Vector3(0.11, 0.11, 0.11), 3, 6, F.col(Color(1.0, 0.7, 0.1), 0.5))
	var seg_mesh := F.commit(st)

	var start_x := -SEG_WIDTH * (SEGMENTS - 1) * 0.5
	for i in SEGMENTS:
		var body := _make_body(seg_mesh, Vector3(SEG_WIDTH * 0.98, 1.2, 0.5), Vector3(0, 0.6, 0), 12.0)
		body.position = Vector3(start_x + i * SEG_WIDTH, 0, 0)
		body.rotation.y = randf_range(-0.05, 0.05)
		_segments.append(body)

	# ---- traffic cones in front
	st = F.begin()
	F.box_at(st, Vector3(0, 0.04, 0), Vector3(0.55, 0.08, 0.55), F.col(Color(0.15, 0.15, 0.15)))
	F.prism(st, F.xform(Vector3(0, 0.08, 0)), 0.22, 0.05, 0.7, 8, F.col(Color(1.0, 0.42, 0.08)))
	F.prism(st, F.xform(Vector3(0, 0.38, 0)), 0.14, 0.11, 0.12, 8, F.col(Color(0.97, 0.97, 0.97)))
	var cone_mesh := F.commit(st)
	for x in [-5.2, -1.6, 1.9, 5.4]:
		var cone := _make_body(cone_mesh, Vector3(0.45, 0.8, 0.45), Vector3(0, 0.4, 0), 2.0)
		cone.position = Vector3(x, 0, 2.2)
		_props.append(cone)

	# ---- a couple of crates
	st = F.begin()
	F.box_at(st, Vector3(0, 0.4, 0), Vector3(0.8, 0.8, 0.8), F.col(Color(0.72, 0.52, 0.3)))
	for k in 3:
		F.box_at(st, Vector3(0, 0.12 + k * 0.28, -0.41), Vector3(0.82, 0.07, 0.03), F.col(Color(0.5, 0.34, 0.18)))
	var crate_mesh := F.commit(st)
	for x in [-6.0, 6.1]:
		var crate := _make_body(crate_mesh, Vector3(0.8, 0.8, 0.8), Vector3(0, 0.4, 0), 6.0)
		crate.position = Vector3(x, 0, -0.9)
		_props.append(crate)


func _make_body(mesh: Mesh, size: Vector3, offset: Vector3, mass_kg: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.mass = mass_kg
	body.gravity_scale = 1.8
	body.collision_layer = LAYER_PROPS
	body.collision_mask = LAYER_WORLD | LAYER_PROPS | LAYER_ACTORS
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = offset
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Palette.world_material()
	body.add_child(mi)
	add_child(body)
	return body
