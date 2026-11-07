extends RefCounted

# ── 小屋のストーブ(描画を持たない) ──────────────────────────────
# 完成した小屋のストーブで、収穫物を保存食に加工する。鍋はひとつで、仕込む → 日数を待つ → 受け取る の順。
# 仕込むたびに薪を 1 回分使う。薪は小屋の東の薪割り台で丸太から割る(1 本 ≒ 0.1m³ を 5 回割って 10 回分)。
# 瓶・砂糖・塩・粉は売値に含めて、別に買わない(手間を増やしすぎないため)。
# 文言は Main、値段は Market、見た目は view/ が決める
const Forest = preload("res://logic/Forest.gd")
const Garden = preload("res://logic/Garden.gd")
const Cabin = preload("res://logic/Cabin.gd")
const Bees = preload("res://logic/Bees.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const LOG_FIRES := 10  # 丸太 1 本を割ってできる薪(回分)
const SPLIT_FIRES := 2 # 1 回割るとできる薪(回分)。丸太 1 本を 5 回割る
const MAX_FIREWOOD := 40  # 積んでおける薪(回分)。小屋の壁際に積める量
const MEAL_KINDS := 3     # 1 日に食べられる数(とむ決定: 同じものは 1 つまで、種類が違えば 3 つまで)
# 食べたものの効果(とむの選択: 4 系統)。その日のあいだ効く。同じ系統は重ならないので、4 つのうち 3 つを選ぶ形になる。数字は仮
const MEALS := {
	"strength": {"name": "力がつく", "short": "速く歩ける"},
	"sweet": {"name": "甘い", "short": "親しくなりやすい"},
	"pickle": {"name": "漬物", "short": "収穫が増える"},
	"warm": {"name": "温まる", "short": "薪割りと雪かきが楽"},
}
const MEAL_ORDER := ["strength", "sweet", "pickle", "warm"]  # 画面に並べる順番
const MEAL_SPEED := 1.15     # 力がつく: 歩く速さの倍率
const MEAL_POINTS := 1       # 甘い: 親しくなるたびに足す点
const MEAL_HARVEST := 1.2    # 漬物: 畑と果樹の収穫の倍率
const MEAL_SPLIT := 2        # 温まる: 1 回で割れる量の倍率(丸太 1 本からできる薪の量は変わらない)
const MEAL_SHOVEL_SPEED := 0.8  # 温まる: 雪かきしながら歩く速さの倍率(ふだんは Snow.SHOVEL_SPEED)

# input: 材料 / amount: 1 回に使う量(リンゴは個、野菜は kg) / output: できる数 / days: できるまでの暦の日数 / meal: 食べたときの効果の系統
const RECIPES := {
	"jam": {"name": "リンゴジャム", "input": "apple", "amount": 10, "output": 4, "unit": "瓶", "days": 1, "meal": "sweet"},
	"sauce": {"name": "トマトソース", "input": "tomato", "amount": 10, "output": 5, "unit": "瓶", "days": 1, "meal": "warm"},
	"pickles": {"name": "きゅうりの塩漬け", "input": "cucumber", "amount": 6, "output": 10, "unit": "瓶", "days": 3, "meal": "pickle"},
	"garlic_pickle": {"name": "ニンニクの酢漬け", "input": "garlic", "amount": 2, "output": 4, "unit": "瓶", "days": 3, "meal": "pickle"},
	"pirozhki": {"name": "ピロシキ", "input": "potato", "amount": 4, "output": 20, "unit": "個", "days": 1, "meal": "strength"},
	"cherry_jam": {"name": "サクランボジャム", "input": "cherry", "amount": 3, "output": 4, "unit": "瓶", "days": 1, "meal": "sweet"},
	"plum_jam": {"name": "スモモジャム", "input": "plum", "amount": 5, "output": 4, "unit": "瓶", "days": 1, "meal": "sweet"},
	"pear_compote": {"name": "ナシのコンポート", "input": "pear", "amount": 15, "output": 4, "unit": "瓶", "days": 1, "meal": "sweet"},
	"pryanik": {"name": "ピャーニク", "input": "honey", "amount": 1, "output": 10, "unit": "個", "days": 1, "meal": "strength"},  # ロシアの蜂蜜菓子
	"sbiten": {"name": "スビーテン", "input": "honey", "amount": 2, "output": 8, "unit": "瓶", "days": 3, "meal": "warm"},  # ロシアの蜂蜜の温かい飲み物
}

var forest: Forest  # GameWorld が設定する(リンゴの持ち物は Forest にある)
var garden: Garden  # GameWorld が設定する(野菜の持ち物は Garden にある)
var cabin: Cabin    # GameWorld が設定する(丸太の持ち物は Cabin にある)
var bees: Bees      # GameWorld が設定する(はちみつの持ち物は Bees にある)

var pot := {}       # 鍋の中身 {recipe, start_day: int}。空なら {}
var stock := {}     # できた保存食の数 {recipe: 数}
var firewood := 0   # 割ってある薪(回分)
var cooked := false # 一度でも仕込んだか(ヒント用。薪は剪定の枝でも増えるので、薪では分からない)
var log_left := 0   # 台の上で割りかけの丸太の残り(回分)
var ate_day := -1   # 最後に食べた日の通し番号(-1 = まだ)
var ate_foods := [] # その日に食べた保存食の id。読むときは eaten_today(前の日の分が残っている)
var last_eaten := "" # 直前に食べた保存食の id(文言用)
var last_collected := {} # 直前に受け取った {recipe, count}(文言用)

func _init() -> void:
	stock = _zero_counts()

static func _zero_counts() -> Dictionary:
	var d := {}
	for k in RECIPES:
		d[k] = 0
	return d

func _commit() -> void:
	dirty.emit()
	changed.emit()

# 材料の持ち物(果物は Forest、はちみつは Bees、野菜は Garden)
func _pile(input: String) -> Dictionary:
	if input == "honey":
		return bees.stock
	return forest.produce if forest.produce.has(input) else garden.produce

func input_count(id: String) -> int:
	var input: String = RECIPES[id].input
	return int(_pile(input).get(input, 0))

func is_empty() -> bool:
	return pot.is_empty()

# 鍋の中身ができるまで、あと何日か(空なら 0)
func days_left() -> int:
	if pot.is_empty():
		return 0
	return maxi(0, int(RECIPES[pot.recipe].days) - (forest.day_number() - int(pot.start_day)))

func is_ready() -> bool:
	return not pot.is_empty() and days_left() == 0

# 明日には受け取れるか(今できているものも含む)
func ready_tomorrow() -> bool:
	return not pot.is_empty() and days_left() <= 1

# 仕込む。結果: started / unknown / busy / no_input / no_wood
func start(id: String) -> String:
	if not RECIPES.has(id):
		return "unknown"
	if not pot.is_empty():
		return "busy"
	var r: Dictionary = RECIPES[id]
	if input_count(id) < int(r.amount):
		return "no_input"
	if firewood <= 0:
		return "no_wood"
	firewood -= 1
	cooked = true
	_pile(r.input)[r.input] -= int(r.amount)
	pot = {"recipe": id, "start_day": forest.day_number()}
	_commit()
	return "started"

func ate_today() -> bool:
	return ate_day == forest.day_number()

func ever_ate() -> bool:
	return ate_day >= 0

# 保存食を持っているか
func has_food() -> bool:
	for id in stock:
		if int(stock[id]) > 0:
			return true
	return false

# 今日食べた保存食の id
func eaten_today() -> Array:
	return ate_foods if ate_today() else []

# その系統の効果が今日効いているか
func has_effect(meal: String) -> bool:
	for id in eaten_today():
		if RECIPES[id].meal == meal:
			return true
	return false

# 今日効いている効果の系統(MEAL_ORDER の順)
func active_effects() -> Array:
	return MEAL_ORDER.filter(func(m): return has_effect(m))

# 畑と果樹の収穫の倍率(Garden と Forest が読む)
func harvest_rate() -> float:
	return MEAL_HARVEST if has_effect("pickle") else 1.0

# 保存食を 1 つ食べる。結果: eaten / same(今日もう食べた) / full(今日はもう 3 つ食べた) / none(持っていない) / unknown
func eat(id: String) -> String:
	if not RECIPES.has(id):
		return "unknown"
	var eaten := eaten_today()
	if id in eaten:
		return "same"
	if eaten.size() >= MEAL_KINDS:
		return "full"
	if int(stock[id]) <= 0:
		return "none"
	stock[id] = int(stock[id]) - 1
	if not ate_today():
		ate_foods = []
		ate_day = forest.day_number()
	ate_foods.append(id)
	last_eaten = id
	_commit()
	return "eaten"

# 剪定で切った枝を薪にする(積める量まで)
func add_firewood(n: int) -> void:
	firewood = mini(firewood + n, MAX_FIREWOOD)
	_commit()

# 薪割り台で 1 回割る。台に丸太がなければ 1 本のせる。結果: split / no_log / full
func split() -> String:
	if firewood >= MAX_FIREWOOD:
		return "full"
	if log_left <= 0:
		if int(cabin.materials.log) <= 0:
			return "no_log"
		cabin.materials.log -= 1
		cabin.clamp_own_logs()
		log_left = LOG_FIRES
	var step: int = SPLIT_FIRES * (MEAL_SPLIT if has_effect("warm") else 1)
	var n: int = mini(mini(step, log_left), MAX_FIREWOOD - firewood)
	firewood += n
	log_left -= n
	_commit()
	return "split"

# できたものを受け取る。結果: collected / empty / cooking
func collect() -> String:
	if pot.is_empty():
		return "empty"
	if not is_ready():
		return "cooking"
	var id: String = pot.recipe
	var n: int = int(RECIPES[id].output)
	stock[id] += n
	last_collected = {"recipe": id, "count": n}
	pot = {}
	_commit()
	return "collected"

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	return {"pot": pot, "stock": stock, "firewood": firewood, "log_left": log_left, "cooked": cooked, "ate_day": ate_day, "ate_foods": ate_foods}

func from_save(d: Dictionary) -> void:
	firewood = int(d.get("firewood", 0))
	log_left = int(d.get("log_left", 0))
	ate_day = int(d.get("ate_day", -1))
	ate_foods = []
	var foods = d.get("ate_foods", [])
	if typeof(foods) == TYPE_ARRAY:
		for id in foods:
			if RECIPES.has(str(id)):
				ate_foods.append(str(id))
	stock = _zero_counts()
	var saved = d.get("stock", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for k in RECIPES:
			stock[k] = int(saved.get(k, 0))
	pot = {}
	var p = d.get("pot", {})
	if typeof(p) == TYPE_DICTIONARY and RECIPES.has(str(p.get("recipe", ""))):
		pot = {"recipe": str(p.recipe), "start_day": int(p.get("start_day", 0))}
	# 記録がないセーブは、薪があれば(当時は仕込むときにしか割らなかった)仕込んだことがある
	cooked = bool(d.get("cooked", firewood > 0 or not pot.is_empty()))
	changed.emit()
