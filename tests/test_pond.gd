extends SceneTree

# 池の作り込み(手順 3-4)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_pond.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Forest = preload("res://logic/Forest.gd")

const TEST_SAVE := "user://test_pond.json"
const SPOT := Vector2(-20, -20)

var _failed := 0
var _passed := 0

# 毎日雨 / 毎日晴れの Forest(天気は日付で決まるので、ふつうには選べない)
# テストを動かす季節に左右されないよう、夏の蒸発も決めておく
class RainForest extends Forest:
	func roll_daily_event(_date: String) -> String:
		return "rain"
	func is_summer_date(_date: String) -> bool:
		return false

class DryForest extends Forest:
	func roll_daily_event(_date: String) -> String:
		return "birds"
	func is_summer_date(_date: String) -> bool:
		return false

class SummerForest extends Forest:
	func roll_daily_event(_date: String) -> String:
		return "birds"
	func is_summer_date(_date: String) -> bool:
		return true

class SummerRainForest extends Forest:
	func roll_daily_event(_date: String) -> String:
		return "rain"
	func is_summer_date(_date: String) -> bool:
		return true

func _initialize() -> void:
	_test_dig()
	_test_cancel()
	_test_quest()
	_test_rain()
	_test_creatures()
	_test_water_around()
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

func _world(forest: Forest = null, remove_save := true) -> GameWorld:
	if remove_save:
		_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	if forest != null:
		w.forest = forest
		w.pond.forest = forest
		w.garden.forest = forest
		w.cabin.forest = forest
		w.quests.forest = forest
		w.market.forest = forest
	w.forest.season = "autumn"
	return w

# 掘り終えた池を作る
func _dug(w: GameWorld, spring := false) -> void:
	w.pond_action(SPOT)
	for i in range(w.pond.DIG_DAYS):
		w.pond.last_dug = ""
		w.pond_action(SPOT)
	if not spring:
		# 雨のたまり方を見るテストでは、湧き水を抜いて空の池から始める
		w.pond.water = 0
		w.pond.wet_since_day = -1

# 1 日進める: 雨を数え直すところだけ前の日に戻す
func _days_pass(w: GameWorld, days: int) -> void:
	w.pond.last_checked_day -= days
	if w.pond.wet_since_day >= 0:
		w.pond.wet_since_day -= days
	w.pond.catch_up()

func _test_dig() -> void:
	print("掘る")
	var w := _world()
	var p := w.pond
	_check(not p.is_placed() and p.dig(SPOT) == "none", "場所を決める前は掘れない")
	_check(w.pond_action(Vector2(49, 0)) == "outside" and not p.is_placed(), "境界にかかる場所には掘れない")
	_check(w.pond_action(SPOT) == "placed" and w.land.pond == SPOT and p.days_dug == 0, "P で足元が池の場所になる(まだ掘っていない)")
	_check(not p.is_dug(), "場所を決めただけでは池にならない")
	_check(w.pond_action(Vector2(20, 20)) == "far" and w.land.pond == SPOT, "池はひとつまで(離れた場所で押しても増えない)")
	_check(w.pond_action(SPOT) == "dug" and p.days_dug == 1 and p.dug_today(), "1 日目を掘る")
	_check(w.pond_action(SPOT) == "done_today" and p.days_dug == 1, "掘るのは 1 日 1 回")
	var edge := SPOT + Vector2(5.5, 0)  # 縁(半径 4m)から 1.5m
	p.last_dug = ""
	_check(w.pond_action(edge) == "dug" and p.days_dug == 2, "縁の外 2m 以内からでも掘れる")
	for i in range(2):
		p.last_dug = ""
		_check(w.pond_action(SPOT) == "dug", "%d 日目を掘る" % (i + 3))
	p.last_dug = ""
	_check(w.pond_action(SPOT) == "finished" and p.is_dug(), "5 日目で掘り終える")
	_check(p.water == p.SPRING_FILL and p.wet_days() == 0, "掘り終えた日に湧き水で半分たまり、生き物を待つ日数が始まる")
	p.last_dug = ""
	_check(w.pond_action(SPOT) == "already" and p.days_dug == 5, "掘り終えたらそれ以上は掘れない")

func _test_cancel() -> void:
	print("場所の取り消し")
	var w := _world()
	var p := w.pond
	_check(not p.cancel(SPOT), "場所がなければ取り消せない")
	w.pond_action(SPOT)
	_check(not p.cancel(Vector2(30, 30)), "離れていると取り消せない")
	_check(p.cancel(SPOT) and not p.is_placed(), "掘りはじめる前なら取り消せる")
	w.pond_action(SPOT)
	w.pond_action(SPOT)
	_check(not p.cancel(SPOT) and p.is_placed(), "掘りはじめたら取り消せない")

func _test_quest() -> void:
	print("クエスト")
	var w := _world()
	var q := w.quests
	_check(q.progress("pond") == [0, 1], "はじめは未達成")
	w.pond_action(SPOT)
	w.pond_action(SPOT)
	_check(q.progress("pond") == [0, 1], "掘っている途中はまだ未達成")
	_dug(w)
	_check(q.progress("pond") == [1, 1], "掘り終えると達成(水がなくてもよい)")

func _test_rain() -> void:
	print("雨で水がたまる")
	var w := _world(RainForest.new())
	var p := w.pond
	p.catch_up()
	_check(p.water == 0, "池がなければ何も起きない")
	w.pond_action(SPOT)
	w.pond_action(SPOT)
	p.last_checked_day = w.forest.day_number() - 3
	p.catch_up()
	_check(p.water == 0, "掘っている途中の雨はたまらない")
	_dug(w)
	_check(p.last_checked_day == w.forest.day_number(), "掘り終えた日からあとの雨を数える")
	p.catch_up()
	_check(p.water == 0 and p.last_gain == 0, "掘り終えた当日の雨は数えない")
	_days_pass(w, 1)
	_check(p.water == 25 and p.last_gain == 25 and p.wet_since_day == -1, "雨 1 回で 25%(まだ生き物は来ない)")
	_days_pass(w, 3)
	_check(p.water == 100 and p.last_gain == 75, "閉じていた 3 日ぶんの雨もたまる")
	_days_pass(w, 2)
	_check(p.water == 100 and p.last_gain == 0, "満杯より増えない")

	# 毎日チェックする通り道: 日付が変わった確認で呼ばれる
	var w2 := _world(RainForest.new())
	_dug(w2)
	w2.pond.last_checked_day -= 1
	w2.forest.last_day = "2000-01-01"
	_check(w2.check_new_day() == "rain" and w2.pond.water == 25, "日付が変わった最初の確認で、水がたまる")
	_check(w2.check_new_day() == "" and w2.pond.water == 25, "同じ日の 2 回目はたまらない")

	# 晴れが続くと増えない。減りもしない
	var w3 := _world(DryForest.new())
	_dug(w3)
	w3.pond.water = 50
	_days_pass(w3, 10)
	_check(w3.pond.water == 50 and w3.pond.last_gain == 0, "雨が降らなければ増えない(減りもしない)")

	# 夏の蒸発
	var w4 := _world(SummerForest.new())
	_dug(w4)
	w4.pond.water = 50
	_days_pass(w4, 10)
	_check(w4.pond.water == 30 and w4.pond.last_gain == -20, "夏は 1 日 2% 減る(閉じていた 10 日ぶんも)")
	_days_pass(w4, 100)
	_check(w4.pond.water == 0, "0% より減らない")
	var w5 := _world(SummerRainForest.new())
	_dug(w5)
	_days_pass(w5, 1)
	_check(w5.pond.water == 25, "夏の雨の日: 空の池に 25% たまる(蒸発のあとに雨)")
	_days_pass(w5, 1)
	_check(w5.pond.water == 48, "次の雨の日: 2% 減って 25% 増える")
	var f2 := Forest.new()
	_check(f2.is_summer_date("2026-06-01") and f2.is_summer_date("2026-08-31"), "夏は 6 月 1 日から 8 月 31 日まで")
	_check(not f2.is_summer_date("2026-05-31") and not f2.is_summer_date("2026-09-01"), "5 月と 9 月は夏ではない")

	# 本物の天気: 2026 年の雨の日は 90 日(ROADMAP の記録どおり)。満杯まで 4 回
	var f := Forest.new()
	var rains := 0
	var start := int(Time.get_unix_time_from_datetime_string("2026-01-01") / 86400.0)
	for d in range(start, start + 365):
		if f.roll_daily_event(Forest.date_of_day(d)) == "rain":
			rains += 1
	print("    2026 年の雨の日: ", rains)
	_check(rains == 90, "通し番号から戻した日付で、日替わりの天気が同じになる")

func _test_creatures() -> void:
	print("生き物")
	var w := _world(RainForest.new())
	var p := w.pond
	_dug(w)
	_check(p.wet_days() == -1 and p.present().is_empty(), "水がなければ生き物はいない")
	_days_pass(w, 2)
	_check(p.water == 50 and p.wet_days() == 0 and p.present().is_empty(), "水が半分になった日はまだ来ない")
	_days_pass(w, 2)
	_check(p.wet_days() == 2 and p.present() == ["strider"] and p.last_arrivals == ["strider"], "2 日後: アメンボが来て、知らせが出る")
	_days_pass(w, 1)
	_check(p.last_arrivals.is_empty() and p.seen == ["strider"], "2 度は知らせない")

	var expected := [
		[5, "autumn", ["strider", "reed"], "5 日後・秋: ガマが生える"],
		[7, "autumn", ["strider", "reed"], "7 日後・秋: カエルはまだ(春と夏だけ)"],
		[7, "spring", ["strider", "reed", "frog"], "7 日後・春: カエルが来る"],
		[10, "autumn", ["strider", "reed", "dragonfly"], "10 日後・秋: トンボが来る"],
		[14, "autumn", ["strider", "reed", "dragonfly", "duck"], "14 日後・秋: カモが来る"],
		[14, "summer", ["strider", "reed", "frog", "dragonfly", "duck"], "14 日後・夏: ぜんぶいる"],
		[14, "spring", ["strider", "reed", "frog", "duck"], "14 日後・春: トンボはまだいない"],
		[14, "winter", ["reed"], "14 日後・冬: ガマだけ残る"],
	]
	for e in expected:
		p.wet_since_day = w.forest.day_number() - e[0]
		w.forest.season = e[1]
		_check(p.present() == e[2], e[3])
	_check(p.is_frozen(), "冬は氷が張る")
	_check(p.is_on_ice(SPOT) and p.is_on_ice(SPOT + Vector2(3.9, 0)) and not p.is_on_ice(SPOT + Vector2(4.2, 0)), "凍った池の上(縁まで)を歩ける")
	w.forest.season = "spring"
	_check(not p.is_frozen(), "春には解ける")
	_check(not p.is_on_ice(SPOT), "解けたら氷の上ではない")

	# 湧き水だけで、雨を待たずに来る(晴れが続いても)
	var w3 := _world(DryForest.new())
	_dug(w3, true)
	_check(w3.pond.water == 50 and w3.pond.present().is_empty(), "湧き水の日はまだ来ない")
	_days_pass(w3, 2)
	_check(w3.pond.water == 50 and w3.pond.present() == ["strider"] and w3.pond.last_arrivals == ["strider"], "雨がなくても 2 日後にアメンボが来る")

	# 留守のあいだに来た生き物も、まとめて知らせる
	var w2 := _world(RainForest.new())
	_dug(w2)
	w2.pond.last_checked_day -= 30
	w2.pond.catch_up()
	_check(w2.pond.water == 100 and w2.pond.wet_days() == 28, "30 日留守: 水は満杯、2 回目の雨(28 日前)で半分を超えた")
	_check(w2.pond.last_arrivals == ["strider", "reed", "dragonfly", "duck"], "30 日留守: 来ていた生き物をまとめて知らせる(秋)")

func _test_water_around() -> void:
	print("池からまとめて水やり")
	var w := _world()
	var p := w.pond
	var f := w.forest
	var g := w.garden
	f.today_event = "birds"
	f.last_day = f.today()
	_check(p.water_around(SPOT) == "far", "池がなければ運べない")
	w.pond_action(SPOT)
	_check(p.water_around(SPOT) == "far", "掘り終えるまでは運べない")
	_dug(w)
	_check(p.water_around(SPOT) == "low", "水がなければ運べない")
	p.water = 4
	_check(p.water_around(SPOT) == "low", "水が 5% 未満なら運べない")
	p.water = 100
	_check(p.water_around(SPOT) == "nothing" and p.water == 100, "水のいるものがなければ、水は減らない")

	# 20m 以内: 木 2 本と区画 1。外: 木 1 本と区画 1
	f.saplings = {"birch": 3, "apple": 0, "cedar": 0}
	f.add_tree(SPOT + Vector2(5, 0), "birch", "sapling")
	f.add_tree(SPOT + Vector2(0, 19), "birch", "sapling")
	f.add_tree(SPOT + Vector2(21, 0), "birch", "sapling")
	var near_plot := SPOT + Vector2(0, -10)
	var far_plot := SPOT + Vector2(-25, 0)
	g.seeds.radish = 2
	w.land.toggle_plot(near_plot)
	w.land.toggle_plot(far_plot)
	g.sow(near_plot, "radish")
	g.sow(far_plot, "radish")
	_check(p.dry_around() == [1, 2], "20m 以内の、水のいる区画と木を数える")
	_check(p.water_around(SPOT + Vector2(30, 0)) == "far", "池から離れていると運べない")
	_check(p.water_around(SPOT + Vector2(5.5, 0)) == "watered", "池のそば(縁から 2m 以内)から運べる")
	_check(p.last_watered == [1, 2] and p.water == 95, "区画 1・木 2 に水が入り、池の水が 5% 減る")
	_check(g.watered_today(g.crop_at(near_plot)) and not g.watered_today(g.crop_at(far_plot)), "20m の外の区画には入らない")
	_check(f.watered_today(f.trees[0]) and f.watered_today(f.trees[1]) and not f.watered_today(f.trees[2]), "20m の外の木には入らない")
	_check(absf(f.trees[0].bonus_years - 0.5) < 0.001, "木の水やりのボーナスもふつうどおり付く")
	_check(p.water_around(SPOT) == "nothing" and p.water == 95, "今日はもう水がいらない(水は減らない)")
	_check(p.dry_around() == [0, 0], "全部済むと数は 0")

	# 収穫できる野菜には運ばない
	var c: Dictionary = g.crop_at(near_plot)
	c.sown_day -= 5
	c.water_days = 6
	c.last_watered = ""
	_check(p.dry_around() == [0, 0], "収穫できる野菜は数えない")

	# 冬は凍っていて汲めない
	f.trees[0].last_watered = ""
	f.season = "winter"
	_check(p.water_around(SPOT) == "frozen" and p.water == 95, "冬は凍っていて運べない")
	f.season = "autumn"
	_check(p.water_around(SPOT) == "watered" and p.water == 90, "凍っていなければ運べる")

	# 水が半分より減っても、生き物は残る
	p.wet_since_day = f.day_number() - 20
	p.water = 10
	_check(not p.present().is_empty(), "水が減っても、来た生き物はいなくならない")

func _test_save() -> void:
	print("セーブ")
	var w := _world()
	w.pond_action(SPOT)
	w.pond_action(SPOT)
	var w2 := _world(null, false)
	w2.load_game()
	_check(w2.land.pond == SPOT and w2.pond.days_dug == 1 and w2.pond.dug_today(), "掘った日数が自動で保存・復元される")

	w2.pond.days_dug = 5
	w2.pond.water = 75
	w2.pond.wet_since_day = 100
	w2.pond.last_checked_day = 200
	w2.pond.seen = ["strider"]
	w2.save_game()
	var w3 := _world(null, false)
	w3.load_game()
	var p3 := w3.pond
	_check(p3.is_dug() and p3.water == 75 and p3.wet_since_day == 100 and p3.last_checked_day == 200, "水の量と日付が復元される")
	_check(p3.seen == ["strider"], "一度来た生き物の記録が復元される")

	# 手順 3-3 までのセーブ: 池の場所だけある(一瞬で掘れて水も入っていた)
	_remove_save()
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"unit": "m", "seeds": {"birch": 1, "apple": 0, "cedar": 0}, "last_day": "", "today_event": "", "trees": [],
		"land": {"plots": [], "pond": [-12.5, 0]}, "quests": {"stage": 3},
	}))
	file.close()
	var w4 := _world(null, false)
	w4.load_game()
	var p4 := w4.pond
	_check(p4.is_dug() and p4.water == 100, "前のセーブの池は掘り終えた満杯の池")
	_check(p4.wet_days() == 0 and p4.present().is_empty(), "生き物はこれから来る")
	_check(w4.quests.progress("pond") == [1, 1] and w4.quests.done.size() == 3, "クエストの達成はそのまま")

	# 湧き水より前のセーブ: 掘り終えて空の池には、開いたときに 1 回だけ湧き水が入る
	_remove_save()
	var old_pond := {"days_dug": 5, "last_dug": "2026-11-10", "water": 0, "wet_since_day": -1, "last_checked_day": 100, "seen": []}
	file = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"unit": "m", "last_day": "", "today_event": "", "trees": [],
		"land": {"plots": [], "pond": [-12.5, 0]}, "pond": old_pond}))
	file.close()
	var w6 := _world(null, false)
	w6.load_game()
	_check(w6.pond.water == 50 and w6.pond.wet_days() == 0, "掘り終えた空の池に湧き水が入る")
	w6.pond.water = 10
	w6.save_game()
	var w7 := _world(null, false)
	w7.load_game()
	_check(w7.pond.water == 10, "2 回目からは入らない(一度入れたら印が付く)")
	_remove_save()
	old_pond.days_dug = 3
	file = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"unit": "m", "last_day": "", "today_event": "", "trees": [],
		"land": {"plots": [], "pond": [-12.5, 0]}, "pond": old_pond}))
	file.close()
	var w8 := _world(null, false)
	w8.load_game()
	_check(w8.pond.water == 0 and not w8.pond.is_dug(), "掘っている途中の池には入らない(掘り終えた日に入る)")
	old_pond.days_dug = 5
	old_pond.water = 75
	old_pond.wet_since_day = 90
	_remove_save()
	file = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"unit": "m", "last_day": "", "today_event": "", "trees": [],
		"land": {"plots": [], "pond": [-12.5, 0]}, "pond": old_pond}))
	file.close()
	var w9 := _world(null, false)
	w9.load_game()
	_check(w9.pond.water == 75 and w9.pond.wet_since_day == 90, "もう水がある池はそのまま")

	# 前のセーブで池がなければ、記録がなくても空
	_remove_save()
	file = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"unit": "m", "last_day": "", "today_event": "", "trees": [], "land": {"plots": []}}))
	file.close()
	var w5 := _world(null, false)
	w5.pond.water = 50  # 読み込みで消えることを見る
	w5.load_game()
	_check(not w5.pond.is_placed() and w5.pond.water == 0 and w5.pond.days_dug == 0, "池がないセーブは空から")
