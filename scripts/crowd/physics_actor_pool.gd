class_name PhysicsActorPool
extends Node3D
## Fixed-size pool of PhysicsActor rigid bodies. When empty, the oldest active
## actor is recycled, so the number of simultaneous physics runners is capped.

@export var actor_scene: PackedScene = preload("res://scenes/crowd/PhysicsActor.tscn")
@export var pool_size := 24

var _free: Array[PhysicsActor] = []
var _active: Array[PhysicsActor] = []


func _ready() -> void:
	for i in pool_size:
		var a: PhysicsActor = actor_scene.instantiate()
		a.name = "Actor%d" % i
		add_child(a)
		a.finished.connect(_on_finished)
		_free.append(a)


func spawn(look: Dictionary, feet_transform: Transform3D, velocity: Vector3, spin: Vector3, lifetime := 1.8) -> PhysicsActor:
	var a: PhysicsActor
	if _free.is_empty():
		if _active.is_empty():
			return null
		a = _active.pop_front()
	else:
		a = _free.pop_back()
	_active.append(a)
	a.launch(look, feet_transform, velocity, spin, lifetime)
	return a


func active_count() -> int:
	return _active.size()


func _on_finished(a: PhysicsActor) -> void:
	_active.erase(a)
	if not _free.has(a):
		_free.append(a)
