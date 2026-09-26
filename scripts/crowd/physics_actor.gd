class_name PhysicsActor
extends RigidBody3D
## A runner that has been hit hard (gate loss, obstacle, boss swing).
## Normal runners are animation-driven MultiMesh instances; only these few
## temporarily become real Jolt rigid bodies, then shrink away and return to
## the pool. They never stand back up (cheap), except `recover` actors which
## play GET_UP before fading.

signal finished(actor: PhysicsActor)

const LAYER_WORLD := 1
const LAYER_PROPS := 2
const LAYER_ACTORS := 4

@export var visual_offset := Vector3(0, -0.9, 0)

var active := false
var life := 0.0
var lifetime := 1.8
var _base_scale := Vector3.ONE
var _hit_flash := 0.0

@onready var visual: RunnerVisual = $Runner


func _ready() -> void:
	collision_layer = LAYER_ACTORS
	collision_mask = LAYER_WORLD | LAYER_PROPS
	gravity_scale = 1.9
	linear_damp = 0.15
	angular_damp = 1.2
	can_sleep = true
	continuous_cd = false
	contact_monitor = false
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.25
	pm.friction = 0.7
	physics_material_override = pm
	visual.position = visual_offset
	_park()


func launch(look: Dictionary, feet_transform: Transform3D, velocity: Vector3, spin: Vector3, life_time := 1.8) -> void:
	visual.apply_look(look)
	_base_scale = visual.scale
	visual.phase = randf() * TAU
	visual.set_anim(RunnerRig.Anim.KNOCKBACK)
	visual.set_flash(0.8)
	_hit_flash = 0.8
	life = 0.0
	lifetime = life_time
	active = true
	visible = true
	# body origin sits at the hips
	var xf := feet_transform
	xf.origin += feet_transform.basis.y.normalized() * -visual_offset.y
	freeze = false
	global_transform = xf
	linear_velocity = velocity
	angular_velocity = spin
	sleeping = false


func _physics_process(delta: float) -> void:
	if not active:
		return
	life += delta
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 4.0)
		visual.set_flash(_hit_flash)
	if visual.anim == RunnerRig.Anim.KNOCKBACK and life > 0.5 and linear_velocity.length() < 3.0:
		visual.set_anim(RunnerRig.Anim.FALL)
	if life > lifetime:
		var k := 1.0 - (life - lifetime) / 0.3
		if k <= 0.0:
			_park()
			finished.emit(self)
			return
		visual.scale = _base_scale * k
	# safety: never let an actor fall forever
	if global_position.y < -20.0:
		life = lifetime + 1.0


func _park() -> void:
	active = false
	visible = false
	freeze = true
	global_position = Vector3(0, -200, 0)
