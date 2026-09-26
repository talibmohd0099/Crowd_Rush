class_name CameraController
extends Node3D
## Third-person elevated follow camera with game-feel helpers:
##  - smooth follow with a tiny lateral delay
##  - zoom out as the crowd grows / in as it shrinks
##  - forward "punch" on gates, trauma-based shake on impacts
##  - boss framing, victory orbit, and blend-in from scripted cinematics

enum Mode { CINEMATIC, FOLLOW, BOSS, VICTORY }

@export var follow_offset := Vector3(0, 8.2, 9.6) ## ~36 deg down-angle
@export var look_ahead := 7.0
@export var base_fov := 58.0
@export var max_zoom := 1.42
@export var shake_decay := 1.9

var mode: Mode = Mode.CINEMATIC
var crowd: CrowdManager
var boss_focus := Vector3.ZERO

var _zoom := 1.0
var _trauma := 0.0
var _punch := 0.0
var _fov_kick := 0.0
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _cine_xf := Transform3D.IDENTITY
var _cine_fov := 58.0
var _blend_from := Transform3D.IDENTITY
var _blend_from_fov := 58.0
var _blend_t := 1.0
var _blend_dur := 1.0
var _time := 0.0
var _orbit := 0.0
var _initialized := false

@onready var cam: Camera3D = $Camera3D


func _ready() -> void:
	cam.fov = base_fov
	cam.near = 0.15
	cam.far = 900.0
	cam.current = true


func setup(crowd_manager: CrowdManager) -> void:
	crowd = crowd_manager


## Called every frame by cinematics (intro).
func set_cinematic(xf: Transform3D, fov: float) -> void:
	mode = Mode.CINEMATIC
	_cine_xf = xf
	_cine_fov = fov


func set_mode(m: Mode, blend_time := 1.0) -> void:
	if m == mode:
		return
	_blend_from = cam.global_transform
	_blend_from_fov = cam.fov
	_blend_t = 0.0
	_blend_dur = maxf(blend_time, 0.001)
	if mode == Mode.CINEMATIC or not _initialized:
		_snap_follow()
	mode = m
	_orbit = 0.0


## Desired gameplay-camera transform right now (used by the intro to aim for it).
func get_follow_transform() -> Transform3D:
	var pl := _follow_targets(_zoom)
	return Transform3D(Basis.looking_at(pl[1] - pl[0], Vector3.UP), pl[0])


## Instantly jump to the follow framing (after teleports / restarts).
func snap() -> void:
	_snap_follow()
	_blend_t = 1.0


func shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func punch(amount := 1.0) -> void:
	_punch = clampf(_punch + amount, 0.0, 1.5)


func fov_kick(deg: float) -> void:
	_fov_kick += deg


func _snap_follow() -> void:
	if crowd == null:
		return
	_zoom = _zoom_for(crowd.count)
	var pl := _follow_targets(_zoom)
	_pos = pl[0]
	_look = pl[1]
	_initialized = true


func _zoom_for(n: int) -> float:
	return lerpf(1.0, max_zoom, clampf((n - 5) / 110.0, 0.0, 1.0))


func _follow_targets(z: float) -> Array[Vector3]:
	var c := crowd.get_center()
	var pos := Vector3(c.x * 0.55, 0.0, c.z) + follow_offset * z
	var look := Vector3(c.x * 0.8, 0.6, c.z - look_ahead * z)
	return [pos, look]


func _process(delta: float) -> void:
	_time += delta
	var xf: Transform3D
	var fov := base_fov
	match mode:
		Mode.CINEMATIC:
			xf = _cine_xf
			fov = _cine_fov
		Mode.FOLLOW:
			_zoom = lerpf(_zoom, _zoom_for(crowd.count), 1.0 - exp(-delta * 1.6))
			var pl := _follow_targets(_zoom)
			# lateral lags a bit more than forward: feels like steering a mass
			_pos.x = lerpf(_pos.x, pl[0].x, 1.0 - exp(-delta * 4.0))
			_pos.y = lerpf(_pos.y, pl[0].y, 1.0 - exp(-delta * 3.0))
			_pos.z = lerpf(_pos.z, pl[0].z, 1.0 - exp(-delta * 14.0))
			_look = _look.lerp(pl[1], 1.0 - exp(-delta * 7.0))
			xf = Transform3D(Basis.looking_at(_look - _pos, Vector3.UP), _pos)
		Mode.BOSS:
			var c := crowd.get_visual_center()
			var mid := c.lerp(boss_focus, 0.42)
			var want := Vector3(c.x * 0.4, 11.5, c.z + 14.0)
			_pos = _pos.lerp(want, 1.0 - exp(-delta * 2.5))
			_look = _look.lerp(mid + Vector3(0, 2.2, 0), 1.0 - exp(-delta * 3.0))
			xf = Transform3D(Basis.looking_at(_look - _pos, Vector3.UP), _pos)
			fov = base_fov + 4.0
		Mode.VICTORY:
			_orbit += delta * 0.16
			var c2 := crowd.get_visual_center().lerp(boss_focus, 0.3)
			var r := 17.0 + minf(_orbit * 8.0, 5.0)
			var want2 := c2 + Vector3(sin(_orbit) * r, 9.0 + minf(_orbit * 4.0, 3.0), cos(_orbit) * r)
			_pos = _pos.lerp(want2, 1.0 - exp(-delta * 1.8))
			_look = _look.lerp(c2 + Vector3(0, 1.5, 0), 1.0 - exp(-delta * 2.5))
			xf = Transform3D(Basis.looking_at(_look - _pos, Vector3.UP), _pos)
			fov = base_fov + 2.0
	# blend from previous shot
	if _blend_t < 1.0:
		_blend_t = minf(1.0, _blend_t + delta / _blend_dur)
		var k := _blend_t * _blend_t * (3.0 - 2.0 * _blend_t)
		xf = _blend_from.interpolate_with(xf, k)
		fov = lerpf(_blend_from_fov, fov, k)
	# punch (short push toward the crowd) + fov kick
	_punch = move_toward(_punch, 0.0, delta * 3.5)
	_fov_kick = lerpf(_fov_kick, 0.0, 1.0 - exp(-delta * 6.0))
	var p := _punch * _punch
	xf.origin += -xf.basis.z * p * 1.2
	fov += _fov_kick - p * 3.0
	# trauma shake (squared for punchy falloff)
	_trauma = move_toward(_trauma, 0.0, delta * shake_decay)
	if _trauma > 0.0:
		var s := _trauma * _trauma
		var ox := sin(_time * 53.0) * 0.6 + sin(_time * 31.0 + 1.3) * 0.4
		var oy := sin(_time * 47.0 + 2.1) * 0.6 + sin(_time * 29.0 + 0.4) * 0.4
		xf.origin += xf.basis.x * ox * s * 0.55 + xf.basis.y * oy * s * 0.45
		xf.basis = xf.basis * Basis(Vector3.FORWARD, sin(_time * 37.0) * s * 0.03)
	cam.global_transform = xf
	cam.fov = clampf(fov, 5.0, 100.0)
