extends RefCounted

# ── 土地を訪ねてくる人(描画を持たない) ─────────────────────────────
# 2〜3 日に 1 人、近所の人が来る。来る日と人は日付で決まる(開き直しても変わらない)。
# 渡せるものがあれば頼みごとをして、渡すと市場より少し高いお金か、種や苗をくれる(物々交換)。
# 渡せるものがなければ話すだけの日になる。頼みごとは断ってもよく、その日が終わると帰る(罰はない)。
# 収入の手段が尽きているとき(is_stuck)だけは、種を少し分けてくれる(冬はまける種がないのでお金)。
# フョードルさん(養蜂家)は、空の巣箱があれば蜂を分けてくれる(kind = bees)。
# 今日の中身は最初に決めた時点で保存する(収穫や売買で中身が変わらないように)。
# 文言は Main、見た目は view/ が決める
const Forest = preload("res://logic/Forest.gd")
const Garden = preload("res://logic/Garden.gd")
const Seedlings = preload("res://logic/Seedlings.gd")
const Market = preload("res://logic/Market.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const VISIT_CYCLE := 5            # 5 日に 2 回来る(間は 2 日と 3 日)
const VISIT_DAYS := [0, 2]        # 通し番号を VISIT_CYCLE で割った余りがこれなら来る
const CHAT_CHANCE := 0.3          # 渡せるものがあっても、話すだけになる割合
const BONUS := 1.3                # 市場の買い取り値に対するお礼の倍率
const MONEY_ROUND := 10           # お金のお礼はこの単位に切り上げる
const SEEDLING_SEASONS := ["spring", "summer"]  # 苗をお礼にくれる季節(植えられる季節)
const HELP_SEEDS := 3             # 手詰まりのときに分けてくれる種(区画の数)
const HELP_MONEY := 200           # まける種がない冬に分けてくれるお金。春に種を買える額

# likes: 頼みたいもの(先頭ほど頼みやすい)。なければ、渡せるものの中から頼む
const CAST := {
	"nina": {"name": "ニーナさん", "likes": ["tomato", "cucumber", "carrot", "radish", "potato"]},
	"fyodor": {"name": "フョードルさん", "likes": ["garlic", "apple", "garlic_pickle", "potato", "carrot"]},
	"tanya": {"name": "ターニャさん", "likes": ["honey", "apple", "pirozhki", "jam", "carrot", "radish"]},
	"pavel": {"name": "パーヴェルさん", "likes": ["sauce", "pickles", "jam", "tomato", "cucumber"]},
}
const ORDER := ["nina", "fyodor", "tanya", "pavel"]  # 来る順番

# 1 回に頼む量(リンゴは個、野菜は kg、保存食は瓶 / 個)
const ASK := {
	"apple": 5, "radish": 3, "carrot": 5, "cucumber": 5, "potato": 5, "garlic": 1, "tomato": 5,
	"jam": 2, "sauce": 2, "pickles": 3, "garlic_pickle": 1, "pirozhki": 5, "honey": 1,
}
const BEEKEEPER := "fyodor"  # 蜂を分けてくれる人

var forest: Forest      # GameWorld が設定する
var garden: Garden
var seedlings: Seedlings
var market: Market
var kitchen = null      # GameWorld が設定する(鍋の中身を見る)
var bees = null         # GameWorld が設定する(空の巣箱を見る)

var visit := {}         # 今日の訪問 {day, who, kind: request/chat/help/bees, item, amount, reward: {...}, done: bool, line: int}。来ない日は who がない
var last_reward := {}   # 直前にもらったお礼(文言用)

static func is_visit_day(day: int) -> bool:
	return (day % VISIT_CYCLE) in VISIT_DAYS

# その日に来る人。順番に交代する
static func who_on(day: int) -> String:
	var turn: int = int(day / float(VISIT_CYCLE)) * VISIT_DAYS.size() + VISIT_DAYS.find(day % VISIT_CYCLE)
	return ORDER[turn % ORDER.size()]

# 日付が変わっていたら、今日の訪問を決める。決めたら true
func check_today() -> bool:
	var day: int = forest.day_number()
	if int(visit.get("day", -1)) == day:
		# 話すだけの予定だった人も、手詰まりなら助けてくれる(その日のうちに手詰まりになったとき)
		if is_here() and visit.kind == "chat" and is_stuck():
			_make_help(visit)
			dirty.emit()
			changed.emit()
		elif is_here() and visit.kind == "chat" and visit.who == BEEKEEPER and _can_share_bees():
			visit.kind = "bees"  # その日のうちに巣箱ができたとき
			dirty.emit()
			changed.emit()
		return false
	visit = _generate(day)
	dirty.emit()
	changed.emit()
	return true

# 収入の手段が尽きているか。種も買えず、畑が空で、売れるものもなく、待てば手に入るものもない
func is_stuck() -> bool:
	if market.money >= _cheapest_seed():
		return false
	for k in garden.seeds:
		if int(garden.seeds[k]) > 0:
			return false
	if not garden.crops.is_empty():
		return false
	for item in market.SELL_PRICES:
		if market.count_of(item) > 0:
			return false
	if not seedlings.pots.is_empty():
		return false
	if kitchen != null and not kitchen.is_empty():
		return false
	return not (forest.season == "autumn" and forest.fruiting_apples() > 0)

func _cheapest_seed() -> int:
	var best := 999999
	for g in market.GOODS:
		if g.form == "crop_seed":
			best = mini(best, int(g.price))
	return best

func _make_help(v: Dictionary) -> void:
	v.kind = "help"
	v.reward = _help_reward()

# 今まける一番安い種を少し。冬はまける種がないので、お金
func _help_reward() -> Dictionary:
	var best := ""
	var best_price := 999999
	for kind in Garden.CROPS:
		var crop: Dictionary = Garden.CROPS[kind]
		if forest.season in crop.seasons and not crop.get("seedling_only", false):
			var price: int = int(market.good(kind + "_seed").price)
			if price < best_price:
				best_price = price
				best = kind
	if best == "":
		return {"type": "money", "amount": HELP_MONEY}
	return {"type": "crop_seed", "kind": best, "count": HELP_SEEDS}

func has_help() -> bool:
	return is_here() and visit.kind == "help"

func has_bees() -> bool:
	return is_here() and visit.kind == "bees"

func _can_share_bees() -> bool:
	return bees != null and bees.can_share_now()

# 蜂を分けてもらう。結果: received / none / no_hive(空の巣箱がなくなった)
func receive_bees() -> String:
	if not has_bees():
		return "none"
	if not bees.add_colony():
		return "no_hive"
	visit.done = true
	dirty.emit()
	changed.emit()
	return "received"

# 分けてくれるものを受け取る。結果: received / none
func receive_help() -> String:
	if not has_help():
		return "none"
	_receive(visit.reward)
	last_reward = visit.reward
	visit.done = true
	market.changed.emit()
	forest.changed.emit()
	dirty.emit()
	changed.emit()
	return "received"

func _generate(day: int) -> Dictionary:
	if not is_visit_day(day):
		return {"day": day}
	var rng := RandomNumberGenerator.new()
	rng.seed = ("visit:%d" % day).hash()
	var who: String = who_on(day)
	var v := {"day": day, "who": who, "kind": "chat", "done": false, "line": rng.randi_range(0, 99)}
	if is_stuck():
		_make_help(v)
		return v
	if who == BEEKEEPER and _can_share_bees():
		v.kind = "bees"
		return v
	var item: String = _choose_item(who)
	if item == "" or rng.randf() < CHAT_CHANCE:
		return v
	var amount: int = mini(int(ASK[item]), available(item))
	v.kind = "request"
	v.item = item
	v.amount = amount
	v.reward = _choose_reward(item, amount, rng)
	return v

# 今日渡せるもののうち、その人が頼むもの。なければ ""
func _choose_item(who: String) -> String:
	for item in CAST[who].likes:
		if available(item) > 0:
			return item
	for item in ASK:
		if available(item) > 0:
			return item
	return ""

# 渡せる量: 持っている分と、今収穫できる畑の分
func available(item: String) -> int:
	var n: int = market.count_of(item)
	for c in garden.crops:
		if c.kind == item and garden.is_ripe(c):
			n += int(Garden.CROPS[item].yield_kg)
	return n

func value_of(item: String, amount: int) -> int:
	return amount * int(market.SELL_PRICES[item])

# お礼。市場で売るより少し高い。種や苗は値段に合う数だけ。今の季節に使えないものはお金にする
func _choose_reward(item: String, amount: int, rng: RandomNumberGenerator) -> Dictionary:
	var worth: float = value_of(item, amount) * BONUS
	var money := {"type": "money", "amount": ceili(worth / MONEY_ROUND) * MONEY_ROUND}
	var options := []
	for kind in Garden.CROPS:
		var crop: Dictionary = Garden.CROPS[kind]
		if forest.season in crop.seasons and not crop.get("seedling_only", false):
			options.append({"type": "crop_seed", "kind": kind, "count": maxi(1, int(worth / market.good(kind + "_seed").price))})
	if forest.season in SEEDLING_SEASONS:
		for kind in Seedlings.SEEDLING_CROPS:
			options.append({"type": "seedling", "kind": kind, "count": maxi(1, int(worth / market.SELL_PRICES["seedling_" + kind]))})
	if options.is_empty() or rng.randf() < 0.5:
		return money
	return options[rng.randi_range(0, options.size() - 1)]

func is_here() -> bool:
	return visit.has("who") and not bool(visit.done)

func who() -> String:
	return str(visit.get("who", ""))

func has_request() -> bool:
	return is_here() and visit.kind == "request"

# 頼まれたものを渡す。結果: given / none / short(足りない)
func give() -> String:
	if not has_request():
		return "none"
	if market.count_of(visit.item) < int(visit.amount):
		return "short"
	var pile: Dictionary = market.pile_of(visit.item)
	var key: String = market.key_of(visit.item)
	pile[key] = int(pile[key]) - int(visit.amount)
	_receive(visit.reward)
	last_reward = visit.reward
	visit.done = true
	market.changed.emit()
	forest.changed.emit()
	dirty.emit()
	changed.emit()
	return "given"

func _receive(r: Dictionary) -> void:
	match r.type:
		"money":
			market.money += int(r.amount)
		"crop_seed":
			garden.seeds[r.kind] = int(garden.seeds[r.kind]) + int(r.count)
		"seedling":
			seedlings.ready[r.kind] = int(seedlings.ready[r.kind]) + int(r.count)

# 話し終えた(話すだけの日)。帰っていく
func finish_chat() -> void:
	if is_here() and visit.kind == "chat":
		visit.done = true
		dirty.emit()
		changed.emit()

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	return {"visit": visit}

func from_save(d: Dictionary) -> void:
	visit = {}
	var v = d.get("visit", {})
	if typeof(v) != TYPE_DICTIONARY or not v.has("day"):
		return
	if v.has("who") and not CAST.has(str(v.who)):
		return
	visit = v.duplicate(true)
	visit.day = int(visit.day)
	if visit.has("amount"):
		visit.amount = int(visit.amount)
	if visit.has("line"):
		visit.line = int(visit.line)
	changed.emit()
