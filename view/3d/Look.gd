extends RefCounted

# ── 3D の view で共通に使う、マテリアルと形の小さな部品 ───────────────
# 座標: ロジックの Vector2(x, y)(m)を 3D の Vector3(x, 高さ, y)に置く。
# 画面の上(-z)がロジックの -y(2D の上)と同じ向きになる
const WorldMaterial = preload("res://view/3d/WorldMaterial.gd")

# 世界が曲がって下がった分だけ、画面の外の物も描く候補に入れる(m)。
# 入れないと、本来の位置が画面の外にある物が、曲がって画面に入ってくるときに消えて見える
const BEND_CULL_MARGIN := 40.0
const STRIP_SEGMENT := 2.0  # 長い帯を分ける長さ(m)。頂点がないと曲がらない
const GROUND_LAYER := 2     # 地面と区画の描画レイヤー。小屋の部屋の明かりは、これを照らさない(開いたドアから外へ漏れないように)

static func at(p: Vector2, height := 0.0) -> Vector3:
	return Vector3(p.x, height, p.y)

# 単色のマテリアル。トゥーン(光と影を色の面で塗り分ける)で、照りはない。奥へ丸く曲がる。
# alpha < 1 なら半透明、unshaded なら光の影響を受けない(印・線用)
static func mat(c: Color, unshaded := false, emission := 0.0) -> WorldMaterial:
	var m := WorldMaterial.new(c, unshaded)
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
	mi.extra_cull_margin = BEND_CULL_MARGIN
	return mi

# 地面に貼る細長い平らな帯(a から b まで、幅 width、地面から y + height の高さ)。境界線・メルカバ用。
# 側面があると輪郭線が点線になって出るので、厚みを持たせない
static func strip(a: Vector2, b: Vector2, width: float, height: float, material: Material, y := 0.0) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(a.distance_to(b) + width, width)
	plane.subdivide_width = int(plane.size.x / STRIP_SEGMENT)
	var mi := mesh_node(plane, material, at((a + b) * 0.5, y + height))
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

# 地面に置く円盤(中心 c、半径 r、厚さ h、下面の高さ y)。水面・岸用
static func disc(c: Vector2, r: float, h: float, material: Material, y := 0.0) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = h
	cyl.radial_segments = 48
	cyl.rings = 1
	var mi := mesh_node(cyl, material, at(c, y + h * 0.5))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func clear_children(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()
