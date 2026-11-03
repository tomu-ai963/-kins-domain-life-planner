extends Node2D

# ── 市場(屋台)の 2D 表示(比較用) ───────────────────────────────
const Market = preload("res://logic/Market.gd")
const PX := 40.0  # 2D 表示の 1m

var market: Market

func setup(m: Market) -> void:
	market = m
	queue_redraw()

func _draw() -> void:
	if market == null:
		return
	var c: Vector2 = market.POS * PX
	draw_line(Vector2(0, 50 * PX), c, Color(0.58, 0.48, 0.34), 40)
	draw_rect(Rect2(c - Vector2(90, 55), Vector2(180, 110)), Color(0.72, 0.28, 0.20))
	draw_rect(Rect2(c - Vector2(80, 45), Vector2(160, 30)), Color(0.55, 0.38, 0.22))
