extends Node3D

# ── 地面の 3D 表示(草地・10m グリッド・メルカバ・境界) ────────────────
# 1 unit = 1m。ドメイン中心が原点で、±50m が境界。季節は logic/Forest.gd から読む
const Forest = preload("res://logic/Forest.gd")
const Look = preload("res://view/3d/Look.gd")

const HALF := 50.0
const GRID := 10.0
const MERKABA_RADIUS := 15.0

# 季節ごとの地面パレット(2D と同じ色)
const GROUND := {
	"spring": {"dirt": Color(0.40, 0.30, 0.20), "grass": Color(0.62, 0.82, 0.42), "grid": Color(0.50, 0.70, 0.32)},
	"summer": {"dirt": Color(0.38, 0.28, 0.18), "grass": Color(0.56, 0.77, 0.34), "grid": Color(0.44, 0.65, 0.27)},
	"autumn": {"dirt": Color(0.36, 0.26, 0.16), "grass": Color(0.74, 0.66, 0.32), "grid": Color(0.62, 0.55, 0.26)},
	"winter": {"dirt": Color(0.35, 0.32, 0.30), "grass": Color(0.88, 0.90, 0.92), "grid": Color(0.78, 0.81, 0.85)},
}

var forest: Forest
var _season := ""
var _dirt_mat := Look.mat(Color.BLACK)
var _grass_mat := Look.mat(Color.BLACK)
var _grid_mat := Look.mat(Color.BLACK)

func setup(f: Forest) -> void:
	forest = f
	forest.changed.connect(_on_changed)
	_build()
	_on_changed()

# 季節が変わったときだけ色を差し替える(形は作り直さない)
func _on_changed() -> void:
	if forest.season == _season:
		return
	_season = forest.season
	var pal: Dictionary = GROUND[_season]
	_dirt_mat.albedo_color = pal.dirt
	_grass_mat.albedo_color = pal.grass
	_grid_mat.albedo_color = pal.grid

func _build() -> void:
	# ドメイン外(土の色)。少し下げて草地とちらつかないようにする
	var dirt := PlaneMesh.new()
	dirt.size = Vector2(400, 400)
	add_child(Look.mesh_node(dirt, _dirt_mat, Vector3(0, -0.02, 0)))

	# 1 ヘクタールの草原(冬は雪原)
	var grass := PlaneMesh.new()
	grass.size = Vector2(HALF * 2, HALF * 2)
	add_child(Look.mesh_node(grass, _grass_mat))

	# 10m グリッド(地面すれすれの細い帯)
	for i in range(-4, 5):
		var p := i * GRID
		add_child(Look.strip(Vector2(p, -HALF), Vector2(p, HALF), 0.08, 0.01, _grid_mat))
		add_child(Look.strip(Vector2(-HALF, p), Vector2(HALF, p), 0.08, 0.01, _grid_mat))

	# メルカバ(二つの正三角形 / 六芒星)。土地のエネルギー軸を示す黄金色のガイド
	var gold := Look.mat(Color(1.0, 0.82, 0.18, 0.55), true)
	for k in range(2):
		var pts := []
		for j in range(3):
			# k=0: 頂点が上(-y)の △ / k=1: 頂点が下の ▽
			var a := -PI / 2 + j * TAU / 3 + k * PI
			pts.append(Vector2(cos(a), sin(a)) * MERKABA_RADIUS)
		for j in range(3):
			add_child(Look.strip(pts[j], pts[(j + 1) % 3], 0.15, 0.01, gold, 0.01))

	# ドメイン境界(深い緑の縁)
	var edge := Look.mat(Color(0.18, 0.44, 0.14))
	var c := [Vector2(-HALF, -HALF), Vector2(HALF, -HALF), Vector2(HALF, HALF), Vector2(-HALF, HALF)]
	for i in range(4):
		add_child(Look.strip(c[i], c[(i + 1) % 4], 0.3, 0.03, edge))

	# 原点の目印
	var dot := CylinderMesh.new()
	dot.top_radius = 0.18
	dot.bottom_radius = 0.18
	dot.height = 0.06
	add_child(Look.mesh_node(dot, Look.mat(Color(0.92, 0.18, 0.1)), Vector3(0, 0.03, 0)))
