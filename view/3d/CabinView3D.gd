extends Node3D

# ── 小屋の 3D 表示 ─────────────────────────────────────────
# 状態とルールは logic/Cabin.gd。ここは読んで形を置くだけ。
# 場所を決めた → 杭と縄 / 基礎 → 土台の角材と床 / 壁 → 作業のたびに高くなる / 屋根 → 垂木 → 屋根とドア。
# 壁が建ったら歩いて通り抜けられないように当たり判定を付ける。南(カメラの側)がドア。
# 苗づくりの鉢(logic/Seedlings.gd)は、見えるようにドアの東の棚に並べる
const Cabin = preload("res://logic/Cabin.gd")
const Seedlings = preload("res://logic/Seedlings.gd")
const Look = preload("res://view/3d/Look.gd")

const WALL_H := 2.2       # 壁の高さ(m)
const WALL_T := 0.2       # 壁の厚さ(m)
const FLOOR_Y := 0.25     # 床の高さ(m)
const DOOR_W := 0.9       # ドアの幅(m)
const DOOR_H := 1.9       # ドアの高さ(m)
const ROOF_H := 1.3       # 屋根の高さ(m)
const ROOF_OVER := 0.3    # 屋根のひさし(m)
const LAMP_ENERGY := 0.9 # 完成した小屋の軒の明かり
const WINDOW_GLOW := 1.6  # 夜の窓の明るさ

var cabin: Cabin
var _night := 0.0
var _lamp_light: OmniLight3D  # 完成するまでは null
var _lamp := Look.mat(Color(1.0, 0.78, 0.45))
var seedlings: Seedlings
var _box := BoxMesh.new()
var _ball := SphereMesh.new()
var _pot := Look.mat(Color(0.70, 0.36, 0.20))
var _sprout := Look.mat(Color(0.30, 0.68, 0.24))
var _stake := Look.mat(Color(0.75, 0.62, 0.42))
var _rope := Look.mat(Color(0.95, 0.90, 0.70), true)
var _sill := Look.mat(Color(0.36, 0.24, 0.14))
var _floor := Look.mat(Color(0.62, 0.46, 0.28))
var _wall := Look.mat(Color(0.56, 0.37, 0.20))
var _rafter := Look.mat(Color(0.70, 0.54, 0.34))
var _roof := Look.mat(Color(0.38, 0.28, 0.24))
var _door := Look.mat(Color(0.30, 0.18, 0.10))
var _window := Look.mat(Color(0.55, 0.78, 0.92))

func setup(c: Cabin, s: Seedlings = null) -> void:
	cabin = c
	seedlings = s
	cabin.changed.connect(_rebuild)
	if seedlings != null:
		seedlings.changed.connect(_rebuild)
		seedlings.forest.changed.connect(_rebuild)  # 日付が変わると苗が育つ
	_rebuild()

func _piece(parent: Node3D, m: Material, pos: Vector3, scl: Vector3) -> void:
	parent.add_child(Look.mesh_node(_box, m, pos, scl))

# 暗くなると、完成した小屋の窓と軒に明かりがともる(0 = 昼、1 = 夜)
func set_night(amount: float) -> void:
	_night = amount
	_apply_night()

func _apply_night() -> void:
	var lit := _night > 0.0 and cabin != null and cabin.is_complete()
	for m in [_window, _lamp]:
		m.emission_enabled = lit
		m.emission = Color(1.0, 0.72, 0.38)
	_window.emission_energy_multiplier = WINDOW_GLOW * _night
	_lamp.emission_energy_multiplier = 3.0 * _night
	if _lamp_light != null:
		_lamp_light.visible = lit
		_lamp_light.light_energy = LAMP_ENERGY * _night

func _rebuild() -> void:
	Look.clear_children(self)
	_lamp_light = null
	_rebuild_pieces()
	_apply_night()

func _rebuild_pieces() -> void:
	if cabin.site == null:
		return
	var spot := Node3D.new()
	spot.position = Look.at(cabin.site)
	add_child(spot)
	if cabin.stage == 0 and cabin.days_done == 0:
		_marks(spot)
		return
	_foundation(spot, cabin.stage >= 1)
	if cabin.stage == 1:
		if cabin.days_done > 0:
			_walls(spot, WALL_H * cabin.days_done / float(Cabin.STAGES[1].days))
	elif cabin.stage >= 2:
		_walls(spot, WALL_H)
		_details(spot)
		_collider(spot)
	if cabin.is_complete():
		_roof_full(spot)
		_porch_lamp(spot)
		_pots(spot)
	elif cabin.stage == 2 and cabin.days_done >= 1:
		_rafters(spot)

# 窓辺の鉢: ドアの東に棚を置き、鉢と芽を並べる。芽は育つと大きくなる
func _pots(spot: Node3D) -> void:
	if seedlings == null or seedlings.pots.is_empty():
		return
	var z: float = Cabin.DEPTH * 0.5 + WALL_T * 0.5 + 0.2
	_piece(spot, _sill, Vector3(1.2, 0.3, z), Vector3(1.4, 0.06, 0.35))
	for i in range(seedlings.pots.size()):
		var x: float = 0.65 + i * 0.22
		_piece(spot, _pot, Vector3(x, 0.4, z), Vector3(0.16, 0.16, 0.16))
		var s: float = lerpf(0.06, 0.26, seedlings.growth_ratio(seedlings.pots[i]))
		spot.add_child(Look.mesh_node(_ball, _sprout, Vector3(x, 0.48 + s * 0.5, z), Vector3(s, s, s)))

# 場所を決めただけ: 四隅の杭と縄
func _marks(spot: Node3D) -> void:
	var w: float = Cabin.WIDTH * 0.5
	var d: float = Cabin.DEPTH * 0.5
	for x in [-w, w]:
		for z in [-d, d]:
			_piece(spot, _stake, Vector3(x, 0.4, z), Vector3(0.1, 0.8, 0.1))
	for z in [-d, d]:
		_piece(spot, _rope, Vector3(0, 0.6, z), Vector3(Cabin.WIDTH, 0.03, 0.03))
	for x in [-w, w]:
		_piece(spot, _rope, Vector3(x, 0.6, 0), Vector3(0.03, 0.03, Cabin.DEPTH))

# 基礎: 1 日目は長い辺の土台だけ。できあがると四辺の土台と床
func _foundation(spot: Node3D, full: bool) -> void:
	var w: float = Cabin.WIDTH
	var d: float = Cabin.DEPTH
	for z in [-d * 0.5, d * 0.5]:
		_piece(spot, _sill, Vector3(0, FLOOR_Y * 0.5, z), Vector3(w + WALL_T, FLOOR_Y, WALL_T))
	if not full:
		return
	for x in [-w * 0.5, w * 0.5]:
		_piece(spot, _sill, Vector3(x, FLOOR_Y * 0.5, 0), Vector3(WALL_T, FLOOR_Y, d))
	_piece(spot, _floor, Vector3(0, FLOOR_Y - 0.02, 0), Vector3(w, 0.04, d))

# 壁: 高さ h まで。南の壁にはドアの開口を空ける
func _walls(spot: Node3D, h: float) -> void:
	var w: float = Cabin.WIDTH
	var d: float = Cabin.DEPTH
	var y: float = FLOOR_Y + h * 0.5
	_piece(spot, _wall, Vector3(0, y, -d * 0.5), Vector3(w + WALL_T, h, WALL_T))
	for x in [-w * 0.5, w * 0.5]:
		_piece(spot, _wall, Vector3(x, y, 0), Vector3(WALL_T, h, d))
	# ドアの両脇: 開口の端から、東西の壁の外側まで
	var side: float = (w + WALL_T - DOOR_W) * 0.5
	for sign_x in [-1.0, 1.0]:
		_piece(spot, _wall, Vector3(sign_x * (DOOR_W + side) * 0.5, y, d * 0.5), Vector3(side, h, WALL_T))
	if h > DOOR_H:
		_piece(spot, _wall, Vector3(0, FLOOR_Y + (DOOR_H + h) * 0.5, d * 0.5), Vector3(DOOR_W, h - DOOR_H, WALL_T))

# 壁ができたら: ドアと東西の窓
func _details(spot: Node3D) -> void:
	var w: float = Cabin.WIDTH
	var d: float = Cabin.DEPTH
	_piece(spot, _door, Vector3(0, FLOOR_Y + DOOR_H * 0.5, d * 0.5), Vector3(DOOR_W, DOOR_H, WALL_T * 0.6))
	for x in [-w * 0.5, w * 0.5]:
		_piece(spot, _window, Vector3(x, FLOOR_Y + 1.3, 0), Vector3(WALL_T + 0.04, 0.7, 0.9))

# 屋根の 1 日目: 棟木と 3 組の垂木
func _rafters(spot: Node3D) -> void:
	var half: float = Cabin.WIDTH * 0.5 + ROOF_OVER
	var depth: float = Cabin.DEPTH + ROOF_OVER * 2.0
	var top: float = FLOOR_Y + WALL_H
	var length: float = sqrt(half * half + ROOF_H * ROOF_H)
	var angle: float = atan2(ROOF_H, half)
	_piece(spot, _rafter, Vector3(0, top + ROOF_H, 0), Vector3(0.14, 0.14, depth))
	for z in [-depth * 0.5 + 0.1, 0.0, depth * 0.5 - 0.1]:
		for sign_x in [-1.0, 1.0]:
			var beam := Look.mesh_node(_box, _rafter, Vector3(sign_x * half * 0.5, top + ROOF_H * 0.5, z), Vector3(length, 0.12, 0.12))
			beam.rotation.z = -sign_x * angle
			spot.add_child(beam)

# 屋根のできあがり: 切妻(棟は南北)
func _roof_full(spot: Node3D) -> void:
	var prism := PrismMesh.new()
	prism.size = Vector3(Cabin.WIDTH + ROOF_OVER * 2.0, ROOF_H, Cabin.DEPTH + ROOF_OVER * 2.0)
	spot.add_child(Look.mesh_node(prism, _roof, Vector3(0, FLOOR_Y + WALL_H + ROOF_H * 0.5, 0)))

# ドアの上の軒の明かり。光は少し南に置いて、ドアの前を照らす
func _porch_lamp(spot: Node3D) -> void:
	var z: float = Cabin.DEPTH * 0.5 + WALL_T
	_piece(spot, _lamp, Vector3(0, FLOOR_Y + DOOR_H + 0.15, z), Vector3(0.2, 0.24, 0.16))
	_lamp_light = OmniLight3D.new()
	_lamp_light.position = Vector3(0, FLOOR_Y + DOOR_H, z + 0.8)
	_lamp_light.light_color = Color(1.0, 0.78, 0.5)
	_lamp_light.omni_range = 10.0
	spot.add_child(_lamp_light)

# 通り抜けられないように(作業は外からなので、ここで閉じ込められることはない)
func _collider(spot: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Collider"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(Cabin.WIDTH + WALL_T, WALL_H + FLOOR_Y, Cabin.DEPTH + WALL_T)
	shape.shape = box
	shape.position = Vector3(0, (WALL_H + FLOOR_Y) * 0.5, 0)
	body.add_child(shape)
	spot.add_child(body)
