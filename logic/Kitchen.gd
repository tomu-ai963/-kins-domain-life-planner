extends RefCounted

# ── 小屋のストーブ(描画を持たない) ──────────────────────────────
# 完成した小屋のストーブで、収穫物を保存食に加工する。鍋はひとつで、仕込む → 日数を待つ → 受け取る の順。
# 仕込むたびに薪を 1 回分使う。薪は丸太から割る(1 本 ≒ 0.1m³ で 10 回分)。
# 瓶・砂糖・塩・粉は売値に含めて、別に買わない(手間を増やしすぎないため)。
# 文言は Main、値段は Market、見た目は view/ が決める
const Forest = preload("res://logic/Forest.gd")
const Garden = preload("res://logic/Garden.gd")
const Cabin = preload("res://logic/Cabin.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const LOG_FIRES := 10  # 丸太 1 本を割ってできる薪(回分)

# input: 材料 / amount: 1 回に使う量(リンゴは個、野菜は kg) / output: できる数 / days: できるまでの暦の日数
const RECIPES := {
	"jam": {"name": "リンゴジャム", "input": "apple", "amount": 10, "output": 4, "unit": "瓶", "days": 1},
	"sauce": {"name": "トマトソース", "input": "tomato", "amount": 10, "output": 5, "unit": "瓶", "days": 1},
	"pickles": {"name": "きゅうりの塩漬け", "input": "cucumber", "amount": 6, "output": 10, "unit": "瓶", "days": 3},
	"garlic_pickle": {"name": "ニンニクの酢漬け", "input": "garlic", "amount": 2, "output": 4, "unit": "瓶", "days": 3},
	"pirozhki": {"name": "ピロシキ", "input": "potato", "amount": 4, "output": 20, "unit": "個", "days": 1},
	"cherry_jam": {"name": "サクランボジャム", "input": "cherry", "amount": 3, "output": 4, "unit": "瓶", "days": 1},
	"plum_jam": {"name": "スモモジャム", "input": "plum", "amount": 5, "output": 4, "unit": "瓶", "days": 1},
	"pear_compote": {"name": "ナシのコンポート", "input": "pear", "amount": 15, "output": 4, "unit": "瓶", "days": 1},
}

var forest: Forest  # GameWorld が設定する(リンゴの持ち物は Forest にある)
var garden: Garden  # GameWorld が設定する(野菜の持ち物は Garden にある)
var cabin: Cabin    # GameWorld が設定する(丸太の持ち物は Cabin にある)

var pot := {}       # 鍋の中身 {recipe, start_day: int}。空なら {}
var stock := {}     # できた保存食の数 {recipe: 数}
var firewood := 0   # 割ってある薪(回分)
var last_split := false  # 直前の仕込みで丸太を割ったか(文言用)
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

# 材料の持ち物(果物は Forest、野菜は Garden)
func _pile(input: String) -> Dictionary:
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
	last_split = firewood <= 0
	if last_split:
		if int(cabin.materials.log) <= 0:
			return "no_wood"
		cabin.materials.log -= 1
		cabin.clamp_own_logs()
		firewood += LOG_FIRES
	firewood -= 1
	_pile(r.input)[r.input] -= int(r.amount)
	pot = {"recipe": id, "start_day": forest.day_number()}
	_commit()
	return "started"

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
	return {"pot": pot, "stock": stock, "firewood": firewood}

func from_save(d: Dictionary) -> void:
	firewood = int(d.get("firewood", 0))
	stock = _zero_counts()
	var saved = d.get("stock", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for k in RECIPES:
			stock[k] = int(saved.get(k, 0))
	pot = {}
	var p = d.get("pot", {})
	if typeof(p) == TYPE_DICTIONARY and RECIPES.has(str(p.get("recipe", ""))):
		pot = {"recipe": str(p.recipe), "start_day": int(p.get("start_day", 0))}
	changed.emit()
