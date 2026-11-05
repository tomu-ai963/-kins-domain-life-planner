extends Node3D

# ── 小屋の 3D 表示 ─────────────────────────────────────────
# 状態とルールは logic/Cabin.gd。ここは読んで形を置くだけ。
# 場所を決めた → 杭と縄 / 基礎 → 土台の角材と床 / 壁 → 作業のたびに高くなる / 屋根 → 垂木 → 屋根とドア。
# 壁が建ったら歩いて通り抜けられないように当たり判定を付ける。南(カメラの側)がドアで、完成すると開いて入れる。
# 中にいるあいだは屋根と南の壁を見せず(影だけ落とす)、部屋の明かりをつける。
# 苗づくりの鉢(logic/Seedlings.gd)は、東の窓辺の棚に並べる
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
const ROOM_LIGHT_ENERGY := 1.1
const DOOR_OPEN_NEAR := 2.2       # ドアからこの距離まで来ると開く(m)
const DOOR_OPEN_ANGLE := -1.8     # 開いたときの角度(南へ外開き)
const DOOR_SPEED := 4.0           # 開け閉めの速さ

var cabin: Cabin
var _night := 0.0
var _lamp_light: OmniLight3D  # 完成するまでは null
var _player: Node3D           # 3D のときだけ Main が渡す
var _inside := false
var _door_hinge: Node3D
var _cut_pieces := []         # 中にいるあいだは見せない形(屋根・南の壁など)
var _inside_pieces := []      # 中にいるあいだだけ見せる形(南の壁の腰の高さまで・部屋の明かり)
var _bed := Look.mat(Color(0.92, 0.88, 0.78))
var _blanket := Look.mat(Color(0.72, 0.30, 0.24))
var _stove := Look.mat(Color(0.22, 0.22, 0.24))
var _rug := Look.mat(Color(0.60, 0.38, 0.30))
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

func _piece(parent: Node3D, m: Material, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	var mi := Look.mesh_node(_box, m, pos, scl)
	parent.add_child(mi)
	return mi

func set_player(p: Node3D) -> void:
	_player = p

func _process(delta: float) -> void:
	if _player == null or cabin == null or cabin.site == null:
		return
	var pos: Vector2 = _player.ground_pos()
	var inside: bool = cabin.is_inside(pos)
	if inside != _inside:
		_inside = inside
		_player.set_indoors(inside, FLOOR_Y)
		_apply_inside()
	if _door_hinge != null and cabin.is_complete():
		var near: bool = pos.distance_to(cabin.door_pos()) < DOOR_OPEN_NEAR
		var goal: float = DOOR_OPEN_ANGLE if near else 0.0
		_door_hinge.rotation.y = move_toward(_door_hinge.rotation.y, goal, DOOR_SPEED * delta)

# 中にいるあいだは、屋根と南の壁を影だけにして部屋を見せる
func _apply_inside() -> void:
	var cast := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if _inside else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for n in _cut_pieces:
		n.cast_shadow = cast
	for n in _inside_pieces:
		n.visible = _inside

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
	_door_hinge = null
	_cut_pieces.clear()
	_inside_pieces.clear()
	_rebuild_pieces()
	_apply_night()
	_apply_inside()

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
		_interior(spot)
		_pots(spot)
	elif cabin.stage == 2 and cabin.days_done >= 1:
		_rafters(spot)

# 窓辺の鉢: 東の窓の下に棚を置き、鉢と芽を並べる。芽は育つと大きくなる
func _pots(spot: Node3D) -> void:
	if seedlings == null or seedlings.pots.is_empty():
		return
	var x: float = Cabin.WIDTH * 0.5 - 0.3
	var y: float = FLOOR_Y + 0.8
	_piece(spot, _sill, Vector3(x, y, 0.2), Vector3(0.38, 0.06, 1.5))
	for i in range(seedlings.pots.size()):
		var z: float = -0.35 + i * 0.22
		_piece(spot, _pot, Vector3(x, y + 0.1, z), Vector3(0.16, 0.16, 0.16))
		var s: float = lerpf(0.06, 0.26, seedlings.growth_ratio(seedlings.pots[i]))
		spot.add_child(Look.mesh_node(_ball, _sprout, Vector3(x, y + 0.18 + s * 0.5, z), Vector3(s, s, s)))

# 部屋の中: ベッド(北西)・ストーブ(北東)・テーブルと腰掛け(南西)・敷物・明かり。
# まとめて 1 つの Node3D に入れる
func _interior(spot: Node3D) -> void:
	var room := Node3D.new()
	room.name = "Interior"
	room.position = Vector3(0, FLOOR_Y, 0)
	spot.add_child(room)
	# ベッド: 枠・敷布団・掛け布団・枕
	_piece(room, _sill, Vector3(-0.9, 0.15, -0.95), Vector3(1.9, 0.3, 0.85))
	_piece(room, _bed, Vector3(-0.9, 0.34, -0.95), Vector3(1.8, 0.1, 0.75))
	_piece(room, _blanket, Vector3(-0.6, 0.41, -0.95), Vector3(1.2, 0.06, 0.78))
	_piece(room, _bed, Vector3(-1.55, 0.43, -0.95), Vector3(0.35, 0.1, 0.5))
	# ストーブと煙突
	_piece(room, _stove, Vector3(1.45, 0.42, -1.0), Vector3(0.7, 0.85, 0.7))
	_piece(room, _stove, Vector3(1.45, 1.5, -1.0), Vector3(0.14, 1.4, 0.14))
	# テーブル(天板と脚 4 本)と腰掛け
	_piece(room, _rafter, Vector3(-1.2, 0.72, 0.75), Vector3(0.95, 0.05, 0.7))
	for x in [-1.6, -0.8]:
		for z in [0.47, 1.03]:
			_piece(room, _sill, Vector3(x, 0.35, z), Vector3(0.06, 0.7, 0.06))
	_piece(room, _sill, Vector3(-0.45, 0.22, 0.75), Vector3(0.3, 0.45, 0.3))
	# 敷物(ドアを入ったところ)
	room.add_child(Look.strip(Vector2(-0.2, 0.2), Vector2(0.2, 0.2), 1.0, 0.01, _rug))
	# 部屋の明かり(中にいるあいだだけ)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.9, 0)
	light.light_color = Color(1.0, 0.82, 0.6)
	light.light_energy = ROOM_LIGHT_ENERGY
	light.omni_range = 5.5
	light.shadow_enabled = true  # 壁を突き抜けて外の地面を照らさないように
	room.add_child(light)
	_inside_pieces.append(light)
	# 南の壁の腰の高さまで(中にいるあいだ、壁の代わりに見せる)
	var w: float = Cabin.WIDTH
	var d: float = Cabin.DEPTH
	var side: float = (w + WALL_T - DOOR_W) * 0.5
	for sign_x in [-1.0, 1.0]:
		_inside_pieces.append(_piece(room, _wall, Vector3(sign_x * (DOOR_W + side) * 0.5, 0.2, d * 0.5), Vector3(side, 0.4, WALL_T)))

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
		_cut_pieces.append(_piece(spot, _wall, Vector3(sign_x * (DOOR_W + side) * 0.5, y, d * 0.5), Vector3(side, h, WALL_T)))
	if h > DOOR_H:
		_cut_pieces.append(_piece(spot, _wall, Vector3(0, FLOOR_Y + (DOOR_H + h) * 0.5, d * 0.5), Vector3(DOOR_W, h - DOOR_H, WALL_T)))

# 壁ができたら: ドアと東西の窓
func _details(spot: Node3D) -> void:
	var w: float = Cabin.WIDTH
	var d: float = Cabin.DEPTH
	# ドアは西の端を軸に回す。形は軸の Node3D の子にする
	_door_hinge = Node3D.new()
	_door_hinge.position = Vector3(-DOOR_W * 0.5, FLOOR_Y, d * 0.5)
	spot.add_child(_door_hinge)
	_cut_pieces.append(_piece(_door_hinge, _door, Vector3(DOOR_W * 0.5, DOOR_H * 0.5, 0), Vector3(DOOR_W, DOOR_H, WALL_T * 0.6)))
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
	var roof := Look.mesh_node(prism, _roof, Vector3(0, FLOOR_Y + WALL_H + ROOF_H * 0.5, 0))
	spot.add_child(roof)
	_cut_pieces.append(roof)

# ドアの上の軒の明かり。光は少し南に置いて、ドアの前を照らす
func _porch_lamp(spot: Node3D) -> void:
	var z: float = Cabin.DEPTH * 0.5 + WALL_T
	_cut_pieces.append(_piece(spot, _lamp, Vector3(0, FLOOR_Y + DOOR_H + 0.15, z), Vector3(0.2, 0.24, 0.16)))
	_lamp_light = OmniLight3D.new()
	_lamp_light.position = Vector3(0, FLOOR_Y + DOOR_H, z + 0.8)
	_lamp_light.light_color = Color(1.0, 0.78, 0.5)
	_lamp_light.omni_range = 10.0
	spot.add_child(_lamp_light)

# 通り抜けられないように。建てているあいだは全体を塞ぐ(作業は外からなので、閉じ込められることはない)。
# 完成したら壁ごとの判定にして、南のドアのところを空ける
func _collider(spot: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Collider"
	var w: float = Cabin.WIDTH
	var d: float = Cabin.DEPTH
	if not cabin.is_complete():
		_collider_box(body, Vector3.ZERO, Vector2(w + WALL_T, d + WALL_T))
	else:
		_collider_box(body, Vector3(0, 0, -d * 0.5), Vector2(w + WALL_T, WALL_T))
		for x in [-w * 0.5, w * 0.5]:
			_collider_box(body, Vector3(x, 0, 0), Vector2(WALL_T, d))
		var side: float = (w + WALL_T - DOOR_W) * 0.5
		for sign_x in [-1.0, 1.0]:
			_collider_box(body, Vector3(sign_x * (DOOR_W + side) * 0.5, 0, d * 0.5), Vector2(side, WALL_T))
	spot.add_child(body)

# 床から壁の上までの箱の判定。size は 東西 × 南北(m)
func _collider_box(body: StaticBody3D, pos: Vector3, size: Vector2) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var h: float = WALL_H + FLOOR_Y
	box.size = Vector3(size.x, h, size.y)
	shape.shape = box
	shape.position = pos + Vector3(0, h * 0.5, 0)
	body.add_child(shape)
