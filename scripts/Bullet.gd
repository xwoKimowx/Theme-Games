extends Area2D

var direction       := Vector2.RIGHT
var speed           := 420.0
var damage          := 15
var lifetime        := 2.2
var pierce          := 0
var home_target:    Node2D = null
var is_orbit:       bool   = false
var has_trip_stun:  bool   = false
var no_vamp:        bool   = false
var orbit_ring_level: int  = 0

const HOME_STRENGTH := 1.8
const FlameZoneScript = preload("res://scripts/FlameZone.gd")

var _pierce_left: int  = 0
var _hit_bodies: Array = []
var _trail:      Node  = null
var _trail_timer: float = 0.0

func _ready() -> void:
	_pierce_left = pierce
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(delta: float) -> void:
	if is_instance_valid(home_target):
		var to_target := (home_target.global_position - global_position).normalized()
		var angle_diff := direction.angle_to(to_target)
		var max_turn   := HOME_STRENGTH * delta
		direction = direction.rotated(clampf(angle_diff, -max_turn, max_turn)).normalized()

	position += direction * speed * delta
	lifetime  -= delta
	if lifetime <= 0.0:
		queue_free()
		return

	# Boss 的 collision_layer=0，body_entered 偵測不到，改用距離判斷
	for boss in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(boss) or boss in _hit_bodies:
			continue
		if global_position.distance_to((boss as Node2D).global_position) < 98.0:
			_hit_bodies.append(boss)
			boss.take_damage(damage)
			if has_trip_stun and randf() < 0.1:
				boss.call("apply_stun", 3.0)
			if _pierce_left > 0:
				_pierce_left -= 1
			else:
				queue_free()
				return

	if is_orbit and is_instance_valid(get_parent()):
		if not is_instance_valid(_trail):
			_trail = Node2D.new()
			_trail.set_script(FlameZoneScript)
			_trail.burn_duration      = [2.0, 3.0, 4.0, 5.0][mini(orbit_ring_level, 3)]
			_trail.burn_tick_interval = [5.0, 3.5, 2.5, 1.5][mini(orbit_ring_level, 3)]
			_trail.radius             = 17.5 * scale.x
			_trail.z_index            = -3
			get_parent().add_child(_trail)
		_trail_timer -= delta
		if _trail_timer <= 0.0:
			_trail_timer = 0.04
			_trail.add_point(global_position)

	queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies") and body not in _hit_bodies:
		_hit_bodies.append(body)
		body.take_damage(damage, not no_vamp)
		if has_trip_stun and randf() < 0.1:
			body.call("apply_stun", 3.0)
		if _pierce_left > 0:
			_pierce_left -= 1
		else:
			queue_free()

func _on_body_exited(body: Node2D) -> void:
	_hit_bodies.erase(body)

func _draw() -> void:
	var t1 := -direction * 16.0
	var t2 := -direction * 9.0
	if pierce > 0:
		draw_line(Vector2.ZERO, t1, Color(0.0, 1.0, 0.35, 0.35), 4.0)
		draw_line(Vector2.ZERO, t2, Color(0.2, 1.0, 0.5, 0.6), 3.0)
		draw_circle(Vector2.ZERO, 8.0, Color(0.0, 0.9, 0.3, 0.45))
		draw_circle(Vector2.ZERO, 5.5, Color(0.1, 1.0, 0.45))
		draw_circle(Vector2.ZERO, 3.0, Color.WHITE)
	elif is_orbit:
		draw_line(Vector2.ZERO, t1, Color(1.0, 0.55, 0.0, 0.35), 4.0)
		draw_line(Vector2.ZERO, t2, Color(1.0, 0.75, 0.1, 0.6), 3.0)
		draw_circle(Vector2.ZERO, 7.0, Color(1.0, 0.45, 0.0, 0.45))
		draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.75, 0.15))
		draw_circle(Vector2.ZERO, 3.0, Color.WHITE)
	else:
		draw_line(Vector2.ZERO, t1, Color(0.0, 0.65, 1.0, 0.3), 3.5)
		draw_line(Vector2.ZERO, t2, Color(0.0, 0.82, 1.0, 0.55), 2.5)
		draw_circle(Vector2.ZERO, 7.0, Color(0.0, 0.6, 1.0, 0.45))
		draw_circle(Vector2.ZERO, 5.0, Color(0.0, 0.88, 1.0))
		draw_circle(Vector2.ZERO, 3.0, Color.WHITE)
