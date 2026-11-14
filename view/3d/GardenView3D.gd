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
	# ── 県を選ぶようにして足した野菜(2026-11-11) ──
	"daikon": {"leaf": Color(0.32, 0.60, 0.24), "size": Vector3(0.42, 0.35, 0.42), "ball": true, "ripe": Color(0.96, 0.96, 0.92), "ripe_size": Vector3(0.14, 0.30, 0.14)},
	"kabu": {"leaf": Color(0.36, 0.62, 0.26), "size": Vector3(0.32, 0.25, 0.32), "ball": true, "ripe": Color(0.97, 0.97, 0.94), "ripe_size": Vector3(0.20, 0.17, 0.20)},
	"sweet_potato": {"leaf": Color(0.24, 0.50, 0.22), "size": Vector3(0.62, 0.22, 0.62), "ball": true, "ripe": Color(0.62, 0.22, 0.36), "ripe_size": Vector3(0.24, 0.14, 0.16)},  # 地をはうつる
	"taro": {"leaf": Color(0.28, 0.56, 0.30), "size": Vector3(0.55, 0.65, 0.55), "ball": true, "ripe": Color(0.50, 0.40, 0.30), "ripe_size": Vector3(0.18, 0.18, 0.18)},  # 大きな葉
	"eggplant": {"leaf": Color(0.24, 0.46, 0.22), "size": Vector3(0.45, 0.70, 0.45), "ball": false, "ripe": Color(0.30, 0.12, 0.36), "ripe_size": Vector3(0.12, 0.24, 0.12)},
	"pepper": {"leaf": Color(0.26, 0.52, 0.20), "size": Vector3(0.40, 0.55, 0.40), "ball": false, "ripe": Color(0.18, 0.56, 0.14), "ripe_size": Vector3(0.14, 0.16, 0.14)},
	"pumpkin": {"leaf": Color(0.28, 0.54, 0.22), "size": Vector3(0.68, 0.32, 0.68), "ball": true, "ripe": Color(0.26, 0.40, 0.22), "ripe_size": Vector3(0.32, 0.24, 0.32)},
	"goya": {"leaf": Color(0.24, 0.54, 0.22), "size": Vector3(0.45, 0.85, 0.45), "ball": false, "ripe": Color(0.42, 0.72, 0.26), "ripe_size": Vector3(0.10, 0.30, 0.10)},  # 棚に絡むつる
	"cabbage": {"leaf": Color(0.56, 0.74, 0.42), "size": Vector3(0.45, 0.30, 0.45), "ball": true, "ripe": Color(0.74, 0.88, 0.58), "ripe_size": Vector3(0.30, 0.24, 0.30)},
	"hakusai": {"leaf": Color(0.48, 0.70, 0.36), "size": Vector3(0.40, 0.45, 0.40), "ball": true, "ripe": Color(0.90, 0.94, 0.76), "ripe_size": Vector3(0.24, 0.34, 0.24)},
	"spinach": {"leaf": Color(0.18, 0.48, 0.18), "size": Vector3(0.30, 0.20, 0.30), "ball": true, "ripe": Color(0.20, 0.52, 0.20), "ripe_size": Vector3(0.22, 0.10, 0.22)},
	"komatsuna": {"leaf": Color(0.22, 0.52, 0.22), "size": Vector3(0.28, 0.28, 0.28), "ball": true, "ripe": Color(0.28, 0.60, 0.24), "ripe_size": Vector3(0.18, 0.14, 0.18)},
	"edamame": {"leaf": Color(0.32, 0.56, 0.22), "size": Vector3(0.40, 0.55, 0.40), "ball": true, "ripe": Color(0.52, 0.72, 0.30), "ripe_size": Vector3(0.14, 0.08, 0.14)},
	"corn": {"leaf": Color(0.36, 0.62, 0.24), "size": Vector3(0.20, 1.30, 0.20), "ball": false, "ripe": Color(0.96, 0.84, 0.30), "ripe_size": Vector3(0.10, 0.24, 0.10)},  # 背が高い
	# 穀物(2026-11-14): 細い茎が立ち、実ると穂が色づく
	"wheat": {"leaf": Color(0.48, 0.66, 0.28), "size": Vector3(0.22, 0.85, 0.22), "ball": false, "ripe": Color(0.90, 0.74, 0.34), "ripe_size": Vector3(0.10, 0.22, 0.10)},  # 黄金色の穂
	"rye": {"leaf": Color(0.42, 0.60, 0.30), "size": Vector3(0.20, 1.15, 0.20), "ball": false, "ripe": Color(0.74, 0.66, 0.44), "ripe_size": Vector3(0.08, 0.26, 0.08)},  # 小麦より背が高く、穂は灰色がかる
	"soba": {"leaf": Color(0.40, 0.62, 0.30), "size": Vector3(0.45, 0.65, 0.45), "ball": true, "ripe": Color(0.94, 0.92, 0.90), "ripe_size": Vector3(0.24, 0.10, 0.24)},  # 白い花の上に実がつく
	"kibi": {"leaf": Color(0.44, 0.64, 0.26), "size": Vector3(0.26, 1.0, 0.26), "ball": false, "ripe": Color(0.96, 0.86, 0.36), "ripe_size": Vector3(0.14, 0.18, 0.14)},  # 垂れた黄色い穂
	"onion": {"leaf": Color(0.40, 0.64, 0.30), "size": Vector3(0.10, 0.50, 0.10), "ball": false, "ripe": Color(0.80, 0.58, 0.30), "ripe_size": Vector3(0.20, 0.18, 0.20)},
	"negi": {"leaf": Color(0.36, 0.62, 0.30), "size": Vector3(0.10, 0.70, 0.10), "ball": false, "ripe": Color(0.95, 0.95, 0.90), "ripe_size": Vector3(0.08, 0.14, 0.08)},
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
