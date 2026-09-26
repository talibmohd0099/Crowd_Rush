class_name Gate
extends Node3D
## A two-choice gate spanning the road. Left panel covers x<0, right panel x>0.
## Each panel: frame posts, header sign, animated curtain, gigantic number.
## Type is communicated by colour AND symbol/shape/pattern:
##   ADD  (+N) : cyan, upward chevrons on header, chevron curtain
##   MUL  (xN) : gold, diamond "gems" on header, sparkling curtain, pulsing
##   SUB  (-N) : red, hazard stripes + warning triangle + teeth, striped curtain

signal crowd_entered(gate: Gate)

enum Op { ADD, SUB, MUL }

const HALF_WIDTH := 7.0
const HEIGHT := 4.4
const LAYER_WORLD := 1
const LAYER_PROPS := 2
const LAYER_GATE_TRIGGER := 32
const LAYER_CROWD_SENSOR := 16

@export var left_op: Op = Op.ADD
@export var left_value := 10
@export var right_op: Op = Op.MUL
@export var right_value := 2

var resolved := false
var _panels: Array[Dictionary] = [] # index 0 = left, 1 = right
var _time := 0.0
var _phase := 0.0


func _ready() -> void:
	_phase = randf() * TAU
	_build()


# ------------------------------------------------------------------ logic
static func op_text(op: Op, value: int) -> String:
	match op:
		Op.ADD: return "+%d" % value
		Op.SUB: return "-%d" % value
		_: return "×%d" % value


static func apply_op(op: Op, value: int, current: int) -> int:
	match op:
		Op.ADD: return current + value
		Op.SUB: return maxi(0, current - value)
		_: return current * value


static func op_color(op: Op) -> Color:
	match op:
		Op.ADD: return Palette.POSITIVE
		Op.SUB: return Palette.NEGATIVE
		_: return Palette.MULTIPLY


func get_op(side: int) -> Op:
	return left_op if side < 0 else right_op


func get_value(side: int) -> int:
	return left_value if side < 0 else right_value


func panel_center(side: int) -> Vector3:
	return global_position + Vector3(3.5 * side, 2.2, 0)


## Marks the gate as used and plays the panel feedback. Returns the op data.
func resolve(side: int) -> Dictionary:
	resolved = true
	var chosen: Dictionary = _panels[0 if side < 0 else 1]
	var other: Dictionary = _panels[1 if side < 0 else 0]
	_activate_panel(chosen)
	_dim_panel(other)
	return {"op": get_op(side), "value": get_value(side)}


## Intro "ad preview": flash a panel without consuming the gate.
func play_preview(side: int) -> void:
	var p: Dictionary = _panels[0 if side < 0 else 1]
	var mat: ShaderMaterial = p["curtain_mat"]
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("intensity", v), 3.5, 1.0, 0.6)
	var label: Label3D = p["label"]
	var tw2 := create_tween()
	tw2.tween_property(label, "scale", Vector3.ONE * 1.3, 0.1)
	tw2.tween_property(label, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_highlight(on: bool) -> void:
	for p in _panels:
		(p["curtain_mat"] as ShaderMaterial).set_shader_parameter("highlight", 1.0 if on else 0.0)


func _activate_panel(p: Dictionary) -> void:
	var mat: ShaderMaterial = p["curtain_mat"]
	var label: Label3D = p["label"]
	var root: Node3D = p["root"]
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("intensity", v), 4.0, 0.0, 0.55)
	tw.tween_property(label, "scale", Vector3.ONE * 1.5, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.2)
	tw.tween_property(label, "outline_modulate:a", 0.0, 0.35).set_delay(0.2)
	tw.tween_property(root, "scale", Vector3(1.06, 1.1, 1.0), 0.08)
	tw.chain().tween_property(root, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _dim_panel(p: Dictionary) -> void:
	var mat: ShaderMaterial = p["curtain_mat"]
	var label: Label3D = p["label"]
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("intensity", v), 1.0, 0.25, 0.4)
	tw.tween_property(label, "modulate:a", 0.35, 0.4)


func _process(delta: float) -> void:
	_time += delta
	for i in _panels.size():
		var p: Dictionary = _panels[i]
		var header: Node3D = p["header"]
		header.position.y = HEIGHT + 0.45 + sin(_time * 2.2 + _phase + i * 1.3) * 0.06
		if not resolved and p["op"] == Op.MUL:
			var label: Label3D = p["label"]
			label.scale = Vector3.ONE * (1.0 + sin(_time * 5.0 + _phase) * 0.045)


# ------------------------------------------------------------------ build
func _build() -> void:
	# centre post shared by both panels
	var st := MeshFactory.begin()
	MeshFactory.box_at(st, Vector3(0, HEIGHT * 0.5 + 0.1, 0), Vector3(0.45, HEIGHT + 0.2, 0.45), MeshFactory.col(Color(0.92, 0.93, 0.95)))
	MeshFactory.box_at(st, Vector3(0, 0.12, 0), Vector3(0.8, 0.24, 0.8), MeshFactory.col(Color(0.3, 0.32, 0.36)))
	var center_post := MeshInstance3D.new()
	center_post.mesh = MeshFactory.commit(st)
	center_post.material_override = Palette.world_material()
	add_child(center_post)
	_add_post_collider(Vector3(0, HEIGHT * 0.5, 0))

	for side in [-1, 1]:
		var op: Op = get_op(side)
		var value: int = get_value(side)
		_panels.append(_build_panel(side, op, value))

	# one trigger across the full road width
	var area := Area3D.new()
	area.name = "TriggerArea"
	area.collision_layer = LAYER_GATE_TRIGGER
	area.collision_mask = LAYER_CROWD_SENSOR
	area.monitoring = true
	area.monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(HALF_WIDTH * 2.0, 4.0, 0.6)
	cs.shape = box
	cs.position = Vector3(0, 2.0, 0)
	area.add_child(cs)
	add_child(area)
	area.area_entered.connect(func(_a: Area3D) -> void:
		if not resolved:
			crowd_entered.emit(self))


func _build_panel(side: int, op: Op, value: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "LeftPanel" if side < 0 else "RightPanel"
	root.position = Vector3(3.5 * side, 0, 0)
	add_child(root)
	var color := op_color(op)
	var F := MeshFactory
	var white := F.col(Color(0.94, 0.95, 0.97))
	var glow := F.col(color, 0.5) # emissive mask
	var dark := F.col(color.darkened(0.55))
	var outer_x := 3.35 * side

	# ---- frame (outer post)
	var st := F.begin()
	if op == Op.SUB:
		# hazard striped post
		var seg := 8
		for k in seg:
			var h := HEIGHT / seg
			var c := Color(0.1, 0.1, 0.1) if k % 2 == 0 else Color(1.0, 0.82, 0.1)
			F.box_at(st, Vector3(outer_x, h * (k + 0.5), 0), Vector3(0.42, h, 0.42), F.col(c))
	else:
		F.box_at(st, Vector3(outer_x, HEIGHT * 0.5, 0), Vector3(0.4, HEIGHT, 0.4), white)
		F.box_at(st, Vector3(outer_x, HEIGHT * 0.5, -0.21), Vector3(0.12, HEIGHT * 0.92, 0.04), glow)
	F.box_at(st, Vector3(outer_x, 0.12, 0), Vector3(0.8, 0.24, 0.8), F.col(Color(0.3, 0.32, 0.36)))
	var frame := MeshInstance3D.new()
	frame.mesh = F.commit(st)
	frame.material_override = Palette.world_material()
	root.add_child(frame)
	_add_post_collider(Vector3(outer_x + 3.5 * side, HEIGHT * 0.5, 0))

	# ---- header sign with type symbols (bobs gently)
	var header := Node3D.new()
	header.position = Vector3(0, HEIGHT + 0.45, 0)
	root.add_child(header)
	st = F.begin()
	F.box_at(st, Vector3.ZERO, Vector3(6.9, 0.8, 0.35), F.col(color))
	F.box_at(st, Vector3(0, 0, -0.18), Vector3(6.6, 0.55, 0.04), glow)
	match op:
		Op.ADD:
			for k in 3:
				var cx := (k - 1) * 1.1
				F.box(st, F.xform(Vector3(cx - 0.17, 0.02, -0.24), Vector3(0, 0, -0.75)), Vector3(0.5, 0.14, 0.06), white)
				F.box(st, F.xform(Vector3(cx + 0.17, 0.02, -0.24), Vector3(0, 0, 0.75)), Vector3(0.5, 0.14, 0.06), white)
		Op.MUL:
			for k in 3:
				var cx2 := (k - 1) * 1.2
				var s := 0.36 if k == 1 else 0.26
				F.box(st, F.xform(Vector3(cx2, 0, -0.24), Vector3(0, 0, PI * 0.25)), Vector3(s, s, 0.08), white)
			F.box_at(st, Vector3(0, 0.55, 0), Vector3(1.2, 0.3, 0.3), F.col(color))
			for k in 3:
				F.box(st, F.xform(Vector3((k - 1) * 0.45, 0.78, 0), Vector3(0, 0, PI * 0.25)), Vector3(0.22, 0.22, 0.25), F.col(color))
		Op.SUB:
			for k in 9:
				var c2 := Color(0.1, 0.1, 0.1) if k % 2 == 0 else Color(1.0, 0.82, 0.1)
				F.box(st, F.xform(Vector3(-3.0 + k * 0.75, 0, -0.2), Vector3(0, 0, 0.6)), Vector3(0.36, 0.9, 0.04), F.col(c2))
			# teeth under the header
			for k in 7:
				F.prism(st, F.xform(Vector3(-2.7 + k * 0.9, -0.4, 0), Vector3(PI, 0, 0)), 0.2, 0.0, 0.35, 4, dark)
			# warning triangle on top
			var tri_h := 0.9
			F.prism(st, F.xform(Vector3(0, 0.4, 0)), 0.62, 0.0, tri_h, 3, F.col(Color(1.0, 0.82, 0.1)))
			F.box_at(st, Vector3(0, 0.78, -0.26), Vector3(0.1, 0.3, 0.06), F.col(Color(0.1, 0.1, 0.1)))
			F.box_at(st, Vector3(0, 0.55, -0.3), Vector3(0.1, 0.09, 0.06), F.col(Color(0.1, 0.1, 0.1)))
	var header_mi := MeshInstance3D.new()
	header_mi.mesh = F.commit(st)
	header_mi.material_override = Palette.world_material()
	header.add_child(header_mi)

	# ---- curtain
	var curtain := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(6.5, HEIGHT - 0.1)
	curtain.mesh = q
	curtain.position = Vector3(0, HEIGHT * 0.5 + 0.05, 0)
	curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load("res://materials/gate_curtain.gdshader")
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("pattern", 0 if op == Op.ADD else (1 if op == Op.MUL else 2))
	curtain.material_override = mat
	root.add_child(curtain)

	# ---- giant number
	var label := Label3D.new()
	label.text = op_text(op, value)
	label.font = Palette.font()
	label.font_size = 230
	label.pixel_size = 0.0105
	label.outline_size = 40
	label.modulate = Color(1, 1, 1)
	label.outline_modulate = color.darkened(0.6)
	label.position = Vector3(0, 2.35, 0.06)
	label.render_priority = 2
	label.outline_render_priority = 1
	label.double_sided = true
	root.add_child(label)

	# ---- ambient sparkles on multiplier gates (tiny, cheap)
	if op == Op.MUL:
		var sp := CPUParticles3D.new()
		sp.amount = 10
		sp.lifetime = 1.6
		sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		sp.emission_box_extents = Vector3(3.0, 2.0, 0.2)
		sp.position = Vector3(0, 2.3, 0.2)
		sp.direction = Vector3(0, 1, 0)
		sp.spread = 20.0
		sp.gravity = Vector3.ZERO
		sp.initial_velocity_min = 0.3
		sp.initial_velocity_max = 0.8
		sp.scale_amount_min = 0.1
		sp.scale_amount_max = 0.2
		sp.color = Color(1.0, 0.92, 0.5)
		var qm := QuadMesh.new()
		qm.material = Palette.particle_material(Palette.soft_circle_texture(), true)
		sp.mesh = qm
		root.add_child(sp)

	return {"root": root, "header": header, "curtain_mat": mat, "label": label, "op": op, "value": value, "side": side}


func _add_post_collider(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_PROPS
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.45, HEIGHT, 0.45)
	cs.shape = box
	body.add_child(cs)
	body.position = pos
	add_child(body)
