extends CharacterBody2D

signal died
signal level_changed(level: int)
signal hp_changed(hp: int, max_hp: int)
signal exp_changed(cur: int, needed: int)
signal skill_on_cooldown(type: String)

const BASE_SPEED        := 185.0
const BASE_ATK_INTERVAL := 1.1

var char_id: String = "mascot"

# ── 基礎屬性（升級可改） ──
var speed:              float = BASE_SPEED
var max_hp:             int   = 100
var hp:                 int   = 100
var bullet_count:       int   = 1
var bullet_damage_bonus:int   = 0
var damage_multiplier:  float = 1.0
var atk_interval_mult:  float = 1.0
var vampiric_heal:      int   = 0
var bullet_pierce:      int   = 0
var gem_attract_range:  float = 160.0

# ── 特殊技能 ──
var has_area_bomb:      bool  = false
var area_bomb_interval: float = 4.0
var area_bomb_timer:    float = 4.0
var area_bomb_flash:    float = 0.0
var has_orbit:          bool  = false
var orbit_interval:     float = 2.5
var orbit_timer:        float = 2.5
var orbit_ring_level:   int   = 0

# ── 護盾 ──
var has_shield:           bool  = false
var shield_max_hp:        int   = 40
var shield_hp:            int   = 0
var shield_recharge:      float = 10.0
var shield_refresh_timer: float = 10.0
var shield_break_flash:   float = 0.0

# ── 生命再生 ──
var has_regen:      bool  = false
var has_africa_title: bool = false
var has_trip:         bool  = false

# ── 跌倒效果 ──
var is_tripped:        bool  = false
var _trip_timer:       float = 0.0
var _trip_cooldown:    float = 0.0
var _trip_check_timer: float = 2.0
var _trip_sprite:      Sprite2D = null

# ── 角色技能 Q / E ──
var skill_q_cd:       float   = 0.0
var skill_e_cd:       float   = 0.0
const SKILL_MAX_CD            := 100.0
var _mg_active:       bool    = false   # 吉祥物 E 機槍掃射
var _mg_timer:        float   = 0.0
var _mg_atk_timer:    float   = 0.0
var _staff_flash:     float    = 0.0    # 悟空 E 立棍特效
var _staff_dir:       Vector2  = Vector2.RIGHT
var _staff_texture:   Texture2D = null
var _shockwave_flash: float    = 0.0    # 吉祥物 Q 衝擊波特效
var _teleport_flash:  float    = 0.0    # 悟空 Q 瞬移特效
var _mg_sprite:       Sprite2D = null   # 吉祥物 E 機槍掃射立繪

var regen_interval: float = 4.0
var regen_amount:   int   = 1
var regen_timer:    float = 4.0

# ── 強化模式（密技） ──
const CHEAT_SEQ := [KEY_W,KEY_A,KEY_S,KEY_D,KEY_W,KEY_W,KEY_S,KEY_S,KEY_A,KEY_D,KEY_A,KEY_D]
var cheat_buffer:     Array = []
var powered_mode:     bool  = false
var power_heal_accum: float = 0.0
var power_bomb_timer: float = 0.0
var power_aura_phase: float = 0.0

# ── 內部狀態 ──
var level:       int   = 1
var exp:         int   = 0
var exp_to_next: int   = 10
var invincible:  bool  = false
var inv_timer:   float = 0.0
var atk_timer:   float = 0.0

var _char_visible: bool  = true
var _facing_right: bool  = true
var _draw_timer:   float   = 0.0
var _swing_flash:  float   = 0.0
var _swing_dir:     Vector2 = Vector2.RIGHT
var orbit_scale:    float   = 1.0
var _swing_hit_ids: Array   = []

var bullet_scene:  PackedScene
var _sprite:       AnimatedSprite2D
var _idle_sprite:  Sprite2D

func _ready() -> void:
	bullet_scene   = load("res://scenes/Bullet.tscn")
	_staff_texture = load("res://assets/立棍.png")
	add_to_group("player")
	char_id = Global.selected_character
	_setup_char()
	_setup_sprite()

func _setup_char() -> void:
	if char_id == "wukong":
		max_hp            = 120
		hp                = 120
		speed             = 220.0
		atk_interval_mult = 0.9
		bullet_pierce     = 1

	match Global.difficulty:
		"easy":
			vampiric_heal   = 1
			regen_amount    = 2
			regen_interval  = 3.5
			shield_max_hp   = 50
			shield_recharge = 8.0
		"normal":
			regen_interval  = 3.8
			shield_max_hp   = 46
			shield_recharge = 9.0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		cheat_buffer.append(event.keycode)
		if cheat_buffer.size() > CHEAT_SEQ.size():
			cheat_buffer.pop_front()
		if cheat_buffer == CHEAT_SEQ:
			_activate_powered_mode()
			cheat_buffer.clear()

		if event.keycode == KEY_Q and not is_tripped:
			if skill_q_cd <= 0.0:
				skill_q_cd = SKILL_MAX_CD
				_activate_skill_q()
				get_viewport().set_input_as_handled()
			else:
				skill_on_cooldown.emit("Q")
		elif event.keycode == KEY_E and not is_tripped:
			if skill_e_cd <= 0.0:
				skill_e_cd = SKILL_MAX_CD
				_activate_skill_e()
				get_viewport().set_input_as_handled()
			else:
				skill_on_cooldown.emit("E")

func _activate_powered_mode() -> void:
	if powered_mode:
		return
	powered_mode          = true
	bullet_damage_bonus  += 100
	speed                += 80.0
	hp_changed.emit(hp, max_hp)
	queue_redraw()

func _setup_sprite() -> void:
	_sprite = AnimatedSprite2D.new()
	var frames := SpriteFrames.new()

	if char_id == "wukong":
		frames.add_animation("walk")
		frames.set_animation_speed("walk", 6.0)
		frames.set_animation_loop("walk", true)
		frames.add_frame("walk", load("res://assets/走路1.png"))
		frames.add_frame("walk", load("res://assets/走路2.png"))

		frames.rename_animation("default", "idle")
		frames.set_animation_speed("idle", 1.0)
		frames.set_animation_loop("idle", true)
		frames.add_frame("idle", load("res://assets/站立.png"))

		_sprite.scale = Vector2(0.17, 0.17)
	else:
		frames.add_animation("walk")
		frames.set_animation_speed("walk", 6.0)
		frames.set_animation_loop("walk", true)
		frames.add_frame("walk", load("res://assets/吉祥物走路2.png"))
		frames.add_frame("walk", load("res://assets/吉祥物走路3.png"))

		frames.rename_animation("default", "idle")
		frames.set_animation_speed("idle", 1.0)
		frames.set_animation_loop("idle", true)
		frames.add_frame("idle", load("res://assets/吉祥物走路2.png"))

		_sprite.scale   = Vector2(0.08, 0.08)
		_sprite.visible = false

		_idle_sprite = Sprite2D.new()
		_idle_sprite.texture  = load("res://assets/吉祥物姿勢-01.png")
		_idle_sprite.scale    = Vector2(0.038, 0.038)
		_idle_sprite.material = _chroma_material()
		_idle_sprite.visible  = true
		add_child(_idle_sprite)

		_mg_sprite = Sprite2D.new()
		_mg_sprite.texture  = load("res://assets/機關槍射擊.png")
		_mg_sprite.scale    = Vector2(0.10, 0.10)
		_mg_sprite.material = _chroma_material()
		_mg_sprite.visible  = false
		add_child(_mg_sprite)

	_sprite.sprite_frames = frames
	_sprite.play("idle")
	_sprite.visible = true
	add_child(_sprite)

func _process(delta: float) -> void:
	# 攻擊計時
	atk_timer -= delta
	if atk_timer <= 0.0:
		atk_timer = BASE_ATK_INTERVAL * atk_interval_mult
		_auto_attack()

	# 範圍爆炸
	if has_area_bomb:
		area_bomb_timer -= delta
		if area_bomb_timer <= 0.0:
			area_bomb_timer = area_bomb_interval
			_do_area_bomb()

	if area_bomb_flash > 0.0:
		area_bomb_flash -= delta
		queue_redraw()

	# 環形射擊
	if has_orbit:
		orbit_timer -= delta
		if orbit_timer <= 0.0:
			orbit_timer = orbit_interval
			_do_orbit_shot()

	# 強化模式
	if powered_mode:
		power_aura_phase += delta * 3.0
		power_heal_accum += delta
		if power_heal_accum >= 1.0:
			power_heal_accum -= 1.0
			heal(100)
		power_bomb_timer -= delta
		if power_bomb_timer <= 0.0:
			power_bomb_timer = 0.5
			_do_area_bomb()
		queue_redraw()

	# 護盾每 8 秒固定刷新
	if has_shield:
		shield_refresh_timer -= delta
		if shield_refresh_timer <= 0.0:
			shield_refresh_timer = shield_recharge
			shield_hp = shield_max_hp
			queue_redraw()
	if shield_break_flash > 0.0:
		shield_break_flash -= delta
		queue_redraw()

	# 非洲人稱號常駐顯示
	if has_africa_title:
		queue_redraw()

	# 生命再生
	if has_regen:
		regen_timer -= delta
		if regen_timer <= 0.0:
			regen_timer = regen_interval
			if hp < max_hp:
				heal(regen_amount)

	# 技能冷卻（機槍掃射進行中 E 冷卻暫停）
	if skill_q_cd > 0.0: skill_q_cd = maxf(0.0, skill_q_cd - delta)
	if skill_e_cd > 0.0 and not _mg_active: skill_e_cd = maxf(0.0, skill_e_cd - delta)

	# 機槍掃射
	if _mg_active:
		_mg_timer -= delta
		if _mg_timer <= 0.0:
			_mg_active = false
		else:
			_mg_atk_timer -= delta
			if _mg_atk_timer <= 0.0:
				_mg_atk_timer = 0.035
				_fire_machinegun()

	# 技能特效計時
	if _staff_flash > 0.0:
		_staff_flash = maxf(0.0, _staff_flash - delta); queue_redraw()
	if _shockwave_flash > 0.0:
		_shockwave_flash = maxf(0.0, _shockwave_flash - delta); queue_redraw()
	if _teleport_flash > 0.0:
		_teleport_flash = maxf(0.0, _teleport_flash - delta); queue_redraw()

	# 跌倒計時
	if has_trip:
		if is_tripped:
			_trip_timer -= delta
			if _trip_timer <= 0.0:
				is_tripped = false
				_trip_check_timer = 1.5
		elif _trip_cooldown > 0.0:
			_trip_cooldown -= delta
		elif velocity.length_squared() > 1.0:
			_trip_check_timer -= delta
			if _trip_check_timer <= 0.0:
				_trip_check_timer = 2.0
				if randf() < 0.01:
					is_tripped = true
					_trip_timer = 1.0
					_trip_cooldown = 20.0
					if not is_instance_valid(_trip_sprite):
						_trip_sprite = Sprite2D.new()
						_trip_sprite.texture = load("res://assets/跌倒.png")
						_trip_sprite.scale = Vector2(0.08, 0.08)
						add_child(_trip_sprite)
					_trip_sprite.visible = true

	# 無敵閃爍
	if invincible:
		inv_timer -= delta
		_char_visible = fmod(inv_timer * 10.0, 2.0) > 1.0
		if char_id == "mascot" and is_instance_valid(_idle_sprite):
			_idle_sprite.visible = _char_visible and velocity.length_squared() <= 1.0
		_sprite.visible = _char_visible and (char_id == "wukong" or velocity.length_squared() > 1.0)
		if inv_timer <= 0.0:
			invincible      = false
			_char_visible   = true
			_sprite.visible = true

	# 走路動畫
	if char_id == "mascot":
		var moving := velocity.length_squared() > 1.0
		_sprite.visible      = moving and _char_visible
		var use_mg_pose := _mg_active and not moving
		_idle_sprite.visible = not moving and not use_mg_pose and _char_visible
		if is_instance_valid(_mg_sprite):
			_mg_sprite.visible = use_mg_pose and _char_visible
		if moving and _sprite.animation != "walk":
			_sprite.play("walk")
	else:
		if velocity.length_squared() > 1.0:
			if _sprite.animation != "walk":
				_sprite.play("walk")
		else:
			if _sprite.animation != "idle":
				_sprite.play("idle")

	# 翻轉方向
	if velocity.x < -1.0:
		_sprite.flip_h = true
		if is_instance_valid(_idle_sprite): _idle_sprite.flip_h = true
		_facing_right  = false
	elif velocity.x > 1.0:
		_sprite.flip_h = false
		if is_instance_valid(_idle_sprite): _idle_sprite.flip_h = false
		_facing_right  = true

	# 悟空揮擊特效 + 持續傷害
	if char_id == "wukong":
		if velocity.length_squared() > 1.0 and _swing_flash <= 0.0:
			_swing_dir = velocity.normalized()
			queue_redraw()
		if _swing_flash > 0.0:
			_swing_flash -= delta
			var _raw_fan := deg_to_rad(60.0 + (bullet_count - 1) * 20.0)
			var fan_half := PI if _raw_fan >= PI else _raw_fan
			var rng      := 120.0 + bullet_pierce * 20.0
			var dmg      := int((20.0 + (level - 1) * 3.0 + float(bullet_damage_bonus)) * damage_multiplier)
			for e in get_tree().get_nodes_in_group("enemies"):
				if not is_instance_valid(e) or e in _swing_hit_ids:
					continue
				var diff: Vector2 = (e as Node2D).global_position - global_position
				if diff.length() > rng:
					continue
				if fan_half >= PI or abs(wrapf(diff.angle() - _swing_dir.angle(), -PI, PI)) <= fan_half:
					e.take_damage(dmg)
					_swing_hit_ids.append(e)
					if has_trip and randf() < 0.1:
						e.call("apply_stun", 3.0)
			queue_redraw()

	# 跌倒時覆蓋：隱藏正常 sprite，顯示跌倒圖
	if has_trip:
		if is_instance_valid(_trip_sprite):
			_trip_sprite.visible = is_tripped
		if is_tripped:
			_sprite.visible = false
			if is_instance_valid(_idle_sprite): _idle_sprite.visible = false
			if is_instance_valid(_mg_sprite):   _mg_sprite.visible   = false

func _physics_process(_delta: float) -> void:
	if is_tripped:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):  dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"): dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):    dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):  dir.y += 1.0
	velocity = dir.normalized() * speed
	move_and_slide()

func _auto_attack() -> void:
	if char_id == "wukong":
		_do_wukong_melee()
		return
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return
	var nearest: Node2D = null
	var min_dist := INF
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < min_dist:
			min_dist = d
			nearest  = e
	if nearest == null or not is_instance_valid(nearest):
		return

	var base_dir := (nearest.global_position - global_position).normalized()
	var dmg := int((15.0 + (level - 1) * 2.5 + float(bullet_damage_bonus)) * damage_multiplier)

	for i in bullet_count:
		var angle_off := 0.0
		if bullet_count > 1:
			angle_off = (i - (bullet_count - 1) * 0.5) * 0.45
		var b = bullet_scene.instantiate()
		b.direction      = base_dir.rotated(angle_off)
		b.damage         = dmg
		b.pierce         = bullet_pierce
		b.home_target    = nearest
		b.has_trip_stun  = has_trip
		get_parent().get_node("Bullets").add_child(b)
		b.global_position = global_position

func _do_wukong_melee() -> void:
	var enemies      := get_tree().get_nodes_in_group("enemies")
	var swing_dir    := velocity.normalized() if velocity.length_squared() > 1.0 else (Vector2.RIGHT if _facing_right else Vector2.LEFT)
	var nearest_dist := INF
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < nearest_dist:
			nearest_dist = d
			swing_dir = (e.global_position - global_position).normalized()
	_swing_dir     = swing_dir
	_swing_hit_ids.clear()
	_swing_flash   = 0.3
	queue_redraw()

func take_damage(amount: int) -> void:
	if Global.hp_lock:
		return
	amount = min(amount, int(max_hp * 0.80))
	if invincible:
		return
	if has_shield and shield_hp > 0:
		shield_hp = max(0, shield_hp - amount)
		if shield_hp <= 0:
			shield_break_flash = 0.5
		queue_redraw()
		return
	hp = max(0, hp - amount)
	hp_changed.emit(hp, max_hp)
	invincible = true
	inv_timer  = 1.0
	if hp <= 0:
		died.emit()

func gain_exp(amount: int) -> void:
	exp += amount
	while exp >= exp_to_next:
		exp         -= exp_to_next
		level       += 1
		exp_to_next  = int(exp_to_next * 1.28)
		level_changed.emit(level)
	exp_changed.emit(exp, exp_to_next)

func heal(amount: int) -> void:
	hp = min(max_hp, hp + amount)
	hp_changed.emit(hp, max_hp)

func on_enemy_killed() -> void:
	if vampiric_heal > 0:
		heal(vampiric_heal)

# ─── 範圍爆炸 ────────────────────────────────────────────────
var bomb_radius: float = 180.0

func _do_area_bomb() -> void:
	var dmg := int((20.0 + level * 3 + float(bullet_damage_bonus)) * damage_multiplier)
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and global_position.distance_to(e.global_position) < bomb_radius:
			e.take_damage(dmg, false)
	area_bomb_flash = 0.5
	queue_redraw()

# ─── 繪製 ────────────────────────────────────────────────────
func _draw() -> void:
	# 悟空揮擊扇形特效
	if char_id == "wukong" and _swing_flash > 0.0:
		var t    := _swing_flash / 0.3
		var ba   := _swing_dir.angle()
		var _raw := deg_to_rad(60.0 + (bullet_count - 1) * 20.0)
		var fh   := PI if _raw >= PI else _raw
		var rng  := 120.0 + bullet_pierce * 20.0
		const SEGS := 48
		if fh >= PI:
			draw_circle(Vector2.ZERO, rng, Color(1.0, 0.88, 0.1, t * 0.28))
			draw_arc(Vector2.ZERO, rng, 0.0, TAU, SEGS, Color(1.0, 0.88, 0.1, t * 0.85), 2.5)
		else:
			var pts := PackedVector2Array()
			pts.append(Vector2.ZERO)
			for i in SEGS + 1:
				var a := ba - fh + fh * 2.0 * float(i) / float(SEGS)
				pts.append(Vector2(cos(a), sin(a)) * rng)
			draw_colored_polygon(pts, Color(1.0, 0.88, 0.1, t * 0.28))
			draw_arc(Vector2.ZERO, rng, ba - fh, ba + fh, SEGS, Color(1.0, 0.88, 0.1, t * 0.85), 2.5)
			draw_line(Vector2.ZERO, Vector2(cos(ba - fh), sin(ba - fh)) * rng, Color(1.0, 0.88, 0.1, t * 0.7), 2.0)
			draw_line(Vector2.ZERO, Vector2(cos(ba + fh), sin(ba + fh)) * rng, Color(1.0, 0.88, 0.1, t * 0.7), 2.0)

	# 強化模式光環
	if powered_mode:
		var pulse := 0.6 + sin(power_aura_phase) * 0.4
		draw_arc(Vector2.ZERO, 44.0, 0.0, TAU, 64, Color(1.0, 0.85, 0.0, pulse * 0.9), 4.0)
		draw_arc(Vector2.ZERO, 50.0, 0.0, TAU, 64, Color(1.0, 0.5, 0.0, pulse * 0.4), 6.0)
		for i in 6:
			var a := power_aura_phase + i * TAU / 6.0
			var pt := Vector2(cos(a), sin(a)) * 44.0
			draw_circle(pt, 4.0, Color(1.0, 1.0, 0.5, pulse))

	# 護盾破碎紅色閃爍
	var shield_r := 49.4 if char_id == "wukong" else 33.8
	if shield_break_flash > 0.0:
		var bt: float = shield_break_flash / 0.5
		draw_arc(Vector2.ZERO, shield_r + 2.0,  0.0, TAU, 48, Color(1.0, 0.1, 0.1, bt * 0.9), 6.0)
		draw_arc(Vector2.ZERO, shield_r + 10.0, 0.0, TAU, 48, Color(1.0, 0.4, 0.0, bt * 0.45), 11.0)

	# 護盾視覺
	if has_shield:
		if shield_hp > 0:
			var ratio: float = float(shield_hp) / float(shield_max_hp)
			var arc_col := Color(0.1 + (1.0 - ratio) * 0.9,
								 0.85 - (1.0 - ratio) * 0.55,
								 1.0 - (1.0 - ratio) * 0.9, 0.92)
			draw_arc(Vector2.ZERO, shield_r, 0.0, TAU, 64, Color(0.2, 0.25, 0.3, 0.4), 5.0)
			draw_arc(Vector2.ZERO, shield_r, -PI * 0.5,
					-PI * 0.5 + TAU * ratio, 64, arc_col, 5.0)
			draw_arc(Vector2.ZERO, shield_r, 0.0, TAU, 64,
					Color(arc_col.r, arc_col.g, arc_col.b, 0.2), 11.0)
		else:
			draw_arc(Vector2.ZERO, shield_r, 0.0, TAU, 64, Color(0.3, 0.35, 0.42, 0.4), 3.0)
			var secs_left: int = int(ceil(shield_refresh_timer))
			draw_string(ThemeDB.fallback_font, Vector2(-6.0, 6.0),
						str(secs_left), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
						Color(0.5, 0.7, 0.9, 0.85))

	# 非洲人稱號
	if has_africa_title:
		draw_string(ThemeDB.fallback_font, Vector2(-29.0, -63.0),
					"非洲人", HORIZONTAL_ALIGNMENT_CENTER, 62, 18,
					Color(0.1, 0.05, 0.0, 0.88))
		draw_string(ThemeDB.fallback_font, Vector2(-31.0, -65.0),
					"非洲人", HORIZONTAL_ALIGNMENT_CENTER, 62, 18,
					Color(0.95, 0.72, 0.0))

	# 悟空 E: 立棍
	if char_id == "wukong" and _staff_flash > 0.0:
		var sf  := _staff_flash / 0.5
		const _SL := 700.0
		const _SW := 70.0
		var fw  := _staff_dir
		if _staff_texture != null:
			var center := fw * (_SL * 0.5)
			draw_set_transform(center, fw.angle() - PI * 0.5, Vector2.ONE)
			draw_texture_rect(_staff_texture,
				Rect2(-_SW, -_SL * 0.5, _SW * 2.0, _SL),
				false, Color(1.0, 1.0, 1.0, sf))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var ri := Vector2(-fw.y, fw.x)
			var pts := PackedVector2Array([ri * -_SW, ri * _SW, fw * _SL + ri * _SW, fw * _SL + ri * -_SW])
			draw_colored_polygon(pts, Color(1.0, 0.88, 0.1, sf * 0.35))
			for si in 4:
				draw_line(pts[si], pts[(si+1)%4], Color(1.0, 0.95, 0.2, sf*0.9), 3.0)

	# 吉祥物 Q: 衝擊波
	if char_id != "wukong" and _shockwave_flash > 0.0:
		var sf := _shockwave_flash / 0.45
		var r  := 380.0 * (1.0 - sf)
		draw_circle(Vector2.ZERO, r, Color(0.4, 0.85, 1.0, sf * 0.22))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(0.5, 0.92, 1.0, sf * 0.85), 5.0)

	# 悟空 Q: 瞬移閃光 + 暈眩範圍
	if char_id == "wukong" and _teleport_flash > 0.0:
		var sf := _teleport_flash / 0.45
		draw_circle(Vector2.ZERO, 220.0 * (1.0 - sf), Color(0.5, 1.0, 0.6, sf * 0.18))
		draw_arc(Vector2.ZERO, 220.0 * (1.0 - sf), 0.0, TAU, 48, Color(0.4, 1.0, 0.55, sf * 0.7), 3.0)
		draw_circle(Vector2.ZERO, 40.0 * sf, Color(0.6, 1.0, 0.7, sf * 0.6))
		draw_arc(Vector2.ZERO, 44.0, 0.0, TAU, 32, Color(0.5, 1.0, 0.6, sf * 0.9), 3.5)

	if area_bomb_flash <= 0.0:
		return
	var t := area_bomb_flash / 0.5

	draw_circle(Vector2.ZERO, bomb_radius, Color(1.0, 0.45, 0.0, t * 0.45))
	var ring_r := bomb_radius + (60.0 * (1.0 - t))
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 64, Color(1.0, 0.8, 0.1, t * 0.9), 5.0)
	if t > 0.6:
		draw_circle(Vector2.ZERO, bomb_radius * 0.5, Color(1.0, 1.0, 0.8, (t - 0.6) * 2.0 * 0.6))


# ─── 環形射擊 ────────────────────────────────────────────────
func _do_orbit_shot() -> void:
	var dmg := int((15.0 + (level - 1) * 2.5 + float(bullet_damage_bonus)) * damage_multiplier)
	for i in 8:
		var angle := i * TAU / 8.0
		var b = bullet_scene.instantiate()
		b.direction        = Vector2.RIGHT.rotated(angle)
		b.damage           = dmg
		b.pierce           = bullet_pierce
		b.home_target      = null
		b.is_orbit         = true
		b.orbit_ring_level = orbit_ring_level
		b.scale            = Vector2(orbit_scale, orbit_scale)
		get_parent().get_node("Bullets").add_child(b)
		b.global_position = global_position

func _activate_skill_q() -> void:
	if char_id == "wukong":
		var target := get_global_mouse_position().clamp(
			Vector2(-1480.0, -780.0), Vector2(1480.0, 780.0))
		global_position = target
		_teleport_flash = 0.45
		# 落點範圍暈眩
		const TELE_R := 220.0
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e): continue
			if (e as Node2D).global_position.distance_to(global_position) <= TELE_R:
				e.call("apply_stun", 3.0)
		queue_redraw()
	else:
		const SW_R := 380.0
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e): continue
			var diff: Vector2 = (e as Node2D).global_position - global_position
			if diff.length() > SW_R: continue
			var dir := diff.normalized() if diff.length_squared() > 0.01 else Vector2.RIGHT
			if e.is_in_group("boss"):
				e.call("apply_stun", 5.0)
			else:
				e.call("apply_knockback", dir, 600.0)
				e.call("apply_stun", 5.0)
		_shockwave_flash = 0.45
		queue_redraw()

func _activate_skill_e() -> void:
	if char_id == "wukong":
		var mouse_world := get_global_mouse_position()
		_staff_dir = (mouse_world - global_position).normalized()
		if _staff_dir.length_squared() < 0.01:
			_staff_dir = Vector2.RIGHT if _facing_right else Vector2.LEFT
		_staff_flash = 0.5
		const SL := 700.0
		const SW := 70.0
		var right := Vector2(-_staff_dir.y, _staff_dir.x)
		var dmg := int(400.0 * damage_multiplier)
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e): continue
			var to_e: Vector2 = (e as Node2D).global_position - global_position
			var along := to_e.dot(_staff_dir)
			var across := to_e.dot(right)
			if along >= 0.0 and along <= SL and absf(across) <= SW:
				e.take_damage(dmg, false)
				if has_trip and randf() < 0.1:
					e.call("apply_stun", 3.0)
		queue_redraw()
	else:
		_mg_active    = true
		_mg_timer     = 15.0
		_mg_atk_timer = 0.0

func _fire_machinegun() -> void:
	var dir := (get_global_mouse_position() - global_position).normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT if _facing_right else Vector2.LEFT
	var b = bullet_scene.instantiate()
	b.direction     = dir
	b.damage        = int(1.0 * damage_multiplier)
	b.pierce        = bullet_pierce * 2
	b.home_target   = null
	b.has_trip_stun = has_trip
	b.no_vamp       = true
	get_parent().get_node("Bullets").add_child(b)
	b.global_position = global_position

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
