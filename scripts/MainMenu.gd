extends Node2D

var _float_timer:   float   = 0.0
var _sprite:        Sprite2D
var _char_label:    Label   = null
var _canvas:        CanvasLayer
var _select_panel:  Control = null
var _wukong_sprite: Sprite2D = null
var _diff_btns:     Array    = []

const _DEV_SEQ := [KEY_M, KEY_E, KEY_L, KEY_U, KEY_S, KEY_I, KEY_N, KEY_E]
var _dev_seq_buf:  Array   = []
var _dev_unlocked: bool    = false
var _dev_row:      Control = null
var _dummy_row:    Control = null

var _settings_panel:   Control = null
var _bgm_player:       AudioStreamPlayer = null
var _vol_lbl:          Label   = null
var _import_status_lbl: Label  = null
var _config         := ConfigFile.new()
const _CONFIG_PATH  := "user://settings.cfg"

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.02, 0.04, 0.13))
	_load_settings()
	_setup_ui()
	_setup_bgm()


func _process(delta: float) -> void:
	_float_timer += delta
	if is_instance_valid(_sprite):
		_sprite.position.y = 370.0 + sin(_float_timer * 1.4) * 6.0
		_sprite.visible = Global.selected_character == "mascot"
	if is_instance_valid(_wukong_sprite):
		_wukong_sprite.position.y = 370.0 + sin(_float_timer * 1.4) * 6.0
		_wukong_sprite.visible = Global.selected_character == "wukong"
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_ESCAPE:
			if is_instance_valid(_select_panel):
				_select_panel.queue_free()
				_select_panel = null
				return
			if is_instance_valid(_settings_panel):
				_settings_panel.queue_free()
				_settings_panel = null
				return
		if is_instance_valid(_settings_panel) and not _dev_unlocked:
			_dev_seq_buf.append(event.keycode)
			if _dev_seq_buf.size() > _DEV_SEQ.size():
				_dev_seq_buf.pop_front()
			if _dev_seq_buf == _DEV_SEQ:
				_dev_seq_buf.clear()
				_dev_unlocked = true
				if is_instance_valid(_dev_row):
					_dev_row.visible = true

# ─── 背景格線 + 漂浮敵人 ──────────────────────────────────────
func _draw() -> void:
	var vp := get_viewport_rect().size
	var cell := 64.0
	var gc := Color(0.0, 0.42, 0.68, 0.22)
	var cols := int(vp.x / cell) + 2
	var rows := int(vp.y / cell) + 2
	for i in cols:
		draw_line(Vector2(i * cell, 0.0), Vector2(i * cell, vp.y), gc, 1.0)
	for i in rows:
		draw_line(Vector2(0.0, i * cell), Vector2(vp.x, i * cell), gc, 1.0)

	# 平台光暈
	draw_circle(Vector2(640.0, 390.0), 72.0, Color(0.0, 0.55, 1.0, 0.12))
	draw_circle(Vector2(640.0, 390.0), 55.0, Color(0.0, 0.7, 1.0, 0.10))
	var pts: PackedVector2Array
	for i in 36:
		var a: float = i / 36.0 * TAU
		pts.append(Vector2(640.0 + cos(a) * 68.0, 400.0 + sin(a) * 18.0))
	draw_colored_polygon(pts, Color(0.0, 0.5, 1.0, 0.22))

	# 漂浮敵人
	_draw_enemy(Vector2(200.0 + sin(_float_timer * 0.7) * 14.0,
						285.0 + cos(_float_timer * 0.5) * 9.0), 2)
	_draw_enemy(Vector2(1070.0 + cos(_float_timer * 0.6) * 11.0,
						265.0 + sin(_float_timer * 0.8) * 11.0), 1)
	_draw_enemy(Vector2(175.0 + sin(_float_timer * 0.9) * 9.0,
						440.0 + cos(_float_timer * 0.4) * 13.0), 0)


func _draw_enemy(pos: Vector2, etype: int) -> void:
	var a := 0.7
	match etype:
		0:
			draw_rect(Rect2(pos + Vector2(-10.0, -14.0), Vector2(20.0, 28.0)),
					Color(0.88, 0.91, 0.95, a), true)
			draw_rect(Rect2(pos + Vector2(-10.0, -14.0), Vector2(20.0, 28.0)),
					Color(0.5, 0.55, 0.65, a), false, 1.5)
			for i in 3:
				draw_line(pos + Vector2(-7.0, -3.0 + i * 6.0),
						pos + Vector2(7.0, -3.0 + i * 6.0),
						Color(0.55, 0.6, 0.72, a), 1.5)
		1:
			draw_rect(Rect2(pos + Vector2(-12.0, -12.0), Vector2(11.0, 6.0)),
					Color(0.7, 0.54, 0.33, a), true)
			draw_rect(Rect2(pos + Vector2(-12.0, -7.0), Vector2(24.0, 18.0)),
					Color(0.82, 0.64, 0.4, a), true)
			draw_rect(Rect2(pos + Vector2(-12.0, -7.0), Vector2(24.0, 18.0)),
					Color(0.5, 0.36, 0.16, a), false, 1.5)
		2:
			draw_rect(Rect2(pos + Vector2(-12.0, -14.0), Vector2(24.0, 28.0)),
					Color(0.9, 0.92, 0.96, a), true)
			draw_rect(Rect2(pos + Vector2(-12.0, -14.0), Vector2(24.0, 28.0)),
					Color(0.4, 0.45, 0.62, a), false, 2.0)
			draw_circle(pos + Vector2(0.0, -3.5), 6.5, Color(0.22, 0.27, 0.48, a))
			draw_circle(pos + Vector2(0.0, -3.5), 4.5, Color(0.9, 0.92, 0.96, a))
			draw_circle(pos + Vector2(0.0, 7.5), 2.8, Color(0.22, 0.27, 0.48, a))


# ─── UI 建立 ────────────────────────────────────────────────
func _setup_ui() -> void:
	# 角色 Sprite（世界座標，吉祥物用）
	_sprite = Sprite2D.new()
	_sprite.texture  = load("res://assets/吉祥物姿勢-01.png")
	_sprite.scale    = Vector2(0.12, 0.12)
	_sprite.position = Vector2(640.0, 370.0)
	_sprite.material = _chroma_material()
	add_child(_sprite)

	_wukong_sprite = Sprite2D.new()
	_wukong_sprite.texture  = load("res://assets/站立.png")
	_wukong_sprite.scale    = Vector2(0.18, 0.18)
	_wukong_sprite.position = Vector2(640.0, 370.0)
	_wukong_sprite.visible  = Global.selected_character == "wukong"
	add_child(_wukong_sprite)

	_canvas = CanvasLayer.new()
	add_child(_canvas)

	# ── 標題 ──
	var title := Label.new()
	title.text = "智生活"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 88)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 55.0
	title.offset_bottom = 155.0
	_canvas.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "知識生存"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 30)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 150.0
	subtitle.offset_bottom = 190.0
	_canvas.add_child(subtitle)

	# ── 按鈕列 ──
	var btn_row := HBoxContainer.new()
	btn_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.offset_top = -165.0
	btn_row.offset_bottom = -100.0
	btn_row.add_theme_constant_override("separation", 30)
	_canvas.add_child(btn_row)

	var btn_start := _make_button("開始遊戲")
	btn_start.pressed.connect(_on_start)
	btn_row.add_child(btn_start)

	var btn_char := _make_button("角色選擇")
	btn_char.pressed.connect(_on_char_select)
	btn_row.add_child(btn_char)

	var btn_settings := _make_button("設定")
	btn_settings.pressed.connect(_on_settings)
	btn_row.add_child(btn_settings)

	# ── 目前角色指示 ──
	# 難度選擇
	var diff_row := HBoxContainer.new()
	diff_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	diff_row.alignment   = BoxContainer.ALIGNMENT_CENTER
	diff_row.offset_top    = -235.0
	diff_row.offset_bottom = -185.0
	diff_row.add_theme_constant_override("separation", 10)
	_canvas.add_child(diff_row)

	var _diff_data := [
		["easy",   "簡單", Color(0.15, 0.88, 0.35)],
		["normal", "普通", Color(0.2,  0.65, 1.0)],
		["hard",   "困難", Color(1.0,  0.65, 0.15)],
		["hell",   "地獄", Color(0.9,  0.1,  0.15)],
	]
	for d in _diff_data:
		var db := Button.new()
		db.text = d[1] as String
		db.custom_minimum_size = Vector2(108.0, 48.0)
		db.add_theme_font_size_override("font_size", 18)
		db.add_theme_color_override("font_color", Color.WHITE)
		var dc: Color = d[2] as Color
		var did: String = d[0] as String
		db.add_theme_stylebox_override("normal",  _diff_style(dc, did == Global.difficulty))
		db.add_theme_stylebox_override("hover",   _diff_style(dc, true))
		db.add_theme_stylebox_override("pressed", _diff_style(dc, true))
		db.pressed.connect(_on_difficulty_picked.bind(did))
		diff_row.add_child(db)
		_diff_btns.append(db)

	_char_label = Label.new()
	_char_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_char_label.offset_top    = -95.0
	_char_label.offset_bottom = -65.0
	_char_label.add_theme_font_size_override("font_size", 16)
	_char_label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	_char_label.text = "目前角色：AI 吉祥物"
	_canvas.add_child(_char_label)

	# ── 版本提示 ──
	var tip := Label.new()
	tip.text = "WASD 移動  |  自動攻擊  |  ESC 暫停  |  撐過 3:45 擊敗 BOSS！"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 15)
	tip.add_theme_color_override("font_color", Color(0.45, 0.65, 0.85, 0.75))
	tip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	tip.offset_top = -40.0
	tip.offset_bottom = -10.0
	_canvas.add_child(tip)

func _make_button(txt: String) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(190.0, 60.0)
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color(0.8, 0.93, 1.0))
	btn.add_theme_stylebox_override("normal",  _btn_style(Color(0.07, 0.18, 0.48, 0.92), Color(0.3, 0.58, 1.0)))
	btn.add_theme_stylebox_override("hover",   _btn_style(Color(0.14, 0.32, 0.72, 0.97), Color(0.5, 0.78, 1.0)))
	btn.add_theme_stylebox_override("pressed", _btn_style(Color(0.05, 0.12, 0.36, 0.97), Color(0.2, 0.48, 0.9)))
	return btn

func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	return s

func _chroma_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float gr = col.g - max(col.r, col.b);
	float mask = step(gr, 0.28);
	COLOR = vec4(col.rgb, col.a * mask);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat

# ─── 角色選擇面板 ──────────────────────────────────────────
func _on_char_select() -> void:
	if is_instance_valid(_select_panel):
		_select_panel.queue_free()

	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_select_panel = panel
	_canvas.add_child(panel)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.04, 0.14, 0.92)
	panel.add_child(bg)

	var title := Label.new()
	title.text = "選  擇  角  色"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top    = 90.0
	title.offset_bottom = 150.0
	panel.add_child(title)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 60)
	hbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hbox.offset_left   = -360.0
	hbox.offset_right  =  360.0
	hbox.offset_top    = -160.0
	hbox.offset_bottom =  180.0
	panel.add_child(hbox)

	hbox.add_child(_make_char_card("mascot", panel))
	hbox.add_child(_make_char_card("wukong", panel))

	var esc_lbl := Label.new()
	esc_lbl.text = "ESC 關閉"
	esc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	esc_lbl.add_theme_font_size_override("font_size", 16)
	esc_lbl.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85, 0.7))
	esc_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	esc_lbl.offset_top    = -45.0
	esc_lbl.offset_bottom = -15.0
	panel.add_child(esc_lbl)

func _make_char_card(cid: String, panel: Control) -> Control:
	var is_wukong  := cid == "wukong"
	var accent     := Color(1.0, 0.82, 0.0) if is_wukong else Color(0.18, 0.72, 1.0)
	var is_current := Global.selected_character == cid

	var card := Button.new()
	card.custom_minimum_size = Vector2(280.0, 330.0)

	var sn := _card_style(Color(0.04, 0.10, 0.26, 0.96), Color(accent.r, accent.g, accent.b, 0.9 if is_current else 0.45), is_current)
	var sh := _card_style(Color(0.08, 0.18, 0.42, 0.97), accent, true)
	card.add_theme_stylebox_override("normal",  sn)
	card.add_theme_stylebox_override("hover",   sh)
	card.add_theme_stylebox_override("pressed", sh)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  18.0
	vbox.offset_right  = -18.0
	vbox.offset_top    =  22.0
	vbox.offset_bottom = -18.0
	vbox.alignment     = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	# 角色預覽圖
	var preview := TextureRect.new()
	if is_wukong:
		preview.texture = load("res://assets/站立.png")
	else:
		preview.texture = load("res://assets/吉祥物姿勢-01.png")
	preview.custom_minimum_size   = Vector2(100.0, 100.0)
	preview.expand_mode           = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview.stretch_mode          = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(preview)

	# 角色名
	var name_lbl := Label.new()
	name_lbl.text = "孫  悟  空" if is_wukong else "AI  吉  祥  物"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 26)
	name_lbl.add_theme_color_override("font_color", accent)
	vbox.add_child(name_lbl)

	# 屬性
	var stats := Label.new()
	if is_wukong:
		stats.text = "HP：80   速度：230\n攻速：快（×0.9）\n\n初始穿透 +1\n（金箍棒貫穿敵人）"
	else:
		stats.text = "HP：100   速度：185\n攻速：標準\n\n無初始特技\n（均衡成長型）"
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 16)
	stats.add_theme_color_override("font_color", Color(0.82, 0.90, 1.0))
	vbox.add_child(stats)

	# 已選標記
	if is_current:
		var sel := Label.new()
		sel.text = "✓  已選擇"
		sel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sel.add_theme_font_size_override("font_size", 18)
		sel.add_theme_color_override("font_color", accent)
		vbox.add_child(sel)

	card.pressed.connect(_on_char_picked.bind(cid, panel))
	return card

func _card_style(bg: Color, border: Color, selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(3 if selected else 2)
	s.set_corner_radius_all(12)
	return s

func _on_char_picked(cid: String, panel: Control) -> void:
	Global.selected_character = cid
	_char_label.text = "目前角色：" + ("孫悟空" if cid == "wukong" else "AI 吉祥物")
	if is_instance_valid(panel):
		panel.queue_free()
	_select_panel = null

func _diff_style(accent: Color, selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(accent.r * 0.18, accent.g * 0.18, accent.b * 0.18, 0.92)
	s.border_color = accent
	s.set_border_width_all(3 if selected else 1)
	s.set_corner_radius_all(7)
	return s

func _refresh_diff_btns() -> void:
	var colors := [Color(0.15, 0.88, 0.35), Color(0.2, 0.65, 1.0), Color(1.0, 0.65, 0.15), Color(0.9, 0.1, 0.15)]
	var ids    := ["easy", "normal", "hard", "hell"]
	for i in _diff_btns.size():
		var sel: bool = (ids[i] as String) == Global.difficulty
		_diff_btns[i].add_theme_stylebox_override("normal", _diff_style(colors[i] as Color, sel))

func _on_difficulty_picked(diff_id: String) -> void:
	Global.difficulty = diff_id
	_refresh_diff_btns()

func _load_settings() -> void:
	Global.load_settings()

func _save_settings() -> void:
	Global.save_settings()

func _on_settings() -> void:
	if is_instance_valid(_settings_panel):
		_settings_panel.queue_free()

	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_panel = panel
	_canvas.add_child(panel)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.04, 0.14, 0.92)
	panel.add_child(bg)

	var title := Label.new()
	title.text = "設  定"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top    = 90.0
	title.offset_bottom = 150.0
	panel.add_child(title)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -280.0
	vbox.offset_right  =  280.0
	vbox.offset_top    = -210.0
	vbox.offset_bottom =  210.0
	vbox.alignment     = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 22)
	panel.add_child(vbox)

	# ── 全螢幕 ──
	var fs_row := HBoxContainer.new()
	fs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	fs_row.add_theme_constant_override("separation", 20)
	vbox.add_child(fs_row)

	var fs_title := Label.new()
	fs_title.text = "全螢幕"
	fs_title.custom_minimum_size = Vector2(120.0, 0.0)
	fs_title.add_theme_font_size_override("font_size", 24)
	fs_title.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	fs_row.add_child(fs_title)

	var is_fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	var fs_toggle := _make_toggle(is_fs, func(pressed: bool) -> void:
		if pressed:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_config.set_value("settings", "fullscreen", pressed)
		_config.save(_CONFIG_PATH)
	)
	fs_row.add_child(fs_toggle)

	# ── 主音量 ──
	var vol_row := HBoxContainer.new()
	vol_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vol_row.add_theme_constant_override("separation", 14)
	vbox.add_child(vol_row)

	var vol_title := Label.new()
	vol_title.text = "主音量"
	vol_title.custom_minimum_size = Vector2(120.0, 0.0)
	vol_title.add_theme_font_size_override("font_size", 24)
	vol_title.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	vol_row.add_child(vol_title)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step      = 1.0
	var cur_vol: float = Global.bgm_volume
	slider.value = cur_vol * 100.0
	slider.custom_minimum_size = Vector2(180.0, 0.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(_on_volume_changed)
	vol_row.add_child(slider)

	_vol_lbl = Label.new()
	_vol_lbl.text = "%d%%" % int(cur_vol * 100.0)
	_vol_lbl.custom_minimum_size = Vector2(55.0, 0.0)
	_vol_lbl.add_theme_font_size_override("font_size", 22)
	_vol_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vol_row.add_child(_vol_lbl)

	# ── 學習模式 ──
	var learn_row := HBoxContainer.new()
	learn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	learn_row.add_theme_constant_override("separation", 14)
	vbox.add_child(learn_row)

	var learn_lbl := Label.new()
	learn_lbl.text = "學習模式"
	learn_lbl.custom_minimum_size = Vector2(120.0, 0.0)
	learn_lbl.add_theme_font_size_override("font_size", 24)
	learn_lbl.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	learn_row.add_child(learn_lbl)

	var learn_toggle := _make_toggle(Global.learn_mode, func(pressed: bool) -> void:
		Global.learn_mode = pressed
		_config.set_value("settings", "learn_mode", pressed)
		_config.save(_CONFIG_PATH)
		if is_instance_valid(_import_status_lbl):
			_import_status_lbl.text = ""
	)
	learn_row.add_child(learn_toggle)

	var import_btn := Button.new()
	import_btn.text = "匯入題目"
	import_btn.custom_minimum_size = Vector2(96.0, 34.0)
	import_btn.add_theme_font_size_override("font_size", 15)
	import_btn.add_theme_color_override("font_color", Color.WHITE)
	var _isty := StyleBoxFlat.new()
	_isty.bg_color      = Color(0.06, 0.20, 0.44, 0.92)
	_isty.border_color  = Color(0.3, 0.62, 1.0)
	_isty.set_border_width_all(2); _isty.set_corner_radius_all(7)
	import_btn.add_theme_stylebox_override("normal", _isty)
	var _isty_h := _isty.duplicate() as StyleBoxFlat
	_isty_h.bg_color = Color(0.14, 0.34, 0.68, 0.97)
	import_btn.add_theme_stylebox_override("hover",   _isty_h)
	import_btn.add_theme_stylebox_override("pressed", _isty_h)
	import_btn.pressed.connect(_import_questions)
	learn_row.add_child(import_btn)

	_import_status_lbl = Label.new()
	_import_status_lbl.text = ""
	_import_status_lbl.add_theme_font_size_override("font_size", 14)
	_import_status_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	_import_status_lbl.custom_minimum_size = Vector2(140.0, 0.0)
	learn_row.add_child(_import_status_lbl)

	# ── 開發者模式（隱藏直到輸入密碼）──
	var dev_section := VBoxContainer.new()
	dev_section.visible = _dev_unlocked or Global.dev_mode
	dev_section.add_theme_constant_override("separation", 16)
	_dev_row = dev_section
	vbox.add_child(dev_section)

	var dev_title_row := HBoxContainer.new()
	dev_title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dev_title_row.add_theme_constant_override("separation", 20)
	dev_section.add_child(dev_title_row)

	var dev_lbl := Label.new()
	dev_lbl.text = "開發者模式"
	dev_lbl.custom_minimum_size = Vector2(120.0, 0.0)
	dev_lbl.add_theme_font_size_override("font_size", 24)
	dev_lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.2))
	dev_title_row.add_child(dev_lbl)

	var dev_toggle := _make_toggle(Global.dev_mode, func(pressed: bool) -> void:
		Global.dev_mode = pressed
		if is_instance_valid(_dummy_row):
			_dummy_row.visible = pressed
		if not pressed:
			Global.dummy_mode = false
	)
	dev_title_row.add_child(dev_toggle)

	var dummy_row_ctrl := HBoxContainer.new()
	dummy_row_ctrl.alignment = BoxContainer.ALIGNMENT_CENTER
	dummy_row_ctrl.add_theme_constant_override("separation", 20)
	dummy_row_ctrl.visible = Global.dev_mode
	_dummy_row = dummy_row_ctrl
	dev_section.add_child(dummy_row_ctrl)

	var dummy_lbl := Label.new()
	dummy_lbl.text = "木樁模式"
	dummy_lbl.custom_minimum_size = Vector2(120.0, 0.0)
	dummy_lbl.add_theme_font_size_override("font_size", 24)
	dummy_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.55))
	dummy_row_ctrl.add_child(dummy_lbl)

	var dummy_toggle := _make_toggle(Global.dummy_mode, func(pressed: bool) -> void:
		Global.dummy_mode = pressed
	)
	dummy_row_ctrl.add_child(dummy_toggle)

	var esc_lbl := Label.new()
	esc_lbl.text = "ESC 關閉"
	esc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	esc_lbl.add_theme_font_size_override("font_size", 16)
	esc_lbl.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85, 0.7))
	esc_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	esc_lbl.offset_top    = -45.0
	esc_lbl.offset_bottom = -15.0
	panel.add_child(esc_lbl)

func _make_toggle(initial_on: bool, callback: Callable) -> Button:
	var btn := Button.new()
	btn.toggle_mode    = true
	btn.button_pressed = initial_on
	btn.custom_minimum_size = Vector2(60.0, 32.0)
	btn.text       = ""
	btn.focus_mode = Control.FOCUS_NONE
	var off_s := _toggle_style(Color(0.22, 0.22, 0.26))
	var on_s  := _toggle_style(Color(0.15, 0.70, 0.42))
	btn.add_theme_stylebox_override("normal",        off_s)
	btn.add_theme_stylebox_override("hover",         off_s)
	btn.add_theme_stylebox_override("pressed",       on_s)
	btn.add_theme_stylebox_override("hover_pressed", on_s)
	var knob := Panel.new()
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ks := StyleBoxFlat.new()
	ks.bg_color = Color(0.96, 0.96, 0.98)
	ks.set_corner_radius_all(12)
	knob.add_theme_stylebox_override("panel", ks)
	knob.size     = Vector2(24.0, 24.0)
	knob.position = Vector2(32.0 if initial_on else 4.0, 4.0)
	btn.add_child(knob)
	btn.toggled.connect(func(pressed: bool) -> void:
		var tween := btn.create_tween()
		tween.tween_property(knob, "position:x", 32.0 if pressed else 4.0, 0.12)
		callback.call(pressed)
	)
	return btn

func _toggle_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(16)
	return s



func _on_start() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _import_questions() -> void:
	if not is_instance_valid(_import_status_lbl):
		return
	var src := "C:/Users/kimya/Downloads/乙級.json"
	if not FileAccess.file_exists(src):
		_import_status_lbl.text = "找不到檔案"
		_import_status_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		return
	var file := FileAccess.open(src, FileAccess.READ)
	if file == null:
		_import_status_lbl.text = "無法讀取"
		_import_status_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		return
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(content) != OK:
		_import_status_lbl.text = "JSON 格式錯誤"
		_import_status_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		return
	var dest := FileAccess.open("user://questions.json", FileAccess.WRITE)
	if dest == null:
		_import_status_lbl.text = "寫入失敗"
		_import_status_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		return
	dest.store_string(content)
	dest.close()
	var q_count: int = (json.data as Array).size() if json.data is Array else 0
	_import_status_lbl.text = "完成（%d 題）" % q_count
	_import_status_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.55))

func _setup_bgm() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_bgm_player)
	
	var stream = load("res://assets/lobby.ogg")
	if not stream: stream = load("res://assets/lobby.mp3")
	
	if stream:
		# Force loop for MP3 in Godot 4
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		elif stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
			
		_bgm_player.stream = stream
		_bgm_player.autoplay = true
		_bgm_player.play()
		
		# Backup manual loop via signal
		_bgm_player.finished.connect(func(): _bgm_player.play())
	
	Global.sync_audio_volume()

func _on_volume_changed(value: float) -> void:
	Global.bgm_volume = value / 100.0
	if is_instance_valid(_vol_lbl):
		_vol_lbl.text = "%d%%" % int(value)
	Global.sync_audio_volume()
	Global.save_settings()
