extends Node2D

# ── 木の 2D 表示(_draw の円) ──────────────────────────────────
# 状態とルールは logic/Forest.gd(座標は m)。ここは読んで px で描くだけ(3D では別の view に差し替える)
const Forest = preload("res://logic/Forest.gd")
const PX := 40.0  # 2D 表示の 1m

# 樹種ごとの色
const COLORS := {
	"birch": {
		"leaf": Color(0.45, 0.72, 0.30, 0.60),
		"leaf_autumn": Color(0.85, 0.72, 0.20, 0.60),
		"trunk": Color(0.92, 0.92, 0.88),
	},
	"apple": {
		"leaf": Color(0.20, 0.60, 0.20, 0.60),
		"leaf_autumn": Color(0.80, 0.55, 0.18, 0.60),
		"trunk": Color(0.35, 0.22, 0.10),
	},
	"cherry": {
		"leaf": Color(0.28, 0.58, 0.24, 0.85), "leaf_autumn": Color(0.82, 0.42, 0.18, 0.85), "trunk": Color(0.34, 0.18, 0.12),
	},
	"plum": {
		"leaf": Color(0.26, 0.52, 0.26, 0.85), "leaf_autumn": Color(0.72, 0.46, 0.20, 0.85), "trunk": Color(0.28, 0.18, 0.14),
	},
	"pear": {
		"leaf": Color(0.30, 0.60, 0.26, 0.85), "leaf_autumn": Color(0.86, 0.62, 0.20, 0.85), "trunk": Color(0.36, 0.26, 0.16),
	},
	"cedar": {
		"leaf": Color(0.08, 0.42, 0.20, 0.65),
		"leaf_autumn": Color(0.08, 0.42, 0.20, 0.65),
		"trunk": Color(0.30, 0.18, 0.08),
	},
	# 県を選ぶようにして足した木(3D の KINDS と同じ色)
	"konara": {"leaf": Color(0.36, 0.60, 0.24, 0.70), "leaf_autumn": Color(0.72, 0.44, 0.16, 0.70), "trunk": Color(0.40, 0.36, 0.30)},
	"gajumaru": {"leaf": Color(0.16, 0.48, 0.20, 0.70), "leaf_autumn": Color(0.16, 0.48, 0.20, 0.70), "trunk": Color(0.52, 0.48, 0.40)},
	"kaki": {"leaf": Color(0.26, 0.54, 0.20, 0.85), "leaf_autumn": Color(0.86, 0.40, 0.12, 0.85), "trunk": Color(0.26, 0.20, 0.16)},
	"mikan": {"leaf": Color(0.14, 0.42, 0.18, 0.85), "leaf_autumn": Color(0.14, 0.42, 0.18, 0.85), "trunk": Color(0.36, 0.30, 0.20)},
	"shikuwasa": {"leaf": Color(0.16, 0.46, 0.18, 0.85), "leaf_autumn": Color(0.16, 0.46, 0.18, 0.85), "trunk": Color(0.36, 0.30, 0.20)},
	"sugi": {"leaf": Color(0.14, 0.36, 0.16, 0.65), "leaf_autumn": Color(0.14, 0.36, 0.16, 0.65), "trunk": Color(0.42, 0.24, 0.14)},
	"ezomatsu": {"leaf": Color(0.10, 0.32, 0.22, 0.65), "leaf_autumn": Color(0.10, 0.32, 0.22, 0.65), "trunk": Color(0.34, 0.26, 0.20)},
	"ryukyu_pine": {"leaf": Color(0.20, 0.46, 0.22, 0.65), "leaf_autumn": Color(0.20, 0.46, 0.22, 0.65), "trunk": Color(0.46, 0.28, 0.18)},
	"keyaki": {"leaf": Color(0.38, 0.62, 0.26, 0.70), "leaf_autumn": Color(0.84, 0.46, 0.18, 0.70), "trunk": Color(0.52, 0.46, 0.40)},
	"kunugi": {"leaf": Color(0.34, 0.56, 0.22, 0.70), "leaf_autumn": Color(0.66, 0.46, 0.20, 0.70), "trunk": Color(0.36, 0.30, 0.24)},
	"deigo": {"leaf": Color(0.30, 0.56, 0.24, 0.70), "leaf_autumn": Color(0.30, 0.56, 0.24, 0.70), "trunk": Color(0.56, 0.50, 0.42)},
	"fukugi": {"leaf": Color(0.12, 0.40, 0.18, 0.70), "leaf_autumn": Color(0.12, 0.40, 0.18, 0.70), "trunk": Color(0.40, 0.34, 0.28)},
	"ume": {"leaf": Color(0.30, 0.56, 0.24, 0.85), "leaf_autumn": Color(0.70, 0.60, 0.24, 0.85), "trunk": Color(0.26, 0.20, 0.18)},
	"kuri": {"leaf": Color(0.30, 0.54, 0.20, 0.85), "leaf_autumn": Color(0.78, 0.60, 0.20, 0.85), "trunk": Color(0.34, 0.26, 0.20)},
	"mango": {"leaf": Color(0.14, 0.40, 0.18, 0.85), "leaf_autumn": Color(0.14, 0.40, 0.18, 0.85), "trunk": Color(0.38, 0.30, 0.24)},
	"papaya": {"leaf": Color(0.30, 0.58, 0.22, 0.85), "leaf_autumn": Color(0.30, 0.58, 0.22, 0.85), "trunk": Color(0.62, 0.60, 0.50)},
	"hinoki": {"leaf": Color(0.12, 0.38, 0.20, 0.65), "leaf_autumn": Color(0.12, 0.38, 0.20, 0.65), "trunk": Color(0.50, 0.30, 0.20)},
	# 自然の木(3D の KINDS と同じ色)
	"buna": {"leaf": Color(0.40, 0.62, 0.28, 0.70), "leaf_autumn": Color(0.80, 0.52, 0.20, 0.70), "trunk": Color(0.62, 0.62, 0.58)},
	"mizunara": {"leaf": Color(0.34, 0.56, 0.24, 0.70), "leaf_autumn": Color(0.72, 0.48, 0.20, 0.70), "trunk": Color(0.46, 0.40, 0.34)},
	"harunire": {"leaf": Color(0.36, 0.58, 0.24, 0.70), "leaf_autumn": Color(0.80, 0.68, 0.24, 0.70), "trunk": Color(0.40, 0.34, 0.28)},
	"nanakamado": {"leaf": Color(0.38, 0.60, 0.26, 0.70), "leaf_autumn": Color(0.86, 0.22, 0.14, 0.70), "trunk": Color(0.42, 0.36, 0.32)},
	"oyamazakura": {"leaf": Color(0.34, 0.58, 0.24, 0.70), "leaf_autumn": Color(0.86, 0.38, 0.18, 0.70), "trunk": Color(0.34, 0.22, 0.20)},
	"yamazakura": {"leaf": Color(0.34, 0.58, 0.24, 0.70), "leaf_autumn": Color(0.84, 0.44, 0.18, 0.70), "trunk": Color(0.36, 0.24, 0.20)},
	"akashide": {"leaf": Color(0.38, 0.60, 0.26, 0.70), "leaf_autumn": Color(0.84, 0.40, 0.18, 0.70), "trunk": Color(0.50, 0.48, 0.44)},
	"mizuki": {"leaf": Color(0.36, 0.60, 0.26, 0.70), "leaf_autumn": Color(0.76, 0.30, 0.22, 0.70), "trunk": Color(0.46, 0.42, 0.38)},
	"enoki": {"leaf": Color(0.36, 0.58, 0.24, 0.70), "leaf_autumn": Color(0.78, 0.66, 0.24, 0.70), "trunk": Color(0.52, 0.48, 0.42)},
	"hannoki": {"leaf": Color(0.28, 0.50, 0.22, 0.70), "leaf_autumn": Color(0.46, 0.44, 0.22, 0.70), "trunk": Color(0.40, 0.34, 0.30)},
	"egonoki": {"leaf": Color(0.38, 0.62, 0.28, 0.70), "leaf_autumn": Color(0.82, 0.70, 0.26, 0.70), "trunk": Color(0.34, 0.28, 0.26)},
	"tsuge": {"leaf": Color(0.18, 0.42, 0.16, 0.70), "leaf_autumn": Color(0.18, 0.42, 0.16, 0.70), "trunk": Color(0.52, 0.46, 0.36)},
	"shirakashi": {"leaf": Color(0.18, 0.40, 0.18, 0.70), "leaf_autumn": Color(0.18, 0.40, 0.18, 0.70), "trunk": Color(0.36, 0.34, 0.30)},
	"sudajii": {"leaf": Color(0.20, 0.40, 0.16, 0.70), "leaf_autumn": Color(0.20, 0.40, 0.16, 0.70), "trunk": Color(0.30, 0.28, 0.26)},
	"akagi": {"leaf": Color(0.26, 0.50, 0.22, 0.70), "leaf_autumn": Color(0.26, 0.50, 0.22, 0.70), "trunk": Color(0.52, 0.34, 0.26)},
	"kanhizakura": {"leaf": Color(0.32, 0.56, 0.24, 0.70), "leaf_autumn": Color(0.32, 0.56, 0.24, 0.70), "trunk": Color(0.34, 0.22, 0.20)},
	"hamaibiwa": {"leaf": Color(0.20, 0.46, 0.20, 0.70), "leaf_autumn": Color(0.20, 0.46, 0.20, 0.70), "trunk": Color(0.56, 0.52, 0.44)},
}

var forest: Forest
var _redraw_timer := 0.0

func setup(f: Forest) -> void:
	forest = f
	forest.changed.connect(queue_redraw)
	queue_redraw()

func _process(delta: float) -> void:
	# 成長は年単位なので毎秒 1 回の再描画で十分(低スペック配慮)
	_redraw_timer += delta
	if _redraw_timer >= 1.0:
		_redraw_timer = 0.0
		queue_redraw()

func _draw() -> void:
	if forest == null:
		return
	var season: String = forest.season
	for tree in forest.trees:
		var evergreen: bool = forest.SPECIES[tree.species].evergreen
		var col: Dictionary = COLORS[tree.species]
		var r: float = forest.radius_of(tree) * PX
		var pos: Vector2 = tree.pos * PX

		if forest.is_seed(tree):
			draw_circle(pos, 4.0, Color(0.36, 0.25, 0.15))  # 種をまいた土
			continue

		if r < 6.0:
			# 苗木フェーズ
			draw_circle(pos, 3.0, Color(0.15, 0.65, 0.15))
			continue

		if season == "winter" and not evergreen:
			# 落葉樹の冬: 裸の樹形(輪郭のみ) + 幹
			draw_arc(pos, r * 0.75, 0, TAU, 32, Color(0.45, 0.38, 0.30, 0.7), 1.5)
			draw_circle(pos, 4.0, col.trunk)
			continue

		var leaf: Color = col.leaf
		if season == "autumn" and not evergreen:
			leaf = col.leaf_autumn
		elif season == "winter" and evergreen:
			# 常緑樹の冬: 少し沈んだ色
			leaf = Color(leaf.r * 0.8, leaf.g * 0.8, leaf.b * 0.85, leaf.a)

		draw_circle(pos, r, leaf)
		draw_circle(pos, r * 0.4, Color(leaf.r * 0.8, leaf.g * 0.85, leaf.b * 0.8, 0.3))
		draw_circle(pos, 4.0, col.trunk)

		# リンゴの季節演出
		if tree.species == "apple" and season == "spring":
			draw_circle(pos, r, Color(0.98, 0.80, 0.86, 0.35))  # 花
		elif forest.shows_fruit(tree):
			_draw_fruits(pos, r)                                  # 実(今日収穫したら消える)

	# 今日水をあげた木は、幹のまわりに水色の輪(どの木が済んだか分かるように)
	for tree in forest.trees:
		if forest.watered_today(tree):
			draw_arc(tree.pos * PX, 8.0, 0, TAU, 16, Color(0.25, 0.60, 0.95, 0.9), 2.0)

func _draw_fruits(pos: Vector2, r: float) -> void:
	# 座標から決まる疑似乱数で毎回同じ場所に実を描く
	var seed_val := int(absf(pos.x) * 7.0 + absf(pos.y) * 13.0)
	for i in range(5):
		var a := float((seed_val + i * 47) % 100) / 100.0 * TAU
		var d := (0.35 + 0.5 * float((seed_val + i * 31) % 100) / 100.0) * r
		draw_circle(pos + Vector2(cos(a), sin(a)) * d, 3.0, Color(0.85, 0.15, 0.12))
