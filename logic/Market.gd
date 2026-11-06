extends RefCounted

# ── お金と市場(描画を持たない) ───────────────────────────────
# 土地の南の境界の外に市場(屋台)がある。そこまで歩いて行き、種・苗木を買い、収穫物を売る。
# 値段はロシアの園芸店・市場の目安(ルーブル)。文言は Main、見た目は view/ が決める
const Forest = preload("res://logic/Forest.gd")
const Garden = preload("res://logic/Garden.gd")
const Cabin = preload("res://logic/Cabin.gd")
const Seedlings = preload("res://logic/Seedlings.gd")
const Kitchen = preload("res://logic/Kitchen.gd")
const Bees = preload("res://logic/Bees.gd")

signal changed

const POS := Vector2(0, 56)    # 屋台の位置(m)。境界(y = 50)の 6m 外
const REACH := 4.0             # 屋台からこの距離までなら売り買いできる
const INITIAL_MONEY := 2000    # はじめの所持金(₽)。移行前のセーブにも足す

# 売っているもの。amount は 1 回で買える数(木の種は 1 袋 10 粒。野菜の種は 1 区画ぶん)
const GOODS := [
	{"id": "birch_seed", "species": "birch", "form": "seed", "amount": 10, "price": 60},
	{"id": "apple_seed", "species": "apple", "form": "seed", "amount": 10, "price": 80},
	{"id": "cedar_seed", "species": "cedar", "form": "seed", "amount": 10, "price": 250},
	{"id": "birch_sapling", "species": "birch", "form": "sapling", "amount": 1, "price": 400},
	{"id": "apple_sapling", "species": "apple", "form": "sapling", "amount": 1, "price": 900},
	{"id": "cedar_sapling", "species": "cedar", "form": "sapling", "amount": 1, "price": 1500},
	{"id": "radish_seed", "species": "radish", "form": "crop_seed", "amount": 1, "price": 40},
	{"id": "carrot_seed", "species": "carrot", "form": "crop_seed", "amount": 1, "price": 50},
	{"id": "cucumber_seed", "species": "cucumber", "form": "crop_seed", "amount": 1, "price": 60},
	{"id": "potato_seed", "species": "potato", "form": "crop_seed", "amount": 1, "price": 150},
	{"id": "garlic_seed", "species": "garlic", "form": "crop_seed", "amount": 1, "price": 250},
	{"id": "tomato_seed", "species": "tomato", "form": "crop_seed", "amount": 1, "price": 80},
	{"id": "logs", "species": "log", "form": "material", "amount": 5, "price": 1500},
]
# 買い取り値(リンゴは 1 個あたり、野菜は 1kg あたりの ₽)。店頭の値段の半分くらい
# seedling_ は小屋で育てた苗(1 鉢 = 1 区画ぶん)の買い取り値。
# 保存食(Kitchen.RECIPES の id)は 1 瓶 / 1 個あたり。材料を生で売るよりおよそ 2 倍になるように置いた仮の数字
const SELL_PRICES := {
	"apple": 15, "radish": 40, "carrot": 20, "cucumber": 25, "potato": 20, "garlic": 120, "tomato": 40,
	"seedling_tomato": 150, "seedling_cucumber": 120,
	"jam": 75, "sauce": 150, "pickles": 35, "garlic_pickle": 120, "pirozhki": 12,
	"honey": 200,  # 1kg あたり。巣箱 1 つで 1 日 100〜140₽ ほどになる仮の数字
}

var money := INITIAL_MONEY
var forest: Forest  # GameWorld が設定する(木の種・苗木・リンゴの持ち物は Forest にある)
var garden: Garden  # GameWorld が設定する(野菜の種・収穫物の持ち物は Garden にある)
var cabin: Cabin    # GameWorld が設定する(丸太の持ち物は Cabin にある)
var seedlings: Seedlings  # GameWorld が設定する(苗の持ち物は Seedlings にある)
var kitchen: Kitchen  # GameWorld が設定する(保存食の持ち物は Kitchen にある)
var bees: Bees        # GameWorld が設定する(はちみつの持ち物は Bees にある)

func is_near(pos: Vector2) -> bool:
	return pos.distance_to(POS) <= REACH

static func good(id: String) -> Dictionary:
	for g in GOODS:
		if g.id == id:
			return g
	return {}

# 1 つ買う。結果: bought / no_money / unknown
func buy(id: String) -> String:
	var g := good(id)
	if g.is_empty():
		return "unknown"
	if money < int(g.price):
		return "no_money"
	money -= int(g.price)
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

# 収穫物 item を全部売る。売れた金額を返す(持っていなければ 0)
func sell_all(item: String) -> int:
	var pile: Dictionary = pile_of(item)
	var key := key_of(item)
	var n := int(pile.get(key, 0))
	if n <= 0 or not SELL_PRICES.has(item):
		return 0
	var income: int = n * int(SELL_PRICES[item])
	pile[key] = 0
	money += income
	changed.emit()
	forest.changed.emit()
	return income

# ── セーブ用 ──────────────────────────────────────────────
func to_save() -> Dictionary:
	return {"money": money}

func from_save(d: Dictionary) -> void:
	money = int(d.get("money", INITIAL_MONEY))
	changed.emit()
