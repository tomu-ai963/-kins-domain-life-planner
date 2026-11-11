extends RefCounted

# ── お金と市場(描画を持たない) ───────────────────────────────
# 土地の南の境界の外に市場(屋台)がある。そこまで歩いて行き、種・苗木を買い、収穫物を売る。
# 値段はロシアの園芸店・市場の目安(ルーブル)。文言は Main、見た目は view/ が決める
const SaveRead = preload("res://logic/SaveRead.gd")
const Forest = preload("res://logic/Forest.gd")
const Garden = preload("res://logic/Garden.gd")
const Cabin = preload("res://logic/Cabin.gd")
const Seedlings = preload("res://logic/Seedlings.gd")
const Kitchen = preload("res://logic/Kitchen.gd")
const Bees = preload("res://logic/Bees.gd")

signal changed

const POS := Vector2(0, 56)    # 屋台の位置(m)。境界(y = 50)の 6m 外
const REACH := 4.0             # 屋台からこの距離までなら売り買いできる
const INITIAL_MONEY := 11000   # はじめの所持金(₽)。小屋の丸太 29 本(5 本束 × 6 = 9,000₽)+ 種などに 2,000₽。お金の記録がない古いセーブにも足す

# 売っているもの。amount は 1 回で買える数(木の種は 1 袋 10 粒。野菜の種は 1 区画ぶん)
const GOODS := [
	{"id": "birch_seed", "species": "birch", "form": "seed", "amount": 10, "price": 60},
	{"id": "apple_seed", "species": "apple", "form": "seed", "amount": 10, "price": 80},
	{"id": "cedar_seed", "species": "cedar", "form": "seed", "amount": 10, "price": 250},
	{"id": "birch_sapling", "species": "birch", "form": "sapling", "amount": 1, "price": 400},
	{"id": "apple_sapling", "species": "apple", "form": "sapling", "amount": 1, "price": 900},
	{"id": "cedar_sapling", "species": "cedar", "form": "sapling", "amount": 1, "price": 1500},
	{"id": "cherry_sapling", "species": "cherry", "form": "sapling", "amount": 1, "price": 700},
	{"id": "plum_sapling", "species": "plum", "form": "sapling", "amount": 1, "price": 700},
	{"id": "pear_sapling", "species": "pear", "form": "sapling", "amount": 1, "price": 900},
	# 県を選ぶようにして足した木(2026-11-11。値段は今の木に合わせた仮の数字)。その土地で育つものだけ並ぶ
	{"id": "konara_seed", "species": "konara", "form": "seed", "amount": 10, "price": 60},
	{"id": "gajumaru_seed", "species": "gajumaru", "form": "seed", "amount": 10, "price": 100},
	{"id": "sugi_seed", "species": "sugi", "form": "seed", "amount": 10, "price": 100},
	{"id": "ezomatsu_seed", "species": "ezomatsu", "form": "seed", "amount": 10, "price": 200},
	{"id": "ryukyu_pine_seed", "species": "ryukyu_pine", "form": "seed", "amount": 10, "price": 80},
	{"id": "konara_sapling", "species": "konara", "form": "sapling", "amount": 1, "price": 400},
	{"id": "gajumaru_sapling", "species": "gajumaru", "form": "sapling", "amount": 1, "price": 800},
	{"id": "sugi_sapling", "species": "sugi", "form": "sapling", "amount": 1, "price": 600},
	{"id": "ezomatsu_sapling", "species": "ezomatsu", "form": "sapling", "amount": 1, "price": 1200},
	{"id": "ryukyu_pine_sapling", "species": "ryukyu_pine", "form": "sapling", "amount": 1, "price": 500},
	{"id": "kaki_sapling", "species": "kaki", "form": "sapling", "amount": 1, "price": 900},
	{"id": "mikan_sapling", "species": "mikan", "form": "sapling", "amount": 1, "price": 900},
	{"id": "shikuwasa_sapling", "species": "shikuwasa", "form": "sapling", "amount": 1, "price": 800},
	# 2026-11-11 に足した木(2 回目)
	{"id": "keyaki_seed", "species": "keyaki", "form": "seed", "amount": 10, "price": 80},
	{"id": "kunugi_seed", "species": "kunugi", "form": "seed", "amount": 10, "price": 60},
	{"id": "hinoki_seed", "species": "hinoki", "form": "seed", "amount": 10, "price": 120},
	{"id": "deigo_seed", "species": "deigo", "form": "seed", "amount": 10, "price": 80},
	{"id": "fukugi_seed", "species": "fukugi", "form": "seed", "amount": 10, "price": 80},
	{"id": "keyaki_sapling", "species": "keyaki", "form": "sapling", "amount": 1, "price": 600},
	{"id": "kunugi_sapling", "species": "kunugi", "form": "sapling", "amount": 1, "price": 400},
	{"id": "hinoki_sapling", "species": "hinoki", "form": "sapling", "amount": 1, "price": 700},
	{"id": "deigo_sapling", "species": "deigo", "form": "sapling", "amount": 1, "price": 600},
	{"id": "fukugi_sapling", "species": "fukugi", "form": "sapling", "amount": 1, "price": 700},
	{"id": "ume_sapling", "species": "ume", "form": "sapling", "amount": 1, "price": 700},
	{"id": "kuri_sapling", "species": "kuri", "form": "sapling", "amount": 1, "price": 800},
	{"id": "mango_sapling", "species": "mango", "form": "sapling", "amount": 1, "price": 1200},
	{"id": "papaya_sapling", "species": "papaya", "form": "sapling", "amount": 1, "price": 500},
	{"id": "radish_seed", "species": "radish", "form": "crop_seed", "amount": 1, "price": 40},
	{"id": "carrot_seed", "species": "carrot", "form": "crop_seed", "amount": 1, "price": 50},
	{"id": "cucumber_seed", "species": "cucumber", "form": "crop_seed", "amount": 1, "price": 60},
	{"id": "potato_seed", "species": "potato", "form": "crop_seed", "amount": 1, "price": 150},
	{"id": "garlic_seed", "species": "garlic", "form": "crop_seed", "amount": 1, "price": 250},
	{"id": "tomato_seed", "species": "tomato", "form": "crop_seed", "amount": 1, "price": 80},
	# 県を選ぶようにして足した野菜(2026-11-11。値段は仮の数字)。ナス・ピーマン・タマネギ・サツマイモは苗を買って植える
	{"id": "daikon_seed", "species": "daikon", "form": "crop_seed", "amount": 1, "price": 50},
	{"id": "kabu_seed", "species": "kabu", "form": "crop_seed", "amount": 1, "price": 40},
	{"id": "sweet_potato_seed", "species": "sweet_potato", "form": "crop_seed", "amount": 1, "price": 150},
	{"id": "taro_seed", "species": "taro", "form": "crop_seed", "amount": 1, "price": 200},
	{"id": "eggplant_seed", "species": "eggplant", "form": "crop_seed", "amount": 1, "price": 150},
	{"id": "pepper_seed", "species": "pepper", "form": "crop_seed", "amount": 1, "price": 120},
	{"id": "pumpkin_seed", "species": "pumpkin", "form": "crop_seed", "amount": 1, "price": 60},
	{"id": "goya_seed", "species": "goya", "form": "crop_seed", "amount": 1, "price": 80},
	{"id": "cabbage_seed", "species": "cabbage", "form": "crop_seed", "amount": 1, "price": 60},
	{"id": "hakusai_seed", "species": "hakusai", "form": "crop_seed", "amount": 1, "price": 60},
	{"id": "spinach_seed", "species": "spinach", "form": "crop_seed", "amount": 1, "price": 50},
	{"id": "komatsuna_seed", "species": "komatsuna", "form": "crop_seed", "amount": 1, "price": 40},
	{"id": "edamame_seed", "species": "edamame", "form": "crop_seed", "amount": 1, "price": 60},
	{"id": "corn_seed", "species": "corn", "form": "crop_seed", "amount": 1, "price": 60},
	{"id": "onion_seed", "species": "onion", "form": "crop_seed", "amount": 1, "price": 150},
	{"id": "negi_seed", "species": "negi", "form": "crop_seed", "amount": 1, "price": 60},
	{"id": "logs", "species": "log", "form": "material", "amount": 5, "price": 1500},
	# 小屋(2026-11-11 とむ決定。値段は仮の数字)。増築は窓ガラス・かまど・釘の代金で、丸太(14 本)は別に要る。家具は増築した部屋に置く
	{"id": "cabin_extension", "species": "extension", "form": "extension", "amount": 1, "price": 8000},
	{"id": "furniture_shelf", "species": "shelf", "form": "furniture", "amount": 1, "price": 2500},
	{"id": "furniture_rocking_chair", "species": "rocking_chair", "form": "furniture", "amount": 1, "price": 4000},
	{"id": "furniture_rug", "species": "rug", "form": "furniture", "amount": 1, "price": 1500},
	{"id": "furniture_lamp", "species": "lamp", "form": "furniture", "amount": 1, "price": 1200},
	{"id": "furniture_clock", "species": "clock", "form": "furniture", "amount": 1, "price": 2000},
]
# 買い取り値(リンゴは 1 個あたり、野菜は 1kg あたりの ₽)。店頭の値段の半分くらい
# seedling_ は小屋で育てた苗(1 鉢 = 1 区画ぶん)の買い取り値。
# 保存食(Kitchen.RECIPES の id)は 1 瓶 / 1 個あたり。材料を生で売るよりおよそ 2 倍になるように置いた仮の数字
const SELL_PRICES := {
	"apple": 15, "cherry": 60, "plum": 40, "pear": 18, "kaki": 20, "mikan": 12, "shikuwasa": 50, "ume": 50, "kuri": 60, "mango": 30, "papaya": 20, "radish": 40, "carrot": 20, "cucumber": 25, "potato": 20, "garlic": 120, "tomato": 40,
	"daikon": 15, "kabu": 25, "sweet_potato": 35, "taro": 40, "eggplant": 35, "pepper": 50, "pumpkin": 30, "goya": 50,
	"cabbage": 20, "hakusai": 15, "spinach": 60, "komatsuna": 40, "edamame": 80, "corn": 60, "onion": 20, "negi": 40,
	"seedling_tomato": 150, "seedling_cucumber": 120,
	"jam": 75, "sauce": 150, "pickles": 35, "garlic_pickle": 120, "pirozhki": 12,
	"cherry_jam": 80, "plum_jam": 90, "pear_compote": 120,
	"pryanik": 40, "sbiten": 100,
	"honey": 200,  # 1kg あたり。巣箱 1 つで 1 日 100〜140₽ ほどになる仮の数字
	# 2026-11-11 に足した料理と保存食。材料を生で売るよりおよそ 2 倍(今までと同じ置き方)
	"hoshigaki": 40, "marmalade": 60, "shikuwasa_juice": 35, "umeboshi": 50, "kuri_kanroni": 60, "dried_mango": 36, "papaya_pickle": 27,
	"takuan": 30, "sauerkraut": 50, "hakusai_zuke": 38, "nasu_zuke": 44, "hoshiimo": 42, "goya_champuru": 50, "zunda": 32,
	"pumpkin_soup": 60, "imoni": 53,
}
# 春の種の注文(2026-11-11 とむ決定): 冬のあいだ、春にまく野菜の種を安く注文でき、3 月 1 日(冬が終わった最初の確認)に届く
const ORDER_RATE := 0.7        # 注文の値段の割合(店頭の 3 割引き。仮の数字)
const ORDER_SEASON := "winter" # 注文できる季節

# 保存食(Kitchen.RECIPES)の買い取り値の倍率。新鮮なものが少ない冬と、蓄えが尽きてくる春は高い(倍率は仮の数字)
const PRESERVE_RATES := {"winter": 1.5, "spring": 1.25}

var money := INITIAL_MONEY
var orders := {}           # 注文した春の種 {野菜の kind: 区画の数}。冬が終わると届く
var last_delivered := {}   # 今日の確認で届いた注文(知らせる用・保存しない)
var forest: Forest  # GameWorld が設定する(木の種・苗木・リンゴの持ち物は Forest にある)
var garden: Garden  # GameWorld が設定する(野菜の種・収穫物の持ち物は Garden にある)
var cabin: Cabin    # GameWorld が設定する(丸太の持ち物は Cabin にある)
var seedlings: Seedlings  # GameWorld が設定する(苗の持ち物は Seedlings にある)
var kitchen: Kitchen  # GameWorld が設定する(保存食の持ち物は Kitchen にある)
var bees: Bees        # GameWorld が設定する(はちみつの持ち物は Bees にある)
var feeders = null    # GameWorld が設定する(増築する場所に餌台がないか見る)

func is_near(pos: Vector2) -> bool:
	return pos.distance_to(POS) <= REACH

static func good(id: String) -> Dictionary:
	for g in GOODS:
		if g.id == id:
			return g
	return {}

# この土地の市場に並ぶ品か(木の種・苗木と野菜の種は、その土地で育つものだけ)
func sells(g: Dictionary) -> bool:
	if g.form == "seed" or g.form == "sapling":
		return forest.grows_here(g.species)
	if g.form == "crop_seed":
		return garden.grows_here(g.species)
	return true

# 1 つ買う。結果: bought / no_money / unknown(並んでいない品も)。
# 増築と家具はほかに: no_cabin(小屋が未完成) / exists・owned(もう頼んだ・持っている) / no_room(増築した部屋がない) /
# edge・center・pond・plot・tree・hive・feeder(増築する場所がふさがっている)
func buy(id: String) -> String:
	var g := good(id)
	if g.is_empty() or not sells(g):
		return "unknown"
	var problem := _cabin_problem(g)
	if problem != "":
		return problem
	if money < int(g.price):
		return "no_money"
	money -= int(g.price)
	if g.form == "extension":
		cabin.start_extension()
		changed.emit()
		return "bought"
	if g.form == "furniture":
		cabin.add_furniture(g.species)
		changed.emit()
		return "bought"
	var stock: Dictionary = forest.seeds
	if g.form == "sapling":
		stock = forest.saplings
	elif g.form == "crop_seed":
		stock = garden.seeds
	elif g.form == "material":
		stock = cabin.materials
	stock[g.species] = int(stock.get(g.species, 0)) + int(g.amount)
	changed.emit()
	forest.changed.emit()
	return "bought"

# 増築・家具を今買えない理由("" なら買える)
func _cabin_problem(g: Dictionary) -> String:
	if g.form == "extension":
		var p: String = cabin.ext_problem()
		if p != "":
			return p
		var r: Rect2 = cabin.ext_rect()
		if bees != null and bees.hives.any(func(h): return r.grow(bees.CLEARANCE).has_point(h.pos)):
			return "hive"
		if feeders != null and feeders.feeders.any(func(f): return r.grow(bees.CLEARANCE).has_point(f.pos)):
			return "feeder"
	elif g.form == "furniture":
		if not cabin.has_extension():
			return "no_room"
		if cabin.has_furniture(g.species):
			return "owned"
	return ""

# 増築・家具をもう買ったか(画面で「済」を出す用)
func is_owned(g: Dictionary) -> bool:
	if g.form == "extension":
		return cabin.ext_started()
	if g.form == "furniture":
		return cabin.has_furniture(g.species)
	return false

# 注文できる野菜(この土地で育ち、春にまけて、苗からでなく種でまけるもの)
func orderable() -> Array:
	var list := []
	for kind in Garden.CROPS:
		var crop: Dictionary = Garden.CROPS[kind]
		if "spring" in crop.seasons and not crop.get("seedling_only", false) and garden.grows_here(kind):
			list.append(kind)
	return list

static func order_price(kind: String) -> int:
	return roundi(int(good(kind + "_seed").price) * ORDER_RATE)

func can_order() -> bool:
	return forest.season == ORDER_SEASON

# 春の種を 1 区画ぶん注文する。結果: ordered / not_season / no_money / unknown
func order(kind: String) -> String:
	if not (kind in orderable()):
		return "unknown"
	if not can_order():
		return "not_season"
	if money < order_price(kind):
		return "no_money"
	money -= order_price(kind)
	orders[kind] = int(orders.get(kind, 0)) + 1
	changed.emit()
	return "ordered"

func order_count() -> int:
	var n := 0
	for kind in orders:
		n += int(orders[kind])
	return n

# 冬が終わっていれば、注文した種を届ける(日付が変わったときに呼ぶ)。閉じていたあいだに冬が終わった場合も届く
func deliver_orders() -> void:
	last_delivered = {}
	if can_order() or orders.is_empty():
		return
	for kind in orders:
		garden.seeds[kind] = int(garden.seeds.get(kind, 0)) + int(orders[kind])
	last_delivered = orders
	orders = {}
	changed.emit()

# 収穫物 item の持ち物の入れ物と、その中のキー
func pile_of(item: String) -> Dictionary:
	if item.begins_with("seedling_"):
		return seedlings.ready
	if Kitchen.RECIPES.has(item):
		return kitchen.stock
	if item == "honey":
		return bees.stock
	return garden.produce if garden.produce.has(item) else forest.produce

func key_of(item: String) -> String:
	return item.trim_prefix("seedling_")

# 収穫物 item をいくつ持っているか
func count_of(item: String) -> int:
	return int(pile_of(item).get(key_of(item), 0))

# 季節 season での買い取り値の倍率
static func price_rate(item: String, season: String) -> float:
	return float(PRESERVE_RATES.get(season, 1.0)) if Kitchen.RECIPES.has(item) else 1.0

# 季節 season での 1 つあたりの買い取り値(₽)
static func price_in(item: String, season: String) -> int:
	return roundi(int(SELL_PRICES[item]) * price_rate(item, season))

# 今の季節の 1 つあたりの買い取り値(₽)
func sell_price(item: String) -> int:
	return price_in(item, forest.season)

# 収穫物 item を全部売る。売れた金額を返す(持っていなければ 0)
func sell_all(item: String) -> int:
	var pile: Dictionary = pile_of(item)
	var key := key_of(item)
	var n := int(pile.get(key, 0))
	if n <= 0 or not SELL_PRICES.has(item):
		return 0
	var income: int = n * sell_price(item)
	pile[key] = 0
	money += income
	changed.emit()
	forest.changed.emit()
	return income

# ── セーブ用 ──────────────────────────────────────────────
func to_save() -> Dictionary:
	return {"money": money, "orders": orders}

func from_save(d: Dictionary) -> void:
	# 読めない所持金は、はじめの所持金にはせず 0 にする(増やす方向に間違えない)。マイナスも 0
	money = maxi(0, SaveRead.whole(d, "money", INITIAL_MONEY if not d.has("money") else 0))
	orders = {}
	var od := SaveRead.dict(d.get("orders"))
	for kind in od:
		if Garden.CROPS.has(kind) and SaveRead.count(od, kind) > 0:
			orders[kind] = SaveRead.count(od, kind)
	changed.emit()
