extends Node2D

# スケール: 1m = 40px  →  1ヘクタール(100m×100m) = 4000px×4000px
# ワールド原点(0,0)をドメイン中心とし、±2000px(±50m)が境界

func _ready() -> void:
	$HUD.player = $Player
	$Player.connect("plant_tree", self, "_on_plant_tree")

func _on_plant_tree(pos: Vector2) -> void:
	$Trees.add_tree(pos)

func _draw() -> void:
	var half := 2000.0
	var grid := 400.0   # 10m グリッド

	# ドメイン外（土の色）
	draw_rect(Rect2(-6000, -6000, 12000, 12000), Color(0.38, 0.28, 0.18))

	# 1ヘクタール草原
	draw_rect(Rect2(-half, -half, half * 2, half * 2), Color(0.56, 0.77, 0.34))

	# 10m グリッド線
	for i in range(-5, 6):
		var p := float(i) * grid
		draw_line(Vector2(p, -half), Vector2(p,  half), Color(0.44, 0.65, 0.27), 1)
		draw_line(Vector2(-half, p), Vector2( half, p), Color(0.44, 0.65, 0.27), 1)

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
