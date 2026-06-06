extends Node2D

const LEVEL_DURATION := 225.0  # 3分45秒
const MAX_ENEMIES    := 120    # 場上小怪上限
const MAP_HALF_W     := 1600.0 # 地圖半寬（世界座標）
const MAP_HALF_H     := 900.0  # 地圖半高（世界座標）

@onready var camera:       Camera2D    = $Camera2D
@onready var enemies_node: Node2D      = $Enemies
@onready var bullets_node: Node2D      = $Bullets
@onready var gems_node:    Node2D      = $Gems
@onready var ui_layer:     CanvasLayer = $UI

var enemy_scene:   PackedScene
var exp_gem_scene: PackedScene
var player_scene:  PackedScene
var boss_scene:    PackedScene
var player_node:   Node2D
var boss_node:     Node2D = null

var spawn_timer:    float = 1.5
var spawn_interval: float = 2.0
var game_time:      float = 0.0
var game_over:      bool  = false
var victory:        bool  = false
var score:          int   = 0
var is_upgrading:   bool  = false
var is_paused:      bool  = false
var boss_spawned:   bool  = false
var _bgm_player:     AudioStreamPlayer = null

# UI 節點
var hp_bar:             ProgressBar
var exp_bar:            ProgressBar
var timer_label:        Label
var level_label:        Label
var score_label:        Label
var overlay:            ColorRect
var overlay_label:      Label
var overlay_vbox:       VBoxContainer
var pause_overlay:      ColorRect
var boss_bar_panel:     Control       # Boss HP 區塊容器
var boss_hp_bar:        ProgressBar
var boss_warning_label: Label
var boss_warning_timer: float = 0.0
var beam_warn_label:    Label
var _upgrade_panel:      Control = null
var _refresh_left:       int = 0
var _pin_left:           int = 0
var _pinned_upgrade:     Dictionary = {}
var _pinned_slot:        int = -1
var _current_upgrades:   Array = []
var _cheat_boosted:      bool = false
var _skill_levels:        Dictionary = {}
var _skill_display_label: Label = null
var _skill_q_label:       Label = null
var _skill_e_label:       Label = null
var _dev_panel:       Control = null
var _dev_stats_lbl:   Label   = null
var _dev_stop_spawn:  bool    = false
var _dev_skill_panel: Control = null

# ─── 學習模式 ─────────────────────────────────────────────────
var _questions:            Array = []
var _qa_panel:             Control = null
var _is_qa:                bool = false
var _learn_revive_used:    bool = false
var _learn_q_charges:      int  = 99
var _learn_e_charges:      int  = 99
var _learn_refresh_earned: int  = 0
var _learn_pin_earned:     int  = 0
var _learn_action_cap:     int  = 0
var _learn_upgrade_locks:  Array = [true, false, true]

# ─── 升級池 ───────────────────────────────────────────────────
const UPGRADE_POOL := [
	{"id": "dmg",       "name": "全傷強化",  "desc": "所有傷害 +8（子彈/爆炸/環射）","color": Color(1.0, 0.45, 0.15)},
	{"id": "atkspd",    "name": "攻速強化",  "desc": "攻擊速度提升 15%",           "color": Color(1.0, 0.88, 0.1)},
	{"id": "movspd",    "name": "移速強化",  "desc": "移動速度 +30",               "color": Color(0.2, 0.95, 0.5)},
	{"id": "maxhp",     "name": "生命強化",  "desc": "最大HP +30，立即回復",       "color": Color(0.15, 1.0, 0.3)},
	{"id": "multishot", "name": "多重射擊",  "desc": "同時多射 1 顆子彈",          "color": Color(0.0, 0.82, 1.0)},
	{"id": "magnet",    "name": "磁吸強化",  "desc": "寶石吸引範圍 +120",          "color": Color(0.72, 0.3, 1.0)},
	{"id": "vampiric",  "name": "吸血效果",  "desc": "擊殺敵人回復 1 HP",          "color": Color(0.95, 0.1, 0.2)},
	{"id": "pierce",    "name": "穿透射擊",  "desc": "子彈可額外穿透 1 個敵人",    "color": Color(0.2, 0.75, 1.0)},
	{"id": "area_bomb", "name": "範圍爆炸",  "desc": "每 4 秒爆炸，傷害周圍敵人",  "color": Color(1.0, 0.35, 0.0)},
	{"id": "orbit_ring","name": "環形射擊",  "desc": "每 2.5 秒向八方同時發射",    "color": Color(0.95, 0.82, 0.0)},
	{"id": "shield",    "name": "能量護盾",  "desc": "護盾層 40 耐久，優先承受傷害，10 秒後重生", "color": Color(0.2, 0.72, 1.0)},
	{"id": "africa",    "name": "非洲人之星", "desc": "恭喜抽到了銘謝惠顧（機率極低），你是萬中選一的非洲人！此技能沒有效果", "color": Color(0.58, 0.58, 0.58)},
	{"id": "trip",      "name": "平地摔",    "desc": "走路時有低機率跌倒。",                                           "color": Color(0.72, 0.45, 0.18)},
]

# ─── 初始化 ───────────────────────────────────────────────────
func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.02, 0.04, 0.13))
	_setup_bgm()

	enemy_scene   = load("res://scenes/Enemy.tscn")
	exp_gem_scene = load("res://scenes/ExpGem.tscn")
	player_scene  = load("res://scenes/Player.tscn")
	boss_scene    = load("res://scenes/Boss.tscn")

	player_node = player_scene.instantiate()
	add_child(player_node)
	player_node.died.connect(_on_player_died)
	player_node.hp_changed.connect(_on_hp_changed)
	player_node.exp_changed.connect(_on_exp_changed)
	player_node.level_changed.connect(_on_level_changed)
	player_node.skill_on_cooldown.connect(_on_skill_cooldown)

	_setup_ui()
	_init_action_counts()
	_learn_action_cap = _refresh_left
	if Global.learn_mode:
		_load_questions()
	if Global.dev_mode:
		if Global.dummy_mode:
			Global.reset_stats()
		_setup_dev_panel()
	call_deferred("_initial_spawn")

func _initial_spawn() -> void:
	for i in 7:
		spawn_enemy()


func _toggle_pause() -> void:
	is_paused             = not is_paused
	pause_overlay.visible = is_paused
	_set_game_nodes_active(not is_paused)

# 暫停/恢復：切換敵人、玩家、子彈、寶石的處理狀態
func _set_game_nodes_active(active: bool) -> void:
	var mode := Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	enemies_node.process_mode = mode
	bullets_node.process_mode = mode
	gems_node.process_mode    = mode
	if is_instance_valid(player_node):
		player_node.process_mode = mode

# ─── 主循環 ───────────────────────────────────────────────────
func _process(delta: float) -> void:
	# ESC 暫停（在所有判斷之前）
	if not game_over and not victory and not is_upgrading:
		if Input.is_action_just_pressed("ui_cancel"):
			_toggle_pause()

	# 開發者模式統計更新
	if Global.dev_mode and is_instance_valid(_dev_stats_lbl):
		if Global.dummy_mode:
			var dps := Global.get_dps()
			_dev_stats_lbl.text = "秒傷: %.0f\n總傷: %d" % [dps, Global.total_dmg]
		else:
			_dev_stats_lbl.text = ""

	# 結束畫面：R 快速重開
	if game_over or victory:
		if Input.is_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		return

	if is_upgrading or is_paused or _is_qa:
		return

	game_time += delta

	# 碼表顯示（計時，從 0 往上）
	var m := int(game_time) / 60
	var s := int(game_time) % 60
	timer_label.text = "%02d:%02d" % [m, s]
	if game_time >= LEVEL_DURATION * 0.85:
		timer_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25))
	elif game_time >= LEVEL_DURATION * 0.65:
		timer_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	else:
		timer_label.add_theme_color_override("font_color", Color.WHITE)

	# Boss 警告漸隱
	if boss_warning_timer > 0.0:
		boss_warning_timer -= delta
		boss_warning_label.visible = boss_warning_timer > 0.0

	# Boss 光束預警倒計時（顯示在計時器下方）
	if is_instance_valid(boss_node) and boss_node.get("is_beam_warning"):
		beam_warn_label.visible = true
		var t: float = float(boss_node.get("beam_warning_timer"))
		beam_warn_label.text = "⚡  %.1f" % t
		var blink := fmod(t * 5.0, 1.0) > 0.45
		beam_warn_label.add_theme_color_override("font_color",
			Color(1.0, 0.05, 0.0) if blink else Color(1.0, 0.45, 0.0))
	else:
		beam_warn_label.visible = false

	# 時間到 → 生成 Boss（之後停止生成普通敵人）
	if not boss_spawned and game_time >= LEVEL_DURATION:
		_spawn_boss()
		return

	# 普通敵人生成（達到上限時暫停生成）
	if not _dev_stop_spawn:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			var current_count := enemies_node.get_child_count()
			if current_count < MAX_ENEMIES:
				var slots  := MAX_ENEMIES - current_count
				var count  := mini(1 + int(game_time / 25.0), slots)
				for i in count:
					spawn_enemy()
			spawn_interval = maxf(0.55, 2.0 - game_time * 0.0045)
			spawn_timer    = spawn_interval

	# 攝影機跟隨
	if is_instance_valid(player_node):
		# 空氣牆：限制玩家在地圖範圍內
		player_node.global_position = player_node.global_position.clamp(
			Vector2(-MAP_HALF_W + 120.0, -MAP_HALF_H + 120.0),
			Vector2( MAP_HALF_W - 120.0,  MAP_HALF_H - 120.0))
		camera.global_position = camera.global_position.lerp(
			player_node.global_position, 7.5 * delta)
		# 鏡頭不超出地圖邊緣
		camera.global_position = camera.global_position.clamp(
			Vector2(-MAP_HALF_W + 440.0, -MAP_HALF_H + 160.0),
			Vector2( MAP_HALF_W - 440.0,  MAP_HALF_H - 160.0))

	# 秘技啟動後補滿刷新/釘選
	if not _cheat_boosted and is_instance_valid(player_node) and bool(player_node.get("powered_mode")):
		_cheat_boosted = true
		_refresh_left  = 99
		_pin_left      = 99

	# Boss HP 條即時更新（受傷閃爍）
	if boss_hp_bar != null and is_instance_valid(boss_node):
		var new_val := float(boss_node.hp) / float(boss_node.max_hp) * 100.0
		if new_val < boss_hp_bar.value:
			boss_hp_bar.add_theme_stylebox_override("fill", _flat(Color(1.0, 0.9, 0.1), 4))
			var t := boss_hp_bar.create_tween()
			t.tween_callback(func():
				boss_hp_bar.add_theme_stylebox_override("fill", _flat(Color(0.9, 0.12, 0.05), 4))
			).set_delay(0.12)
		boss_hp_bar.value = new_val

	# 技能冷卻顯示
	if is_instance_valid(player_node) and _skill_q_label != null:
		var q_cd := float(player_node.get("skill_q_cd"))
		var e_cd := float(player_node.get("skill_e_cd"))
		var mg   := bool(player_node.get("_mg_active"))
		var mgt  := float(player_node.get("_mg_timer"))
		var is_wukong: bool = (player_node.get("char_id") == "wukong")
		var q_name := "筋斗雲" if is_wukong else "衝擊波"
		var e_name := "立棍"   if is_wukong else "機槍掃射"
		var q_ready := q_cd <= 0.0
		var e_ready := e_cd <= 0.0
		_skill_q_label.text = "[Q] %s  %s" % [q_name, "準備好！" if q_ready else "%.0fs" % q_cd]
		_skill_e_label.text = "[E] %s  %s" % [e_name,
			"掃射中 %.0fs" % mgt if mg else ("準備好！" if e_ready else "%.0fs" % e_cd)]
		_skill_q_label.add_theme_color_override("font_color",
			Color(0.2, 1.0, 0.45, 0.95) if q_ready else Color(0.7, 0.88, 1.0, 0.88))
		_skill_e_label.add_theme_color_override("font_color",
			Color(1.0, 0.55, 0.1, 0.95) if mg else (Color(0.2, 1.0, 0.45, 0.95) if e_ready else Color(1.0, 0.82, 0.4, 0.88)))

	queue_redraw()

# ─── 生成普通敵人 ─────────────────────────────────────────────
func spawn_enemy() -> void:
	if not is_instance_valid(camera) or enemy_scene == null:
		return
	var cam_pos := camera.global_position
	var vp      := get_viewport_rect().size
	if vp.x < 1.0:
		vp = Vector2(1280.0, 720.0)
	var hw := vp.x * 0.5 + 95.0
	var hh := vp.y * 0.5 + 95.0

	var side := randi() % 4
	var pos  := Vector2.ZERO
	match side:
		0: pos = Vector2(randf_range(-hw, hw), -hh)
		1: pos = Vector2(randf_range(-hw, hw),  hh)
		2: pos = Vector2(-hw, randf_range(-hh, hh))
		3: pos = Vector2( hw, randf_range(-hh, hh))

	var e = enemy_scene.instantiate()
	enemies_node.add_child(e)
	e.global_position = cam_pos + pos
	e.player          = player_node
	e.enemy_type      = randi() % 3

	# 基礎屬性
	var base_hp  := int(8.0 + game_time * 0.28)
	var base_dmg := 14 + int(game_time * 0.09)
	var base_spd := 80.0 + game_time * 0.14

	# 時間過半後屬性平滑增強（從 50% 到 100% 線性遞增）
	if game_time >= LEVEL_DURATION * 0.5:
		var late_t    := clampf((game_time - LEVEL_DURATION * 0.5) / (LEVEL_DURATION * 0.5), 0.0, 1.0)
		var dmg_scale := 0.7 if Global.difficulty == "hell" else 0.30
		base_hp  = int(base_hp  * (1.0 + 0.45 * late_t))
		base_dmg = int(base_dmg * (1.0 + dmg_scale * late_t))
		base_spd *= (1.0 + 0.15 * late_t)
		e.scale  = Vector2(1.0 + 0.3 * late_t, 1.0 + 0.3 * late_t)

	e.max_hp = base_hp
	e.hp     = base_hp
	var _spd_mult := 1.0
	match Global.difficulty:
		"normal": _spd_mult = 1.3
		"hard":   _spd_mult = 1.5
		"hell":   _spd_mult = 1.5
	e.speed  = base_spd * _spd_mult
	e.damage = int(base_dmg * (0.82 if Global.difficulty == "hell" else 1.0))
	e.died.connect(_on_enemy_died.bind(e))

# ─── 生成 Boss ────────────────────────────────────────────────
func _spawn_boss() -> void:
	boss_spawned = true

	var cam_pos := camera.global_position
	var vp      := get_viewport_rect().size
	if vp.x < 1.0:
		vp = Vector2(1280.0, 720.0)

	boss_node = boss_scene.instantiate()
	enemies_node.add_child(boss_node)
	var spawn_pos := (cam_pos + Vector2(vp.x * 0.5 + 200.0, 0.0)).clamp(
		Vector2(-MAP_HALF_W + 100.0, -MAP_HALF_H + 100.0),
		Vector2( MAP_HALF_W - 100.0,  MAP_HALF_H - 100.0))
	boss_node.global_position = spawn_pos
	boss_node.player          = player_node
	boss_node.bullets_node    = bullets_node
	boss_node.map_half_w      = MAP_HALF_W
	boss_node.map_half_h      = MAP_HALF_H
	boss_node.died.connect(_on_boss_died)

	boss_bar_panel.visible     = true
	boss_warning_label.visible = true
	boss_warning_timer         = 3.5

# ─── 事件回呼 ─────────────────────────────────────────────────
func _on_enemy_died(vamp: bool, e: Node2D) -> void:
	score += 10
	score_label.text = "得分: %d" % score
	if is_instance_valid(player_node) and vamp:
		player_node.on_enemy_killed()
	if exp_gem_scene == null:
		return
	var gem = exp_gem_scene.instantiate()
	gems_node.add_child(gem)
	gem.global_position = e.global_position
	gem.player          = player_node
	gem.exp_value       = 3 + int(game_time / 30.0)  # 每 30 秒增加 1 EXP

func _on_boss_died() -> void:
	boss_node              = null
	boss_bar_panel.visible = false
	score += 500
	score_label.text = "得分: %d" % score
	_trigger_victory()

func _on_player_died() -> void:
	if game_over:
		return
	if Global.learn_mode and not _learn_revive_used:
		is_paused             = false
		pause_overlay.visible = false
		_set_game_nodes_active(false)
		_show_revival_option()
		return
	game_over             = true
	is_paused             = false
	pause_overlay.visible = false
	_set_game_nodes_active(false)   # 停止所有敵人/玩家繼續處理
	overlay.visible       = true
	overlay.color         = Color(0.55, 0.04, 0.04, 0.84)
	overlay_label.text    = "遊戲結束\n\n得分: %d" % score
	_show_end_buttons()

func _trigger_victory() -> void:
	if victory:
		return
	victory               = true
	is_paused             = false
	pause_overlay.visible = false
	_set_game_nodes_active(false)
	overlay.visible       = true
	overlay.color         = Color(0.04, 0.22, 0.6, 0.84)
	overlay_label.text    = "倖存成功！\n\n得分: %d" % score
	_show_end_buttons()

func _on_hp_changed(hp: int, max_hp: int) -> void:
	hp_bar.value = float(hp) / float(max_hp) * 100.0

func _on_exp_changed(cur: int, needed: int) -> void:
	exp_bar.value = float(cur) / float(needed) * 100.0

func _on_level_changed(lv: int) -> void:
	level_label.text = "LV.%d" % lv
	if lv > 1:
		_show_upgrade_menu()

# ─── 遊戲結束/勝利按鈕 ────────────────────────────────────────
func _show_end_buttons() -> void:
	var btn_row := HBoxContainer.new()
	btn_row.alignment    = BoxContainer.ALIGNMENT_CENTER
	btn_row.process_mode = Node.PROCESS_MODE_ALWAYS
	btn_row.add_theme_constant_override("separation", 24)
	overlay_vbox.add_child(btn_row)

	var btn_r := _make_end_btn("重新開始 (R)")
	btn_r.pressed.connect(func(): get_tree().reload_current_scene())
	btn_row.add_child(btn_r)

	var btn_l := _make_end_btn("回大廳")
	btn_l.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	btn_row.add_child(btn_l)

func _make_end_btn(txt: String) -> Button:
	var btn := Button.new()
	btn.text                 = txt
	btn.custom_minimum_size  = Vector2(185.0, 55.0)
	btn.process_mode         = Node.PROCESS_MODE_ALWAYS
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color.WHITE)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.07, 0.18, 0.48, 0.92)
	sn.border_color = Color(0.3, 0.58, 1.0)
	sn.set_border_width_all(2)
	sn.set_corner_radius_all(8)
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0.14, 0.32, 0.72, 0.97)
	sh.border_color = Color(0.5, 0.78, 1.0)
	sh.set_border_width_all(2)
	sh.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal",  sn)
	btn.add_theme_stylebox_override("hover",   sh)
	btn.add_theme_stylebox_override("pressed", sh)
	return btn

# ─── 刷新 / 釘選輔助 ──────────────────────────────────────────
func _init_action_counts() -> void:
	match Global.difficulty:
		"easy":   _refresh_left = 10; _pin_left = 10
		"normal": _refresh_left = 5;  _pin_left = 5
		"hard":   _refresh_left = 3;  _pin_left = 3
		"hell":   _refresh_left = 3;  _pin_left = 3  # 地獄共用 _refresh_left

func _can_refresh() -> bool:
	if Global.learn_mode:
		return _learn_refresh_earned < _learn_action_cap + 5
	return _refresh_left > 0

func _can_pin() -> bool:
	if Global.learn_mode:
		var earned := _learn_refresh_earned if Global.difficulty == "hell" else _learn_pin_earned
		return earned < _learn_action_cap + 5
	return _refresh_left > 0 if Global.difficulty == "hell" else _pin_left > 0

func _use_refresh() -> void: _refresh_left = max(0, _refresh_left - 1)

func _use_pin() -> void:
	if Global.difficulty == "hell":
		_refresh_left = max(0, _refresh_left - 1)
	else:
		_pin_left = max(0, _pin_left - 1)

func _action_count_text() -> String:
	if Global.learn_mode:
		var r_rem := _learn_action_cap + 5 - _learn_refresh_earned
		if Global.difficulty == "hell":
			return "刷新/釘選 可賺：%d 次（答題獲得）" % r_rem
		var p_rem := _learn_action_cap + 5 - _learn_pin_earned
		return "刷新可賺：%d  ·  釘選可賺：%d  （答題獲得）" % [r_rem, p_rem]
	if Global.difficulty == "hell":
		return "刷新/釘選 剩餘：%d 次" % _refresh_left
	return "刷新：%d  ·  釘選：%d" % [_refresh_left, _pin_left]

func _pick_upgrades_for_menu() -> void:
	# 極低機率（0.0001%）：三張全是非洲人之星
	if is_instance_valid(player_node) and not bool(player_node.get("has_africa_title")) and randf() < 0.000001:
		var africa: Dictionary = {}
		for u in UPGRADE_POOL:
			if u["id"] == "africa":
				africa = u; break
		if not africa.is_empty():
			_current_upgrades = [africa, africa, africa]
			return

	# 低機率（0.01%）：其中一張是跌倒
	if is_instance_valid(player_node) and not bool(player_node.get("has_trip")) and randf() < 0.0001:
		var trip_upg: Dictionary = {}
		for u in UPGRADE_POOL:
			if u["id"] == "trip":
				trip_upg = u; break
		if not trip_upg.is_empty():
			_current_upgrades = _pick_upgrades(3)
			while _current_upgrades.size() < 3:
				_current_upgrades.append(null)
			_current_upgrades[randi() % 3] = trip_upg
			return

	if _pinned_upgrade.is_empty():
		_current_upgrades = _pick_upgrades(3)
		return
	var pin_id:   String = _pinned_upgrade["id"]
	var pin_slot: int    = clampi(_pinned_slot, 0, 2)
	var atk_pool: Array  = []
	var sur_pool: Array  = []
	for upg in UPGRADE_POOL:
		if upg["id"] == "africa" or upg["id"] == "trip" or _upgrade_maxed(upg["id"]) or upg["id"] == pin_id:
			continue
		if upg["id"] in _ATK_IDS: atk_pool.append(upg)
		else:                      sur_pool.append(upg)
	atk_pool.shuffle(); sur_pool.shuffle()
	var fills: Array = []
	if not atk_pool.is_empty(): fills.append(atk_pool.pop_front())
	if not sur_pool.is_empty(): fills.append(sur_pool.pop_front())
	var rest := atk_pool + sur_pool; rest.shuffle()
	while fills.size() < 2 and not rest.is_empty():
		fills.append(rest.pop_front())
	fills.shuffle()
	_current_upgrades = [null, null, null]
	_current_upgrades[pin_slot] = _pinned_upgrade
	_pinned_upgrade = {}
	_pinned_slot    = -1
	var fi := 0
	for i in 3:
		if i != pin_slot and fi < fills.size():
			_current_upgrades[i] = fills[fi]; fi += 1

func _do_refresh() -> void:
	if Global.learn_mode:
		if _learn_refresh_earned >= _learn_action_cap + 5:
			return
		var n_q := 1
		var note := ""
		if _learn_refresh_earned >= _learn_action_cap:
			n_q  = 5
			note = "⚠ 已超出刷新上限！本次需答 5 題才能刷新"
		var refresh_cb := func():
			_learn_refresh_earned += 1
			_learn_upgrade_locks = [true, false, true]
			_pick_upgrades_for_menu()
			_build_upgrade_panel()
		_show_qa_session(n_q, refresh_cb, note)
		return
	_use_refresh()
	_learn_upgrade_locks = [true, false, true]
	_pick_upgrades_for_menu()
	_build_upgrade_panel()

func _do_pin(upg: Dictionary, slot: int) -> void:
	if Global.learn_mode:
		var earned := _learn_refresh_earned if Global.difficulty == "hell" else _learn_pin_earned
		if earned >= _learn_action_cap + 5:
			return
		var n_q := 1
		var note := ""
		if earned >= _learn_action_cap:
			n_q  = 5
			note = "⚠ 已超出釘選上限！本次需答 5 題才能釘選"
		var cap_upg := upg.duplicate()
		var cap_slot := slot
		var pin_cb := func():
			if Global.difficulty == "hell":
				_learn_refresh_earned += 1
			else:
				_learn_pin_earned += 1
			_pinned_upgrade = cap_upg
			_pinned_slot    = cap_slot
			_build_upgrade_panel()
		_show_qa_session(n_q, pin_cb, note)
		return
	_use_pin()
	_pinned_upgrade = upg.duplicate()
	_pinned_slot    = slot
	_build_upgrade_panel()

func _do_unpin() -> void:
	_pinned_upgrade = {}
	_pinned_slot    = -1
	if Global.difficulty == "hell":
		_refresh_left += 1
	else:
		_pin_left += 1
	_build_upgrade_panel()

# ─── 升級選卡系統 ─────────────────────────────────────────────
func _show_upgrade_menu() -> void:
	is_upgrading = true
	_set_game_nodes_active(false)
	_learn_upgrade_locks = [true, false, true]
	_pick_upgrades_for_menu()
	_build_upgrade_panel()

func _build_upgrade_panel() -> void:
	if is_instance_valid(_upgrade_panel):
		_upgrade_panel.queue_free()

	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_upgrade_panel = panel
	ui_layer.add_child(panel)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.04, 0.14, 0.88)
	panel.add_child(bg)

	var title := Label.new()
	title.text = "升  級！選擇一項強化"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top    = 110.0
	title.offset_bottom = 165.0
	panel.add_child(title)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 36)
	hbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hbox.offset_left   = -480.0
	hbox.offset_right  =  480.0
	hbox.offset_top    = -125.0
	hbox.offset_bottom =  170.0
	panel.add_child(hbox)

	for i in 3:
		var upg = _current_upgrades[i] if i < _current_upgrades.size() else null
		if upg == null:
			continue
		if Global.learn_mode and i < _learn_upgrade_locks.size() and bool(_learn_upgrade_locks[i]):
			hbox.add_child(_make_locked_card())
			continue
		var dyn: Dictionary = upg.duplicate()
		dyn["name"] = _upgrade_name(upg["id"])
		dyn["desc"] = _upgrade_desc(upg["id"])
		var is_pinned: bool = (not _pinned_upgrade.is_empty() and _pinned_upgrade.get("id") == upg.get("id"))
		hbox.add_child(_make_card(dyn, panel, i, is_pinned))

	# 刷新 + 次數顯示
	var act_row := HBoxContainer.new()
	act_row.alignment = BoxContainer.ALIGNMENT_CENTER
	act_row.add_theme_constant_override("separation", 20)
	act_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	act_row.offset_left   = -300.0; act_row.offset_right  =  300.0
	act_row.offset_top    =  185.0; act_row.offset_bottom =  230.0
	panel.add_child(act_row)

	var rbtn := Button.new()
	rbtn.text = "🔄 刷新"
	var _is_africa := _current_upgrades.all(func(u): return u != null and u.get("id", "") == "africa")
	rbtn.disabled = not _can_refresh() or _is_africa
	rbtn.custom_minimum_size = Vector2(110.0, 38.0)
	rbtn.add_theme_font_size_override("font_size", 17)
	rbtn.add_theme_color_override("font_color", Color.WHITE)
	var rsn := StyleBoxFlat.new()
	rsn.bg_color = Color(0.06, 0.16, 0.42, 0.92); rsn.set_border_width_all(2)
	rsn.border_color = Color(0.3, 0.58, 1.0); rsn.set_corner_radius_all(7)
	var rsh := StyleBoxFlat.new()
	rsh.bg_color = Color(0.12, 0.28, 0.68, 0.97); rsh.set_border_width_all(2)
	rsh.border_color = Color(0.5, 0.78, 1.0); rsh.set_corner_radius_all(7)
	rbtn.add_theme_stylebox_override("normal",  rsn)
	rbtn.add_theme_stylebox_override("hover",   rsh)
	rbtn.add_theme_stylebox_override("pressed", rsh)
	rbtn.pressed.connect(func(): _do_refresh())
	act_row.add_child(rbtn)

	var cnt_lbl := Label.new()
	cnt_lbl.text = _action_count_text()
	cnt_lbl.add_theme_font_size_override("font_size", 16)
	cnt_lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0, 0.85))
	act_row.add_child(cnt_lbl)

	if Global.learn_mode:
		var locked_count := 0
		for li in 3:
			if li < _learn_upgrade_locks.size() and bool(_learn_upgrade_locks[li]):
				locked_count += 1
		if locked_count > 0:
			var unlock_cost := 1 if locked_count == 2 else 3
			var unlock_btn := Button.new()
			unlock_btn.text = "🔓 解鎖（%d 題）" % unlock_cost
			unlock_btn.custom_minimum_size = Vector2(120.0, 38.0)
			unlock_btn.add_theme_font_size_override("font_size", 15)
			unlock_btn.add_theme_color_override("font_color", Color.WHITE)
			unlock_btn.process_mode = Node.PROCESS_MODE_ALWAYS
			var usn := StyleBoxFlat.new()
			usn.bg_color    = Color(0.18, 0.12, 0.04, 0.92)
			usn.border_color = Color(1.0, 0.75, 0.1)
			usn.set_border_width_all(2); usn.set_corner_radius_all(7)
			unlock_btn.add_theme_stylebox_override("normal", usn)
			var ush := usn.duplicate() as StyleBoxFlat
			ush.bg_color = Color(0.35, 0.24, 0.04, 0.97)
			unlock_btn.add_theme_stylebox_override("hover",   ush)
			unlock_btn.add_theme_stylebox_override("pressed", ush)
			var cap_cost := unlock_cost
			unlock_btn.pressed.connect(func():
				_show_qa_session(cap_cost, func():
					var locked_slots: Array = []
					for li2 in 3:
						if li2 < _learn_upgrade_locks.size() and bool(_learn_upgrade_locks[li2]):
							locked_slots.append(li2)
					if not locked_slots.is_empty():
						_learn_upgrade_locks[locked_slots[randi() % locked_slots.size()]] = false
					_build_upgrade_panel()
				)
			)
			act_row.add_child(unlock_btn)

func _upgrade_maxed(id: String) -> bool:
	if not is_instance_valid(player_node):
		return false
	var p = player_node
	match id:
		"maxhp":
			var base_hp: int = (80 if p.char_id == "wukong" else 100)
			var cap: int = (30 if Global.difficulty == "hell" else (60 if Global.difficulty == "hard" else (90 if Global.difficulty == "normal" else 120)))
			return p.max_hp >= base_hp + cap
		"vampiric":
			var cap: int = (2 if Global.difficulty == "hell" else (3 if Global.difficulty == "hard" else (4 if Global.difficulty == "normal" else 5)))
			return p.vampiric_heal >= cap
		"pierce":
			var cap: int = (3 if Global.difficulty == "hell" else (2 if Global.difficulty == "hard" else (1 if Global.difficulty == "normal" else 0)))
			return p.bullet_pierce >= cap
		"multishot":
			if p.char_id == "wukong":
				return p.bullet_count >= 7
			return Global.difficulty == "hell" and p.bullet_count >= 4
		"dmg":
			return Global.difficulty == "hell" and p.bullet_damage_bonus >= 24
		"atkspd":
			return p.atk_interval_mult <= 0.35
		"africa":
			return bool(player_node.get("has_africa_title"))
		"trip":
			return bool(player_node.get("has_trip"))
		"area_bomb":
			return p.has_area_bomb and p.area_bomb_interval <= 1.5
		"orbit_ring":
			return p.has_orbit and p.orbit_interval <= 0.8 and p.orbit_scale >= 2.5
	return false

const _ATK_IDS := ["dmg", "atkspd", "multishot", "pierce", "area_bomb", "orbit_ring"]

func _pick_upgrades(n: int) -> Array:
	var atk_pool: Array = []
	var sur_pool: Array = []
	for upg in UPGRADE_POOL:
		if upg["id"] == "africa" or upg["id"] == "trip" or _upgrade_maxed(upg["id"]):
			continue
		if upg["id"] in _ATK_IDS:
			atk_pool.append(upg)
		else:
			sur_pool.append(upg)
	atk_pool.shuffle()
	sur_pool.shuffle()

	var result: Array = []
	if not atk_pool.is_empty():
		result.append(atk_pool.pop_front())
	if not sur_pool.is_empty():
		result.append(sur_pool.pop_front())

	var rest: Array = atk_pool + sur_pool
	rest.shuffle()
	while result.size() < n and not rest.is_empty():
		result.append(rest.pop_front())

	result.shuffle()
	return result

func _make_card(upg: Dictionary, panel: Control, slot: int = -1, is_pinned: bool = false) -> Control:
	var card := Button.new()
	card.custom_minimum_size = Vector2(270.0, 270.0)

	var accent := upg["color"] as Color
	card.add_theme_stylebox_override("normal",  _card_style(Color(0.05, 0.12, 0.30, 0.94), accent, 0.6))
	card.add_theme_stylebox_override("hover",   _card_style(Color(0.10, 0.22, 0.50, 0.97), accent, 1.0))
	card.add_theme_stylebox_override("pressed", _card_style(Color(0.10, 0.22, 0.50, 0.97), accent, 1.0))

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   =  18.0
	vbox.offset_right  = -18.0
	vbox.offset_top    =  18.0
	vbox.offset_bottom = -12.0
	vbox.alignment     = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	var _icon_path := ""
	match upg.get("id", ""):
		"africa": _icon_path = "res://assets/非洲人之星.png"
		"trip":   _icon_path = "res://assets/跌倒_icon.png"
	if _icon_path != "":
		var tex := TextureRect.new()
		tex.texture              = load(_icon_path)
		tex.custom_minimum_size  = Vector2(64.0, 64.0)
		tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tex.expand_mode          = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex.stretch_mode         = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vbox.add_child(tex)
	else:
		var icon := ColorRect.new()
		icon.color                 = Color(accent.r, accent.g, accent.b, 0.25)
		icon.custom_minimum_size   = Vector2(52.0, 52.0)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = upg["name"]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", accent)
	vbox.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = upg["desc"]
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 16)
	desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.90, 1.0))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_lbl)

	# 釘選按鈕
	if slot >= 0:
		var pin_btn := Button.new()
		pin_btn.text = "📌 取消釘選" if is_pinned else "📌 釘選"
		pin_btn.custom_minimum_size = Vector2(0.0, 28.0)
		pin_btn.add_theme_font_size_override("font_size", 13)
		pin_btn.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.0) if is_pinned else Color(0.78, 0.88, 1.0))
		if not is_pinned:
			pin_btn.disabled = not _can_pin() or not _pinned_upgrade.is_empty()
		var psn := StyleBoxFlat.new()
		psn.bg_color = Color(0.35, 0.25, 0.0, 0.85) if is_pinned else Color(0.08, 0.08, 0.20, 0.85)
		psn.set_border_width_all(1)
		psn.border_color = Color(1.0, 0.75, 0.0, 0.8) if is_pinned else Color(0.4, 0.55, 0.9, 0.6)
		psn.set_corner_radius_all(5)
		pin_btn.add_theme_stylebox_override("normal",  psn)
		pin_btn.add_theme_stylebox_override("hover",   psn)
		pin_btn.add_theme_stylebox_override("pressed", psn)
		if is_pinned:
			pin_btn.pressed.connect(func(): _do_unpin())
		else:
			var cap_upg := upg.duplicate()
			var cap_slot := slot
			pin_btn.pressed.connect(func(): _do_pin(cap_upg, cap_slot))
		vbox.add_child(pin_btn)

	card.pressed.connect(_apply_upgrade.bind(upg["id"], panel))
	return card

func _card_style(bg: Color, border: Color, border_alpha: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = bg
	s.border_color = Color(border.r, border.g, border.b, border_alpha)
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	return s

func _upgrade_name(id: String) -> String:
	if is_instance_valid(player_node) and player_node.char_id == "wukong":
		match id:
			"multishot": return "擴大扇角"
	for upg in UPGRADE_POOL:
		if upg["id"] == id:
			return upg["name"]
	return id

func _upgrade_desc(id: String) -> String:
	if not is_instance_valid(player_node):
		return ""
	var p: Node2D = player_node
	match id:
		"dmg":
			var c: int = p.bullet_damage_bonus
			var dmg_tag := "近戰/爆炸/環射" if p.char_id == "wukong" else "子彈/爆炸/環射"
			return "全傷 +8（%d → %d，影響%s）" % [c, c + 8, dmg_tag] if c > 0 else "所有傷害 +8（%s）" % dmg_tag
		"atkspd":
			var pct: int = int((1.0 - float(p.atk_interval_mult)) * 100.0)
			return "攻速再提升 15%%（目前快 %d%%）" % pct if pct > 0 else "攻擊速度提升 15%"
		"movspd":
			var c: int = int(float(p.speed))
			return "移速 +20（%d → %d）" % [c, c + 20] if c > int(float(p.BASE_SPEED)) else "移動速度 +20"
		"maxhp":
			var c: int = p.max_hp
			return "最大HP +30，立即回復（%d → %d）" % [c, c + 30]
		"multishot":
			var c: int = p.bullet_count
			if p.char_id == "wukong":
				var cur_half: int = 60 + (c - 1) * 20
				if cur_half + 20 >= 180:
					return "揮擊範圍 → 全圓（目前 ±%d°）" % cur_half
				return "揮擊扇角 +20°（目前 ±%d°）" % cur_half
			return "子彈數 +1（%d → %d 顆）" % [c, c + 1]
		"magnet":
			var c: int = int(float(p.gem_attract_range))
			return "磁吸範圍 +120（%d → %d）" % [c, c + 120] if c > 160 else "寶石吸引範圍 +120"
		"vampiric":
			var c: int = p.vampiric_heal
			return "吸血 +1（%d → %d HP/擊殺）" % [c, c + 1] if c > 0 else "擊殺敵人回復 1 HP"
		"pierce":
			var c: int = p.bullet_pierce
			if p.char_id == "wukong":
				return "穿透 +1，近戰範圍 +20（%d → %d），環形射擊同樣適用" % [120 + c * 20, 120 + (c + 1) * 20]
			return "穿透 +1（%d → %d 個）" % [c, c + 1] if c > 0 else "子彈可額外穿透 1 個敵人"
		"area_bomb":
			if p.has_area_bomb:
				var c: float = float(p.area_bomb_interval)
				var n: float = maxf(1.5, c - 0.5)
				var r: int   = int(p.bomb_radius)
				return "冷卻 %.1fs → %.1fs，爆炸範圍 +20（→%d）" % [c, n, r + 20]
			return "每 4s 自動爆炸，範圍 180，傷害 %d" % [int(30 + p.level * 3) + p.bullet_damage_bonus]
		"orbit_ring":
			if p.has_orbit:
				var c: float  = float(p.orbit_interval)
				var n: float  = maxf(0.8, c - 0.3)
				var sc: float = minf(2.5, p.orbit_scale + 0.3)
				return "冷卻 %.1fs → %.1fs，子彈大小 × %.1f" % [c, n, sc]
			return "每 2.5s 向八方發射，子彈留下 1s 火焰"
		"shield":
			if p.has_shield:
				var c: int   = p.shield_max_hp
				var add: int = 30 if Global.difficulty == "hell" else 20
				return "護盾上限 +%d（%d → %d），立即刷新" % [add, c, c + add]
			return "護盾 %d 耐久，優先承傷，%.0fs 後重生" % [p.shield_max_hp, p.shield_recharge]
		"regen":
			if p.has_regen:
				var c: int = p.regen_amount
				var add: int = 2 if Global.difficulty == "hell" else 1
				return "再生量 +%d（每 %.1fs 回復 %d → %d HP）" % [add, p.regen_interval, c, c + add]
			return "每 %.1fs 自動回復 %d HP" % [p.regen_interval, p.regen_amount]
		"africa":
			return "恭喜抽到了銘謝惠顧（機率極低），你是萬中選一的非洲人！此技能沒有效果"
		"trip":
			return "走路時有低機率跌倒。"
	return ""

func _apply_upgrade(upgrade_id: String, panel: Control) -> void:
	if not is_instance_valid(player_node):
		return
	# 若選了釘選的那格，清除釘選；否則釘選保留到下一輪
	if not _pinned_upgrade.is_empty() and _pinned_upgrade.get("id", "") == upgrade_id:
		_pinned_upgrade = {}
		_pinned_slot    = -1
	match upgrade_id:
		"dmg":        player_node.bullet_damage_bonus += 8
		"atkspd":     player_node.atk_interval_mult = maxf(0.35, player_node.atk_interval_mult * 0.85)
		"movspd":     player_node.speed += 20.0
		"maxhp":
			player_node.max_hp += 30
			player_node.heal(30)
		"multishot":
			var _ms_cap: int = 4 if Global.difficulty == "hell" else 99
			player_node.bullet_count = mini(player_node.bullet_count + 1, _ms_cap)
		"magnet":     player_node.gem_attract_range += 120.0
		"vampiric":
			var _vcap: int = (2 if Global.difficulty == "hell" else (3 if Global.difficulty == "hard" else (4 if Global.difficulty == "normal" else 5)))
			player_node.vampiric_heal = min(player_node.vampiric_heal + 1, _vcap)
		"pierce":
			var _pcap: int = (3 if Global.difficulty == "hell" else (2 if Global.difficulty == "hard" else (1 if Global.difficulty == "normal" else 0)))
			player_node.bullet_pierce = min(player_node.bullet_pierce + 1, _pcap)
		"area_bomb":
			if player_node.has_area_bomb:
				player_node.area_bomb_interval = maxf(1.5, player_node.area_bomb_interval - 0.5)
				if player_node.bomb_radius < 220.0:
					player_node.bomb_radius += 20.0
			else:
				player_node.has_area_bomb = true
		"orbit_ring":
			if player_node.has_orbit:
				player_node.orbit_interval  = maxf(0.8, player_node.orbit_interval - 0.3)
				player_node.orbit_scale     = minf(2.5, player_node.orbit_scale + 0.3)
				player_node.orbit_ring_level += 1
			else:
				player_node.has_orbit = true
		"shield":
			if player_node.has_shield:
				player_node.shield_max_hp += (30 if Global.difficulty == "hell" else 20)
				if player_node.shield_hp > 0:
					player_node.shield_hp = player_node.shield_max_hp
			else:
				player_node.has_shield    = true
				player_node.shield_hp     = player_node.shield_max_hp
		"regen":
			if player_node.has_regen:
				player_node.regen_amount += (2 if Global.difficulty == "hell" else 1)
			else:
				player_node.has_regen = true
		"africa":
			player_node.set("has_africa_title", true)
			player_node.set("damage_multiplier", 2.0)
		"trip":
			player_node.set("has_trip", true)

	if upgrade_id != "africa" and upgrade_id != "trip":
		_skill_levels[upgrade_id] = _skill_levels.get(upgrade_id, 0) + 1
		_update_skill_display()

	panel.queue_free()
	_upgrade_panel = null
	is_upgrading   = false
	_set_game_nodes_active(true)

# ─── 背景格線 ─────────────────────────────────────────────────
func _draw() -> void:
	if not is_instance_valid(camera):
		return
	var cam_pos := camera.global_position
	var vp      := get_viewport_rect().size
	if vp.x < 1.0:
		return
	var cell  := 64.0
	var hw    := vp.x * 0.5 + cell * 2.0
	var hh    := vp.y * 0.5 + cell * 2.0
	var left  := floorf((cam_pos.x - hw) / cell) * cell
	var top   := floorf((cam_pos.y - hh) / cell) * cell
	var right := cam_pos.x + hw
	var bot   := cam_pos.y + hh
	var gc    := Color(0.0, 0.42, 0.68, 0.22)
	var x := left
	while x <= right:
		draw_line(Vector2(x, top), Vector2(x, bot), gc, 1.0)
		x += cell
	var y := top
	while y <= bot:
		draw_line(Vector2(left, y), Vector2(right, y), gc, 1.0)
		y += cell

	# 地圖邊界
	var pw := MAP_HALF_W - 120.0
	var ph := MAP_HALF_H - 120.0
	draw_rect(Rect2(-pw, -ph, pw * 2.0, ph * 2.0),
		Color(0.25, 0.55, 1.0, 0.55), false, 3.0)

# ─── UI 建立 ──────────────────────────────────────────────────
func _setup_ui() -> void:
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS

	# ── 左上：HP / EXP ──
	var tl := HBoxContainer.new()
	tl.position = Vector2(16.0, 16.0)
	tl.add_theme_constant_override("separation", 8)
	ui_layer.add_child(tl)

	var heart := Label.new()
	heart.text = "❤"
	heart.add_theme_color_override("font_color", Color(1.0, 0.14, 0.14))
	heart.add_theme_font_size_override("font_size", 38)
	tl.add_child(heart)

	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 5)
	tl.add_child(bars)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 6)
	bars.add_child(hp_row)
	var hp_lbl := Label.new()
	hp_lbl.text = "HP"
	hp_lbl.add_theme_font_size_override("font_size", 15)
	hp_lbl.add_theme_color_override("font_color", Color.WHITE)
	hp_row.add_child(hp_lbl)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(200.0, 18.0)
	hp_bar.value               = 100.0
	hp_bar.show_percentage     = false
	hp_bar.add_theme_stylebox_override("fill",       _flat(Color(0.12, 0.88, 0.22), 4))
	hp_bar.add_theme_stylebox_override("background", _flat(Color(0.08, 0.08, 0.14), 4))
	hp_row.add_child(hp_bar)

	var exp_row := HBoxContainer.new()
	exp_row.add_theme_constant_override("separation", 6)
	bars.add_child(exp_row)
	var exp_lbl := Label.new()
	exp_lbl.text = "EXP"
	exp_lbl.add_theme_font_size_override("font_size", 15)
	exp_lbl.add_theme_color_override("font_color", Color.WHITE)
	exp_row.add_child(exp_lbl)
	exp_bar = ProgressBar.new()
	exp_bar.custom_minimum_size = Vector2(200.0, 18.0)
	exp_bar.value               = 0.0
	exp_bar.show_percentage     = false
	exp_bar.add_theme_stylebox_override("fill",       _flat(Color(0.18, 0.52, 1.0), 4))
	exp_bar.add_theme_stylebox_override("background", _flat(Color(0.08, 0.08, 0.14), 4))
	exp_row.add_child(exp_bar)

	level_label = Label.new()
	level_label.text = "LV.1"
	level_label.add_theme_font_size_override("font_size", 15)
	level_label.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	bars.add_child(level_label)

	# ── 頂部中央：計時器（碼表） ──
	var tc := PanelContainer.new()
	tc.position = Vector2(537.0, 14.0)
	tc.add_theme_stylebox_override("panel", _flat(Color(0.04, 0.09, 0.24, 0.88), 7))
	ui_layer.add_child(tc)
	var tc_m := MarginContainer.new()
	tc_m.add_theme_constant_override("margin_left",   18)
	tc_m.add_theme_constant_override("margin_right",  18)
	tc_m.add_theme_constant_override("margin_top",     6)
	tc_m.add_theme_constant_override("margin_bottom",  6)
	tc.add_child(tc_m)
	timer_label = Label.new()
	timer_label.text = "00:00"
	timer_label.add_theme_font_size_override("font_size", 38)
	timer_label.add_theme_color_override("font_color", Color.WHITE)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tc_m.add_child(timer_label)

	# ── 計時器下方：Boss 光束警告倒計時 ──
	beam_warn_label = Label.new()
	beam_warn_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	beam_warn_label.offset_top    = 70.0
	beam_warn_label.offset_bottom = 106.0
	beam_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	beam_warn_label.add_theme_font_size_override("font_size", 28)
	beam_warn_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.0))
	beam_warn_label.visible = false
	ui_layer.add_child(beam_warn_label)

	# ── 右上：得分 ──
	score_label = Label.new()
	score_label.position = Vector2(1080.0, 20.0)
	score_label.text = "得分: 0"
	score_label.add_theme_font_size_override("font_size", 20)
	score_label.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0))
	ui_layer.add_child(score_label)

	# ── 底部：Boss HP 條（預設隱藏） ──
	boss_bar_panel = PanelContainer.new()
	boss_bar_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	boss_bar_panel.offset_top    = -62.0
	boss_bar_panel.offset_bottom = -8.0
	boss_bar_panel.offset_left   = 180.0
	boss_bar_panel.offset_right  = -180.0
	boss_bar_panel.add_theme_stylebox_override("panel", _flat(Color(0.04, 0.04, 0.12, 0.9), 6))
	boss_bar_panel.visible = false
	ui_layer.add_child(boss_bar_panel)

	var bm := MarginContainer.new()
	bm.add_theme_constant_override("margin_left",  12)
	bm.add_theme_constant_override("margin_right", 12)
	bm.add_theme_constant_override("margin_top",    5)
	bm.add_theme_constant_override("margin_bottom", 5)
	boss_bar_panel.add_child(bm)

	var bvbox := VBoxContainer.new()
	bvbox.add_theme_constant_override("separation", 4)
	bm.add_child(bvbox)

	var boss_lbl := Label.new()
	boss_lbl.text = "⚠  BOSS"
	boss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_lbl.add_theme_font_size_override("font_size", 15)
	boss_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.1))
	bvbox.add_child(boss_lbl)

	boss_hp_bar = ProgressBar.new()
	boss_hp_bar.custom_minimum_size = Vector2(0.0, 18.0)
	boss_hp_bar.value               = 100.0
	boss_hp_bar.show_percentage     = false
	boss_hp_bar.add_theme_stylebox_override("fill",       _flat(Color(0.9, 0.12, 0.05), 4))
	boss_hp_bar.add_theme_stylebox_override("background", _flat(Color(0.1, 0.02, 0.02), 4))
	bvbox.add_child(boss_hp_bar)

	# ── Boss 出現警告標籤 ──
	boss_warning_label = Label.new()
	boss_warning_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	boss_warning_label.offset_left   = -300.0
	boss_warning_label.offset_right  =  300.0
	boss_warning_label.offset_top    = -45.0
	boss_warning_label.offset_bottom =  45.0
	boss_warning_label.text = "⚠  BOSS 出現！"
	boss_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_warning_label.add_theme_font_size_override("font_size", 46)
	boss_warning_label.add_theme_color_override("font_color", Color(1.0, 0.28, 0.0))
	boss_warning_label.visible = false
	ui_layer.add_child(boss_warning_label)

	# ── 右下角技能欄 ──
	_skill_display_label = Label.new()
	_skill_display_label.anchor_left   = 1.0
	_skill_display_label.anchor_right  = 1.0
	_skill_display_label.anchor_top    = 1.0
	_skill_display_label.anchor_bottom = 1.0
	_skill_display_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skill_display_label.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	_skill_display_label.offset_right  = -10.0
	_skill_display_label.offset_bottom = -38.0
	_skill_display_label.add_theme_font_size_override("font_size", 14)
	_skill_display_label.add_theme_color_override("font_color", Color(0.82, 0.95, 1.0, 0.92))
	_skill_display_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_skill_display_label.add_theme_constant_override("outline_size", 2)
	_skill_display_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skill_display_label.text    = ""
	_skill_display_label.visible = not Global.dev_mode
	ui_layer.add_child(_skill_display_label)

	# ── 左下角技能冷卻顯示 ──
	_skill_q_label = Label.new()
	_skill_q_label.position = Vector2(16.0, 638.0)
	_skill_q_label.add_theme_font_size_override("font_size", 16)
	_skill_q_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_skill_q_label.add_theme_constant_override("outline_size", 2)
	ui_layer.add_child(_skill_q_label)

	_skill_e_label = Label.new()
	_skill_e_label.position = Vector2(16.0, 660.0)
	_skill_e_label.add_theme_font_size_override("font_size", 16)
	_skill_e_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_skill_e_label.add_theme_constant_override("outline_size", 2)
	ui_layer.add_child(_skill_e_label)

	# ── 底部提示 ──
	var tip := Label.new()
	tip.position = Vector2(16.0, 688.0)
	tip.text     = "WASD 移動  |  自動攻擊  |  ESC 暫停  |  撐過 3:45 擊敗 BOSS 即勝利！"
	tip.add_theme_font_size_override("font_size", 14)
	tip.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9, 0.8))
	ui_layer.add_child(tip)

	# ── 暫停遮罩 ──
	pause_overlay = ColorRect.new()
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.color        = Color(0.0, 0.04, 0.14, 0.72)
	pause_overlay.visible      = false
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	ui_layer.add_child(pause_overlay)

	var pause_vbox := VBoxContainer.new()
	pause_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_vbox.alignment     = BoxContainer.ALIGNMENT_CENTER
	pause_vbox.process_mode  = Node.PROCESS_MODE_ALWAYS
	pause_vbox.add_theme_constant_override("separation", 28)
	pause_overlay.add_child(pause_vbox)

	var plbl := Label.new()
	plbl.text = "⏸  已暫停"
	plbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plbl.add_theme_font_size_override("font_size", 52)
	plbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	pause_vbox.add_child(plbl)

	var phint := Label.new()
	phint.text = "ESC 繼續"
	phint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phint.add_theme_font_size_override("font_size", 22)
	phint.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0, 0.8))
	pause_vbox.add_child(phint)

	var btn_lobby := _make_end_btn("回大廳")
	btn_lobby.custom_minimum_size    = Vector2(130.0, 38.0)
	btn_lobby.size_flags_horizontal  = Control.SIZE_SHRINK_CENTER
	btn_lobby.add_theme_font_size_override("font_size", 17)
	btn_lobby.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	pause_vbox.add_child(btn_lobby)

	# ── 遊戲結束遮罩 ──
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color        = Color(0.0, 0.0, 0.0, 0.8)
	overlay.visible      = false
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	ui_layer.add_child(overlay)

	overlay_vbox = VBoxContainer.new()
	overlay_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_vbox.alignment   = BoxContainer.ALIGNMENT_CENTER
	overlay_vbox.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay_vbox.add_theme_constant_override("separation", 28)
	overlay.add_child(overlay_vbox)

	overlay_label = Label.new()
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	overlay_label.add_theme_font_size_override("font_size", 54)
	overlay_label.add_theme_color_override("font_color", Color.WHITE)
	overlay_vbox.add_child(overlay_label)

func _update_skill_display() -> void:
	if _skill_display_label == null:
		return
	var lines: Array = []
	for skill_id in _skill_levels.keys():
		var lv: int = _skill_levels[skill_id]
		lines.append("%s  Lv.%d" % [_upgrade_name(skill_id), lv])
	_skill_display_label.text = "\n".join(lines)
	if Global.dev_mode:
		_build_dev_skill_panel()

func _setup_dev_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(5.0, 110.0)
	panel.add_theme_stylebox_override("panel", _flat(Color(0.06, 0.03, 0.18, 0.93), 7))
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	ui_layer.add_child(panel)
	_dev_panel = panel

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   8)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "開 發 模 式"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.2))
	vbox.add_child(title_lbl)

	_dev_stats_lbl = Label.new()
	_dev_stats_lbl.text = ""
	_dev_stats_lbl.add_theme_font_size_override("font_size", 12)
	_dev_stats_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(_dev_stats_lbl)

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.35, 0.3, 0.55, 0.6))
	vbox.add_child(sep)

	# 無敵 toggle（= hp_lock）
	vbox.add_child(_dev_toggle_row("無敵", Global.hp_lock, func(on: bool) -> void:
		Global.hp_lock = on
	))

	# 木樁模式 toggle
	vbox.add_child(_dev_toggle_row("木樁模式", Global.dummy_mode, func(on: bool) -> void:
		Global.dummy_mode = on
		if on:
			Global.reset_stats()
	))

	# 停止生成 toggle
	vbox.add_child(_dev_toggle_row("停止生成", _dev_stop_spawn, func(on: bool) -> void:
		_dev_stop_spawn = on
	))

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("color", Color(0.35, 0.3, 0.55, 0.6))
	vbox.add_child(sep2)

	var inf_btn := _make_dev_btn("無限刷新")
	inf_btn.pressed.connect(func():
		_refresh_left = 999
		_pin_left     = 999
	)
	vbox.add_child(inf_btn)

	var upg_btn := _make_dev_btn("自由升級")
	upg_btn.pressed.connect(func():
		if not game_over and not victory and not is_upgrading and not is_paused:
			_show_upgrade_menu()
	)
	vbox.add_child(upg_btn)

	var exp_btn := _make_dev_btn("+100 EXP")
	exp_btn.pressed.connect(func():
		if is_instance_valid(player_node):
			player_node.gain_exp(100)
	)
	vbox.add_child(exp_btn)

	var spawn_btn := _make_dev_btn("生成小怪")
	spawn_btn.pressed.connect(func():
		if not game_over and not victory:
			spawn_enemy()
	)
	vbox.add_child(spawn_btn)

	var dummy_boss_btn := _make_dev_btn("生成木樁")
	dummy_boss_btn.pressed.connect(func():
		if not game_over and not victory:
			_spawn_dummy_boss()
	)
	vbox.add_child(dummy_boss_btn)

	var boss_btn := _make_dev_btn("生成Boss")
	boss_btn.pressed.connect(func():
		if not game_over and not victory and not boss_spawned:
			_spawn_boss()
	)
	vbox.add_child(boss_btn)

	var clear_btn := _make_dev_btn("清除全怪")
	clear_btn.pressed.connect(func():
		if is_instance_valid(boss_node):
			boss_node = null
			boss_spawned = false
			boss_bar_panel.visible = false
		for e in enemies_node.get_children():
			e.queue_free()
	)
	vbox.add_child(clear_btn)

func _dev_toggle_row(label_text: String, initial_on: bool, callback: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var btn := Button.new()
	btn.toggle_mode    = true
	btn.button_pressed = initial_on
	btn.custom_minimum_size = Vector2(40.0, 22.0)
	btn.text       = ""
	btn.focus_mode = Control.FOCUS_NONE
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	var off_s := StyleBoxFlat.new()
	off_s.bg_color = Color(0.22, 0.22, 0.26)
	off_s.set_corner_radius_all(11)
	var on_s := StyleBoxFlat.new()
	on_s.bg_color = Color(0.15, 0.70, 0.42)
	on_s.set_corner_radius_all(11)
	btn.add_theme_stylebox_override("normal",        off_s)
	btn.add_theme_stylebox_override("hover",         off_s)
	btn.add_theme_stylebox_override("pressed",       on_s)
	btn.add_theme_stylebox_override("hover_pressed", on_s)
	var knob := Panel.new()
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ks := StyleBoxFlat.new()
	ks.bg_color = Color(0.96, 0.96, 0.98)
	ks.set_corner_radius_all(8)
	knob.add_theme_stylebox_override("panel", ks)
	knob.size     = Vector2(16.0, 16.0)
	knob.position = Vector2(21.0 if initial_on else 3.0, 3.0)
	btn.add_child(knob)
	btn.toggled.connect(func(on: bool) -> void:
		var tween := btn.create_tween()
		tween.tween_property(knob, "position:x", 21.0 if on else 3.0, 0.10)
		callback.call(on)
	)
	row.add_child(btn)
	return row

func _make_dev_btn(txt: String) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(112.0, 24.0)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	var sn := StyleBoxFlat.new()
	sn.bg_color     = Color(0.06, 0.18, 0.42, 0.92)
	sn.border_color = Color(0.3, 0.58, 1.0)
	sn.set_border_width_all(1)
	sn.set_corner_radius_all(5)
	btn.add_theme_stylebox_override("normal",  sn)
	var sh := StyleBoxFlat.new()
	sh.bg_color     = Color(0.12, 0.28, 0.68, 0.97)
	sh.border_color = Color(0.5, 0.78, 1.0)
	sh.set_border_width_all(1)
	sh.set_corner_radius_all(5)
	btn.add_theme_stylebox_override("hover",   sh)
	btn.add_theme_stylebox_override("pressed", sh)
	return btn

func _spawn_dummy_boss() -> void:
	var b := boss_scene.instantiate()
	enemies_node.add_child(b)
	b.global_position = player_node.global_position + Vector2(220.0, 0.0)
	b.player          = player_node
	b.bullets_node    = bullets_node
	b.map_half_w      = MAP_HALF_W
	b.map_half_h      = MAP_HALF_H
	b.is_dummy        = true

func _build_dev_skill_panel() -> void:
	if is_instance_valid(_dev_skill_panel):
		_dev_skill_panel.queue_free()
	if _skill_levels.is_empty():
		return
	var vbox := VBoxContainer.new()
	vbox.anchor_left    = 1.0
	vbox.anchor_right   = 1.0
	vbox.anchor_top     = 1.0
	vbox.anchor_bottom  = 1.0
	vbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	vbox.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	vbox.offset_right   = -10.0
	vbox.offset_bottom  = -38.0
	vbox.custom_minimum_size = Vector2(190.0, 0.0)
	vbox.add_theme_constant_override("separation", 3)
	ui_layer.add_child(vbox)
	_dev_skill_panel = vbox
	for skill_id in _skill_levels.keys():
		var lv: int = _skill_levels[skill_id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var minus_btn := Button.new()
		minus_btn.text = "-"
		minus_btn.custom_minimum_size = Vector2(22.0, 22.0)
		minus_btn.add_theme_font_size_override("font_size", 13)
		minus_btn.focus_mode   = Control.FOCUS_NONE
		minus_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		var msn := StyleBoxFlat.new()
		msn.bg_color = Color(0.35, 0.06, 0.06, 0.88)
		msn.set_corner_radius_all(4)
		minus_btn.add_theme_stylebox_override("normal", msn)
		minus_btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
		var cap_id: String = str(skill_id)
		minus_btn.pressed.connect(func(): _dev_remove_upgrade(cap_id))
		row.add_child(minus_btn)
		var lbl := Label.new()
		lbl.text = "%s  Lv.%d" % [_upgrade_name(skill_id), lv]
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.82, 0.95, 1.0, 0.92))
		lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(lbl)
		var plus_btn := Button.new()
		plus_btn.text = "+"
		plus_btn.custom_minimum_size = Vector2(22.0, 22.0)
		plus_btn.add_theme_font_size_override("font_size", 13)
		plus_btn.focus_mode   = Control.FOCUS_NONE
		plus_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		var psn := StyleBoxFlat.new()
		psn.bg_color = Color(0.06, 0.28, 0.06, 0.88)
		psn.set_corner_radius_all(4)
		plus_btn.add_theme_stylebox_override("normal", psn)
		plus_btn.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
		plus_btn.pressed.connect(func(): _dev_apply_upgrade(cap_id))
		row.add_child(plus_btn)
		vbox.add_child(row)

func _dev_apply_upgrade(id: String) -> void:
	if not is_instance_valid(player_node):
		return
	match id:
		"dmg":        player_node.bullet_damage_bonus += 8
		"atkspd":     player_node.atk_interval_mult = maxf(0.15, player_node.atk_interval_mult * 0.85)
		"movspd":     player_node.speed += 20.0
		"maxhp":
			player_node.max_hp += 30
			player_node.heal(30)
		"multishot":  player_node.bullet_count += 1
		"magnet":     player_node.gem_attract_range += 120.0
		"vampiric":   player_node.vampiric_heal += 1
		"pierce":     player_node.bullet_pierce += 1
		"area_bomb":
			if player_node.has_area_bomb:
				player_node.area_bomb_interval = maxf(0.5, player_node.area_bomb_interval - 0.5)
				player_node.bomb_radius = minf(300.0, player_node.bomb_radius + 20.0)
			else:
				player_node.has_area_bomb = true
		"orbit_ring":
			if player_node.has_orbit:
				player_node.orbit_interval  = maxf(0.3, player_node.orbit_interval - 0.3)
				player_node.orbit_scale     = minf(4.0, player_node.orbit_scale + 0.3)
				player_node.orbit_ring_level += 1
			else:
				player_node.has_orbit = true
		"shield":
			if player_node.has_shield:
				player_node.shield_max_hp += (30 if Global.difficulty == "hell" else 20)
				player_node.shield_hp = player_node.shield_max_hp
			else:
				player_node.has_shield = true
				player_node.shield_hp  = player_node.shield_max_hp
		"regen":
			if player_node.has_regen:
				player_node.regen_amount += (2 if Global.difficulty == "hell" else 1)
			else:
				player_node.has_regen = true
	_skill_levels[id] = _skill_levels.get(id, 0) + 1
	_update_skill_display()

func _dev_remove_upgrade(id: String) -> void:
	if not is_instance_valid(player_node) or not _skill_levels.has(id):
		return
	var lv: int = _skill_levels[id]
	match id:
		"dmg":
			player_node.bullet_damage_bonus = maxi(0, player_node.bullet_damage_bonus - 8)
		"atkspd":
			player_node.atk_interval_mult = minf(1.0, player_node.atk_interval_mult / 0.85)
		"movspd":
			player_node.speed = maxf(80.0, player_node.speed - 20.0)
		"maxhp":
			player_node.max_hp = maxi(1, player_node.max_hp - 30)
			player_node.hp = mini(player_node.hp, player_node.max_hp)
		"multishot":
			player_node.bullet_count = maxi(1, player_node.bullet_count - 1)
		"magnet":
			player_node.gem_attract_range = maxf(0.0, player_node.gem_attract_range - 120.0)
		"vampiric":
			player_node.vampiric_heal = maxi(0, player_node.vampiric_heal - 1)
		"pierce":
			player_node.bullet_pierce = maxi(0, player_node.bullet_pierce - 1)
		"area_bomb":
			if lv <= 1:
				player_node.has_area_bomb      = false
				player_node.area_bomb_interval = 4.0
				player_node.bomb_radius        = 180.0
			else:
				player_node.area_bomb_interval = minf(4.0, player_node.area_bomb_interval + 0.5)
				player_node.bomb_radius = maxf(180.0, player_node.bomb_radius - 20.0)
		"orbit_ring":
			if lv <= 1:
				player_node.has_orbit        = false
				player_node.orbit_interval   = 2.5
				player_node.orbit_scale      = 1.0
				player_node.orbit_ring_level = 0
			else:
				player_node.orbit_interval   = minf(2.5, player_node.orbit_interval + 0.3)
				player_node.orbit_scale      = maxf(1.0, player_node.orbit_scale - 0.3)
				player_node.orbit_ring_level = maxi(0, player_node.orbit_ring_level - 1)
		"shield":
			var sub: int = 30 if Global.difficulty == "hell" else 20
			if lv <= 1:
				player_node.has_shield = false
				player_node.shield_hp  = 0
			else:
				player_node.shield_max_hp = maxi(40, player_node.shield_max_hp - sub)
				player_node.shield_hp     = mini(player_node.shield_hp, player_node.shield_max_hp)
		"regen":
			var sub_r: int = 2 if Global.difficulty == "hell" else 1
			if lv <= 1:
				player_node.has_regen = false
			else:
				player_node.regen_amount = maxi(1, player_node.regen_amount - sub_r)
	if lv <= 1:
		_skill_levels.erase(id)
	else:
		_skill_levels[id] = lv - 1
	_update_skill_display()

func _flat(color: Color, radius: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	return s

# ─── Q/E 冷卻解除攔截 ─────────────────────────────────────────

func _on_skill_cooldown(skill_key: String) -> void:
	if not Global.learn_mode: return
	if _is_qa or is_paused or is_upgrading or game_over or victory: return

	var rem := 0
	var cb_type := ""
	if skill_key == "Q":
		if _learn_q_charges <= 0: return
		rem = _learn_q_charges - 1
		cb_type = "Q"
	else:
		if _learn_e_charges <= 0: return
		rem = _learn_e_charges - 1
		cb_type = "E"

	var on_confirm = func():
		var q_cb = func():
			if skill_key == "Q": _learn_q_charges -= 1
			else: _learn_e_charges -= 1
			if is_instance_valid(player_node):
				player_node.set("skill_" + skill_key.to_lower() + "_cd", 0.0)
			_show_skill_hint("%s 技能冷卻已消除！（剩餘 %d 次）" % [skill_key, rem])
		_show_qa_session(10, q_cb, "連續答對 10 題以解鎖技能")

	_show_skill_confirm(skill_key, rem + 1, on_confirm)

func _unhandled_input(event: InputEvent) -> void:
	pass

# 顯示技能重置確認對話框
func _show_skill_confirm(skill_key: String, charges: int, on_confirm: Callable) -> void:
	_is_qa = true
	_set_game_nodes_active(false)

	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	ui_layer.add_child(overlay)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.03, 0.12, 0.82)
	overlay.add_child(dim)

	var dialog := Control.new()
	dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dialog.offset_left   = -260.0
	dialog.offset_right  =  260.0
	dialog.offset_top    = -140.0
	dialog.offset_bottom =  140.0
	overlay.add_child(dialog)

	var dlg_bg := ColorRect.new()
	dlg_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dlg_bg.color = Color(0.06, 0.10, 0.28, 0.97)
	dialog.add_child(dlg_bg)

	var title_lbl := Label.new()
	title_lbl.text = "【%s 技能冷卻中】" % skill_key
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title_lbl.offset_top    = 24.0
	title_lbl.offset_bottom = 60.0
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	dialog.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = "回答 10 題可立即解除冷卻（剩 %d 次機會）\n確定要現在答題嗎？" % charges
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	desc_lbl.offset_top    = 70.0
	desc_lbl.offset_bottom = 180.0
	desc_lbl.offset_left   = 20.0
	desc_lbl.offset_right  = -20.0
	desc_lbl.add_theme_font_size_override("font_size", 18)
	desc_lbl.add_theme_color_override("font_color", Color.WHITE)
	dialog.add_child(desc_lbl)

	var confirm_btn := Button.new()
	confirm_btn.text = "確定答題"
	confirm_btn.custom_minimum_size = Vector2(140.0, 48.0)
	confirm_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	confirm_btn.focus_mode = Control.FOCUS_NONE
	confirm_btn.add_theme_font_size_override("font_size", 18)
	confirm_btn.add_theme_color_override("font_color", Color.WHITE)
	confirm_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	confirm_btn.offset_left   = -160.0
	confirm_btn.offset_right  = -20.0
	confirm_btn.offset_top    = -68.0
	confirm_btn.offset_bottom = -20.0
	var csn := StyleBoxFlat.new()
	csn.bg_color = Color(0.06, 0.20, 0.52, 0.95)
	csn.border_color = Color(0.3, 0.65, 1.0)
	csn.set_border_width_all(2); csn.set_corner_radius_all(8)
	confirm_btn.add_theme_stylebox_override("normal",  csn)
	var csh := csn.duplicate() as StyleBoxFlat
	csh.bg_color = Color(0.14, 0.35, 0.72, 0.97)
	confirm_btn.add_theme_stylebox_override("hover",   csh)
	confirm_btn.add_theme_stylebox_override("pressed", csh)
	dialog.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "稍後再說"
	cancel_btn.custom_minimum_size = Vector2(140.0, 48.0)
	cancel_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.add_theme_font_size_override("font_size", 18)
	cancel_btn.add_theme_color_override("font_color", Color.WHITE)
	cancel_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	cancel_btn.offset_left   = 20.0
	cancel_btn.offset_right  = 160.0
	cancel_btn.offset_top    = -68.0
	cancel_btn.offset_bottom = -20.0
	var dsn := StyleBoxFlat.new()
	dsn.bg_color = Color(0.28, 0.08, 0.08, 0.92)
	dsn.border_color = Color(0.75, 0.3, 0.3)
	dsn.set_border_width_all(2); dsn.set_corner_radius_all(8)
	cancel_btn.add_theme_stylebox_override("normal",  dsn)
	var dsh := dsn.duplicate() as StyleBoxFlat
	dsh.bg_color = Color(0.45, 0.12, 0.12, 0.97)
	cancel_btn.add_theme_stylebox_override("hover",   dsh)
	cancel_btn.add_theme_stylebox_override("pressed", dsh)
	dialog.add_child(cancel_btn)

	confirm_btn.pressed.connect(func():
		overlay.queue_free()
		on_confirm.call()
	)
	cancel_btn.pressed.connect(func():
		overlay.queue_free()
		_is_qa = false
		_set_game_nodes_active(true)
	)

# ─── 題庫讀取 ─────────────────────────────────────────────────
func _load_questions() -> void:
	var paths := [
		"res://乙級.json",
		"user://questions.json",
		"C:/Users/kimya/Downloads/乙級.json"
	]
	var content_str := ""
	for path in paths:
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				content_str = file.get_as_text()
				file.close()
				break
	if content_str == "": return
	var parsed = JSON.parse_string(content_str)
	if parsed == null or not (parsed is Array): return
	_questions.clear()
	for item in (parsed as Array):
		if item is Dictionary: _questions.append(item)

# ─── 學習模式：問答系統 ───────────────────────────────────────
func _show_qa_session(n_questions: int, callback: Callable, note: String = "") -> void:
	if _questions.is_empty():
		callback.call()
		return
	_is_qa = true
	_set_game_nodes_active(false)
	var pool := _questions.duplicate()
	pool.shuffle()
	var picks: Array = []
	for i in mini(n_questions, pool.size()):
		picks.append(pool[i])
	var safety := 0
	while picks.size() < n_questions and not pool.is_empty() and safety < 300:
		safety += 1
		picks.append(pool[randi() % pool.size()])
	_build_qa_ui(picks, 0, callback, note)

func _build_qa_ui(questions: Array, idx: int, callback: Callable, note: String) -> void:
	if is_instance_valid(_qa_panel):
		_qa_panel.queue_free()

	var raw_q: Dictionary = questions[idx] if idx < questions.size() else {}
	var q_text: String = raw_q.get("題目", raw_q.get("question", "（題目讀取失敗）"))
	var opts_raw = raw_q.get("選項", raw_q.get("options", {}))
	var options: Array = []
	if opts_raw is Dictionary:
		for key in ["A", "B", "C", "D"]:
			if key in opts_raw:
				options.append("%s. %s" % [key, (opts_raw as Dictionary)[key]])
	elif opts_raw is Array:
		for o in opts_raw:
			options.append(str(o))
	var ans_raw = raw_q.get("答案", raw_q.get("answer", "A"))
	var ans_idx: int = 0
	if ans_raw is int:
		ans_idx = ans_raw
	elif ans_raw is String:
		match (ans_raw as String).strip_edges().to_upper():
			"A": ans_idx = 0
			"B": ans_idx = 1
			"C": ans_idx = 2
			"D": ans_idx = 3

	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_qa_panel = panel
	ui_layer.add_child(panel)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.03, 0.12, 0.95)
	panel.add_child(bg)

	var top_y := 28.0
	if note != "":
		var note_lbl := Label.new()
		note_lbl.text = note
		note_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		note_lbl.offset_top    = top_y
		note_lbl.offset_bottom = top_y + 34.0
		note_lbl.add_theme_font_size_override("font_size", 17)
		note_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
		panel.add_child(note_lbl)
		top_y += 38.0

	var prog_lbl := Label.new()
	prog_lbl.text = "第 %d / %d 題" % [idx + 1, questions.size()]
	prog_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prog_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	prog_lbl.offset_top    = top_y
	prog_lbl.offset_bottom = top_y + 34.0
	prog_lbl.add_theme_font_size_override("font_size", 20)
	prog_lbl.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
	panel.add_child(prog_lbl)

	var q_lbl := Label.new()
	q_lbl.text = q_text
	q_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	q_lbl.offset_top    = top_y + 40.0
	q_lbl.offset_bottom = top_y + 155.0
	q_lbl.offset_left   = 70.0
	q_lbl.offset_right  = -70.0
	q_lbl.add_theme_font_size_override("font_size", 22)
	q_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	panel.add_child(q_lbl)

	var opt_vbox := VBoxContainer.new()
	opt_vbox.anchor_left   = 0.0
	opt_vbox.anchor_right  = 1.0
	opt_vbox.anchor_top    = 0.0
	opt_vbox.anchor_bottom = 1.0
	opt_vbox.offset_left   = 50.0
	opt_vbox.offset_right  = -50.0
	opt_vbox.offset_top    = top_y + 165.0
	opt_vbox.offset_bottom = -90.0
	opt_vbox.add_theme_constant_override("separation", 8)
	panel.add_child(opt_vbox)

	var cont_btn := Button.new()
	cont_btn.text = "繼續 →" if idx + 1 < questions.size() else "完成 ✓"
	cont_btn.custom_minimum_size = Vector2(160.0, 44.0)
	cont_btn.visible = false
	cont_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	cont_btn.focus_mode   = Control.FOCUS_NONE
	cont_btn.add_theme_font_size_override("font_size", 18)
	cont_btn.add_theme_color_override("font_color", Color.WHITE)
	var csn := StyleBoxFlat.new()
	csn.bg_color = Color(0.06, 0.20, 0.52, 0.92)
	csn.border_color = Color(0.3, 0.65, 1.0)
	csn.set_border_width_all(2); csn.set_corner_radius_all(8)
	cont_btn.add_theme_stylebox_override("normal",  csn)
	var csh := csn.duplicate() as StyleBoxFlat
	csh.bg_color = Color(0.14, 0.35, 0.72, 0.97)
	cont_btn.add_theme_stylebox_override("hover",   csh)
	cont_btn.add_theme_stylebox_override("pressed", csh)
	cont_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	cont_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cont_btn.offset_top    = -78.0
	cont_btn.offset_bottom = -28.0
	panel.add_child(cont_btn)

	var answered := false
	var opt_btns: Array = []

	for i in options.size():
		var opt_btn := Button.new()
		opt_btn.text = ""
		opt_btn.custom_minimum_size = Vector2(0.0, 58.0)
		opt_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opt_btn.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		opt_btn.focus_mode   = Control.FOCUS_NONE
		opt_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		var sn := StyleBoxFlat.new()
		sn.bg_color     = Color(0.07, 0.15, 0.38, 0.92)
		sn.border_color = Color(0.3, 0.55, 0.9, 0.7)
		sn.set_border_width_all(2); sn.set_corner_radius_all(8)
		opt_btn.add_theme_stylebox_override("normal", sn)
		var sh := StyleBoxFlat.new()
		sh.bg_color     = Color(0.12, 0.28, 0.62, 0.97)
		sh.border_color = Color(0.5, 0.75, 1.0)
		sh.set_border_width_all(2); sh.set_corner_radius_all(8)
		opt_btn.add_theme_stylebox_override("hover",   sh)
		opt_btn.add_theme_stylebox_override("pressed", sh)
		var opt_lbl := Label.new()
		opt_lbl.text = options[i] as String
		opt_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		opt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		opt_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		opt_lbl.offset_left  = 14.0
		opt_lbl.offset_right = -14.0
		opt_lbl.add_theme_font_size_override("font_size", 17)
		opt_lbl.add_theme_color_override("font_color", Color.WHITE)
		opt_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		opt_btn.add_child(opt_lbl)
		opt_btns.append(opt_btn)
		opt_vbox.add_child(opt_btn)

		var cap_i := i
		opt_btn.pressed.connect(func():
			if answered:
				return
			answered = true
			for b in opt_btns:
				(b as Button).disabled = true
			var cs := StyleBoxFlat.new()
			cs.bg_color = Color(0.05, 0.50, 0.12, 0.95)
			cs.border_color = Color(0.15, 1.0, 0.3)
			cs.set_border_width_all(2); cs.set_corner_radius_all(8)
			(opt_btns[ans_idx] as Button).add_theme_stylebox_override("disabled", cs)
			if cap_i != ans_idx:
				var ws := StyleBoxFlat.new()
				ws.bg_color = Color(0.55, 0.04, 0.04, 0.95)
				ws.border_color = Color(1.0, 0.2, 0.2)
				ws.set_border_width_all(2); ws.set_corner_radius_all(8)
				(opt_btns[cap_i] as Button).add_theme_stylebox_override("disabled", ws)
			cont_btn.visible = true
		)

	cont_btn.pressed.connect(func():
		panel.queue_free()
		_qa_panel = null
		if idx + 1 < questions.size():
			_build_qa_ui(questions, idx + 1, callback, note)
		else:
			_is_qa = false
			if not is_upgrading:
				_set_game_nodes_active(true)
			callback.call()
	)

func _make_locked_card() -> Control:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(270.0, 270.0)
	var sn := StyleBoxFlat.new()
	sn.bg_color    = Color(0.04, 0.07, 0.20, 0.94)
	sn.border_color = Color(0.28, 0.32, 0.52, 0.5)
	sn.set_border_width_all(2); sn.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", sn)
	var lbl := Label.new()
	lbl.text = "🔒\n（待解鎖）"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color(0.38, 0.42, 0.62, 0.7))
	card.add_child(lbl)
	return card

func _show_revival_option() -> void:
	var rpanel := Control.new()
	rpanel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rpanel.process_mode = Node.PROCESS_MODE_ALWAYS
	ui_layer.add_child(rpanel)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.03, 0.12, 0.92)
	rpanel.add_child(bg)

	var title_lbl := Label.new()
	title_lbl.text = "你已陣亡！"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 52)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.22, 0.22))
	title_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title_lbl.offset_left   = -300.0; title_lbl.offset_right  =  300.0
	title_lbl.offset_top    = -140.0; title_lbl.offset_bottom = -65.0
	rpanel.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "【學習模式】答 10 題可復活一次"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 21)
	sub_lbl.add_theme_color_override("font_color", Color(0.72, 0.88, 1.0))
	sub_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sub_lbl.offset_left   = -350.0; sub_lbl.offset_right  =  350.0
	sub_lbl.offset_top    =  -25.0; sub_lbl.offset_bottom =  25.0
	rpanel.add_child(sub_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 30)
	btn_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	btn_row.offset_left   = -240.0; btn_row.offset_right  =  240.0
	btn_row.offset_top    =   50.0; btn_row.offset_bottom =  108.0
	rpanel.add_child(btn_row)

	var revive_cb := func():
		_learn_revive_used = true
		if is_instance_valid(player_node):
			player_node.heal(player_node.max_hp / 2)
			player_node.set("invincible", true)
			player_node.set("inv_timer",  3.0)
	var revive_btn := _make_end_btn("答 10 題復活")
	revive_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	revive_btn.pressed.connect(func():
		rpanel.queue_free()
		_show_qa_session(10, revive_cb)
	)
	btn_row.add_child(revive_btn)

	var giveup_btn := _make_end_btn("放棄")
	giveup_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	giveup_btn.pressed.connect(func():
		rpanel.queue_free()
		game_over             = true
		overlay.visible       = true
		overlay.color         = Color(0.55, 0.04, 0.04, 0.84)
		overlay_label.text    = "遊戲結束\n\n得分: %d" % score
		_show_end_buttons()
	)
	btn_row.add_child(giveup_btn)

func _show_skill_hint(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lbl.offset_left   = -300.0; lbl.offset_right  =  300.0
	lbl.offset_top    =  -26.0; lbl.offset_bottom =  26.0
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.2, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.process_mode = Node.PROCESS_MODE_ALWAYS
	ui_layer.add_child(lbl)
	var tween := lbl.create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tween.tween_callback(lbl.queue_free)

func _setup_bgm() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_bgm_player)
	
	var stream = load("res://assets/battle.ogg")
	if not stream: stream = load("res://assets/battle.mp3")
	
	if stream:
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		elif stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
			
		_bgm_player.stream = stream
		_bgm_player.play()
		_bgm_player.finished.connect(func(): _bgm_player.play())
	
	Global.sync_audio_volume()
