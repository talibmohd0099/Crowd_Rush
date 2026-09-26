class_name HUD
extends CanvasLayer
## UIManager: minimal, anchored, mobile-readable HUD.
##  - top centre crowd counter (animated count, gain/loss colour flash)
##  - gate delta line ("+10", "×2!  10 > 20") under the counter
##  - START -> BOSS progress track
##  - boss health bar
##  - cinematic text, letterbox bars, fade
##  - result panel (LEVEL COMPLETE / YOUR CROWD IS GONE) with one button

signal restart_pressed

const TEXT := Color(1, 1, 1)
const OUTLINE := Color(0.04, 0.05, 0.12)

var _root: Control
var _font: Font
var _counter: PanelContainer
var _count_label: Label
var _delta_box: HBoxContainer
var _delta_op: Label
var _delta_from: Label
var _delta_arrow: Control
var _delta_to: Label
var _progress: Control
var _progress_value := 0.0
var _boss_box: VBoxContainer
var _boss_bar: Control
var _boss_ratio := 1.0
var _boss_lag := 1.0
var _cine_label: Label
var _banner: Label
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _fade: ColorRect
var _result: PanelContainer
var _result_title: Label
var _result_line1: Label
var _result_line2: Label
var _result_button: Button
var _shown_count := 0.0
var _target_count := 0
var _count_tween: Tween
var _cine_tween: Tween


func _ready() -> void:
	layer = 10
	_font = Palette.font()
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = _font
	_root.theme = theme
	add_child(_root)
	_build_letterbox()
	_build_counter()
	_build_boss_bar()
	_build_texts()
	_build_result()
	_build_fade()
	set_gameplay_visible(false, 0.0)


# ------------------------------------------------------------------ API
func set_gameplay_visible(on: bool, fade := 0.35) -> void:
	for c: CanvasItem in [_counter, _progress, _delta_box]:
		if fade <= 0.0:
			c.modulate.a = 1.0 if on else 0.0
		else:
			create_tween().tween_property(c, "modulate:a", 1.0 if on else 0.0, fade)


func set_count(n: int, animate := true) -> void:
	var old := _target_count
	_target_count = n
	if not animate:
		_shown_count = n
		_count_label.text = str(n)
		return
	if _count_tween and _count_tween.is_valid():
		_count_tween.kill()
	_count_tween = create_tween()
	_count_tween.tween_method(_set_shown, _shown_count, float(n), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# bounce + colour flash
	var col := Color(0.55, 1.0, 0.6) if n > old else Color(1.0, 0.45, 0.45)
	_count_label.pivot_offset = _count_label.size * 0.5
	var tw := create_tween()
	tw.tween_property(_count_label, "scale", Vector2.ONE * 1.35, 0.08)
	tw.parallel().tween_property(_count_label, "modulate", col, 0.08)
	tw.tween_property(_count_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_count_label, "modulate", Color.WHITE, 0.45)


func show_gate_delta(op: int, value: int, old: int, new_count: int) -> void:
	var col := Gate.op_color(op)
	_delta_op.text = Gate.op_text(op, value) + ("!" if op == Gate.Op.MUL else "")
	_delta_op.add_theme_color_override("font_color", col.lightened(0.25))
	_delta_from.text = str(old)
	_delta_to.text = str(new_count)
	_delta_to.add_theme_color_override("font_color", col.lightened(0.35))
	_delta_arrow.modulate = col.lightened(0.3)
	_delta_box.pivot_offset = _delta_box.size * 0.5
	_delta_box.modulate.a = 0.0
	_delta_box.scale = Vector2.ONE * 0.6
	_delta_box.visible = true
	var tw := create_tween()
	tw.tween_property(_delta_box, "modulate:a", 1.0, 0.08)
	tw.parallel().tween_property(_delta_box, "scale", Vector2.ONE * 1.1, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_delta_box, "scale", Vector2.ONE, 0.15)
	tw.tween_interval(0.55)
	tw.tween_property(_delta_box, "modulate:a", 0.0, 0.25)


func set_progress(v: float) -> void:
	_progress_value = clampf(v, 0.0, 1.0)
	_progress.queue_redraw()


func show_boss_bar(on: bool) -> void:
	_boss_box.visible = true
	create_tween().tween_property(_boss_box, "modulate:a", 1.0 if on else 0.0, 0.4)
	create_tween().tween_property(_progress, "modulate:a", 0.0 if on else 1.0, 0.3)


func set_boss_health(ratio: float) -> void:
	_boss_ratio = clampf(ratio, 0.0, 1.0)
	_boss_bar.queue_redraw()


func show_cinematic_text(text: String) -> void:
	if _cine_tween and _cine_tween.is_valid():
		_cine_tween.kill()
	_cine_label.text = text
	_cine_label.pivot_offset = _cine_label.size * 0.5
	_cine_label.modulate.a = 0.0
	_cine_label.scale = Vector2.ONE * 0.86
	_cine_tween = create_tween()
	_cine_tween.tween_property(_cine_label, "modulate:a", 1.0, 0.16)
	_cine_tween.parallel().tween_property(_cine_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cine_tween.tween_property(_cine_label, "scale", Vector2.ONE * 1.04, 1.2)


func hide_cinematic_text(fade := 0.2) -> void:
	if _cine_tween and _cine_tween.is_valid():
		_cine_tween.kill()
	_cine_tween = create_tween()
	_cine_tween.tween_property(_cine_label, "modulate:a", 0.0, fade)


func show_banner(text: String, color := Color(1, 0.85, 0.3), hold := 1.0) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.pivot_offset = _banner.size * 0.5
	_banner.modulate.a = 0.0
	_banner.scale = Vector2.ONE * 1.6
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.3)


func set_letterbox(on: bool, dur := 0.5) -> void:
	var h := 72.0 if on else 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_bar_top, "custom_minimum_size:y", h, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_bar_bottom, "custom_minimum_size:y", h, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func fade_from_black(dur := 1.0) -> void:
	_fade.modulate.a = 1.0
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 0.0, dur).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: _fade.visible = false)


func set_black(on: bool) -> void:
	_fade.visible = on
	_fade.modulate.a = 1.0 if on else 0.0


func show_victory(survived: int, best: int) -> void:
	_show_result("LEVEL COMPLETE", Color(1.0, 0.85, 0.25), "CROWD SURVIVED: %d" % survived, "BEST: %d" % best, "PLAY AGAIN")


func show_failure() -> void:
	_show_result("YOUR CROWD IS GONE", Color(1.0, 0.4, 0.4), "Pick the bright gates!", "", "RETRY")


# ------------------------------------------------------------------ internals
func _set_shown(v: float) -> void:
	_shown_count = v
	_count_label.text = str(int(round(v)))


func _process(delta: float) -> void:
	if _boss_box.visible and absf(_boss_lag - _boss_ratio) > 0.001:
		_boss_lag = move_toward(_boss_lag, _boss_ratio, delta * 0.6)
		_boss_bar.queue_redraw()


func _label(text: String, size: int, outline := 12, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel_style(bg: Color, radius := 24) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _build_letterbox() -> void:
	_bar_top = ColorRect.new()
	_bar_top.color = Color.BLACK
	_bar_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar_top.custom_minimum_size = Vector2(0, 72)
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar_top)
	_bar_bottom = ColorRect.new()
	_bar_bottom.color = Color.BLACK
	_bar_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar_bottom.custom_minimum_size = Vector2(0, 72)
	_bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar_bottom)


func _build_counter() -> void:
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 14
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top)

	_counter = PanelContainer.new()
	_counter.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.06, 0.16, 0.55), 30))
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(_counter)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(34, 44)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func() -> void:
		var c := Color(0.55, 0.85, 1.0)
		icon.draw_circle(Vector2(17, 11), 8.5, c)
		icon.draw_rect(Rect2(6, 22, 22, 18), c)
		icon.draw_circle(Vector2(17, 23), 11.0, c))
	row.add_child(icon)
	var cap := _label("CROWD", 28, 8, Color(0.75, 0.88, 1.0))
	row.add_child(cap)
	_count_label = _label("5", 58, 14)
	_count_label.custom_minimum_size = Vector2(96, 0)
	row.add_child(_count_label)

	# delta line: "+10   5 > 15"
	_delta_box = HBoxContainer.new()
	_delta_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_delta_box.add_theme_constant_override("separation", 10)
	_delta_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_delta_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(_delta_box)
	_delta_op = _label("+10", 46, 12)
	_delta_from = _label("5", 34, 10, Color(0.85, 0.88, 0.95))
	_delta_arrow = Control.new()
	_delta_arrow.custom_minimum_size = Vector2(26, 26)
	_delta_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_delta_arrow.draw.connect(func() -> void:
		var pts := PackedVector2Array([Vector2(2, 5), Vector2(24, 13), Vector2(2, 21)])
		_delta_arrow.draw_colored_polygon(pts, Color.WHITE))
	_delta_to = _label("15", 40, 12)
	for c in [_delta_op, _delta_from, _delta_arrow, _delta_to]:
		_delta_box.add_child(c)
	_delta_box.modulate.a = 0.0

	# progress track
	_progress = Control.new()
	_progress.custom_minimum_size = Vector2(360, 26)
	_progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.draw.connect(_draw_progress)
	top.add_child(_progress)
	top.move_child(_progress, 1)


func _draw_progress() -> void:
	var w := _progress.size.x
	var y := 13.0
	_progress.draw_line(Vector2(12, y), Vector2(w - 16, y), Color(0, 0, 0, 0.45), 9.0, true)
	_progress.draw_line(Vector2(12, y), Vector2(w - 16, y), Color(1, 1, 1, 0.35), 5.0, true)
	var px := lerpf(12.0, w - 16.0, _progress_value)
	_progress.draw_line(Vector2(12, y), Vector2(px, y), Color(0.45, 0.85, 1.0), 5.0, true)
	_progress.draw_circle(Vector2(12, y), 6.0, Color(1, 1, 1))
	# boss marker: red disc with little horns
	var bx := w - 12.0
	_progress.draw_circle(Vector2(bx, y), 11.0, Color(0.1, 0.02, 0.02))
	_progress.draw_circle(Vector2(bx, y), 9.0, Color(0.95, 0.2, 0.18))
	_progress.draw_colored_polygon(PackedVector2Array([Vector2(bx - 8, y - 5), Vector2(bx - 11, y - 14), Vector2(bx - 3, y - 8)]), Color(0.95, 0.2, 0.18))
	_progress.draw_colored_polygon(PackedVector2Array([Vector2(bx + 8, y - 5), Vector2(bx + 11, y - 14), Vector2(bx + 3, y - 8)]), Color(0.95, 0.2, 0.18))
	# crowd marker
	_progress.draw_circle(Vector2(px, y), 8.5, Color(0.04, 0.06, 0.16))
	_progress.draw_circle(Vector2(px, y), 6.5, Color(0.55, 0.9, 1.0))


func _build_boss_bar() -> void:
	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boss_box.position.y = 112
	_boss_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_boss_box.add_theme_constant_override("separation", 0)
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_boss_box)
	var name_l := _label("GIANT GUARD", 30, 10, Color(1.0, 0.75, 0.7))
	_boss_box.add_child(name_l)
	_boss_bar = Control.new()
	_boss_bar.custom_minimum_size = Vector2(520, 30)
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, _boss_bar.size)
		_boss_bar.draw_rect(r.grow(4), Color(0.04, 0.02, 0.04, 0.8))
		_boss_bar.draw_rect(r, Color(0.25, 0.05, 0.07))
		_boss_bar.draw_rect(Rect2(r.position, Vector2(r.size.x * _boss_lag, r.size.y)), Color(1.0, 0.9, 0.75))
		_boss_bar.draw_rect(Rect2(r.position, Vector2(r.size.x * _boss_ratio, r.size.y)), Color(0.95, 0.18, 0.2))
		_boss_bar.draw_rect(Rect2(r.position, Vector2(r.size.x * _boss_ratio, r.size.y * 0.35)), Color(1, 1, 1, 0.2)))
	_boss_box.add_child(_boss_bar)
	_boss_box.modulate.a = 0.0
	_boss_box.visible = false


func _build_texts() -> void:
	_cine_label = _label("", 104, 20)
	_cine_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_cine_label.offset_top = 110
	_cine_label.offset_bottom = 250
	_cine_label.modulate.a = 0.0
	_root.add_child(_cine_label)
	_banner = _label("", 76, 18, Color(1, 0.85, 0.3))
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.offset_top = -120
	_banner.modulate.a = 0.0
	_root.add_child(_banner)


func _build_result() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_result = PanelContainer.new()
	var sb := _panel_style(Color(0.04, 0.06, 0.16, 0.82), 36)
	sb.content_margin_left = 60
	sb.content_margin_right = 60
	sb.content_margin_top = 30
	sb.content_margin_bottom = 34
	sb.border_color = Color(1, 1, 1, 0.15)
	sb.set_border_width_all(3)
	_result.add_theme_stylebox_override("panel", sb)
	center.add_child(_result)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_result.add_child(v)
	_result_title = _label("LEVEL COMPLETE", 80, 18, Color(1.0, 0.85, 0.25))
	_result_line1 = _label("", 46, 12)
	_result_line2 = _label("", 36, 10, Color(0.75, 0.88, 1.0))
	v.add_child(_result_title)
	v.add_child(_result_line1)
	v.add_child(_result_line2)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	v.add_child(spacer)
	_result_button = Button.new()
	_result_button.text = "PLAY AGAIN"
	_result_button.custom_minimum_size = Vector2(360, 96)
	_result_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_result_button.add_theme_font_size_override("font_size", 52)
	_result_button.add_theme_color_override("font_color", Color(0.1, 0.12, 0.2))
	_result_button.add_theme_color_override("font_hover_color", Color(0.1, 0.12, 0.2))
	_result_button.add_theme_color_override("font_pressed_color", Color(0.1, 0.12, 0.2))
	_result_button.add_theme_color_override("font_focus_color", Color(0.1, 0.12, 0.2))
	var bn := _panel_style(Color(0.35, 0.9, 0.5), 28)
	bn.shadow_color = Color(0, 0, 0, 0.35)
	bn.shadow_offset = Vector2(0, 6)
	bn.shadow_size = 4
	var bh := bn.duplicate() as StyleBoxFlat
	bh.bg_color = Color(0.45, 1.0, 0.6)
	var bp := bn.duplicate() as StyleBoxFlat
	bp.bg_color = Color(0.25, 0.75, 0.4)
	_result_button.add_theme_stylebox_override("normal", bn)
	_result_button.add_theme_stylebox_override("hover", bh)
	_result_button.add_theme_stylebox_override("pressed", bp)
	_result_button.add_theme_stylebox_override("focus", bh)
	_result_button.pressed.connect(func() -> void: restart_pressed.emit())
	v.add_child(_result_button)
	_result.visible = false


func _show_result(title: String, title_col: Color, line1: String, line2: String, button: String) -> void:
	_result_title.text = title
	_result_title.add_theme_color_override("font_color", title_col)
	_result_line1.text = line1
	_result_line2.text = line2
	_result_line2.visible = line2 != ""
	_result_button.text = button
	_result.visible = true
	_result.pivot_offset = _result.size * 0.5
	_result.scale = Vector2.ONE * 0.5
	_result.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_result, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(_result, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# the button breathes a little to invite the replay
	var bt := create_tween().set_loops()
	bt.tween_interval(0.6)
	bt.tween_callback(func() -> void: _result_button.pivot_offset = _result_button.size * 0.5)
	bt.tween_property(_result_button, "scale", Vector2.ONE * 1.06, 0.45).set_trans(Tween.TRANS_SINE)
	bt.tween_property(_result_button, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)


func _build_fade() -> void:
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	_root.add_child(_fade)
