extends Node2D

# ── 小屋の 2D 表示(比較用) ─────────────────────────────────────
# 上から見た四角。場所だけなら縄の枠、基礎で床の色、壁で太い枠、完成で屋根の色
const Cabin = preload("res://logic/Cabin.gd")
const PX := 40.0  # 2D 表示の 1m

var cabin: Cabin

func setup(c: Cabin) -> void:
	cabin = c
	cabin.changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	if cabin.site == null:
		return
	var r: Rect2 = cabin.rect()
	var px := Rect2(r.position * PX, r.size * PX)
	if cabin.stage >= 1 or cabin.days_done > 0:
		draw_rect(px, Color(0.62, 0.46, 0.28))
	if cabin.stage >= 2 or (cabin.stage == 1 and cabin.days_done > 0):
		draw_rect(px, Color(0.42, 0.27, 0.14), false, 8.0)
	else:
		draw_rect(px, Color(0.95, 0.90, 0.70), false, 2.0)
	if cabin.is_complete():
		draw_rect(px.grow(-4.0), Color(0.38, 0.28, 0.24))
