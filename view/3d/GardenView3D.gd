extends Node3D

# ── 畑の野菜の 3D 表示 ───────────────────────────────────────
# 状態とルールは logic/Garden.gd。区画(LandView3D の土の箱)の上に、畝に沿って 3 列 × 4 株を並べる。
# 葉は育ち具合で大きくなり、収穫できる野菜には実を付ける。今日水をあげた区画は土が濡れて暗くなる。
# 雑草が生えた区画は、株のあいだに草が増える(生えて長いほど多い)。わらを敷いた区画は、土の上が黄土色になる。
# 同じ形・同じ色の部品は MultiMesh でまとめて 1 回で描く(1 区画 25 個ほどの部品を、別々の部品にしない。レビュー M1)
const Garden = preload("res://logic/Garden.gd")
const Look = preload("res://view/3d/Look.gd")

const ROWS := 3     # LandView3D の畝と同じ本数
const COLUMNS := 4
const BED_TOP := 0.12  # LandView3D の土の箱の上面
const MIN_SCALE := 0.2 # まいたばかりの芽の大きさ(育ちきった葉に対する割合)
const SPOILED := Color(0.36, 0.26, 0.14)  # 傷んだ実の色
const WEED := Color(0.70, 0.74, 0.26)     # 雑草の色(野菜の葉と見分けられるよう、黄色っぽく明るい)
const STRAW := Color(0.80, 0.68, 0.40)    # 敷いたわらの色
const PADDY_WATER := Color(0.42, 0.62, 0.74, 0.8)  # 田んぼに張った水の色(空を映した水色)
const MAX_WEEDS := 8                      # 1 区画に見せる雑草の株の数(生えて 4 日でいっぱい)

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
	"rice": {"leaf": Color(0.42, 0.66, 0.26), "size": Vector3(0.16, 0.8, 0.16), "ball": false, "ripe": Color(0.92, 0.80, 0.40), "ripe_size": Vector3(0.12, 0.2, 0.12)},  # 細い株。実ると穂が黄金色に垂れる
	"kibi": {"leaf": Color(0.44, 0.64, 0.26), "size": Vector3(0.26, 1.0, 0.26), "ball": false, "ripe": Color(0.96, 0.86, 0.36), "ripe_size": Vector3(0.14, 0.18, 0.14)},  # 垂れた黄色い穂
	"onion": {"leaf": Color(0.40, 0.64, 0.30), "size": Vector3(0.10, 0.50, 0.10), "ball": false, "ripe": Color(0.80, 0.58, 0.30), "ripe_size": Vector3(0.20, 0.18, 0.20)},
	"negi": {"leaf": Color(0.36, 0.62, 0.30), "size": Vector3(0.10, 0.70, 0.10), "ball": false, "ripe": Color(0.95, 0.95, 0.90), "ripe_size": Vector3(0.08, 0.14, 0.08)},
}

var garden: Garden
var _ball := SphereMesh.new()
var _cone := CylinderMesh.new()
var _wet_mesh := BoxMesh.new()
var _wet_mat := Look.mat(Color(0.14, 0.09, 0.06, 0.55))
var _straw_mesh := BoxMesh.new()
var _mats := {}
# 描く部品は、形・種類・色ごとの組に入れる(組ごとに 1 つの MultiMesh)
var _groups := []                  # [{what: leaf/fruit/wet/water/straw/weed, mesh, color, xforms: [Transform3D]}]
var _index := {}                   # [mesh, what, color] → _groups の番号
var _order := PackedInt32Array()   # 置いた順の組の番号(区画ごとに 濡れた土 → 水 → わら → 雑草 → 株と実)。テスト用の parts() が使う

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
	_straw_mesh.size = Vector3(size, 0.03, size)
	garden.changed.connect(_rebuild)
	garden.forest.calendar_changed.connect(_rebuild)  # 先送りプレビュー・日付の変化(木の変化では作り直さない。レビュー M2)
	_rebuild()

func _mat(c: Color) -> Material:
	if not _mats.has(c):
		_mats[c] = Look.mat(c)
		_mats[c].scaled_instances = true  # 株は伸び縮みさせて置くので、面の向きを直す(下の _rebuild で伸び縮みを渡す)
	return _mats[c]

# 描いている部品の数(テスト用)
func part_count() -> int:
	return _order.size()

# 描いている部品を置いた順に [{what, mesh, color, transform}](テスト用。ふだんの描画では作らない)
func parts() -> Array:
	var used := {}
	var out := []
	for gi in _order:
		var k: int = used.get(gi, 0)
		used[gi] = k + 1
		var g: Dictionary = _groups[gi]
		out.append({"what": g.what, "mesh": g.mesh, "color": g.color, "transform": g.xforms[k]})
	return out

func _part(what: String, mesh: Mesh, c: Color, pos: Vector3, scl := Vector3.ONE) -> void:
	_put(_group(what, mesh, c), pos, scl)

# 形・種類・色の組の番号(なければ作る)
func _group(what: String, mesh: Mesh, c: Color) -> int:
	var key := [mesh, what, c]
	var gi: int = _index.get(key, -1)
	if gi < 0:
		gi = _groups.size()
		_index[key] = gi
		_groups.append({"what": what, "mesh": mesh, "color": c, "xforms": []})
	return gi

func _put(gi: int, pos: Vector3, scl: Vector3) -> void:
	_groups[gi].xforms.append(Transform3D(Basis.from_scale(scl), pos))
	_order.append(gi)

func _rebuild() -> void:
	_groups.clear()
	_index.clear()
	_order.clear()
	_collect()
	Look.clear_children(self)
	for g in _groups:
		var xforms: Array = g.xforms
		# 16 個の数で 1 つ: 置き方 12 個(基底の行ごとに x・y・z と位置)+ 伸び縮み 4 個(材質が面の向きを直すのに使う)。
		# まとめて渡すと 1 つずつ渡すより速い
		var buf := PackedFloat32Array()
		buf.resize(xforms.size() * 16)
		for i in range(xforms.size()):
			var t: Transform3D = xforms[i]
			var j := i * 16
			buf[j] = t.basis.x.x; buf[j + 1] = t.basis.y.x; buf[j + 2] = t.basis.z.x; buf[j + 3] = t.origin.x
			buf[j + 4] = t.basis.x.y; buf[j + 5] = t.basis.y.y; buf[j + 6] = t.basis.z.y; buf[j + 7] = t.origin.y
			buf[j + 8] = t.basis.x.z; buf[j + 9] = t.basis.y.z; buf[j + 10] = t.basis.z.z; buf[j + 11] = t.origin.z
			buf[j + 12] = t.basis.x.x; buf[j + 13] = t.basis.y.y; buf[j + 14] = t.basis.z.z; buf[j + 15] = 1.0
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = g.mesh
		mm.instance_count = xforms.size()
		mm.buffer = buf
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = _wet_mat if g.what == "wet" else _mat(g.color)
		node.extra_cull_margin = Look.BEND_CULL_MARGIN
		if g.what in ["wet", "water", "straw"]:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # 土の上の平たい板
		add_child(node)

func _collect() -> void:
	var plot: float = garden.land.PLOT_SIZE - 0.2
	for c in garden.crops:
		var look: Dictionary = LOOKS[c.kind]
		var ratio: float = garden.growth_ratio(c)
		var leaf: Vector3 = look.size * lerpf(MIN_SCALE, 1.0, ratio)
		var mesh: Mesh = _ball if look.ball else _cone
		var fruit: Color = SPOILED if garden.is_spoiled(c) else look.ripe
		if garden.watered_today(c):
			_part("wet", _wet_mesh, _wet_mat.albedo_color, Look.at(c.pos, BED_TOP + 0.005))
		if garden.CROPS[c.kind].get("paddy", false):
			_part("water", _straw_mesh, PADDY_WATER, Look.at(c.pos, BED_TOP + 0.02))
		if c.get("mulched", false):
			_part("straw", _straw_mesh, STRAW, Look.at(c.pos, BED_TOP + 0.015))
		_add_weeds(c, plot)
		var leaves: int = _group("leaf", mesh, look.leaf)  # 1 区画の株は同じ組なので、探すのは 1 回だけ
		var fruits: int = _group("fruit", _ball, fruit) if ratio >= 1.0 else -1
		for r in range(ROWS):
			for k in range(COLUMNS):
				var p := Vector2(
					c.pos.x - plot * 0.5 + plot * (k + 0.5) / COLUMNS,
					c.pos.y - plot * 0.5 + plot * (r + 1.0) / (ROWS + 1.0))
				_put(leaves, Look.at(p, BED_TOP + leaf.y * 0.5), leaf)
				if fruits >= 0:
					# 引いたカメラからも分かるように、実は葉の上に見せる
					_put(fruits, Look.at(p, BED_TOP + leaf.y), look.ripe_size)

# 雑草: 株と株のあいだ(畝のあいだ)に、尖った草の束を置く。場所は区画の位置から決まる(描き直しても動かない)
func _add_weeds(c: Dictionary, plot: float) -> void:
	var n: int = mini(MAX_WEEDS, garden.weeds_now(c) * 2)
	if n <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = ("weed:%.1f:%.1f" % [c.pos.x, c.pos.y]).hash()
	for i in range(n):
		var p := Vector2(c.pos.x + rng.randf_range(-0.45, 0.45) * plot, c.pos.y - plot * 0.5 + plot * (rng.randi_range(0, ROWS) + 0.5) / (ROWS + 1.0))
		var h: float = rng.randf_range(0.22, 0.4)
		_part("weed", _cone, WEED, Look.at(p, BED_TOP + h * 0.5), Vector3(0.22, h, 0.22))
