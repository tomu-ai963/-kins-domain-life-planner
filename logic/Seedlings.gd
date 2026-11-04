extends RefCounted

# ── 小屋の苗づくり(描画を持たない) ──────────────────────────────
# 完成した小屋の窓辺で、種から苗を育てる。外の季節によらず、冬でもできる(雨は当たらない)。
# 育った苗は春に畑へ植える(2 日ぶん早く収穫できる)か、市場で売る。
# 水をやった日は 1 日ぶん、やらなかった日は半日ぶん育つ(畑と同じ)。
# 文言は Main、値段は Market、見た目は view/ が決める
const Forest = preload("res://logic/Forest.gd")
const Garden = preload("res://logic/Garden.gd")
const Cabin = preload("res://logic/Cabin.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const SEEDLING_CROPS := ["tomato", "cucumber"]  # 苗にできる野菜
const POTS := 6        # 窓辺に置ける鉢の数。1 鉢が 1 区画ぶんの苗
const GROW_DAYS := 5   # 毎日世話をしたときの日数(現実は 50〜60 日ほど。縮めている)
const DRY_GROWTH := 0.5

var forest: Forest  # GameWorld が設定する
var garden: Garden
var cabin: Cabin

var pots := []    # 窓辺の鉢 [{kind, sown_day: int, water_days: int, last_watered}]
var ready := {}   # 育った苗の数 {kind: 数}
var last_count := 0  # 直前の操作で受け取った苗の数 / 世話をした鉢の数(文言用)

func _init() -> void:
	ready = _zero_counts()

static func _zero_counts() -> Dictionary:
	var d := {}
	for k in SEEDLING_CROPS:
		d[k] = 0
	return d

func _commit() -> void:
	dirty.emit()
	changed.emit()

func watered_today(p: Dictionary) -> bool:
	return p.last_watered == forest.today()

# 育った日数。今日の分はまだ数えない(畑と同じ)
func growth_days(p: Dictionary) -> float:
	var elapsed: int = forest.day_number() - int(p.sown_day)
	var wet: int = int(p.water_days) - (1 if watered_today(p) else 0)
	return elapsed * DRY_GROWTH + wet * (1.0 - DRY_GROWTH)

func is_grown(p: Dictionary) -> bool:
	return growth_days(p) >= GROW_DAYS

func growth_ratio(p: Dictionary) -> float:
	return clampf(growth_days(p) / GROW_DAYS, 0.0, 1.0)

# いちばん早く育つ鉢まで、毎日世話をしてあと何日か(鉢がなければ 0)
func days_left() -> int:
	var best := GROW_DAYS
	for p in pots:
		best = mini(best, ceili(GROW_DAYS - growth_days(p)))
	return 0 if pots.is_empty() else maxi(0, best)

# まだ今日世話をしていない鉢があるか
func needs_care() -> bool:
	for p in pots:
		if not watered_today(p):
			return true
	return false

# 小屋の外で H を押したときの作業。育った苗を受け取る → 世話をする → 種をまく の順に、1 回に 1 つ進む
# 結果: collected / tended / sown / none / far / not_seedling / full / no_seed
func act(pos: Vector2, kind: String) -> String:
	if not cabin.is_complete():
		return "none"
	if not cabin.is_near(pos):
		return "far"
	last_count = 0
	for i in range(pots.size() - 1, -1, -1):
		if is_grown(pots[i]):
			ready[pots[i].kind] += 1
			pots.remove_at(i)
			last_count += 1
	if last_count > 0:
		_commit()
		return "collected"
	for p in pots:
		if not watered_today(p):
			p.last_watered = forest.today()
			p.water_days += 1
			last_count += 1
	if last_count > 0:
		_commit()
		return "tended"
	if not (kind in SEEDLING_CROPS):
		return "not_seedling"
	if pots.size() >= POTS:
		return "full"
	if int(garden.seeds.get(kind, 0)) <= 0:
		return "no_seed"
	garden.seeds[kind] -= 1
	# まいた日の世話も済ませておく
	pots.append({"kind": kind, "sown_day": forest.day_number(), "water_days": 1, "last_watered": forest.today()})
	_commit()
	return "sown"

# 育った苗を足元の区画に植える。結果: Garden.sow の結果か no_seedling
func transplant(pos: Vector2, kind: String) -> String:
	if int(ready.get(kind, 0)) <= 0:
		return "no_seedling"
	var result: String = garden.sow(pos, kind, true)
	if result == "sown":
		ready[kind] -= 1
		_commit()
	return result

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	return {"pots": pots, "ready": ready}

func from_save(d: Dictionary) -> void:
	ready = _zero_counts()
	var saved = d.get("ready", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for k in SEEDLING_CROPS:
			ready[k] = int(saved.get(k, 0))
	pots = []
	for p in d.get("pots", []):
		if typeof(p) == TYPE_DICTIONARY and str(p.get("kind", "")) in SEEDLING_CROPS:
			pots.append({
				"kind": str(p.kind),
				"sown_day": int(p.sown_day),
				"water_days": int(p.get("water_days", 0)),
				"last_watered": str(p.get("last_watered", "")),
			})
	changed.emit()
