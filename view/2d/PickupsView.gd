extends Node2D

# ── 地面に落ちている種の 2D 表示(比較用) ────────────────────────
const Forest = preload("res://logic/Forest.gd")
const PX := 40.0  # 2D 表示の 1m

var forest: Forest

func setup(f: Forest) -> void:
	forest = f
	forest.changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	for p in forest.pickups:
		draw_circle(p.pos * PX, 6.0, Color(0.80, 0.70, 0.45))
		draw_arc(p.pos * PX, 10.0, 0, TAU, 16, Color(1.0, 0.95, 0.55), 2.0)
