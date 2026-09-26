class_name RunnerVisual
extends Node3D
## Stand-alone runner (Runner.tscn). Uses the same meshes + procedural poses as
## the MultiMesh crowd. Used for physics actors (knocked runners) and anywhere a
## single hero runner is needed.

@export var auto_animate := true
@export var cadence := 15.0 # run-cycle radians per second

var anim: int = RunnerRig.Anim.IDLE
var anim_t := 0.0
var phase := 0.0
var lean := 0.0
var look := 0.0

var _parts: Array[MeshInstance3D] = []
var _pose: Array[Transform3D] = RunnerRig.new_pose_buffer()
var _hair_style := -1


func _ready() -> void:
	if _parts.is_empty():
		_build()


func _build() -> void:
	for i in RunnerRig.PART_COUNT:
		var mi := MeshInstance3D.new()
		mi.name = RunnerRig.Part.keys()[i]
		mi.mesh = RunnerRig.mesh(RunnerRig.part_mesh_name(i, 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		_parts.append(mi)
	apply_look(RunnerRig.random_look(RandomNumberGenerator.new()))


func apply_look(look_data: Dictionary) -> void:
	if _parts.is_empty():
		_build()
	var skin: float = look_data["skin"]
	var style: int = look_data["hair_style"]
	if style != _hair_style:
		_parts[RunnerRig.Part.HAIR].mesh = RunnerRig.mesh(RunnerRig.part_mesh_name(RunnerRig.Part.HAIR, style))
		_hair_style = style
	var mats := {}
	for i in RunnerRig.PART_COUNT:
		var tint: Color = RunnerRig.part_tint(i, look_data)
		var key := tint.to_html()
		if not mats.has(key):
			mats[key] = Palette.runner_actor_material(tint, skin)
		_parts[i].material_override = mats[key]
	scale = Vector3(look_data["width"], look_data["height"], look_data["width"])


func set_anim(new_anim: int) -> void:
	if new_anim != anim:
		anim = new_anim
		anim_t = 0.0


func set_flash(amount: float) -> void:
	for p in _parts:
		var m := p.material_override as ShaderMaterial
		if m:
			m.set_shader_parameter("flash", amount)


func _process(delta: float) -> void:
	if not auto_animate or not visible:
		return
	anim_t += delta
	phase += delta * cadence
	update_pose()


func update_pose() -> void:
	RunnerRig.pose_into(_pose, anim, phase, anim_t, lean, look)
	for i in RunnerRig.PART_COUNT:
		_parts[i].transform = _pose[i]
