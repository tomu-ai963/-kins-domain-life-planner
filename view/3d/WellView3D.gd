extends Node3D

# ── 井戸とエンジンポンプの 3D 表示 ──────────────────────────────
# 状態とルールは logic/Well.gd と logic/Tools.gd。ここは読んで形を置くだけ。
# 場所を決めた → 縄の輪と杭 / 掘る → 穴が深くなり、掘った土の山が大きくなる /
# 掘り終えた → 石を積んだ縁・2 本の柱と小さな屋根・巻き上げの横木・縄と桶。中に水面が見える。
# エンジンポンプを持っていれば、井戸の横(井戸がなければ池の南の岸)に置き、ホースを水へ垂らす。
# 井戸のそばに立つと、ポンプでまとめて水をやれる範囲の輪が見える(ポンプがあるときだけ)。
# 通り抜けられないように、当たり判定を付ける
const Well = preload("res://logic/Well.gd")
const Look = preload("res://view/3d/Look.gd")

const RIM_H := 0.7        # 石の縁の高さ(m)
const STONES := 12        # 縁の石の数(1 段あたり)
const POST_H := 2.0       # 柱の高さ
const PUMP_SIDE := Vector2(1.5, 0.4)  # 井戸の中心から見たポンプの場所(東)

var well: Well
var tools = null          # logic/Tools.gd(ポンプを持っているか)
var pond = null           # logic/Pond.gd(井戸がなければ池にポンプを置く)
var _player: Node3D = null
var _reach_ring: MeshInstance3D = null
var _shown_pump := false
var _box := BoxMesh.new()
var _ball := SphereMesh.new()
var _cylinder := CylinderMesh.new()
var _rope := Look.mat(Color(0.95, 0.90, 0.70), true)
var _stake := Look.mat(Color(0.75, 0.62, 0.42))
var _hole := Look.mat(Color(0.20, 0.14, 0.09))
var _dirt := Look.mat(Color(0.40, 0.29, 0.18))
var _stone := Look.mat(Color(0.62, 0.60, 0.56))
var _stone_dark := Look.mat(Color(0.50, 0.48, 0.45))
var _wood := Look.mat(Color(0.52, 0.36, 0.20))
var _roof := Look.mat(Color(0.42, 0.27, 0.16))
var _bucket := Look.mat(Color(0.60, 0.44, 0.26))
var _water := Look.mat(Color(0.18, 0.34, 0.52))
var _pump_body := Look.mat(Color(0.82, 0.20, 0.16))
var _pump_dark := Look.mat(Color(0.18, 0.18, 0.18))
var _hose := Look.mat(Color(0.20, 0.42, 0.26))
var _reach_mat := Look.mat(Color(0.45, 0.72, 0.98, 0.75), true)

func setup(w: Well, t, p = null) -> void:
	well = w
	tools = t
	pond = p
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 10
	_ball.rings = 5
	_cylinder.top_radius = 0.5
	_cylinder.bottom_radius = 0.5
	_cylinder.height = 1.0
	_cylinder.radial_segments = 14
	_cylinder.rings = 1
	well.changed.connect(_rebuild)
	tools.changed.connect(_on_tools_changed)
	if pond != null:
		pond.changed.connect(_rebuild)
		pond.land.changed.connect(_rebuild)
	_rebuild()

func set_player(p: Node3D) -> void:
	_player = p

func _process(_delta: float) -> void:
	if _reach_ring != null:
		_reach_ring.visible = _player != null and well.is_near(_player.ground_pos())

# ジョウロの水やガソリンが減るたびには作り直さない(ポンプを買ったときだけ)
func _on_tools_changed() -> void:
	if tools.has("pump") != _shown_pump:
		_rebuild()

func _rebuild() -> void:
	Look.clear_children(self)
	_reach_ring = null
	_shown_pump = tools.has("pump")
	if well.is_placed():
		var spot := Node3D.new()
		spot.name = "Well"
		spot.position = Look.at(well.site)
		add_child(spot, true)
		if well.days_dug == 0:
			_marks(spot)
		elif not well.is_dug():
			_digging(spot)
		else:
			_finished(spot)
			_collider(spot)
		if _shown_pump and well.is_dug():
			_reach_ring = Look.ring(well.site, Well.WATER_RADIUS, 0.15, _reach_mat, 0.03)
			_reach_ring.name = "WellReachRing"
			_reach_ring.layers = Look.GROUND_LAYER
			_reach_ring.visible = false
			add_child(_reach_ring)
	if _shown_pump:
		_place_pump()

func _marks(spot: Node3D) -> void:
	var r: float = Well.RADIUS
	spot.add_child(Look.ring(Vector2.ZERO, r, 0.06, _rope, 0.3))
	for i in range(6):
		var p := Vector2.from_angle(TAU * i / 6.0) * r
		spot.add_child(Look.mesh_node(_box, _stake, Look.at(p, 0.3), Vector3(0.08, 0.6, 0.08)))

# 掘っている途中: 黒い穴と、日ごとに大きくなる土の山
func _digging(spot: Node3D) -> void:
	var r: float = Well.RADIUS
	var ratio: float = float(well.days_dug) / Well.DIG_DAYS
	spot.add_child(Look.disc(Vector2.ZERO, r + 0.2, 0.04, _dirt, 0.0))
	var hole := Look.disc(Vector2.ZERO, r * 0.85, 0.04, _hole, 0.02)
	hole.name = "WellHole"
	spot.add_child(hole)
	var pile := Look.mesh_node(_ball, _dirt, Vector3(r + 1.0, 0.0, -0.3), Vector3(0.9, 0.6, 0.9) * (1.0 + 1.5 * ratio))
	pile.name = "WellDirt"
	spot.add_child(pile)

# 掘り終えた井戸: 石の縁・柱・屋根・横木・縄と桶
func _finished(spot: Node3D) -> void:
	var r: float = Well.RADIUS
	var water := Look.disc(Vector2.ZERO, r * 0.8, 0.04, _water, RIM_H * 0.35)
	water.name = "WellWater"
	spot.add_child(water)
	for layer in range(3):
		var y: float = RIM_H * (layer + 0.5) / 3.0
		for i in range(STONES):
			var a: float = TAU * (i + 0.5 * (layer % 2)) / STONES
			var p := Vector2.from_angle(a) * (r - 0.08)
			var stone := Look.mesh_node(_box, _stone if (i + layer) % 3 != 0 else _stone_dark, Look.at(p, y), Vector3(0.42, RIM_H / 3.0 - 0.02, 0.2))
			stone.rotation.y = -a + PI * 0.5
			spot.add_child(stone)
	spot.get_child(spot.get_child_count() - 1).name = "WellRim"
	# 柱と屋根(切妻)
	for side in [-1.0, 1.0]:
		spot.add_child(Look.mesh_node(_box, _wood, Vector3(side * (r + 0.05), POST_H * 0.5, 0), Vector3(0.12, POST_H, 0.12)))
	for side in [-1.0, 1.0]:
		var board := Look.mesh_node(_box, _roof, Vector3(0, POST_H + 0.18, side * 0.28), Vector3(r * 2.0 + 0.4, 0.06, 0.65))
		board.rotation.x = side * 0.55
		spot.add_child(board)
	spot.get_child(spot.get_child_count() - 1).name = "WellRoof"
	# 巻き上げの横木と、縄でつるした桶
	var axle := Look.mesh_node(_cylinder, _wood, Vector3(0, POST_H - 0.35, 0), Vector3(0.1, r * 2.0 + 0.1, 0.1))
	axle.rotation.z = PI * 0.5
	spot.add_child(axle)
	spot.add_child(Look.mesh_node(_box, _rope, Vector3(0, POST_H - 0.75, 0), Vector3(0.025, 0.8, 0.025)))
	var bucket := Look.mesh_node(_cylinder, _bucket, Vector3(0, POST_H - 1.25, 0), Vector3(0.3, 0.28, 0.3))
	bucket.name = "WellBucket"
	spot.add_child(bucket)

# エンジンポンプ: 赤い本体と黒い枠、水へ垂らしたホース。井戸の東か、池の南の岸に置く
func _place_pump() -> void:
	var at = null
	var water_at = null
	if well.is_dug():
		at = well.site + PUMP_SIDE
		water_at = well.site
	elif pond != null and pond.is_dug():
		at = pond.land.pond + Vector2(0.0, pond.land.POND_RADIUS + 0.9)
		water_at = pond.land.pond + Vector2(0.0, pond.land.POND_RADIUS - 0.6)
	if at == null:
		return
	var spot := Node3D.new()
	spot.name = "Pump"
	spot.position = Look.at(at)
	add_child(spot, true)
	spot.add_child(Look.mesh_node(_box, _pump_dark, Vector3(0, 0.05, 0), Vector3(0.6, 0.1, 0.45)))
	spot.add_child(Look.mesh_node(_box, _pump_body, Vector3(0, 0.3, 0), Vector3(0.5, 0.38, 0.38)))
	spot.add_child(Look.mesh_node(_cylinder, _pump_dark, Vector3(0.12, 0.55, 0), Vector3(0.18, 0.12, 0.18)))  # 給油口
	for side in [-1.0, 1.0]:  # 枠
		spot.add_child(Look.mesh_node(_box, _pump_dark, Vector3(side * 0.28, 0.32, 0), Vector3(0.04, 0.5, 0.42)))
	# ホース: ポンプから水まで
	var hose := Look.strip(at, water_at, 0.08, 0.08, _hose, 0.05)
	hose.name = "PumpHose"
	add_child(hose)

func _collider(spot: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "WellBody"
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = Well.RADIUS + 0.05
	cyl.height = RIM_H
	shape.shape = cyl
	shape.position = Vector3(0, RIM_H * 0.5, 0)
	body.add_child(shape)
	spot.add_child(body)
