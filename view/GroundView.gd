extends Node2D

# ── 地面の 2D 表示(草地・グリッド・メルカバ・境界) ────────────────────
# スケール: 1m = 40px  →  1ヘクタール(100m×100m) = 4000px×4000px
# ワールド原点(0,0)をドメイン中心とし、±2000px(±50m)が境界。季節は logic/Forest.gd から読む

# 季節ごとの地面パレット
const GROUND := {
	"spring": {"dirt": Color(0.40, 0.30, 0.20), "grass": Color(0.62, 0.82, 0.42), "grid": Color(0.50, 0.70, 0.32)},
	"summer": {"dirt": Color(0.38, 0.28, 0.18), "grass": Color(0.56, 0.77, 0.34), "grid": Color(0.44, 0.65, 0.27)},
	"autumn": {"dirt": Color(0.36, 0.26, 0.16), "grass": Color(0.74, 0.66, 0.32), "grid": Color(0.62, 0.55, 0.26)},
	"winter": {"dirt": Color(0.35, 0.32, 0.30), "grass": Color(0.88, 0.90, 0.92), "grid": Color(0.78, 0.81, 0.85)},
}

var forest: Reference
var _season := ""

func setup(f: Reference) -> void:
	forest = f
	forest.connect("changed", self, "_on_changed")
	_on_changed()

# 地面は季節が変わったときだけ描き直す
func _on_changed() -> void:
	if forest.season != _season:
		_season = forest.season
		update()

func _draw() -> void:
	if _season == "":
		return
	var half := 2000.0
	var grid := 400.0   # 10m グリッド
	var pal: Dictionary = GROUND[_season]

	# ドメイン外（土の色）
	draw_rect(Rect2(-6000, -6000, 12000, 12000), pal.dirt)

	# 1ヘクタール草原（冬は雪原）
	draw_rect(Rect2(-half, -half, half * 2, half * 2), pal.grass)

	# 10m グリッド線
	for i in range(-5, 6):
		var p := float(i) * grid
		draw_line(Vector2(p, -half), Vector2(p,  half), pal.grid, 1)
		draw_line(Vector2(-half, p), Vector2( half, p), pal.grid, 1)

	# ── メルカバ（二つの正三角形 / 六芒星）────────────────────────
	# 土地のエネルギー軸を示す黄金色のガイドライン
	# 半径 600px = 15m。頂点はドメイン原点を中心に等分配置
	_draw_merkaba(Vector2.ZERO, 600.0, Color(1.0, 0.82, 0.18, 0.38), 2.0)
	# ────────────────────────────────────────────────────────────────

	# ドメイン境界線
	draw_line(Vector2(-half, -half), Vector2( half, -half), Color(0.18, 0.44, 0.14), 4)
	draw_line(Vector2( half, -half), Vector2( half,  half), Color(0.18, 0.44, 0.14), 4)
	draw_line(Vector2( half,  half), Vector2(-half,  half), Color(0.18, 0.44, 0.14), 4)
	draw_line(Vector2(-half,  half), Vector2(-half, -half), Color(0.18, 0.44, 0.14), 4)

	# 原点マーカー
	draw_circle(Vector2.ZERO, 7, Color(0.92, 0.18, 0.1))

# 正三角形 2 枚を重ねて六芒星（メルカバ）を描く
# △ (上向き): 頂点が上  /  ▽ (下向き): 頂点が下
func _draw_merkaba(center: Vector2, radius: float, color: Color, width: float) -> void:
	var h := sqrt(3.0) * 0.5  # sin(60°) ≈ 0.866

	# 上向き三角形 △
	var u0 := center + Vector2(0,          -radius)
	var u1 := center + Vector2(-radius * h,  radius * 0.5)
	var u2 := center + Vector2( radius * h,  radius * 0.5)
	draw_line(u0, u1, color, width)
	draw_line(u1, u2, color, width)
	draw_line(u2, u0, color, width)

	# 下向き三角形 ▽
	var d0 := center + Vector2(0,           radius)
	var d1 := center + Vector2(-radius * h, -radius * 0.5)
	var d2 := center + Vector2( radius * h, -radius * 0.5)
	draw_line(d0, d1, color, width)
	draw_line(d1, d2, color, width)
	draw_line(d2, d0, color, width)
