class_name IntroSequence
extends Node
## ~10 s in-engine "mobile ad" opening, played on the live level:
##  0.0-1.5  fade in, wide elevated shot, push toward the 5 runners  "START WITH 5"
##  1.5-3.0  close on the runners running at camera, one looks aside  "MAKE IT BIGGER"
##  3.0-5.0  camera swings behind into the real gameplay camera; gates ahead pulse
##  5.0-7.0  fly ahead: a preview squad hits the x2 gate, 5 -> 10 payoff
##  7.0-9.0  rise + telephoto zoom on the distant GIANT GUARD     "REACH THE BOSS"
##  9.0-10.0 blend into the gameplay camera, HUD in, player in control
## No video, no loading - camera + events scripted over real game objects.

signal finished

const DURATION := 10.0
const INTRO_SPEED := 6.0
const PREVIEW_CAM := Vector3(5.5, 5.2, 7.5) ## 3/4 view: crowd, gate panel and burst all readable
const PREVIEW_LOOK := Vector3(-0.8, 1.2, -3.0)

var game: GameManager
var t := 0.0
var playing := false

var _events: Array = []
var _ev_idx := 0
var _preview_started := false
var _multiplied := false
var _camera_released := false
var _arrows: Node3D
var _arrow_mat: StandardMaterial3D
var _env: Environment
var _base_fog := 0.0024


func play(gm: GameManager) -> void:
	game = gm
	t = 0.0
	_ev_idx = 0
	playing = true
	_build_arrows()
	var eb := game.get_node_or_null("Environment") as EnvironmentBuilder
	if eb and eb.world_env:
		_env = eb.world_env.environment
		_base_fog = _env.fog_density
	var hud := game.hud
	var audio := game.audio
	var crowd := game.crowd
	_events = [
		[0.0, func() -> void:
			hud.set_black(true)
			hud.fade_from_black(1.1)
			hud.set_letterbox(true, 0.01)
			audio.play(&"intro_rumble", -2.0, 1.0, 0.0)
			audio.start_ambience(2.5)],
		[0.35, func() -> void: hud.show_cinematic_text("START WITH 5")],
		[1.0, func() -> void: audio.set_footsteps_level(0.22)],
		[1.42, func() -> void: hud.hide_cinematic_text(0.1)],
		[1.55, func() -> void: hud.show_cinematic_text("MAKE IT BIGGER")],
		[2.0, func() -> void: crowd.set_runner_look(1, 0.95)],
		[2.75, func() -> void: crowd.set_runner_look(1, 0.0)],
		[2.9, func() -> void: hud.hide_cinematic_text(0.15)],
		[3.0, func() -> void:
			audio.play(&"whoosh", -3.0)
			audio.play_music(&"music_main", 1.5, -11.0)],
		[3.5, func() -> void:
			game.level.first_gate().set_highlight(true)
			_show_arrows(true)
			audio.set_music_offset(-7.0, 1.2)],
		[4.9, func() -> void: _show_arrows(false)],
		[5.0, func() -> void:
			_start_preview()
			audio.play(&"whoosh", 0.0, 0.8)],
		[7.1, func() -> void:
			audio.set_music_offset(-15.0, 0.4)
			_fog_to(0.0004, 0.5)],
		[7.25, func() -> void:
			hud.show_cinematic_text("REACH THE BOSS")
			audio.play(&"impact_distant", 0.0)],
		[7.7, func() -> void:
			audio.play(&"boss_roar", -1.0, 0.82, 0.0)
			game.camera.shake(0.28)
			var b := game.level.boss
			var tw := b.create_tween()
			tw.tween_property(b, "p_visor", 4.0, 0.2)
			tw.tween_property(b, "p_visor", 1.0, 0.8)],
		[8.85, func() -> void: hud.hide_cinematic_text(0.2)],
		[9.0, func() -> void:
			_fog_to(_base_fog, 1.0)
			_release_camera(1.0)
			audio.play(&"whoosh", -2.0, 1.15)
			audio.set_music_offset(0.0, 1.0)
			hud.set_letterbox(false, 0.6)
			crowd.target_speed = crowd.base_speed
			_hide_preview()],
		[9.4, func() -> void:
			hud.set_gameplay_visible(true, 0.4)
			game.begin_control()],
		[9.6, func() -> void: game.level.first_gate().set_highlight(false)],
	]
	# individual footsteps for the close-up of 5 runners
	var ft := 1.05
	var k := 0
	while ft < 3.2:
		var pitch := 0.9 + (k % 3) * 0.08
		_events.append([ft, func() -> void: audio.play(&"footstep", -9.0, pitch, 0.06)])
		ft += 0.155
		k += 1
	_events.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	crowd.forward_speed = INTRO_SPEED
	crowd.target_speed = INTRO_SPEED
	_update_camera()


## The telephoto boss reveal looks through ~400 units of haze: thin it briefly.
func _fog_to(density: float, dur: float) -> void:
	if _env:
		create_tween().tween_property(_env, "fog_density", density, dur)


## Debug / replay: jump straight to gameplay.
func skip() -> void:
	if not playing:
		return
	for i in range(_ev_idx, _events.size()):
		var ev: Array = _events[i]
		if ev[0] >= 9.0 or ev[0] == 3.0:
			(ev[1] as Callable).call()
	game.hud.hide_cinematic_text(0.1)
	_show_arrows(false)
	_hide_preview()
	_fog_to(_base_fog, 0.2)
	_release_camera(0.4)
	_finish()


func _process(delta: float) -> void:
	if not playing:
		return
	t += delta
	while _ev_idx < _events.size() and _events[_ev_idx][0] <= t:
		(_events[_ev_idx][1] as Callable).call()
		_ev_idx += 1
	if _preview_started and not _multiplied:
		var pv := game.preview_crowd
		var gz := game.level.first_gate().global_position.z
		if pv.get_front_z() <= gz:
			_preview_multiply()
	if _arrows and _arrows.visible:
		var c := game.crowd.get_center()
		_arrows.position = Vector3(c.x, 0.06, c.z - 5.5)
		_arrow_mat.albedo_color.a = 0.55 + 0.35 * sin(t * 10.0)
	if not _camera_released:
		_update_camera()
	if t >= DURATION:
		_finish()


func _finish() -> void:
	playing = false
	if _arrows:
		_arrows.queue_free()
		_arrows = null
	finished.emit()


# ------------------------------------------------------------------ camera
func _update_camera() -> void:
	var c := game.crowd.get_center()
	var pos: Vector3
	var look: Vector3
	var fov := 50.0
	if t < 3.0:
		var u := _ease_out(t / 3.0)
		var k0 := Vector3(2.4, 5.8, -30.0)
		var k1 := Vector3(1.8, 2.0, -13.0)
		var k2 := Vector3(0.85, 1.5, -5.4)
		var off := k0 * (1.0 - u) * (1.0 - u) + k1 * 2.0 * u * (1.0 - u) + k2 * u * u
		pos = c + off
		look = c + Vector3(0, lerpf(0.9, 1.15, u), 0)
		fov = lerpf(50.0, 46.0, u)
	elif t < 5.0:
		var u2 := _smooth((t - 3.0) / 2.0)
		var theta := lerpf(0.15, PI, u2)
		var r := lerpf(5.45, game.camera.follow_offset.z, u2)
		var h := lerpf(1.5, game.camera.follow_offset.y, u2)
		pos = c + Vector3(sin(theta) * r, h, -cos(theta) * r)
		look = c + Vector3(0, 1.15, 0).lerp(Vector3(0, 0.6, -game.camera.look_ahead), u2)
		fov = lerpf(46.0, game.camera.base_fov, u2)
	elif t < 7.0:
		var p := game.preview_crowd.get_center()
		var k := _smooth((t - 5.0) / 1.35)
		var from_pos := c + game.camera.follow_offset
		var from_look := c + Vector3(0, 0.6, -game.camera.look_ahead)
		pos = from_pos.lerp(p + PREVIEW_CAM, k)
		look = from_look.lerp(p + PREVIEW_LOOK, k)
		fov = game.camera.base_fov + sin(k * PI) * 9.0
	else:
		var p2 := game.preview_crowd.get_center()
		var u3 := _smooth((t - 7.0) / 1.6)
		pos = p2 + PREVIEW_CAM.lerp(Vector3(0, 20.0, 18.0), u3)
		var boss_look := game.level.boss.global_position + Vector3(0, 3.4, 0)
		look = (p2 + PREVIEW_LOOK).lerp(boss_look, _smooth((t - 7.0) / 0.9))
		fov = lerpf(game.camera.base_fov, 4.2, _smooth((t - 7.25) / 1.25))
	game.camera.set_cinematic(Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos), fov)


func _release_camera(blend: float) -> void:
	if _camera_released:
		return
	_camera_released = true
	game.camera.set_mode(CameraController.Mode.FOLLOW, blend)


static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)


# ------------------------------------------------------------------ preview squad
func _start_preview() -> void:
	if _preview_started:
		return
	_preview_started = true
	var pv := game.preview_crowd
	var gz := game.level.first_gate().global_position.z
	pv.visible = true
	pv.process_mode = Node.PROCESS_MODE_INHERIT
	pv.reset_crowd(Vector3(3.5, 0, gz + 15.0), 5)
	pv.input_enabled = true
	pv.set_steer_target(3.5)
	pv.forward_speed = 10.0
	pv.target_speed = 10.0


func _preview_multiply() -> void:
	_multiplied = true
	var pv := game.preview_crowd
	var gate := game.level.first_gate()
	pv.add_runners(5)
	gate.play_preview(1)
	game.audio.play(&"multiply", 1.0)
	game.audio.play(&"sparkle", -5.0, 1.15)
	game.vfx.burst(&"gate", gate.panel_center(1), Palette.MULTIPLY)
	game.vfx.burst(&"multiply", pv.get_center() + Vector3(0, 1.0, 0))
	game.vfx.ring(pv.get_center() + Vector3(0, 0.1, 0), Palette.MULTIPLY, 6.0, 0.55)
	game.vfx.pop_text(pv.get_center() + Vector3(-1.5, 5.6, -3.5), "×2!", Palette.MULTIPLY.lightened(0.2), 1.4, 1.1)
	game.camera.punch(1.0)
	game.camera.fov_kick(5.0)


func _hide_preview() -> void:
	var pv := game.preview_crowd
	if is_instance_valid(pv):
		pv.visible = false
		pv.process_mode = Node.PROCESS_MODE_DISABLED


# ------------------------------------------------------------------ route arrows
func _build_arrows() -> void:
	_arrows = Node3D.new()
	_arrows.name = "IntroArrows"
	_arrow_mat = StandardMaterial3D.new()
	_arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_arrow_mat.albedo_color = Color(1, 1, 1, 0.8)
	_arrow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := MeshFactory.begin()
	# chevron pointing -Z, flat on the ground
	for k in 2:
		var z := -k * 0.9
		MeshFactory.quad(st, Vector3(-0.9, 0, z + 0.5), Vector3(0, 0, z - 0.4), Vector3(0, 0, z + 0.05), Vector3(-0.9, 0, z + 0.95), Color.WHITE, Vector3(0, -1, 0))
		MeshFactory.quad(st, Vector3(0.9, 0, z + 0.5), Vector3(0, 0, z - 0.4), Vector3(0, 0, z + 0.05), Vector3(0.9, 0, z + 0.95), Color.WHITE, Vector3(0, -1, 0))
	var mesh := MeshFactory.commit(st)
	for side in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _arrow_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(side * 1.9, 0, 0)
		mi.rotation.y = -side * 0.55
		_arrows.add_child(mi)
	_arrows.visible = false
	game.add_child(_arrows)


func _show_arrows(on: bool) -> void:
	if _arrows:
		_arrows.visible = on
