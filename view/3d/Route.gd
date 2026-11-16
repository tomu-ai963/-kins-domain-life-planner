extends RefCounted

# ── 回り込む道(訪問者と家族で共通) ─────────────────────────────
# 避けるもの(Rect2 の並び)を受け取り、from から to まで、ぶつからない道(通る点の並び。最後が to)を返す。
# 近いものから順に避け、角を回って進む。ROUTE_TURNS 回曲がっても抜けられなければ、そのまま行き先へ向かう
const ROUTE_TURNS := 12  # 道を曲がる回数の上限(木が多いときのため)

static func plan(from: Vector2, to: Vector2, obstacles: Array) -> Array:
	var points := []
	var at := from
	for _i in range(ROUTE_TURNS):
		var corner = detour(at, to, obstacles)
		if corner == null:
			break
		points.append(corner)
		at = corner
	points.append(to)
	return points

# a → b がふさがっていれば、回り込む角を返す。ふさがっていなければ null
static func detour(a: Vector2, b: Vector2, obstacles: Array):
	# 近いものから順に見る(遠くの木を先に避けると、手前を通り抜けてしまう)
	var list: Array = obstacles.duplicate()
	list.sort_custom(func(p, q): return p.get_center().distance_to(a) < q.get_center().distance_to(a))
	for r in list:
		# 始まりや行き先が範囲の中なら、その範囲は避けようがない(そばに立っている木など)
		if r.has_point(a) or r.has_point(b) or not crosses(a, b, r.grow(-0.05)):
			continue
		var best = null
		var best_len := INF
		for c in [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]:
			if c.distance_to(a) < 0.1 or crosses(a, c, r.grow(-0.05)):
				continue
			var length: float = a.distance_to(c) + c.distance_to(b)
			if length < best_len:
				best_len = length
				best = c
		if best != null:
			return best
	return null

static func crosses(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var corners := [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]
	for i in range(4):
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return true
	return false

# 進む向き dir のまま進むと、avoid の点(プレイヤーやほかの人)に radius より近づくなら、横へよける向きを返す
static func sidestep(pos: Vector2, dir: Vector2, avoid: Array, radius: float) -> Vector2:
	for p in avoid:
		var to_p: Vector2 = p - pos
		if to_p.length() >= radius or to_p.length() < 0.001 or dir.dot(to_p) <= 0.0:
			continue
		# 進む向きのうち、相手へ向かう分を消す。まっすぐ向かっていたら右へ
		var toward: Vector2 = to_p.normalized()
		var side: Vector2 = dir - toward * dir.dot(toward)
		if side.length() < 0.1:
			side = Vector2(-toward.y, toward.x)
		return side.normalized()
	return dir
