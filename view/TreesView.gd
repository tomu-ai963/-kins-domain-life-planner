extends Node2D

# ── 木の 2D 表示(_draw の円) ──────────────────────────────────
# 状態とルールは logic/Forest.gd。ここは読んで描くだけ(3D では別の view に差し替える)

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
	"cedar": {
		"leaf": Color(0.08, 0.42, 0.20, 0.65),
		"leaf_autumn": Color(0.08, 0.42, 0.20, 0.65),
		"trunk": Color(0.30, 0.18, 0.08),
	},
}

var forest: Reference
var _redraw_timer := 0.0

func setup(f: Reference) -> void:
	forest = f
	forest.connect("changed", self, "update")
	update()

func _process(delta: float) -> void:
	# 成長は年単位なので毎秒 1 回の再描画で十分(低スペック配慮)
	_redraw_timer += delta
	if _redraw_timer >= 1.0:
		_redraw_timer = 0.0
		update()

func _draw() -> void:
	if forest == null:
		return
	var season: String = forest.season
	for tree in forest.trees:
		var evergreen: bool = forest.SPECIES[tree.species].evergreen
		var col: Dictionary = COLORS[tree.species]
		var r: float = forest.radius_of(tree)

		if r < 6.0:
			# 苗木フェーズ
			draw_circle(tree.pos, 3.0, Color(0.15, 0.65, 0.15))
			continue

		if season == "winter" and not evergreen:
			# 落葉樹の冬: 裸の樹形(輪郭のみ) + 幹
			draw_arc(tree.pos, r * 0.75, 0, TAU, 32, Color(0.45, 0.38, 0.30, 0.7), 1.5)
			draw_circle(tree.pos, 4.0, col.trunk)
			continue

		var leaf: Color = col.leaf
		if season == "autumn" and not evergreen:
			leaf = col.leaf_autumn
		elif season == "winter" and evergreen:
			# 常緑樹の冬: 少し沈んだ色
			leaf = Color(leaf.r * 0.8, leaf.g * 0.8, leaf.b * 0.85, leaf.a)

		draw_circle(tree.pos, r, leaf)
		draw_circle(tree.pos, r * 0.4, Color(leaf.r * 0.8, leaf.g * 0.85, leaf.b * 0.8, 0.3))
		draw_circle(tree.pos, 4.0, col.trunk)

		# リンゴの季節演出
		if tree.species == "apple" and season == "spring":
			draw_circle(tree.pos, r, Color(0.98, 0.80, 0.86, 0.35))  # 花
		elif forest.shows_fruit(tree):
			_draw_fruits(tree.pos, r)                                  # 実(今日収穫したら消える)

	# 今日水をあげた木は、幹のまわりに水色の輪(どの木が済んだか分かるように)
	for tree in forest.trees:
		if forest.watered_today(tree):
			draw_arc(tree.pos, 8.0, 0, TAU, 16, Color(0.25, 0.60, 0.95, 0.9), 2.0)

func _draw_fruits(pos: Vector2, r: float) -> void:
	# 座標から決まる疑似乱数で毎回同じ場所に実を描く
	var seed_val := int(abs(pos.x) * 7.0 + abs(pos.y) * 13.0)
	for i in range(5):
		var a := float((seed_val + i * 47) % 100) / 100.0 * TAU
		var d := (0.35 + 0.5 * float((seed_val + i * 31) % 100) / 100.0) * r
		draw_circle(pos + Vector2(cos(a), sin(a)) * d, 3.0, Color(0.85, 0.15, 0.12))
