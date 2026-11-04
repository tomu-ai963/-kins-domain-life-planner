extends Node3D

# ── 小屋の 3D 表示 ─────────────────────────────────────────
# 状態とルールは logic/Cabin.gd。ここは読んで形を置くだけ。
# 場所を決めた → 杭と縄 / 基礎 → 土台の角材と床 / 壁 → 作業のたびに高くなる / 屋根 → 垂木 → 屋根とドア。
# 壁が建ったら歩いて通り抜けられないように当たり判定を付ける。南(カメラの側)がドア
const Cabin = preload("res://logic/Cabin.gd")
const Look = preload("res://view/3d/Look.gd")

const WALL_H := 2.2       # 壁の高さ(m)
const WALL_T := 0.2       # 壁の厚さ(m)
const FLOOR_Y := 0.25     # 床の高さ(m)
const DOOR_W := 0.9       # ドアの幅(m)
const DOOR_H := 1.9       # ドアの高さ(m)
const ROOF_H := 1.3       # 屋根の高さ(m)
const ROOF_OVER := 0.3    # 屋根のひさし(m)

var cabin: Cabin
var _box := BoxMesh.new()
var _stake := Look.mat(Color(0.75, 0.62, 0.42))
var _rope := Look.mat(Color(0.95, 0.90, 0.70), true)
var _sill := Look.mat(Color(0.36, 0.24, 0.14))
var _floor := Look.mat(Color(0.62, 0.46, 0.28))
var _wall := Look.mat(Color(0.56, 0.37, 0.20))
var _rafter := Look.mat(Color(0.70, 0.54, 0.34))
var _roof := Look.mat(Color(0.38, 0.28, 0.24))
var _door := Look.mat(Color(0.30, 0.18, 0.10))
var _window := Look.mat(Color(0.55, 0.78, 0.92))

func setup(c: Cabin) -> void:
	cabin = c
	cabin.changed.connect(_rebuild)
	_rebuild()

func _piece(parent: Node3D, m: Material, pos: Vector3, scl: Vector3) -> void:
	parent.add_child(Look.mesh_node(_box, m, pos, scl))

func _rebuild() -> void:
	Look.clear_children(self)
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
	elif cabin.stage == 2 and cabin.days_done >= 1:
		_rafters(spot)

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
