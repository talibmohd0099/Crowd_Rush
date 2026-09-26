class_name InputController
extends Node
## Touch + drag anywhere to steer the crowd left/right (mouse drag on desktop via
## "emulate touch from mouse"). Relative drag -> target X on the road; the crowd
## itself smooths toward it with a weighted spring (CrowdManager).

signal steer_changed(target_x: float)

## World units moved per full screen width of finger travel. Lower = calmer.
@export var units_per_screen := 13.0
@export var keyboard_speed := 9.0
@export var sensitivity := 1.0

var enabled := false
var target_x := 0.0
var crowd: CrowdManager

var _touch_index := -1


func setup(crowd_manager: CrowdManager) -> void:
	crowd = crowd_manager


func reset(x := 0.0) -> void:
	target_x = x
	_touch_index = -1


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch_index == -1:
			_touch_index = t.index
		elif not t.pressed and t.index == _touch_index:
			_touch_index = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index != _touch_index:
			return
		var w := get_viewport().get_visible_rect().size.x
		_set_target(target_x + d.relative.x / maxf(w, 1.0) * units_per_screen * sensitivity)


func _process(delta: float) -> void:
	if not enabled:
		return
	var dir := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir += 1.0
	if dir != 0.0:
		_set_target(target_x + dir * keyboard_speed * delta)


func _set_target(x: float) -> void:
	var lim := crowd.steer_limit() if crowd else 4.0
	target_x = clampf(x, -lim, lim)
	if crowd:
		crowd.set_steer_target(target_x)
	steer_changed.emit(target_x)
