extends Node3D

# ── 地面の 3D 表示(草地・10m グリッド・メルカバ・境界・土地の外の丘・草の株と花) ───
# 1 unit = 1m。ドメイン中心が原点で、±50m が境界。季節は logic/Forest.gd から読む。
# 土地の中はルールどおり平らで、起伏があるのは歩ける範囲(Player3D.WALK_LIMIT)より外の丘だけ
const Forest = preload("res://logic/Forest.gd")
const Look = preload("res://view/3d/Look.gd")
const TreeShapes = preload("res://view/3d/TreeShapes3D.gd")

const HALF := 50.0
const GRID := 10.0
const MERKABA_RADIUS := 15.0
const GRASS_SEGMENT := 2.0  # 草地を分ける長さ(m)。頂点がないと世界の曲がりに付いてこない

# 土地の外の丘
const WILD_RANGE := 320.0   # 地面を作る範囲(半分の幅)
const WILD_STEP := 5.0      # 頂点の間隔。50 を割り切れる値にして、土地の縁とそろえる
const HILL_START := 80.0    # ここまでは平ら(市場と、歩ける範囲を含む)
const HILL_END := 170.0     # ここで丘が最大の高さになる
const HILL_LOW := 8.0       # 丘の低いところの高さ(m)
const HILL_HIGH := 34.0     # 丘の高いところの高さ(m)
const HILL_FREQUENCY := 0.008  # 丘の大きさ。1 山がおよそ 100m
const HILL_NORMAL_SOFTEN := 3.0  # 丘の光の当たり方で、傾きをこの分だけ弱める

# 草の株と花
const TUFT_COUNT := 2600
const FLOWER_COUNT := 320
const SCATTER_SEED := 20261105
const SCATTER_MARGIN := 1.0     # 境界のすぐそばには生やさない
const TUFT_DARKEN := 0.14       # 株は地面より少し濃く、輪郭が出なくても見える
const POND_CLEAR := 2.0         # 池の縁と掘った土の分、池から離す(m)
const CABIN_CLEAR := 0.8        # 小屋のまわりの土台の分、離す(m)
const FLOWER_COLORS := [Color(0.98, 0.97, 0.90), Color(0.98, 0.84, 0.28), Color(0.95, 0.68, 0.74), Color(0.78, 0.70, 0.96)]

# 季節ごとの地面パレット(草地は 2D と同じ色)。wild は土地の外の、手入れしていない草地
const GROUND := {
	"spring": {"wild": Color(0.44, 0.63, 0.31), "grass": Color(0.62, 0.82, 0.42), "grid": Color(0.50, 0.70, 0.32)},
	"summer": {"wild": Color(0.37, 0.56, 0.26), "grass": Color(0.56, 0.77, 0.34), "grid": Color(0.44, 0.65, 0.27)},
	"autumn": {"wild": Color(0.56, 0.49, 0.24), "grass": Color(0.74, 0.66, 0.32), "grid": Color(0.62, 0.55, 0.26)},
	# 冬: 空の青い環境光を受けるので、地面の色は暖かめにしておく(青白く見えないように)
	"winter": {"wild": Color(0.92, 0.91, 0.88), "grass": Color(0.98, 0.95, 0.91), "grid": Color(0.86, 0.84, 0.82)},
}

# 土地の外の森(丘の上)。歩ける範囲より外だけに生えていて、見るだけのもの
const FOREST_SEED := 20261107
const FOREST_TRIES := 7000      # 置く場所を試す回数。林の外に当たったら置かない
const FOREST_SIZE_MIN := 0.42   # 木の大きさ。丘はカメラに近いので、土地の木より小さくしないと岩のかたまりに見える
const FOREST_SIZE_MAX := 0.78
const FOREST_START := 86.0      # ここより内には生やさない(東西南北の距離。歩ける範囲は 78m)
const FOREST_END := 250.0       # ここより外は世界の丸みで見えない
const FOREST_NOISE := 2.6       # 林の大きさ(丘の起伏の何倍の細かさか)
const FOREST_CLEARING := -0.08  # 雑音がこれより小さいところは林の切れ目
const FIR_COLOR := Color(0.14, 0.34, 0.20)
const FIR_COLOR_WINTER := Color(0.24, 0.38, 0.30)
const LEAF_COLORS := {
	"spring": Color(0.46, 0.66, 0.30),
	"summer": Color(0.27, 0.52, 0.22),
	"autumn": Color(0.80, 0.58, 0.18),
	"winter": Color(0.42, 0.36, 0.31),  # 冬は隠すので見えない
}

var forest: Forest
var land
var cabin
var _season := ""
var _wild_mat := Look.mat(Color.BLACK)
var _grass_mat := Look.mat(Color.BLACK)
var _grid_mat := Look.mat(Color.BLACK)
var _tuft_mat := Look.mat(Color.BLACK)
var _flower_mat := Look.mat(Color.WHITE)
var _fir_mat := Look.mat(FIR_COLOR)
var _leaf_mat := Look.mat(Color.BLACK)
var _tufts: MultiMeshInstance3D
var _flowers: MultiMeshInstance3D
var _firs: MultiMeshInstance3D      # 土地の外の森の針葉樹
var _broadleaves: MultiMeshInstance3D  # 土地の外の森の広葉樹
var _hills := FastNoiseLite.new()
var _hidden_count := 0  # 区画や小屋に隠れている株と花の数

func setup(f: Forest) -> void:
	forest = f
	forest.changed.connect(_on_changed)
	_hills.seed = SCATTER_SEED
	_hills.frequency = HILL_FREQUENCY
	_hills.fractal_octaves = 3
	_tuft_mat.vertex_color_use_as_albedo = true
	_flower_mat.vertex_color_use_as_albedo = true
	_fir_mat.vertex_color_use_as_albedo = true
	_leaf_mat.vertex_color_use_as_albedo = true
	_build()
	_on_changed()

# 区画・池・小屋の上には草を生やさない(3D だけ。Main が渡す)
func set_land(l, c) -> void:
	land = l
	cabin = c
	land.changed.connect(hide_covered)
	cabin.changed.connect(hide_covered)
	hide_covered()

# 季節が変わったときだけ色を差し替える(形は作り直さない)
func _on_changed() -> void:
	if forest.season == _season:
		return
	_season = forest.season
	var pal: Dictionary = GROUND[_season]
	_wild_mat.albedo_color = pal.wild
	_grass_mat.albedo_color = pal.grass
	_grid_mat.albedo_color = pal.grid
	_tuft_mat.albedo_color = (pal.grass as Color).darkened(TUFT_DARKEN)
	_tufts.visible = _season != "winter"  # 雪の下
	_flowers.visible = _season == "spring" or _season == "summer"
	_fir_mat.albedo_color = FIR_COLOR_WINTER if _season == "winter" else FIR_COLOR
	_leaf_mat.albedo_color = LEAF_COLORS[_season]
	_broadleaves.visible = _season != "winter"  # 葉を落とす。枝だけの形は遠くでは見えない

# 土地の外の地面の高さ(m)。歩ける範囲では 0 より少し低い平ら
func height_at(x: float, z: float) -> float:
	var ramp := smoothstep(HILL_START, HILL_END, maxf(absf(x), absf(z)))
	if ramp <= 0.0:
		return -0.02
	return -0.02 + ramp * lerpf(HILL_LOW, HILL_HIGH, _hills.get_noise_2d(x, z) * 0.5 + 0.5)

func _build() -> void:
	# 土地の外(丘)。子の順番: 0 = 丘、1 = 草地
	var wild := Look.mesh_node(_wild_mesh(), _wild_mat)
	wild.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # 低い太陽で、丘の影が土地に落ちないように
	add_child(wild)
	_wild_mat.vertex_color_use_as_albedo = true

	# 1 ヘクタールの草原(冬は雪原)。濃淡のむらを貼る
	var grass := PlaneMesh.new()
	grass.size = Vector2(HALF * 2, HALF * 2)
	grass.subdivide_width = int(HALF * 2 / GRASS_SEGMENT) - 1
	grass.subdivide_depth = grass.subdivide_width
	_grass_mat.albedo_texture = _patch_texture()
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

	_tufts = _scatter(_tuft_mesh(), TUFT_COUNT, _tuft_mat, false)
	_flowers = _scatter(_flower_mesh(), FLOWER_COUNT, _flower_mat, true)
	# 部屋の明かりが地面に当たらないように、地面の仲間だけ別のレイヤーにする(森はこのあとで足す)
	for child in get_children():
		child.layers = Look.GROUND_LAYER
	_build_forest()

# 土地の外の森。場所は乱数の種で決まるので毎回同じ
func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = FOREST_SEED
	var fir_spots := []
	var leaf_spots := []
	for _i in range(FOREST_TRIES):
		var x := rng.randf_range(-FOREST_END, FOREST_END)
		var z := rng.randf_range(-FOREST_END, FOREST_END)
		var is_fir := rng.randf() < 0.55
		var size := rng.randf_range(FOREST_SIZE_MIN, FOREST_SIZE_MAX)
		var yaw := rng.randf() * TAU
		if maxf(absf(x), absf(z)) < FOREST_START or _hills.get_noise_2d(x * FOREST_NOISE, z * FOREST_NOISE) < FOREST_CLEARING:
			continue
		var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), Vector3(x, height_at(x, z) - 0.2, z))
		if is_fir:
			fir_spots.append(t)
		else:
			leaf_spots.append(t)
	_firs = _forest_part(_fir_mesh(), fir_spots, _fir_mat)
	_broadleaves = _forest_part(_broadleaf_mesh(), leaf_spots, _leaf_mat)

func _forest_part(mesh: Mesh, spots: Array, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in range(spots.size()):
		mm.set_instance_transform(i, spots[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.set_meta("base", spots)  # 草の株と同じく、配置を読めるように持っておく
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = Look.BEND_CULL_MARGIN
	add_child(node)
	return node

# 針葉樹: 3 段の円錐。上の段ほど明るい
func _fir_mesh() -> ArrayMesh:
	var b := TreeShapes.MeshBuilder.new()
	_add_cone(b, 1.0, 3.0, 4.6, 0.72)
	_add_cone(b, 3.4, 2.3, 4.0, 0.86)
	_add_cone(b, 5.8, 1.5, 3.6, 1.0)
	return b.commit()

func _add_cone(b, base_y: float, radius: float, height: float, tint: float) -> void:
	const SIDES := 7
	var tip: int = b.vertex(Vector3(0.0, base_y + height, 0.0), Vector3.UP, tint)
	var rim := []
	for i in range(SIDES):
		var a := float(i) * TAU / SIDES
		var out := Vector3(cos(a), 0.0, sin(a))
		rim.append(b.vertex(out * radius + Vector3.UP * base_y, (out + Vector3.UP * 0.6).normalized(), tint * 0.85))
	for i in range(SIDES):
		b.tri(tip, rim[i], rim[(i + 1) % SIDES])

# 広葉樹: 丸い葉のかたまりを 3 つ
func _broadleaf_mesh() -> ArrayMesh:
	var b := TreeShapes.MeshBuilder.new()
	_add_cone(b, 0.0, 0.5, 4.5, 0.6)  # 幹
	_add_blob(b, Vector3(0.0, 5.0, 0.0), Vector3(3.2, 2.9, 3.2), 0.86)
	_add_blob(b, Vector3(1.5, 4.0, 0.8), Vector3(2.0, 1.8, 2.0), 0.76)
	_add_blob(b, Vector3(-1.3, 4.3, -0.9), Vector3(2.2, 2.0, 2.2), 1.0)
	return b.commit()

func _add_blob(b, center: Vector3, radii: Vector3, tint: float) -> void:
	const SIDES := 7
	const RINGS := 4
	var ids := []
	for r in range(RINGS + 1):
		var up := PI * float(r) / RINGS
		for i in range(SIDES):
			var a := float(i) * TAU / SIDES
			var dir := Vector3(sin(up) * cos(a), cos(up), sin(up) * sin(a))
			ids.append(b.vertex(center + dir * radii, dir, tint))
	for r in range(RINGS):
		for i in range(SIDES):
			var next := (i + 1) % SIDES
			b.quad(ids[r * SIDES + i], ids[r * SIDES + next], ids[(r + 1) * SIDES + i], ids[(r + 1) * SIDES + next])

# 丘の地面。土地の中には穴をあける(草地と重なってちらつかないように)
func _wild_mesh() -> ArrayMesh:
	var n := int(WILD_RANGE * 2.0 / WILD_STEP) + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for iz in range(n):
		for ix in range(n):
			heights[iz * n + ix] = height_at(_wild_coord(ix), _wild_coord(iz))
	var b := TreeShapes.MeshBuilder.new()
	var ids := PackedInt32Array()
	ids.resize(n * n)
	for iz in range(n):
		for ix in range(n):
			var h := heights[iz * n + ix]
			var left := heights[iz * n + maxi(ix - 1, 0)]
			var right := heights[iz * n + mini(ix + 1, n - 1)]
			var up := heights[maxi(iz - 1, 0) * n + ix]
			var down := heights[mini(iz + 1, n - 1) * n + ix]
			# 傾きを弱めた法線にして、丘の裏側がトゥーンの影の色にぱっと変わらないようにする
			var normal := Vector3(left - right, 2.0 * WILD_STEP * HILL_NORMAL_SOFTEN, up - down).normalized()
			# 高いところほど濃い。さらに草のむらを大きな単位で付ける
			var patch := 0.95 if _hills.get_noise_2d(_wild_coord(ix) * 6.0, _wild_coord(iz) * 6.0) < 0.0 else 1.0
			var tint := lerpf(1.0, 0.78, clampf(h / HILL_HIGH, 0.0, 1.0)) * patch
			ids[iz * n + ix] = b.vertex(Vector3(_wild_coord(ix), h, _wild_coord(iz)), normal, tint)
	for iz in range(n - 1):
		for ix in range(n - 1):
			if _inside_land(_wild_coord(ix), _wild_coord(iz)):
				continue
			var a := ids[iz * n + ix]
			var c := ids[(iz + 1) * n + ix]
			b.quad(a, ids[iz * n + ix + 1], c, ids[(iz + 1) * n + ix + 1])
	return b.commit()

func _wild_coord(i: int) -> float:
	return -WILD_RANGE + float(i) * WILD_STEP

# (x, z) から 1 マス分の四角が土地の中に入っているか
func _inside_land(x: float, z: float) -> bool:
	return x >= -HALF and x + WILD_STEP <= HALF and z >= -HALF and z + WILD_STEP <= HALF

# 草地の濃淡。境目のくっきりした 3 段にして、トゥーンの塗り分けとそろえる
func _patch_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = SCATTER_SEED
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.42, 0.62])
	g.colors = PackedColorArray([Color(0.955, 0.955, 0.955), Color(0.98, 0.98, 0.98), Color(1, 1, 1)])  # 木の影と見分けがつく薄さ
	var t := NoiseTexture2D.new()
	t.width = 1024
	t.height = 1024
	t.seamless = true
	t.noise = noise
	t.color_ramp = g
	return t

# 草の株: 外へ傾いた細い葉が 5 枚。法線を真上にして、地面と同じ光を受ける(株ごとに輪郭線が出ない)
func _tuft_mesh() -> ArrayMesh:
	var b := TreeShapes.MeshBuilder.new()
	for i in range(5):
		var a := float(i) * TAU / 5.0 + 0.4
		var out := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-out.z, 0.0, out.x)
		var root := out * 0.06
		var tall := 0.22 + 0.06 * float(i % 3)
		var p := b.vertex(root - side * 0.035, Vector3.UP, 0.86)
		var q := b.vertex(root + side * 0.035, Vector3.UP, 0.86)
		var tip := b.vertex(root + out * 0.16 + Vector3.UP * tall, Vector3.UP, 1.0)
		b.tri(p, q, tip)
	return b.commit()

# 花: 上を向いた 5 枚の花びら(星形)。まんなかは少し濃い
func _flower_mesh() -> ArrayMesh:
	const POINTS := 10
	const TIP := 0.17
	const NOTCH := 0.07
	const HEIGHT := 0.16
	var b := TreeShapes.MeshBuilder.new()
	var center := b.vertex(Vector3.UP * HEIGHT, Vector3.UP, 0.72)
	var rim := []
	for i in range(POINTS):
		var a := float(i) * TAU / float(POINTS)
		var r := TIP if i % 2 == 0 else NOTCH
		rim.append(b.vertex(Vector3(cos(a) * r, HEIGHT, sin(a) * r), Vector3.UP, 1.0))
	for i in range(POINTS):
		b.tri(center, rim[i], rim[(i + 1) % POINTS])
	return b.commit()

# 土地に形を散らす。場所は乱数の種で決まるので毎回同じ
func _scatter(mesh: Mesh, count: int, material: Material, colored: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colored
	mm.mesh = mesh
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = SCATTER_SEED + count
	var limit := HALF - SCATTER_MARGIN
	var base := []  # もとの配置。区画などで隠したあとに戻すために持っておく
	for i in range(count):
		var pos := Vector3(rng.randf_range(-limit, limit), 0.0, rng.randf_range(-limit, limit))
		var size := rng.randf_range(0.8, 1.3)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size), pos)
		base.append(t)
		mm.set_instance_transform(i, t)
		if colored:
			# インスタンスの色はそのまま計算に入るので、見た目の色に合わせて変換する
			var flower: Color = FLOWER_COLORS[rng.randi_range(0, FLOWER_COLORS.size() - 1)]
			mm.set_instance_color(i, flower.srgb_to_linear())
	var hidden := PackedByteArray()
	hidden.resize(count)
	hidden.fill(0)
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.set_meta("base", base)
	node.set_meta("hidden", hidden)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = Look.BEND_CULL_MARGIN
	add_child(node)
	return node

# 区画・池・小屋の上の株と花を隠す(大きさ 0 にする)。隠した数を覚えておく
func hide_covered() -> void:
	if land == null:
		return
	_hidden_count = 0
	var cells := {}
	for c in land.plots:
		cells[c] = true
	for node in [_tufts, _flowers]:
		var mm: MultiMesh = node.multimesh
		var base: Array = node.get_meta("base")
		var hidden: PackedByteArray = node.get_meta("hidden")
		for i in range(mm.instance_count):
			var t: Transform3D = base[i]
			var covered := _is_covered(Vector2(t.origin.x, t.origin.z), cells)
			if covered:
				_hidden_count += 1
			if covered != (hidden[i] == 1):
				hidden[i] = 1 if covered else 0
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), t.origin) if covered else t)
		node.set_meta("hidden", hidden)

func hidden_count() -> int:
	return _hidden_count

func _is_covered(p: Vector2, cells: Dictionary) -> bool:
	if cells.has(land.plot_center(p)):
		return true
	if land.pond != null and p.distance_to(land.pond) < land.POND_RADIUS + POND_CLEAR:
		return true
	if cabin.site != null:
		var d: Vector2 = (p - cabin.site).abs()
		if d.x < cabin.WIDTH * 0.5 + CABIN_CLEAR and d.y < cabin.DEPTH * 0.5 + CABIN_CLEAR:
			return true
	return false
