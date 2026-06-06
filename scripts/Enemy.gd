extends CharacterBody2D

signal died(vamp: bool)

var player: Node2D = null
var hp: int = 10
var max_hp: int = 10
var damage: int = 8
var speed: float = 65.0
var enemy_type: int = 0   # 0=文件 1=資料夾 2=問號方塊

var contact_timer:    float = 0.0
var flash_timer:      float = 0.0
var hit_flash:        bool  = false
var stun_timer:       float = 0.0
var burn_timer:          float = 0.0
var _burn_tick_interval: float = 5.0
var _burn_dmg_timer:     float = 0.0
var _knockback_vel:      Vector2 = Vector2.ZERO
var _knockback_timer:    float   = 0.0

func _ready() -> void:
	add_to_group("enemies")

func _process(delta: float) -> void:
	if contact_timer > 0.0:
		contact_timer -= delta
	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0:
			hit_flash = false
	if stun_timer > 0.0:
		stun_timer -= delta
		stun_timer = maxf(0.0, stun_timer)
	if burn_timer > 0.0:
		burn_timer -= delta
		burn_timer = maxf(0.0, burn_timer)
		_burn_dmg_timer -= delta
		if _burn_dmg_timer <= 0.0:
			_burn_dmg_timer = _burn_tick_interval
			take_damage(maxi(1, int(float(max_hp) * 0.007)), false)
	else:
		_burn_dmg_timer = 0.0
	queue_redraw()

func apply_stun(duration: float) -> void:
	stun_timer = maxf(stun_timer, duration)

func apply_knockback(dir: Vector2, force: float) -> void:
	_knockback_vel   = dir * force
	_knockback_timer = 0.5

func apply_burn(duration: float, tick_interval: float) -> void:
	if burn_timer <= 0.0:
		_burn_dmg_timer = 0.0   # 立即觸發第一次扣血
	if duration > burn_timer:
		burn_timer          = duration
		_burn_tick_interval = tick_interval

func _physics_process(delta: float) -> void:
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		velocity = _knockback_vel * clampf(_knockback_timer / 0.5, 0.0, 1.0)
		move_and_slide()
		return
	if stun_timer > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if not is_instance_valid(player):
		return
	var dir := (player.global_position - global_position).normalized()
	velocity = dir * speed
	move_and_slide()
	if global_position.distance_to(player.global_position) < 26.0 and contact_timer <= 0.0:
		player.take_damage(damage)
		contact_timer = 1.0

func take_damage(amount: int, vamp: bool = true) -> void:
	hp -= amount
	Global.record_damage(amount)
	hit_flash = true
	flash_timer = 0.14
	_spawn_damage_number(amount)
	if hp <= 0:
		died.emit(vamp)
		queue_free()

func _spawn_damage_number(amount: int) -> void:
	var ui := get_tree().current_scene.get_node_or_null("UI")
	if ui == null:
		return
	var canvas_pos := get_viewport().get_canvas_transform() * global_position
	canvas_pos += Vector2(randf_range(-14.0, 14.0), -20.0)

	var lbl := Label.new()
	lbl.text = "-%d" % amount
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.15))
	lbl.position = canvas_pos
	lbl.z_index  = 10
	ui.add_child(lbl)

	var tween := lbl.create_tween()
	tween.tween_property(lbl, "position:y", canvas_pos.y - 48.0, 0.6)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.6)
	tween.tween_callback(lbl.queue_free)

func _draw() -> void:
	var a := 0.35 if hit_flash else 1.0

	match enemy_type:
		0:  # 白色文件
			draw_rect(Rect2(-10.0, -14.0, 20.0, 28.0), Color(0.88, 0.91, 0.95, a), true)
			draw_rect(Rect2(-10.0, -14.0, 20.0, 28.0), Color(0.5, 0.55, 0.65, a), false, 1.5)
			for i in 3:
				draw_line(Vector2(-7.0, -3.0 + i * 6.0), Vector2(7.0, -3.0 + i * 6.0),
						Color(0.55, 0.6, 0.72, a), 1.5)
			draw_colored_polygon(
				[Vector2(3.0, -14.0), Vector2(10.0, -14.0), Vector2(10.0, -7.0)],
				Color(0.62, 0.66, 0.78, a))
		1:  # 資料夾
			draw_rect(Rect2(-12.0, -12.0, 11.0, 6.0), Color(0.7, 0.54, 0.33, a), true)
			draw_rect(Rect2(-12.0, -7.0, 24.0, 18.0), Color(0.82, 0.64, 0.4, a), true)
			draw_rect(Rect2(-12.0, -7.0, 24.0, 18.0), Color(0.5, 0.36, 0.16, a), false, 1.5)
		2:  # 問號方塊
			draw_rect(Rect2(-12.0, -14.0, 24.0, 28.0), Color(0.9, 0.92, 0.96, a), true)
			draw_rect(Rect2(-12.0, -14.0, 24.0, 28.0), Color(0.4, 0.45, 0.62, a), false, 2.0)
			draw_circle(Vector2(0.0, -3.5), 6.5, Color(0.22, 0.27, 0.48, a))
			draw_circle(Vector2(0.0, -3.5), 4.5, Color(0.9, 0.92, 0.96, a))
			draw_circle(Vector2(0.0, 7.5), 2.8, Color(0.22, 0.27, 0.48, a))

	# 燃燒指示（藍色）
	if burn_timer > 0.0:
		draw_circle(Vector2.ZERO, 14.0, Color(0.0, 0.35, 1.0, 0.30))
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 24, Color(0.1, 0.55, 1.0, 0.85), 2.0)

	# 暈眩指示
	if stun_timer > 0.0:
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 32, Color(1.0, 0.88, 0.1, 0.9), 2.5)

	# 血量條
	var bw := 26.0
	var bh := 4.0
	var ratio := float(hp) / float(max_hp)
	draw_rect(Rect2(-bw * 0.5, -23.0, bw, bh), Color(0.15, 0.05, 0.05, 0.85), true)
	if ratio > 0.0:
		draw_rect(Rect2(-bw * 0.5, -23.0, bw * ratio, bh), Color(0.9, 0.15, 0.1, 0.9), true)
