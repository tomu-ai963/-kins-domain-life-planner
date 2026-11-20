extends RefCounted

# ── 市場の画面: 買う列と売る列のページ・品の名前・売り買いと注文 ──
# Main.gd から分けた(レビュー C4)。Main が 1 つ持ち(Main.market_panel)、main を通して world・HUD・ほかの画面を使う
const MainScript = preload("res://Main.gd")
const GameWorld = preload("res://logic/GameWorld.gd")
const Msg = preload("res://view/main/Messages.gd")

var main: MainScript
var world: GameWorld:
	get:
		return main.world
var hud: Node:
	get:
		return main.get_node("HUD")

# 市場のページ。買う列は品の種類(Market.GOODS の form)で、売る列は収穫物と保存食で分ける
# 野菜の種は組(Garden.GROUPS)で 3 ページに分ける(2026-11-11。野菜が増えて 1 列 15 行を超えるため)
const BUY_PAGES := [
	{"name": "木の種", "forms": ["seed"]},
	{"name": "森の木の苗木", "forms": ["sapling"], "tree_groups": ["broadleaf", "conifer"]},  # 木が増えて 1 列 15 行を超えるため分けた
	{"name": "果樹の苗木", "forms": ["sapling"], "tree_groups": ["fruit"]},
	{"name": "根菜といもの種", "forms": ["crop_seed"], "groups": ["root", "imo"]},
	{"name": "実もの野菜の種と苗", "forms": ["crop_seed"], "groups": ["fruit"]},
	{"name": "葉ものと香味野菜の種", "forms": ["crop_seed"], "groups": ["leaf", "aroma"]},
	{"name": "豆と穀物の種", "forms": ["crop_seed"], "groups": ["bean"]},  # 穀物を足して 1 列 15 行を超えるため分けた(2026-11-14)
	{"name": "丸太", "forms": ["material"]},
	{"name": "小屋", "forms": ["extension", "furniture"]},
	{"name": "道具と燃料", "forms": ["tool", "fuel", "straw"]},
]
# 売る列のページ。果物ははちみつも、実もの野菜は苗も。野菜の組は SELL_GROUPS(果樹と野菜が増えて 1 列 15 行を超えるため分けた)
const SELL_PAGES := ["果物", "根菜といも", "実もの野菜と苗", "葉もの・香味野菜", "豆と穀物と粉", "果物とはちみつの保存食", "野菜の保存食", "穀物と粉の料理", "自然の木の種 1", "自然の木の種 2"]
const WILD_SEEDS_PER_PAGE := 10  # 自然の木の種の売る列は 10 種類ずつ(ほかの土地の種を持つこともあるので)
const SELL_GROUPS := {"root": 1, "imo": 1, "fruit": 2, "leaf": 3, "bean": 4, "aroma": 3}
var _buy_page := 0           # 市場の買う列の今のページ(閉じても覚えておく)
var _sell_page := 0          # 市場の売る列の今のページ

func _init(m: MainScript) -> void:
	main = m

# 市場の品の表示名。例: 「白樺の種(10粒)」「リンゴの苗木(樹齢3年)」「じゃがいもの種いも(春にまく)」「丸太(5本)」
func good_name(g: Dictionary) -> String:
	if g.form == "tool":
		return main.TOOL_NAMES[g.species]
	if g.form == "fuel":
		return "ガソリン(%s・持っている %s)" % [main.gas_text(int(g.amount)), main.gas_text(world.tools.gas)]
	if g.form == "extension":
		return "小屋の増築(西に1部屋・丸太%d本は別)" % world.cabin.ext_total_logs()
	if g.form == "furniture":
		return main.FURNITURE_NAMES[g.species]
	if g.form == "material":
		return "丸太(%d本)" % g.amount
	if g.form == "straw":
		return "わら(%d束・敷くと雑草が生えない・持っている %d束)" % [g.amount, world.garden.straw]
	if g.species == "tomato":
		return "%s(小屋で苗にする)" % world.garden.CROPS.tomato.seed_name
	if g.form == "crop_seed":
		return "%s(%sにまく)" % [world.garden.CROPS[g.species].seed_name, main.crop_seasons(g.species)]
	var sp: Dictionary = world.forest.SPECIES[g.species]
	if g.form == "sapling":
		return "%sの苗木(樹齢%d年)" % [sp.name, int(sp.sapling_age)]
	return "%sの種(%d粒・発芽率%d%%)" % [sp.name, g.amount, roundi(sp.germination * 100.0)]

# 市場の行 [{id, text, column, page}]。column 0 = 買う列、1 = 売る列
func market_rows() -> Array:
	var m := world.market
	var rows := []
	var buy_next: int = (_buy_page + 1) % BUY_PAGES.size()
	rows.append({"id": "page_buy", "text": "買う品: %s(押すと次: %s)" % [BUY_PAGES[_buy_page].name, BUY_PAGES[buy_next].name], "column": 0})
	var ordering: Array = m.orderable() if m.can_order() else []
	for g in m.GOODS:
		if not m.sells(g):
			continue  # この土地で育たない木と野菜は並ばない
		var page := _buy_page_of(g)
		if g.form == "crop_seed" and g.species in ordering and not world.garden.can_sow_now(g.species) \
				and not (g.species in world.seedlings.SEEDLING_CROPS):
			# 冬は、春の種を安く注文できる(冬が終わった月の 1 日に届く。今までのルールでは 3 月 1 日)。
			# 今まけない野菜は、買う行の代わりに注文の行を出す(小屋で苗にする野菜は、冬も買える)
			rows.append(_order_row(g.species, page))
			continue
		var label: String = "済: %s" % good_name(g) if m.is_owned(g) else "買う: %s  %d₽" % [good_name(g), g.price]
		rows.append({"id": g.id, "text": label, "column": 0, "page": page})
		if g.form == "crop_seed" and g.species in ordering:
			rows.append(_order_row(g.species, page))
	var sell_next: int = (_sell_page + 1) % SELL_PAGES.size()
	rows.append({"id": "page_sell", "text": "売る品: %s(押すと次: %s %d種類)" % [SELL_PAGES[_sell_page], SELL_PAGES[sell_next], _held_kinds(sell_next)], "column": 1})
	for item in m.SELL_PRICES:
		# 野菜は持っているものだけ並べる(行が多くなりすぎないように)
		var n := main.produce_count(item)
		if (item == "apple" and world.forest.grows_here("apple")) or n > 0:
			var dear := "(%s)" % main.SEASON_NAMES[world.forest.season] if m.price_rate(item, world.forest.season) > 1.0 else ""
			rows.append({"id": "sell_" + item, "text": "売る: %s %d%s × %d₽%s" % [main.produce_name(item), n, main.produce_unit(item), m.sell_price(item), dear], "column": 1, "page": _sell_page_of(item)})
	rows.append({"id": "close", "text": "閉じる(B / Esc)", "column": 1})
	return rows

# 春の種の注文の行
func _order_row(kind: String, page: int) -> Dictionary:
	var m := world.market
	var ordered: int = int(m.orders.get(kind, 0))
	var note := "・注文済み %d" % ordered if ordered > 0 else ""
	return {"id": "order_" + kind, "text": "注文: %s(%d/1に届く%s)  %d₽" % [world.garden.CROPS[kind].seed_name, world.region.winter_end_month(), note, m.order_price(kind)], "column": 0, "page": page}

func _buy_page_of(g: Dictionary) -> int:
	for i in range(BUY_PAGES.size()):
		if g.form in BUY_PAGES[i].forms and (g.form != "crop_seed" or world.garden.CROPS[g.species].group in BUY_PAGES[i].groups) \
				and (g.form != "sapling" or world.forest.SPECIES[g.species].group in BUY_PAGES[i].tree_groups):
			return i
	return 0

func _sell_page_of(item: String) -> int:
	if item.begins_with("seed_"):
		var seeds: Array = world.market.SELL_PRICES.keys().filter(func(k): return k.begins_with("seed_"))
		return SELL_PAGES.find("自然の木の種 1") + mini(1, int(seeds.find(item) / float(WILD_SEEDS_PER_PAGE)))
	if world.kitchen.RECIPES.has(item):
		if world.kitchen.from_grain(item):
			return SELL_PAGES.find("穀物と粉の料理")
		return SELL_PAGES.find("果物とはちみつの保存食" if world.kitchen.from_tree(item) else "野菜の保存食")
	if item.begins_with("flour_"):
		return SELL_PAGES.find("豆と穀物と粉")
	if world.forest.FRUITS.has(item) or item == "honey":
		return 0
	return SELL_GROUPS[world.garden.CROPS[item.trim_prefix("seedling_")].group]

# そのページで持っている品の種類の数
func _held_kinds(page: int) -> int:
	var n := 0
	for item in world.market.SELL_PRICES:
		if _sell_page_of(item) == page and main.produce_count(item) > 0:
			n += 1
	return n

# 市場の行を選んだとき: ページ送り・注文・売る・買う
func _market_action(id: String) -> void:
	var m := world.market
	if id == "page_buy" or id == "page_sell":
		main._sfx("click")
		if id == "page_buy":
			_buy_page = (_buy_page + 1) % BUY_PAGES.size()
		else:
			_sell_page = (_sell_page + 1) % SELL_PAGES.size()
		hud.refresh_shop()
		return
	if id.begins_with("order_"):
		var kind := id.trim_prefix("order_")
		var price: int = m.order_price(kind)
		var ordered: bool = m.order(kind) == "ordered"
		main._sfx("coin" if ordered else "click")
		if ordered:
			hud.show_message("%sを注文した(-%d₽)。%d月1日に届く(店頭より%d₽安い)" % [world.garden.CROPS[kind].seed_name, price, world.region.winter_end_month(), int(m.good(kind + "_seed").price) - price], 5.0)
		else:
			hud.show_message("お金が足りない(%d₽ 必要)" % price)
	elif id.begins_with("sell_"):
		var item := id.trim_prefix("sell_")
		var income: int = m.sell_all(item)
		main._sfx("coin" if income > 0 else "click")
		hud.show_message("%sを売った(+%d₽)" % [main.produce_name(item), income] if income > 0 else "売る%sがない" % main.produce_name(item))
	else:
		var g: Dictionary = m.good(id)
		var result: String = m.buy(id)
		var bought: bool = result == "bought"
		main._sfx("coin" if bought else "click")
		if bought and g.form == "extension":
			hud.show_message("小屋の増築を頼んだ(-%d₽)。窓ガラスとかまどが届いて、西に杭が立った。西の外から H で建てる(丸太%d本・%d日)" % [g.price, world.cabin.ext_total_logs(), main._ext_total_days()], 8.0)
		elif bought and g.form == "furniture":
			hud.show_message("%sを買って、増築した部屋に置いた(-%d₽)" % [main.FURNITURE_NAMES[g.species], g.price], 5.0)
		elif bought and g.form == "tool":
			hud.show_message("%sを買った(-%d₽)。%s" % [main.TOOL_NAMES[g.species], g.price, Msg.TOOL_BOUGHT[g.species]], 6.0)
		elif bought and g.form == "fuel":
			hud.show_message("ガソリンを%s買った(-%d₽。持っている %s)" % [main.gas_text(int(g.amount)), g.price, main.gas_text(world.tools.gas)])
		elif bought:
			hud.show_message("%sを買った(-%d₽)" % [good_name(g), g.price])
		elif Msg.EXTENSION_MESSAGES.has(result):
			hud.show_message(Msg.EXTENSION_MESSAGES[result], 5.0)
		else:
			hud.show_message("お金が足りない(%d₽ 必要)" % g.price)
	world.save_game()
	hud.refresh_shop()
