extends Node3D

# ムクドリの巣箱の見た目。作っているあいだは木の根元に板と箱、掛け終えると幹(カメラの側 = 南)に掛かる。
# 木の大きさは TreesView3D と同じ決め方(KINDS の幹の高さ × 樹冠の半径)で合わせる
const NestBoxes = preload("res://logic/NestBoxes.gd")
const Forest = preload("res://logic/Forest.gd")
const Look = preload("res://view/3d/Look.gd")
const TreesView = preload("res://view/3d/TreesView3D.gd")

const BOX := Vector3(0.24, 0.34, 0.24)  # 箱の幅・高さ・奥行き(m)
const HANG_RATIO := 0.75   # 幹の高さのどこに掛けるか
const HANG_MIN := 1.3      # 掛ける高さの下限・上限(m)
const HANG_MAX := 2.4

var nest_boxes: NestBoxes
var forest: Forest
var _box := BoxMesh.new()
var _ball := SphereMesh.new()
var _wood := Look.mat(Color(0.62, 0.46, 0.28))
var _roof := Look.mat(Color(0.42, 0.30, 0.18))
var _hole := Look.mat(Color(0.08, 0.06, 0.05))

func setup(nb: NestBoxes, f: Forest) -> void:
	nest_boxes = nb
	forest = f
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 10
	_ball.rings = 5
	nest_boxes.changed.connect(_rebuild)
	forest.changed.connect(_rebuild)  # 木が育つ・伐られる
	_rebuild()

func _rebuild() -> void:
	Look.clear_children(self)
	for b in nest_boxes.boxes:
		var tree := _tree_at(b.pos)
		if tree.is_empty():
			continue  # 伐られた木(次の作業で巣箱の記録からも消える)
		var spot := Node3D.new()
		spot.name = "NestBox"
		add_child(spot, true)
		if nest_boxes.is_done(b):
			_hung(spot, tree)
		else:
			_building(spot, b)

func _tree_at(pos: Vector2) -> Dictionary:
	for t in forest.trees:
		if t.pos.distance_to(pos) < NestBoxes.SAME_SPOT:
			return t
	return {}

# 幹の高さと太さ(TreesView3D._layout と同じ)
func _trunk(tree: Dictionary) -> Vector2:
	var k: Dictionary = TreesView.KINDS[tree.species]
	var r: float = forest.radius_of(tree)
	return Vector2(float(k.trunk_h) * r, float(k.trunk_w) * r + 0.04)

# 掛け終えた巣箱: 幹の南側に、屋根と丸い穴と止まり木
func _hung(spot: Node3D, tree: Dictionary) -> void:
	var trunk := _trunk(tree)
	var h: float = clampf(trunk.x * HANG_RATIO, HANG_MIN, HANG_MAX)
	spot.position = Look.at(tree.pos + Vector2(0, trunk.y * 0.5 + BOX.z * 0.5), h)
	_box_parts(spot, 1.0, true)

# 作っているあいだ: 根元に置いた箱が、日ごとに組み上がる
func _building(spot: Node3D, b: Dictionary) -> void:
	spot.position = Look.at(b.pos + Vector2(0.45, 0.45), BOX.y * 0.5)
	var ratio: float = float(b.days_done) / NestBoxes.WORK_DAYS
	_box_parts(spot, ratio, false)
	# 残りの板
	for i in range(NestBoxes.WORK_DAYS - int(b.days_done)):
		spot.add_child(Look.mesh_node(_box, _wood, Vector3(0.3, -BOX.y * 0.5 + 0.02 + i * 0.03, 0), Vector3(0.28, 0.02, 0.1)))

func _box_parts(spot: Node3D, ratio: float, roofed: bool) -> void:
	var height: float = BOX.y * maxf(ratio, 0.34)
	spot.add_child(Look.mesh_node(_box, _wood, Vector3(0, -BOX.y * 0.5 + height * 0.5, 0), Vector3(BOX.x, height, BOX.z)))
	if not roofed:
		return
	spot.add_child(Look.mesh_node(_box, _roof, Vector3(0, BOX.y * 0.5 + 0.02, 0.03), Vector3(BOX.x + 0.08, 0.04, BOX.z + 0.1)))
	var front: float = BOX.z * 0.5 + 0.005
	spot.add_child(Look.mesh_node(_ball, _hole, Vector3(0, 0.06, front), Vector3(0.09, 0.09, 0.02)))
	spot.add_child(Look.mesh_node(_box, _roof, Vector3(0, -0.04, front + 0.05), Vector3(0.025, 0.025, 0.1)))
