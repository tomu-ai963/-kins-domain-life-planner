extends RefCounted

# ── 土地の外の川(描画を持たない) ──────────────────────────────────
# 2026-11-11 とむ「土地の外に川をつくる」→ 2026-11-15 とむ決定: 川で水を汲めるようにし、田んぼで米も育てる。
# 一族の土地の北の境界の外を、東から西へ小川が流れる。外の土地でできるのは種を拾うことだけ(logic/Wilds.gd)だが、
# 川で水を汲むことだけは例外にする。川の水は減らず、流れているので冬も凍らない。
# 川のそばでは、ジョウロに汲め、エンジンポンプで足元から WATER_RADIUS までの区画と木にまとめて水をやれる。
# 田んぼ(米の区画)は、川か池から水が引ける範囲(PADDY_REACH)にだけ作れる(Garden.CROPS の paddy)。
# 川は県を選んでから現れる(外の林と同じ)。形は決まった式で、保存しない。北は -y。座標の単位は m
const Forest = preload("res://logic/Forest.gd")

const CENTER_Y := -58.5     # 川の中心の線の、おおよその位置(北の境界 -50m の 8m あまり外)
const BEND := 3.0           # 蛇行の幅(m)
const BEND_FREQUENCY := 0.05  # 蛇行の細かさ(rad/m)。1 回りがおよそ 125m
const HALF_WIDTH := 1.6     # 川の幅の半分(m)
const REACH := 2.0          # 岸からこの距離までなら汲める(池と同じ)
const WATER_RADIUS := 20.0  # ポンプで、足元からまとめて水をやれる距離(m)。池・井戸と同じ
const PADDY_REACH := 20.0   # 田んぼを作れる、川の中心の線からの距離(m)。ポンプで水が届く範囲
const EXTENT := 80.0        # 東西の端(歩ける端 78m の少し外まで流れる)
const STEP := 2.0           # 形の点の間隔(m)

var forest: Forest  # GameWorld が設定する(県を選んだか見る)

# 川があるか(県を選んでから)
func exists() -> bool:
	return forest != null and forest.region != null

# x の位置での川の中心の y
static func center_y(x: float) -> float:
	return CENTER_Y + BEND * sin(x * BEND_FREQUENCY + 0.7)

# 川の中心の線の点(西から東へ STEP おき)。見た目と距離に使う
static func points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x := -EXTENT
	while x <= EXTENT + 0.01:
		pts.append(Vector2(x, center_y(x)))
		x += STEP
	return pts

# 川の中心の線までの距離(m)。川がなければ INF
func distance_to(pos: Vector2) -> float:
	if not exists():
		return INF
	return line_distance(pos)

static func line_distance(pos: Vector2) -> float:
	var pts := points()
	var best := INF
	for i in range(pts.size() - 1):
		best = minf(best, pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, pts[i], pts[i + 1])))
	return best

# 川のそば(岸から REACH まで。川の中に立っていてもよい)か
func is_beside(pos: Vector2) -> bool:
	return distance_to(pos) <= HALF_WIDTH + REACH

# 川の上か(外の林の木や、ほかの物を置かない)。margin は岸からさらに空ける幅
func covers(pos: Vector2, margin := 0.0) -> bool:
	return distance_to(pos) <= HALF_WIDTH + margin

# 区画(中心 c)に田んぼを作れるほど川が近いか
func feeds_paddy(c: Vector2) -> bool:
	return distance_to(c) <= PADDY_REACH
