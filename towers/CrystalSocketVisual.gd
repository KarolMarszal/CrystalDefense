class_name CrystalSocketVisual
extends Node2D

var occupied: bool = false:
	set(value):
		if occupied == value:
			return
		occupied = value
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 16.0, Color(0.06, 0.08, 0.07, 0.96))
	if not occupied:
		draw_circle(Vector2.ZERO, 10.0, Color(0.22, 0.27, 0.2, 1.0))
		draw_colored_polygon(
			PackedVector2Array([
				Vector2(0.0, -6.0),
				Vector2(5.0, 0.0),
				Vector2(0.0, 6.0),
				Vector2(-5.0, 0.0)
			]),
			Color(0.86, 0.69, 0.34, 1.0)
		)
	draw_arc(
		Vector2.ZERO,
		15.0,
		0.0,
		TAU,
		32,
		Color(0.98, 0.78, 0.38, 1.0),
		2.5,
		true
	)
