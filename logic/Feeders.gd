extends RefCounted

# ── 鳥の餌台(描画を持たない) ───────────────────────────────────
# 丸太 1 本で餌台を立て、秋と冬に白樺の種を置くと鳥が集まる(冬の餌台はロシアの冬の習慣)。
# 白樺は秋と冬に根元へ種を落とすので、自分の木の種がそのまま餌になる。
# 春と夏は、畑の野菜を 1kg 置ける(秋と冬も、種がなければ野菜)。餌を置くと生き物との仲良し度が上がる(logic/Pests.gd。2026-11-15)。
# 文言は Main、鳥の数は Wildlife、見た目は view/ が決める。座標の単位は m
const SaveRead = preload("res://logic/SaveRead.gd")
const Forest = preload("res://logic/Forest.gd")
const Land = preload("res://logic/Land.gd")
const Cabin = preload("res://logic/Cabin.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const MAX_FEEDERS := 2     # 餌台の数の上限
const LOG_COST := 1        # 餌台 1 つに使う丸太(仮の数字)
const FEED_SEEDS := 3      # 1 回に置く白樺の種の粒数(仮の数字)
const OFFER_KG := 1        # 1 回に置く野菜(kg。仮の数字)
const KEEP_DAYS := 1       # 餌が残る日数。置いた日の翌日まで(夕方に置いても、次の昼に鳥を見られるように)
const FEED_SEASONS := ["autumn", "winter"]  # 餌を置く季節
const REACH := 2.0         # 餌台からこの距離までなら作業できる
const GAP := 2.0           # 餌台どうしの間
const TABLE_H := 1.13      # 餌を置く台の高さ(m)。鳥はここにとまる

var forest: Forest  # GameWorld が設定する
var land: Land
var cabin: Cabin
var bees = null     # GameWorld が設定する(置ける場所の決まりは巣箱と同じ)
var garden = null   # GameWorld が設定する(置く野菜は Garden の収穫物から)

var feeders := []   # [{pos: Vector2, fed_day: int(-1 = まだ), offered_day: int(野菜を置いた日。-1 = まだ)}]
var last_fed := {}  # 直前に作業した餌台(文言と動き用)
var last_offered := ""  # 直前に置いた野菜の kind(文言用)

func _commit() -> void:
	dirty.emit()
	changed.emit()

func feeder_near(pos: Vector2) -> Dictionary:
	for f in feeders:
		if f.pos.distance_to(pos) <= REACH:
			return f
	return {}

# 餌が残っているか
func is_fed(f: Dictionary) -> bool:
	var fed: int = int(f.fed_day)
	return fed >= 0 and forest.day_number() - fed <= KEEP_DAYS

func fed_today(f: Dictionary) -> bool:
	return int(f.fed_day) == forest.day_number()

func offered_today(f: Dictionary) -> bool:
	return int(f.get("offered_day", -1)) == forest.day_number()

# 置く野菜: 選んでいる野菜があればそれ、なければいちばん多く持っている野菜。なければ ""
func offer_kind(prefer := "") -> String:
	if garden == null:
		return ""
	if int(garden.produce.get(prefer, 0)) >= OFFER_KG:
		return prefer
	var best := ""
	for k in garden.produce:
		if int(garden.produce[k]) >= OFFER_KG and (best == "" or int(garden.produce[k]) > int(garden.produce[best])):
			best = k
	return best

func fed_count() -> int:
	return feeders.filter(func(f): return is_fed(f)).size()

func can_feed_now() -> bool:
	return forest.season in FEED_SEASONS

# 餌を足したほうがいい餌台の数(秋と冬だけ。日記用)
func hungry_count() -> int:
	if not can_feed_now():
		return 0
	return feeders.filter(func(f): return not is_fed(f)).size()

# 一度でも餌を置いたか(ヒント用)
func ever_fed() -> bool:
	return feeders.any(func(f): return int(f.fed_day) >= 0)

# 餌台に置く種の樹種(その土地の広葉樹の種。県を選ぶ前は白樺)
func feed_species() -> String:
	return forest.wind_seed()

# L: 近くに餌台がなければ front に立てる。あれば餌を置く(餌台ごとに 1 日 1 回)。
# 秋と冬は餌の種(feed_species)を置く。種がないときと、春と夏は、畑の野菜を 1kg 置く(prefer は選んでいる野菜)
# 結果: placed / too_many / blocked / no_wood / fed / offered / full / not_season(春と夏で野菜がない) / no_seed(秋と冬で種も野菜もない)
func act(pos: Vector2, front = null, prefer := "") -> String:
	var near := feeder_near(pos)
	if near.is_empty():
		return _place(pos if front == null else front)
	last_fed = near
	if offered_today(near) or (fed_today(near) and can_feed_now()):
		return "full"
	var sp := feed_species()
	if can_feed_now() and int(forest.seeds.get(sp, 0)) >= FEED_SEEDS:
		forest.seeds[sp] = int(forest.seeds[sp]) - FEED_SEEDS
		near.fed_day = forest.day_number()
		_commit()
		return "fed"
	var kind := offer_kind(prefer)
	if kind == "":
		return "no_seed" if can_feed_now() else "not_season"
	garden.produce[kind] = int(garden.produce[kind]) - OFFER_KG
	near.offered_day = forest.day_number()
	last_offered = kind
	_commit()
	garden.changed.emit()
	return "offered"

func _place(pos: Vector2) -> String:
	if feeders.size() >= MAX_FEEDERS:
		return "too_many"
	if is_blocked(pos):
		return "blocked"
	if int(cabin.materials.log) < LOG_COST:
		return "no_wood"
	cabin.materials.log = int(cabin.materials.log) - LOG_COST
	cabin.clamp_own_logs()
	last_fed = {"pos": pos, "fed_day": -1, "offered_day": -1}
	feeders.append(last_fed)
	_commit()
	return "placed"

# そこに餌台を置けないか(区画・小屋・池・木・巣箱のそばと、土地の端)
func is_blocked(pos: Vector2) -> bool:
	if bees.is_blocked(pos):
		return true
	return covers(pos, GAP)

# その場所に餌台がかかるか(radius は調べる範囲)。区画や木を置くときに見る
func covers(pos: Vector2, radius := 0.6) -> bool:
	for f in feeders:
		if f.pos.distance_to(pos) < radius:
			return true
	return false

# 区画(中心 c)が餌台にかかるか
func blocks_plot(c: Vector2, half: float) -> bool:
	for f in feeders:
		if absf(f.pos.x - c.x) <= half + 0.3 and absf(f.pos.y - c.y) <= half + 0.3:
			return true
	return false

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	var list := []
	for f in feeders:
		list.append({"x": f.pos.x, "y": f.pos.y, "fed_day": f.fed_day, "offered_day": f.get("offered_day", -1)})
	return {"feeders": list}

func from_save(d: Dictionary) -> void:
	feeders.clear()
	for item in SaveRead.list(d.get("feeders")):
		var f := SaveRead.dict(item)
		var pos = SaveRead.point(f)
		if pos != null:
			feeders.append({"pos": pos, "fed_day": SaveRead.whole(f, "fed_day", -1), "offered_day": SaveRead.whole(f, "offered_day", -1)})
	changed.emit()
