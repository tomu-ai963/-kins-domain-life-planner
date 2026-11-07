extends Node3D

# ── 鳥の餌台の 3D 表示 ───────────────────────────────────────────
# 状態とルールは logic/Feeders.gd。柱の上に縁のある台。餌があるあいだは台の上に種が見える。
# 見下ろしのカメラから鳥が見えるように、屋根は付けない。通り抜けられないように、当たり判定を付ける
const Feeders = preload("res://logic/Feeders.gd")
const Look = preload("res://view/3d/Look.gd")

const POST_R := 0.05
const TABLE_SIZE := 1.1
const TABLE_T := 0.05     # 台の厚み
const RIM_H := 0.05
const GRAINS := 10        # 見せる種の数
const CHECK_SECONDS := 2.0  # 日付が変わって餌がなくなったのを見直す間隔

var feeders: Feeders
var _cylinder := CylinderMesh.new()
var _ball := SphereMesh.new()
var _box := BoxMesh.new()
var _wood := Look.mat(Color(0.56, 0.40, 0.24))
var _table := Look.mat(Color(0.72, 0.56, 0.36))
var _grain := Look.mat(Color(0.93, 0.80, 0.42))
var _timer := 0.0
var _shown_fed := -1

func setup(f: Feeders) -> void:
	feeders = f
	_cylinder.top_radius = 0.5
	_cylinder.bottom_radius = 0.5
	_cylinder.height = 1.0
	_cylinder.radial_segments = 10
	_cylinder.rings = 1
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 6
	_ball.rings = 3
	feeders.changed.connect(_rebuild)
	_rebuild()

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= CHECK_SECONDS:
		_timer = 0.0
		if feeders.fed_count() != _shown_fed:
			_rebuild()

func _rebuild() -> void:
	Look.clear_children(self)
	_shown_fed = feeders.fed_count()
	for f in feeders.feeders:
		var spot := Node3D.new()
		spot.name = "Feeder"
		spot.position = Look.at(f.pos)
		add_child(spot, true)
		_feeder(spot, f)
		_collider(spot)

func _feeder(spot: Node3D, f: Dictionary) -> void:
	var top: float = Feeders.TABLE_H
	var table_y: float = top - TABLE_T * 0.5
	spot.add_child(Look.mesh_node(_cylinder, _wood, Vector3(0, table_y * 0.5, 0), Vector3(POST_R * 2.0, table_y, POST_R * 2.0)))
	spot.add_child(Look.mesh_node(_box, _table, Vector3(0, table_y, 0), Vector3(TABLE_SIZE, TABLE_T, TABLE_SIZE)))
	var edge: float = TABLE_SIZE * 0.5
	for side in [-1.0, 1.0]:
		spot.add_child(Look.mesh_node(_box, _wood, Vector3(side * edge, top + RIM_H * 0.5, 0), Vector3(0.04, RIM_H, TABLE_SIZE)))
		spot.add_child(Look.mesh_node(_box, _wood, Vector3(0, top + RIM_H * 0.5, side * edge), Vector3(TABLE_SIZE, RIM_H, 0.04)))
	if not feeders.is_fed(f):
		return
	# 種の並びは場所で決める(作り直しても同じ)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(f.pos)
	for _i in range(GRAINS):
		var p := Vector3(rng.randf_range(-0.4, 0.4), top + 0.02, rng.randf_range(-0.4, 0.4))
		var grain := Look.mesh_node(_ball, _grain, p, Vector3(0.07, 0.04, 0.05))
		grain.name = "FeederGrain"
		grain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spot.add_child(grain, true)

func _collider(spot: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "FeederBody"
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = POST_R + 0.15
	cyl.height = Feeders.TABLE_H
	shape.shape = cyl
	shape.position = Vector3(0, Feeders.TABLE_H * 0.5, 0)
	body.add_child(shape)
	spot.add_child(body)
