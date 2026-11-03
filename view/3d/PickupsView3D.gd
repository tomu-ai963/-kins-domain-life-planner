extends Node3D

# ── 地面に落ちている種の 3D 表示 ─────────────────────────────────
# 状態は logic/Forest.gd の pickups。近づくと拾える(Main)。
# 引いたカメラからも見つけられるよう、上に小さな光の目印を浮かべてゆっくり上下させる
const Forest = preload("res://logic/Forest.gd")
const Look = preload("res://view/3d/Look.gd")

const COLORS := {"birch": Color(0.80, 0.70, 0.45), "cedar": Color(0.42, 0.26, 0.12)}

var forest: Forest
var _markers := []
var _t := 0.0
var _seed_mesh := SphereMesh.new()
var _marker_mesh := SphereMesh.new()
var _marker_mat := Look.mat(Color(1.0, 0.55, 0.12), true, 1.5)  # 淡い地面でも目立つ橙
var _ring_mat := Look.mat(Color(1.0, 0.55, 0.12, 0.9), true)  # 生垣の白い印と見分けられる橙
var _mats := {}

func setup(f: Forest) -> void:
	forest = f
	_seed_mesh.radius = 0.5
	_seed_mesh.height = 1.0
	_seed_mesh.radial_segments = 8
	_seed_mesh.rings = 4
	_marker_mesh.radius = 0.5
	_marker_mesh.height = 1.0
	_marker_mesh.radial_segments = 4  # ひし形に見える低い分割
	_marker_mesh.rings = 2
	forest.changed.connect(_rebuild)
	_rebuild()

func _process(delta: float) -> void:
	_t += delta
	for i in range(_markers.size()):
		var m: Node3D = _markers[i]
		m.position.y = 1.4 + 0.2 * sin(_t * 2.0 + i)
		m.rotation.y = _t * 1.5

func _rebuild() -> void:
	Look.clear_children(self)
	_markers.clear()
	for p in forest.pickups:
		var sp: String = p.species
		if not _mats.has(sp):
			_mats[sp] = Look.mat(COLORS.get(sp, Color.WHITE))
		var spot := Node3D.new()
		spot.position = Look.at(p.pos)
		# 種のかたまり(白樺は平たい粒、杉は松ぼっくり形)
		var scl := Vector3(0.5, 0.1, 0.5) if sp == "birch" else Vector3(0.25, 0.35, 0.25)
		spot.add_child(Look.mesh_node(_seed_mesh, _mats[sp], Vector3(0, scl.y * 0.5, 0), scl))
		spot.add_child(Look.ring(Vector2.ZERO, 0.55, 0.1, _ring_mat))  # 拾える範囲の目安になる輪
		var marker := Look.mesh_node(_marker_mesh, _marker_mat, Vector3(0, 1.4, 0), Vector3(0.55, 0.85, 0.55))
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spot.add_child(marker)
		_markers.append(marker)
		add_child(spot)
