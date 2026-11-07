extends Node3D

# ── 木の 3D 表示(先細りの幹 + 葉のかたまりの樹冠。冬の落葉樹は枝だけ) ─────
# 状態とルールは logic/Forest.gd、形は TreeShapes3D.gd。ここは読んで形を置くだけ。
# 木が増えた・減った・季節が変わった(changed)ら作り直し、成長は 1 秒ごとに大きさだけ直す。
# 幹のある木には、幹の太さの当たり判定を付ける(葉の下は歩ける。種や幹のない苗木は通り抜けられる)
const Forest = preload("res://logic/Forest.gd")
const Look = preload("res://view/3d/Look.gd")
const TreeShapes = preload("res://view/3d/TreeShapes3D.gd")

const SAPLING_R := 0.15  # 樹冠半径(m)がこれ未満なら苗木の形

# 樹種ごとの色(2D と同じ色を不透明にしたもの)と形の比率(樹冠半径 r に対する倍率)
#   trunk_h: 幹の見えている高さ / trunk_w: 幹の太さ(直径)
#   crown_h: 樹冠の高さ / crown_y: 幹の上端から樹冠の中心(円錐は底)までの高さ / twig: 冬の枝の色
const KINDS := {
	"birch": {
		"leaf": Color(0.45, 0.72, 0.30), "leaf_autumn": Color(0.90, 0.74, 0.20), "trunk": Color(0.92, 0.92, 0.88), "twig": Color(0.36, 0.28, 0.24),
		"shape": "sphere", "trunk_h": 2.2, "trunk_w": 0.09, "crown_h": 2.6, "crown_y": 0.9,
	},
	"apple": {
		"leaf": Color(0.24, 0.58, 0.22), "leaf_autumn": Color(0.80, 0.55, 0.18), "trunk": Color(0.35, 0.22, 0.10), "twig": Color(0.35, 0.22, 0.10),
		"shape": "sphere", "trunk_h": 0.8, "trunk_w": 0.14, "crown_h": 1.6, "crown_y": 0.6,
	},
	"cherry": {
		"leaf": Color(0.28, 0.58, 0.24), "leaf_autumn": Color(0.82, 0.42, 0.18), "trunk": Color(0.34, 0.18, 0.12), "twig": Color(0.34, 0.18, 0.12),
		"shape": "sphere", "trunk_h": 0.9, "trunk_w": 0.13, "crown_h": 1.7, "crown_y": 0.6,
	},
	"plum": {
		"leaf": Color(0.26, 0.52, 0.26), "leaf_autumn": Color(0.72, 0.46, 0.20), "trunk": Color(0.28, 0.18, 0.14), "twig": Color(0.28, 0.18, 0.14),
		"shape": "sphere", "trunk_h": 0.8, "trunk_w": 0.12, "crown_h": 1.8, "crown_y": 0.6,
	},
	"pear": {
		"leaf": Color(0.30, 0.60, 0.26), "leaf_autumn": Color(0.86, 0.62, 0.20), "trunk": Color(0.36, 0.26, 0.16), "twig": Color(0.36, 0.26, 0.16),
		"shape": "sphere", "trunk_h": 1.0, "trunk_w": 0.13, "crown_h": 2.3, "crown_y": 0.8,
	},
	"cedar": {
		"leaf": Color(0.10, 0.40, 0.20), "leaf_autumn": Color(0.10, 0.40, 0.20), "trunk": Color(0.30, 0.18, 0.08),
		"shape": "cone", "trunk_h": 0.5, "trunk_w": 0.12, "crown_h": 3.5, "crown_y": -0.2,
	},
}
const BLOSSOM := Color(1.0, 0.80, 0.74)  # 空の光で青みが足されるので、暖かい色にしておく
const FRUIT := Color(0.85, 0.15, 0.12)
# 実の色と大きさの倍率(サクランボは小さく、ナシは少し大きい)
const FRUIT_LOOKS := {
	"apple": {"color": FRUIT, "scale": 1.0},
	"cherry": {"color": Color(0.72, 0.06, 0.14), "scale": 0.8},
	"plum": {"color": Color(0.40, 0.14, 0.44), "scale": 0.9},
	"pear": {"color": Color(0.82, 0.78, 0.26), "scale": 1.15},
}
# 春の花の色(花の咲く果樹だけ)。花をどれだけ前に出すか
const BLOSSOMS := {
	"apple": {"color": BLOSSOM, "amount": 0.85},
	"cherry": {"color": Color(1.0, 0.72, 0.78), "amount": 0.95},
	"plum": {"color": Color(1.0, 0.95, 0.90), "amount": 0.9},
	"pear": {"color": Color(1.0, 0.97, 0.92), "amount": 0.85},
}
const LEAF_SHADE := 0.06  # 木ごとの葉の色の違い(明るい・そのまま・暗いの 3 通り)
const SPROUT_SCALE := 0.45
const FALL_WAIT := 0.35     # 斧が当たるまで立っている時間
const FALL_SECONDS := 0.9   # 倒れるのにかかる時間
const FALL_FADE := 0.4      # 倒れたあと小さくなって消えるまでの時間
const TRUNK_BODY_MIN := 0.1   # 幹の当たり判定の半径の下限(m)
const TRUNK_BODY_EXTRA := 0.05  # 見た目の幹より少し太くする(めり込んで見えないように)
const TRUNK_BODY_HEIGHT := 3.0
const PRUNED_CROWN := 0.86   # 剪定した冬の枝の広がり(切り詰めて、少し小さくまとまる)
const PRUNED_FRUITS := 7     # 剪定した木に見える実の数(ふだんは 5)
const BRUSH_STICKS := 4      # 根元に束ねた、切った枝の本数

var forest: Forest
var last_fall: Tween  # 直前に倒れた木の動き(テスト用)
var _bodies: StaticBody3D  # 幹の当たり判定をまとめる
var _timer := 0.0
var _items := []  # 木ごとの {tree, trunk, crown, fruits: []} (forest.trees と同じ順)

# 形は単位の大きさで樹種・種類ごとに 1 つずつ作り、木はそれを使い回して scale で大きさを変える
var _shapes := {}  # "樹種_種類" → {trunk, crown, anchors, bare}
var _sphere_mesh := _sphere(0.5, 32)
var _fruit_mesh := _sphere(0.5, 8)
var _sprout_mesh := TreeShapes.sprout()
var _stick_mesh := BoxMesh.new()
var _sapling_mat := Look.mat(Color(0.20, 0.65, 0.20))
var _mound_mat := Look.mat(Color(0.36, 0.25, 0.15))  # 種をまいた土の盛り上がり
var _fruit_mats := {}  # 樹種ごとの実の材質
var _water_mat := Look.mat(Color(0.25, 0.60, 0.95, 0.9), true)
var _mats := {}  # マテリアルの使い回し

func _shape(species: String, variant: int) -> Dictionary:
	var key := "%s_%d" % [species, variant]
	if not _shapes.has(key):
		var c: Dictionary = TreeShapes.crown(species, variant)
		_shapes[key] = {
			"trunk": TreeShapes.trunk(species, variant),
			"crown": c.mesh,
			"anchors": c.anchors,
			"bare": null if forest.SPECIES[species].evergreen else TreeShapes.bare_branches(species, variant),
		}
	return _shapes[key]

static func _sphere(r: float, seg: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = int(seg / 2.0)
	return m

func setup(f: Forest) -> void:
	forest = f
	_bodies = StaticBody3D.new()
	_bodies.name = "TrunkBodies"
	get_parent().add_child(_bodies)  # 木の形と分けて置く(倒れる木と同じく、親の下)
	forest.changed.connect(_rebuild)
	_rebuild()

func _process(delta: float) -> void:
	# 成長は年単位(1 日 = 1 年)なので、大きさの更新は 1 秒に 1 回で十分
	_timer += delta
	if _timer >= 1.0:
		_timer = 0.0
		_layout()

# 頂点の色(かたまりごとの明るさ)を効かせた単色の材質
func _material(key: String, c: Color) -> Material:
	if not _mats.has(key):
		var m := Look.mat(c)
		m.vertex_color_use_as_albedo = true
		_mats[key] = m
	return _mats[key]

# 伐られた木が from(足元)の反対側へ倒れる形を作る。木を消す前に呼ぶ。
# ロジックからはすぐ消えるので、形の写しを親に置く(作り直しで消えないように)。
# 幹のない苗木や種は倒れない(false を返す)
func start_fall(tree: Dictionary, from: Vector2) -> bool:
	for item in _items:
		if not is_same(item.tree, tree):
			continue
		if not item.trunk.visible:
			return false
		var base := Look.at(tree.pos)
		var pivot := Node3D.new()
		pivot.name = "FallingTree"
		pivot.position = base
		get_parent().add_child(pivot, true)
		for node in [item.trunk, item.crown] + item.fruits:
			var copy: MeshInstance3D = node.duplicate()
			copy.position = node.position - base
			pivot.add_child(copy)
		var away: Vector2 = tree.pos - from
		if away.length() < 0.01:
			away = Vector2.RIGHT
		var axis: Vector3 = Vector3.UP.cross(Vector3(away.x, 0.0, away.y).normalized())
		last_fall = pivot.create_tween()
		last_fall.tween_interval(FALL_WAIT)
		last_fall.tween_property(pivot, "quaternion", Quaternion(axis, PI * 0.48), FALL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		last_fall.tween_property(pivot, "scale", Vector3.ONE * 0.01, FALL_FADE)
		last_fall.tween_callback(pivot.queue_free)
		return true
	return false

# 冬の落葉樹は葉を落として枝だけになる
func is_bare(species: String) -> bool:
	return forest.season == "winter" and not forest.SPECIES[species].evergreen

func twig_material(species: String) -> Material:
	return _material(species + "_twig", KINDS[species].twig)

func _leaf_color(species: String) -> Color:
	var k: Dictionary = KINDS[species]
	var evergreen: bool = forest.SPECIES[species].evergreen
	match forest.season:
		"autumn":
			return k.leaf if evergreen else k.leaf_autumn
		"winter":
			return k.leaf.darkened(0.2)  # 常緑樹は少し沈んだ色
		"spring":
			if BLOSSOMS.has(species):
				return k.leaf.lerp(BLOSSOMS[species].color, BLOSSOMS[species].amount)
			return k.leaf
	return k.leaf

# 木ごとの違いは位置から決める(毎回同じ見た目)
func _rebuild() -> void:
	Look.clear_children(self)
	Look.clear_children(_bodies)
	_items.clear()
	for tree in forest.trees:
		var k: Dictionary = KINDS[tree.species]
		var h: int = absi(hash(tree.pos))
		var shape := _shape(tree.species, h % TreeShapes.VARIANTS)
		var pruned: bool = forest.is_pruned(tree)
		var item := {"tree": tree, "fruits": [], "hash": h, "anchors": shape.anchors, "pruned_bare": pruned and is_bare(tree.species)}
		item.trunk = Look.mesh_node(shape.trunk, _material(tree.species + "_trunk", k.trunk))
		if is_bare(tree.species):
			item.crown_mesh = shape.bare
			item.leaf_mat = twig_material(tree.species)
		else:
			var shade := float((h >> 8) % 3 - 1) * LEAF_SHADE
			var leaf := _leaf_color(tree.species)
			leaf = leaf.lightened(shade) if shade > 0.0 else leaf.darkened(-shade)
			item.crown_mesh = shape.crown
			item.leaf_mat = _material("%s_leaf_%s" % [tree.species, leaf.to_html()], leaf)
		item.crown = Look.mesh_node(item.crown_mesh, item.leaf_mat)
		# 同じ形でも向きを変えると別の木に見える
		var yaw := deg_to_rad(float((h >> 12) % 360))
		item.trunk.rotation.y = yaw
		item.crown.rotation.y = yaw
		add_child(item.trunk)
		add_child(item.crown)
		if forest.shows_fruit(tree):
			if not _fruit_mats.has(tree.species):
				_fruit_mats[tree.species] = Look.mat(FRUIT_LOOKS[tree.species].color)
			for i in range(PRUNED_FRUITS if pruned else 5):
				var fr := Look.mesh_node(_fruit_mesh, _fruit_mats[tree.species])
				item.fruits.append(fr)
				add_child(fr)
		# 剪定した冬のあいだは、切った枝が根元に束ねてある
		if item.pruned_bare:
			add_child(_brush(tree, h))
		# 今日水をあげた木は、根元に水色の輪(どの木が済んだか分かるように)
		if forest.watered_today(tree):
			item.ring = Look.ring(tree.pos, 0.6, 0.12, _water_mat)
			add_child(item.ring)
		item.trunk_body = _trunk_shape(tree.pos)
		_items.append(item)
	_layout()

# 切った枝の束(カメラの側、幹の南に置く)
func _brush(tree: Dictionary, h: int) -> Node3D:
	var key: String = tree.species + "_brush"
	if not _mats.has(key):
		_mats[key] = Look.mat(KINDS[tree.species].twig.lightened(0.15))
	var brush := Node3D.new()
	brush.name = "PrunedBranches"
	brush.position = Look.at(tree.pos + Vector2(0.15, 0.65))
	brush.rotation.y = deg_to_rad(float((h >> 4) % 40) - 20.0)
	for i in range(BRUSH_STICKS):
		var spread: float = (i - (BRUSH_STICKS - 1) * 0.5) * 0.06
		var stick := Look.mesh_node(_stick_mesh, _mats[key], Vector3(spread, 0.05 + (i % 2) * 0.04, 0), Vector3(0.035, 0.035, 0.85))
		stick.rotation.y = spread * 2.5
		brush.add_child(stick)
	return brush

# 幹の当たり判定を 1 本ぶん作る。太さは _layout が決める
func _trunk_shape(pos: Vector2) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.height = TRUNK_BODY_HEIGHT
	cyl.radius = TRUNK_BODY_MIN
	shape.shape = cyl
	shape.position = Look.at(pos, TRUNK_BODY_HEIGHT * 0.5)
	shape.disabled = true
	_bodies.add_child(shape)
	return shape

# 樹齢に合わせて大きさと位置を決める
func _layout() -> void:
	for item in _items:
		var tree: Dictionary = item.tree
		var k: Dictionary = KINDS[tree.species]
		var r: float = forest.radius_of(tree)
		var base := Look.at(tree.pos)
		item.trunk_body.disabled = true  # 幹のある木だけ、下で付ける
		if forest.is_seed(tree):
			# 芽が出る前の種: 小さな土の盛り上がり
			item.trunk.visible = false
			item.crown.material_override = _mound_mat
			item.crown.mesh = _sphere_mesh
			item.crown.position = base + Vector3(0, 0.02, 0)
			item.crown.scale = Vector3(0.5, 0.12, 0.5)
			continue
		if r < SAPLING_R:
			# 苗木: 地面から少し出た小さな芽
			item.trunk.visible = false
			item.crown.material_override = _sapling_mat
			item.crown.mesh = _sprout_mesh
			item.crown.position = base
			item.crown.scale = Vector3.ONE * SPROUT_SCALE
			continue
		item.trunk.visible = true
		item.crown.mesh = item.crown_mesh
		item.crown.material_override = item.leaf_mat
		var trunk_h: float = k.trunk_h * r
		var trunk_w: float = k.trunk_w * r + 0.04
		item.trunk_body.disabled = false
		item.trunk_body.shape.radius = maxf(trunk_w * 0.5 + TRUNK_BODY_EXTRA, TRUNK_BODY_MIN)
		var crown_h: float = k.crown_h * r
		# 幹は樹冠の中まで伸ばして、継ぎ目が見えないようにする
		var trunk_len: float = trunk_h + crown_h * 0.5
		item.trunk.position = base + Vector3(0, trunk_len * 0.5, 0)
		item.trunk.scale = Vector3(trunk_w, trunk_len, trunk_w)
		var crown_y: float = trunk_h + k.crown_y * r
		if k.shape == "cone":
			item.crown.position = base + Vector3(0, crown_y + crown_h * 0.5, 0)
		else:
			item.crown.position = base + Vector3(0, crown_y, 0)
		item.crown.scale = Vector3(2.0 * r, crown_h, 2.0 * r)
		if item.pruned_bare:
			item.crown.scale *= PRUNED_CROWN
		_place_fruits(item, r)

# 実は葉のかたまりの表面に付ける(浮いたり埋もれたりしないように、形が持っている場所を使う)
func _place_fruits(item: Dictionary, r: float) -> void:
	var anchors: Array = item.anchors
	var crown: MeshInstance3D = item.crown
	for i in range(item.fruits.size()):
		var anchor: Vector3 = anchors[(item.hash + i) % anchors.size()]
		item.fruits[i].position = crown.position + crown.basis * anchor
		item.fruits[i].scale = Vector3.ONE * clampf(0.12 * r, 0.12, 0.3) * float(FRUIT_LOOKS[item.tree.species].scale)
