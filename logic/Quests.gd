extends RefCounted

# ── 段階クエスト(原作『アナスタシア』の一族の土地づくり) ────────────
# 4 つは順番がなく、条件を満たしたものから達成する(2026-11-11 とむ決定。前は順番に 1 つずつだった)。
# 達成したものは、あとで木を抜いても戻らない。4 つそろうと「愛の空間」が完成する。
# 完成のあとの長い目標(2026-11-11 とむ決定): 生き物の図鑑(土地と池に来た生き物をそろえる)と、木の節目(樹種ごとに
# いちばん年上の木が樹齢 10・25・50・100 年になる)。どちらも完成の前から数えている。
# 数えるのは根付いた木だけ(芽が出る前の種は数えない)。
# 文言は Main、見た目は view/ が決める(ここは id と数だけ)。座標の単位は m
const SaveRead = preload("res://logic/SaveRead.gd")
const Forest = preload("res://logic/Forest.gd")
const Land = preload("res://logic/Land.gd")
const Pond = preload("res://logic/Pond.gd")
const Wildlife = preload("res://logic/Wildlife.gd")

signal changed

const QUESTS := ["hedge", "garden", "pond", "family_cedar"]

const HALF := 50.0               # ドメインの半幅(m)
const HEDGE_BAND := 3.0          # 生垣とみなす帯: 境界から内側 3m
const HEDGE_SEGMENT := 10.0      # 周囲を 10m ごとに区切る
const HEDGE_SEGMENTS := 40       # 周囲 400m / 10m
const GARDEN_PLOTS := 4          # 菜園は区画 4 つ
const FAMILY_CEDAR_RADIUS := 5.0 # 中心から 5m 以内の家族の木(family_tree。シベリア杉・スギ・ガジュマル)
const MILESTONE_AGES := [10, 25, 50, 100]  # 木の節目の樹齢(1 現実日 = 1 年)

var done := []                   # 達成したクエストの id(達成した順)
var milestones := []             # 迎えた木の節目 "樹種:樹齢"(例 "birch:10")
var guide_done := false          # 生き物の図鑑がそろったことを知らせたか
var forest: Forest               # GameWorld が設定する
var land: Land
var pond: Pond
var wildlife: Wildlife

func is_done(id: String) -> bool:
	return id in done

func is_complete() -> bool:
	return done.size() >= QUESTS.size()

# まだ達成していないクエスト(QUESTS の順)
func remaining() -> Array:
	return QUESTS.filter(func(id): return not is_done(id))

# まだのうち、いちばん前のもの。完成していれば ""
func current_id() -> String:
	var left := remaining()
	return "" if left.is_empty() else left[0]

# 生垣の 40 区画それぞれに木があるか。角の近くの木は 2 辺の区画を同時に埋める
func hedge_filled() -> Array:
	var filled := []
	filled.resize(HEDGE_SEGMENTS)
	filled.fill(false)
	for t in forest.trees:
		if not forest.is_established(t):
			continue
		var p: Vector2 = t.pos
		if absf(p.x) > HALF or absf(p.y) > HALF:
			continue
		# 周囲を時計回りに 1 本の線とみなした位置(m): 上辺 → 右辺 → 下辺 → 左辺
		if p.y - (-HALF) <= HEDGE_BAND:
			_fill(filled, p.x + HALF)
		if HALF - p.x <= HEDGE_BAND:
			_fill(filled, 2 * HALF + (p.y + HALF))
		if HALF - p.y <= HEDGE_BAND:
			_fill(filled, 4 * HALF + (HALF - p.x))
		if p.x - (-HALF) <= HEDGE_BAND:
			_fill(filled, 6 * HALF + (HALF - p.y))
	return filled

func _fill(filled: Array, s: float) -> void:
	filled[clampi(floori(s / HEDGE_SEGMENT), 0, HEDGE_SEGMENTS - 1)] = true

# [いまの数, 目標の数]
# 「家族の木」のクエストで中心に植える木(その土地の木。県を選ぶ前はシベリア杉)
func family_tree() -> String:
	return forest.region.family_tree() if forest.region != null else "cedar"

func progress(id: String) -> Array:
	match id:
		"hedge":
			var n := 0
			for f in hedge_filled():
				if f:
					n += 1
			return [n, HEDGE_SEGMENTS]
		"garden":
			return [mini(land.plots.size(), GARDEN_PLOTS), GARDEN_PLOTS]
		"pond":
			return [1 if pond.is_dug() else 0, 1]  # 掘り終えたら達成(水はあとからたまる)
		"family_cedar":
			for t in forest.trees:
				if t.species == family_tree() and forest.is_established(t) and t.pos.length() <= FAMILY_CEDAR_RADIUS:
					return [1, 1]
			return [0, 1]
	return [0, 1]

# 条件を満たしたクエストを達成にする(どれからでもよい)。
# 新しく達成した id の配列を返す。完成したら最後に "complete" が入る
func advance() -> Array:
	var now := []
	for id in remaining():
		var p: Array = progress(id)
		if p[0] >= p[1]:
			done.append(id)
			now.append(id)
	if not now.is_empty() and is_complete():
		now.append("complete")
	if not now.is_empty():
		changed.emit()
	return now

# ── 生き物の図鑑 ──
# 図鑑に載る生き物の id(この土地にいる生き物と、池の生き物。県を選ぶ前は今までの生き物)
func guide_ids() -> Array:
	var ids: Array = wildlife.local_species() if wildlife != null else Wildlife.SPECIES.keys().filter(func(id): return not Wildlife.SPECIES[id].get("regional", false))
	ids.append_array(Pond.CREATURES.keys())
	return ids

func guide_seen() -> Array:
	var seen := []
	if wildlife != null:
		seen.append_array(wildlife.seen)
	if pond != null:
		seen.append_array(pond.seen)
	return guide_ids().filter(func(id): return id in seen)

func guide_missing() -> Array:
	var seen := guide_seen()
	return guide_ids().filter(func(id): return not (id in seen))

# 図鑑がそろったら 1 回だけ true(知らせる用)
func take_guide_complete() -> bool:
	if guide_done or not guide_missing().is_empty():
		return false
	guide_done = true
	return true

# ── 木の節目 ──
# 節目の数: この土地で育つ樹種(と、土地に植わっている樹種)× 節目の樹齢
func milestone_total() -> int:
	var n := 0
	for sp in Forest.SPECIES:
		if forest.grows_here(sp) or forest.trees.any(func(t): return t.species == sp):
			n += 1
	return n * MILESTONE_AGES.size()

# 樹種ごとの、いちばん年上の根付いた木の樹齢(現実の樹齢)
func oldest_ages() -> Dictionary:
	var ages := {}
	for t in forest.trees:
		if forest.is_established(t):
			ages[t.species] = maxf(float(ages.get(t.species, 0.0)), forest.real_age_years(t))
	return ages

# 新しく迎えた節目を記録して返す([{species, age}])。quiet なら記録だけして返さない(節目の記録がない古いセーブ用)
func check_milestones(quiet := false) -> Array:
	var reached := []
	var ages := oldest_ages()
	for sp in Forest.SPECIES:
		for age in MILESTONE_AGES:
			var key := "%s:%d" % [sp, age]
			if float(ages.get(sp, 0.0)) >= age and not (key in milestones):
				milestones.append(key)
				reached.append({"species": sp, "age": age})
	if not reached.is_empty():
		changed.emit()
	return [] if quiet else reached

# 次に迎える節目 {species, age, days}(いちばん近いもの)。なければ空
func next_milestone() -> Dictionary:
	var best := {}
	var ages := oldest_ages()
	for sp in ages:
		for age in MILESTONE_AGES:
			if "%s:%d" % [sp, age] in milestones:
				continue
			var days := ceili(age - float(ages[sp]))
			if best.is_empty() or days < int(best.days):
				best = {"species": sp, "age": age, "days": days}
			break
	return best

# 生垣の区画 i の真ん中、境界から 1.5m 内側の点
func segment_center(i: int) -> Vector2:
	var s := (i + 0.5) * HEDGE_SEGMENT
	var inset := HEDGE_BAND * 0.5
	if s < 2 * HALF:
		return Vector2(-HALF + s, -HALF + inset)
	s -= 2 * HALF
	if s < 2 * HALF:
		return Vector2(HALF - inset, -HALF + s)
	s -= 2 * HALF
	if s < 2 * HALF:
		return Vector2(HALF - s, HALF - inset)
	s -= 2 * HALF
	return Vector2(-HALF + inset, HALF - s)

# ── セーブ用 ──────────────────────────────────────────────
func to_save() -> Dictionary:
	return {"done": done, "milestones": milestones, "guide_done": guide_done}

func from_save(d: Dictionary) -> void:
	done = []
	var saved = d.get("done", null)
	if typeof(saved) == TYPE_ARRAY:
		done = SaveRead.ids(saved, QUESTS)
	else:
		# 順番に進めていたころのセーブ(stage まで達成した)
		for i in range(clampi(SaveRead.whole(d, "stage"), 0, QUESTS.size())):
			done.append(QUESTS[i])
	var ms = d.get("milestones", null)
	milestones = []
	for key in SaveRead.list(ms):
		if typeof(key) == TYPE_STRING and not (key in milestones):
			milestones.append(key)
	guide_done = SaveRead.flag(d, "guide_done")
	changed.emit()
	# 節目の記録がないセーブ(2026-11-11 より前)は、もう迎えた節目を黙って記録する(開いた日に昔の節目をまとめて知らせない)
	if typeof(ms) != TYPE_ARRAY and forest != null:
		check_milestones(true)
