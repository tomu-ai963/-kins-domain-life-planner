extends Node3D

# ── 池の 3D 表示 ───────────────────────────────────────────
# 状態とルールは logic/Pond.gd(場所は logic/Land.gd)。ここは読んで形を置くだけ。
# 場所を決めた → 縄の輪 / 掘る → 穴が広がり、掘った土の山が大きくなる / 掘り終えた → 空の穴 /
# 雨 → 水面が広がる(冬は氷) / 生き物 → 水面や岸に出て、ゆっくり動く
const Pond = preload("res://logic/Pond.gd")
const Look = preload("res://view/3d/Look.gd")

const MIN_WATER_SCALE := 0.5  # 水が少ないときの水面の半径(池の半径に対する割合)
const COUNTS := {"strider": 5, "reed": 8, "frog": 2, "dragonfly": 3, "duck": 2}

var pond: Pond
var _movers := []  # 動く生き物 [{node, radius, speed, phase, height, bob}]
var _t := 0.0
var _ball := SphereMesh.new()
var _box := BoxMesh.new()
var _rope := Look.mat(Color(0.95, 0.90, 0.70), true)
var _stake := Look.mat(Color(0.75, 0.62, 0.42))
var _shore := Look.mat(Color(0.48, 0.40, 0.28))
var _hole := Look.mat(Color(0.26, 0.19, 0.12))
var _dirt := Look.mat(Color(0.40, 0.29, 0.18))
var _water_deep := Look.mat(Color(0.22, 0.45, 0.72, 0.9))
var _water_light := Look.mat(Color(0.40, 0.66, 0.90, 0.6))
var _ice := Look.mat(Color(0.62, 0.78, 0.90))  # 雪の地面と見分けられる青み
var _strider := Look.mat(Color(0.12, 0.10, 0.08))
var _reed_leaf := Look.mat(Color(0.36, 0.55, 0.24))
var _reed_head := Look.mat(Color(0.34, 0.20, 0.10))
var _frog := Look.mat(Color(0.32, 0.62, 0.20))
var _dragonfly := Look.mat(Color(0.85, 0.20, 0.15), true)
var _duck := Look.mat(Color(0.52, 0.40, 0.28))
var _duck_head := Look.mat(Color(0.12, 0.42, 0.26))
var _reach_mat := Look.mat(Color(0.45, 0.72, 0.98, 0.75), true)  # まとめて水やりの範囲の輪(草にも雪にも見える水色)
var _player: Node3D = null       # 3D のときだけ Main が渡す
var _reach_ring: MeshInstance3D = null  # 池の中心から WATER_RADIUS の輪。池のそばに立ったときだけ見せる

func setup(p: Pond) -> void:
	pond = p
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 20
	_ball.rings = 10
	pond.changed.connect(_rebuild)
	pond.land.changed.connect(_rebuild)
	pond.forest.changed.connect(_rebuild)  # 季節(氷・生き物)
	_rebuild()

func set_player(p: Node3D) -> void:
	_player = p

func _process(delta: float) -> void:
	_t += delta
	if _reach_ring != null:
		# 池のそば(場所を決めただけでも)に立つと、まとめて水をやれる範囲が見える。凍っている冬は運べないので出さない
		_reach_ring.visible = _player != null and pond.is_near(_player.ground_pos()) and not pond.is_frozen()
	for m in _movers:
		var a: float = _t * m.speed + m.phase
		var n: Node3D = m.node
		n.position = Vector3(cos(a) * m.radius, m.height + sin(_t * 3.0 + m.phase) * m.bob, sin(a) * m.radius)
		n.rotation.y = -a

func _rebuild() -> void:
	Look.clear_children(self)
	_movers.clear()
	_reach_ring = null
	if not pond.is_placed():
		return
	var spot := Node3D.new()
	spot.position = Look.at(pond.land.pond)
	add_child(spot)
	# 輪は池の部品(spot)とは別に置く(池の段階ごとの部品の数を変えない)
	_reach_ring = Look.ring(pond.land.pond, pond.WATER_RADIUS, 0.15, _reach_mat, 0.03)
	_reach_ring.name = "ReachRing"
	_reach_ring.layers = Look.GROUND_LAYER
	_reach_ring.visible = false
	add_child(_reach_ring)
	var r: float = pond.land.POND_RADIUS
	if pond.days_dug == 0:
		_marks(spot, r)
		return
	spot.add_child(Look.disc(Vector2.ZERO, r + 0.3, 0.04, _shore, 0.0))
	if not pond.is_dug():
		var ratio: float = float(pond.days_dug) / pond.DIG_DAYS
		spot.add_child(Look.disc(Vector2.ZERO, r * ratio, 0.04, _hole, 0.02))
		spot.add_child(Look.mesh_node(_ball, _dirt, Vector3(r + 1.5, 0.0, 0.0), Vector3(1.0, 0.7, 1.0) * (1.0 + 2.0 * ratio)))
		return
	spot.add_child(Look.disc(Vector2.ZERO, r, 0.04, _hole, 0.02))
	if pond.water > 0:
		var wr: float = r * lerpf(MIN_WATER_SCALE, 1.0, pond.water / 100.0)
		if pond.is_frozen():
			spot.add_child(Look.disc(Vector2.ZERO, wr, 0.04, _ice, 0.04))
		else:
			spot.add_child(Look.disc(Vector2.ZERO, wr, 0.04, _water_deep, 0.04))
			spot.add_child(Look.disc(Vector2.ZERO, wr * 0.6, 0.04, _water_light, 0.06))
	for id in pond.present():
		_creature(spot, id, r)

func _marks(spot: Node3D, r: float) -> void:
	spot.add_child(Look.ring(Vector2.ZERO, r, 0.08, _rope, 0.3))
	for i in range(8):
		var p := Vector2.from_angle(TAU * i / 8.0) * r
		spot.add_child(Look.mesh_node(_box, _stake, Look.at(p, 0.3), Vector3(0.1, 0.6, 0.1)))

func _creature(spot: Node3D, id: String, r: float) -> void:
	for i in range(int(COUNTS[id])):
		var a: float = TAU * i / float(COUNTS[id])
		match id:
			"strider":
				_mover(spot, Look.mesh_node(_ball, _strider, Vector3.ZERO, Vector3(0.18, 0.05, 0.08)), r * 0.25 + i * 0.4, 0.25, a, 0.11, 0.0)
			"reed":
				# 岸の北側に群れて生える
				var p := Vector2.from_angle(PI + PI * (i + 0.5) / COUNTS[id]) * (r - 0.1)
				spot.add_child(Look.mesh_node(_box, _reed_leaf, Look.at(p, 0.8), Vector3(0.06, 1.6, 0.06)))
				spot.add_child(Look.mesh_node(_ball, _reed_head, Look.at(p, 1.65), Vector3(0.12, 0.35, 0.12)))
			"frog":
				var p := Vector2.from_angle(a + 0.6) * (r + 0.1)
				spot.add_child(Look.mesh_node(_ball, _frog, Look.at(p, 0.12), Vector3(0.28, 0.2, 0.32)))
			"dragonfly":
				_mover(spot, Look.mesh_node(_box, _dragonfly, Vector3.ZERO, Vector3(0.28, 0.05, 0.06)), r * 0.7, 0.9, a, 1.2, 0.2)
			"duck":
				var duck := Look.mesh_node(_ball, _duck, Vector3.ZERO, Vector3(0.7, 0.4, 0.45))
				duck.add_child(Look.mesh_node(_ball, _duck_head, Vector3(0.45, 0.65, 0.0), Vector3(0.45, 0.8, 0.7)))
				_mover(spot, duck, r * 0.5, 0.12, a, 0.2, 0.0)

func _mover(spot: Node3D, node: Node3D, radius: float, speed: float, phase: float, height: float, bob: float) -> void:
	spot.add_child(node)
	_movers.append({"node": node, "radius": radius, "speed": speed, "phase": phase, "height": height, "bob": bob})
	node.position = Vector3(cos(phase) * radius, height, sin(phase) * radius)
