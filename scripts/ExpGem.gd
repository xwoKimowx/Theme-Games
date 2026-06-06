extends Area2D

var player:        Node2D = null
var exp_value:     int    = 3
var attract_speed: float  = 0.0
var gem_color:     Color

func _ready() -> void:
	var r := randi() % 3
	gem_color = [Color(1.0, 0.42, 0.72), Color(0.82, 0.32, 1.0), Color(0.95, 0.78, 0.0)][r]
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		var attract_range: float = player.gem_attract_range if "gem_attract_range" in player else 95.0
		if dist < attract_range:
			var top_spd: float = (player.speed if "speed" in player else 185.0) * 2.5
			attract_speed = minf(top_spd, attract_speed + top_spd * 3.0 * delta)
			var dir := (player.global_position - global_position).normalized()
			global_position += dir * attract_speed * delta
		else:
			attract_speed = 0.0
	queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		body.gain_exp(exp_value)
		queue_free()

func _draw() -> void:
	var glow := Color(gem_color.r, gem_color.g, gem_color.b, 0.28)
	draw_circle(Vector2.ZERO, 10.0, glow)
	draw_circle(Vector2.ZERO, 7.0, gem_color)
	draw_circle(Vector2(-2.2, -2.2), 2.8, Color(1.0, 1.0, 1.0, 0.65))
