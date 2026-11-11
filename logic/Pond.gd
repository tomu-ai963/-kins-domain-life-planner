extends RefCounted

# ── 池の作り込み(描画を持たない) ───────────────────────────────
# 池の場所は Land.pond。ここは掘る作業・水の量・来る生き物を持つ。
# 場所を決める → 1 日 1 回掘る(5 日) → 掘り終えると湧き水で半分まで入る → 雨で水がたまる
# → 水が半分を超えると生き物が順に来る。
# 雨と夏の蒸発は閉じているあいだの分も数える(天気は日付から決まる。Forest.roll_daily_event)。
# 文言は Main、見た目は view/ が決める。座標の単位は m
const SaveRead = preload("res://logic/SaveRead.gd")
const Forest = preload("res://logic/Forest.gd")
const Land = preload("res://logic/Land.gd")
const Garden = preload("res://logic/Garden.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const DIG_DAYS := 5     # 掘る日数(50m² を手で掘ると現実は 2〜3 週間ほど。縮めている)
const REACH := 2.0      # 池の縁からこの距離までなら作業できる
const RAIN_FILL := 25   # 雨 1 回でたまる水(%)。4 回の雨で満杯
const SUMMER_LOSS := 2  # 夏(6〜8 月)に 1 日で蒸発する水(%)。雨は平均で 1 日 6% ほどたまる
const WET_WATER := 50   # 水がこの量(%)を超えると、生き物が来るようになる
const SPRING_FILL := 50 # 掘り終えた日に湧き水でたまる水(%)。雨を待たずに生き物が来はじめる
const WATER_RADIUS := 20.0  # 池の中心からこの距離(m)までの木と区画に、まとめて水をやれる
const WATER_COST := 5       # まとめて水をやると減る水(%)。雨は 4 日に 1 回 25% なので、毎日使っても釣り合う

# days: 水が WET_WATER を超えてから来るまでの日数(現実の数週間〜数か月を縮めた) / seasons: 見られる季節
const CREATURES := {
	"strider": {"name": "アメンボ", "days": 2, "seasons": ["spring", "summer", "autumn"]},
	"reed": {"name": "ガマ", "days": 5, "seasons": ["spring", "summer", "autumn", "winter"]},
	"frog": {"name": "カエル", "days": 7, "seasons": ["spring", "summer"]},
	"dragonfly": {"name": "トンボ", "days": 10, "seasons": ["summer", "autumn"]},
	"duck": {"name": "カモ", "days": 14, "seasons": ["spring", "summer", "autumn"]},
}

var forest: Forest  # GameWorld が設定する
var land: Land
var garden: Garden

var days_dug := 0            # 掘った日数
var last_dug := ""           # 最後に掘った日(YYYY-MM-DD)
var water := 0               # 水の量(%)
var wet_since_day := -1      # 水が WET_WATER を超えた日の通し番号(-1 = まだ)
var last_checked_day := 0    # 雨を数え終えた日の通し番号
var seen := []               # 一度でも来た生き物の id
var last_arrivals := []      # 今日はじめて来た生き物の id(知らせる用・保存しない)
var last_gain := 0           # 今日の確認でたまった水(%)(知らせる用・保存しない)
var last_watered := [0, 0]   # 直前にまとめて水をやった [区画の数, 木の数](文言用・保存しない)

func is_placed() -> bool:
	return land.pond != null

func is_dug() -> bool:
	return is_placed() and days_dug >= DIG_DAYS

func dug_today() -> bool:
	return last_dug == forest.today()

func _commit() -> void:
	dirty.emit()
	changed.emit()

func _reset() -> void:
	days_dug = 0
	last_dug = ""
	water = 0
	wet_since_day = -1
	last_checked_day = 0
	seen = []
	last_arrivals = []
	last_gain = 0

func _is_near(pos: Vector2) -> bool:
	return is_placed() and pos.distance_to(land.pond) <= land.POND_RADIUS + REACH

# 池のそばか(場所を決めただけでも、縁から REACH まで)。まとめて水やりの範囲の輪を出す用
func is_near(pos: Vector2) -> bool:
	return _is_near(pos)

# 足元で掘る。結果: dug / finished / none / far / already / done_today
func dig(pos: Vector2) -> String:
	if not is_placed():
		return "none"
	if not _is_near(pos):
		return "far"
	if is_dug():
		return "already"
	if dug_today():
		return "done_today"
	days_dug += 1
	last_dug = forest.today()
	var result := "dug"
	if is_dug():
		result = "finished"
		last_checked_day = forest.day_number()  # 掘り終えた次の雨からたまる
		_fill_spring()
	_commit()
	return result

# 掘りはじめる前なら、場所を取り消せる。取り消したら true
func cancel(pos: Vector2) -> bool:
	if not _is_near(pos) or days_dug > 0:
		return false
	land.toggle_pond(land.pond)
	_reset()
	_commit()
	return true

# 湧き水で SPRING_FILL まで入れる(すでに多ければそのまま)
func _fill_spring() -> void:
	water = maxi(water, SPRING_FILL)
	if water >= WET_WATER and wet_since_day < 0:
		wet_since_day = forest.day_number()

# 掘り終えた池のそばにいるか
func is_beside(pos: Vector2) -> bool:
	return is_dug() and _is_near(pos)

# 池のまわりの、水がいる [区画の数, 木の数]
func dry_around() -> Array:
	if not is_placed():
		return [0, 0]
	return [garden.dry_within(land.pond, WATER_RADIUS), forest.dry_within(land.pond, WATER_RADIUS)]

# 池のそばから、まわりの区画と木にまとめて水をやる。結果: watered / far / frozen / low / nothing
func water_around(pos: Vector2) -> String:
	if not is_beside(pos):
		return "far"
	if is_frozen():
		return "frozen"
	if water < WATER_COST:
		return "low"
	var dry := dry_around()
	if dry[0] + dry[1] == 0:
		return "nothing"
	last_watered = [garden.water_within(land.pond, WATER_RADIUS), forest.water_within(land.pond, WATER_RADIUS)]
	water -= WATER_COST
	_commit()
	return "watered"

# 前の確認から今日までに降った雨で水をためて、来た生き物を確かめる(日付が変わったときに呼ぶ)
func catch_up() -> void:
	last_arrivals = []
	last_gain = 0
	if not is_dug():
		return
	var before := water
	var today: int = forest.day_number()
	for d in range(last_checked_day + 1, today + 1):
		var date := Forest.date_of_day(d)
		if forest.is_summer_date(date):
			water = maxi(0, water - SUMMER_LOSS)
		if forest.roll_daily_event(date) == "rain":
			water = mini(100, water + RAIN_FILL)
		if water >= WET_WATER and wet_since_day < 0:
			wet_since_day = d
	last_checked_day = today
	last_gain = water - before
	for id in present():
		if not (id in seen):
			seen.append(id)
			last_arrivals.append(id)
	_commit()

# 水が WET_WATER を超えてからの日数(まだなら -1)
func wet_days() -> int:
	return -1 if wet_since_day < 0 else forest.day_number() - wet_since_day

# いま池にいる生き物の id
func present() -> Array:
	var list := []
	var days := wet_days()
	if days < 0:
		return list
	for id in CREATURES:
		if days >= int(CREATURES[id].days) and forest.season in CREATURES[id].seasons:
			list.append(id)
	return list

func is_frozen() -> bool:
	return forest.season == "winter" and water > 0

# 凍った池の上か(冬は上を歩けて、滑る。2026-11-11 とむ決定)
func is_on_ice(pos: Vector2) -> bool:
	return is_dug() and is_frozen() and pos.distance_to(land.pond) <= land.POND_RADIUS

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	return {
		"days_dug": days_dug, "last_dug": last_dug, "water": water,
		"wet_since_day": wet_since_day, "last_checked_day": last_checked_day, "seen": seen,
		"spring": true,
	}

# Land を読んだあとで呼ぶ
func from_save(d: Dictionary) -> void:
	_reset()
	if is_placed():
		if d.is_empty():
			# 手順 3-3 までのセーブの池は、一瞬で掘れて水が入っていた。そのまま満杯の池として扱う
			days_dug = DIG_DAYS
			water = 100
			wet_since_day = forest.day_number()
			last_checked_day = wet_since_day
		else:
			days_dug = clampi(SaveRead.whole(d, "days_dug"), 0, DIG_DAYS)
			last_dug = SaveRead.text(d, "last_dug")
			water = clampi(SaveRead.whole(d, "water"), 0, 100)
			wet_since_day = SaveRead.whole(d, "wet_since_day", -1)
			last_checked_day = SaveRead.whole(d, "last_checked_day")
			seen = SaveRead.ids(d.get("seen"), CREATURES)
			# 湧き水を入れる前(2026-11-11 より前)に掘り終えた池には、開いたときに 1 回だけ入れる
			if not d.has("spring") and is_dug():
				_fill_spring()
	changed.emit()
