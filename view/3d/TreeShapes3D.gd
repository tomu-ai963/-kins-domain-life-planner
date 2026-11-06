extends RefCounted

# ── 木の形を作る(見た目の部品だけで、ルールは持たない) ─────────────────
# 樹冠と枝は「中心が原点で、幅・高さが 1 の箱」に収まる形で作り、TreesView3D が scale で大きさを決める。
# 幹は y = -0.5〜0.5、太さ 1 の円柱と同じ大きさ。
# 木ごとに違って見えるよう、樹種ごとに VARIANTS 通りの形を作る。形は乱数の種で決まるので毎回同じ。
# 頂点の色は明るさの倍率(1 = そのままの色)。材質の vertex_color_use_as_albedo で効く
const VARIANTS := 3

const LUMP_SEGMENTS := 16  # 葉のかたまりの細かさ。木が増えても重くならず、輪郭線が角ばらないところ
const LUMP_RINGS := 8

# 丸い樹冠: count = かたまりの数 / size = かたまりの半径の範囲 / core = 隙間を埋める芯の半径
const ROUND := {
	"birch": {"count": 10, "size": [0.15, 0.21], "core": 0.30, "branches": 6, "branch_thick": 0.012},
	"apple": {"count": 8, "size": [0.20, 0.27], "core": 0.33, "branches": 5, "branch_thick": 0.024},
	"cherry": {"count": 9, "size": [0.17, 0.23], "core": 0.31, "branches": 5, "branch_thick": 0.022},
	"plum": {"count": 11, "size": [0.14, 0.20], "core": 0.32, "branches": 6, "branch_thick": 0.018},
	"pear": {"count": 9, "size": [0.17, 0.24], "core": 0.30, "branches": 4, "branch_thick": 0.024},
}
# 針葉樹の段: 下から上へ、段ごとに細くなる
const CEDAR_TIERS := 5
const CEDAR_RIM_WAVE := 0.07
const CEDAR_RIM_DROOP := 0.018  # 縁の波に合わせて上下にも揺らす(枝先が垂れて見える)

# 頂点をためて ArrayMesh にする。面の向きは法線から決めるので、呼ぶ側は順番を気にしなくてよい
class MeshBuilder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func vertex(p: Vector3, n: Vector3, tint: float) -> int:
		verts.append(p)
		normals.append(n)
		colors.append(Color(tint, tint, tint))
		return verts.size() - 1

	func tri(a: int, b: int, c: int) -> void:
		var face := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		if face.length_squared() < 1e-12:
			return  # 球の極にできるつぶれた三角形
		# Godot は表から見て時計回りが表面
		if face.dot(normals[a] + normals[b] + normals[c]) > 0.0:
			indices.append_array([a, c, b])
		else:
			indices.append_array([a, b, c])

	func quad(a: int, b: int, c: int, d: int) -> void:
		tri(a, b, c)
		tri(b, d, c)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m

static func _rng(species: String, variant: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = species.hash() + variant * 7919
	return rng

# 樹冠。{"mesh": 形, "anchors": 実を付ける場所(かたまりの表面)}
static func crown(species: String, variant: int) -> Dictionary:
	if species == "cedar":
		return {"mesh": _cedar_crown(variant), "anchors": []}
	return _round_crown(species, variant)

static func _round_crown(species: String, variant: int) -> Dictionary:
	var spec: Dictionary = ROUND[species]
	var rng := _rng(species, variant)
	var b := MeshBuilder.new()
	var anchors: Array[Vector3] = []
	_add_lump(b, Vector3.ZERO, Vector3.ONE * spec.core, 0.78, rng.randf() * TAU)
	var spin := rng.randf() * TAU
	for i in range(spec.count):
		# 上に寄せて、らせん状に散らす(下は幹が見えるように少なめ)
		var t := (float(i) + 0.5) / float(spec.count)
		var up := lerpf(-0.55, 0.95, t)
		var angle := spin + float(i) * 2.399 + rng.randf_range(-0.4, 0.4)
		var flat := sqrt(1.0 - up * up)
		var dir := Vector3(flat * cos(angle), up, flat * sin(angle))
		var size := rng.randf_range(spec.size[0], spec.size[1])
		var center := dir * (0.5 - size)  # かたまりの外側が箱にちょうど収まる
		var tint := clampf(lerpf(0.82, 1.0, (up + 0.55) / 1.5) + rng.randf_range(-0.04, 0.04), 0.0, 1.0)
		_add_lump(b, center, Vector3.ONE * size, tint, rng.randf() * TAU)
		if up > -0.2:
			anchors.append(center + dir * size)
	return {"mesh": b.commit(), "anchors": anchors}

# 葉のかたまり 1 つ: 球の表面を少し波打たせる。法線は球のままにして、光の当たり方はなめらかに保つ
static func _add_lump(b: MeshBuilder, center: Vector3, radius: Vector3, tint: float, phase: float) -> void:
	var first := b.verts.size()
	for i in range(LUMP_RINGS + 1):
		var theta := PI * float(i) / float(LUMP_RINGS)
		for j in range(LUMP_SEGMENTS + 1):
			var phi := TAU * float(j) / float(LUMP_SEGMENTS)
			var dir := Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
			# 極では phi に関係なく同じ点になるよう sin(theta) を掛ける。整数倍の波なので継ぎ目も閉じる
			var wobble := 1.0 + 0.09 * sin(theta) * sin(3.0 * phi + phase) * sin(2.0 * theta + phase)
			b.vertex(center + dir * radius * wobble, (dir / radius).normalized(), tint)
	for i in range(LUMP_RINGS):
		for j in range(LUMP_SEGMENTS):
			var a := first + i * (LUMP_SEGMENTS + 1) + j
			var c := a + LUMP_SEGMENTS + 1
			b.quad(a, a + 1, c, c + 1)

# シベリア杉: 縁が波打った、垂れた傘を重ねる
static func _cedar_crown(variant: int) -> ArrayMesh:
	var rng := _rng("cedar", variant)
	var b := MeshBuilder.new()
	for t in range(CEDAR_TIERS):
		var f := float(t) / float(CEDAR_TIERS - 1)
		var rim_y := lerpf(-0.5, 0.16, f) + rng.randf_range(-0.012, 0.012)
		var apex_y := 0.5 if t == CEDAR_TIERS - 1 else rim_y + 0.34
		var radius := lerpf(0.44, 0.15, f) * rng.randf_range(0.97, 1.03)
		_add_tier(b, rim_y, apex_y, radius, lerpf(0.82, 1.0, f), rng)
	return b.commit()

static func _add_tier(b: MeshBuilder, rim_y: float, apex_y: float, radius: float, tint: float, rng: RandomNumberGenerator) -> void:
	const SEGMENTS := 60  # 波 1 つを 5 分割以上で描いて、縁を丸くする
	const STEPS := 3  # 頂点から縁まで。少しふくらませて、ただの円錐に見えないように
	var waves := rng.randi_range(9, 12)
	var phase := rng.randf() * TAU
	var first := b.verts.size()
	var height := apex_y - rim_y
	for s in range(STEPS + 1):
		var along := float(s) / float(STEPS)
		for j in range(SEGMENTS + 1):
			var phi := TAU * float(j) / float(SEGMENTS)
			var wave := sin(float(waves) * phi + phase)
			var r := radius * pow(along, 0.85) * (1.0 + CEDAR_RIM_WAVE * along * wave)
			var y := apex_y - height * along + CEDAR_RIM_DROOP * along * wave
			var n := Vector3(cos(phi) * height, radius, sin(phi) * height).normalized()
			b.vertex(Vector3(cos(phi) * r, y, sin(phi) * r), n, tint)
	for s in range(STEPS):
		for j in range(SEGMENTS):
			var a := first + s * (SEGMENTS + 1) + j
			var c := a + SEGMENTS + 1
			b.quad(a, a + 1, c, c + 1)
	# 底をふさぐ(太陽が低いときの影に穴があかないように)
	var rim := first + STEPS * (SEGMENTS + 1)
	var hub := b.vertex(Vector3(0.0, rim_y + height * 0.2, 0.0), Vector3.DOWN, tint)
	for j in range(SEGMENTS):
		var p := b.verts[rim + j]
		var q := b.verts[rim + j + 1]
		var ia := b.vertex(p, Vector3.DOWN, tint)
		var ib := b.vertex(q, Vector3.DOWN, tint)
		b.tri(hub, ia, ib)

# 幹: 先細りの円柱。頂点の色で樹皮のむらを付ける(白樺は黒い節)
static func trunk(species: String, variant: int) -> ArrayMesh:
	const SEGMENTS := 10
	const ROWS := 12
	const TOP_RADIUS := 0.3
	const BOTTOM_RADIUS := 0.5
	var rng := _rng(species + "_bark", variant)
	var b := MeshBuilder.new()
	for row in range(ROWS):
		var y0 := -0.5 + float(row) / float(ROWS)
		var y1 := y0 + 1.0 / float(ROWS)
		var r0 := lerpf(BOTTOM_RADIUS, TOP_RADIUS, y0 + 0.5)
		var r1 := lerpf(BOTTOM_RADIUS, TOP_RADIUS, y1 + 0.5)
		for j in range(SEGMENTS):
			var p0 := TAU * float(j) / float(SEGMENTS)
			var p1 := TAU * float(j + 1) / float(SEGMENTS)
			var tint := rng.randf_range(0.86, 1.0)
			if species == "birch" and rng.randf() < 0.14:
				tint = 0.22
			# 面ごとに頂点を分けて、色が隣へにじまないようにする。法線はなめらかなまま
			var n0 := Vector3(cos(p0), 0.0, sin(p0))
			var n1 := Vector3(cos(p1), 0.0, sin(p1))
			var a := b.vertex(Vector3(n0.x * r0, y0, n0.z * r0), n0, tint)
			var c := b.vertex(Vector3(n1.x * r0, y0, n1.z * r0), n1, tint)
			var d := b.vertex(Vector3(n0.x * r1, y1, n0.z * r1), n0, tint)
			var e := b.vertex(Vector3(n1.x * r1, y1, n1.z * r1), n1, tint)
			b.quad(a, c, d, e)
	return b.commit()

# 冬の落葉樹の枝。幹の途中から外へ伸びて、2 回ずつ分かれる
static func bare_branches(species: String, variant: int) -> ArrayMesh:
	var spec: Dictionary = ROUND[species]
	var rng := _rng(species + "_twig", variant)
	var b := MeshBuilder.new()
	var spin := rng.randf() * TAU
	for i in range(spec.branches):
		var t := (float(i) + 0.5) / float(spec.branches)
		var start := Vector3(0.0, lerpf(-0.45, 0.30, t), 0.0)
		var angle := spin + float(i) * 2.399
		var dir := Vector3(cos(angle), lerpf(0.5, 1.3, t), sin(angle)).normalized()
		_add_branch(b, start, dir, 0.24, spec.branch_thick, 2, rng)
	return b.commit()

static func _add_branch(b: MeshBuilder, from: Vector3, dir: Vector3, length: float, thick: float, depth: int, rng: RandomNumberGenerator) -> void:
	var to := from + dir * length
	if to.length() > 0.5:
		to = to.normalized() * 0.5
	if to.distance_to(from) < 0.02:
		return
	_add_tube(b, from, to, thick, thick * 0.7)
	if depth == 0:
		return
	var side := dir.cross(Vector3(0.3, 0.2, 1.0)).normalized()
	for s in [-1.0, 1.0]:
		var spread: Vector3 = side.rotated(dir, rng.randf() * 1.2) * s * 0.75
		var next := (dir + spread + Vector3.UP * 0.2).normalized()
		_add_branch(b, to, next, length * 0.72, thick * 0.7, depth - 1, rng)

# from から to までの細い 5 角柱
static func _add_tube(b: MeshBuilder, from: Vector3, to: Vector3, r0: float, r1: float) -> void:
	const SIDES := 5
	var axis := (to - from).normalized()
	var u := axis.cross(Vector3(0.31, 0.17, 0.93)).normalized()
	var v := axis.cross(u)
	var first := b.verts.size()
	for j in range(SIDES + 1):
		var a := TAU * float(j) / float(SIDES)
		var n := u * cos(a) + v * sin(a)
		b.vertex(from + n * r0, n, 1.0)
		b.vertex(to + n * r1, n, 1.0)
	for j in range(SIDES):
		var i := first + j * 2
		b.quad(i, i + 1, i + 2, i + 3)

# 苗木: 細い茎に小さな葉が 3 枚。高さ約 1(根元が原点)
static func sprout() -> ArrayMesh:
	var b := MeshBuilder.new()
	_add_tube(b, Vector3.ZERO, Vector3(0.0, 0.8, 0.0), 0.05, 0.035)
	_add_lump(b, Vector3(-0.24, 0.72, 0.0), Vector3(0.28, 0.09, 0.15), 1.0, 0.0)
	_add_lump(b, Vector3(0.24, 0.80, 0.05), Vector3(0.28, 0.09, 0.15), 1.0, 2.0)
	_add_lump(b, Vector3(0.0, 0.92, -0.10), Vector3(0.14, 0.08, 0.24), 1.0, 4.0)
	return b.commit()
