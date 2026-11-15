extends RefCounted

# ── 畑を荒らす生き物と、仲良し度(描画を持たない) ────────────────────
# 2026-11-11 とむ: 「野生動物の食害と仲良し度(仲良くなると食害がなくなる)」。2026-11-15 実装。数字は仮。
# - 夜のあいだ(日付が変わったとき)に、土地に来ている生き物が畑の野菜をかじる。かじられた区画は収量が半分になり、
#   3 回で食べ尽くされる(Garden.bite)。イノシシとエゾシカは 1 回で区画を掘り返す
# - 仲良し度(0〜100)が上がるほど荒らさなくなり、FRIEND_SAFE 以上では荒らさない
# - 餌台に餌(秋と冬は種)か野菜を置くと上がる(餌台ごとに 1 日 1 回)。何もしない日は少しずつ下がる。
#   ガソリンで動く機械の音で生き物が逃げて下がる(機械ごとに 1 日 1 回)
# 来るかどうかは Wildlife(土地の様子・季節・土地の生き物)。文言は Main、見た目は view/ が決める
const SaveRead = preload("res://logic/SaveRead.gd")
const Forest = preload("res://logic/Forest.gd")
const Garden = preload("res://logic/Garden.gd")

signal dirty  # セーブに入る状態が変わった

const FRIEND_MAX := 100
const FRIEND_START := 20   # はじめの仲良し度(新しいゲームも、仲良し度のない古いセーブも)
const FRIEND_SAFE := 80    # これ以上なら畑を荒らさない
const FEED_GAIN := 5       # 餌台に餌を置くと上がる(餌台ごとに 1 日 1 回)
const DAILY_FADE := 1      # 1 日たつごとに下がる
const MACHINE_LOSS := 3    # 機械を動かした日に下がる(機械ごとに 1 日 1 回)
const MAX_FADE_DAYS := 30  # 閉じていたあいだに下がるのは、この日数まで

# 畑を荒らす生き物(Wildlife.SPECIES の id)。groups: かじる野菜の組(Garden.GROUPS) /
# chance: 仲良し度 0 のときに一晩で荒らす見込み / dig: 区画ごと掘り返す
const PESTS := {
	"hare": {"groups": ["leaf", "root"], "chance": 0.5, "dig": false},       # 葉ものと根菜の葉をかじる
	"snow_hare": {"groups": ["leaf", "root"], "chance": 0.5, "dig": false},
	"tanuki": {"groups": ["fruit", "imo", "bean"], "chance": 0.4, "dig": false},  # トマトやトウモロコシ、いもを食べる
	"crow": {"groups": ["fruit", "bean"], "chance": 0.5, "dig": false},      # 実った野菜や豆、まいた穀物をつつく
	"boar": {"groups": ["imo", "root", "bean"], "chance": 0.3, "dig": true},  # いもを掘り返す
	"ezo_deer": {"groups": ["leaf", "bean", "root"], "chance": 0.3, "dig": true},
}

var forest: Forest   # GameWorld が設定する
var garden: Garden
var wildlife = null  # GameWorld が設定する

var friendship := FRIEND_START
var last_day := ""        # 最後に夜を数えた日(YYYY-MM-DD)
var gift_days := {}       # 餌台ごとに、最後に仲良し度が上がった日 {"x,y": YYYY-MM-DD}
var machine_days := {}    # 機械ごとに、最後に仲良し度が下がった日 {machine: YYYY-MM-DD}
var last_damage := []     # 今日の確認で荒らされた区画 [{id, kind, dug: bool, gone: bool}](知らせる用・保存しない)
var last_gain := 0        # 直前に上がった量(文言用・保存しない)

func is_safe() -> bool:
	return friendship >= FRIEND_SAFE

# 今、一晩で荒らす見込みの倍率(0〜1)
func damage_rate() -> float:
	return clampf(float(FRIEND_SAFE - friendship) / FRIEND_SAFE, 0.0, 1.0)

# 今この土地に来ていて、畑を荒らす生き物の id(PESTS の順)
func present() -> Array:
	if wildlife == null:
		return []
	return PESTS.keys().filter(func(id): return wildlife.would_come(id))

func _add(n: int) -> void:
	friendship = clampi(friendship + n, 0, FRIEND_MAX)

# 餌台(pos)に餌を置いた。その餌台で今日はじめてなら上がる。上がった量を返す
func befriend(pos: Vector2) -> int:
	var key := "%.1f,%.1f" % [pos.x, pos.y]
	last_gain = 0
	if gift_days.get(key, "") == forest.today():
		return 0
	gift_days[key] = forest.today()
	var before := friendship
	_add(FEED_GAIN)
	last_gain = friendship - before
	dirty.emit()
	return last_gain

# ガソリンで動く機械を動かした(Tools.machine_used)。その機械で今日はじめてなら下がる
func on_machine(machine: String) -> void:
	if machine_days.get(machine, "") == forest.today():
		return
	machine_days[machine] = forest.today()
	_add(-MACHINE_LOSS)
	dirty.emit()

# 日付が変わったときに呼ぶ: ゆうべ来ていた生き物が畑を荒らし、たった日数ぶん仲良し度が下がる。
# 荒らすかどうかは日付と生き物から決まる(同じ日を開き直しても変わらない)。閉じていたあいだの夜は、最後の一晩だけ数える
func night_passed() -> void:
	last_damage = []
	var today := forest.today()
	if last_day == today:
		return
	var days := 1
	if last_day != "":
		days = clampi(forest.day_number() - int(Time.get_unix_time_from_datetime_string(last_day) / 86400.0), 0, MAX_FADE_DAYS)
	last_day = today
	# ゆうべの仲良し度で荒らすかを決めてから、たった日数ぶん下げる
	var rate := damage_rate()
	if rate > 0.0:
		for id in present():
			_raid(id, today, rate)
	_add(-DAILY_FADE * days)
	dirty.emit()

func _raid(id: String, today: String, rate: float) -> void:
	var p: Dictionary = PESTS[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = ("pest:%s:%s" % [today, id]).hash()
	if rng.randf() >= float(p.chance) * rate:
		return
	var targets: Array = garden.crops.filter(func(c): return Garden.CROPS[c.kind].group in p.groups)
	if targets.is_empty():
		return
	var c: Dictionary = targets[rng.randi_range(0, targets.size() - 1)]
	var kind: String = c.kind
	if p.dig:
		garden.dig_up(c)
		last_damage.append({"id": id, "kind": kind, "dug": true, "gone": true})
	else:
		var gone: bool = garden.bite(c)
		last_damage.append({"id": id, "kind": kind, "dug": false, "gone": gone})

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	return {"friendship": friendship, "last_day": last_day, "gift_days": gift_days, "machine_days": machine_days}

func from_save(d: Dictionary) -> void:
	friendship = clampi(SaveRead.whole(d, "friendship", FRIEND_START), 0, FRIEND_MAX) if d.has("friendship") else FRIEND_START
	last_day = SaveRead.text(d, "last_day")
	gift_days = {}
	var g := SaveRead.dict(d.get("gift_days"))
	for k in g:
		if g[k] is String:
			gift_days[str(k)] = g[k]
	machine_days = {}
	var m := SaveRead.dict(d.get("machine_days"))
	for k in m:
		if m[k] is String:
			machine_days[str(k)] = m[k]
