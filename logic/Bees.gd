extends RefCounted

# ── 丸太の巣箱とはちみつ(描画を持たない) ───────────────────────────
# 自分の木を伐った丸太(Cabin.own_log_count。市場の丸太は使えない)で巣箱を作り、何日かかけてくり抜く。
# 蜂は、自然に入るのを待つ(春と夏だけ。日付で決まるので開き直しても同じ)か、フョードルさんに分けてもらう(Visitors)。
# 蜂が入ると、はちみつが日ごとにたまる。J で採って市場で売る。採っても蜂はいなくならない。
# 閉じているあいだの分も数える。文言は Main、値段は Market、見た目は view/ が決める。座標の単位は m
const SaveRead = preload("res://logic/SaveRead.gd")
const Forest = preload("res://logic/Forest.gd")
const Land = preload("res://logic/Land.gd")
const Garden = preload("res://logic/Garden.gd")
const Cabin = preload("res://logic/Cabin.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const MAX_HIVES := 3      # 巣箱の数の上限
const LOG_COST := 2       # 巣箱 1 つに使う丸太(細い丸太を束ねる。仮の数字)
const HOLLOW_DAYS := 3    # くり抜く日数(1 日 1 回)
const REACH := 2.0        # 巣箱からこの距離までなら作業できる
const CLEARANCE := 1.0    # 巣箱のまわりでこの距離に木などがあると置けない
const HIVE_GAP := 2.0     # 巣箱どうしの間
const EDGE_MARGIN := 3.0  # 境界からこの幅は生垣クエストのために空ける
const SWARM_CHANCE := 0.08  # 空の巣箱に、自然に蜂が入る確率(春と夏の 1 日あたり。2 週間に 1 回ほど)
const SWARM_SEASONS := ["spring", "summer"]  # 分蜂の季節(現実は春から初夏)
const SHARE_SEASONS := ["spring", "summer", "autumn"]  # フョードルさんが分けてくれる季節。秋はゲーム都合(次の春まで待たなくていいように)
const HONEY_RATE := {"spring": 0.5, "summer": 0.5, "autumn": 0.2, "winter": 0.0}  # 1 日にたまるはちみつ(kg)
const FLOWER_BONUS := 0.2  # 畑に野菜があると増える分(kg)
const COMB_MAX := 5.0     # 巣箱にためておける量(kg)
const MAX_CATCH_UP_DAYS := 365

var forest: Forest  # GameWorld が設定する
var land: Land
var garden: Garden
var cabin: Cabin
var taken_nearby := Callable()  # (pos, radius) -> bool。GameWorld が餌台の covers を設定する(餌台は巣箱を持つので、互いに持つと解放されない)

var hives := []        # [{pos: Vector2, days_done: int, last_worked, hollowed_day: int(-1 = まだ), occupied: bool, comb: float}]
var stock := {"honey": 0}  # 採ったはちみつ(kg)。市場で売る
var last_checked_day := 0  # はちみつと蜂の入りを数え終えた日
var last_arrivals := 0     # 今日の確認で自然に蜂が入った巣箱の数(知らせる用・保存しない)
var last_harvest := 0      # 直前に採ったはちみつ(kg)(文言用)

func _commit() -> void:
	dirty.emit()
	changed.emit()

static func is_hollowed(h: Dictionary) -> bool:
	return int(h.days_done) >= HOLLOW_DAYS

func hive_near(pos: Vector2) -> Dictionary:
	for h in hives:
		if h.pos.distance_to(pos) <= REACH:
			return h
	return {}

# 足元で作業する(J)。巣箱がなければ置き、くり抜き途中なら今日の分をくり抜き、蜂がいれば採る。
# front は巣箱を置く場所(体の前。足元に置くと当たり判定に埋まる)。省くと足元
# 結果: placed / no_wood / too_many / blocked / hollowed / finished / done_today / empty / harvested / not_yet
func act(pos: Vector2, front = null) -> String:
	var h := hive_near(pos)
	if h.is_empty():
		return _place(pos if front == null else front)
	if not is_hollowed(h):
		return _hollow(h)
	if not h.occupied:
		return "empty"
	var kg: int = floori(float(h.comb))
	if kg < 1:
		return "not_yet"
	h.comb = float(h.comb) - kg
	stock.honey = int(stock.honey) + kg
	last_harvest = kg
	_commit()
	return "harvested"

func _place(pos: Vector2) -> String:
	if hives.size() >= MAX_HIVES:
		return "too_many"
	if is_blocked(pos):
		return "blocked"
	if cabin.own_log_count() < LOG_COST:
		return "no_wood"
	cabin.spend_own_logs(LOG_COST)
	hives.append({"pos": pos, "days_done": 0, "last_worked": "", "hollowed_day": -1, "occupied": false, "comb": 0.0})
	_commit()
	return "placed"

func _hollow(h: Dictionary) -> String:
	if h.last_worked == forest.today():
		return "done_today"
	h.last_worked = forest.today()
	h.days_done = int(h.days_done) + 1
	if is_hollowed(h):
		h.hollowed_day = forest.day_number()
		_commit()
		return "finished"
	_commit()
	return "hollowed"

# そこに巣箱を置けないか
func is_blocked(pos: Vector2) -> bool:
	var limit: float = land.HALF - EDGE_MARGIN
	if absf(pos.x) > limit or absf(pos.y) > limit:
		return true
	if land.plot_at(pos) != null or land.plot_at(pos + Vector2(CLEARANCE, 0)) != null or land.plot_at(pos - Vector2(CLEARANCE, 0)) != null \
			or land.plot_at(pos + Vector2(0, CLEARANCE)) != null or land.plot_at(pos - Vector2(0, CLEARANCE)) != null:
		return true
	if cabin.footprints().any(func(r): return r.grow(CLEARANCE).has_point(pos)) or cabin.in_yard(pos):
		return true
	if land.pond != null and pos.distance_to(land.pond) < land.POND_RADIUS + CLEARANCE:
		return true
	for t in forest.trees:
		if t.pos.distance_to(pos) < CLEARANCE:
			return true
	for h in hives:
		if h.pos.distance_to(pos) < HIVE_GAP:
			return true
	return taken_nearby.is_valid() and taken_nearby.call(pos, HIVE_GAP)

# その場所に巣箱がかかるか(radius は調べる範囲)。区画や木を置くときに見る
func covers(pos: Vector2, radius := 0.6) -> bool:
	for h in hives:
		if h.pos.distance_to(pos) < radius:
			return true
	return false

# 区画(中心 c)が巣箱にかかるか
func blocks_plot(c: Vector2, half: float) -> bool:
	for h in hives:
		if absf(h.pos.x - c.x) <= half + 0.3 and absf(h.pos.y - c.y) <= half + 0.3:
			return true
	return false

# くり抜き終えて、蜂がまだいない巣箱
func empty_hive() -> Dictionary:
	for h in hives:
		if is_hollowed(h) and not h.occupied:
			return h
	return {}

func has_empty_hive() -> bool:
	return not empty_hive().is_empty()

func can_share_now() -> bool:
	return has_empty_hive() and forest.season in SHARE_SEASONS

# 蜂を分けてもらう。入れたら true
func add_colony() -> bool:
	var h := empty_hive()
	if h.is_empty():
		return false
	h.occupied = true
	h.comb = 0.0
	_commit()
	return true

func ready_count() -> int:
	return hives.filter(func(h): return h.occupied and float(h.comb) >= 1.0).size()

func occupied_count() -> int:
	return hives.filter(func(h): return h.occupied).size()

# 明日採れるようになる巣箱の数(今採れるものも含む。日記用)
func ready_tomorrow() -> int:
	var rate: float = _rate_on(season_of(forest.day_number() + 1))
	return hives.filter(func(h): return h.occupied and minf(float(h.comb) + rate, COMB_MAX) >= 1.0).size()

static func season_of(day: int) -> String:
	var month := int(Forest.date_of_day(day).substr(5, 2))
	if month >= 3 and month <= 5:
		return "spring"
	if month >= 6 and month <= 8:
		return "summer"
	if month >= 9 and month <= 11:
		return "autumn"
	return "winter"

func _rate_on(season: String) -> float:
	var rate: float = HONEY_RATE[season]
	if rate > 0.0 and not garden.crops.is_empty():
		rate += FLOWER_BONUS
	return rate

# 日付が変わったときに呼ぶ。閉じていたあいだの分も、1 日ずつ数える
func catch_up() -> void:
	last_arrivals = 0
	var today: int = forest.day_number()
	if last_checked_day <= 0:
		last_checked_day = today
		dirty.emit()
		return
	if today <= last_checked_day:
		return
	var from: int = maxi(last_checked_day + 1, today - MAX_CATCH_UP_DAYS + 1)
	for d in range(from, today + 1):
		var season := season_of(d)
		for i in range(hives.size()):
			var h: Dictionary = hives[i]
			if h.occupied:
				h.comb = minf(float(h.comb) + _rate_on(season), COMB_MAX)
			elif is_hollowed(h) and int(h.hollowed_day) < d and season in SWARM_SEASONS and _swarm_roll(d, i):
				h.occupied = true
				h.comb = 0.0
				last_arrivals += 1
	last_checked_day = today
	_commit()

# 日付と巣箱で決まる(開き直しても同じ)
func _swarm_roll(day: int, index: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("swarm:%d:%d" % [day, index]).hash()
	return rng.randf() < SWARM_CHANCE

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	var list := []
	for h in hives:
		list.append({
			"x": h.pos.x, "y": h.pos.y, "days_done": h.days_done, "last_worked": h.last_worked,
			"hollowed_day": h.hollowed_day, "occupied": h.occupied, "comb": h.comb,
		})
	return {"hives": list, "honey": stock.honey, "last_checked_day": last_checked_day}

func from_save(d: Dictionary) -> void:
	hives.clear()
	for item in SaveRead.list(d.get("hives")):
		var h := SaveRead.dict(item)
		var pos = SaveRead.point(h)
		if pos == null:
			continue  # 位置の読めない巣箱だけ飛ばす
		hives.append({
			"pos": pos,
			"days_done": SaveRead.count(h, "days_done"),
			"last_worked": SaveRead.text(h, "last_worked"),
			"hollowed_day": SaveRead.whole(h, "hollowed_day", -1),
			"occupied": SaveRead.flag(h, "occupied"),
			"comb": maxf(0.0, SaveRead.num(h, "comb")),
		})
	stock = {"honey": SaveRead.count(d, "honey")}
	last_checked_day = SaveRead.whole(d, "last_checked_day")
	changed.emit()
