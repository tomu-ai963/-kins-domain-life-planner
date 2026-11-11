extends SceneTree

# 果樹の種類のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_fruit.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Forest = preload("res://logic/Forest.gd")
const Market = preload("res://logic/Market.gd")
const Kitchen = preload("res://logic/Kitchen.gd")
const Visitors = preload("res://logic/Visitors.gd")

const TEST_SAVE := "user://test_fruit.json"
const AT := Vector2(5, 5)

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_tables()
	_test_apple_unchanged()
	_test_yield_curve()
	_test_seasons_and_age()
	_test_harvest()
	_test_nearest()
	_test_planting()
	_test_market()
	_test_kitchen()
	_test_visitors_and_stuck()
	_test_save()
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

func _world(season := "summer") -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.forest.season = season
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birds"
	return w

func _tree(w: GameWorld, species: String, age: float, pos := AT) -> Dictionary:
	var t := {"pos": pos, "species": species, "form": "sapling", "planted_at": w.forest._now(), "start_age": age, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0}
	w.forest.trees.append(t)
	return t

func _test_tables() -> void:
	print("表")
	for id in Forest.FRUIT_ORDER:
		_check(Forest.FRUITS.has(id) and Forest.SPECIES.has(id), "%s は果樹で樹種" % id)
		_check(Market.SELL_PRICES.has(id), "%s に買い取り値がある" % id)
		_check(Visitors.ASK.has(id), "%s を訪問者が頼める" % id)
		_check(Forest.INITIAL_SAPLINGS.has(id) and Forest.INITIAL_SEEDS.has(id), "%s の持ち物の枠がある" % id)
	for id in Forest.SAPLING_ONLY:
		_check(not Market.good(id + "_sapling").is_empty(), "%s の苗木を市場で買える" % id)
		_check(Market.good(id + "_seed").is_empty(), "%s の種は売っていない" % id)
		_check(Forest.INITIAL_SEEDS[id] == 0 and Forest.INITIAL_SAPLINGS[id] == 0, "%s は最初は持っていない" % id)
	# 収入がリンゴ(1 本 300₽/日)を超えない
	var apple_best: int = Forest.FRUITS.apple.most * Market.SELL_PRICES.apple
	_check(apple_best == 300, "前提: リンゴは 1 本 300₽/日まで")
	for id in Forest.SAPLING_ONLY:
		var best: int = int(Forest.FRUITS[id].most) * int(Market.SELL_PRICES[id])
		_check(best > 0 and best <= apple_best, "%s は 1 本 %d₽/日まで(リンゴ以下)" % [id, best])

func _test_apple_unchanged() -> void:
	print("リンゴは今までどおり")
	_check(Forest.apple_yield(6.0) == 5, "樹齢 6 年で 5 個")
	_check(Forest.apple_yield(7.0) == 10, "1 年で 5 個増える")
	_check(Forest.apple_yield(50.0) == 20, "上限 20 個")
	_check(Forest.APPLE_MAX_YIELD == 20, "上限の定数も同じ")
	var w := _world("autumn")
	_tree(w, "apple", 8.0)
	_check(w.forest.harvest_nearest(AT, 2.0) == "harvested" and w.forest.produce.apple == 15 and w.forest.last_harvest_item == "apple", "秋に収穫できる(樹齢 8 年で 15 個)")
	_check(w.forest.fruiting_apples() == 1, "実をつける本数も数えられる")

func _test_yield_curve() -> void:
	print("収穫量")
	_check(Forest.fruit_yield("cherry", 4.0) == 1 and Forest.fruit_yield("cherry", 6.0) == 3 and Forest.fruit_yield("cherry", 30.0) == 3, "サクランボ: 樹齢 4 年で 1kg、上限 3kg")
	_check(Forest.fruit_yield("plum", 5.0) == 1 and Forest.fruit_yield("plum", 9.0) == 5 and Forest.fruit_yield("plum", 30.0) == 5, "スモモ: 樹齢 5 年で 1kg、上限 5kg")
	_check(Forest.fruit_yield("pear", 6.0) == 4 and Forest.fruit_yield("pear", 7.0) == 8 and Forest.fruit_yield("pear", 30.0) == 15, "ナシ: 樹齢 6 年で 4 個、上限 15 個")

func _test_seasons_and_age() -> void:
	print("季節と樹齢")
	var w := _world()
	var f := w.forest
	var cases := {"apple": "autumn", "cherry": "summer", "plum": "summer", "pear": "autumn"}
	for id in cases:
		f.trees.clear()
		var t := _tree(w, id, 30.0)
		for s in ["spring", "summer", "autumn", "winter"]:
			f.season = s
			t.last_harvest = ""
			var expected: bool = s == cases[id]
			_check(f.shows_fruit(t) == expected, "%s は %s に実が%s" % [id, s, "見える" if expected else "見えない"])
			_check((f.fruiting_in(s) == 1) == expected, "%s の本数の判定が %s に合う" % [id, s])
		f.season = cases[id]
		_check(f.shows_fruit(t), "%s: 前提" % id)
		t.last_harvest = f.today()
		_check(not f.shows_fruit(t), "%s は収穫すると今日は実が見えない" % id)
	f.trees.clear()
	f.season = "summer"
	var young := _tree(w, "cherry", 3.0)
	_check(f.harvest_nearest(AT, 2.0) == "young" and f.last_harvest_item == "cherry", "若い木は実らない")
	_check(not f.shows_fruit(young), "若い木に実は見えない")
	_check(f.fruiting_in("summer") == 0, "若い木は本数に入らない")
	young.start_age = 4.0
	_check(f.harvest_nearest(AT, 2.0) == "harvested" and f.produce.cherry == 1, "樹齢 4 年で採れる")
	f.season = "autumn"
	young.last_harvest = ""
	_check(f.harvest_nearest(AT, 2.0) == "not_season" and f.last_harvest_item == "cherry", "季節が違うと採れない")
	f.season = "summer"
	f.time_offset_years = 5.0
	_check(f.harvest_nearest(AT, 2.0) == "preview", "プレビュー中は採れない")
	f.time_offset_years = 0.0
	var bonus := _tree(w, "plum", 4.6, AT + Vector2(10, 0))
	_check(f.harvest_nearest(AT + Vector2(10, 0), 2.0) == "young", "スモモ: 樹齢 4.6 年はまだ")
	bonus.bonus_years = 0.5
	_check(f.harvest_nearest(AT + Vector2(10, 0), 2.0) == "harvested", "水やりのボーナスで実る")

func _test_harvest() -> void:
	print("収穫")
	var w := _world("summer")
	var f := w.forest
	_check(f.harvest_nearest(AT, 2.0) == "none", "木がなければ none")
	_tree(w, "birch", 30.0)
	_check(f.harvest_nearest(AT, 2.0) == "none", "実のならない木は none")
	f.trees.clear()
	_tree(w, "plum", 30.0)
	_check(f.harvest_nearest(AT, 2.0) == "harvested" and f.produce.plum == 5 and f.last_harvest_count == 5, "スモモを 5kg 収穫する")
	_check(f.harvest_nearest(AT, 2.0) == "done" and f.produce.plum == 5 and f.last_harvest_wait == 3, "採ったら次に実るまで 3 日")
	_check(FileAccess.file_exists(TEST_SAVE), "収穫すると保存する")
	var t: Dictionary = f.trees[0]
	_check(not f.shows_fruit(t) and f.ripe_fruit_count("summer") == 0, "採った木には実が見えない")
	_check(f.ripe_fruit_count("summer", 2) == 0 and f.ripe_fruit_count("summer", 3) == 1, "日記の見込み: 3 日後に実る")
	for days in [1, 2]:
		t.last_harvest = Forest.date_of_day(f.day_number() - days)
		_check(f.harvest_nearest(AT, 2.0) == "done" and f.last_harvest_wait == 3 - days, "%d 日後: まだ(あと %d 日)" % [days, 3 - days])
	t.last_harvest = Forest.date_of_day(f.day_number() - 3)
	_check(f.shows_fruit(t) and f.ripe_fruit_count("summer") == 1, "3 日後: また実が見える")
	_check(f.harvest_nearest(AT, 2.0) == "harvested" and f.produce.plum == 10, "3 日後にまた採れる")

func _test_nearest() -> void:
	print("いちばん近い果樹")
	var w := _world("summer")
	var f := w.forest
	_tree(w, "birch", 30.0, AT)
	_tree(w, "cherry", 30.0, AT + Vector2(1.5, 0))
	_tree(w, "plum", 30.0, AT + Vector2(0.5, 0))
	_check(f.trees[f.nearest_fruit_index(AT, 2.0)].species == "plum", "近いほうの果樹を選ぶ")
	_check(f.nearest_fruit_index(AT + Vector2(30, 0), 2.0) == -1, "遠ければ -1")
	_check(f.harvest_nearest(AT, 2.0) == "harvested" and f.last_harvest_item == "plum", "白樺のそばでも果樹を収穫する")

func _test_planting() -> void:
	print("植える")
	var w := _world("summer")
	var f := w.forest
	_check(not f.add_tree(AT, "cherry", "seed"), "種はないので植えられない")
	_check(not f.add_tree(AT, "cherry", "sapling"), "苗木がなければ植えられない")
	f.saplings.cherry = 1
	_check(f.add_tree(AT, "cherry", "sapling") and f.saplings.cherry == 0, "苗木で植えられる")
	_check(f.is_established(f.trees[0]) and is_equal_approx(f.real_age_years(f.trees[0]), 1.0), "苗木は根付いて樹齢 1 年から(植えて 3 日で実る)")
	_check(f.radius_of(f.trees[0]) > 0.0, "大きさがある")
	f.season = "winter"
	_check(not f.can_plant("pear", "sapling"), "冬は植えられない")
	# 丸太
	f.trees.clear()
	_check(f.wood_yield(_tree(w, "cherry", 10.0)) == 0, "若い果樹は丸太にならない")
	_check(f.wood_yield(_tree(w, "pear", 40.0, AT + Vector2(5, 0))) == 2, "育ったナシは丸太になる")

func _test_market() -> void:
	print("市場")
	var w := _world()
	w.market.money = 1000
	_check(w.market.buy("cherry_sapling") == "bought" and w.forest.saplings.cherry == 1 and w.market.money == 300, "苗木を買える")
	_check(w.market.buy("pear_sapling") == "no_money", "お金が足りないと買えない")
	w.forest.produce.cherry = 3
	_check(w.market.count_of("cherry") == 3 and w.market.sell_all("cherry") == 180 and w.forest.produce.cherry == 0, "サクランボ 3kg で 180₽")
	w.forest.produce.pear = 15
	_check(w.market.sell_all("pear") == 270, "ナシ 15 個で 270₽")

func _test_kitchen() -> void:
	print("保存食")
	for id in ["cherry_jam", "plum_jam", "pear_compote"]:
		var r: Dictionary = Kitchen.RECIPES[id]
		_check(Forest.FRUITS.has(r.input), "%s は果物から作る" % id)
		_check(int(r.amount) <= int(Forest.FRUITS[r.input].most), "%s の材料は 1 本の収穫で足りる" % id)
		_check(Market.SELL_PRICES.has(id) and Visitors.ASK.has(id), "%s は売れて、頼まれる" % id)
	var w := _world()
	w.kitchen.firewood = 1
	w.forest.produce.plum = 5
	_check(w.kitchen.input_count("plum_jam") == 5, "持っている量が分かる")
	_check(w.kitchen.start("plum_jam") == "started" and w.forest.produce.plum == 0, "スモモから仕込む")
	w.kitchen.pot.start_day -= 1
	_check(w.kitchen.collect() == "collected" and w.kitchen.stock.plum_jam == 4, "4 瓶できる")
	_check(w.market.sell_all("plum_jam") == 360, "4 瓶で 360₽")

func _test_visitors_and_stuck() -> void:
	print("訪問者と手詰まり")
	var w := _world("summer")
	w.forest.produce.cherry = 2
	_check(w.visitors._choose_item("tanya") == "cherry", "ターニャさんはサクランボを頼む")
	_check(w.visitors.available("cherry") == 2, "渡せる量が分かる")
	w.forest.produce.pear = 8
	_check(w.visitors._choose_item("fyodor") == "pear", "フョードルさんはナシを頼む")
	# 手詰まりの判定: 今の季節に実る果樹があれば当てにできる
	var w2 := _world("summer")
	w2.market.money = 10
	_tree(w2, "cherry", 30.0)
	_check(not w2.visitors.is_stuck(), "夏にサクランボが実るなら手詰まりではない")
	w2.forest.season = "autumn"
	_check(w2.visitors.is_stuck(), "秋はサクランボを当てにできないので手詰まり")
	w2.forest.produce.pear = 1
	_check(not w2.visitors.is_stuck(), "ナシを持っていれば売れる")

func _test_save() -> void:
	print("セーブ")
	var w := _world("summer")
	w.forest.produce.plum = 3
	w.forest.saplings.pear = 2
	_tree(w, "cherry", 7.0)
	w.save_game()
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	_check(w2.forest.produce.plum == 3 and w2.forest.saplings.pear == 2, "持ち物が残る")
	_check(w2.forest.trees[0].species == "cherry", "果樹が残る")
	_remove_save()
	# 前のセーブ: 新しい果樹の枠がなくても読める
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"unit": "m", "trees": [], "seeds": {"birch": 2, "apple": 1, "cedar": 0}, "saplings": {"birch": 0, "apple": 1, "cedar": 0}, "produce": {"apple": 9}}))
	f.close()
	var w3 := GameWorld.new()
	w3.save_path = TEST_SAVE
	w3.load_game()
	_check(w3.forest.produce.apple == 9 and w3.forest.produce.cherry == 0 and w3.forest.saplings.pear == 0, "前のセーブも読める。新しい果樹は 0 から")
	_check(w3.forest.saplings.apple == 1 and w3.forest.seeds.birch == 2, "前の持ち物はそのまま")
