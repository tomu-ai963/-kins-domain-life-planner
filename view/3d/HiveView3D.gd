extends Node3D

# ── 丸太の巣箱の 3D 表示 ───────────────────────────────────────
# 状態とルールは logic/Bees.gd。くり抜いている途中は、立てた丸太と木くずの山。
# できあがると屋根と巣の入口が付き、蜂が入ると入口のまわりを蜂が飛ぶ。はちみつが採れると、入口の下が金色になる。
# 通り抜けられないように、当たり判定を付ける
const Bees = preload("res://logic/Bees.gd")
const Look = preload("res://view/3d/Look.gd")

const LOG_H := 1.0        # 巣箱の高さ(m)
const LOG_R := 0.28       # 巣箱の太さ(半径 m)
const BEES_PER_HIVE := 5
const BEE_SIZE := 0.1
const BEE_ORBIT := 0.55   # 蜂が飛ぶ範囲(m)

var bees: Bees
var _cylinder := CylinderMesh.new()
var _ball := SphereMesh.new()
var _box := BoxMesh.new()
var _bark := Look.mat(Color(0.42, 0.30, 0.18))
var _bark_light := Look.mat(Color(0.62, 0.46, 0.28))
var _roof := Look.mat(Color(0.36, 0.28, 0.20))
var _hole := Look.mat(Color(0.10, 0.07, 0.05))
var _chips := Look.mat(Color(0.86, 0.68, 0.44))
var _honey := Look.mat(Color(0.96, 0.70, 0.14))
var _bee := Look.mat(Color(0.96, 0.74, 0.14))
var _flying := []  # [{node, center: Vector3, seed: float}]
var _t := 0.0

func setup(b: Bees) -> void:
	bees = b
	_cylinder.top_radius = 0.5
	_cylinder.bottom_radius = 0.5
	_cylinder.height = 1.0
	_cylinder.radial_segments = 14
	_cylinder.rings = 1
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 8
	_ball.rings = 4
	bees.changed.connect(_rebuild)
	_rebuild()

func _process(delta: float) -> void:
	_t += delta
	for f in _flying:
		var t: float = _t * 1.6 + float(f.seed)
		f.node.position = f.center + Vector3(sin(t) * BEE_ORBIT, 0.2 * sin(t * 3.1), cos(t * 1.3) * BEE_ORBIT)

func _rebuild() -> void:
	Look.clear_children(self)
	_flying.clear()
	for h in bees.hives:
		var spot := Node3D.new()
		spot.name = "Hive"
		spot.position = Look.at(h.pos)
		add_child(spot, true)
		_hive(spot, h)
		_collider(spot)

func _hive(spot: Node3D, h: Dictionary) -> void:
	spot.add_child(Look.mesh_node(_cylinder, _bark, Vector3(0, LOG_H * 0.5, 0), Vector3(LOG_R * 2.0, LOG_H, LOG_R * 2.0)))
	if not Bees.is_hollowed(h):
		# くり抜いている途中: 切り口が見えて、木くずが増えていく
		spot.add_child(Look.mesh_node(_cylinder, _bark_light, Vector3(0, LOG_H + 0.005, 0), Vector3(LOG_R * 1.9, 0.01, LOG_R * 1.9)))
		var pile: float = 0.2 + 0.25 * int(h.days_done)
		spot.add_child(Look.mesh_node(_ball, _chips, Vector3(0.5, 0.05, 0.25), Vector3(pile, 0.14, pile)))
		return
	# できあがり: 屋根と巣の入口(南 = カメラの側)
	var roof := Look.mesh_node(_cylinder, _roof, Vector3(0, LOG_H + 0.05, 0), Vector3(LOG_R * 2.7, 0.1, LOG_R * 2.7))
	roof.name = "HiveRoof"
	spot.add_child(roof)
	var door := Look.mesh_node(_box, _hole, Vector3(0, LOG_H * 0.55, LOG_R - 0.01), Vector3(0.14, 0.09, 0.04))
	door.name = "HiveDoor"
	spot.add_child(door)
	if not h.occupied:
		return
	if float(h.comb) >= 1.0:
		var drip := Look.mesh_node(_box, _honey, Vector3(0, LOG_H * 0.4, LOG_R), Vector3(0.2, 0.14, 0.03))
		drip.name = "HiveHoney"
		spot.add_child(drip)
	var center := Vector3(0, LOG_H * 0.7, 0)
	for i in range(BEES_PER_HIVE):
		var b := Look.mesh_node(_ball, _bee, center, Vector3.ONE * BEE_SIZE)
		b.name = "HiveBee"
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spot.add_child(b, true)
		_flying.append({"node": b, "center": center, "seed": TAU * i / BEES_PER_HIVE})

func _collider(spot: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "HiveBody"
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = LOG_R + 0.05
	cyl.height = LOG_H
	shape.shape = cyl
	shape.position = Vector3(0, LOG_H * 0.5, 0)
	body.add_child(shape)
	spot.add_child(body)
