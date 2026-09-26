class_name BossArena
extends Node3D
## Final plaza: wider concrete floor, red target rings around the boss spot,
## hazard border, container stacks, floodlight towers, swaying banners and a
## big industrial gate that closes the level. Node origin = arena entrance,
## boss stands `boss_offset` further down the road (-Z).

@export var boss_offset := 37.0
@export var length := 90.0
@export var half_width := 17.0

var _banners: Array[Node3D] = []
var _time := 0.0


func _ready() -> void:
	_build()


func boss_spot() -> Vector3:
	return global_position + Vector3(0, 0, -boss_offset)


func _process(delta: float) -> void:
	_time += delta
	for i in _banners.size():
		_banners[i].rotation.z = sin(_time * 1.7 + i * 0.9) * 0.06
		_banners[i].rotation.x = sin(_time * 1.3 + i * 1.7) * 0.05


func _build() -> void:
	var F := MeshFactory
	var st := F.begin()
	var mid_z := -length * 0.5
	# floor
	F.box_at(st, Vector3(0, -0.1, mid_z), Vector3(half_width * 2.0, 0.2, length), F.col(Color(0.5, 0.5, 0.53)))
	# tiles
	var z := 0.0
	while z > -length:
		F.flat_quad(st, Vector3(0, 0.004, z), Vector2(half_width * 2.0, 0.08), F.col(Color(0.43, 0.43, 0.46)))
		z -= 4.0
	# hazard entrance line
	for k in 17:
		var c := Color(1.0, 0.8, 0.1) if k % 2 == 0 else Color(0.12, 0.12, 0.12)
		F.flat_quad(st, Vector3(-half_width + 1.0 + k * 2.0, 0.006, -0.5), Vector2(2.0, 1.0), F.col(c))
	# red target rings around the boss spot
	var bz := -boss_offset
	for ring in [[9.0, 8.4], [5.2, 4.8]]:
		var segs := 40
		for s in segs:
			var a0 := TAU * s / segs
			var a1 := TAU * (s + 1) / segs
			var r0: float = ring[1]
			var r1: float = ring[0]
			var p0 := Vector3(cos(a0) * r0, 0.007, bz + sin(a0) * r0)
			var p1 := Vector3(cos(a1) * r0, 0.007, bz + sin(a1) * r0)
			var p2 := Vector3(cos(a1) * r1, 0.007, bz + sin(a1) * r1)
			var p3 := Vector3(cos(a0) * r1, 0.007, bz + sin(a0) * r1)
			F.quad(st, p0, p1, p2, p3, F.col(Color(0.85, 0.18, 0.15)), Vector3(0, -1, bz))
	# side walls of jersey barriers
	for side in [-1.0, 1.0]:
		var zz := -2.0
		while zz > -length + 4.0:
			F.box(st, F.xform(Vector3(side * (half_width - 0.5), 0.5, zz)), Vector3(0.8, 1.0, 2.6), F.col(Color(0.82, 0.8, 0.76)), Vector2(0.45, 1.0))
			F.box_at(st, Vector3(side * (half_width - 0.5), 0.75, zz), Vector3(0.58, 0.2, 2.62), F.col(Color(0.9, 0.2, 0.2)))
			zz -= 2.8
	# container stacks
	var ccols := [Color(0.85, 0.3, 0.2), Color(0.2, 0.45, 0.75), Color(0.95, 0.65, 0.15), Color(0.3, 0.6, 0.4)]
	var ci := 0
	for side in [-1.0, 1.0]:
		for i in 3:
			var cz := -14.0 - i * 18.0
			for lvl in (2 if i != 1 else 3):
				var cc: Color = ccols[ci % ccols.size()]
				ci += 1
				var cx: float = side * (half_width + 3.5)
				F.box_at(st, Vector3(cx, 1.3 + lvl * 2.6, cz), Vector3(5.0, 2.6, 12.0), F.col(cc))
				var r := -5.6
				while r < 5.8:
					F.box_at(st, Vector3(cx - side * 2.52, 1.3 + lvl * 2.6, cz + r), Vector3(0.06, 2.4, 0.18), F.col(cc.darkened(0.25)))
					r += 0.8
	# the end gate / wall
	var wz := -length + 2.0
	F.box_at(st, Vector3(0, 8.0, wz), Vector3(half_width * 2.0 + 10.0, 16.0, 2.0), F.col(Color(0.28, 0.3, 0.35)))
	F.box_at(st, Vector3(0, 5.0, wz + 1.05), Vector3(14.0, 10.0, 0.2), F.col(Color(0.2, 0.21, 0.25)))
	for k in 10:
		var c2 := Color(1.0, 0.8, 0.1) if k % 2 == 0 else Color(0.12, 0.12, 0.12)
		F.box(st, F.xform(Vector3(-6.3 + k * 1.4, 10.4, wz + 1.2), Vector3(0, 0, 0.6)), Vector3(0.7, 1.4, 0.1), F.col(c2))
	F.box_at(st, Vector3(0, 13.3, wz + 1.1), Vector3(20.0, 1.2, 0.3), F.col(Color(1.0, 0.2, 0.15), 0.5))
	for side in [-1.0, 1.0]:
		F.box_at(st, Vector3(side * 10.0, 11.0, wz + 0.5), Vector3(4.0, 22.0, 4.0), F.col(Color(0.34, 0.36, 0.42)))
		F.box_at(st, Vector3(side * 10.0, 22.4, wz + 0.5), Vector3(4.6, 0.8, 4.6), F.col(Color(0.96, 0.46, 0.1)))
	# floodlight towers
	for p in [Vector3(-14, 0, -8), Vector3(14, 0, -8), Vector3(-14, 0, -60), Vector3(14, 0, -60)]:
		F.box_at(st, p + Vector3(0, 6.0, 0), Vector3(0.5, 12.0, 0.5), F.col(Color(0.3, 0.32, 0.36)))
		F.box_at(st, p + Vector3(0, 12.3, 0), Vector3(2.6, 1.3, 0.5), F.col(Color(0.25, 0.26, 0.3)))
		F.box_at(st, p + Vector3(0, 12.3, 0.26), Vector3(2.3, 1.0, 0.06), F.col(Color(1.0, 0.97, 0.85), 0.5))
		F.box_at(st, p + Vector3(0, 12.3, -0.26), Vector3(2.3, 1.0, 0.06), F.col(Color(1.0, 0.97, 0.85), 0.5))
	var mi := MeshInstance3D.new()
	mi.name = "ArenaMesh"
	mi.mesh = F.commit(st)
	mi.material_override = Palette.world_material()
	add_child(mi)

	# banners (swaying = subtle environment motion)
	var bst := F.begin()
	F.box_at(bst, Vector3(0, -2.0, 0), Vector3(1.6, 4.0, 0.08), F.col(Color(0.85, 0.12, 0.12)))
	F.box_at(bst, Vector3(0, -2.0, 0.05), Vector3(0.9, 0.9, 0.04), F.col(Color(1.0, 0.8, 0.1)))
	F.box_at(bst, Vector3(0, 0.05, 0), Vector3(1.9, 0.12, 0.14), F.col(Color(0.2, 0.2, 0.22)))
	var bmesh := F.commit(bst)
	for side in [-1.0, 1.0]:
		for i in 3:
			var b := MeshInstance3D.new()
			b.mesh = bmesh
			b.material_override = Palette.world_material()
			b.position = Vector3(side * (half_width + 0.9), 9.5, -10.0 - i * 20.0)
			b.rotation.y = side * PI * 0.5
			add_child(b)
			_banners.append(b)

	# colliders: floor + walls
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(half_width * 2.0 + 20.0, 1.0, length)
	cs.shape = box
	cs.position = Vector3(0, -0.5, mid_z)
	body.add_child(cs)
	for side in [-1.0, 1.0]:
		var cw := CollisionShape3D.new()
		var bw := BoxShape3D.new()
		bw.size = Vector3(0.8, 2.0, length)
		cw.shape = bw
		cw.position = Vector3(side * (half_width - 0.5), 1.0, mid_z)
		body.add_child(cw)
	add_child(body)
