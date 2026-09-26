extends SceneTree
## CPU micro-benchmark of the crowd update (animation + MultiMesh writes).
## Run: godot --headless --path . -s tools/perf_test.gd
## Prints average ms per crowd update for several crowd sizes. Mobile CPUs are
## roughly 3-5x slower than a desktop core - budget accordingly.

var main: GameManager
var _frame := 0


func _initialize() -> void:
	main = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	var crowd := main.crowd
	crowd.process_mode = Node.PROCESS_MODE_DISABLED
	for n in [5, 30, 80, 150]:
		crowd.reset_crowd(Vector3(0, 0, -60), n)
		crowd.forward_speed = 10.0
		crowd.target_speed = 10.0
		crowd.input_enabled = true
		for i in 30:
			crowd._process(1.0 / 60.0)
		var t0 := Time.get_ticks_usec()
		var frames := 300
		for i in frames:
			crowd.set_steer_target(sin(i * 0.05) * 3.0)
			crowd._process(1.0 / 60.0)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
		print("crowd %3d : %.3f ms / update" % [n, ms])
	# worst case: everyone in a non-cached pose (victory)
	crowd.reset_crowd(Vector3(0, 0, -60), 150)
	crowd.celebrate()
	var t1 := Time.get_ticks_usec()
	for i in 300:
		crowd._process(1.0 / 60.0)
	print("crowd 150 (VICTORY, uncached poses): %.3f ms / update" % ((Time.get_ticks_usec() - t1) / 1000.0 / 300))
	quit()
	return true
