extends SceneTree
## Headless smoke test: plays the whole level with a simple "bot" that steers
## toward the better gate, logs progress, and exits with code 0 on victory.
## Run:  godot --headless --path . --fixed-fps 60 -s tools/autoplay_test.gd
## Optional: `-- worst` picks the worse gate every time (tests failure),
## `-- replay` starts like PLAY AGAIN does (intro skipped).

var main: GameManager
var t := 0.0
var _log_t := 0.0
var _won_t := -1.0
var _worst := false
var _last_state := -1
var _frame_us_total := 0
var _frames := 0
var _max_count := 0


func _initialize() -> void:
	_worst = OS.get_cmdline_user_args().has("worst")
	if OS.get_cmdline_user_args().has("replay"):
		SaveData.intro_seen = true # simulate PLAY AGAIN (intro skipped)
	main = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(main)


func _hook() -> void:
	main.gate_manager.gate_passed.connect(func(_g: Gate, op: int, value: int, old: int, n: int) -> void:
		print("  [t=%.1f] GATE %s -> %d => %d" % [t, Gate.op_text(op, value), old, n]))


func _process(delta: float) -> bool:
	var start := Time.get_ticks_usec()
	if t == 0.0:
		_hook()
	t += delta
	if main.state != _last_state:
		_last_state = main.state
		print("[t=%.2f] STATE %s  crowd=%d z=%.1f" % [t, GameManager.State.keys()[main.state], main.crowd.count, main.crowd.center.z])
	if main.state == GameManager.State.PLAYING:
		var g: Gate = main.gate_manager.next_gate()
		if g:
			var c := main.crowd.count
			var l := Gate.apply_op(g.left_op, g.left_value, c)
			var r := Gate.apply_op(g.right_op, g.right_value, c)
			var side := -1.0 if l >= r else 1.0
			if _worst:
				side = -side
			main.input._set_target(side * 3.6)
	_max_count = maxi(_max_count, main.crowd.count)
	_log_t += delta
	if _log_t >= 2.0:
		_log_t = 0.0
		print("[t=%.1f] crowd=%d visual=%d actors=%d z=%.1f x=%.2f boss_hp=%.1f" % [t, main.crowd.count, main.crowd.visible_runner_count(), main.pool.active_count(), main.crowd.center.z, main.crowd.center.x, main.level.boss.hp])
	if main.state == GameManager.State.VICTORY or main.state == GameManager.State.FAILED:
		if _won_t < 0.0:
			_won_t = t
		elif t - _won_t > 3.0:
			print("RESULT %s at t=%.1f crowd=%d max_crowd=%d avg_frame_ms=%.3f" % [GameManager.State.keys()[main.state], t, main.crowd.count, _max_count, _frame_us_total / 1000.0 / maxf(_frames, 1)])
			quit(0 if main.state == GameManager.State.VICTORY else 2)
	if t > 150.0:
		print("TIMEOUT state=%s" % GameManager.State.keys()[main.state])
		quit(1)
	_frame_us_total += Time.get_ticks_usec() - start
	_frames += 1
	return false
