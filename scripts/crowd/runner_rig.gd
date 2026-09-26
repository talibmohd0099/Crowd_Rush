class_name RunnerRig
extends RefCounted
## The single shared runner character: procedural low-poly part meshes + a
## procedural pose function. The same data drives both the MultiMesh crowd
## (hundreds of runners, 8 draw calls) and the few stand-alone physics actors.
##
## Rig (runner local space, feet at origin, facing -Z, ~1.6 units tall):
##   BODY (hips joint) -> HEAD/HAIR (neck) -> ARM_L / ARM_R (shoulders)
##   THIGH_L / THIGH_R (hip joints) -> SHIN_L / SHIN_R (knees, incl. shoes)
## Chibi proportions: big round head (~1/3 of the height), short legs and
## chunky sneakers, so runners read as toys even when the crowd is small on
## a phone screen.
## Animation is fully procedural (no skeletons): cheap, phase-offsettable and
## trivially blendable, which is exactly what a crowd needs.

enum Part { BODY, HEAD, HAIR, ARM_L, ARM_R, THIGH_L, THIGH_R, SHIN_L, SHIN_R }
const PART_COUNT := 9

enum Anim { IDLE, RUN, HIT, KNOCKBACK, FALL, GET_UP, VICTORY, ATTACK }
## TURN_LEFT / TURN_RIGHT are additive: `lean` (-1..1) leans/yaws the pose.

const HIP_HEIGHT := 0.64
const THIGH_LEN := 0.25
const SHIN_LEN := 0.25 ## knee -> ankle; the shoe adds the last ~0.14
const NECK := Vector3(0, 0.40, 0)
const SHOULDER := Vector3(0.235, 0.33, 0)
const HIP_OFFSET := 0.11

const HAIR_STYLES := 2 # 0 = spiky hair, 1 = cap
const SHOE_STYLES := 4 # see Palette.SHOES

static var _meshes: Dictionary = {}


static func mesh(part: StringName) -> ArrayMesh:
	if _meshes.is_empty():
		_build_meshes()
	return _meshes[part]


static func _build_meshes() -> void:
	var F := MeshFactory
	var dark := F.col(Color(0.12, 0.12, 0.14))
	var white := F.col(Color(0.97, 0.97, 0.97))
	var tint := F.col(Color.WHITE, F.TINT)
	var skin := F.col(Color.WHITE, F.SKIN)
	var accent := F.col(Color.WHITE, F.ACCENT)

	# BODY: rounded hoodie torso (shirt tint), pocket, neck
	var st := F.begin()
	F.box(st, F.xform(Vector3(0, 0.2, 0)), Vector3(0.40, 0.34, 0.28), tint, Vector2(0.86, 0.85))
	F.box(st, F.xform(Vector3(0, 0.04, 0)), Vector3(0.38, 0.1, 0.27), tint, Vector2(1.06, 1.04))
	F.box(st, F.xform(Vector3(0, 0.25, -0.128)), Vector3(0.16, 0.045, 0.02), white)
	F.prism(st, F.xform(Vector3(0, 0.35, 0)), 0.08, 0.075, 0.07, 6, skin)
	_meshes[&"body"] = F.commit(st)

	# HEAD: big smooth round head, big eyes (white + pupil + shine), ears
	st = F.begin()
	F.smooth_sphere(st, F.xform(Vector3(0, 0.25, 0)), Vector3(0.27, 0.26, 0.255), 8, 14, skin)
	for sx in [-1.0, 1.0]:
		F.box(st, F.xform(Vector3(0.095 * sx, 0.27, -0.235), Vector3(0.12, 0.0, 0.0)), Vector3(0.085, 0.1, 0.03), white)
		F.box(st, F.xform(Vector3(0.095 * sx, 0.26, -0.252), Vector3(0.12, 0.0, 0.0)), Vector3(0.05, 0.07, 0.02), F.col(Color(0.07, 0.07, 0.1)))
		F.box(st, F.xform(Vector3(0.105 * sx, 0.285, -0.262)), Vector3(0.018, 0.018, 0.01), white)
		F.smooth_sphere(st, F.xform(Vector3(0.262 * sx, 0.23, 0.01)), Vector3(0.04, 0.06, 0.05), 3, 6, skin)
	F.box(st, F.xform(Vector3(0, 0.15, -0.238), Vector3(0.25, 0, 0)), Vector3(0.09, 0.022, 0.02), F.col(Color(0.45, 0.14, 0.12)))
	_meshes[&"head"] = F.commit(st)

	# HAIR A: spiky hair - a round cap plus tufts sweeping up and back
	st = F.begin()
	F.sphere(st, F.xform(Vector3(0, 0.27, 0.02)), Vector3(0.285, 0.265, 0.28), 4, 12, tint, 0.05, 1.0)
	F.box(st, F.xform(Vector3(0, 0.22, 0.1)), Vector3(0.55, 0.24, 0.34), tint, Vector2(1.0, 0.9))
	var spikes := [
		[Vector3(0.0, 0.47, -0.1), Vector3(-0.5, 0.0, 0.0)],
		[Vector3(-0.13, 0.45, -0.02), Vector3(-0.2, 0.0, 0.5)],
		[Vector3(0.13, 0.45, -0.02), Vector3(-0.2, 0.0, -0.5)],
		[Vector3(0.0, 0.46, 0.1), Vector3(0.55, 0.0, 0.0)],
		[Vector3(-0.12, 0.4, 0.17), Vector3(0.9, 0.0, 0.4)],
		[Vector3(0.12, 0.4, 0.17), Vector3(0.9, 0.0, -0.4)],
		[Vector3(0.0, 0.33, 0.25), Vector3(1.4, 0.0, 0.0)],
	]
	for sp in spikes:
		F.prism(st, F.xform(sp[0] - Vector3(0, 0.06, 0), sp[1]), 0.085, 0.0, 0.16, 5, tint)
	_meshes[&"hair_0"] = F.commit(st)

	# HAIR B: baseball cap (dome + button + curved brim) over short hair
	st = F.begin()
	F.sphere(st, F.xform(Vector3(0, 0.29, 0)), Vector3(0.29, 0.25, 0.29), 4, 12, tint, 0.15, 1.0)
	F.box(st, F.xform(Vector3(0, 0.54, 0)), Vector3(0.05, 0.03, 0.05), tint)
	F.box(st, F.xform(Vector3(0, 0.33, -0.3), Vector3(-0.18, 0, 0)), Vector3(0.36, 0.035, 0.22), tint, Vector2(0.85, 1.0))
	F.box(st, F.xform(Vector3(0, 0.18, 0.13)), Vector3(0.5, 0.16, 0.2), F.col(Color(0.14, 0.1, 0.08)))
	_meshes[&"hair_1"] = F.commit(st)

	# ARM: short puffy sleeve (shirt tint) + forearm + round hand. Pivot = shoulder.
	st = F.begin()
	F.box(st, F.xform(Vector3(0, -0.08, 0)), Vector3(0.15, 0.2, 0.15), tint, Vector2(1.1, 1.1))
	F.box(st, F.xform(Vector3(0, -0.23, -0.02), Vector3(0.2, 0, 0)), Vector3(0.1, 0.16, 0.1), skin)
	F.smooth_sphere(st, F.xform(Vector3(0, -0.33, -0.045)), Vector3(0.075, 0.075, 0.075), 4, 8, skin)
	_meshes[&"arm"] = F.commit(st)

	# THIGH: short, pants tint. Pivot = hip joint (top overlaps pelvis).
	st = F.begin()
	F.box(st, F.xform(Vector3(0, -0.1, 0)), Vector3(0.16, 0.3, 0.17), tint, Vector2(1.2, 1.15))
	_meshes[&"thigh"] = F.commit(st)

	# SHIN: pants + a BIG chunky sneaker (white upper, coloured toe, tongue,
	# laces and a thick coloured sole). Pivot = knee.
	st = F.begin()
	var ank := -SHIN_LEN
	F.box(st, F.xform(Vector3(0, -0.11, 0)), Vector3(0.14, 0.24, 0.15), tint, Vector2(1.1, 1.1))
	F.box(st, F.xform(Vector3(0, ank + 0.0, 0.0)), Vector3(0.18, 0.12, 0.2), white, Vector2(0.9, 0.9))
	F.box(st, F.xform(Vector3(0, ank - 0.035, -0.1)), Vector3(0.2, 0.11, 0.34), white, Vector2(0.9, 0.85))
	F.box(st, F.xform(Vector3(0, ank - 0.03, -0.235)), Vector3(0.205, 0.1, 0.1), accent, Vector2(0.85, 0.7))
	F.box(st, F.xform(Vector3(0, ank + 0.02, -0.12), Vector3(-0.35, 0, 0)), Vector3(0.12, 0.02, 0.14), accent)
	F.box(st, F.xform(Vector3(0, ank - 0.105, -0.09)), Vector3(0.225, 0.05, 0.42), accent, Vector2(1.0, 1.0))
	F.box(st, F.xform(Vector3(0, ank - 0.133, -0.09)), Vector3(0.23, 0.014, 0.43), F.col(Color(0.95, 0.95, 0.95)))
	_meshes[&"shin"] = F.commit(st)


## Writes the 9 part transforms (runner-local) for a pose into `out`.
## phase  : run-cycle phase (radians), used for RUN/ATTACK/VICTORY offsets
## t      : seconds since the state started (HIT, KNOCKBACK, GET_UP ...)
## lean   : -1..1 steering lean (additive TURN_LEFT / TURN_RIGHT)
## look   : head yaw (radians)
static func pose_into(out: Array[Transform3D], anim: int, phase: float, t: float, lean: float, look: float) -> void:
	var s := sin(phase)
	var c := cos(phase)
	var hip_y := HIP_HEIGHT
	var body_pitch := 0.0
	var body_yaw := 0.0
	var body_roll := -lean * 0.22
	var head_pitch := 0.0
	var head_yaw := look
	var al_x := 0.0
	var al_z := -0.08
	var ar_x := 0.0
	var ar_z := 0.08
	var tl_x := 0.0
	var tr_x := 0.0
	var tl_z := 0.0
	var tr_z := 0.0
	var sl_x := 0.0
	var sr_x := 0.0

	match anim:
		Anim.RUN, Anim.HIT, Anim.GET_UP:
			hip_y = HIP_HEIGHT + 0.035 - 0.07 * absf(s)
			body_pitch = -0.2 - absf(lean) * 0.08
			body_yaw = 0.12 * s
			head_pitch = 0.14
			al_x = -0.85 * s
			ar_x = 0.85 * s
			al_z = -0.13
			ar_z = 0.13
			tl_x = 0.72 * s
			tr_x = -0.72 * s
			sl_x = -(0.15 + 1.15 * maxf(0.0, c))
			sr_x = -(0.15 + 1.15 * maxf(0.0, -c))
			if anim == Anim.HIT:
				# stumble: quick recoil backwards, arms flung out, knees buckle
				var k := sin(clampf(t / 0.55, 0.0, 1.0) * PI)
				k = k * k * (3.0 - 2.0 * k)
				hip_y = lerpf(hip_y, HIP_HEIGHT - 0.1, k)
				body_pitch = lerpf(body_pitch, 0.55, k)
				head_pitch = lerpf(head_pitch, -0.4, k)
				al_x = lerpf(al_x, 0.9, k)
				ar_x = lerpf(ar_x, 0.9, k)
				al_z = lerpf(al_z, -1.3, k)
				ar_z = lerpf(ar_z, 1.3, k)
				tl_x = lerpf(tl_x, 0.5, k)
				tr_x = lerpf(tr_x, -0.1, k)
				sl_x = lerpf(sl_x, -0.9, k)
				sr_x = lerpf(sr_x, -0.3, k)
			elif anim == Anim.GET_UP:
				var k2 := 1.0 - clampf(t / 0.6, 0.0, 1.0)
				k2 = k2 * k2
				hip_y = lerpf(hip_y, HIP_HEIGHT - 0.24, k2)
				body_pitch = lerpf(body_pitch, -0.9, k2)
				tl_x = lerpf(tl_x, 1.3, k2)
				tr_x = lerpf(tr_x, 0.9, k2)
				sl_x = lerpf(sl_x, -2.1, k2)
				sr_x = lerpf(sr_x, -1.6, k2)
				al_x = lerpf(al_x, 0.9, k2)
				ar_x = lerpf(ar_x, 0.9, k2)
		Anim.IDLE:
			var b := sin(t * 2.2 + phase)
			hip_y = HIP_HEIGHT - 0.01 + 0.008 * b
			body_pitch = 0.03 * b
			al_z = -0.1 - 0.03 * b
			ar_z = 0.1 + 0.03 * b
			al_x = 0.05
			ar_x = 0.05
			head_pitch = 0.05
			tl_z = -0.04
			tr_z = 0.04
		Anim.KNOCKBACK:
			var f := t * 17.0 + phase
			body_pitch = 0.35
			head_pitch = -0.35
			al_x = 0.6 + 0.9 * sin(f)
			ar_x = 0.6 - 0.9 * sin(f)
			al_z = -1.7 - 0.35 * sin(f * 1.3)
			ar_z = 1.7 + 0.35 * sin(f * 1.3)
			tl_x = 0.7 * sin(f * 0.9)
			tr_x = -0.7 * sin(f * 0.9)
			tl_z = -0.25
			tr_z = 0.25
			sl_x = -0.8
			sr_x = -0.8
		Anim.FALL:
			body_pitch = 0.25
			head_pitch = -0.2
			al_z = -1.35
			ar_z = 1.25
			al_x = 0.3
			ar_x = -0.2
			tl_x = 0.35
			tr_x = -0.15
			tl_z = -0.18
			tr_z = 0.2
			sl_x = -0.5
			sr_x = -0.2
		Anim.VICTORY:
			var hop := absf(sin(t * 5.5 + phase))
			hip_y = HIP_HEIGHT + hop * 0.4
			body_pitch = 0.08
			head_pitch = -0.25
			var wave := sin(t * 11.0 + phase) * 0.25
			al_x = 2.75 + wave
			ar_x = 2.75 - wave
			al_z = -0.35
			ar_z = 0.35
			tl_x = 0.5 * hop
			tr_x = 0.35 * hop
			sl_x = -0.9 * hop
			sr_x = -0.7 * hop
		Anim.ATTACK:
			var a := t * 10.0 + phase
			var pl := maxf(0.0, sin(a))
			var pr := maxf(0.0, -sin(a))
			hip_y = HIP_HEIGHT - 0.05 + 0.1 * absf(sin(a))
			body_pitch = -0.25
			body_yaw = 0.3 * sin(a)
			head_pitch = 0.2
			al_x = 0.9 + 0.75 * pl
			ar_x = 0.9 + 0.75 * pr
			al_z = -0.25
			ar_z = 0.25
			tl_x = 0.45 * sin(a * 0.5)
			tr_x = -0.45 * sin(a * 0.5)
			sl_x = -0.5
			sr_x = -0.5

	var hips := Vector3(0, hip_y, 0)
	var body := Transform3D(Basis.from_euler(Vector3(body_pitch, body_yaw, body_roll)), hips)
	var head := body * Transform3D(Basis.from_euler(Vector3(head_pitch, head_yaw, -body_roll * 0.5)), NECK)
	out[Part.BODY] = body
	out[Part.HEAD] = head
	out[Part.HAIR] = head
	out[Part.ARM_L] = body * Transform3D(Basis.from_euler(Vector3(al_x, 0, al_z)), Vector3(-SHOULDER.x, SHOULDER.y, 0))
	out[Part.ARM_R] = body * Transform3D(Basis.from_euler(Vector3(ar_x, 0, ar_z)), Vector3(SHOULDER.x, SHOULDER.y, 0))
	var pelvis := Basis(Vector3.UP, -body_yaw * 0.5)
	var thigh_l := Transform3D(pelvis * Basis.from_euler(Vector3(tl_x, 0, tl_z)), hips + pelvis * Vector3(-HIP_OFFSET, 0, 0))
	var thigh_r := Transform3D(pelvis * Basis.from_euler(Vector3(tr_x, 0, tr_z)), hips + pelvis * Vector3(HIP_OFFSET, 0, 0))
	out[Part.THIGH_L] = thigh_l
	out[Part.THIGH_R] = thigh_r
	out[Part.SHIN_L] = thigh_l * Transform3D(Basis(Vector3.RIGHT, sl_x), Vector3(0, -THIGH_LEN, 0))
	out[Part.SHIN_R] = thigh_r * Transform3D(Basis(Vector3.RIGHT, sr_x), Vector3(0, -THIGH_LEN, 0))


static func new_pose_buffer() -> Array[Transform3D]:
	var a: Array[Transform3D] = []
	a.resize(PART_COUNT)
	return a


## Mesh name used by a part (hair depends on the runner's style).
static func part_mesh_name(part: int, hair_style: int) -> StringName:
	match part:
		Part.BODY: return &"body"
		Part.HEAD: return &"head"
		Part.HAIR: return StringName("hair_%d" % hair_style)
		Part.ARM_L, Part.ARM_R: return &"arm"
		Part.THIGH_L, Part.THIGH_R: return &"thigh"
		_: return &"shin"


## Random look for a runner. Returns a Dictionary consumed by crowd + actors.
static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var style := rng.randi_range(0, HAIR_STYLES - 1)
	var hair_col: Color = Palette.HAIR[rng.randi() % Palette.HAIR.size()]
	if style == 1:
		hair_col = Palette.CAPS[rng.randi() % Palette.CAPS.size()]
	return {
		"shirt": Palette.SHIRTS[rng.randi() % Palette.SHIRTS.size()],
		"pants": Palette.PANTS[rng.randi() % Palette.PANTS.size()],
		"hair": hair_col,
		"hair_style": style,
		# skin tone (0..3) and shoe colour (0..3) packed into one float: the
		# crowd shader receives it as INSTANCE_CUSTOM.a (see crowd_runner.gdshader)
		"skin": (float(rng.randi_range(0, 3) + 4 * rng.randi_range(0, SHOE_STYLES - 1)) + 0.5) / 16.0,
		"height": rng.randf_range(0.95, 1.05),
		"width": rng.randf_range(0.94, 1.08),
	}


## Which tint a part uses (shirt / pants / hair).
static func part_tint(part: int, look: Dictionary) -> Color:
	match part:
		Part.BODY, Part.ARM_L, Part.ARM_R: return look["shirt"]
		Part.HAIR: return look["hair"]
		Part.THIGH_L, Part.THIGH_R, Part.SHIN_L, Part.SHIN_R: return look["pants"]
		_: return look["shirt"]
