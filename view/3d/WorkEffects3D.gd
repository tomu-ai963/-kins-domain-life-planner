extends Node3D

# ── 作業のときに飛ぶもの(水・土・木くず・収穫物) ───────────────────
# 小さな玉を放り投げて、数百 ms で消す。見た目だけで、ルールには関わらない。
# Player3D が top_level の子として持つ(プレイヤーが動いても、飛んだものは付いてこない)
const Look = preload("res://view/3d/Look.gd")
const GardenView = preload("res://view/3d/GardenView3D.gd")
const TreesView = preload("res://view/3d/TreesView3D.gd")

const GRAVITY := -6.0
const DROPS := 14            # じょうろから出る水の粒の数
const DROP_EVERY := 0.05     # 水の粒を出す間隔(秒)
const WATER := Color(0.40, 0.70, 1.0)
const DIRT := Color(0.36, 0.25, 0.15)
const WOOD := Color(0.86, 0.68, 0.44)
const LEAF := Color(0.32, 0.60, 0.24)
const TWIG := Color(0.38, 0.26, 0.16)
const GRAIN := Color(0.93, 0.80, 0.42)

var figure: Node3D  # じょうろの注ぎ口の位置を聞く(PlayerFigure3D)
var _mats := {}
var _ball := SphereMesh.new()
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 8
	_ball.rings = 4
	_rng.randomize()

# 作業 kind の当たった瞬間に呼ぶ。spot は作業する場所の地面、item は収穫物(野菜の id か apple)
func play(kind: String, spot: Vector3, item := "") -> void:
	match kind:
		"water":
			_pour()
		"dig":
			_scatter(DIRT, spot + Vector3(0, 0.1, 0), 7, 0.09, 0.9, 2.0)
		"plant":
			_scatter(DIRT, spot + Vector3(0, 0.1, 0), 3, 0.06, 0.4, 1.2)
		"pull":
			_scatter(DIRT, spot + Vector3(0, 0.1, 0), 5, 0.08, 0.7, 1.8)
			_scatter(LEAF, spot + Vector3(0, 0.2, 0), 3, 0.08, 0.5, 1.6)
		"chop":
			_scatter(WOOD, spot + Vector3(0, 0.8, 0), 7, 0.07, 1.2, 1.4)
		"build":
			_scatter(WOOD, spot + Vector3(0, 1.0, 0), 5, 0.06, 0.8, 1.2)
		"pick":
			_scatter(_item_color(item), spot + Vector3(0, 0.25, 0), 5, 0.14, 0.5, 2.6)
		"pick_high":
			_scatter(_item_color(item), spot + Vector3(0, 2.2, 0), 4, 0.14, 0.4, 0.0)
		"prune":  # 切った枝が落ちる
			_scatter(TWIG, spot + Vector3(0, 2.0, 0), 7, 0.07, 0.7, 0.2)
		"feed":  # 手から台の上へ種をまく
			_scatter(GRAIN, spot + Vector3(0, 1.25, 0), 7, 0.05, 0.35, 0.8)

func _item_color(item: String) -> Color:
	if GardenView.LOOKS.has(item):
		return GardenView.LOOKS[item].ripe
	if TreesView.FRUIT_LOOKS.has(item):
		return TreesView.FRUIT_LOOKS[item].color
	if item == "honey":
		return Color(0.96, 0.70, 0.14)
	return TreesView.FRUIT

# じょうろの水: 少しずつ注ぎ口から落とす
func _pour() -> void:
	_drop()
	for i in range(1, DROPS):
		create_tween().tween_callback(_drop).set_delay(i * DROP_EVERY)

func _drop() -> void:
	if figure == null:
		return
	var v := Vector3(_rng.randf_range(-0.2, 0.2), 0.0, _rng.randf_range(-0.2, 0.2))
	_throw(WATER, figure.spout_pos(), v, 0.45, 0.05)

# 玉を n 個、まわりへ放り上げる
func _scatter(c: Color, from: Vector3, n: int, size: float, spread: float, up: float) -> void:
	for _i in range(n):
		var v := Vector3(_rng.randf_range(-spread, spread), up * _rng.randf_range(0.7, 1.2), _rng.randf_range(-spread, spread))
		_throw(c, from, v, 0.6, size)

func _throw(c: Color, from: Vector3, v: Vector3, seconds: float, size: float) -> void:
	if not _mats.has(c):
		_mats[c] = Look.mat(c)
	var mi := Look.mesh_node(_ball, _mats[c], from, Vector3.ONE * size)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var tw := mi.create_tween()
	tw.tween_method(_move.bind(mi, from, v, seconds, size), 0.0, seconds, seconds)
	tw.tween_callback(mi.queue_free)

func _move(t: float, mi: MeshInstance3D, from: Vector3, v: Vector3, seconds: float, size: float) -> void:
	mi.position = from + v * t + Vector3(0, 0.5 * GRAVITY * t * t, 0)
	mi.scale = Vector3.ONE * size * minf(1.0, (1.0 - t / seconds) * 3.0)
