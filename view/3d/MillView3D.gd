extends Node3D

# ── 石臼と製粉機の 3D 表示 ─────────────────────────────────────
# 状態とルールは logic/Mill.gd と logic/Tools.gd。ここは読んで形を置くだけ。
# 丸太の台の上に、上下 2 枚の石と、上の石に立てた木の取っ手。粉を持っていれば、台の横に粉袋を置く(多いほど大きい)。
# 製粉機を持っていれば、石臼の東に、ホッパー(漏斗)の付いた機械を置く。通り抜けられないように当たり判定を付ける
const Mill = preload("res://logic/Mill.gd")
const Look = preload("res://view/3d/Look.gd")

const TABLE_H := 0.55     # 台(丸太)の高さ
const STONE_R := 0.36     # 石の半径
const STONE_H := 0.12     # 石 1 枚の厚み
const MACHINE_SIDE := Vector3(1.0, 0, 0.0)  # 石臼から見た製粉機の場所(東)

var mill: Mill
var tools = null
var _shown := ""          # 今の見た目を決めた状態(ジョウロやガソリンが減るたびには作り直さない)
var _box := BoxMesh.new()
var _cylinder := CylinderMesh.new()
var _ball := SphereMesh.new()
var _wood := Look.mat(Color(0.52, 0.36, 0.20))
var _stone := Look.mat(Color(0.60, 0.58, 0.55))
var _stone_dark := Look.mat(Color(0.48, 0.46, 0.44))
var _sack := Look.mat(Color(0.86, 0.80, 0.64))
var _machine := Look.mat(Color(0.26, 0.48, 0.70))
var _dark := Look.mat(Color(0.18, 0.18, 0.18))

func setup(m: Mill, t) -> void:
	mill = m
	tools = t
	_cylinder.top_radius = 0.5
	_cylinder.bottom_radius = 0.5
	_cylinder.height = 1.0
	_cylinder.radial_segments = 16
	_cylinder.rings = 1
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 10
	_ball.rings = 5
	mill.changed.connect(_rebuild)
	tools.changed.connect(_on_tools_changed)
	_rebuild()

func _on_tools_changed() -> void:
	if _state() != _shown:
		_rebuild()

func _total_flour() -> int:
	var n := 0
	for g in mill.flour:
		n += int(mill.flour[g])
	return n

func _state() -> String:
	return "%s|%s|%d" % [str(mill.site), tools.has("mill"), mini(_total_flour(), 20)]

func _rebuild() -> void:
	Look.clear_children(self)
	_shown = _state()
	if not mill.is_placed():
		return
	var spot := Node3D.new()
	spot.name = "Quern"
	spot.position = Look.at(mill.site)
	add_child(spot, true)
	# 台(太い丸太)と、上下 2 枚の石
	spot.add_child(Look.mesh_node(_cylinder, _wood, Vector3(0, TABLE_H * 0.5, 0), Vector3(Mill.RADIUS * 2.0, TABLE_H, Mill.RADIUS * 2.0)))
	spot.add_child(Look.mesh_node(_cylinder, _stone_dark, Vector3(0, TABLE_H + STONE_H * 0.5, 0), Vector3(STONE_R * 2.0, STONE_H, STONE_R * 2.0)))
	var top := Look.mesh_node(_cylinder, _stone, Vector3(0, TABLE_H + STONE_H * 1.5 + 0.01, 0), Vector3(STONE_R * 1.9, STONE_H, STONE_R * 1.9))
	top.name = "QuernTop"
	spot.add_child(top)
	spot.add_child(Look.mesh_node(_cylinder, _stone_dark, Vector3(0, TABLE_H + STONE_H * 2.0 + 0.02, 0), Vector3(0.1, 0.02, 0.1)))  # 穀物を入れる穴
	var handle := Look.mesh_node(_cylinder, _wood, Vector3(STONE_R * 0.7, TABLE_H + STONE_H * 2.0 + 0.12, 0), Vector3(0.05, 0.24, 0.05))
	handle.name = "QuernHandle"
	spot.add_child(handle)
	# 粉袋
	var flour := _total_flour()
	if flour > 0:
		var s: float = lerpf(0.35, 0.6, minf(flour, 20) / 20.0)
		var sack := Look.mesh_node(_ball, _sack, Vector3(-0.2, s * 0.45, Mill.RADIUS + 0.35), Vector3(s, s * 0.9, s * 0.8))
		sack.name = "FlourSack"
		spot.add_child(sack)
	if tools.has("mill"):
		_machine_at(spot)
	_collider(spot)

# 製粉機: 青い箱の上にホッパー(逆さの四角すいの代わりに、上が広い箱)、横に小さなエンジン
func _machine_at(spot: Node3D) -> void:
	var node := Node3D.new()
	node.name = "MillMachine"
	node.position = MACHINE_SIDE
	spot.add_child(node)
	node.add_child(Look.mesh_node(_box, _machine, Vector3(0, 0.35, 0), Vector3(0.5, 0.7, 0.45)))
	node.add_child(Look.mesh_node(_box, _machine, Vector3(0, 0.82, 0), Vector3(0.42, 0.24, 0.42)))
	node.add_child(Look.mesh_node(_box, _machine, Vector3(0, 0.96, 0), Vector3(0.6, 0.06, 0.6)))
	node.add_child(Look.mesh_node(_box, Look.mat(Color(0.80, 0.20, 0.16)), Vector3(0.36, 0.25, 0), Vector3(0.24, 0.3, 0.3)))  # エンジン
	node.add_child(Look.mesh_node(_box, _dark, Vector3(0, 0.25, -0.26), Vector3(0.16, 0.06, 0.1)))  # 粉の出口

func _collider(spot: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "QuernBody"
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = Mill.RADIUS + 0.05
	cyl.height = TABLE_H
	shape.shape = cyl
	shape.position = Vector3(0, TABLE_H * 0.5, 0)
	body.add_child(shape)
	spot.add_child(body)
