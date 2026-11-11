extends RefCounted

# ── 土地を訪ねてくる人(描画を持たない) ─────────────────────────────
# 2〜3 日に 1 人、近所の人が来る。来る日と人は日付で決まる(開き直しても変わらない)。
# 渡せるものがあれば頼みごとをして、渡すと市場より少し高いお金か、種や苗をくれる(物々交換)。
# 渡せるものがなければ話すだけの日になる。頼みごとは断ってもよく、その日が終わると帰る(罰はない)。
# 収入の手段が尽きているとき(is_stuck)だけは、種を少し分けてくれる(冬はまける種がないのでお金)。
# フョードルさん(養蜂家)は、空の巣箱があれば蜂を分けてくれる(kind = bees)。
# 冬は、小屋が建っていて今日のうちに割れる丸太があれば、薪を頼まれる(item = firewood。2026-11-11 とむ決定)。
# 冬のお礼の種は、春にまける種(冬にまける種はないので)。
# 今日の中身は最初に決めた時点で保存する(収穫や売買で中身が変わらないように)。
# 親しさ: 人ごとに、話すと +1、蜂を分けてもらうと +2、頼みごとに応えると +3。断っても減らない。
# 親しくなるほど話す言葉が増え(Main)、話すだけの日にときどき贈り物を持ってくる(kind = gift)。
# 文言は Main、見た目は view/ が決める
const SaveRead = preload("res://logic/SaveRead.gd")
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
	"nina": {"name": "ニーナさん", "likes": ["tomato", "cucumber", "carrot", "radish", "potato", "plum"]},
	"fyodor": {"name": "フョードルさん", "likes": ["garlic", "apple", "pear", "garlic_pickle", "potato", "carrot"]},
	"tanya": {"name": "ターニャさん", "likes": ["honey", "cherry", "apple", "pirozhki", "jam", "cherry_jam", "pryanik", "carrot", "radish"]},
	"pavel": {"name": "パーヴェルさん", "likes": ["sauce", "pickles", "jam", "plum_jam", "pear_compote", "sbiten", "tomato", "cucumber"]},
}
const ORDER := ["nina", "fyodor", "tanya", "pavel"]  # 来る順番

# 1 回に頼む量(リンゴは個、野菜は kg、保存食は瓶 / 個)
const ASK := {
	"apple": 5, "cherry": 1, "plum": 2, "pear": 4, "kaki": 4, "mikan": 5, "shikuwasa": 1, "cherry_jam": 1, "plum_jam": 1, "pear_compote": 1,
	"radish": 3, "carrot": 5, "cucumber": 5, "potato": 5, "garlic": 1, "tomato": 5,
	"daikon": 5, "kabu": 3, "sweet_potato": 5, "taro": 3, "eggplant": 3, "pepper": 3, "pumpkin": 3, "goya": 2,
	"cabbage": 3, "hakusai": 3, "spinach": 2, "komatsuna": 2, "edamame": 2, "corn": 2, "onion": 5, "negi": 2,
	"jam": 2, "sauce": 2, "pickles": 3, "garlic_pickle": 1, "pirozhki": 5, "honey": 1,
	"pryanik": 5, "sbiten": 2,
}
const BEEKEEPER := "fyodor"  # 蜂を分けてくれる人
const FIREWOOD := "firewood"   # 冬の頼みごとの薪(Kitchen.firewood。市場では売れない)
const FIREWOOD_ASK := 4        # 1 回に頼む薪(回分)。薪割り 2 回ぶん
const FIREWOOD_PRICE := 50     # お礼を決めるときの薪 1 回分の値段(₽。丸太 1 本 300₽ = 10 回分より高い。冬は薪が要るので。仮の数字)

# 親しさ。LEVELS[n] 以上で段階 n。同じ人は 10 日に 1 回来るので、頼みごとに応え続けると 顔なじみ 10 日・親しい 30 日・家族のよう 50 日(仮の数字)
const LEVELS := [0, 3, 8, 15]
const LEVEL_NAMES := ["顔見知り", "顔なじみ", "親しい", "家族のよう"]
const POINTS_CHAT := 1
const POINTS_BEES := 2
const POINTS_REQUEST := 3
const GIFT_CHANCE := [0.0, 0.15, 0.25, 0.35]  # 話すだけの日に贈り物を持ってくる割合(段階ごと。仮の数字)

var forest: Forest      # GameWorld が設定する
var garden: Garden
var seedlings: Seedlings
var market: Market
var kitchen = null      # GameWorld が設定する(鍋の中身を見る)
var bees = null         # GameWorld が設定する(空の巣箱を見る)
var feeders = null      # GameWorld が設定する(姿が餌台を回り込む)

var visit := {}         # 今日の訪問 {day, who, kind: request/chat/help/bees, item, amount, reward: {...}, done: bool, line: int}。来ない日は who がない
var last_reward := {}   # 直前にもらったお礼(文言用)
var closeness := {}     # 人ごとの親しさの点数 {who: 点}
var last_level_up := "" # 直前に親しさの段階が上がった人(文言用。読むと Main が消す)

func _init() -> void:
	for id in CAST:
		closeness[id] = 0

# 親しさの段階(0〜3)
func level_of(person: String) -> int:
	var points: int = int(closeness.get(person, 0))
	var level := 0
	for i in range(LEVELS.size()):
		if points >= int(LEVELS[i]):
			level = i
	return level

func _gain(person: String, points: int) -> void:
	var before := level_of(person)
	if kitchen != null and kitchen.has_effect("sweet"):  # 甘いものを食べた日は親しくなりやすい
		points += kitchen.MEAL_POINTS
	closeness[person] = int(closeness.get(person, 0)) + points
	if level_of(person) > before:
		last_level_up = person

static func is_visit_day(day: int) -> bool:
	return (day % VISIT_CYCLE) in VISIT_DAYS

# その日に来る人。順番に交代する
static func who_on(day: int) -> String:
	var turn: int = int(day / float(VISIT_CYCLE)) * VISIT_DAYS.size() + VISIT_DAYS.find(day % VISIT_CYCLE)
	return ORDER[turn % ORDER.size()]

# 日付が変わっていたら、今日の訪問を決める。決めたら true
func check_today() -> bool:
	var day: int = forest.day_number()
	if day < int(visit.get("day", -1)):
		return false  # 時計が戻ったときは、前の日の訪問を作り直さない(お礼をもう一度もらえないように)
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
	if kitchen != null and not kitchen.all_empty():
		return false
	return forest.fruiting_in(forest.season) == 0

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
		if garden.can_sow_now(kind) and not crop.get("seedling_only", false):
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
	_gain(who(), POINTS_BEES)
	dirty.emit()
	changed.emit()
	return "received"

func has_gift() -> bool:
	return is_here() and visit.kind == "gift"

# 贈り物の中身。人ごとに決まっている。ニーナさんは今まける種(冬は塩漬け)
func _gift_reward(person: String, rng: RandomNumberGenerator) -> Dictionary:
	match person:
		"nina":
			var sowable := []
			for kind in Garden.CROPS:
				var crop: Dictionary = Garden.CROPS[kind]
				if garden.can_sow_now(kind) and not crop.get("seedling_only", false):
					sowable.append(kind)
			if sowable.is_empty():
				return {"type": "item", "item": "pickles", "count": 2}
			return {"type": "crop_seed", "kind": sowable[rng.randi_range(0, sowable.size() - 1)], "count": 2}
		"fyodor":
			return {"type": "item", "item": "honey", "count": 1}
		"tanya":
			return {"type": "item", "item": "pirozhki", "count": 3}
	return {"type": "firewood", "count": 2}

# 分けてくれるもの(手詰まりのとき)や贈り物を受け取る。結果: received / none
func receive_help() -> String:
	if not has_help() and not has_gift():
		return "none"
	_receive(visit.reward)
	last_reward = visit.reward
	visit.done = true
	_gain(who(), POINTS_CHAT)
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
	# 冬は薪を頼む(今は持っていなくても、今日のうちに割って渡せるなら)
	if forest.season == "winter" and can_ask_firewood():
		item = FIREWOOD
	if item == "" or rng.randf() < CHAT_CHANCE:
		var chance: float = GIFT_CHANCE[level_of(who)]
		if chance > 0.0 and rng.randf() < chance:
			v.kind = "gift"
			v.reward = _gift_reward(who, rng)
		return v
	var amount: int = FIREWOOD_ASK if item == FIREWOOD else mini(int(ASK[item]), available(item))
	v.kind = "request"
	v.item = item
	v.amount = amount
	v.reward = _choose_reward(item, amount, rng)
	return v

# 薪を頼めるか: 小屋が建っていて、割ってある薪と今日割れる丸太で FIREWOOD_ASK に届く
func can_ask_firewood() -> bool:
	if kitchen == null or not kitchen.cabin.is_complete():
		return false
	var can_make: int = kitchen.firewood + kitchen.log_left + int(kitchen.cabin.materials.log) * kitchen.LOG_FIRES
	return can_make >= FIREWOOD_ASK

# 頼まれたものを今いくつ持っているか(薪は割ってある分)
func have(item: String) -> int:
	if item == FIREWOOD:
		return kitchen.firewood if kitchen != null else 0
	return market.count_of(item)

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
	if item == FIREWOOD:
		return amount * FIREWOOD_PRICE
	return amount * market.sell_price(item)  # 冬の保存食は市場でも高いので、お礼も今の値段から決める

# お礼。市場で売るより少し高い。種や苗は値段に合う数だけ。今の季節に使えないものはお金にする
func _choose_reward(item: String, amount: int, rng: RandomNumberGenerator) -> Dictionary:
	var worth: float = value_of(item, amount) * BONUS
	var money := {"type": "money", "amount": ceili(worth / MONEY_ROUND) * MONEY_ROUND}
	var options := []
	var frost_winter: bool = forest.season == "winter" and forest.climate().has_frost()
	var sow_season: String = "spring" if frost_winter else forest.season  # 霜の降りる冬は春にまける種
	for kind in Garden.CROPS:
		var crop: Dictionary = Garden.CROPS[kind]
		if garden.can_sow_in(kind, sow_season) and not crop.get("seedling_only", false):
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
	if have(visit.item) < int(visit.amount):
		return "short"
	if visit.item == FIREWOOD:
		kitchen.firewood -= int(visit.amount)
		kitchen.changed.emit()
	else:
		var pile: Dictionary = market.pile_of(visit.item)
		var key: String = market.key_of(visit.item)
		pile[key] = int(pile[key]) - int(visit.amount)
	_receive(visit.reward)
	last_reward = visit.reward
	visit.done = true
	_gain(who(), POINTS_REQUEST)
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
		"item":
			var pile: Dictionary = market.pile_of(r.item)
			var key: String = market.key_of(r.item)
			pile[key] = int(pile.get(key, 0)) + int(r.count)
		"firewood":
			kitchen.add_firewood(int(r.count))

# 話し終えた(話すだけの日)。帰っていく
func finish_chat() -> void:
	if is_here() and visit.kind == "chat":
		visit.done = true
		_gain(who(), POINTS_CHAT)
		dirty.emit()
		changed.emit()

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	return {"visit": visit, "closeness": closeness}

func from_save(d: Dictionary) -> void:
	visit = {}
	# 親しさの記録がないセーブは、みんな顔見知りから
	var saved := SaveRead.dict(d.get("closeness"))
	for id in CAST:
		closeness[id] = SaveRead.count(saved, id)
	var v := SaveRead.dict(d.get("visit"))
	if not SaveRead.is_num(v.get("day")):
		return
	if v.has("who") and not CAST.has(SaveRead.text(v, "who")):
		return
	visit = v.duplicate(true)
	visit.day = SaveRead.whole(v, "day")
	if visit.has("amount"):
		visit.amount = SaveRead.count(v, "amount")
	if visit.has("line"):
		visit.line = SaveRead.count(v, "line")
	if visit.has("done"):
		visit.done = SaveRead.flag(v, "done", true)
	# JSON から読むと数は小数になる。お礼の数も整数に戻す(保存し直したときに 1 → 1.0 と変わらないように)
	if typeof(visit.get("reward")) == TYPE_DICTIONARY:
		for key in ["count", "amount"]:
			if visit.reward.has(key):
				visit.reward[key] = int(visit.reward[key])
	changed.emit()
