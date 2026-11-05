extends Node3D

# ── 木の 3D 表示(先細りの幹 + 葉のかたまりの樹冠。冬の落葉樹は枝だけ) ─────
# 状態とルールは logic/Forest.gd、形は TreeShapes3D.gd。ここは読んで形を置くだけ。
# 木が増えた・減った・季節が変わった(changed)ら作り直し、成長は 1 秒ごとに大きさだけ直す
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
	"cedar": {
		"leaf": Color(0.10, 0.40, 0.20), "leaf_autumn": Color(0.10, 0.40, 0.20), "trunk": Color(0.30, 0.18, 0.08),
		"shape": "cone", "trunk_h": 0.5, "trunk_w": 0.12, "crown_h": 3.5, "crown_y": -0.2,
	},
}
const BLOSSOM := Color(1.0, 0.80, 0.74)  # 空の光で青みが足されるので、暖かい色にしておく
const FRUIT := Color(0.85, 0.15, 0.12)
const LEAF_SHADE := 0.06  # 木ごとの葉の色の違い(明るい・そのまま・暗いの 3 通り)
const SPROUT_SCALE := 0.45

var forest: Forest
var _timer := 0.0
var _items := []  # 木ごとの {tree, trunk, crown, fruits: []} (forest.trees と同じ順)

# 形は単位の大きさで樹種・種類ごとに 1 つずつ作り、木はそれを使い回して scale で大きさを変える
var _shapes := {}  # "樹種_種類" → {trunk, crown, anchors, bare}
var _sphere_mesh := _sphere(0.5, 32)
var _fruit_mesh := _sphere(0.5, 8)
var _sprout_mesh := TreeShapes.sprout()
var _sapling_mat := Look.mat(Color(0.20, 0.65, 0.20))
var _mound_mat := Look.mat(Color(0.36, 0.25, 0.15))  # 種をまいた土の盛り上がり
var _fruit_mat := Look.mat(FRUIT)
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
	forest.changed.connect(_rebuild)
	_rebuild()

func _process(delta: float) -> void:
	# 成長は年単位(1 日 = 1 年)なので、大きさの更新は 1 秒に 1 回で十分
	_timer += delta
	if _timer >= 1.0:
		_timer = 0.0
		_layout()

# 頂点の色(かたまりごとの明るさ)を効かせた単色の材質
func _material(key: String, c: Color) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := Look.mat(c)
		m.vertex_color_use_as_albedo = true
		_mats[key] = m
	return _mats[key]

# 冬の落葉樹は葉を落として枝だけになる
func is_bare(species: String) -> bool:
	return forest.season == "winter" and not forest.SPECIES[species].evergreen

func twig_material(species: String) -> StandardMaterial3D:
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
			return k.leaf.lerp(BLOSSOM, 0.85) if species == "apple" else k.leaf
	return k.leaf

# 木ごとの違いは位置から決める(毎回同じ見た目)
func _rebuild() -> void:
	Look.clear_children(self)
	_items.clear()
	for tree in forest.trees:
		var k: Dictionary = KINDS[tree.species]
		var h: int = absi(hash(tree.pos))
		var shape := _shape(tree.species, h % TreeShapes.VARIANTS)
		var item := {"tree": tree, "fruits": [], "hash": h, "anchors": shape.anchors}
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
			for i in range(5):
				var fr := Look.mesh_node(_fruit_mesh, _fruit_mat)
				item.fruits.append(fr)
				add_child(fr)
		# 今日水をあげた木は、根元に水色の輪(どの木が済んだか分かるように)
		if forest.watered_today(tree):
			item.ring = Look.ring(tree.pos, 0.6, 0.12, _water_mat)
			add_child(item.ring)
		_items.append(item)
	_layout()

# 樹齢に合わせて大きさと位置を決める
func _layout() -> void:
	for item in _items:
		var tree: Dictionary = item.tree
		var k: Dictionary = KINDS[tree.species]
		var r: float = forest.radius_of(tree)
		var base := Look.at(tree.pos)
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
		_place_fruits(item, r)

# 実は葉のかたまりの表面に付ける(浮いたり埋もれたりしないように、形が持っている場所を使う)
func _place_fruits(item: Dictionary, r: float) -> void:
	var anchors: Array = item.anchors
	var crown: MeshInstance3D = item.crown
	for i in range(item.fruits.size()):
		var anchor: Vector3 = anchors[(item.hash + i) % anchors.size()]
		item.fruits[i].position = crown.position + crown.basis * anchor
		item.fruits[i].scale = Vector3.ONE * clampf(0.12 * r, 0.12, 0.3)
