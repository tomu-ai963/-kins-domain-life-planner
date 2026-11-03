extends RefCounted

# ── お金と市場(描画を持たない) ───────────────────────────────
# 土地の南の境界の外に市場(屋台)がある。そこまで歩いて行き、種・苗木を買い、収穫物を売る。
# 値段はロシアの園芸店・市場の目安(ルーブル)。文言は Main、見た目は view/ が決める
const Forest = preload("res://logic/Forest.gd")

signal changed

const POS := Vector2(0, 56)    # 屋台の位置(m)。境界(y = 50)の 6m 外
const REACH := 4.0             # 屋台からこの距離までなら売り買いできる
const INITIAL_MONEY := 2000    # はじめの所持金(₽)。移行前のセーブにも足す

# 売っているもの。amount は 1 回で買える数(種は 1 袋 10 粒)
const GOODS := [
	{"id": "birch_seed", "species": "birch", "form": "seed", "amount": 10, "price": 60},
	{"id": "apple_seed", "species": "apple", "form": "seed", "amount": 10, "price": 80},
	{"id": "cedar_seed", "species": "cedar", "form": "seed", "amount": 10, "price": 250},
	{"id": "birch_sapling", "species": "birch", "form": "sapling", "amount": 1, "price": 400},
	{"id": "apple_sapling", "species": "apple", "form": "sapling", "amount": 1, "price": 900},
	{"id": "cedar_sapling", "species": "cedar", "form": "sapling", "amount": 1, "price": 1500},
]
# 買い取り値(1 個あたり ₽)
const SELL_PRICES := {"apple": 15}

var money := INITIAL_MONEY
var forest: Forest  # GameWorld が設定する(種・苗木・収穫物の持ち物は Forest にある)

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
	var stock: Dictionary = forest.saplings if g.form == "sapling" else forest.seeds
	stock[g.species] = int(stock.get(g.species, 0)) + int(g.amount)
	changed.emit()
	forest.changed.emit()
	return "bought"

# 収穫物 item を全部売る。売れた金額を返す(持っていなければ 0)
func sell_all(item: String) -> int:
	var n := int(forest.produce.get(item, 0))
	if n <= 0 or not SELL_PRICES.has(item):
		return 0
	var income: int = n * int(SELL_PRICES[item])
	forest.produce[item] = 0
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
