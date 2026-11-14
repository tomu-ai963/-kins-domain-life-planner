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
	# 県を選ぶようにして足した野菜(3D の LOOKS の ripe と同じ色)
	"daikon": Color(0.96, 0.96, 0.92), "kabu": Color(0.97, 0.97, 0.94), "sweet_potato": Color(0.62, 0.22, 0.36), "taro": Color(0.50, 0.40, 0.30),
	"eggplant": Color(0.30, 0.12, 0.36), "pepper": Color(0.18, 0.56, 0.14), "pumpkin": Color(0.26, 0.40, 0.22), "goya": Color(0.42, 0.72, 0.26),
	"cabbage": Color(0.74, 0.88, 0.58), "hakusai": Color(0.90, 0.94, 0.76), "spinach": Color(0.20, 0.52, 0.20), "komatsuna": Color(0.28, 0.60, 0.24),
	"edamame": Color(0.52, 0.72, 0.30), "corn": Color(0.96, 0.84, 0.30),
	"wheat": Color(0.90, 0.74, 0.34), "rye": Color(0.74, 0.66, 0.44), "soba": Color(0.94, 0.92, 0.90), "kibi": Color(0.96, 0.86, 0.36), "onion": Color(0.80, 0.58, 0.30), "negi": Color(0.95, 0.95, 0.90),
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
		if garden.is_spoiled(c):
			color = Color(0.36, 0.26, 0.14)
		for r in range(ROWS):
			for k in range(COLUMNS):
				var p := center + Vector2(plot * ((k + 0.5) / COLUMNS - 0.5), plot * ((r + 1.0) / (ROWS + 1.0) - 0.5))
				draw_circle(p, lerpf(2.0, 7.0, ratio), color)
