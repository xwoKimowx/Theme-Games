extends CharacterBody2D

signal died

var player:       Node2D = null
var bullets_node: Node2D = null
var hp:     int   = 4000
var max_hp: int   = 4000
var damage: int   = 75
var speed:  float = 120.0

var contact_timer:       float = 0.0
var overlap_timer:       float = 0.0
var stun_timer:          float = 0.0
var hit_flash:           bool  = false
var flash_timer:         float = 0.0
var burn_timer:          float = 0.0
var _burn_tick_interval: float = 5.0
var _burn_dmg_timer:     float = 0.0

# ─── 彈幕攻擊 ──────────────────────────────
var spiral_timer:  float = 0.0    # 螺旋彈幕計時
var spiral_angle:  float = 0.0    # 當前螺旋角度
var burst_timer:   float = 2.5    # 全方位爆射計時
var aimed_timer:   float = 3.5    # 瞄準散射計時

# ─── 近戰大招 ──────────────────────────────
var slam_cooldown:    float = 6.0    # 大招冷卻
var is_slam_charge:   bool  = false  # 蓄力中
var slam_charge_timer:float = 0.0
var slam_flash:       float = 0.0   # 大招特效
const SLAM_RANGE     := 220.0       # 觸發距離（世界座標）
const SLAM_HIT_RANGE := 280.0       # 傷害範圍

# ─── 網格光束攻擊 ──────────────────────────
var beam_cooldown:     float = 10.0
var is_charging:       bool  = false
var beam_charge_timer: float = 0.0
var is_beam_warning:   bool  = false
var beam_warning_timer:float = 0.0
const BEAM_WARN_DUR:   float = 2.0
var is_beaming:        bool  = false
var beam_active_timer: float = 0.0
var _beam_origin:      Vector2 = Vector2.ZERO  # 蓄力開始時鎖定的格子中心

var map_half_w: float = 1600.0
var map_half_h: float = 900.0

var boss_bullet_scene: PackedScene
var is_dummy: bool = false

var bullet_interval_mult: float = 1.0
var _beam_charge_dur:     float = 1.6
var _beam_reset_cd:       float = 9.0

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	scale = Vector2(5.0, 5.0)
	collision_layer = 0
	boss_bullet_scene = load("res://scenes/BossBullet.tscn")
	match Global.difficulty:
		"easy":
			hp = 2000;  max_hp = 2000
			damage = 38;  speed = 90.0
			bullet_interval_mult = 2.5
			beam_cooldown = 18.0;  _beam_charge_dur = 2.0;  _beam_reset_cd = 17.0
		"normal":
			hp = 2800;  max_hp = 2800
			damage = 53;  speed = 105.0
			bullet_interval_mult = 1.5
			beam_cooldown = 14.0;  _beam_charge_dur = 1.8;  _beam_reset_cd = 13.0
		"hell":
			hp = 5200;  max_hp = 5200
			damage = 98;  speed = 138.0
			bullet_interval_mult = 0.85
			beam_cooldown = 8.5;  _beam_charge_dur = 1.3;  _beam_reset_cd = 8.0
	burst_timer = 2.5 * bullet_interval_mult
	aimed_timer = 3.5 * bullet_interval_mult

# ─── 每幀邏輯 ──────────────────────────────
func apply_stun(duration: float) -> void:
	stun_timer = maxf(stun_timer, duration)
	# 取消蓄力中的招式，避免暈眩結束後立即發動
	if is_slam_charge:
		is_slam_charge = false
		slam_cooldown  = 6.0
	if is_charging or is_beam_warning or is_beaming:
		is_charging     = false
		is_beam_warning = false
		is_beaming      = false
		beam_cooldown   = _beam_reset_cd

func apply_burn(duration: float, tick_interval: float) -> void:
	if burn_timer <= 0.0:
		_burn_dmg_timer = 0.0
	if duration > burn_timer:
		burn_timer          = duration
		_burn_tick_interval = tick_interval

func _process(delta: float) -> void:
	if stun_timer > 0.0:
		stun_timer -= delta
		stun_timer = maxf(0.0, stun_timer)
	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0:
			hit_flash = false
	if burn_timer > 0.0:
		burn_timer -= delta
		burn_timer = maxf(0.0, burn_timer)
		_burn_dmg_timer -= delta
		if _burn_dmg_timer <= 0.0:
			_burn_dmg_timer = _burn_tick_interval
			take_damage(maxi(1, int(float(max_hp) * 0.007)))
	else:
		_burn_dmg_timer = 0.0

	if stun_timer > 0.0:
		queue_redraw()
		return

	if is_dummy:
		queue_redraw()
		return

	var phase := _get_phase()

	# ── 螺旋彈幕（持續旋轉發射）──
	if not is_charging and not is_beam_warning and not is_beaming:
		spiral_timer -= delta
		var spiral_interval: float = ([0.14, 0.09, 0.065] as Array)[phase - 1] * bullet_interval_mult
		if spiral_timer <= 0.0:
			spiral_timer = spiral_interval
			_do_spiral(phase)

	# ── 全方位爆射 ──
	if not is_charging and not is_beam_warning and not is_beaming:
		burst_timer -= delta
		var burst_interval: float = ([3.0, 2.0, 1.4] as Array)[phase - 1] * bullet_interval_mult
		if burst_timer <= 0.0:
			burst_timer = burst_interval
			_do_burst(phase)

	# ── 瞄準散射（phase 2+ 才觸發）──
	if phase >= 2 and not is_charging and not is_beam_warning and not is_beaming:
		aimed_timer -= delta
		var aimed_interval: float = ([0.0, 2.2, 1.2] as Array)[phase - 1] * bullet_interval_mult
		if aimed_timer <= 0.0:
			aimed_timer = aimed_interval
			_do_aimed(phase)

	# 網格光束週期
	if not is_charging and not is_beam_warning and not is_beaming:
		beam_cooldown -= delta
		if beam_cooldown <= 0.0:
			is_charging      = true
			beam_charge_timer = _beam_charge_dur
			_beam_origin     = global_position

	if is_charging:
		beam_charge_timer -= delta
		if beam_charge_timer <= 0.0:
			is_charging        = false
			is_beam_warning    = true
			beam_warning_timer = BEAM_WARN_DUR

	if is_beam_warning:
		beam_warning_timer -= delta
		if beam_warning_timer <= 0.0:
			is_beam_warning   = false
			is_beaming        = true
			beam_active_timer = 0.75
			_check_beam_damage()

	if is_beaming:
		beam_active_timer -= delta
		if beam_active_timer <= 0.0:
			is_beaming    = false
			beam_cooldown = _beam_reset_cd

	# ── 近戰大招 ──
	if slam_flash > 0.0:
		slam_flash -= delta
	if not is_slam_charge and not is_charging:
		slam_cooldown -= delta
		if slam_cooldown <= 0.0 and is_instance_valid(player):
			var dist := global_position.distance_to(player.global_position)
			if dist < SLAM_RANGE:
				is_slam_charge   = true
				slam_charge_timer = 0.7
	if is_slam_charge:
		slam_charge_timer -= delta
		if slam_charge_timer <= 0.0:
			is_slam_charge = false
			slam_cooldown  = 6.0
			slam_flash     = 0.5
			_do_slam()

	queue_redraw()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return

	if is_dummy:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if stun_timer > 0.0 or is_charging or is_beam_warning or is_beaming or is_slam_charge:
		velocity = Vector2.ZERO
	else:
		var dir := (player.global_position - global_position).normalized()
		velocity = dir * speed
	move_and_slide()

	if contact_timer > 0.0:
		contact_timer -= delta
	if overlap_timer > 0.0:
		overlap_timer -= delta

	if is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		# 重疊懲罰：鑽進 boss 內部，5 倍傷害，0.15s 冷卻
		if overlap_timer <= 0.0 and dist < 50.0:
			player.take_damage(damage * 5)
			overlap_timer = 0.15

# ─── 近戰衝擊大招 ────────────────────────
func _do_slam() -> void:
	if not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)
	if dist < SLAM_HIT_RANGE:
		player.take_damage(int(damage * 3.5))   # 3.5 倍傷害

# ─── 取得當前階段（依 HP 比例）───────────
func _get_phase() -> int:
	var ratio := float(hp) / float(max_hp)
	if ratio > 0.6:   return 1
	elif ratio > 0.3: return 2
	else:             return 3

# ─── 共用發射函數 ────────────────────────
func _fire(dir: Vector2, spd: float = 260.0) -> void:
	if not is_instance_valid(bullets_node) or boss_bullet_scene == null:
		return
	var b := boss_bullet_scene.instantiate()
	bullets_node.add_child(b)
	b.global_position = global_position
	b.direction       = dir.normalized()
	b.speed           = spd
	b.damage          = int(damage * 0.5)
	b.player          = player

# ─── 螺旋彈幕 ────────────────────────────
func _do_spiral(phase: int) -> void:
	var streams: int   = 1 if phase == 1 else (2 if phase == 2 else 3)
	var spd:     float = 260.0 if phase == 1 else (290.0 if phase == 2 else 320.0)
	var rot_inc: float = 0.20 if phase == 1 else (0.27 if phase == 2 else 0.35)
	for s in streams:
		var a: float = spiral_angle + s * TAU / float(streams)
		_fire(Vector2.RIGHT.rotated(a), spd)
	spiral_angle += rot_inc

# ─── 全方位爆射 ──────────────────────────
func _do_burst(phase: int) -> void:
	var base_count := 18 if phase == 1 else (24 if phase == 2 else 30)
	var count: int  = clampi(int(float(base_count) / bullet_interval_mult), 8, 48)
	var spd:   float = 240.0 if phase == 1 else (270.0 if phase == 2 else 300.0)
	var rings: int   = 1 if phase <= 2 else 2
	for r in rings:
		var offset: float = float(r) * TAU / float(count * 2)
		for i in count:
			var a: float = float(i) * TAU / float(count) + offset
			_fire(Vector2.RIGHT.rotated(a), spd)

# ─── 瞄準散射 ────────────────────────────
func _do_aimed(phase: int) -> void:
	if not is_instance_valid(player):
		return
	var shots:    int   = 5 if phase == 2 else 7
	var spd:      float = 310.0 if phase == 2 else 360.0
	var spread:   float = 0.28
	var base_dir: Vector2 = (player.global_position - global_position).normalized()
	for i in shots:
		var offset: float = (float(i) - float(shots - 1) * 0.5) * spread / maxf(float(shots - 1), 1.0)
		_fire(base_dir.rotated(offset), spd)

# ─── 網格光束：判斷玩家是否在光束路徑內 ───
func _check_beam_damage() -> void:
	if not is_instance_valid(player):
		return
	var px      := player.global_position.x
	var py      := player.global_position.y
	var bx      := 0.0
	var by      := 0.0
	var half    := 14.0
	var spacing := 120.0
	var hit     := false

	var row_off := -960.0
	while row_off <= 960.0:
		if abs(py - (by + row_off)) < half:
			hit = true
			break
		row_off += spacing
	if not hit:
		var col_off := -1680.0
		while col_off <= 1680.0:
			if abs(px - (bx + col_off)) < half:
				hit = true
				break
			col_off += spacing
	if hit:
		player.take_damage(int(damage * 1.6))

# ─── 受傷 ──────────────────────────────────
func take_damage(amount: int, _vamp: bool = true) -> void:
	hp -= amount
	Global.record_damage(amount)
	hit_flash  = true
	flash_timer = 0.14
	_spawn_damage_number(amount)
	if hp <= 0:
		died.emit()
		queue_free()

func _spawn_damage_number(amount: int) -> void:
	var ui := get_tree().current_scene.get_node_or_null("UI")
	if ui == null:
		return
	var canvas_pos := get_viewport().get_canvas_transform() * global_position
	canvas_pos += Vector2(randf_range(-22.0, 22.0), -55.0)

	var lbl := Label.new()
	lbl.text = "-%d" % amount
	var font_size := 28 if amount >= 100 else 22
	lbl.add_theme_font_size_override("font_size", font_size)
	var col := Color(1.0, 0.28, 0.08) if amount >= 50 else Color(1.0, 0.65, 0.1)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.position = canvas_pos
	lbl.z_index  = 10
	ui.add_child(lbl)

	var tween := lbl.create_tween()
	tween.tween_property(lbl, "position:y", canvas_pos.y - 60.0, 0.75)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.75)
	tween.tween_callback(lbl.queue_free)

# ─── 繪製（在 local 空間，外部 scale=5）────
func _draw() -> void:
	var a := 0.38 if hit_flash else 1.0

	# 蓄力中：本體變橘色提示

	# ── 大招衝擊波特效 ──
	if slam_flash > 0.0:
		var st: float = slam_flash / 0.5
		var slam_r: float = (SLAM_HIT_RANGE / 5.0) * (1.0 + (1.0 - st) * 0.4)
		draw_arc(Vector2.ZERO, slam_r, 0.0, TAU, 64, Color(1.0, 0.0, 0.2, st * 0.9), 8.0)
		draw_arc(Vector2.ZERO, slam_r * 1.15, 0.0, TAU, 64, Color(1.0, 0.3, 0.0, st * 0.4), 14.0)

	# ── 大招蓄力：紅色閃爍漸強 ──
	if is_slam_charge:
		var ct: float = 1.0 - slam_charge_timer / 0.7
		var blink: bool = fmod(slam_charge_timer * 10.0, 2.0) > 1.0
		if blink:
			draw_circle(Vector2.ZERO, 22.0 + ct * 8.0, Color(1.0, 0.0, 0.1, ct * 0.8))

	# ── 光束視覺 ──
	if is_charging:
		var cd_secs := int(ceil(beam_charge_timer))
		draw_string(ThemeDB.fallback_font, Vector2(-5.0, -35.0),
					str(cd_secs), HORIZONTAL_ALIGNMENT_LEFT, -1, 7,
					Color(1.0, 0.7, 0.0, 0.95))

	if is_beam_warning:
		var cd_secs := int(ceil(beam_warning_timer))
		var blink   := fmod(beam_warning_timer * 5.0, 1.0) > 0.45
		var wcol    := Color(1.0, 0.05, 0.0, 0.95) if blink else Color(1.0, 0.45, 0.0, 0.90)
		draw_string(ThemeDB.fallback_font, Vector2(-8.0, -26.0),
					"⚡%d" % cd_secs, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, wcol)

	if is_beaming or is_charging or is_beam_warning:
		var beam_col: Color
		if is_beaming:
			beam_col = Color(1.0, 1.0, 1.0, 0.88)
		elif is_beam_warning:
			var pulse := 0.42 + 0.38 * absf(sin(beam_warning_timer * TAU))
			beam_col = Color(1.0, 0.08, 0.0, pulse)
		else:
			beam_col = Color(1.0, 0.42, 0.0, 0.32)
		var bw          := 4.5
		var bl          := 360.0
		var spc         := 24.0
		var beam_offset := to_local(Vector2.ZERO)
		var row_off     := -192.0
		while row_off <= 192.0:
			draw_rect(Rect2(-bl, beam_offset.y + row_off - bw * 0.5, bl * 2.0, bw), beam_col, true)
			row_off += spc
		var col_off     := -336.0
		while col_off <= 336.0:
			draw_rect(Rect2(beam_offset.x + col_off - bw * 0.5, -bl, bw, bl * 2.0), beam_col, true)
			col_off += spc

	# ── 燃燒指示（藍色，local 空間）──
	if burn_timer > 0.0:
		draw_circle(Vector2.ZERO, 20.0, Color(0.0, 0.35, 1.0, 0.28))
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color(0.1, 0.55, 1.0, 0.85), 2.5)

	# ── 近戰危險範圍警示光環（世界 95px = local 19px）──
	var danger_pulse := fmod(Time.get_ticks_msec() * 0.003, 1.0)
	var danger_alpha := 0.25 + danger_pulse * 0.35
	draw_arc(Vector2.ZERO, 19.0, 0.0, TAU, 48, Color(1.0, 0.1, 0.0, danger_alpha), 2.5)

	# ── Boss 本體 ──
	var body_col: Color
	if is_charging:
		body_col = Color(1.0, 0.38, 0.0, a)
	elif is_beam_warning:
		var blink2 := fmod(beam_warning_timer * 5.0, 1.0) > 0.45
		body_col = Color(1.0, 0.02, 0.0, a) if blink2 else Color(0.85, 0.10, 0.0, a)
	else:
		body_col = Color(0.76, 0.04, 0.08, a)
	draw_circle(Vector2.ZERO, 18.0, body_col)
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 36, Color(1.0, 0.22, 0.0, a * 0.75), 1.8)

	if not hit_flash:
		# 眼睛
		draw_circle(Vector2(-6.5, -5.5), 4.5, Color(1.0, 0.92, 0.0))
		draw_circle(Vector2(6.5,  -5.5), 4.5, Color(1.0, 0.92, 0.0))
		draw_circle(Vector2(-6.5, -5.5), 2.5, Color(0.05, 0.0, 0.0))
		draw_circle(Vector2(6.5,  -5.5), 2.5, Color(0.05, 0.0, 0.0))
		# 惡狠狠眉毛
		draw_line(Vector2(-10.0, -10.5), Vector2(-3.5, -8.0),  Color(0.0, 0.0, 0.0), 1.8)
		draw_line(Vector2( 10.0, -10.5), Vector2( 3.5, -8.0),  Color(0.0, 0.0, 0.0), 1.8)
		# 嘴巴（倒弧形）
		draw_line(Vector2(-7.0, 6.0), Vector2(-2.0, 4.0), Color(0.0, 0.0, 0.0), 1.5)
		draw_line(Vector2(-2.0, 4.0), Vector2( 2.0, 4.0), Color(0.0, 0.0, 0.0), 1.5)
		draw_line(Vector2( 2.0, 4.0), Vector2( 7.0, 6.0), Color(0.0, 0.0, 0.0), 1.5)

	# ── 暈眩指示 ──
	if stun_timer > 0.0:
		draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 48, Color(1.0, 0.88, 0.1, 0.95), 3.0)
		draw_string(ThemeDB.fallback_font, Vector2(-8.0, -38.0),
					"★%.1f" % stun_timer, HORIZONTAL_ALIGNMENT_LEFT, -1, 7,
					Color(1.0, 0.92, 0.1, 0.95))

	# ── HP 條（local 空間，顯示在 boss 上方） ──
	var bw2   := 26.0
	var ratio := float(hp) / float(max_hp)
	draw_rect(Rect2(-bw2 * 0.5, -28.0, bw2,           5.0), Color(0.08, 0.0, 0.0, 0.92), true)
	if ratio > 0.0:
		var bc := Color(0.9, 0.12, 0.05, 0.95) if ratio > 0.35 else Color(1.0, 0.55, 0.0, 0.95)
		draw_rect(Rect2(-bw2 * 0.5, -28.0, bw2 * ratio, 5.0), bc, true)

	if is_dummy:
		draw_string(ThemeDB.fallback_font, Vector2(-8.0, -35.0),
					"木樁", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.3, 1.0, 0.55, 0.9))
