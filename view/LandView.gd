extends Node2D

# ── 菜園の区画と池の 2D 表示(四角と円) ──────────────────────────
# 状態とルールは logic/Land.gd(座標は m)。ここは読んで px で描くだけ
const Land = preload("res://logic/Land.gd")
const PX := 40.0  # 2D 表示の 1m

var land: Land

func setup(l: Land) -> void:
	land = l
	land.changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	if land == null:
		return
	var soil := Color(0.42, 0.28, 0.16)
	var furrow := Color(0.30, 0.20, 0.11)
	var size: float = land.PLOT_SIZE * PX
	var h := size * 0.5
	for plot in land.plots:
		var c: Vector2 = plot * PX
		draw_rect(Rect2(c.x - h + 4, c.y - h + 4, size - 8, size - 8), soil)
		for k in range(1, 4):  # 畝
			var y: float = c.y - h + 4 + (size - 8) * k / 4.0
			draw_line(Vector2(c.x - h + 10, y), Vector2(c.x + h - 10, y), furrow, 2)
	if land.pond != null:
		draw_circle(land.pond * PX, land.POND_RADIUS * PX, Color(0.28, 0.52, 0.78, 0.85))
		draw_circle(land.pond * PX, land.POND_RADIUS * PX * 0.6, Color(0.34, 0.60, 0.86, 0.6))
