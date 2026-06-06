extends Node2D

var burn_duration:      float = 2.0
var burn_tick_interval: float = 5.0
var radius:             float = 12.0

const LIFETIME: float = 2.0

var _points:       Array      = []
var _in_range_prev: Dictionary = {}   # enemy → true，上一幀的接觸集合

func add_point(world_pos: Vector2) -> void:
	_points.append({"p": world_pos, "t": LIFETIME})

func _process(delta: float) -> void:
	var i := _points.size() - 1
	while i >= 0:
		_points[i]["t"] -= delta
		if _points[i]["t"] <= 0.0:
			_points.remove_at(i)
		i -= 1

	var in_range_now: Dictionary = {}
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var epos: Vector2 = (e as Node2D).global_position
		for pt in _points:
			if pt["p"].distance_to(epos) < radius + 10.0:
				in_range_now[e] = true
				break

	# 新進入範圍的敵人立即附著燃燒
	for e in in_range_now.keys():
		if not _in_range_prev.has(e):
			e.call("apply_burn", burn_duration, burn_tick_interval)

	_in_range_prev = in_range_now

	if _points.is_empty():
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	for pt in _points:
		var t:  float   = clampf(pt["t"] / LIFETIME, 0.0, 1.0)
		var lp: Vector2 = to_local(pt["p"])
		draw_circle(lp, radius * 1.3, Color(0.0, 0.30, 1.0, t * 0.38))
		draw_circle(lp, radius,       Color(0.0, 0.55, 1.0, t * 0.58))
		draw_circle(lp, radius * 0.4, Color(0.45, 0.88, 1.0, t * 0.82))
