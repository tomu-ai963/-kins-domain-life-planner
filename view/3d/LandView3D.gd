extends Node3D

# ── 菜園の区画と池の 3D 表示(土の箱と水面の円盤) ────────────────────
# 状態とルールは logic/Land.gd(座標は m)。ここは読んで形を置くだけ
const Land = preload("res://logic/Land.gd")
const Look = preload("res://view/3d/Look.gd")

var land: Land
var _soil := Look.mat(Color(0.42, 0.28, 0.16))
var _furrow := Look.mat(Color(0.30, 0.20, 0.11))
var _water_deep := Look.mat(Color(0.22, 0.45, 0.72, 0.9))
var _water_light := Look.mat(Color(0.40, 0.66, 0.90, 0.6))
var _shore := Look.mat(Color(0.48, 0.40, 0.28))

func setup(l: Land) -> void:
	land = l
	land.changed.connect(_rebuild)
	_rebuild()

func _rebuild() -> void:
	Look.clear_children(self)
	var size: float = land.PLOT_SIZE - 0.2
	for c in land.plots:
		# 少し盛った土と、3 本の畝
		var bed := BoxMesh.new()
		bed.size = Vector3(size, 0.12, size)
		add_child(Look.mesh_node(bed, _soil, Look.at(c, 0.06)))
		for k in range(1, 4):
			var y: float = c.y - size * 0.5 + size * k / 4.0
			add_child(Look.strip(Vector2(c.x - size * 0.5 + 0.2, y), Vector2(c.x + size * 0.5 - 0.2, y), 0.14, 0.04, _furrow, 0.12))
	if land.pond != null:
		var r: float = land.POND_RADIUS
		add_child(_disc(land.pond, r + 0.3, 0.04, _shore, 0.0))       # 岸
		add_child(_disc(land.pond, r, 0.04, _water_deep, 0.02))        # 水面
		add_child(_disc(land.pond, r * 0.6, 0.04, _water_light, 0.04)) # 浅く見える真ん中

func _disc(c: Vector2, r: float, h: float, m: Material, y: float) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = h
	cyl.radial_segments = 48
	cyl.rings = 1
	var mi := Look.mesh_node(cyl, m, Look.at(c, y + h * 0.5))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
