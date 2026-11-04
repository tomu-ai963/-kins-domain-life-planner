extends Node2D

# ── 畑の野菜の 2D 表示(比較用) ──────────────────────────────────
# 区画の上に 3 列 × 4 株の丸を描く。収穫できると実の色に変わる
const Garden = preload("res://logic/Garden.gd")
const PX := 40.0  # 2D 表示の 1m
const ROWS := 3
const COLUMNS := 4

const LEAF := Color(0.30, 0.58, 0.22)
const RIPE := {
	"tomato": Color(0.88, 0.14, 0.10),
	"radish": Color(0.85, 0.15, 0.32),
	"carrot": Color(0.95, 0.50, 0.10),
	"cucumber": Color(0.62, 0.82, 0.28),
	"potato": Color(0.76, 0.62, 0.38),
	"garlic": Color(0.95, 0.92, 0.84),
}

var garden: Garden

func setup(g: Garden) -> void:
	garden = g
	garden.changed.connect(queue_redraw)
	garden.forest.changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var plot: float = (garden.land.PLOT_SIZE - 0.2) * PX
	for c in garden.crops:
		var center: Vector2 = c.pos * PX
		if garden.watered_today(c):
			draw_rect(Rect2(center - Vector2(plot, plot) * 0.5, Vector2(plot, plot)), Color(0.14, 0.09, 0.06, 0.45))
		var ratio: float = garden.growth_ratio(c)
		var color: Color = RIPE[c.kind] if ratio >= 1.0 else LEAF
		for r in range(ROWS):
			for k in range(COLUMNS):
				var p := center + Vector2(plot * ((k + 0.5) / COLUMNS - 0.5), plot * ((r + 1.0) / (ROWS + 1.0) - 0.5))
				draw_circle(p, lerpf(2.0, 7.0, ratio), color)
