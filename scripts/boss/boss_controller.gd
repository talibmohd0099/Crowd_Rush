class_name BossController
extends Node3D
## GIANT GUARD - a ~6.5 unit tall low-poly armoured brute with a huge hammer.
## Built procedurally from pivots; all animation is tweened pose parameters
## layered on a procedural idle (breathing / sway). Scale sells the threat.

signal footstep(pos: Vector3)
signal roared
signal slammed(pos: Vector3)
signal entrance_finished
signal swing_started
signal swing_hit(origin: Vector3, reach: float)
signal damaged(hp: float, max_hp: float)
signal defeated

enum State { DORMANT, ENTRANCE, IDLE, ATTACKING, DEFEATED }

@export var max_hp := 100.0
@export var attack_interval := 2.4
@export var reach := 6.5

var hp := 100.0
var state: State = State.DORMANT
var crowd_focus := Vector3.ZERO

# pose parameters (tweened)
var p_arm_r := 0.35
var p_arm_r_z := 0.15
var p_arm_l := 0.1
var p_arm_l_z := -0.2
var p_torso_pitch := 0.0
var p_torso_yaw := 0.0
var p_head_yaw := 0.0
var p_head_pitch := 0.0
var p_leg_l := 0.0
var p_leg_r := 0.0
var p_lift := 0.0
var p_fall := 0.0
var p_visor := 1.0

var _time := 0.0
var _attack_timer := 0.0
var _flash := 0.0
var _mat: ShaderMaterial
var _body: Node3D
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _hammer: Node3D
var _telegraph: MeshInstance3D
var _telegraph_mat: StandardMaterial3D
var _collider: StaticBody3D
var _tw: Tween


func _ready() -> void:
	hp = max_hp
	_build()


# ------------------------------------------------------------------ public
## World position of the hammer head (for dust / impacts).
func hammer_head_position() -> Vector3:
	return _hammer.global_transform * Vector3(0, -1.5, -2.6)


func front_position(dist := 3.0) -> Vector3:
	return global_position + global_transform.basis.z * -dist


func play_entrance() -> void:
	state = State.ENTRANCE
	var fwd := -global_transform.basis.z
	var tw := create_tween()
	_tw = tw
	tw.tween_interval(0.25)
	# two heavy steps forward
	for i in 2:
		var leg := "p_leg_l" if i == 0 else "p_leg_r"
		tw.tween_property(self, leg, 0.45, 0.22).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(self, "p_lift", 0.25, 0.22)
		tw.parallel().tween_property(self, "global_position", global_position + fwd * (1.4 * (i + 1)), 0.44).set_trans(Tween.TRANS_SINE)
		tw.tween_property(self, leg, 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(self, "p_lift", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void: footstep.emit(global_position + fwd * 1.0))
		tw.tween_interval(0.1)
	# look toward the crowd, roar
	tw.tween_callback(func() -> void:
		var to := crowd_focus - global_position
		var local := global_transform.basis.inverse() * to
		var yaw := clampf(atan2(-local.x, -local.z), -0.6, 0.6)
		var tw2 := create_tween()
		tw2.tween_property(self, "p_head_yaw", yaw, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.parallel().tween_property(self, "p_head_pitch", 0.25, 0.3))
	tw.tween_interval(0.3)
	tw.tween_callback(func() -> void: roared.emit())
	tw.tween_property(self, "p_visor", 3.5, 0.15)
	tw.parallel().tween_property(self, "p_torso_pitch", 0.15, 0.3)
	tw.tween_interval(0.45)
	tw.tween_property(self, "p_visor", 1.4, 0.4)
	tw.parallel().tween_property(self, "p_head_yaw", 0.0, 0.4)
	# raise the hammer (anticipation) ...
	tw.parallel().tween_property(self, "p_arm_r", 2.9, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "p_torso_pitch", 0.22, 0.6)
	tw.parallel().tween_property(self, "p_arm_l", 0.6, 0.6)
	tw.tween_interval(0.18)
	# ... SLAM
	tw.tween_property(self, "p_arm_r", 0.05, 0.17).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "p_torso_pitch", -0.32, 0.17).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "p_head_pitch", 0.35, 0.17)
	tw.tween_callback(func() -> void: slammed.emit(hammer_head_position()))
	tw.tween_interval(0.55)
	tw.tween_property(self, "p_arm_r", 0.35, 0.5).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(self, "p_torso_pitch", 0.0, 0.5)
	tw.parallel().tween_property(self, "p_head_pitch", 0.1, 0.5)
	tw.parallel().tween_property(self, "p_arm_l", 0.1, 0.5)
	tw.tween_callback(func() -> void:
		state = State.IDLE
		entrance_finished.emit())


func start_fight() -> void:
	state = State.IDLE
	_attack_timer = 1.1


func take_damage(amount: float) -> void:
	if state == State.DEFEATED or amount <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	_flash = minf(1.0, _flash + 0.35)
	damaged.emit(hp, max_hp)
	if hp <= 0.0:
		_defeat()


# ------------------------------------------------------------------ attack
func _process(delta: float) -> void:
	_time += delta
	_flash = move_toward(_flash, 0.0, delta * 3.5)
	_mat.set_shader_parameter("flash", _flash * 0.55)
	_mat.set_shader_parameter("emission_boost", (p_visor - 1.0) * 1.5)
	if state == State.IDLE:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack()
	_apply_pose()


func _attack() -> void:
	state = State.ATTACKING
	swing_started.emit()
	_telegraph.visible = true
	_telegraph_mat.albedo_color.a = 0.0
	var tw := create_tween()
	_tw = tw
	# wind-up: twist away, hammer back, telegraph arc fades in
	tw.tween_property(self, "p_torso_yaw", -1.15, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "p_arm_r", 1.25, 0.55)
	tw.parallel().tween_property(self, "p_arm_r_z", 0.9, 0.55)
	tw.parallel().tween_property(_telegraph_mat, "albedo_color:a", 0.45, 0.5)
	tw.tween_interval(0.12)
	# the sweep
	tw.tween_property(self, "p_torso_yaw", 1.2, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(self, "p_arm_r", 0.45, 0.3)
	tw.parallel().tween_callback(func() -> void: swing_hit.emit(front_position(3.2), reach)).set_delay(0.14)
	tw.parallel().tween_property(_telegraph_mat, "albedo_color:a", 0.0, 0.25).set_delay(0.1)
	tw.tween_interval(0.25)
	# recover
	tw.tween_property(self, "p_torso_yaw", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(self, "p_arm_r", 0.35, 0.5)
	tw.parallel().tween_property(self, "p_arm_r_z", 0.15, 0.5)
	tw.tween_callback(func() -> void:
		_telegraph.visible = false
		if state == State.ATTACKING:
			state = State.IDLE
			_attack_timer = attack_interval)


func _defeat() -> void:
	state = State.DEFEATED
	_telegraph.visible = false
	if _tw and _tw.is_valid():
		_tw.kill()
	var back := global_transform.basis.z
	var tw := create_tween()
	# stagger
	tw.tween_property(self, "p_head_pitch", -0.5, 0.18)
	tw.parallel().tween_property(self, "p_torso_pitch", 0.35, 0.18)
	tw.parallel().tween_property(self, "p_arm_r", 1.6, 0.18)
	tw.parallel().tween_property(self, "p_visor", 0.2, 0.6)
	tw.tween_property(self, "global_position", global_position + back * 1.2, 0.35).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(self, "p_leg_l", -0.35, 0.35)
	tw.tween_callback(_drop_hammer)
	tw.tween_property(self, "p_torso_yaw", 0.4, 0.3)
	tw.parallel().tween_property(self, "p_arm_l", 1.2, 0.3)
	tw.parallel().tween_property(self, "p_arm_r", 2.2, 0.3)
	# collapse backwards
	tw.tween_property(self, "p_fall", 1.48, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "p_leg_l", 0.4, 0.8)
	tw.parallel().tween_property(self, "p_leg_r", 0.2, 0.8)
	tw.tween_callback(func() -> void:
		slammed.emit(global_position + back * 3.5)
		defeated.emit())
	tw.tween_property(self, "p_fall", 1.38, 0.15)
	tw.tween_property(self, "p_fall", 1.48, 0.2)


func _drop_hammer() -> void:
	var xf := _hammer.global_transform
	var body := RigidBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1 | 2
	body.mass = 40.0
	body.gravity_scale = 1.8
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.4, 1.1, 3.8)
	cs.shape = shape
	cs.position = Vector3(0, -1.0, -1.6)
	body.add_child(cs)
	_hammer.get_parent().remove_child(_hammer)
	body.add_child(_hammer)
	_hammer.transform = Transform3D.IDENTITY
	get_parent().add_child(body)
	body.global_transform = xf
	body.linear_velocity = Vector3(randf_range(-2, 2), 2.0, 3.0)
	body.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-3, 3))


# ------------------------------------------------------------------ pose
func _apply_pose() -> void:
	var breath := sin(_time * 1.8) if state != State.DEFEATED else 0.0
	var sway := sin(_time * 0.9) * 0.03 if state != State.DEFEATED else 0.0
	_body.rotation = Vector3(p_fall, 0, 0)
	_hips.position = Vector3(0, 2.7 + p_lift + breath * 0.03, 0)
	_torso.rotation = Vector3(-p_torso_pitch + breath * 0.02, p_torso_yaw + sway, sway * 0.5)
	_torso.scale = Vector3(1.0 + breath * 0.012, 1.0, 1.0 + breath * 0.012)
	_head.rotation = Vector3(-p_head_pitch + breath * 0.02, p_head_yaw, 0)
	_arm_r.rotation = Vector3(p_arm_r + breath * 0.03, 0, p_arm_r_z)
	_arm_l.rotation = Vector3(p_arm_l - breath * 0.03, 0, p_arm_l_z)
	_leg_l.rotation = Vector3(p_leg_l, 0, -0.04)
	_leg_r.rotation = Vector3(p_leg_r, 0, 0.04)


# ------------------------------------------------------------------ build
func _build() -> void:
	_mat = Palette.world_material().duplicate()
	var F := MeshFactory
	var steel := F.col(Color(0.34, 0.36, 0.43))
	var steel_dk := F.col(Color(0.2, 0.21, 0.26))
	var accent := F.col(Color(0.96, 0.46, 0.1))
	var visor := F.col(Color(1.0, 0.18, 0.12), 0.5)
	var hazard_y := F.col(Color(1.0, 0.8, 0.12))
	var hazard_k := F.col(Color(0.1, 0.1, 0.1))

	_body = _pivot(self, "Body", Vector3.ZERO)
	_hips = _pivot(_body, "Hips", Vector3(0, 2.7, 0))

	# legs
	for side in [-1, 1]:
		var leg := _pivot(_hips, "LegL" if side < 0 else "LegR", Vector3(0.72 * side, 0, 0))
		var st := F.begin()
		F.box(st, F.xform(Vector3(0, -0.6, 0)), Vector3(0.8, 1.35, 0.85), steel, Vector2(1.15, 1.1))
		F.box_at(st, Vector3(0, -1.3, -0.1), Vector3(0.85, 0.4, 0.7), accent)
		F.box(st, F.xform(Vector3(0, -1.85, 0)), Vector3(0.72, 1.0, 0.78), steel_dk, Vector2(1.15, 1.1))
		F.box(st, F.xform(Vector3(0, -2.5, -0.2)), Vector3(1.0, 0.42, 1.45), steel_dk, Vector2(0.85, 0.8))
		_mesh(leg, st)
		if side < 0:
			_leg_l = leg
		else:
			_leg_r = leg

	# torso
	_torso = _pivot(_hips, "Torso", Vector3.ZERO)
	var st2 := F.begin()
	F.box_at(st2, Vector3(0, 0.1, 0), Vector3(1.8, 0.6, 1.15), steel_dk)
	F.box(st2, F.xform(Vector3(0, 1.45, 0)), Vector3(2.0, 2.1, 1.25), steel, Vector2(1.55, 1.35))
	F.box(st2, F.xform(Vector3(0, 1.6, -0.72)), Vector3(1.9, 1.3, 0.2), accent, Vector2(1.2, 1.0))
	F.box_at(st2, Vector3(0, 1.6, -0.84), Vector3(0.7, 0.7, 0.1), visor)
	for sx in [-1.0, 1.0]:
		F.box(st2, F.xform(Vector3(1.72 * sx, 2.45, 0)), Vector3(1.15, 0.75, 1.4), accent, Vector2(0.8, 0.85))
		F.box_at(st2, Vector3(1.72 * sx, 2.1, 0), Vector3(1.2, 0.12, 1.45), steel_dk)
	# back tanks / exhaust for silhouette
	F.prism(st2, F.xform(Vector3(-0.5, 1.8, 0.9)), 0.28, 0.28, 1.1, 6, steel_dk)
	F.prism(st2, F.xform(Vector3(0.5, 1.8, 0.9)), 0.28, 0.28, 1.1, 6, steel_dk)
	_mesh(_torso, st2)

	# head
	_head = _pivot(_torso, "Head", Vector3(0, 2.55, -0.1))
	var st3 := F.begin()
	F.box(st3, F.xform(Vector3(0, 0.5, 0)), Vector3(1.15, 1.05, 1.15), steel, Vector2(0.85, 0.85))
	F.box_at(st3, Vector3(0, 0.56, -0.56), Vector3(0.95, 0.2, 0.12), visor)
	F.box(st3, F.xform(Vector3(0, 0.12, -0.45)), Vector3(0.95, 0.3, 0.35), steel_dk, Vector2(0.8, 1.0))
	F.box(st3, F.xform(Vector3(0, 1.12, 0.05)), Vector3(0.18, 0.35, 1.1), accent, Vector2(1.0, 0.7))
	_mesh(_head, st3)

	# arms
	for side in [-1, 1]:
		var arm := _pivot(_torso, "ArmL" if side < 0 else "ArmR", Vector3(1.8 * side, 2.2, 0))
		var st4 := F.begin()
		F.box(st4, F.xform(Vector3(0, -0.6, 0)), Vector3(0.75, 1.2, 0.75), steel, Vector2(1.1, 1.1))
		F.box(st4, F.xform(Vector3(0, -1.6, 0)), Vector3(0.85, 1.05, 0.85), steel_dk, Vector2(1.15, 1.15))
		F.box_at(st4, Vector3(0, -1.25, 0), Vector3(0.95, 0.18, 0.95), accent)
		F.box_at(st4, Vector3(0, -2.35, 0), Vector3(0.8, 0.7, 0.8), steel)
		_mesh(arm, st4)
		if side < 0:
			_arm_l = arm
		else:
			_arm_r = arm

	# hammer, held in the right fist: handle points forward/down
	_hammer = _pivot(_arm_r, "Hammer", Vector3(0, -2.35, 0))
	var st5 := F.begin()
	var dir := Vector3(0, -0.5, -0.866)
	var hxf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 - 0.5236), Vector3.ZERO)
	F.prism(st5, hxf, 0.14, 0.14, 3.0, 6, F.col(Color(0.45, 0.3, 0.2)))
	var head_c := dir * 3.0
	var hb := Basis(Vector3.RIGHT, -0.5236)
	F.box(st5, Transform3D(hb, head_c), Vector3(1.5, 1.1, 1.05), steel_dk)
	for k in 5:
		var c := hazard_y if k % 2 == 0 else hazard_k
		F.box(st5, Transform3D(hb, head_c + hb * Vector3(-0.6 + k * 0.3, 0, 0)), Vector3(0.3, 1.14, 1.09), c)
	F.box(st5, Transform3D(hb, head_c + hb * Vector3(0, 0, -0.56)), Vector3(1.2, 0.8, 0.1), visor)
	_mesh(_hammer, st5)

	# attack telegraph (flat arc in front of the boss)
	_telegraph = MeshInstance3D.new()
	var st6 := F.begin()
	var segs := 20
	for k in segs:
		var a0 := lerpf(-1.7, 1.7, float(k) / segs)
		var a1 := lerpf(-1.7, 1.7, float(k + 1) / segs)
		var r0 := 1.5
		var r1 := reach
		var p0 := Vector3(sin(a0) * r0, 0, -cos(a0) * r0)
		var p1 := Vector3(sin(a1) * r0, 0, -cos(a1) * r0)
		var p2 := Vector3(sin(a1) * r1, 0, -cos(a1) * r1)
		var p3 := Vector3(sin(a0) * r1, 0, -cos(a0) * r1)
		F.quad(st6, p0, p1, p2, p3, Color.WHITE, Vector3(0, -1, 0))
	_telegraph.mesh = F.commit(st6)
	_telegraph_mat = StandardMaterial3D.new()
	_telegraph_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_telegraph_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph_mat.albedo_color = Color(1.0, 0.15, 0.1, 0.0)
	_telegraph_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_telegraph.material_override = _telegraph_mat
	_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph.position = Vector3(0, 0.06, 0)
	_telegraph.visible = false
	add_child(_telegraph)

	# simple collision so knocked runners bounce off the giant
	_collider = StaticBody3D.new()
	_collider.collision_layer = 2
	_collider.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 1.4
	cap.height = 6.0
	cs.shape = cap
	cs.position = Vector3(0, 3.0, 0)
	_collider.add_child(cs)
	add_child(_collider)
	_apply_pose()


func _pivot(parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = n
	p.position = pos
	parent.add_child(p)
	return p


func _mesh(parent: Node3D, st: SurfaceTool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshFactory.commit(st)
	mi.material_override = _mat
	parent.add_child(mi)
