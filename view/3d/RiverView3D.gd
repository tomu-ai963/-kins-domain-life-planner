extends Node3D

# ── 土地の外の川の 3D 表示 ──────────────────────────────────────
# 川の形と、汲めるかどうかは logic/River.gd。北の境界の外を東西に流れる小川を、
# 中心の線に沿った帯(川底の砂利の岸 → 水面)で描き、岸に石を置く。県を選んでから現れる。
# 流れているので冬も凍らない(雪の土地でも水面のまま)
const River = preload("res://logic/River.gd")
const Look = preload("res://view/3d/Look.gd")

const BANK_EXTRA := 0.7          # 岸(砂利)が水面から外へ出る幅(片側 m)
const WATER_Y := 0.03            # 水面の高さ(地面の草よりわずかに上)
const BANK_Y := 0.015
const WATER := Color(0.40, 0.62, 0.74)  # 不透明にする(帯の重なりが縞に見えないように)
const DEEP := Color(0.30, 0.52, 0.68)   # まんなかの深いところ
const BANK := Color(0.66, 0.60, 0.48)         # 砂利の岸
const STONE := Color(0.56, 0.56, 0.54)
const STONE_EVERY := 3           # 何点ごとに岸に石を置くか
const SEED := 20261115

var river: River
var _built := false

func setup(r: River) -> void:
	river = r
	river.forest.changed.connect(_refresh)
	_refresh()

func is_built() -> bool:
	return _built

func _refresh() -> void:
	if river.exists() == _built:
		return
	Look.clear_children(self)
	_built = river.exists()
	if _built:
		_build()

func _build() -> void:
	var pts: PackedVector2Array = River.points()
	var water := Look.mat(WATER)
	var deep := Look.mat(DEEP)
	var bank := Look.mat(BANK)
	var stone := Look.mat(STONE)
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 8
	ball.rings = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in range(pts.size() - 1):
		add_child(Look.strip(pts[i], pts[i + 1], (River.HALF_WIDTH + BANK_EXTRA) * 2.0, 0.0, bank, BANK_Y))
		add_child(Look.strip(pts[i], pts[i + 1], River.HALF_WIDTH * 2.0, 0.0, water, WATER_Y))
		add_child(Look.strip(pts[i], pts[i + 1], River.HALF_WIDTH, 0.0, deep, WATER_Y + 0.005))
		if i % STONE_EVERY == 0:
			var along: Vector2 = (pts[i + 1] - pts[i]).normalized()
			var side := Vector2(-along.y, along.x) * (1.0 if rng.randf() < 0.5 else -1.0)
			var p: Vector2 = pts[i] + along * rng.randf_range(0.0, River.STEP) + side * (River.HALF_WIDTH + rng.randf_range(0.0, BANK_EXTRA))
			var s: float = rng.randf_range(0.25, 0.5)
			add_child(Look.mesh_node(ball, stone, Look.at(p, s * 0.2), Vector3(s, s * 0.5, s * 0.8)))
