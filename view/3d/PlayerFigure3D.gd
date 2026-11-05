extends Node3D

# ── プレイヤーの体(顔と手足のある人物) ──────────────────────────
# 基本の形を組み合わせて作り、手足を振って歩く。向きは -z が正面、足の裏が y = 0。
# 当たり判定は Player3D.tscn のカプセルのままで、ここは見た目だけ
const Look = preload("res://view/3d/Look.gd")

const SKIN := Color(0.93, 0.74, 0.60)
const CHEEK := Color(0.93, 0.60, 0.52)
const EYE := Color(0.13, 0.09, 0.08)
const MOUTH := Color(0.62, 0.30, 0.26)
const HAIR := Color(0.36, 0.22, 0.12)
const TUNIC := Color(0.22, 0.48, 0.92)  # 遠くからでも見つけやすい青(カプセルのころと同じ色)
const SASH := Color(0.80, 0.26, 0.20)
const TROUSERS := Color(0.34, 0.30, 0.27)
const BOOTS := Color(0.28, 0.17, 0.10)

const HIP_Y := 0.66
const STRIDE_SPEED := 10.0  # 手足を振る速さ(rad/s)。歩く速さ 5 m/s に合わせた
const LEG_SWING := 0.75     # 足の振れ幅(rad)
const ARM_SWING := 0.6
const BOB := 0.035          # 歩くときの上下の揺れ(m)
const LEAN := 0.10          # 歩くときの前かがみ(rad)
const BLEND_SPEED := 8.0    # 歩きと立ちを切り替える速さ
const LANTERN_ARM := 0.55   # ランタンを持つ腕を前に出す角度(rad)
const ARM_SPREAD := 0.12    # 腕を体から少し離す角度(rad)

var moving := false         # Player3D が毎フレーム決める
var holding_lantern := false
var right_hand: Node3D      # ランタンを持たせる場所

var _phase := 0.0
var _amount := 0.0          # 0 = 立っている、1 = 歩いている
var _lift := 0.0            # ランタンを持つ腕の上がり具合
var _hips: Node3D
var _upper: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D

func _ready() -> void:
	_build()

func _process(delta: float) -> void:
	var blend := minf(1.0, BLEND_SPEED * delta)
	_amount = lerpf(_amount, 1.0 if moving else 0.0, blend)
	_lift = lerpf(_lift, 1.0 if holding_lantern else 0.0, blend)
	if moving:
		_phase = fposmod(_phase + STRIDE_SPEED * delta, TAU)
	var swing := sin(_phase) * _amount
	_leg_l.rotation.x = swing * LEG_SWING
	_leg_r.rotation.x = -swing * LEG_SWING
	_arm_l.rotation.x = -swing * ARM_SWING
	# ランタンを持つ腕は前に出し、振りを小さくする
	_arm_r.rotation.x = swing * ARM_SWING * (1.0 - _lift * 0.7) + _lift * LANTERN_ARM
	_hips.position.y = absf(cos(_phase)) * BOB * _amount
	_upper.rotation.x = -LEAN * _amount

# 持ち物を手に持たせる(手の下にぶら下げる)
func hold(item: Node3D) -> void:
	item.reparent(right_hand, false)
	item.position = Vector3(0.0, -0.16, 0.0)

func swing_amount() -> float:
	return absf(_leg_l.rotation.x)

func _build() -> void:
	var skin := Look.mat(SKIN)
	var hair := Look.mat(HAIR)
	var tunic := Look.mat(TUNIC)
	var trousers := Look.mat(TROUSERS)
	var boots := Look.mat(BOOTS)

	_hips = _pivot("Hips", self, Vector3.ZERO)
	_leg_l = _build_leg("LegL", -0.085, trousers, boots)
	_leg_r = _build_leg("LegR", 0.085, trousers, boots)

	_upper = _pivot("Upper", _hips, Vector3(0.0, HIP_Y, 0.0))
	_part("Tunic", _upper, _cone(0.15, 0.21, 0.52), tunic, Vector3(0.0, 0.16, 0.0))
	_part("Shoulders", _upper, _ball(), tunic, Vector3(0.0, 0.39, 0.0), Vector3(0.34, 0.13, 0.21))
	_part("Sash", _upper, _cone(0.197, 0.202, 0.055), Look.mat(SASH), Vector3(0.0, 0.05, 0.0))
	_part("Neck", _upper, _cone(0.055, 0.06, 0.14), skin, Vector3(0.0, 0.49, 0.0))

	_arm_l = _build_arm("ArmL", -1.0, tunic, skin)
	_arm_r = _build_arm("ArmR", 1.0, tunic, skin)
	right_hand = _arm_r.get_node("Hand")

	# 髪: 後ろ上にずらした球で頭を包むと、前だけ顔が見える。上から見下ろすカメラでも顔が隠れないよう、深めに後ろへずらす
	var head := _pivot("Head", _upper, Vector3(0.0, 0.70, 0.0))
	_part("Face", head, _ball(), skin, Vector3.ZERO, Vector3(0.38, 0.37, 0.36))
	_part("Hair", head, _ball(), hair, Vector3(0.0, 0.060, 0.075), Vector3(0.405, 0.365, 0.35))
	_part("Bangs", head, _ball(), hair, Vector3(0.0, 0.130, -0.060), Vector3(0.28, 0.10, 0.18))
	for side in [-1.0, 1.0]:
		_part("Eye", head, _ball(), Look.mat(EYE), Vector3(side * 0.072, 0.020, -0.160), Vector3(0.042, 0.062, 0.022))
		_part("Cheek", head, _ball(), Look.mat(CHEEK), Vector3(side * 0.112, -0.038, -0.138), Vector3(0.060, 0.034, 0.020))
	_part("Mouth", head, _ball(), Look.mat(MOUTH), Vector3(0.0, -0.075, -0.158), Vector3(0.050, 0.016, 0.016))

func _build_leg(node_name: String, x: float, trousers: Material, boots: Material) -> Node3D:
	var leg := _pivot(node_name, _hips, Vector3(x, HIP_Y, 0.0))
	_part("Thigh", leg, _capsule(0.078, 0.60), trousers, Vector3(0.0, -0.30, 0.0))
	_part("Boot", leg, _ball(), boots, Vector3(0.0, -0.60, -0.035), Vector3(0.16, 0.13, 0.26))
	return leg

func _build_arm(node_name: String, side: float, tunic: Material, skin: Material) -> Node3D:
	var shoulder := _pivot(node_name + "Spread", _upper, Vector3(side * 0.205, 0.38, 0.0))
	shoulder.rotation.z = side * ARM_SPREAD
	var arm := _pivot(node_name, shoulder, Vector3.ZERO)
	_part("Sleeve", arm, _capsule(0.056, 0.40), tunic, Vector3(0.0, -0.17, 0.0))
	var hand := _pivot("Hand", arm, Vector3(0.0, -0.39, 0.0))
	_part("Palm", hand, _ball(), skin, Vector3.ZERO, Vector3.ONE * 0.115)
	return arm

func _pivot(node_name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n

func _part(node_name: String, parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, scl := Vector3.ONE) -> void:
	var mi := Look.mesh_node(mesh, material, pos, scl)
	mi.name = node_name
	parent.add_child(mi, true)

# 直径 1 の球。scale で大きさと形を決める
var _ball_mesh: SphereMesh
func _ball() -> SphereMesh:
	if _ball_mesh == null:
		_ball_mesh = SphereMesh.new()
		_ball_mesh.radius = 0.5
		_ball_mesh.height = 1.0
		_ball_mesh.radial_segments = 24
		_ball_mesh.rings = 12
	return _ball_mesh

func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 16
	m.rings = 4
	return m

func _cone(top: float, bottom: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 20
	m.rings = 1
	return m
