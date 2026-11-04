extends Node3D

# ── 菜園の区画の 3D 表示(土の箱) ────────────────────────────────
# 状態とルールは logic/Land.gd(座標は m)。ここは読んで形を置くだけ。野菜は GardenView3D、池は PondView3D
const Land = preload("res://logic/Land.gd")
const Look = preload("res://view/3d/Look.gd")

var land: Land
var _soil := Look.mat(Color(0.42, 0.28, 0.16))
var _furrow := Look.mat(Color(0.30, 0.20, 0.11))

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
