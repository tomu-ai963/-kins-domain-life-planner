extends Node3D

# ── 菜園の区画の 3D 表示(土の箱) ────────────────────────────────
# 状態とルールは logic/Land.gd(座標は m)。ここは読んで形を置くだけ。野菜は GardenView3D、池は PondView3D
# 土の箱と畝は、どの区画も同じ形なので MultiMesh でまとめて 1 回で描く(区画ごとに 4 つの部品にしない。レビュー M1)
const Land = preload("res://logic/Land.gd")
const Look = preload("res://view/3d/Look.gd")

const FURROWS := 3  # 1 区画の畝の本数

var land: Land
var _soil := Look.mat(Color(0.42, 0.28, 0.16))
var _furrow := Look.mat(Color(0.30, 0.20, 0.11))
var _beds: MultiMeshInstance3D     # 少し盛った土の箱(区画ごとに 1 つ)
var _furrows: MultiMeshInstance3D  # 畝(区画ごとに 3 本)

func setup(l: Land) -> void:
	land = l
	var size: float = land.PLOT_SIZE - 0.2
	var bed := BoxMesh.new()
	bed.size = Vector3(size, 0.12, size)
	_beds = _part(bed, _soil)
	# 畝は地面に貼る平らな帯(Look.strip と同じ形。側面があると輪郭線が点線になって出る)
	var plane := PlaneMesh.new()
	plane.size = Vector2(size - 0.4 + 0.14, 0.14)
	plane.subdivide_width = int(plane.size.x / Look.STRIP_SEGMENT)
	_furrows = _part(plane, _furrow)
	land.changed.connect(_rebuild)
	_rebuild()

func _part(mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # 低い太陽だと、薄い箱の影の端がノコギリの歯のようになる
	node.layers = Look.GROUND_LAYER
	node.extra_cull_margin = Look.BEND_CULL_MARGIN
	add_child(node)
	return node

# 区画の土の箱と畝の数(テスト用)
func bed_count() -> int:
	return _beds.multimesh.instance_count

func furrow_count() -> int:
	return _furrows.multimesh.instance_count

func _rebuild() -> void:
	var size: float = land.PLOT_SIZE - 0.2
	var plots: Array = land.plots
	_beds.multimesh.instance_count = plots.size()
	_furrows.multimesh.instance_count = plots.size() * FURROWS
	for i in range(plots.size()):
		var c: Vector2 = plots[i]
		_beds.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Look.at(c, 0.06)))
		for k in range(1, FURROWS + 1):
			var y: float = c.y - size * 0.5 + size * k / float(FURROWS + 1)
			_furrows.multimesh.set_instance_transform(i * FURROWS + k - 1, Transform3D(Basis.IDENTITY, Look.at(Vector2(c.x, y), 0.16)))
