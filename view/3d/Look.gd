extends RefCounted

# ── 3D の view で共通に使う、マテリアルと形の小さな部品 ───────────────
# 座標: ロジックの Vector2(x, y)(m)を 3D の Vector3(x, 高さ, y)に置く。
# 画面の上(-z)がロジックの -y(2D の上)と同じ向きになる

static func at(p: Vector2, height := 0.0) -> Vector3:
	return Vector3(p.x, height, p.y)

# 単色のマテリアル。alpha < 1 なら半透明、unshaded なら光の影響を受けない(印・線用)
static func mat(c: Color, unshaded := false, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = Color(c.r, c.g, c.b)
		m.emission_energy_multiplier = emission
	return m

static func mesh_node(mesh: Mesh, material: Material, pos := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.scale = scl
	return mi

# 地面に置く細長い帯(a から b まで、幅 width、厚さ height)。境界線・メルカバ用
static func strip(a: Vector2, b: Vector2, width: float, height: float, material: Material, y := 0.0) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(a.distance_to(b) + width, height, width)
	var mi := mesh_node(box, material, at((a + b) * 0.5, y + height * 0.5))
	mi.rotation.y = -(b - a).angle()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

# 地面に置く輪(中心 c、半径 r、太さ thickness)
static func ring(c: Vector2, r: float, thickness: float, material: Material, y := 0.05) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = r - thickness * 0.5
	torus.outer_radius = r + thickness * 0.5
	torus.rings = 48 if r > 3.0 else 24
	var mi := mesh_node(torus, material, at(c, y), Vector3(1.0, 0.3, 1.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func clear_children(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()
