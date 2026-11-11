extends Node3D

# ── 一族の土地の外の、自然の林の 3D 表示 ───────────────────────────
# 木の場所・樹種・樹齢は logic/Wilds.gd。形は TreeShapes3D、色は TreesView3D.KINDS と同じものを使う(土地の木と同じに見える)。
# 林の木は育ちきっているので、大きさは変わらない。季節(落葉・紅葉・花)と県が変わったときだけ作り直す。
# 幹には当たり判定を付ける(土地の木と同じ)。落ちた種は PickupsView3D が描く
const Wilds = preload("res://logic/Wilds.gd")
const Look = preload("res://view/3d/Look.gd")
const TreeShapes = preload("res://view/3d/TreeShapes3D.gd")
const TreesView = preload("res://view/3d/TreesView3D.gd")

const LEAF_SHADE := 0.06

var wilds: Wilds
var _key := "-"            # 作ったときの「県:季節」
var _bodies: StaticBody3D
var _shapes := {}
var _mats := {}

func setup(w: Wilds) -> void:
	wilds = w
	_bodies = StaticBody3D.new()
	_bodies.name = "WildTrunkBodies"
	add_child(_bodies)
	wilds.forest.changed.connect(_on_changed)
	_on_changed()

func _on_changed() -> void:
	var f = wilds.forest
	var key := "%s:%s" % [f.region.pref if f.region != null else "", f.season]
	if key == _key:
		return
	_key = key
	_rebuild()

func tree_count() -> int:
	return _bodies.get_child_count()

func _material(key: String, c: Color) -> Material:
	if not _mats.has(key):
		var m := Look.mat(c)
		m.vertex_color_use_as_albedo = true
		_mats[key] = m
	return _mats[key]

func _shape(species: String, variant: int) -> Dictionary:
	var key := "%s_%d" % [species, variant]
	if not _shapes.has(key):
		var c: Dictionary = TreeShapes.crown(species, variant)
		_shapes[key] = {
			"trunk": TreeShapes.trunk(species, variant),
			"crown": c.mesh,
			"bare": null if wilds.forest.SPECIES[species].evergreen else TreeShapes.bare_branches(species, variant),
		}
	return _shapes[key]

func _leaf_color(species: String) -> Color:
	var f = wilds.forest
	var k: Dictionary = TreesView.KINDS[species]
	var evergreen: bool = f.SPECIES[species].evergreen
	match f.season:
		"autumn":
			return k.leaf if evergreen else k.leaf_autumn
		"winter":
			return k.leaf.darkened(0.2)
		"spring":
			if TreesView.BLOSSOMS.has(species):
				return k.leaf.lerp(TreesView.BLOSSOMS[species].color, TreesView.BLOSSOMS[species].amount)
	return k.leaf

func _rebuild() -> void:
	for c in get_children():
		if c != _bodies:
			c.queue_free()
	for b in _bodies.get_children():
		b.queue_free()
	wilds.refresh()
	var f = wilds.forest
	for i in range(wilds.trees.size()):
		var t: Dictionary = wilds.trees[i]
		var sp: String = t.species
		var s: Dictionary = f.SPECIES[sp]
		var k: Dictionary = TreesView.KINDS[sp]
		var shape := _shape(sp, i % TreeShapes.VARIANTS)
		var r: float = float(s.max_r) * pow(1.0 - exp(-float(t.age) / float(s.tau)), float(s.p))
		var base := Look.at(t.pos)
		var trunk_h: float = k.trunk_h * r
		var trunk_w: float = k.trunk_w * r + 0.04
		var crown_h: float = k.crown_h * r
		var trunk_len: float = trunk_h + crown_h * 0.5
		add_child(Look.mesh_node(shape.trunk, _material(sp + "_trunk", k.trunk), base + Vector3(0, trunk_len * 0.5, 0), Vector3(trunk_w, trunk_len, trunk_w)))
		var bare: bool = f.season == "winter" and not s.evergreen
		var mesh: Mesh = shape.bare if bare else shape.crown
		var mat: Material
		if bare:
			mat = _material(sp + "_twig", k.get("twig", k.trunk))
		else:
			var shade := float(i % 3 - 1) * LEAF_SHADE
			var leaf := _leaf_color(sp)
			leaf = leaf.lightened(shade) if shade > 0.0 else leaf.darkened(-shade)
			mat = _material("%s_%s_%d" % [sp, f.season, i % 3], leaf)
		var crown_y: float = trunk_h + k.crown_y * r
		var pos := base + Vector3(0, crown_y + (crown_h * 0.5 if k.shape == "cone" else 0.0), 0)
		add_child(Look.mesh_node(mesh, mat, pos, Vector3(2.0 * r, crown_h, 2.0 * r)))
		var col := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = maxf(trunk_w * 0.5 + 0.05, 0.1)
		cyl.height = 3.0
		col.shape = cyl
		col.position = Vector3(t.pos.x, 1.5, t.pos.y)
		_bodies.add_child(col)
