extends Node3D

# ── プレイヤーの体(顔と手足のある人物) ──────────────────────────
# 基本の形を組み合わせて作り、手足を振って歩く。向きは -z が正面、足の裏が y = 0。
# 作業(play)のときは腕と上体を動かし、道具を持つ。歩いている足はそのまま動く。
# 当たり判定は Player3D.tscn のカプセルのままで、ここは見た目だけ
const Look = preload("res://view/3d/Look.gd")

signal action_finished

# 作業の動き。seconds: 全体の長さ / hit: 道具が当たる(物が飛ぶ)までの秒 / tool: 持つ道具
const ACTIONS := {
	"water": {"seconds": 1.0, "hit": 0.22, "tool": "can"},
	"dig": {"seconds": 0.65, "hit": 0.38, "tool": "hoe"},
	"chop": {"seconds": 0.65, "hit": 0.38, "tool": "axe"},
	"build": {"seconds": 0.8, "hit": 0.3, "tool": "hammer"},
	"pick": {"seconds": 0.6, "hit": 0.28, "tool": ""},
	"pick_high": {"seconds": 0.6, "hit": 0.2, "tool": ""},
	"prune": {"seconds": 0.9, "hit": 0.35, "tool": "shears"},
	"feed": {"seconds": 0.7, "hit": 0.3, "tool": ""},
	"shovel": {"seconds": 0.5, "hit": 0.28, "tool": "shovel"},
	"plant": {"seconds": 0.6, "hit": 0.3, "tool": ""},
	"pull": {"seconds": 0.6, "hit": 0.35, "tool": ""},
	"wave": {"seconds": 1.1, "hit": 0.0, "tool": ""},
}
# 道具を持つ角度(手に対する x 回転)。腕を振り下ろしたときに道具の先が前の低いところへ来るように
const TOOL_ANGLES := {"can": -1.25, "hoe": -1.0, "axe": -1.3, "hammer": -1.0, "shears": -1.4, "shovel": -0.95}
const POUR_TILT := 0.55   # じょうろを傾ける角度(rad)
const CAN_ARM := 1.25     # じょうろを持つ腕の角度(rad)
const STEEL := Color(0.55, 0.57, 0.60)
const HANDLE := Color(0.62, 0.44, 0.24)
const CAN := Color(0.40, 0.62, 0.58)

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
var look := {}              # 色を変えるとき { "TUNIC": Color, ... }。add_child の前に設定する(訪問者)
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
var _action := ""           # 今している作業。なければ ""
var _action_t := 0.0        # 作業の進み具合 0〜1
var _tools := {}            # 道具の名前 → Node3D
var _spout: Node3D          # じょうろの注ぎ口

func _ready() -> void:
	_build()
	_build_tools()

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
	if _action != "":
		_apply_action(delta)

# ── 作業の動き ─────────────────────────────────────────────
func play(kind: String) -> void:
	_show_tool("")
	_action = kind
	_action_t = 0.0
	_show_tool(ACTIONS[kind].tool)

func is_acting() -> bool:
	return _action != ""

func current_action() -> String:
	return _action

func current_tool() -> String:
	for tool_name in _tools:
		if _tools[tool_name].visible:
			return tool_name
	return ""

func spout_pos() -> Vector3:
	return _spout.global_position

func _show_tool(tool_name: String) -> void:
	for key in _tools:
		_tools[key].visible = key == tool_name
		_tools[key].rotation.x = TOOL_ANGLES[key]

func _apply_action(delta: float) -> void:
	_action_t += delta / float(ACTIONS[_action].seconds)
	if _action_t >= 1.0:
		_action = ""
		_arm_r.get_parent().rotation.z = ARM_SPREAD
		_show_tool("")
		action_finished.emit()
		return
	var t := _action_t
	var e := smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.82, 1.0, t))  # 作業の姿勢へ入って、戻る
	match _action:
		"water":
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, CAN_ARM, e)
			_tools.can.rotation.x = TOOL_ANGLES.can - POUR_TILT * smoothstep(0.1, 0.25, t) * (1.0 - smoothstep(0.8, 0.95, t))
			_upper.rotation.x = lerpf(_upper.rotation.x, -0.08, e)
		"chop":
			_swing_both(t, e, 2.5, 0.8, -0.35)
		"dig":
			_swing_both(t, e, 1.7, 0.55, -0.45)
		"build":
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 1.6 + 0.7 * sin(t * TAU * 2.0), e)
			_upper.rotation.x = lerpf(_upper.rotation.x, -0.12, e)
		"pick":
			_bow(e, -0.75, 0.9)
		"plant":
			_bow(e, -0.9, 1.0 + 0.2 * sin(t * TAU * 2.0))
		"pull":
			_bow(e, -0.7 + 0.3 * smoothstep(0.5, 0.7, t), 1.0)
		"pick_high":
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 2.7, e)
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 2.7, e)
			_upper.rotation.x = lerpf(_upper.rotation.x, 0.08, e)
		"prune":  # 枝へ手を伸ばして、はさみで何度か切る
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 2.3, e)
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 2.5 + 0.22 * sin(t * TAU * 3.0), e)
			_upper.rotation.x = lerpf(_upper.rotation.x, 0.06, e)
		"feed":  # 台の高さへ手を伸ばして、種をまく
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 1.55 + 0.25 * sin(t * TAU * 2.0), e)
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 1.1, e)
		"shovel":  # 腰を曲げて雪をすくい、横へ放る
			var scoop: float = sin(t * PI)
			_bow(e, -0.45 + 0.25 * scoop, 0.8 + 0.55 * scoop)
		"wave":  # 右手を上げて振る
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 2.8, e)
			_arm_r.get_parent().rotation.z = ARM_SPREAD + e * (0.5 + 0.35 * sin(t * TAU * 3.0))

# 両手で振りかぶって振り下ろす(斧・くわ)。t = 0.45 までが振りかぶり、0.58 で当たる
func _swing_both(t: float, e: float, high: float, low: float, lean: float) -> void:
	var angle: float = high * smoothstep(0.0, 0.4, t) if t < 0.45 else lerpf(high, low, smoothstep(0.45, 0.58, t))
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, angle, e)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, angle, e)
	var bend: float = lerpf(0.1, lean, smoothstep(0.45, 0.58, t))
	_upper.rotation.x = lerpf(_upper.rotation.x, bend, e)

# 腰を曲げて手を伸ばす
func _bow(e: float, lean: float, arms: float) -> void:
	_upper.rotation.x = lerpf(_upper.rotation.x, lean, e)
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, arms, e)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, arms, e)

# 道具は右手の子。柄は手から -z へ伸び、刃は振り下ろす向き(-y)へ付ける。ふだんは見せない
func _build_tools() -> void:
	var can := _tool("can")
	var can_mat := Look.mat(CAN)
	_box(can, can_mat, Vector3(0, -0.02, -0.14), Vector3(0.17, 0.17, 0.2))
	_box(can, can_mat, Vector3(0, 0.08, -0.14), Vector3(0.03, 0.03, 0.16))  # 取っ手
	_box(can, can_mat, Vector3(0, 0.0, -0.33), Vector3(0.035, 0.035, 0.22)) # 注ぎ口
	_spout = Node3D.new()
	_spout.name = "Spout"
	_spout.position = Vector3(0, 0.0, -0.45)
	can.add_child(_spout)
	var handle := Look.mat(HANDLE)
	var steel := Look.mat(STEEL)
	var hoe := _tool("hoe")
	_box(hoe, handle, Vector3(0, 0, -0.35), Vector3(0.03, 0.03, 1.0))
	_box(hoe, steel, Vector3(0, -0.09, -0.83), Vector3(0.17, 0.2, 0.03))
	var axe := _tool("axe")
	_box(axe, handle, Vector3(0, 0, -0.24), Vector3(0.03, 0.03, 0.62))
	_box(axe, steel, Vector3(0, -0.07, -0.5), Vector3(0.03, 0.18, 0.13))
	var hammer := _tool("hammer")
	_box(hammer, handle, Vector3(0, 0, -0.14), Vector3(0.03, 0.03, 0.34))
	_box(hammer, steel, Vector3(0, -0.02, -0.3), Vector3(0.06, 0.15, 0.06))
	var shovel := _tool("shovel")
	_box(shovel, handle, Vector3(0, 0, -0.33), Vector3(0.03, 0.03, 0.95))
	_box(shovel, steel, Vector3(0, -0.03, -0.9), Vector3(0.3, 0.03, 0.3))
	var shears := _tool("shears")
	_box(shears, handle, Vector3(-0.025, 0, -0.08), Vector3(0.025, 0.025, 0.2))
	_box(shears, handle, Vector3(0.025, 0, -0.08), Vector3(0.025, 0.025, 0.2))
	_box(shears, steel, Vector3(-0.012, 0, -0.27), Vector3(0.025, 0.03, 0.2))
	_box(shears, steel, Vector3(0.012, 0, -0.27), Vector3(0.025, 0.03, 0.2))
	_show_tool("")

func _tool(tool_name: String) -> Node3D:
	var n := _pivot("Tool_" + tool_name, right_hand, Vector3.ZERO)
	_tools[tool_name] = n
	return n

var _box_mesh := BoxMesh.new()
func _box(parent: Node3D, m: Material, pos: Vector3, size: Vector3) -> void:
	parent.add_child(Look.mesh_node(_box_mesh, m, pos, size))

# 持ち物を手に持たせる(手の下にぶら下げる)
func hold(item: Node3D) -> void:
	item.reparent(right_hand, false)
	item.position = Vector3(0.0, -0.16, 0.0)

func swing_amount() -> float:
	return absf(_leg_l.rotation.x)

func _build() -> void:
	var skin := Look.mat(SKIN)
	var hair := Look.mat(look.get("HAIR", HAIR))
	var tunic := Look.mat(look.get("TUNIC", TUNIC))
	var trousers := Look.mat(look.get("TROUSERS", TROUSERS))
	var boots := Look.mat(BOOTS)

	_hips = _pivot("Hips", self, Vector3.ZERO)
	_leg_l = _build_leg("LegL", -0.085, trousers, boots)
	_leg_r = _build_leg("LegR", 0.085, trousers, boots)

	_upper = _pivot("Upper", _hips, Vector3(0.0, HIP_Y, 0.0))
	_part("Tunic", _upper, _cone(0.15, 0.21, 0.52), tunic, Vector3(0.0, 0.16, 0.0))
	_part("Shoulders", _upper, _ball(), tunic, Vector3(0.0, 0.39, 0.0), Vector3(0.34, 0.13, 0.21))
	_part("Sash", _upper, _cone(0.197, 0.202, 0.055), Look.mat(look.get("SASH", SASH)), Vector3(0.0, 0.05, 0.0))
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
