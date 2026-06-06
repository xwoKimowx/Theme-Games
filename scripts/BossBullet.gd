extends Area2D

var direction := Vector2.RIGHT
var speed     := 260.0
var damage    := 18
var player: Node2D = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	position += direction * speed * delta

	# 飛出螢幕外才消失（攝影機中心 ±margin）
	if is_instance_valid(player):
		var cam_pos := player.global_position
		var margin  := 900.0
		var gp      := global_position
		if gp.x < cam_pos.x - margin or gp.x > cam_pos.x + margin or \
		   gp.y < cam_pos.y - margin or gp.y > cam_pos.y + margin:
			queue_free()
			return

	queue_redraw()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		body.take_damage(damage)
		queue_free()

func _draw() -> void:
	var tail := -direction * 30.0
	draw_line(Vector2.ZERO, tail, Color(1.0, 0.45, 0.0, 0.35), 10.0)
	draw_circle(Vector2.ZERO, 20.0, Color(1.0, 0.3, 0.0, 0.35))
	draw_circle(Vector2.ZERO, 16.0, Color(1.0, 0.38, 0.0, 0.85))
	draw_circle(Vector2.ZERO, 10.0, Color(1.0, 0.72, 0.0))
	draw_circle(Vector2.ZERO, 5.5, Color.WHITE)
