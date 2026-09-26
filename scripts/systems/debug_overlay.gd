class_name DebugOverlay
extends CanvasLayer
## Development-only overlay: FPS, crowd count, active physics actors, state.
## Toggle with F6. Disabled automatically in release exports
## (GameManager.debug_tools_enabled + OS.is_debug_build()).

var game: GameManager
var _label: Label
var _acc := 0.0


func _ready() -> void:
	layer = 20
	_label = Label.new()
	_label.position = Vector2(12, 90)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func setup(gm: GameManager) -> void:
	game = gm


func _process(delta: float) -> void:
	if not visible or game == null:
		return
	_acc += delta
	if _acc < 0.25:
		return
	_acc = 0.0
	var c := game.crowd
	_label.text = "FPS %d\nCrowd %d (visual %d)\nPhysics actors %d\nState %s\nDraw calls %d\nF1 reset  F2 +10  F3 -10\nF4 boss  F5 x2  F6 overlay" % [
		Engine.get_frames_per_second(),
		c.count,
		c.visible_runner_count(),
		game.pool.active_count(),
		GameManager.State.keys()[game.state],
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	]
