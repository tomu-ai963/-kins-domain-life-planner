extends SceneTree

# 小屋のストーブ(料理)とベッド(日記の見込み)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_kitchen.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Kitchen = preload("res://logic/Kitchen.gd")
const Cabin = preload("res://logic/Cabin.gd")

const TEST_SAVE := "user://test_kitchen.json"
const SITE := Vector2(20, 20)

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_prices()
	_test_cook()
	_test_firewood()
	_test_sell()
	_test_honey()
	_test_season_prices()
	_test_save()
	_test_old_save()
	_test_places()
	_test_tomorrow_garden()
	_test_tomorrow_others()
	_remove_save()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)

func _remove_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

# 小屋が完成した世界
func _world() -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.forest.season = "autumn"
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birds"
	w.cabin.site = SITE
	w.cabin.stage = Cabin.STAGES.size()
	return w

func _test_prices() -> void:
	print("値段")
	var w := _world()
	for id in Kitchen.RECIPES:
		var r: Dictionary = Kitchen.RECIPES[id]
		_check(w.market.SELL_PRICES.has(id), "%s は市場で売れる" % r.name)
		var made: int = int(r.output) * int(w.market.SELL_PRICES[id])
		var raw: int = int(r.amount) * int(w.market.SELL_PRICES[r.input])
		# 薪代(丸太 1 本 300₽ の 1/10)を引いても、生で売るより得
		_check(made - 30 > raw and made <= raw * 3, "%s: 生 %d₽ → 加工 %d₽(2 倍前後)" % [r.name, raw, made])

func _test_cook() -> void:
	print("仕込む → 待つ → 受け取る")
	var w := _world()
	var k := w.kitchen
	w.cabin.materials.log = 1
	_check(k.collect() == "empty", "鍋が空なら受け取れない")
	_check(k.start("nothing") == "unknown", "知らない料理は作れない")
	w.garden.produce.tomato = 9
	_check(k.start("sauce") == "no_input", "材料が足りないと仕込めない")
	_check(w.garden.produce.tomato == 9 and w.cabin.materials.log == 1 and k.firewood == 0, "仕込めなければ何も減らない")
	w.garden.produce.tomato = 12
	_check(k.start("sauce") == "started", "トマトソースを仕込める")
	_check(w.garden.produce.tomato == 2, "材料が 10kg 減る")
	_check(k.days_left() == 1 and not k.is_ready() and k.ready_tomorrow(), "今日はまだできない。明日できる")
	_check(k.collect() == "cooking", "できるまでは受け取れない")
	w.garden.produce.tomato = 20
	_check(k.start("sauce") == "busy" and w.garden.produce.tomato == 20, "鍋はひとつ")
	k.pot.start_day -= 1  # 次の日
	_check(k.is_ready(), "次の日にできる")
	_check(k.collect() == "collected" and k.stock.sauce == 5 and k.is_empty(), "受け取ると 5 瓶ふえて鍋が空く")
	_check(k.collect() == "empty" and k.stock.sauce == 5, "二重に受け取れない")

	w.garden.produce.cucumber = 6
	_check(k.start("pickles") == "started" and k.days_left() == 3 and not k.ready_tomorrow(), "塩漬けは 3 日かかる")
	k.pot.start_day -= 2
	_check(k.days_left() == 1 and k.ready_tomorrow(), "2 日たつと、あと 1 日")
	k.pot.start_day -= 10
	_check(k.days_left() == 0, "長く放っておいても 0 日で止まる")
	k.collect()
	_check(k.stock.pickles == 10, "放っておいても数は減らない")

	# リンゴの持ち物は Forest にある
	w.forest.produce.apple = 10
	_check(k.input_count("jam") == 10 and k.start("jam") == "started" and w.forest.produce.apple == 0, "リンゴジャムはリンゴを使う")

func _test_firewood() -> void:
	print("薪")
	var w := _world()
	var k := w.kitchen
	w.garden.produce.potato = 1000
	_check(k.start("pirozhki") == "no_wood" and w.garden.produce.potato == 1000 and k.firewood == 0, "丸太がないと仕込めず、材料も減らない")
	w.cabin.materials.log = 1
	_check(k.start("pirozhki") == "started" and k.last_split, "丸太を割って火をおこす")
	_check(w.cabin.materials.log == 0 and k.firewood == Kitchen.LOG_FIRES - 1, "丸太 1 本で薪 10 回分。1 回使って残り 9")
	for i in range(Kitchen.LOG_FIRES - 1):
		k.pot = {}
		_check(k.start("pirozhki") == "started" and not k.last_split, "残りの薪で %d 回目" % (i + 2))
	k.pot = {}
	_check(k.firewood == 0 and k.start("pirozhki") == "no_wood", "10 回で薪が尽きる")

func _test_sell() -> void:
	print("売る")
	var w := _world()
	w.kitchen.stock.sauce = 5
	var before: int = w.market.money
	_check(w.market.sell_all("sauce") == 750, "トマトソース 5 瓶で 750₽")
	_check(w.market.money == before + 750 and w.kitchen.stock.sauce == 0, "お金が増え、瓶はなくなる")
	_check(w.market.sell_all("sauce") == 0, "なければ売れない")
	w.garden.produce.garlic = 3
	_check(w.market.sell_all("garlic") == 360 and w.kitchen.stock.garlic_pickle == 0, "生のニンニクは今までどおり売れる")

func _test_honey() -> void:
	print("はちみつの料理")
	var w := _world()
	var k := w.kitchen
	w.cabin.materials.log = 1
	_check(k.start("pryanik") == "no_input", "はちみつがないと仕込めない")
	w.bees.stock.honey = 3
	_check(k.input_count("pryanik") == 3 and k.input_count("sbiten") == 3, "持っているはちみつの量が分かる")
	_check(k.start("pryanik") == "started" and w.bees.stock.honey == 2, "ピャーニクははちみつ 1kg を使う")
	_check(k.days_left() == 1, "ピャーニクは 1 日でできる")
	k.pot.start_day -= 1
	_check(k.collect() == "collected" and k.stock.pryanik == 10, "ピャーニクが 10 個できる")
	_check(k.start("sbiten") == "started" and w.bees.stock.honey == 0, "スビーテンははちみつ 2kg を使う")
	_check(k.days_left() == 3, "スビーテンは 3 日かかる")
	k.pot.start_day -= 3
	_check(k.collect() == "collected" and k.stock.sbiten == 8, "スビーテンが 8 瓶できる")
	_check(w.market.count_of("pryanik") == 10 and w.market.sell_all("pryanik") == 400, "ピャーニク 10 個で 400₽")
	_check(w.market.sell_all("sbiten") == 800, "スビーテン 8 瓶で 800₽")
	_check(w.visitors.ASK.has("pryanik") and w.visitors.ASK.has("sbiten"), "はちみつの料理も頼まれる")

func _test_season_prices() -> void:
	print("季節の値段")
	var w := _world()
	var m := w.market
	var f := w.forest
	for id in Kitchen.RECIPES:
		var base: int = int(m.SELL_PRICES[id])
		_check(m.price_in(id, "summer") == base and m.price_in(id, "autumn") == base, "%s: 夏と秋はもとの値段" % id)
		_check(m.price_in(id, "spring") > base and m.price_in(id, "winter") > m.price_in(id, "spring"), "%s: 春は高く、冬はもっと高い" % id)
	for item in ["tomato", "apple", "honey", "seedling_tomato"]:
		for season in ["spring", "summer", "autumn", "winter"]:
			_check(m.price_in(item, season) == int(m.SELL_PRICES[item]), "%s は %s も同じ値段(保存食だけ変わる)" % [item, season])
	var earned := {}
	for season in ["summer", "autumn", "spring", "winter"]:
		f.season = season
		w.kitchen.stock.sauce = 5
		earned[season] = m.sell_all("sauce")
	_check(earned.summer == 750 and earned.autumn == 750, "トマトソース 5 瓶: 夏と秋は 750₽")
	_check(earned.spring == 940, "トマトソース 5 瓶: 春は 940₽(1 瓶 188₽)")
	_check(earned.winter == 1125, "トマトソース 5 瓶: 冬は 1,125₽")
	f.season = "winter"
	w.kitchen.stock.sauce = 2
	w.garden.produce.tomato = 5
	_check(w.visitors.value_of("sauce", 2) == 450, "訪問者のお礼も冬の値段から決まる")
	_check(w.visitors.value_of("tomato", 5) == 200, "生の野菜のお礼は変わらない")

func _test_save() -> void:
	print("セーブ")
	var w := _world()
	var k := w.kitchen
	w.cabin.materials.log = 1
	w.forest.produce.apple = 10
	k.stock.pirozhki = 7
	k.start("jam")  # dirty で保存される
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	var k2 := w2.kitchen
	_check(k2.pot.recipe == "jam" and k2.pot.start_day == k.pot.start_day, "鍋の中身が残る")
	_check(k2.stock.pirozhki == 7 and k2.stock.jam == 0, "保存食が残る")
	_check(k2.firewood == Kitchen.LOG_FIRES - 1 and w2.cabin.materials.log == 0, "薪と丸太が残る")
	k2.pot = {"recipe": "jam", "start_day": k2.pot.start_day - 1}
	_check(k2.collect() == "collected" and k2.stock.jam == 4, "読み直しても受け取れる")

	var k3 := Kitchen.new()
	k3.from_save({"pot": {"recipe": "gone", "start_day": 3}, "stock": {"gone": 9, "jam": 2}, "firewood": 4})
	_check(k3.is_empty() and k3.stock.jam == 2 and not k3.stock.has("gone") and k3.firewood == 4, "知らない料理のセーブは無視する")

func _test_old_save() -> void:
	print("前のセーブ")
	_remove_save()
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"unit": "m", "trees": [], "market": {"money": 20}, "cabin": {"site": [10, 20], "stage": 0, "days_done": 1, "logs": 2}}))
	f.close()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.load_game()
	_check(w.kitchen.is_empty() and w.kitchen.firewood == 0 and w.market.money == 20 and w.cabin.materials.log == 2, "台所の記録がないセーブは、鍋が空・薪 0 から")

func _test_places() -> void:
	print("家具のそば")
	var w := _world()
	var c := w.cabin
	var stove := SITE + Cabin.STOVE_OFFSET
	var bed := SITE + Cabin.BED_OFFSET
	_check(c.is_at_stove(stove + Vector2(-0.65, 0)), "ストーブの西に立つと前にいる")
	_check(c.is_at_stove(stove + Vector2(0, 0.65)), "ストーブの南に立つと前にいる")
	_check(not c.is_at_stove(SITE) and not c.is_at_bed(SITE), "部屋の真ん中はどちらでもない(苗づくり)")
	_check(not c.is_at_stove(SITE + Vector2(1.6, 0.4)), "東の窓辺はストーブの前ではない(苗づくり)")
	_check(c.is_at_bed(bed + Vector2(0, 0.73)), "ベッドの南に立つとそばにいる")
	_check(not c.is_at_bed(SITE + Vector2(-1.2, 0.8)) and not c.is_at_stove(stove + Vector2(0, -3)), "テーブルや外は違う")
	c.stage = 1
	_check(not c.is_at_stove(stove) and not c.is_at_bed(bed), "完成前は使えない")

func _test_tomorrow_garden() -> void:
	print("日記: 明日の畑")
	var w := _world()
	var g := w.garden
	var today: String = w.forest.today()
	var c := _radish(g, 5)  # 今 2.5 日ぶん、明日 3.0 日ぶん
	_check(not g.is_ripe(c) and g.tomorrow_counts().ripe == 1 and g.tomorrow_counts().spoiling == 0, "明日収穫できる区画を数える")
	c = _radish(g, 3)  # 今 1.5、明日 2.0
	_check(g.tomorrow_counts().ripe == 0, "明日もまだなら数えない")
	c = _radish(g, 4, 1, today)  # 今 2.0(今日の水やりはまだ数えない)、明日 3.0
	_check(g.growth_days(c) == 2.0 and g.tomorrow_counts().ripe == 1, "今日の水やりは明日の見込みに入る")
	c = _radish(g, 4)  # 水をやらないと明日 2.5
	_check(g.tomorrow_counts().ripe == 0, "水をやっていなければ明日も育ちきらない")
	c = _radish(g, 9)  # 今 4.5(できてから 3 日)、明日 5.0(4 日)
	_check(g.is_ripe(c) and not g.is_spoiled(c), "前提: 今はまだ傷んでいない")
	var plan: Dictionary = g.tomorrow_counts()
	_check(plan.ripe == 1 and plan.spoiling == 1, "明日傷みはじめる区画を数える")
	c = _radish(g, 11)  # もう傷んでいる
	_check(g.is_spoiled(c) and g.tomorrow_counts().spoiling == 0 and g.tomorrow_counts().ripe == 1, "もう傷んでいる区画は「これから傷む」に数えない")

	# 明日の見込みと、明日になったときの実際が同じになる
	var mismatches := 0
	var cases := 0
	for sown_ago in range(0, 14):
		for wet in [0, 1, 2]:
			c = _radish(g, sown_ago, wet)
			var plan_ripe: bool = g.tomorrow_counts().ripe == 1
			var was_spoiled: bool = g.is_spoiled(c)
			var plan_spoiling: bool = g.tomorrow_counts().spoiling == 1
			c.sown_day -= 1  # 1 日たつ
			cases += 1
			if g.is_ripe(c) != plan_ripe or (g.is_spoiled(c) and not was_spoiled) != plan_spoiling:
				mismatches += 1
	_check(mismatches == 0, "見込みと翌日の実際が一致(%d 通り中 %d 通りずれ)" % [cases, mismatches])

	_radish(g, 5)
	_check(g.today_counts().dry == 1 and g.today_counts().ripe == 0, "今日: まだ水をやっていない区画")
	_radish(g, 5, 1, today)
	_check(g.today_counts().dry == 0, "今日: 水をやれば数えない")
	_radish(g, 8)
	_check(g.today_counts().ripe == 1 and g.today_counts().dry == 0, "今日: 収穫できる区画は水やりに数えない")

# 畑をラディッシュ 1 区画だけにする(3 日で育つ・3 日で傷む)
func _radish(g, sown_ago: int, water_days := 0, last_watered := "") -> Dictionary:
	var c := {"pos": Vector2.ZERO, "kind": "radish", "sown_day": g.day_number() - sown_ago, "water_days": water_days, "last_watered": last_watered, "head": 0.0}
	g.crops.clear()
	g.crops.append(c)
	return c

func _test_tomorrow_others() -> void:
	print("日記: 雨・苗・リンゴ")
	var w := _world()
	var f := w.forest
	var d: int = f.day_number()
	_check(w.tomorrow_date() == f.date_of_day(d + 1) and w.tomorrow_date() > f.today(), "明日の日付")
	_check(w.tomorrow_rain() == (f.roll_daily_event(w.tomorrow_date()) == "rain"), "明日の雨は発見と同じ決まり方")

	var sl := w.seedlings
	sl.pots = [{"kind": "tomato", "sown_day": d - 9, "water_days": 0, "last_watered": ""}]  # 今 4.5、明日 5.0
	_check(not sl.is_grown(sl.pots[0]) and sl.grown_tomorrow() == 1, "明日受け取れる苗を数える")
	sl.pots = [{"kind": "tomato", "sown_day": d - 8, "water_days": 0, "last_watered": ""}]
	_check(sl.grown_tomorrow() == 0, "明日もまだなら数えない")

	_check(f.fruiting_apples() == 0, "リンゴの木がなければ 0")
	f.trees.append({"pos": Vector2(1, 1), "species": "apple", "form": "sapling", "planted_at": f._now(), "start_age": 6.0, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	var age: float = f.real_age_years(f.trees[0])
	_check(age >= f.APPLE_FRUIT_AGE and f.fruiting_apples() == 1, "実をつける年のリンゴを数える(樹齢 %.1f)" % age)
	f.trees[0].species = "birch"
	_check(f.fruiting_apples() == 0, "ほかの木は数えない")
