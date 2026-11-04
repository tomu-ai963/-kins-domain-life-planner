extends Node2D

# ── 池の 2D 表示(比較用) ───────────────────────────────────────
# 縄の輪 → 掘った穴 → 水面(水の量で広がる。冬は氷)。生き物はいる種類の数だけ点を打つ
const Pond = preload("res://logic/Pond.gd")
const PX := 40.0  # 2D 表示の 1m

var pond: Pond

func setup(p: Pond) -> void:
	pond = p
	pond.changed.connect(queue_redraw)
	pond.land.changed.connect(queue_redraw)
	pond.forest.changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	if not pond.is_placed():
		return
	var c: Vector2 = pond.land.pond * PX
	var r: float = pond.land.POND_RADIUS * PX
	if pond.days_dug == 0:
		draw_arc(c, r, 0, TAU, 48, Color(0.95, 0.90, 0.70), 2.0)
		return
	var ratio: float = float(pond.days_dug) / pond.DIG_DAYS
	draw_circle(c, r * ratio, Color(0.26, 0.19, 0.12))
	if pond.water > 0:
		var wr: float = r * lerpf(0.5, 1.0, pond.water / 100.0)
		draw_circle(c, wr, Color(0.82, 0.90, 0.96) if pond.is_frozen() else Color(0.28, 0.52, 0.78, 0.85))
	var i := 0
	for id in pond.present():
		draw_circle(c + Vector2.from_angle(TAU * i / 5.0) * r * 0.5, 6.0, Color(0.15, 0.12, 0.08))
		i += 1
