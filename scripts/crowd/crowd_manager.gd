class_name CrowdManager
extends Node3D
## The crowd is ONE gameplay entity. The player steers its centre; runners are
## lightweight data records rendered through a handful of MultiMeshes.
##
##  CrowdManager
##   |- Visual Crowd        : 8 MultiMeshInstance3D (body, head, 2 hair styles,
##   |                        arms, thighs, shins, blob shadows)
##   |- Active Physics Actors: PhysicsActorPool (few temporary RigidBody3D)
##   |- Formation Controller : Formation (slot layout per count, cached)
##   |- Crowd Statistics     : count / bounds / signals
##   |- Sensor               : one Area3D sized to the formation (gate triggers)

signal crowd_size_changed(new_count: int, old_count: int)
signal crowd_grew(amount: int)
signal crowd_hit(amount: int)
signal crowd_emptied

enum Mode { RUN, HALT, CHARGE, SWARM, CELEBRATE }

const MAX_CROWD := 150
const ROAD_HALF_WIDTH := 7.0
const SPAWN_DURATION := 0.36
const LAYER_CROWD_SENSOR := 16

@export var start_count := 5
@export var base_speed := 10.0
@export var steer_omega := 8.5 ## critically damped spring; lower = heavier crowd
@export var is_preview := false ## intro "ad preview" crowd: no sensor
@export var cast_shadows := true

var count := 0
var center := Vector3.ZERO
var forward_speed := 0.0
var target_speed := 0.0
var steer_target_x := 0.0
var input_enabled := false
var mode: Mode = Mode.RUN
var halt_z := 0.0
var swarm_target := Vector3.ZERO
var swarm_radius := 2.8
var funnel_z := INF
var funnel_side := 0

var runners: Array[RunnerData] = []
var pool: PhysicsActorPool
var vfx: VFXManager
var audio: AudioManager

var _steer_vel := 0.0
var _speed_mult := 1.0
var _compress := 0.0
var _slots := PackedVector2Array()
var _bounds := Vector3(0.5, -0.5, 0.5)
var _swarm_slots := PackedVector3Array()
var _spawn_queue := 0
var _spawn_rate := 0.0
var _spawn_acc := 0.0
var _slots_dirty := true
var _custom_dirty := true
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _pose: Array[Transform3D] = RunnerRig.new_pose_buffer()
var _run_lut: Array = []
var _sensor: Area3D
var _sensor_shape: BoxShape3D

# MultiMesh groups
enum G { BODY, HEAD, HAIR0, HAIR1, ARM, THIGH, SHIN, SHADOW }
var _mmi: Array[MultiMeshInstance3D] = []
var _mm_rid: Array[RID] = []
var _HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3(0, -500, 0))
const LUT_PHASES := 32
const LUT_LEANS := 9


class RunnerData:
	var pos := Vector3.ZERO
	var phase := 0.0
	var cadence := 15.0
	var follow := 8.0
	var anim: int = RunnerRig.Anim.RUN
	var anim_t := 0.0
	var lean := 0.0
	var look := 0.0
	var look_target := 0.0
	var yaw := 0.0
	var vx := 0.0
	var spawn_t := 1.0
	var dying := false
	var die_t := 0.0
	var look_data: Dictionary
	var seed := 0.0
	var slot := 0
	var push := Vector3.ZERO ## temporary displacement (stumbles, compression)
	var get_up := false ## heavy stumble: play GET_UP after HIT


func _ready() -> void:
	_rng.randomize()
	_build_multimeshes()
	_build_run_lut()
	if not is_preview:
		_sensor = Area3D.new()
		_sensor.name = "Sensor"
		_sensor.collision_layer = LAYER_CROWD_SENSOR
		_sensor.collision_mask = 0
		_sensor.monitoring = false
		_sensor.monitorable = true
		var cs := CollisionShape3D.new()
		_sensor_shape = BoxShape3D.new()
		cs.shape = _sensor_shape
		_sensor.add_child(cs)
		add_child(_sensor)


func setup(actor_pool: PhysicsActorPool, vfx_manager: VFXManager, audio_manager: AudioManager) -> void:
	pool = actor_pool
	vfx = vfx_manager
	audio = audio_manager


## Places the crowd and spawns the starting runners in formation.
func reset_crowd(at: Vector3, n: int = -1) -> void:
	if n < 0:
		n = start_count
	runners.clear()
	center = at
	count = 0
	_spawn_queue = 0
	_set_count(n)
	_refresh_slots()
	for i in n:
		var r := _new_runner()
		var sl := _slots[i]
		r.pos = center + Vector3(sl.x, 0, sl.y)
		r.slot = i
		runners.append(r)
	_custom_dirty = true


# ------------------------------------------------------------------ queries
func get_center() -> Vector3:
	return center


func get_front_z() -> float:
	return center.z + _bounds.y


func get_back_z() -> float:
	return center.z + _bounds.z


func get_half_width() -> float:
	return _bounds.x


func active_runner_count() -> int:
	var n := 0
	for r in runners:
		if not r.dying:
			n += 1
	return n


## Average position of living runners (useful during swarm / cinematics).
func get_visual_center() -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	for r in runners:
		if not r.dying:
			acc += r.pos
			n += 1
	return center if n == 0 else acc / n


# ------------------------------------------------------------------ control
func set_mode(m: Mode) -> void:
	mode = m
	_slots_dirty = true
	if m == Mode.SWARM:
		_swarm_slots = PackedVector3Array()


func halt_at(z: float) -> void:
	halt_z = z
	set_mode(Mode.HALT)


func charge(target: Vector3, radius: float) -> void:
	swarm_target = target
	swarm_radius = radius
	target_speed = base_speed * 0.8
	set_mode(Mode.CHARGE)


func celebrate() -> void:
	set_mode(Mode.CELEBRATE)
	target_speed = 0.0
	for r in runners:
		r.anim = RunnerRig.Anim.VICTORY
		r.anim_t = _rng.randf() * 0.3
		r.phase = _rng.randf() * TAU


func set_steer_target(x: float) -> void:
	steer_target_x = x


func steer_limit() -> float:
	return maxf(0.0, ROAD_HALF_WIDTH - _bounds.x - 0.45)


## Debug helper: moves the whole crowd (and its runners) to a new z.
func teleport_to_z(z: float) -> void:
	var dz := z - center.z
	center.z = z
	for r in runners:
		r.pos.z += dz


func set_runner_look(index: int, yaw: float) -> void:
	if index >= 0 and index < runners.size():
		runners[index].look_target = yaw


# ------------------------------------------------------------------ growth
## Adds runners. They pop in AROUND existing runners and flow into the outer
## formation slots over ~0.35 s (never a chaotic pile on one spot).
func add_runners(amount: int) -> int:
	var old := count
	var new_count := mini(count + amount, MAX_CROWD)
	var added := new_count - count
	if added <= 0:
		return 0
	_set_count(new_count)
	_spawn_queue += added
	_spawn_rate = maxf(float(_spawn_queue) / SPAWN_DURATION, 20.0)
	_refresh_slots()
	crowd_grew.emit(added)
	if old == 0 and runners.is_empty():
		_process_spawns(1.0)
	return added


## Removes runners after a bad gate: outer runners get knocked outward by
## physics (a few), the rest pop away; front runners stumble.
func remove_runners(amount: int, physics_max := 6) -> int:
	var removed := 0
	# cancel queued spawns first
	var q := mini(_spawn_queue, amount)
	_spawn_queue -= q
	removed += q
	var launched := 0
	var living: Array[RunnerData] = []
	for r in runners:
		if not r.dying:
			living.append(r)
	# outer formation slots first
	living.sort_custom(func(a: RunnerData, b: RunnerData) -> bool: return a.slot > b.slot)
	var k := 0
	while removed < amount and k < living.size():
		var r := living[k]
		k += 1
		var out_dir := Vector3(r.pos.x - center.x, 0, r.pos.z - center.z)
		if out_dir.length() < 0.2:
			out_dir = Vector3(_rng.randf_range(-1, 1), 0, 0.5)
		out_dir = out_dir.normalized()
		if launched < physics_max and pool:
			var vel := out_dir * _rng.randf_range(4.0, 6.5) + Vector3(0, _rng.randf_range(3.5, 5.5), forward_speed * -0.4)
			_launch(r, vel, 1.3)
			runners.erase(r)
			launched += 1
		else:
			r.dying = true
			r.die_t = 0.0
			r.push = out_dir * 0.8
		removed += 1
	stumble_near(Vector3(center.x, 0, get_front_z()), mini(7, count / 2 + 1))
	_set_count(count - removed)
	_refresh_slots()
	_custom_dirty = true
	if removed > 0:
		crowd_hit.emit(removed)
	return removed


## Knocks the `amount` runners closest to `source` away with real physics.
func knock_from(source: Vector3, amount: int, horizontal := 8.0, vertical := 6.0, dir_override := Vector3.ZERO) -> int:
	if amount <= 0:
		return 0
	var living: Array[RunnerData] = []
	for r in runners:
		if not r.dying:
			living.append(r)
	living.sort_custom(func(a: RunnerData, b: RunnerData) -> bool:
		return a.pos.distance_squared_to(source) < b.pos.distance_squared_to(source))
	var n := mini(amount, living.size())
	for k in n:
		var r := living[k]
		var dir := dir_override
		if dir == Vector3.ZERO:
			dir = Vector3(r.pos.x - source.x, 0, r.pos.z - source.z)
			if dir.length() < 0.1:
				dir = Vector3(0, 0, 1)
		dir = dir.normalized()
		var vel := dir * horizontal * _rng.randf_range(0.75, 1.2) + Vector3(0, vertical * _rng.randf_range(0.8, 1.2), 0)
		_launch(r, vel, 1.6)
		runners.erase(r)
	_set_count(count - n)
	_refresh_slots()
	_custom_dirty = true
	if n > 0:
		crowd_hit.emit(n)
	return n


## Plays a short stumble on the `amount` living runners nearest `pos`.
func stumble_near(pos: Vector3, amount: int, push_strength := 0.6) -> void:
	var living: Array[RunnerData] = []
	for r in runners:
		if not r.dying and r.spawn_t >= 1.0:
			living.append(r)
	living.sort_custom(func(a: RunnerData, b: RunnerData) -> bool:
		return a.pos.distance_squared_to(pos) < b.pos.distance_squared_to(pos))
	for k in mini(amount, living.size()):
		var r := living[k]
		r.anim = RunnerRig.Anim.HIT
		r.anim_t = _rng.randf() * 0.1
		r.get_up = push_strength >= 1.2 and k < amount / 2
		var d := r.pos - pos
		d.y = 0
		r.push += d.normalized() * push_strength if d.length() > 0.01 else Vector3(0, 0, push_strength)


## Obstacle impact: front of the crowd squashes, speed dips, some runners fly.
func hit_obstacle(barrier_z: float, loss: int) -> int:
	_compress = 1.0
	_speed_mult = 0.35
	var front := Vector3(center.x, 0, barrier_z)
	var lost := knock_from(front, loss, 3.5, 5.5, Vector3(0, 0, 1))
	stumble_near(front, 8, 0.9)
	return lost


func _launch(r: RunnerData, velocity: Vector3, life: float) -> void:
	if pool == null:
		return
	var xf := Transform3D(Basis(Vector3.UP, r.yaw), r.pos)
	var spin := Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-4, 4), _rng.randf_range(-6, 6))
	pool.spawn(r.look_data, xf, velocity, spin, life)
	if vfx:
		vfx.burst(&"hit", r.pos + Vector3(0, 1.0, 0))


func _set_count(n: int) -> void:
	n = clampi(n, 0, MAX_CROWD)
	if n == count:
		return
	var old := count
	count = n
	crowd_size_changed.emit(count, old)
	if count == 0 and old > 0:
		crowd_emptied.emit()


func _new_runner() -> RunnerData:
	var r := RunnerData.new()
	r.look_data = RunnerRig.random_look(_rng)
	r.phase = _rng.randf() * TAU
	r.cadence = _rng.randf_range(14.0, 16.5)
	r.follow = _rng.randf_range(6.5, 10.0)
	r.seed = _rng.randf() * 100.0
	return r


func _refresh_slots() -> void:
	_slots = Formation.slots(maxi(count, 1))
	_bounds = Formation.bounds(maxi(count, 1))
	_slots_dirty = true


## Assigns slots so runners closest to the centre take the centre slots
## (keeps the blob stable when runners are added / removed).
func _assign_slots() -> void:
	_slots_dirty = false
	var living: Array[RunnerData] = []
	for r in runners:
		if not r.dying:
			living.append(r)
	if mode == Mode.SWARM:
		_swarm_slots = Formation.swarm_slots(maxi(living.size(), 1), swarm_target, swarm_radius)
		living.sort_custom(func(a: RunnerData, b: RunnerData) -> bool:
			return a.pos.distance_squared_to(swarm_target) < b.pos.distance_squared_to(swarm_target))
		for k in living.size():
			living[k].slot = k
		return
	var c := center
	living.sort_custom(func(a: RunnerData, b: RunnerData) -> bool:
		var da := Vector2(a.pos.x - c.x, (a.pos.z - c.z) * 0.8).length_squared()
		var db := Vector2(b.pos.x - c.x, (b.pos.z - c.z) * 0.8).length_squared()
		if a.spawn_t < 1.0 and b.spawn_t >= 1.0:
			return false
		if b.spawn_t < 1.0 and a.spawn_t >= 1.0:
			return true
		return da < db)
	for k in living.size():
		living[k].slot = mini(k, _slots.size() - 1)


func _process_spawns(delta: float) -> void:
	if _spawn_queue <= 0:
		return
	_spawn_acc += _spawn_rate * delta
	var n := mini(int(_spawn_acc), _spawn_queue)
	if n <= 0:
		return
	_spawn_acc -= n
	var parents: Array[RunnerData] = []
	for r in runners:
		if not r.dying and r.spawn_t >= 1.0:
			parents.append(r)
	for k in n:
		var r := _new_runner()
		var base := center
		if not parents.is_empty():
			base = parents[_rng.randi() % parents.size()].pos
		var ang := _rng.randf() * TAU
		r.pos = base + Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(0.3, 0.7)
		r.spawn_t = 0.0
		r.phase = _rng.randf() * TAU
		runners.append(r)
		if vfx and k % 3 == 0:
			vfx.burst(&"spawn", r.pos + Vector3(0, 0.9, 0))
	_spawn_queue -= n
	if audio:
		audio.play_limited(&"pop", 0.05, -8.0, 1.0 + randf() * 0.3)
	_slots_dirty = true
	_custom_dirty = true


# ------------------------------------------------------------------ update
func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_time += delta
	_update_center(delta)
	_process_spawns(delta)
	if _slots_dirty:
		_assign_slots()
	_update_runners(delta)
	_update_sensor()


func _update_center(delta: float) -> void:
	_speed_mult = move_toward(_speed_mult, 1.0, delta * 1.1)
	_compress = move_toward(_compress, 0.0, delta * 1.6)
	match mode:
		Mode.RUN:
			forward_speed = lerpf(forward_speed, target_speed, 1.0 - exp(-delta * 3.0))
		Mode.HALT:
			var dist := center.z - halt_z
			var want := clampf(dist * 1.6, 0.0, target_speed)
			forward_speed = lerpf(forward_speed, want, 1.0 - exp(-delta * 4.0))
			if dist < 0.05:
				forward_speed = 0.0
		Mode.CHARGE:
			forward_speed = lerpf(forward_speed, target_speed, 1.0 - exp(-delta * 3.0))
			if get_front_z() <= swarm_target.z + swarm_radius + 3.0:
				set_mode(Mode.SWARM)
		Mode.SWARM, Mode.CELEBRATE:
			forward_speed = lerpf(forward_speed, 0.0, 1.0 - exp(-delta * 5.0))
	center.z -= forward_speed * _speed_mult * delta
	# steering: critically damped spring toward the drag target
	var lim := steer_limit()
	var tx := clampf(steer_target_x if input_enabled else 0.0, -lim, lim)
	if mode == Mode.SWARM or mode == Mode.CELEBRATE:
		tx = center.x
	var acc := steer_omega * steer_omega * (tx - center.x) - 2.0 * steer_omega * _steer_vel
	_steer_vel += acc * delta
	center.x = clampf(center.x + _steer_vel * delta, -lim, lim)


func _update_runners(delta: float) -> void:
	var fwd := -forward_speed * _speed_mult * delta
	var z_scale := 1.0 - 0.38 * _compress
	var anim_speed := clampf(forward_speed * _speed_mult / base_speed, 0.35, 1.25)
	var base_anim: int = RunnerRig.Anim.RUN
	if mode == Mode.HALT and forward_speed < 1.2:
		base_anim = RunnerRig.Anim.IDLE
	elif mode == Mode.CELEBRATE:
		base_anim = RunnerRig.Anim.VICTORY
	var rs := RenderingServer
	var i := 0
	var remove_list: Array[int] = []
	var h0 := _mm_rid[G.HAIR0]
	var h1 := _mm_rid[G.HAIR1]
	for idx in runners.size():
		var r := runners[idx]
		var sc := 1.0
		var hop := 0.0
		if r.dying:
			r.die_t += delta
			var k := r.die_t / 0.28
			if k >= 1.0:
				remove_list.append(idx)
				if vfx:
					vfx.burst(&"poof", r.pos + Vector3(0, 0.8, 0))
				sc = 0.0
			else:
				sc = 1.0 - k * k
				hop = sin(k * PI) * 0.35
			r.pos += r.push * delta * 3.0
			r.pos.z += fwd
		else:
			# ---- target position
			var tx: float
			var tz: float
			if mode == Mode.SWARM and r.slot < _swarm_slots.size():
				var sp := _swarm_slots[r.slot]
				tx = sp.x
				tz = sp.z
			else:
				var sl := _slots[mini(r.slot, _slots.size() - 1)]
				tx = center.x + sl.x + sin(_time * 0.9 + r.seed) * 0.07
				tz = center.z + sl.y * z_scale + cos(_time * 0.7 + r.seed) * 0.06
				if mode == Mode.CELEBRATE:
					tz = r.pos.z
					tx = r.pos.x
			# funnel runners through the chosen gate panel
			if funnel_side != 0 and absf(r.pos.z - funnel_z) < 5.0:
				if funnel_side > 0:
					tx = maxf(tx, 0.55)
				else:
					tx = minf(tx, -0.55)
			var prev_x := r.pos.x
			r.pos.z += fwd
			var follow := r.follow * (1.6 if mode == Mode.SWARM else 1.0)
			var kf := 1.0 - exp(-delta * follow)
			r.pos.x += (tx - r.pos.x) * kf
			r.pos.z += (tz - r.pos.z) * kf
			r.pos += r.push * delta * 4.0
			r.push = r.push.lerp(Vector3.ZERO, 1.0 - exp(-delta * 5.0))
			r.pos.x = clampf(r.pos.x, -ROAD_HALF_WIDTH + 0.3, ROAD_HALF_WIDTH - 0.3)
			var vx := (r.pos.x - prev_x) / maxf(delta, 0.0001)
			r.vx = lerpf(r.vx, vx, 1.0 - exp(-delta * 10.0))
			# ---- anim state
			r.anim_t += delta
			if r.anim == RunnerRig.Anim.HIT:
				if r.anim_t > 0.55:
					r.anim = RunnerRig.Anim.GET_UP if r.get_up else base_anim
					r.anim_t = 0.0
					r.get_up = false
			elif r.anim == RunnerRig.Anim.GET_UP:
				if r.anim_t > 0.6:
					r.anim = base_anim
					r.anim_t = 0.0
			elif mode == Mode.SWARM:
				var dist2 := Vector2(tx - r.pos.x, tz - r.pos.z).length_squared()
				var want: int = RunnerRig.Anim.ATTACK if dist2 < 1.0 else RunnerRig.Anim.RUN
				if r.anim != want:
					r.anim = want
					r.anim_t = 0.0
			elif r.anim != base_anim:
				r.anim = base_anim
				r.anim_t = 0.0
			if r.anim == RunnerRig.Anim.RUN or r.anim == RunnerRig.Anim.HIT or r.anim == RunnerRig.Anim.GET_UP:
				r.phase += delta * r.cadence * (anim_speed if mode != Mode.SWARM else 1.0)
			else:
				r.phase += delta * 2.0
			# ---- facing / lean (additive TURN_LEFT / TURN_RIGHT)
			var fwd_speed := maxf(forward_speed * _speed_mult, 3.0)
			var want_yaw := -atan2(r.vx, fwd_speed) * 0.8
			if mode == Mode.SWARM:
				var to := swarm_target - r.pos
				want_yaw = atan2(-to.x, -to.z)
			elif mode == Mode.CELEBRATE:
				want_yaw = sin(r.seed) * 0.6
			r.yaw = lerp_angle(r.yaw, want_yaw, 1.0 - exp(-delta * 8.0))
			r.lean = clampf(-r.vx / 7.0, -1.0, 1.0) if mode != Mode.SWARM else 0.0
			r.look = lerpf(r.look, r.look_target, 1.0 - exp(-delta * 6.0))
			# ---- spawn pop
			if r.spawn_t < 1.0:
				r.spawn_t = minf(1.0, r.spawn_t + delta / SPAWN_DURATION)
				var t := r.spawn_t
				sc = 1.0 + sin(t * PI * 1.5) * (1.0 - t) * 0.6 if t > 0.2 else t / 0.2
				hop = sin(t * PI) * 0.55
		# ---- write instances
		var ld := r.look_data
		var lw: float = ld["width"]
		var lh: float = ld["height"]
		var root := Transform3D(Basis(Vector3.UP, r.yaw).scaled(Vector3(lw * sc, lh * sc, lw * sc)), r.pos + Vector3(0, hop, 0))
		var pose := _get_pose(r)
		rs.multimesh_instance_set_transform(_mm_rid[G.BODY], i, root * pose[RunnerRig.Part.BODY])
		var head := root * pose[RunnerRig.Part.HEAD]
		rs.multimesh_instance_set_transform(_mm_rid[G.HEAD], i, head)
		if ld["hair_style"] == 0:
			rs.multimesh_instance_set_transform(h0, i, head)
			rs.multimesh_instance_set_transform(h1, i, _HIDDEN)
		else:
			rs.multimesh_instance_set_transform(h1, i, head)
			rs.multimesh_instance_set_transform(h0, i, _HIDDEN)
		var j := i * 2
		rs.multimesh_instance_set_transform(_mm_rid[G.ARM], j, root * pose[RunnerRig.Part.ARM_L])
		rs.multimesh_instance_set_transform(_mm_rid[G.ARM], j + 1, root * pose[RunnerRig.Part.ARM_R])
		rs.multimesh_instance_set_transform(_mm_rid[G.THIGH], j, root * pose[RunnerRig.Part.THIGH_L])
		rs.multimesh_instance_set_transform(_mm_rid[G.THIGH], j + 1, root * pose[RunnerRig.Part.THIGH_R])
		rs.multimesh_instance_set_transform(_mm_rid[G.SHIN], j, root * pose[RunnerRig.Part.SHIN_L])
		rs.multimesh_instance_set_transform(_mm_rid[G.SHIN], j + 1, root * pose[RunnerRig.Part.SHIN_R])
		var shadow_s := (1.0 - clampf(hop, 0.0, 0.6)) * sc * lw
		rs.multimesh_instance_set_transform(_mm_rid[G.SHADOW], i, Transform3D(Basis.from_scale(Vector3(shadow_s, 1, shadow_s)), Vector3(r.pos.x, 0.03, r.pos.z)))
		i += 1
	var n := runners.size()
	if _custom_dirty:
		_write_customs()
	for g in G.size():
		var mult := 2 if (g == G.ARM or g == G.THIGH or g == G.SHIN) else 1
		_mmi[g].multimesh.visible_instance_count = n * mult
	if not remove_list.is_empty():
		for k in range(remove_list.size() - 1, -1, -1):
			runners.remove_at(remove_list[k])
		_custom_dirty = true
		_slots_dirty = true


func _get_pose(r: RunnerData) -> Array[Transform3D]:
	if r.anim == RunnerRig.Anim.RUN and absf(r.look) < 0.01:
		var pi := int(fposmod(r.phase, TAU) / TAU * LUT_PHASES) % LUT_PHASES
		var li := clampi(int(round((r.lean + 1.0) * 0.5 * (LUT_LEANS - 1))), 0, LUT_LEANS - 1)
		return _run_lut[pi * LUT_LEANS + li]
	RunnerRig.pose_into(_pose, r.anim, r.phase, r.anim_t, r.lean, r.look)
	return _pose


## RUN poses depend only on (phase, lean) -> precomputed once. This makes the
## common case (a big running crowd) almost free.
func _build_run_lut() -> void:
	_run_lut.clear()
	for p in LUT_PHASES:
		for l in LUT_LEANS:
			var buf := RunnerRig.new_pose_buffer()
			var lean := lerpf(-1.0, 1.0, float(l) / float(LUT_LEANS - 1))
			RunnerRig.pose_into(buf, RunnerRig.Anim.RUN, TAU * float(p) / LUT_PHASES, 0.0, lean, 0.0)
			_run_lut.append(buf)


func _write_customs() -> void:
	_custom_dirty = false
	var rs := RenderingServer
	for i in runners.size():
		var ld := runners[i].look_data
		var skin: float = ld["skin"]
		var shirt: Color = ld["shirt"]
		var pants: Color = ld["pants"]
		var hair: Color = ld["hair"]
		var cs := Color(shirt.r, shirt.g, shirt.b, skin)
		var cp := Color(pants.r, pants.g, pants.b, skin)
		var ch := Color(hair.r, hair.g, hair.b, skin)
		rs.multimesh_instance_set_custom_data(_mm_rid[G.BODY], i, cs)
		rs.multimesh_instance_set_custom_data(_mm_rid[G.HEAD], i, cs)
		rs.multimesh_instance_set_custom_data(_mm_rid[G.HAIR0], i, ch)
		rs.multimesh_instance_set_custom_data(_mm_rid[G.HAIR1], i, ch)
		rs.multimesh_instance_set_custom_data(_mm_rid[G.ARM], i * 2, cs)
		rs.multimesh_instance_set_custom_data(_mm_rid[G.ARM], i * 2 + 1, cs)
		rs.multimesh_instance_set_custom_data(_mm_rid[G.THIGH], i * 2, cp)
		rs.multimesh_instance_set_custom_data(_mm_rid[G.THIGH], i * 2 + 1, cp)
		rs.multimesh_instance_set_custom_data(_mm_rid[G.SHIN], i * 2, cp)
		rs.multimesh_instance_set_custom_data(_mm_rid[G.SHIN], i * 2 + 1, cp)


func _update_sensor() -> void:
	if _sensor == null:
		return
	_sensor_shape.size = Vector3(_bounds.x * 2.0, 2.0, _bounds.z - _bounds.y)
	_sensor.global_position = Vector3(center.x, 1.0, center.z + (_bounds.y + _bounds.z) * 0.5)


func _build_multimeshes() -> void:
	var names := [&"body", &"head", &"hair_0", &"hair_1", &"arm", &"thigh", &"shin", &"shadow"]
	var cap := MAX_CROWD + 8
	for g in G.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var is_shadow: bool = g == G.SHADOW
		mm.use_custom_data = not is_shadow
		var mult := 2 if (g == G.ARM or g == G.THIGH or g == G.SHIN) else 1
		if is_shadow:
			mm.mesh = _shadow_mesh()
		else:
			mm.mesh = RunnerRig.mesh(names[g])
		mm.instance_count = cap * mult
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_%s" % names[g]
		mmi.multimesh = mm
		if is_shadow:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mmi.material_override = Palette.runner_crowd_material()
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# the crowd moves a lot: generous cull margin instead of AABB updates
		mmi.extra_cull_margin = 4.0
		add_child(mmi)
		_mmi.append(mmi)
		_mm_rid.append(mm.get_rid())


func _shadow_mesh() -> Mesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	q.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = Palette.soft_circle_texture()
	m.albedo_color = Color(0.0, 0.0, 0.05, 0.45)
	m.render_priority = -1
	q.material = m
	return q


func visible_runner_count() -> int:
	return runners.size()
