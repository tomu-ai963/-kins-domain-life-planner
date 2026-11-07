extends MultiMeshInstance3D

# ── 雪をどかした道の 3D 表示 ──────────────────────────────────────
# 状態とルールは logic/Snow.gd。どかしたマスに土の色の板を敷く。冬だけ見える。
# マスが増えるたびに並べ直す(マスの数は多くても数百なので、これで十分)
const Snow = preload("res://logic/Snow.gd")
const Look = preload("res://view/3d/Look.gd")

const SOIL := Color(0.50, 0.35, 0.21)  # 冬の青い光で灰色に寄るので、暖かめにしておく
const HEIGHT := 0.016     # 地面と 10m グリッド(0.01)のすぐ上

var snow: Snow

func setup(s: Snow) -> void:
	snow = s
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * Snow.CELL
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plane
	multimesh = mm
	material_override = Look.mat(SOIL)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = Look.BEND_CULL_MARGIN
	snow.changed.connect(_rebuild)
	snow.forest.changed.connect(_rebuild)
	_rebuild()

func shown_count() -> int:
	return multimesh.instance_count if visible else 0

func _rebuild() -> void:
	visible = snow.can_clear_now()
	var cells: Array = snow.cells.keys()
	if multimesh.instance_count != cells.size():
		multimesh.instance_count = cells.size()
	for i in range(cells.size()):
		var p: Vector2 = Snow.center_of(cells[i])
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(p.x, HEIGHT, p.y)))
