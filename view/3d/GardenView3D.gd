extends Node3D

# ── 畑の野菜の 3D 表示 ───────────────────────────────────────
# 状態とルールは logic/Garden.gd。区画(LandView3D の土の箱)の上に、畝に沿って 3 列 × 4 株を並べる。
# 葉は育ち具合で大きくなり、収穫できる野菜には実を付ける。今日水をあげた区画は土が濡れて暗くなる
const Garden = preload("res://logic/Garden.gd")
const Look = preload("res://view/3d/Look.gd")

const ROWS := 3     # LandView3D の畝と同じ本数
const COLUMNS := 4
const BED_TOP := 0.12  # LandView3D の土の箱の上面
const MIN_SCALE := 0.2 # まいたばかりの芽の大きさ(育ちきった葉に対する割合)
const SPOILED := Color(0.36, 0.26, 0.14)  # 傷んだ実の色

# size: 育ちきった葉の幅・高さ・奥行き(m) / ball: 丸い葉(false なら細長い円錐)
# ripe / ripe_size: 収穫できるときに見える実の色と大きさ
const LOOKS := {
	"tomato": {"leaf": Color(0.26, 0.52, 0.20), "size": Vector3(0.45, 0.80, 0.45), "ball": false, "ripe": Color(0.88, 0.14, 0.10), "ripe_size": Vector3(0.20, 0.20, 0.20)},
	"radish": {"leaf": Color(0.35, 0.62, 0.25), "size": Vector3(0.35, 0.22, 0.35), "ball": true, "ripe": Color(0.85, 0.15, 0.32), "ripe_size": Vector3(0.20, 0.16, 0.20)},
	"carrot": {"leaf": Color(0.30, 0.60, 0.22), "size": Vector3(0.25, 0.45, 0.25), "ball": false, "ripe": Color(0.95, 0.50, 0.10), "ripe_size": Vector3(0.14, 0.20, 0.14)},
	"cucumber": {"leaf": Color(0.22, 0.50, 0.20), "size": Vector3(0.50, 0.60, 0.50), "ball": true, "ripe": Color(0.62, 0.82, 0.28), "ripe_size": Vector3(0.12, 0.30, 0.12)},
	"potato": {"leaf": Color(0.28, 0.52, 0.22), "size": Vector3(0.55, 0.45, 0.55), "ball": true, "ripe": Color(0.76, 0.62, 0.38), "ripe_size": Vector3(0.22, 0.16, 0.18)},
	"garlic": {"leaf": Color(0.45, 0.68, 0.35), "size": Vector3(0.12, 0.60, 0.12), "ball": false, "ripe": Color(0.95, 0.92, 0.84), "ripe_size": Vector3(0.20, 0.18, 0.20)},
}

var garden: Garden
var _ball := SphereMesh.new()
var _cone := CylinderMesh.new()
var _wet_mesh := BoxMesh.new()
var _wet_mat := Look.mat(Color(0.14, 0.09, 0.06, 0.55))
var _mats := {}

func setup(g: Garden) -> void:
	garden = g
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 8
	_ball.rings = 4
	_cone.top_radius = 0.0
	_cone.bottom_radius = 0.5
	_cone.height = 1.0
	_cone.radial_segments = 6
	_cone.rings = 1
	var size: float = garden.land.PLOT_SIZE - 0.3
	_wet_mesh.size = Vector3(size, 0.01, size)
	garden.changed.connect(_rebuild)
	garden.forest.changed.connect(_rebuild)  # 先送りプレビュー・日付の変化
	_rebuild()

func _mat(c: Color) -> Material:
	if not _mats.has(c):
		_mats[c] = Look.mat(c)
	return _mats[c]

func _rebuild() -> void:
	Look.clear_children(self)
	var plot: float = garden.land.PLOT_SIZE - 0.2
	for c in garden.crops:
		var look: Dictionary = LOOKS[c.kind]
		var ratio: float = garden.growth_ratio(c)
		var leaf: Vector3 = look.size * lerpf(MIN_SCALE, 1.0, ratio)
		var mesh: Mesh = _ball if look.ball else _cone
		var fruit: Color = SPOILED if garden.is_spoiled(c) else look.ripe
		if garden.watered_today(c):
			var wet := Look.mesh_node(_wet_mesh, _wet_mat, Look.at(c.pos, BED_TOP + 0.005))
			wet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(wet)
		for r in range(ROWS):
			for k in range(COLUMNS):
				var p := Vector2(
					c.pos.x - plot * 0.5 + plot * (k + 0.5) / COLUMNS,
					c.pos.y - plot * 0.5 + plot * (r + 1.0) / (ROWS + 1.0))
				add_child(Look.mesh_node(mesh, _mat(look.leaf), Look.at(p, BED_TOP + leaf.y * 0.5), leaf))
				if ratio >= 1.0:
					# 引いたカメラからも分かるように、実は葉の上に見せる
					add_child(Look.mesh_node(_ball, _mat(fruit), Look.at(p, BED_TOP + leaf.y), look.ripe_size))
