class_name GateManager
extends Node
## Detects the crowd passing gates, computes the new count and fires the full
## feedback chain: INPUT -> MOTION -> VISUAL -> SOUND -> SMALL EFFECT.

signal gate_passed(gate: Gate, op: int, value: int, old_count: int, new_count: int)

var gates: Array[Gate] = []
var active := false
var crowd: CrowdManager
var vfx: VFXManager
var audio: AudioManager
var camera: CameraController
var hud: HUD


func setup(crowd_manager: CrowdManager, vfx_manager: VFXManager, audio_manager: AudioManager, cam: CameraController, hud_ui: HUD) -> void:
	crowd = crowd_manager
	vfx = vfx_manager
	audio = audio_manager
	camera = cam
	hud = hud_ui


func register(gate: Gate) -> void:
	gates.append(gate)
	gate.crowd_entered.connect(_on_gate_entered)


func next_gate() -> Gate:
	for g in gates:
		if not g.resolved:
			return g
	return null


func _process(_delta: float) -> void:
	if crowd == null:
		return
	# funnel: squeeze runners through the chosen panel while crossing
	crowd.funnel_side = 0
	for g in gates:
		var gz := g.global_position.z
		var dz := crowd.get_front_z() - gz
		if dz < 6.0 and crowd.get_back_z() > gz - 3.0:
			crowd.funnel_z = gz
			crowd.funnel_side = -1 if crowd.center.x < 0.0 else 1
		# fallback trigger (in case the physics sensor missed it)
		if active and not g.resolved and crowd.center.z <= gz:
			_resolve(g)


func _on_gate_entered(gate: Gate) -> void:
	if active and not gate.resolved:
		_resolve(gate)


func _resolve(gate: Gate) -> void:
	var side := -1 if crowd.center.x < 0.0 else 1
	var res := gate.resolve(side)
	apply_effect(res["op"], res["value"], gate.panel_center(side), gate)


## Applies a gate operation to the crowd with all feedback. Also used by debug F5.
func apply_effect(op: Gate.Op, value: int, fx_pos: Vector3, gate: Gate = null) -> void:
	var old := crowd.count
	var target := mini(Gate.apply_op(op, value, old), CrowdManager.MAX_CROWD)
	var above := crowd.get_center() + Vector3(0, 3.2, -1.0)
	var col := Gate.op_color(op)
	match op:
		Gate.Op.ADD:
			crowd.add_runners(target - old)
			audio.play(&"gate_positive", 0.0)
			audio.play(&"sparkle", -8.0)
			vfx.burst(&"gate", fx_pos, col)
			vfx.burst(&"sparkle", crowd.get_center() + Vector3(0, 1.2, 0))
			vfx.ring(crowd.get_center() + Vector3(0, 0.1, 0), col, 4.5, 0.45)
			vfx.pop_text(above, Gate.op_text(op, value), col.lightened(0.3), 1.0)
			camera.punch(0.6)
		Gate.Op.MUL:
			crowd.add_runners(target - old)
			audio.play(&"multiply", 1.0)
			audio.play(&"sparkle", -5.0, 1.15)
			vfx.burst(&"gate", fx_pos, col)
			vfx.burst(&"multiply", crowd.get_center() + Vector3(0, 1.0, 0))
			vfx.ring(crowd.get_center() + Vector3(0, 0.1, 0), col, 6.5, 0.55)
			vfx.pop_text(above + Vector3(0, 0.4, 0), Gate.op_text(op, value) + "!", col.lightened(0.2), 1.35, 1.0)
			camera.punch(1.0)
			camera.fov_kick(5.0)
		Gate.Op.SUB:
			crowd.remove_runners(old - target)
			audio.play(&"gate_negative", 0.0)
			audio.play(&"warning", -10.0)
			vfx.burst(&"negative", fx_pos, col)
			vfx.ring(crowd.get_center() + Vector3(0, 0.1, 0), col, 4.0, 0.4)
			vfx.pop_text(above, Gate.op_text(op, value), col.lightened(0.15), 1.0)
			camera.shake(0.35)
			camera.punch(0.3)
	if hud:
		hud.show_gate_delta(op, value, old, crowd.count)
	gate_passed.emit(gate, op, value, old, crowd.count)
