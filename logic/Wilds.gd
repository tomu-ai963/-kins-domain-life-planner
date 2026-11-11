extends RefCounted

# ── 一族の土地の外の、自然の林(描画を持たない) ─────────────────────
# 境界(±50m)の外から歩ける端(Player3D.WALK_LIMIT = 78m)までの帯に、その土地に自生する木の林がある(2026-11-11 とむ決定)。
# 外の林でできるのは種を拾うことだけ。種は木ごとに決まった日にだけ根元に落ちる(樹種ごとに、実る月のうち年 DROP_DAYS 日)。
# その日を逃すと拾えない。落ちた種は Forest.pickups に入れるので、拾い方・見た目・保存は自分の木の種と同じ。
# 外の林でしか手に入らない木(Forest.SPECIES の wild_only)の種は、市場で売れるが買えない。自分の土地に植えて育てれば種を増やせる。
# 林の木の場所・樹種・樹齢は、県(気候区分)から毎回同じに決まるので保存しない。座標の単位は m
const Forest = preload("res://logic/Forest.gd")

const BAND_IN := 54.0        # 林の内側の端(境界の 4m 外)
const BAND_OUT := 75.0       # 林の外側の端(歩ける端の 3m 内)
const TREE_COUNT := 56       # 林の木の数
const MIN_GAP := 4.5         # 木と木の間
const MARKET_CLEAR := 10.0   # 市場のまわりは空ける
const PATH_CLEAR := 6.0      # 南の小道(市場への道)の幅の半分
const MARKET_POS := Vector2(0, 56)  # Market.POS と同じ(Market は Forest を読むので、ここでは持たない)
const AGE_MIN := 30.0        # 林の木の樹齢
const AGE_MAX := 90.0
const DROP_DAYS := 3         # 樹種ごとの、1 年で種が落ちる日の数
const DROP_SPREAD := 1.8     # 種は根元からこの距離に落ちる

var forest: Forest   # GameWorld が設定する
var trees := []      # [{pos: Vector2, species, age: float}]
var _built_for := "-"  # 林を作ったときの県("-" = まだ)
var last_drops := []   # 今日の確認で種が落ちた樹種(知らせる用・保存しない)

# 林に生える樹種(この土地で自然に育つ木)
func species_here() -> Array:
	if forest == null or forest.region == null:
		return []
	return Forest.SPECIES.keys().filter(func(sp): return Forest.SPECIES[sp].get("wild", false) and forest.grows_here(sp))

# 県が変わっていたら林を作り直す(県を選ぶ前は林がない)
func refresh() -> void:
	var pref: String = forest.region.pref if forest != null and forest.region != null else ""
	if pref == _built_for:
		return
	_built_for = pref
	trees.clear()
	var kinds := species_here()
	if kinds.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = ("wilds:" + forest.region.zone_id()).hash()
	var tries := 0
	while trees.size() < TREE_COUNT and tries < TREE_COUNT * 40:
		tries += 1
		var pos := Vector2(rng.randf_range(-BAND_OUT, BAND_OUT), rng.randf_range(-BAND_OUT, BAND_OUT))
		if maxf(absf(pos.x), absf(pos.y)) < BAND_IN:
			continue
		if pos.distance_to(MARKET_POS) < MARKET_CLEAR or (pos.y > 0.0 and absf(pos.x) < PATH_CLEAR):
			continue
		if trees.any(func(t): return t.pos.distance_to(pos) < MIN_GAP):
			continue
		# 樹種は順に回して、どの木も林にあるようにする
		trees.append({"pos": pos, "species": kinds[trees.size() % kinds.size()], "age": rng.randf_range(AGE_MIN, AGE_MAX)})

# その年に、その樹種の種が落ちる日(通し番号)。実る月(drop_months)の中から DROP_DAYS 日を選ぶ。同じ年・樹種なら必ず同じ
func drop_days_in(species: String, year: int) -> Array:
	var days := []
	for m in Forest.SPECIES[species].get("drop_months", []):
		var first := int(Time.get_unix_time_from_datetime_string("%04d-%02d-01" % [year, m]) / 86400.0)
		var next_month := "%04d-%02d-01" % [year + (1 if m == 12 else 0), 1 if m == 12 else m + 1]
		var last := int(Time.get_unix_time_from_datetime_string(next_month) / 86400.0)
		for d in range(first, last):
			days.append(d)
	if days.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = ("drop:%s:%d:%s" % [species, year, forest.region.zone_id() if forest.region != null else ""]).hash()
	var picked := []
	while picked.size() < mini(DROP_DAYS, days.size()):
		var d: int = days[rng.randi_range(0, days.size() - 1)]
		if not (d in picked):
			picked.append(d)
	picked.sort()
	return picked

# その日に種が落ちる、林にある樹種
func dropping_on(day: int) -> Array:
	refresh()
	var year := int(Forest.date_of_day(day).substr(0, 4))
	var present := {}
	for t in trees:
		present[t.species] = true
	return present.keys().filter(func(sp): return day in drop_days_in(sp, year))

# 日付が変わったときに呼ぶ(Forest.check_new_day のあと。前の日の種はそこで片づく)。今日落ちる種を林の根元に置く
func drop_today() -> void:
	last_drops = dropping_on(forest.day_number())
	if last_drops.is_empty():
		return
	for i in range(trees.size()):
		var t: Dictionary = trees[i]
		if not (t.species in last_drops):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%s:%d" % [forest.today(), i]).hash()
		var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.0, DROP_SPREAD)
		forest.pickups.append({"pos": t.pos + off, "species": t.species, "amount": int(Forest.SPECIES[t.species].seed_drop)})
	forest.dirty.emit()
	forest.changed.emit()

# pos から max_dist 以内の林の木(なければ {})
func tree_near(pos: Vector2, max_dist: float) -> Dictionary:
	refresh()
	var best := {}
	var best_d := max_dist
	for t in trees:
		var d: float = t.pos.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = t
	return best

# その樹種の、今日以降で次に種が落ちる日(通し番号)。今年と来年から探す。なければ -1
func next_drop(species: String, from_day: int) -> int:
	var year := int(Forest.date_of_day(from_day).substr(0, 4))
	for y in [year, year + 1]:
		for d in drop_days_in(species, y):
			if d >= from_day:
				return d
	return -1
