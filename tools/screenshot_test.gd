extends SceneTree
## Renders the level and saves screenshots at given times (visual regression aid).
## Run (needs a display, e.g. xvfb-run):
##   godot --path . --fixed-fps 30 -s tools/screenshot_test.gd -- out=/tmp/shots times=1,2.5,4
## Uses the same simple steering bot as autoplay_test.gd.

var main: GameManager
var t := 0.0
var times: Array[float] = []
var out_dir := "user://shots"
var _idx := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_dir = a.substr(4)
		elif a.begins_with("times="):
			for s in a.substr(6).split(","):
				times.append(float(s))
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	if main.state == GameManager.State.PLAYING:
		var g: Gate = main.gate_manager.next_gate()
		if g:
			var c := main.crowd.count
			var l := Gate.apply_op(g.left_op, g.left_value, c)
			var r := Gate.apply_op(g.right_op, g.right_value, c)
			main.input._set_target((-1.0 if l >= r else 1.0) * 3.6)
	if _idx < times.size() and t >= times[_idx]:
		var img := root.get_viewport().get_texture().get_image()
		var path := "%s/shot_%05.1f.png" % [out_dir, times[_idx]]
		img.save_png(path)
		print("saved ", path)
		_idx += 1
	if _idx >= times.size():
		quit()
	return false
