extends SceneTree

# 冬のルール(手順 4-1)と小屋の苗づくりのロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_winter.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Forest = preload("res://logic/Forest.gd")

const TEST_SAVE := "user://test_winter.json"
const SPOT := Vector2(1, 1)            # 区画(1.5, 1.5)の中
const OUTSIDE := Vector2(20, 22.5)     # 小屋の南、1m 離れたところ
const SITE := Vector2(20, 20)

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_planting()
	_test_frost()
	_test_seedlings()
	_test_transplant()
	_test_market()
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

func _world(season := "autumn", remove_save := true) -> GameWorld:
	if remove_save:
		_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.forest.season = season
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birds"
	return w

# 完成した小屋がある世界
func _with_cabin(season := "winter") -> GameWorld:
	var w := _world(season)
	w.cabin.site = SITE
	w.cabin.stage = 3
	return w

func _test_planting() -> void:
	print("冬に植えられるもの")
	var f := Forest.new()
	f.season = "winter"
	_check(not f.can_plant("birch", "sapling") and not f.can_plant("apple", "sapling") and not f.can_plant("cedar", "sapling"), "冬は苗木を植えられない")
	_check(f.can_plant("birch", "seed"), "白樺の種は雪の上にまける")
	_check(not f.can_plant("apple", "seed") and not f.can_plant("cedar", "seed"), "リンゴと杉の種はまけない")
	for s in ["spring", "summer", "autumn"]:
		f.season = s
		_check(f.can_plant("cedar", "sapling") and f.can_plant("apple", "seed"), "%s は何でも植えられる" % s)

func _sown(w: GameWorld, kind: String, pos := SPOT) -> Dictionary:
	w.land.toggle_plot(pos)
	var season: String = w.forest.season
	w.forest.season = w.garden.CROPS[kind].seasons[0]
	w.garden.seeds[kind] = 1
	w.garden.sow(pos, kind)
	w.forest.season = season
	return w.garden.crop_at(pos)

func _test_frost() -> void:
	print("霜")
	var w := _world("autumn")
	var g := w.garden
	_sown(w, "radish")
	_sown(w, "garlic", Vector2(10, 10))
	g.apply_frost()
	_check(g.crops.size() == 2 and g.last_frost.is_empty(), "秋はどちらも枯れない")
	w.forest.season = "winter"
	g.apply_frost()
	_check(g.crops.size() == 1 and g.crops[0].kind == "garlic", "冬になるとニンニク以外は枯れる")
	_check(g.last_frost == {"radish": 1}, "枯れた数を知らせる")
	g.apply_frost()
	_check(g.last_frost.is_empty(), "次の確認では何も起きない")

	# 閉じているあいだに冬が来て過ぎた
	var w2 := _world("spring")
	var c: Dictionary = _sown(w2, "radish")
	w2.garden.apply_frost()
	_check(w2.garden.crops.size() == 1, "まいたばかりなら春は枯れない")
	c.sown_day = int(Time.get_unix_time_from_datetime_string("2025-11-20") / 86400.0)
	w2.garden.apply_frost()
	_check(w2.garden.crops.is_empty() and w2.garden.last_frost == {"radish": 1}, "閉じているあいだに冬が過ぎていれば枯れている")
	var c2: Dictionary = _sown(w2, "radish")
	var day: int = int(Time.get_unix_time_from_datetime_string("2026-03-05") / 86400.0)
	c2.sown_day = day
	_check(not w2.garden._winter_between(day, day + 100), "春から夏のあいだに冬の日はない")
	_check(w2.garden._winter_between(day - 10, day), "2 月をまたぐと冬の日がある")

	# 日付が変わった確認で呼ばれる
	var w3 := _world("winter")
	_sown(w3, "radish")
	w3.forest.last_day = "2000-01-01"
	_check(w3.check_new_day() != "" and w3.garden.crops.is_empty(), "日付が変わった最初の確認で、霜が降りる")

	# 予告
	var w4 := _world("autumn")
	_check(not w4.garden.frost_is_near("2026-11-24"), "畑に野菜がなければ予告しない")
	_sown(w4, "garlic")
	_check(not w4.garden.frost_is_near("2026-11-24"), "ニンニクだけなら予告しない")
	_sown(w4, "radish", Vector2(10, 10))
	_check(not w4.garden.frost_is_near("2026-11-23"), "11 月 23 日はまだ予告しない")
	_check(w4.garden.frost_is_near("2026-11-24") and w4.garden.frost_is_near("2026-11-30"), "11 月 24 日から月末まで予告する")
	_check(not w4.garden.frost_is_near("2026-10-30") and not w4.garden.frost_is_near("2026-12-01"), "ほかの月は予告しない")

# 1 日進める。cared なら、その日の世話もする
func _pass_day(w: GameWorld, cared: bool) -> void:
	for p in w.seedlings.pots:
		p.sown_day -= 1
		p.last_watered = ""
	if cared:
		w.seedlings.act(OUTSIDE, "radish")

func _test_seedlings() -> void:
	print("苗づくり")
	var w := _world("winter")
	var sl := w.seedlings
	_check(sl.act(OUTSIDE, "tomato") == "none", "小屋がなければ苗づくりはできない")
	w.cabin.site = SITE
	w.cabin.stage = 2
	_check(sl.act(OUTSIDE, "tomato") == "none", "小屋が建ち上がるまではできない")
	w.cabin.stage = 3
	_check(sl.act(Vector2(0, 0), "tomato") == "far", "離れているとできない")
	_check(sl.act(OUTSIDE, "radish") == "not_seedling", "ラディッシュは苗にできない")
	_check(sl.act(OUTSIDE, "tomato") == "no_seed", "種がなければまけない")
	w.market.buy("tomato_seed")
	_check(w.market.money == 1920 and w.garden.seeds.tomato == 1, "トマトの種を 80₽ で買える")
	_check(sl.act(OUTSIDE, "tomato") == "sown" and sl.pots.size() == 1 and w.garden.seeds.tomato == 0, "冬でも鉢にまける(種が減る)")
	_check(sl.watered_today(sl.pots[0]), "まいた日の世話は済んでいる")
	_check(sl.growth_days(sl.pots[0]) == 0.0 and sl.days_left() == 5, "まいた日は育っていない(あと 5 日)")

	w.garden.seeds.tomato = 6
	w.garden.seeds.cucumber = 1
	_check(sl.act(OUTSIDE, "cucumber") == "sown" and sl.pots[1].kind == "cucumber", "きゅうりも苗にできる")
	for i in range(4):
		sl.act(OUTSIDE, "tomato")
	_check(sl.pots.size() == 6 and sl.act(OUTSIDE, "tomato") == "full" and w.garden.seeds.tomato == 2, "鉢は 6 つまで")

	# 毎日世話をする
	for i in range(4):
		_pass_day(w, true)
	_check(sl.growth_days(sl.pots[0]) == 4.0 and sl.days_left() == 1 and sl.watered_today(sl.pots[0]), "4 日世話をすると 4 日ぶん育つ")
	_check(sl.act(OUTSIDE, "radish") == "not_seedling" and sl.pots.size() == 6, "今日の世話が済めば、もう進まない")
	_pass_day(w, false)
	_check(sl.needs_care(), "日付が変わると、また世話がいる")
	_check(sl.act(OUTSIDE, "radish") == "collected" and sl.pots.is_empty(), "5 日で育って、受け取れる")
	_check(sl.last_count == 6 and sl.ready == {"tomato": 5, "cucumber": 1}, "種類ごとに数えて受け取る")

	# 世話をしないと倍かかる
	var w2 := _with_cabin()
	w2.garden.seeds.tomato = 1
	w2.seedlings.act(OUTSIDE, "tomato")
	var pot: Dictionary = w2.seedlings.pots[0]
	pot.sown_day -= 5
	pot.last_watered = ""
	pot.water_days = 0
	_check(w2.seedlings.growth_days(pot) == 2.5 and not w2.seedlings.is_grown(pot), "世話なしの 5 日は 2.5 日ぶん")
	pot.sown_day -= 5
	_check(w2.seedlings.is_grown(pot), "世話なしでも 10 日で育つ(枯れない)")
	_check(w2.seedlings.act(OUTSIDE, "tomato") == "collected", "育っていれば受け取るのが先")

	# 霜と雨は小屋の中まで届かない
	var w3 := _with_cabin()
	w3.garden.seeds.tomato = 1
	w3.seedlings.act(OUTSIDE, "tomato")
	w3.seedlings.pots[0].last_watered = ""
	w3.garden.apply_frost()
	w3.garden.water_all()
	_check(w3.seedlings.pots.size() == 1 and w3.seedlings.needs_care(), "鉢は霜で枯れず、雨でも水が入らない")

func _test_transplant() -> void:
	print("苗を畑に植える")
	var w := _with_cabin("spring")
	var g := w.garden
	var sl := w.seedlings
	w.land.toggle_plot(SPOT)
	_check(g.sow(SPOT, "tomato") == "needs_seedling" and g.crops.is_empty(), "トマトは種をじかにまけない")
	_check(sl.transplant(SPOT, "tomato") == "no_seedling", "苗がなければ植えられない")
	sl.ready.tomato = 1
	w.forest.season = "winter"
	_check(sl.transplant(SPOT, "tomato") == "not_season" and sl.ready.tomato == 1, "冬は畑に植えられない(苗は減らない)")
	w.forest.season = "autumn"
	_check(sl.transplant(SPOT, "tomato") == "not_season", "トマトは秋にも植えられない")
	w.forest.season = "spring"
	_check(sl.transplant(Vector2(30, 30), "tomato") == "no_plot" and sl.ready.tomato == 1, "区画の外には植えられない")
	_check(sl.transplant(SPOT, "tomato") == "sown" and sl.ready.tomato == 0, "春に区画へ植えると、苗が減る")
	var c: Dictionary = g.crop_at(SPOT)
	_check(g.growth_days(c) == 2.0 and g.days_left(c) == 5, "苗は 2 日ぶん育った状態から(トマトは 7 日のところ、あと 5 日)")
	c.sown_day -= 5
	c.water_days = 5
	_check(g.is_ripe(c), "毎日水をやれば 5 日で収穫できる")
	_check(g.harvest_at(SPOT) == "harvested" and g.produce.tomato == 30, "トマトは 1 区画 30kg")
	_check(w.market.sell_all("tomato") == 1200, "30kg × 40₽ = 1,200₽ で売れる")

	# きゅうりは種からでも苗からでも
	g.seeds.cucumber = 1
	sl.ready.cucumber = 1
	w.land.toggle_plot(Vector2(10, 10))
	_check(sl.transplant(Vector2(10, 10), "cucumber") == "sown", "きゅうりは苗からも植えられる")
	_check(g.days_left(g.crop_at(Vector2(10, 10))) == 3 and g.seeds.cucumber == 1, "きゅうりの苗: あと 3 日(種は減らない)")

func _test_market() -> void:
	print("苗を売る")
	var w := _with_cabin()
	var sl := w.seedlings
	sl.ready = {"tomato": 2, "cucumber": 1}
	var money: int = w.market.money
	_check(w.market.sell_all("seedling_tomato") == 300 and sl.ready.tomato == 0 and sl.ready.cucumber == 1, "トマトの苗 2 鉢 × 150₽")
	_check(w.market.sell_all("seedling_cucumber") == 120 and w.market.money == money + 420, "きゅうりの苗 1 鉢 × 120₽")
	_check(w.market.sell_all("seedling_tomato") == 0, "苗がなければ 0₽")
	_check(w.market.SELL_PRICES.seedling_tomato > w.market.good("tomato_seed").price, "苗の値段は種代より高い")

func _test_save() -> void:
	print("セーブ")
	var w := _with_cabin("spring")
	w.garden.seeds.tomato = 2
	w.seedlings.act(OUTSIDE, "tomato")
	w.seedlings.ready.tomato = 4
	w.land.toggle_plot(SPOT)
	w.seedlings.transplant(SPOT, "tomato")
	w.save_game()
	var w2 := _world("spring", false)
	w2.load_game()
	var sl := w2.seedlings
	_check(sl.pots.size() == 1 and sl.pots[0].kind == "tomato" and sl.watered_today(sl.pots[0]), "鉢が復元される")
	_check(sl.ready.tomato == 3 and sl.ready.cucumber == 0, "育った苗の数が復元される")
	_check(w2.garden.days_left(w2.garden.crop_at(SPOT)) == 5, "苗から植えた野菜の早さが復元される")

	# 手順 3-4 までのセーブ: 苗の記録がなく、畑の野菜に head がない
	_remove_save()
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"unit": "m", "seeds": {"birch": 1, "apple": 0, "cedar": 0}, "last_day": "", "today_event": "", "trees": [],
		"land": {"plots": [[1.5, 1.5]]},
		"garden": {"crops": [{"x": 1.5, "y": 1.5, "kind": "radish", "sown_day": w.forest.day_number(), "water_days": 0, "last_watered": ""}], "seeds": {"radish": 1}},
	}))
	file.close()
	var w3 := _world("spring", false)
	w3.seedlings.ready.tomato = 9  # 読み込みで消えることを見る
	w3.load_game()
	_check(w3.seedlings.pots.is_empty() and w3.seedlings.ready.tomato == 0 and w3.garden.seeds.tomato == 0, "前のセーブは鉢も苗もなしから")
	_check(w3.garden.growth_days(w3.garden.crop_at(SPOT)) == 0.0, "前のセーブの野菜はふつうに育つ")
