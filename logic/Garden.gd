extends RefCounted

# ── 畑の野菜(描画を持たない) ──────────────────────────────────
# Land の菜園の区画 1 つに、野菜を 1 種類まく(3m 四方 = 9m²)。
# まける季節は現実どおり、育つ日数は数日〜1 週間に縮める(2026-11-03 とむの方針)。
# 日数は暦で数える。水をやった日は 1 日ぶん、やらなかった日は半日ぶん育つ。
# 文言は Main、値段は Market、見た目は view/ が決める
const Forest = preload("res://logic/Forest.gd")
const Land = preload("res://logic/Land.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const DRY_GROWTH := 0.5  # 水をやらなかった日の育ち(1 日あたり)

# seasons: まける季節 / grow_days: 毎日水をやったときの日数(現実の日数から縮めたもの)
# yield_kg: 1 区画(9m²)の収量。現実の 1m² あたりの目安 × 9
const CROPS := {
	"radish": {"name": "ラディッシュ", "seed_name": "ラディッシュの種", "seasons": ["spring", "autumn"], "grow_days": 3, "yield_kg": 6},  # 現実 約 25 日
	"carrot": {"name": "にんじん", "seed_name": "にんじんの種", "seasons": ["spring", "summer"], "grow_days": 6, "yield_kg": 20},     # 現実 約 90 日
	"cucumber": {"name": "きゅうり", "seed_name": "きゅうりの種", "seasons": ["spring", "summer"], "grow_days": 5, "yield_kg": 18},  # 現実 約 55 日
	"potato": {"name": "じゃがいも", "seed_name": "じゃがいもの種いも", "seasons": ["spring"], "grow_days": 7, "yield_kg": 25},       # 現実 約 90 日
	"garlic": {"name": "ニンニク", "seed_name": "ニンニクの種球", "seasons": ["autumn"], "grow_days": 7, "yield_kg": 5},             # 現実 約 9 か月(秋に植えて翌夏)
}

var land: Land      # GameWorld が設定する
var forest: Forest  # 季節・日付・雨・先送りプレビューは Forest が持っている

var crops := []    # [{pos: Vector2(区画の中心), kind, sown_day: int, water_days: int, last_watered}]
var seeds := {}    # 野菜ごとの種の数(1 つで 1 区画ぶん)
var produce := {}  # 野菜ごとの収穫物(kg)。市場で売る
var last_harvest_kg := 0  # 直前の収穫の量(文言用)

func _init() -> void:
	seeds = _zero_counts()
	produce = _zero_counts()

static func _zero_counts() -> Dictionary:
	var d := {}
	for k in CROPS:
		d[k] = 0
	return d

# 暦の日の通し番号(日付をまたぐと 1 増える。植えた時刻によらない)
func day_number() -> int:
	return forest.day_number()

# 保存が必要な変更のあと: 保存してから描き直す
func _commit() -> void:
	dirty.emit()
	changed.emit()

# 足元の区画の野菜。なければ空の Dictionary
func crop_at(pos: Vector2) -> Dictionary:
	var c: Vector2 = land.plot_center(pos)
	for crop in crops:
		if crop.pos == c:
			return crop
	return {}

# 足元の区画に種をまく。結果: sown / no_plot / occupied / not_season / no_seed
func sow(pos: Vector2, kind: String) -> String:
	var c = land.plot_at(pos)
	if c == null:
		return "no_plot"
	if not crop_at(pos).is_empty():
		return "occupied"
	if not (forest.season in CROPS[kind].seasons):
		return "not_season"
	if int(seeds.get(kind, 0)) <= 0:
		return "no_seed"
	seeds[kind] -= 1
	crops.append({"pos": c, "kind": kind, "sown_day": day_number(), "water_days": 0, "last_watered": ""})
	# 雨の日は一日中降っている扱い。あとからまいた区画も水やり済みにする
	if forest.last_day == forest.today() and forest.today_event == "rain":
		_water(crops[-1])
	_commit()
	return "sown"

# 足元の区画に水をあげる。結果: watered / none / done / ripe
func water_at(pos: Vector2) -> String:
	var c := crop_at(pos)
	if c.is_empty():
		return "none"
	if is_ripe(c):
		return "ripe"
	if not _water(c):
		return "done"
	_commit()
	return "watered"

# まだ今日水をあげていない区画すべてに水をあげる(雨の日)。あげた区画の数を返す
func water_all() -> int:
	var n := 0
	for c in crops:
		if _water(c):
			n += 1
	if n > 0:
		_commit()
	return n

func _water(c: Dictionary) -> bool:
	if c.last_watered == forest.today():
		return false
	c.last_watered = forest.today()
	c.water_days += 1
	return true

func watered_today(c: Dictionary) -> bool:
	return c.last_watered == forest.today()

# 足元の区画を収穫する。結果: harvested / none / preview / growing
func harvest_at(pos: Vector2) -> String:
	var c := crop_at(pos)
	if c.is_empty():
		return "none"
	# 先送りで収穫できないよう、判定は現実の日数で行い、プレビュー中は収穫させない
	if forest.time_offset_years > 0.0:
		return "preview"
	if not is_ripe(c):
		return "growing"
	last_harvest_kg = int(CROPS[c.kind].yield_kg)
	produce[c.kind] += last_harvest_kg
	crops.erase(c)
	_commit()
	return "harvested"

# 足元の野菜を抜く(種は戻らない)。抜いたら true
func remove_at(pos: Vector2) -> bool:
	var c := crop_at(pos)
	if c.is_empty():
		return false
	crops.erase(c)
	_commit()
	return true

# 足元の 3m マスに区画を置く / 取り消す。野菜が育っている区画は取り消せない
# 結果: placed / removed / outside(Land)、has_crop
func toggle_plot(pos: Vector2) -> String:
	if not crop_at(pos).is_empty():
		return "has_crop"
	return land.toggle_plot(pos)

# 育った日数。今日の分はまだ数えない(今日の水やりは、明日の時点で 1 日ぶんになる)
func growth_days(c: Dictionary) -> float:
	var elapsed: int = day_number() - int(c.sown_day)
	var wet: int = int(c.water_days) - (1 if watered_today(c) else 0)
	return elapsed * DRY_GROWTH + wet * (1.0 - DRY_GROWTH)

func is_ripe(c: Dictionary) -> bool:
	return growth_days(c) >= float(CROPS[c.kind].grow_days)

# 毎日水をやったとして、収穫まであと何日か
func days_left(c: Dictionary) -> int:
	return maxi(0, ceili(float(CROPS[c.kind].grow_days) - growth_days(c)))

# 表示用の育ち具合 0〜1(プレビューの先送りを含む。1 年の先送り = 1 日)
func growth_ratio(c: Dictionary) -> float:
	return clampf((growth_days(c) + forest.time_offset_years) / float(CROPS[c.kind].grow_days), 0.0, 1.0)

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	var list := []
	for c in crops:
		list.append({
			"x": c.pos.x, "y": c.pos.y, "kind": c.kind, "sown_day": c.sown_day,
			"water_days": c.water_days, "last_watered": c.last_watered,
		})
	return {"crops": list, "seeds": seeds, "produce": produce}

func from_save(d: Dictionary) -> void:
	seeds = _zero_counts()
	produce = _zero_counts()
	for k in CROPS:
		seeds[k] = int(d.get("seeds", {}).get(k, 0))
		produce[k] = int(d.get("produce", {}).get(k, 0))
	crops.clear()
	for c in d.get("crops", []):
		if typeof(c) == TYPE_DICTIONARY and str(c.get("kind", "")) in CROPS:
			crops.append({
				"pos": Vector2(float(c.x), float(c.y)),
				"kind": str(c.kind),
				"sown_day": int(c.sown_day),
				"water_days": int(c.get("water_days", 0)),
				"last_watered": str(c.get("last_watered", "")),
			})
	changed.emit()
