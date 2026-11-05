extends SceneTree

# お金・市場・種と苗木・発芽・育った木が落とす種・現実寄りの育ち方(手順 3)のロジックテスト。
# 本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_market.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Forest = preload("res://logic/Forest.gd")

const TEST_SAVE := "user://test_market.json"
const DAY := 86400

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_buy_and_sell()
	_test_saplings()
	_test_germination()
	_test_seed_drops()
	_test_growth_is_realistic()
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

func _world(remove_save := true) -> GameWorld:
	if remove_save:
		_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.forest.season = "autumn"
	return w

func _now() -> int:
	return int(Time.get_unix_time_from_system())

# 植えた直後の木を days 日前に植えた扱いにする
func _age(t: Dictionary, days: float) -> void:
	t.planted_at = _now() - int(days * DAY)

func _test_buy_and_sell() -> void:
	print("市場")
	var w := _world()
	var m := w.market
	var f := w.forest
	_check(m.money == 2000, "はじめの所持金は 2,000₽")
	_check(m.is_near(Vector2(0, 54)) and not m.is_near(Vector2(0, 0)), "市場の前(南の境界の外)でだけ売り買いできる")
	_check(m.buy("birch_seed") == "bought" and m.money == 1940 and f.seeds.birch == 13, "白樺の種(10粒・60₽)を買うと種が 10 増える")
	_check(m.buy("cedar_sapling") == "bought" and m.money == 440 and f.saplings.cedar == 1, "シベリア杉の苗木(1,500₽)を買える")
	_check(m.buy("apple_sapling") == "no_money" and m.money == 440 and f.saplings.apple == 0, "お金が足りなければ買えない")
	_check(m.buy("nothing") == "unknown", "ない品は買えない")
	f.produce.apple = 20
	_check(m.sell_all("apple") == 300 and m.money == 740 and f.produce.apple == 0, "リンゴ 20 個を売ると 300₽(1 個 15₽)")
	_check(m.sell_all("apple") == 0 and m.money == 740, "売るリンゴがなければ 0₽")
	_check(Forest.apple_yield(6.0) == 5 and Forest.apple_yield(8.0) == 15 and Forest.apple_yield(9.0) == 20 and Forest.apple_yield(40.0) == 20, "収穫量は樹齢 6 年で 5 個、1 年ごとに 5 個増えて、上限 20 個")

func _test_saplings() -> void:
	print("苗木")
	var w := _world()
	var f := w.forest
	_check(not f.add_tree(Vector2(0, 0), "birch", "sapling"), "苗木がなければ植えられない")
	f.saplings.birch = 1
	var seeds_before: int = f.seeds.birch
	_check(f.add_tree(Vector2(0, 0), "birch", "sapling") and f.saplings.birch == 0 and f.seeds.birch == seeds_before, "苗木を植えると苗木が 1 減る(種は減らない)")
	var t: Dictionary = f.trees[0]
	_check(absf(f.real_age_years(t) - 2.0) < 0.01, "白樺の苗木は樹齢 2 年から")
	_check(f.is_established(t) and not f.is_seed(t), "苗木はすぐ根付く")
	f.saplings.apple = 1
	f.add_tree(Vector2(10, 0), "apple", "sapling")
	_age(f.trees[-1], 3.0)
	_check(f.harvest_nearest(Vector2(10, 0), 2.0) == "harvested", "リンゴの苗木(樹齢 3 年)は 3 日で実る(樹齢 6 年)")

func _test_germination() -> void:
	print("種と発芽")
	var w := _world()
	var f := w.forest
	f.seeds = {"birch": 2000, "apple": 0, "cedar": 0}
	f.germination_rates.birch = 1.0
	f.add_tree(Vector2(0, 0), "birch")
	var t: Dictionary = f.trees[0]
	_check(f.is_seed(t) and not f.is_established(t) and f.radius_of(t) == 0.0, "まいたばかりの種は土の中(根付いていない)")
	_age(t, 1.0)
	_check(not f.is_seed(t) and f.is_established(t), "1 日たつと芽が出る")

	f.germination_rates.birch = 0.0
	f.add_tree(Vector2(5, 0), "birch")
	var bad: Dictionary = f.trees[-1]
	_check(not bad.sprouts and not f.has_failed(bad), "芽が出ない種も、1 日たつまでは分からない")
	_age(bad, 1.0)
	_check(f.has_failed(bad) and not f.is_established(bad), "1 日たつと芽が出なかったと分かる")
	f.last_day = "2000-01-01"
	f.check_new_day()
	_check(f.trees.size() == 1 and f.last_failed.get("birch", 0) == 1, "翌日の確認で、芽が出なかった種は消える(数を知らせる)")

	# 発芽率は 40%。1000 粒まくと 350〜450 粒ほど芽が出る
	f.germination_rates.birch = 0.4
	f.trees.clear()
	for i in range(1000):
		f.add_tree(Vector2(i * 0.05, 7), "birch")
	var n := 0
	for tree in f.trees:
		if tree.sprouts:
			n += 1
	print("    1000 粒のうち芽が出る数: ", n)
	_check(n >= 350 and n <= 450, "白樺の発芽率はおよそ 40%")

func _test_seed_drops() -> void:
	print("育った木が落とす種")
	var w := _world()
	var f := w.forest
	f.saplings = {"birch": 3, "apple": 1, "cedar": 2}
	f.add_tree(Vector2(0, 0), "birch", "sapling")
	_age(f.trees[-1], 8.0)   # 2 + 8 = 樹齢 10 年
	f.add_tree(Vector2(20, 0), "birch", "sapling")
	_age(f.trees[-1], 6.5)   # 樹齢 8.5 年(まだ落とさない)
	f.add_tree(Vector2(-20, 0), "cedar", "sapling")
	_age(f.trees[-1], 21.0)  # 4 + 21 = 樹齢 25 年
	f.add_tree(Vector2(0, 20), "apple", "sapling")
	_age(f.trees[-1], 20.0)  # リンゴは種を落とさない(収穫する)

	f.season = "autumn"
	f.drop_seeds("2026-10-01")
	_check(f.pickups.size() == 2, "秋: 樹齢 10 年の白樺と 25 年の杉が落とす(若い白樺・リンゴは落とさない)")
	var ok := true
	for p in f.pickups:
		var tree_pos := Vector2(0, 0) if p.species == "birch" else Vector2(-20, 0)
		var d: float = p.pos.distance_to(tree_pos)
		if d < 1.0 or d > 2.5 or p.amount != 5:
			ok = false
	_check(ok, "種は根元から 1〜2.5m に、5 粒ずつ落ちている")
	var first: Vector2 = f.pickups[0].pos
	f.drop_seeds("2026-10-01")
	_check(f.pickups[0].pos == first, "落ちる場所は日付で決まる(開き直しても同じ)")
	f.season = "winter"
	f.drop_seeds("2026-12-01")
	_check(f.pickups.size() == 1 and f.pickups[0].species == "birch", "冬: 白樺は落とすが、杉は落とさない")
	f.season = "summer"
	f.drop_seeds("2026-07-01")
	_check(f.pickups.is_empty(), "夏はどれも落とさない")

	f.season = "autumn"
	f.last_day = "2000-01-01"
	f.check_new_day()
	_check(f.pickups.size() == 2, "日付が変わった最初の確認で、今日の分が落ちる")
	var before: int = f.seeds.birch
	var got: Array = f.collect_near(Vector2(50, 50), 1.2)
	_check(got.is_empty(), "離れていると拾えない")
	var bp: Vector2 = f.pickups[0].pos if f.pickups[0].species == "birch" else f.pickups[1].pos
	got = f.collect_near(bp + Vector2(0.5, 0), 1.2)
	_check(got.size() == 1 and f.seeds.birch == before + 5 and f.pickups.size() == 1, "近づくと拾えて、種が 5 増える")
	f.last_day = "2000-01-01"
	f.season = "summer"
	f.check_new_day()
	_check(f.pickups.is_empty(), "拾わなかった分は翌日には消える(たまらない)")

func _test_growth_is_realistic() -> void:
	print("育ち方(若いうちはゆっくり)")
	var f := Forest.new()
	var t := {"species": "birch", "form": "", "planted_at": _now(), "start_age": 1.0, "sprouts": true, "bonus_years": 0.0}
	_check(f.radius_of(t) < 0.05, "白樺 1 年: 樹冠半径 5cm 未満(高さ 0.2m ほど)")
	t.start_age = 10.0
	var r10: float = f.radius_of(t)
	_check(r10 > 1.8 and r10 < 2.4, "白樺 10 年: 樹冠半径 1.8〜2.4m(高さ 8〜10m ほど)")
	t.species = "cedar"
	_check(f.radius_of(t) < 0.4, "シベリア杉 10 年: まだ小さい(樹冠半径 0.4m 未満)")
	t.start_age = 25.0
	var c25: float = f.radius_of(t)
	_check(c25 > 1.0 and c25 < 1.6, "シベリア杉 25 年: 樹冠半径 1〜1.6m(高さ 5m ほど)")
	t.species = "apple"
	t.start_age = 6.0
	var a6: float = f.radius_of(t)
	_check(a6 > 1.2 and a6 < 1.8, "リンゴ 6 年(実りはじめ): 樹冠半径 1.2〜1.8m")

func _test_save() -> void:
	print("セーブ")
	var w := _world()
	var f := w.forest
	w.market.buy("apple_sapling")
	f.add_tree(Vector2(3, 4), "apple", "sapling")
	f.add_tree(Vector2(6, 4), "birch")
	f.produce.apple = 7
	f.pickups.append({"pos": Vector2(1, 2), "species": "birch", "amount": 5})
	w.save_game()
	var w2 := _world(false)
	w2.load_game()
	var f2 := w2.forest
	_check(w2.market.money == 1100, "所持金が保存・復元される")
	_check(f2.produce.apple == 7 and f2.saplings.apple == 0, "収穫物と苗木の数が保存・復元される")
	_check(f2.trees[0].form == "sapling" and f2.trees[0].start_age == 3.0, "苗木から植えた木は苗木の樹齢ごと復元される")
	_check(f2.trees[1].form == "seed" and f2.trees[1].sprouts == f.trees[1].sprouts, "種から植えた木は、芽が出るかどうかごと復元される")
	_check(f2.pickups.size() == 1 and f2.pickups[0].pos == Vector2(1, 2), "落ちている種が保存・復元される(開き直しても消えない)")

	# 手順 2 までのセーブ: お金・苗木・収穫物・種と苗木の区別がない
	_remove_save()
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"unit": "m", "seeds": {"birch": 1, "apple": 0, "cedar": 0}, "last_day": "", "today_event": "",
		"trees": [{"x": 8.6, "y": 0, "species": "birch", "planted_at": _now() - 5 * DAY, "last_harvest": "", "last_watered": "", "bonus_years": 0}],
	}))
	file.close()
	var w3 := _world(false)
	w3.load_game()
	_check(w3.market.money == 2000 and w3.forest.saplings.birch == 0 and w3.forest.produce.apple == 0, "前のセーブには所持金 2,000₽ を足し、苗木・収穫物は 0 から")
	_check(w3.forest.is_established(w3.forest.trees[0]), "前のセーブの木は根付いている扱い")
