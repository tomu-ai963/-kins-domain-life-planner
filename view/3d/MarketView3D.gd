extends Node3D

# ── 市場(屋台)の 3D 表示 ──────────────────────────────────────
# 南の境界の外にある木の屋台。境界からの小道と、売り物の箱を置く。位置は logic/Market.gd の POS。
# 売り台と柱は通り抜けられない(屋根の下には横や後ろから入れる)
const Market = preload("res://logic/Market.gd")
const Look = preload("res://view/3d/Look.gd")

const LANTERN_ENERGY := 1.0

var market: Market
var _lantern_light: OmniLight3D
var _lantern_mat := Look.mat(Color(1.0, 0.78, 0.45))

func setup(m: Market) -> void:
	market = m
	_build()

# 暗くなると、屋台の軒のランタンをともす(0 = 昼、1 = 夜)
func set_night(amount: float) -> void:
	_lantern_light.visible = amount > 0.0
	_lantern_light.light_energy = LANTERN_ENERGY * amount
	_lantern_mat.emission_enabled = amount > 0.0
	_lantern_mat.emission = Color(1.0, 0.72, 0.38)
	_lantern_mat.emission_energy_multiplier = 3.0 * amount

func _build() -> void:
	var wood := Look.mat(Color(0.55, 0.38, 0.22))
	var dark := Look.mat(Color(0.38, 0.25, 0.14))
	var roof := Look.mat(Color(0.72, 0.28, 0.20))
	var path := Look.mat(Color(0.58, 0.48, 0.34))
	var c: Vector2 = market.POS
	# 境界から屋台までの小道
	add_child(Look.strip(Vector2(0, 50), c + Vector2(0, -1.5), 1.6, 0.02, path))
	var spot := Node3D.new()
	spot.position = Look.at(c)
	add_child(spot)
	var box := BoxMesh.new()
	# 4 本の柱
	for x in [-1.8, 1.8]:
		for z in [-1.0, 1.0]:
			spot.add_child(Look.mesh_node(box, dark, Vector3(x, 1.2, z), Vector3(0.15, 2.4, 0.15)))
	# 売り台・屋根・看板
	spot.add_child(Look.mesh_node(box, wood, Vector3(0, 0.5, -1.0), Vector3(3.8, 1.0, 0.7)))
	spot.add_child(Look.mesh_node(box, roof, Vector3(0, 2.5, 0), Vector3(4.4, 0.15, 2.8)))
	spot.add_child(Look.mesh_node(box, wood, Vector3(0, 3.0, -1.2), Vector3(2.0, 0.7, 0.1)))
	# 売り物(種の袋・苗木の鉢・リンゴの箱)
	var goods := [Color(0.85, 0.80, 0.55), Color(0.30, 0.55, 0.25), Color(0.80, 0.20, 0.15)]
	for i in range(3):
		spot.add_child(Look.mesh_node(box, Look.mat(goods[i]), Vector3(-1.2 + i * 1.2, 1.15, -1.0), Vector3(0.6, 0.3, 0.4)))
	# 軒のランタン(買いに来る北側に吊るす)
	spot.add_child(Look.mesh_node(box, _lantern_mat, Vector3(0, 2.2, -1.5), Vector3(0.22, 0.28, 0.22)))
	_lantern_light = OmniLight3D.new()
	_lantern_light.position = Vector3(0, 2.1, -1.8)
	_lantern_light.light_color = Color(1.0, 0.78, 0.5)
	_lantern_light.omni_range = 9.0
	_lantern_light.visible = false
	spot.add_child(_lantern_light)
	_build_collider(spot)

# 売り台(前の 2 本の柱も含む)と、後ろの 2 本の柱
func _build_collider(spot: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "MarketBody"
	_collider_box(body, Vector3(0, 0.6, -1.0), Vector3(3.8, 1.2, 0.7))
	for x in [-1.8, 1.8]:
		_collider_box(body, Vector3(x, 1.2, 1.0), Vector3(0.2, 2.4, 0.2))
	spot.add_child(body)

func _collider_box(body: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	body.add_child(shape)
