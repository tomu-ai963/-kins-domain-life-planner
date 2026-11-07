extends RefCounted

# ── チュートリアル(ヒント)(描画を持たない) ──────────────────────────
# 今の土地の様子に合ったヒントを、1 つずつ出す。手順を強制しない。ルールには関わらない。
# 「やること」のヒントは、その操作をすると消える。「お知らせ」のヒントは SHOW_SECONDS で消える。どちらも K で閉じられる。
# 一度出たヒントは二度と出ない(seen に残す)。もう済んでいることのヒントは出ない(途中のセーブからでも使える)。
# 文言は Main、見た目は HUD が決める
const Forest = preload("res://logic/Forest.gd")
const Land = preload("res://logic/Land.gd")
const Garden = preload("res://logic/Garden.gd")
const Cabin = preload("res://logic/Cabin.gd")
const Pond = preload("res://logic/Pond.gd")
const Market = preload("res://logic/Market.gd")
const Kitchen = preload("res://logic/Kitchen.gd")
const Visitors = preload("res://logic/Visitors.gd")
const Wildlife = preload("res://logic/Wildlife.gd")

signal dirty  # セーブに入る状態が変わった

const SHOW_SECONDS := 15.0   # お知らせのヒントを出しておく時間
const GAP_SECONDS := 4.0     # 次のヒントを出すまでの間
const MIN_PLOTS_FOR_CABIN := 4  # 畑に慣れてから小屋を案内する

# 上にあるものを先に出す
const HINTS := [
	"walk", "plant", "plot", "buy_seeds", "sow", "water", "harvest", "sell", "stuck", "broke",
	"apple", "visitor", "pond_rain", "pond_water", "cabin_site", "cabin_logs",
	"cabin_inside", "split", "stove", "bed", "table", "hive_make", "hive_bees", "honey", "winter", "shovel", "prune", "feeder", "feed", "creatures",
]
# お知らせのヒント(やることではなく、知らせるだけ)
const NOTICES := ["apple", "visitor", "pond_rain", "pond_water", "bed", "winter", "creatures"]

var forest: Forest      # GameWorld が設定する
var land: Land
var garden: Garden
var cabin: Cabin
var pond: Pond
var market: Market
var kitchen: Kitchen
var visitors: Visitors
var wildlife: Wildlife
var bees = null          # GameWorld が設定する
var feeders = null       # GameWorld が設定する
var snow = null          # GameWorld が設定する
var has_people := false  # 訪問者の姿があるか(3D だけ Main が true にする)

var seen := []           # 出し終えたヒントの id
var current := ""        # 今出しているヒントの id。なければ ""
var _shown_for := 0.0
var _gap := 0.0
var _start = null        # はじめの足元(歩いたかを見る)
var _pos := Vector2.ZERO
var _was_inside := false

# 足元と経過時間を受けて、今出すヒントを決める
func update(pos: Vector2, delta: float) -> void:
	_pos = pos
	if _start == null:
		_start = pos
	if cabin.is_inside(pos):
		_was_inside = true
	if current != "":
		_shown_for += delta
		if _is_done(current) or (current in NOTICES and _shown_for >= SHOW_SECONDS):
			_finish()
		elif not _wants(current):
			current = ""  # 今は関係なくなった。また関係してきたら出す
		return
	_gap -= delta
	if _gap > 0.0:
		return
	for id in HINTS:
		if not (id in seen) and not _is_done(id) and _wants(id):
			current = id
			_shown_for = 0.0
			return

# K で閉じる
func dismiss() -> void:
	if current != "":
		_finish()

func _finish() -> void:
	seen.append(current)
	current = ""
	_gap = GAP_SECONDS
	dirty.emit()

func _crop_seeds() -> int:
	var n := 0
	for k in garden.seeds:
		n += int(garden.seeds[k])
	return n

func _has_produce() -> bool:
	for k in forest.produce:
		if int(forest.produce[k]) > 0:
			return true
	for k in garden.produce:
		if int(garden.produce[k]) > 0:
			return true
	for k in kitchen.stock:
		if int(kitchen.stock[k]) > 0:
			return true
	return int(bees.stock.honey) > 0

func _any_ripe() -> bool:
	return garden.crops.any(func(c): return garden.is_ripe(c))

func _any_watered() -> bool:
	return garden.crops.any(func(c): return int(c.water_days) > 0)

func _needs_water() -> bool:
	return not forest.is_raining() and garden.crops.any(func(c): return not garden.is_ripe(c) and not garden.watered_today(c))

func _cheapest_seed() -> int:
	var best := 999999
	for g in market.GOODS:
		if g.form == "crop_seed":
			best = mini(best, int(g.price))
	return best

func _logs_needed() -> int:
	var n := 0
	for i in range(cabin.stage, cabin.STAGES.size()):
		var s: Dictionary = cabin.STAGES[i]
		n += int(s.days) * int(s.logs_per_day)
	if cabin.stage < cabin.STAGES.size():
		n -= cabin.days_done * int(cabin.STAGES[cabin.stage].logs_per_day)
	return n

# そのヒントが今の状況に合っているか
func _wants(id: String) -> bool:
	match id:
		"walk":
			return forest.trees.is_empty() and land.plots.is_empty()
		"plant":
			return forest.trees.is_empty()
		"plot":
			return land.plots.is_empty()
		"buy_seeds":
			return not land.plots.is_empty() and garden.crops.is_empty() and _crop_seeds() == 0 and market.money >= _cheapest_seed()
		"sow":
			return not land.plots.is_empty() and garden.crops.is_empty() and _crop_seeds() > 0
		"water":
			return _needs_water()
		"harvest":
			return _any_ripe()
		"sell":
			return _has_produce()
		"stuck":
			return has_people and visitors.is_stuck()
		"broke":  # 手詰まりなら「収穫して売ろう」は当てはまらない
			return market.money < _cheapest_seed() and _crop_seeds() == 0 and not visitors.is_stuck()
		"apple":
			return forest.fruiting_in(forest.season) > 0
		"visitor":
			return has_people and visitors.is_here()
		"pond_rain":
			return pond.is_dug() and pond.water == 0
		"pond_water":
			return pond.is_dug() and not pond.is_frozen() and pond.water >= pond.WATER_COST and pond.is_beside(_pos) and (pond.dry_around()[0] + pond.dry_around()[1]) > 0
		"cabin_site":
			return cabin.site == null and land.plots.size() >= MIN_PLOTS_FOR_CABIN
		"cabin_logs":
			return cabin.site != null and not cabin.is_complete()
		"cabin_inside":
			return cabin.is_complete()
		"split":
			return cabin.is_complete() and kitchen.firewood <= 0
		"shovel":
			return snow.can_clear_now()
		"stove":
			return cabin.is_inside(_pos) and _has_produce()
		"bed":
			return cabin.is_inside(_pos)
		"table":
			return cabin.is_inside(_pos) and kitchen.has_food()
		"hive_make":
			return cabin.own_log_count() >= bees.LOG_COST
		"hive_bees":
			return bees.has_empty_hive()
		"honey":
			return bees.ready_count() > 0
		"winter":
			return forest.season == "winter"
		"prune":
			return forest.season == "winter" and forest.prunable_count() > 0
		"feeder":
			return feeders.can_feed_now() and int(cabin.materials.log) >= feeders.LOG_COST
		"feed":
			return feeders.can_feed_now() and not feeders.feeders.is_empty()
		"creatures":
			return has_people and not wildlife.seen.is_empty()
	return false

# そのヒントの用が済んでいるか
func _is_done(id: String) -> bool:
	match id:
		"walk":
			return _start != null and _pos.distance_to(_start) > 1.0
		"plant":
			return not forest.trees.is_empty()
		"plot":
			return not land.plots.is_empty()
		"buy_seeds":
			return _crop_seeds() > 0 or not garden.crops.is_empty()
		"sow":
			return not garden.crops.is_empty()
		"water":
			return _any_watered()
		"harvest":
			return not _any_ripe()
		"sell":
			return not _has_produce()
		"stuck":
			return not visitors.is_stuck()
		"broke":
			return market.money >= _cheapest_seed() or _crop_seeds() > 0
		"cabin_site":
			return cabin.site != null
		"cabin_logs":
			return cabin.is_complete() or int(cabin.materials.log) >= _logs_needed()
		"cabin_inside":
			return _was_inside
		"split":
			return kitchen.firewood > 0 or kitchen.cooked
		"shovel":
			return not snow.cells.is_empty()
		"stove":
			return kitchen.cooked
		"table":
			return kitchen.ever_ate()
		"prune":
			return forest.pruned_count() > 0
		"feeder":
			return not feeders.feeders.is_empty()
		"feed":
			return feeders.ever_fed()
		"visitor":
			return not visitors.is_here()
		"hive_make":
			return not bees.hives.is_empty()
		"hive_bees":
			return bees.occupied_count() > 0
		"honey":
			return bees.ready_count() == 0
	return false

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	return {"seen": seen}

func from_save(d: Dictionary) -> void:
	seen = []
	current = ""
	for id in d.get("seen", []):
		if str(id) in HINTS:
			seen.append(str(id))
