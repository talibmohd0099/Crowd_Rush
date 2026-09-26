class_name GameManager
extends Node3D
## Root of Main.tscn. Owns the tiny game state machine and wires the systems
## together with signals (no global singletons):
##   INTRO -> PLAYING -> BOSS_INTRO -> BOSS_FIGHT -> VICTORY   (or FAILED)

signal state_changed(new_state: State)
signal boss_started
signal boss_damaged(hp: float, max_hp: float)
signal boss_defeated
signal level_completed(survived: int)

enum State { INTRO, PLAYING, BOSS_INTRO, BOSS_FIGHT, VICTORY, FAILED }

@export var debug_tools_enabled := true ## F1-F6 + overlay (debug builds only)
@export var skip_intro_on_replay := true
@export_group("Boss fight tuning")
@export var boss_base_dps := 4.0
@export var boss_dps_per_runner := 0.14
@export var boss_min_survivors := 3 ## swings never drop the crowd below this
@export var boss_enrage_time := 9.0 ## after this the crowd hits much harder

var state: State = State.INTRO

@onready var level: LevelManager = $Level
@onready var gate_manager: GateManager = $Level/GateManager
@onready var crowd: CrowdManager = $Crowd
@onready var preview_crowd: CrowdManager = $PreviewCrowd
@onready var pool: PhysicsActorPool = $Crowd/ActivePhysicsActors
@onready var camera: CameraController = $CameraRig
@onready var input: InputController = $InputController
@onready var audio: AudioManager = $AudioManager
@onready var vfx: VFXManager = $VFXManager
@onready var hud: HUD = $HUD
@onready var intro: IntroSequence = $IntroSequence
@onready var debug_overlay: DebugOverlay = $DebugOverlay

var _touches := {}

var _obstacle_done := false
var _fight_time := 0.0
var _dmg_acc := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	level.build(gate_manager)
	crowd.setup(pool, vfx, audio)
	preview_crowd.setup(pool, vfx, audio)
	preview_crowd.visible = false
	preview_crowd.process_mode = Node.PROCESS_MODE_DISABLED
	input.setup(crowd)
	camera.setup(crowd)
	gate_manager.setup(crowd, vfx, audio, camera, hud)
	vfx.attach_ambient_motes(camera.cam)
	debug_overlay.setup(self)
	debug_overlay.visible = false # F6 toggles (debug builds only)

	crowd.crowd_size_changed.connect(_on_crowd_size_changed)
	crowd.crowd_emptied.connect(_on_crowd_emptied)
	hud.restart_pressed.connect(_restart)
	intro.finished.connect(_on_intro_finished)
	var boss := level.boss
	boss.footstep.connect(_on_boss_footstep)
	boss.roared.connect(_on_boss_roared)
	boss.slammed.connect(_on_boss_slammed)
	boss.entrance_finished.connect(_start_fight)
	boss.swing_started.connect(_on_boss_swing_started)
	boss.swing_hit.connect(_on_boss_swing_hit)
	boss.damaged.connect(_on_boss_damaged)
	boss.defeated.connect(_on_boss_defeated)
	camera.boss_focus = level.boss_final_position()

	if skip_intro_on_replay and SaveData.intro_seen:
		_start_direct()
	else:
		_start_intro()


# ------------------------------------------------------------------ flow
func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)


func _start_intro() -> void:
	_set_state(State.INTRO)
	crowd.reset_crowd(Vector3.ZERO)
	hud.set_count(crowd.count, false)
	intro.play(self)


## Replays skip the 10 s intro and start just before the first gate.
func _start_direct() -> void:
	crowd.reset_crowd(Vector3(0, 0, -LevelManager.INTRO_END_D))
	crowd.forward_speed = 6.0
	crowd.target_speed = crowd.base_speed
	hud.set_count(crowd.count, false)
	hud.set_letterbox(false, 0.01)
	hud.set_black(true)
	hud.fade_from_black(0.45)
	camera.set_mode(CameraController.Mode.FOLLOW, 0.001)
	audio.start_ambience(0.8)
	audio.play_music(&"music_main", 0.6)
	audio.play(&"whoosh", -4.0)
	hud.set_gameplay_visible(true, 0.3)
	begin_control()


## Called by the intro at ~9.4 s (or directly on replays).
func begin_control() -> void:
	if state == State.PLAYING:
		return
	input.reset(crowd.center.x)
	input.enabled = true
	crowd.input_enabled = true
	gate_manager.active = true
	_set_state(State.PLAYING)


func _on_intro_finished() -> void:
	SaveData.intro_seen = true
	if is_instance_valid(preview_crowd):
		preview_crowd.queue_free()
	if state == State.INTRO:
		begin_control()


func _restart() -> void:
	audio.play(&"ui_click")
	get_tree().call_deferred("reload_current_scene")


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	match state:
		State.PLAYING:
			hud.set_progress(level.progress_for(crowd.center.z))
			if not _obstacle_done and crowd.get_front_z() <= level.obstacle_z() + 0.8:
				_hit_obstacle()
			if crowd.get_front_z() <= level.boss_trigger_z():
				_start_boss_intro()
		State.BOSS_FIGHT:
			_update_fight(delta)
	# footstep bed follows crowd size + movement
	var moving := crowd.forward_speed > 1.5
	var lvl := clampf(0.2 + crowd.count / 110.0, 0.0, 1.0) * (1.0 if moving else 0.35)
	if state == State.INTRO and intro.t < 1.0 or state == State.VICTORY or state == State.FAILED:
		lvl = 0.0
	audio.set_footsteps_level(lvl)


func _hit_obstacle() -> void:
	_obstacle_done = true
	var loss := mini(clampi(roundi(crowd.count * 0.1), 2, 5), crowd.count - 1)
	var bz := level.obstacle_z()
	level.obstacle.smash(crowd.center.x, crowd.get_half_width())
	if loss > 0:
		crowd.hit_obstacle(bz, loss)
		vfx.pop_text(crowd.get_center() + Vector3(0, 3.0, -1.5), "-%d" % loss, Palette.NEGATIVE.lightened(0.2), 0.9)
	else:
		crowd.stumble_near(Vector3(crowd.center.x, 0, bz), 3)
	audio.play(&"barrier_crash", 1.0)
	audio.play(&"thud", -2.0)
	audio.play(&"hit", -4.0, 0.9)
	vfx.burst(&"debris", Vector3(crowd.center.x, 0.9, bz))
	vfx.burst(&"dust", Vector3(crowd.center.x, 0.3, bz), Color(0, 0, 0, 0), 0.7)
	camera.shake(0.5)
	camera.punch(0.4)


# ------------------------------------------------------------------ boss
func _start_boss_intro() -> void:
	_set_state(State.BOSS_INTRO)
	boss_started.emit()
	gate_manager.active = false
	crowd.halt_at(level.halt_z())
	crowd.funnel_side = 0
	input.reset(0.0) # drift the crowd to the centre of the arena
	crowd.set_steer_target(0.0)
	camera.boss_focus = level.boss_final_position()
	camera.set_mode(CameraController.Mode.BOSS, 1.4)
	audio.play_music(&"music_boss", 0.7)
	hud.set_progress(1.0)
	hud.show_boss_bar(true)
	hud.set_boss_health(1.0)
	level.boss.crowd_focus = crowd.get_center()
	level.boss.play_entrance()


func _start_fight() -> void:
	if state != State.BOSS_INTRO:
		return
	_set_state(State.BOSS_FIGHT)
	_fight_time = 0.0
	_dmg_acc = 0.0
	crowd.charge(level.boss.global_position, 2.9)
	level.boss.start_fight()
	hud.show_banner("OVERWHELM IT!", Color(1.0, 0.85, 0.3), 0.9)
	audio.play(&"crowd_cheer", -5.0, 1.05)
	camera.punch(0.5)


func _update_fight(delta: float) -> void:
	_fight_time += delta
	if crowd.mode != CrowdManager.Mode.SWARM:
		return
	var dps := boss_base_dps + boss_dps_per_runner * crowd.count
	if _fight_time > boss_enrage_time:
		dps *= 2.5
	_dmg_acc += delta
	if _dmg_acc >= 0.15:
		_dmg_acc -= 0.15
		level.boss.take_damage(dps * 0.15)
		audio.play_limited(&"boss_hit", 0.07, -7.0, _rng.randf_range(0.85, 1.2))
		var bp := level.boss.global_position
		vfx.burst(&"hit", bp + Vector3(_rng.randf_range(-1.6, 1.6), _rng.randf_range(0.8, 3.5), 1.6))


func _on_boss_footstep(pos: Vector3) -> void:
	audio.play(&"boss_step", 0.0, 1.0, 0.06)
	camera.shake(0.22)
	vfx.burst(&"dust", pos + Vector3(0, 0.2, 0), Color(0, 0, 0, 0), 0.35)


func _on_boss_roared() -> void:
	audio.play(&"boss_roar", 1.0)
	camera.shake(0.3)


func _on_boss_slammed(pos: Vector3) -> void:
	audio.play(&"ground_slam", 2.0)
	camera.shake(0.85)
	camera.punch(0.6)
	vfx.burst(&"dust", Vector3(pos.x, 0.3, pos.z))
	vfx.ring(Vector3(pos.x, 0.15, pos.z), Color(1, 0.95, 0.85, 0.8), 11.0, 0.7)
	if state == State.BOSS_INTRO:
		# shockwave: the front of the crowd stumbles, nobody dies (payoff comes later)
		crowd.stumble_near(Vector3(crowd.center.x, 0, crowd.get_front_z()), 14, 1.4)
		audio.play(&"thud", -4.0, 0.8)


func _on_boss_swing_started() -> void:
	audio.play(&"warning", -9.0)
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if state == State.BOSS_FIGHT:
			audio.play(&"weapon_swing", 0.0))


func _on_boss_swing_hit(origin: Vector3, _reach: float) -> void:
	if state != State.BOSS_FIGHT:
		return
	var k := mini(clampi(roundi(crowd.count * 0.09), 2, 10), crowd.count - boss_min_survivors)
	var bp := level.boss.global_position
	if k > 0:
		crowd.knock_from(bp, k, 10.0, 7.0)
		audio.play(&"hit", 0.0)
		audio.play(&"hit", -3.0, 0.8)
	crowd.stumble_near(origin, 6, 1.0)
	audio.play(&"thud", -2.0)
	camera.shake(0.5)
	vfx.burst(&"dust", Vector3(origin.x, 0.3, origin.z), Color(0, 0, 0, 0), 0.6)


func _on_boss_damaged(hp: float, max_hp: float) -> void:
	hud.set_boss_health(hp / max_hp)
	boss_damaged.emit(hp, max_hp)


func _on_boss_defeated() -> void:
	if state == State.VICTORY:
		return
	_set_state(State.VICTORY)
	boss_defeated.emit()
	input.enabled = false
	crowd.input_enabled = false
	crowd.celebrate()
	camera.set_mode(CameraController.Mode.VICTORY, 1.6)
	audio.stop_music(0.4)
	audio.play(&"victory_sting", 0.0)
	audio.play(&"crowd_cheer", 0.0)
	hud.show_boss_bar(false)
	var c := crowd.get_visual_center()
	vfx.burst(&"confetti", c + Vector3(0, 1.0, 0))
	get_tree().create_timer(0.7).timeout.connect(func() -> void: vfx.burst(&"confetti", c + Vector3(-3, 1.0, -2)))
	get_tree().create_timer(1.3).timeout.connect(func() -> void:
		vfx.burst(&"confetti", c + Vector3(3, 1.0, -1))
		audio.play(&"sparkle", -4.0))
	get_tree().create_timer(1.7).timeout.connect(func() -> void:
		var best := SaveData.submit(crowd.count)
		hud.show_victory(crowd.count, best)
		level_completed.emit(crowd.count))


# ------------------------------------------------------------------ crowd events
func _on_crowd_size_changed(new_count: int, _old: int) -> void:
	hud.set_count(new_count, state != State.INTRO)


func _on_crowd_emptied() -> void:
	if state == State.VICTORY or state == State.FAILED:
		return
	_set_state(State.FAILED)
	input.enabled = false
	crowd.input_enabled = false
	crowd.target_speed = 0.0
	crowd.halt_at(crowd.center.z - 4.0)
	gate_manager.active = false
	audio.stop_music(0.8)
	audio.play(&"gate_negative", 0.0, 0.7)
	hud.show_boss_bar(false)
	get_tree().create_timer(1.1).timeout.connect(hud.show_failure)


# ------------------------------------------------------------------ debug
func _unhandled_input(event: InputEvent) -> void:
	# three-finger tap toggles the FPS overlay on phones (works in release
	# builds too, so performance can be checked on real devices)
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = true
			if _touches.size() == 3:
				debug_overlay.visible = not debug_overlay.visible
		else:
			_touches.erase(t.index)
		return
	if not (debug_tools_enabled and OS.is_debug_build()):
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_F1:
			_restart()
		KEY_F2:
			gate_manager.apply_effect(Gate.Op.ADD, 10, crowd.get_center() + Vector3(0, 2, -2))
		KEY_F3:
			gate_manager.apply_effect(Gate.Op.SUB, 10, crowd.get_center() + Vector3(0, 2, -2))
		KEY_F4:
			_debug_jump_to_boss()
		KEY_F5:
			gate_manager.apply_effect(Gate.Op.MUL, 2, crowd.get_center() + Vector3(0, 2, -2))
		KEY_F6:
			debug_overlay.visible = not debug_overlay.visible


func _debug_jump_to_boss() -> void:
	if state == State.INTRO:
		intro.skip()
	if state != State.PLAYING:
		return
	for g in level.gates:
		g.resolved = true
	_obstacle_done = true
	crowd.teleport_to_z(level.boss_trigger_z() + 14.0)
	camera.snap()
