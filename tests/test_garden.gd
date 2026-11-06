extends SceneTree

# 畑と野菜(手順 3-2)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_garden.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Forest = preload("res://logic/Forest.gd")

const TEST_SAVE := "user://test_garden.json"
const SPOT := Vector2(1, 1)  # 区画(1.5, 1.5)の中

var _failed := 0
var _passed := 0

# 今日の発見がかならず雨になる Forest(日付で決まるので、ふつうには選べない)
class RainForest extends Forest:
	func roll_daily_event(_date: String) -> String:
		return "rain"

func _initialize() -> void:
	_test_sowing()
	_test_growth_and_water()
	_test_harvest_and_sell()
	_test_spoiling()
	_test_rain()
	_test_plot_guard_and_remove()
	_test_new_plot_limit()
	_test_preview()
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

# 区画 1 つと、季節を決めた世界。雨の日にならないよう発見を決めておく
func _world(season := "autumn", remove_save := true) -> GameWorld:
	if remove_save:
		_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.forest.season = season
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birds"
	return w

# まいて days 日たった野菜を返す(水は wet_days 回あげた扱い)
func _grown(w: GameWorld, kind: String, days: int, wet_days: int) -> Dictionary:
	w.land.toggle_plot(SPOT)
	w.garden.seeds[kind] = 1
	w.garden.sow(SPOT, kind)
	var c: Dictionary = w.garden.crop_at(SPOT)
	c.sown_day -= days
	c.water_days = wet_days
	return c

func _test_sowing() -> void:
	print("種まき")
	var w := _world()
	var g := w.garden
	_check(g.sow(SPOT, "radish") == "no_plot", "区画がなければまけない")
	w.land.toggle_plot(SPOT)
	_check(g.sow(SPOT, "radish") == "no_seed", "種がなければまけない")
	_check(w.market.buy("radish_seed") == "bought" and g.seeds.radish == 1 and w.market.money == 10960,"ラディッシュの種(1 区画ぶん・40₽)を市場で買える")
	_check(g.sow(SPOT + Vector2(3, 0), "radish") == "no_plot", "区画の外にはまけない")
	_check(g.sow(SPOT, "potato") == "not_season", "じゃがいもは秋にはまけない(春だけ)")
	_check(g.sow(SPOT, "radish") == "sown" and g.seeds.radish == 0 and g.crops.size() == 1, "まくと種が減り、区画に野菜が入る")
	_check(g.crop_at(SPOT).pos == Vector2(1.5, 1.5), "野菜は区画の中心に結びつく")
	_check(not g.crop_at(SPOT + Vector2(0.4, 0.4)).is_empty(), "同じ区画のどこに立っていても足元の野菜が分かる")
	g.seeds.radish = 1
	_check(g.sow(SPOT, "radish") == "occupied" and g.seeds.radish == 1, "1 区画に 1 種類だけ(種は減らない)")

	# 季節ごとにまけるもの
	for expected in [
			["spring", {"radish": true, "carrot": true, "cucumber": true, "potato": true, "garlic": false}],
			["summer", {"radish": false, "carrot": true, "cucumber": true, "potato": false, "garlic": false}],
			["autumn", {"radish": true, "carrot": false, "cucumber": false, "potato": false, "garlic": true}],
			["winter", {"radish": false, "carrot": false, "cucumber": false, "potato": false, "garlic": false}]]:
		var ok := true
		for kind in expected[1]:
			var w2 := _world(expected[0])
			w2.land.toggle_plot(SPOT)
			w2.garden.seeds[kind] = 1
			if (w2.garden.sow(SPOT, kind) == "sown") != expected[1][kind]:
				ok = false
		_check(ok, "%s にまける野菜が現実の目安どおり" % expected[0])

func _test_growth_and_water() -> void:
	print("育ち方と水やり")
	var w := _world()
	var g := w.garden
	var c := _grown(w, "radish", 0, 0)
	_check(g.growth_days(c) == 0.0 and not g.is_ripe(c) and g.days_left(c) == 3, "まいた日は育っていない(ラディッシュはあと 3 日)")
	_check(g.water_at(SPOT) == "watered" and g.watered_today(c), "足元の区画に水をあげられる")
	_check(g.water_at(SPOT) == "done", "水やりは 1 区画 1 日 1 回")
	_check(g.growth_days(c) == 0.0, "今日の水やりは今日の分にはまだ数えない")
	_check(g.water_at(SPOT + Vector2(3, 0)) == "none", "足元に野菜がなければ水はあげられない")

	# 毎日水をあげた: 3 日で収穫できる
	c.sown_day -= 2
	c.water_days = 2
	c.last_watered = ""
	_check(g.growth_days(c) == 2.0 and g.days_left(c) == 1, "2 日間水をあげた: 2 日ぶん育ち、あと 1 日")
	c.sown_day -= 1
	c.water_days = 3
	_check(g.is_ripe(c) and g.days_left(c) == 0, "3 日間水をあげた: 収穫できる")
	_check(g.water_at(SPOT) == "ripe", "収穫できる野菜には水はいらない")

	# 水をあげなかった: 倍かかる
	c.water_days = 0
	_check(g.growth_days(c) == 1.5 and not g.is_ripe(c), "水なしの 3 日は 1.5 日ぶんしか育たない")
	c.sown_day -= 3
	_check(g.is_ripe(c), "水なしでも 6 日で収穫できる(枯れない)")

	# 半々: 4 日のうち 2 日だけ水 = 2 + 1 = 3 日ぶん
	var w2 := _world()
	var c2 := _grown(w2, "radish", 4, 2)
	_check(w2.garden.growth_days(c2) == 3.0, "4 日のうち 2 日だけ水 = 3 日ぶん育つ")

	var ok := true
	for kind in w.garden.CROPS:
		var days: int = w.garden.CROPS[kind].grow_days
		if days < 3 or days > 7:
			ok = false
	_check(ok, "どの野菜も数日〜1 週間で育つ")

func _test_harvest_and_sell() -> void:
	print("収穫と市場")
	var w := _world()
	var g := w.garden
	_check(g.harvest_at(SPOT) == "none", "足元に野菜がなければ収穫できない")
	var c := _grown(w, "radish", 2, 2)
	_check(g.harvest_at(SPOT) == "growing" and g.crops.size() == 1, "育ちきるまで収穫できない")
	c.sown_day -= 1
	c.water_days = 3
	var money := w.market.money
	_check(g.harvest_at(SPOT) == "harvested" and g.produce.radish == 6 and g.last_harvest_kg == 6, "ラディッシュは 1 区画 6kg 採れる")
	_check(g.crops.is_empty() and w.land.plot_at(SPOT) != null, "収穫すると区画は空きに戻る(区画は残る)")
	_check(w.market.sell_all("radish") == 240 and w.market.money == money + 240 and g.produce.radish == 0, "6kg × 40₽ = 240₽ で売れる")
	_check(w.market.sell_all("radish") == 0, "売る野菜がなければ 0₽")
	# リンゴの売り買いは今までどおり
	w.forest.produce.apple = 2
	_check(w.market.sell_all("apple") == 30 and w.forest.produce.apple == 0, "リンゴも今までどおり売れる")

	# 種の値段より収穫の売り上げが高い(畑をやる意味がある)
	var ok := true
	for g2 in w.market.GOODS:
		if g2.form == "crop_seed":
			var income: int = int(g.CROPS[g2.species].yield_kg) * int(w.market.SELL_PRICES[g2.species])
			if income <= int(g2.price):
				ok = false
	_check(ok, "どの野菜も 1 区画の売り上げが種代を上回る")

func _test_spoiling() -> void:
	print("傷む")
	var w := _world()
	var g := w.garden
	# ラディッシュ: 毎日水をやって 3 日で収穫でき、そこから 3 日もつ
	var c := _grown(w, "radish", 3, 3)
	_check(g.is_ripe(c) and g.days_since_ripe(c) == 0.0 and g.days_until_spoiled(c) == 3, "収穫できるようになった日は、あと 3 日もつ")
	c.sown_day -= 3
	_check(g.days_since_ripe(c) == 3.0 and not g.is_spoiled(c) and g.days_until_spoiled(c) == 0, "3 日たってもまだ傷んでいない(ちょうど期限)")
	c.sown_day -= 1
	_check(g.is_spoiled(c), "4 日たつと傷む")
	_check(g.harvest_at(SPOT) == "harvested" and g.last_harvest_kg == 3 and g.last_harvest_spoiled and g.produce.radish == 3, "傷んだ野菜は半分だけ採れる(6kg → 3kg)")

	var w2 := _world()
	var c2 := _grown(w2, "radish", 3, 3)
	_check(w2.garden.harvest_at(SPOT) == "harvested" and w2.garden.last_harvest_kg == 6 and not w2.garden.last_harvest_spoiled, "傷む前なら満量")

	# 野菜ごとの持ち
	var expected := {"radish": 3, "cucumber": 3, "tomato": 4, "carrot": 7, "potato": 10, "garlic": 10}
	var ok := true
	for kind in expected:
		if int(w.garden.CROPS[kind].keep_days) != expected[kind]:
			ok = false
	_check(ok and expected.size() == w.garden.CROPS.size(), "どの野菜にも、傷むまでの日数がある")
	var w3 := _world()
	var c3 := _grown(w3, "garlic", 7, 7)
	c3.sown_day -= 10
	_check(not w3.garden.is_spoiled(c3), "ニンニクは 10 日もつ")
	c3.sown_day -= 1
	_check(w3.garden.is_spoiled(c3), "11 日で傷む")
	_check(w3.garden.harvest_at(SPOT) == "harvested" and w3.garden.last_harvest_kg == 3, "5kg の半分は切り上げて 3kg")

	# 雨で日数が狂わない: 収穫できる野菜には雨が入らない
	var w4 := _world()
	var c4 := _grown(w4, "radish", 3, 3)
	_check(w4.garden.water_all() == 0 and not w4.garden.watered_today(c4), "収穫できる野菜には雨の水を数えない")

	# 水やりなしで育った野菜も、同じ日数で傷む
	var w5 := _world()
	var c5 := _grown(w5, "radish", 6, 0)
	_check(w5.garden.is_ripe(c5) and w5.garden.days_since_ripe(c5) == 0.0, "水なしで 6 日: 収穫できるようになったところ")
	c5.sown_day -= 4
	_check(w5.garden.is_spoiled(c5), "そこから 4 日で傷む")

func _test_rain() -> void:
	print("雨")
	var w := _world()
	var g := w.garden
	var c := _grown(w, "radish", 0, 0)
	_check(g.water_all() == 1 and g.watered_today(c), "water_all で区画に水が入る")
	_check(g.water_all() == 0, "もう水が入っていれば何もしない")

	var w2 := _world()
	w2.forest.today_event = "rain"
	var c2 := _grown(w2, "radish", 0, 0)
	_check(w2.garden.watered_today(c2), "雨の日にあとからまいた区画も水やり済み")

	# 日付が変わって雨が降ると、畑にも降る
	var w3 := _world()
	var rain := RainForest.new()
	rain.season = "autumn"
	w3.forest = rain
	w3.garden.forest = rain
	var c3 := _grown(w3, "radish", 0, 0)
	rain.last_day = "2000-01-01"
	_check(w3.check_new_day() == "rain" and w3.garden.watered_today(c3), "日付が変わって雨が降ると、畑にも水が入る")

func _test_plot_guard_and_remove() -> void:
	print("区画の取り消しと抜く")
	var w := _world()
	var g := w.garden
	_grown(w, "radish", 0, 0)
	_check(g.toggle_plot(SPOT) == "has_crop" and w.land.plot_at(SPOT) != null, "野菜が育っている区画は取り消せない")
	_check(g.remove_at(SPOT) and g.crops.is_empty() and g.seeds.radish == 0, "抜くと野菜は消える(種は戻らない)")
	_check(not g.remove_at(SPOT), "もう抜くものがない")
	_check(g.toggle_plot(SPOT) == "removed" and w.land.plot_at(SPOT) == null, "空きの区画は取り消せる")
	_check(g.toggle_plot(Vector2(49.75, 0)) == "outside", "土地の外は今までどおり置けない")

func _test_new_plot_limit() -> void:
	print("新しく耕せる区画は 1 日 2 つまで")
	var w := _world()
	var g := w.garden
	var a := Vector2(1, 1)
	var b := Vector2(4, 1)
	var c := Vector2(7, 1)
	_check(g.plots_left_today() == 2, "はじめは今日あと 2 区画")
	_check(g.toggle_plot(a) == "placed" and g.plots_left_today() == 1, "1 つ目を耕せる")
	_check(g.toggle_plot(b) == "placed" and g.plots_left_today() == 0, "2 つ目を耕せる")
	_check(g.toggle_plot(c) == "limit" and w.land.plot_at(c) == null, "3 つ目は今日はもう耕せない")
	_check(g.toggle_plot(Vector2(49.75, 0)) == "limit", "上限のときは、場所を見る前に上限と知らせる")
	_check(g.toggle_plot(b) == "removed" and g.plots_left_today() == 1, "取り消すと今日の分が 1 つ戻る(置き間違いで損をしない)")
	_check(g.toggle_plot(c) == "placed" and g.plots_left_today() == 0, "戻った分で別の場所を耕せる")
	_check(g.toggle_plot(a) == "removed" and g.toggle_plot(a) == "placed" and w.land.plots.size() == 2, "取り消しと耕し直しでは区画は増えない")
	g.tilled_day = "2000-01-01"
	g.tilled_count = 2
	_check(g.plots_left_today() == 2, "日付が変わると、また 2 区画耕せる")
	_check(g.toggle_plot(b) == "placed" and g.tilled_day == w.forest.today() and g.tilled_count == 1, "新しい日の分として数える")
	var d := Vector2(10, 1)
	g.toggle_plot(d)
	w.save_game()
	var w2 := _world("autumn", false)
	w2.load_game()
	_check(w2.garden.plots_left_today() == 0 and w2.land.plots.size() == 4, "開き直しても今日の分は戻らない(セーブに入っている)")
	_check(w2.garden.toggle_plot(Vector2(13, 1)) == "limit", "開き直したあとも 3 つ目は耕せない")
	var old := _world()  # 保存先をテスト用にしておく(GameWorld.new() のままだと本物のセーブに向く)
	old.garden.from_save({"seeds": {}, "produce": {}, "crops": []})
	_check(old.garden.tilled_day == "" and old.garden.tilled_count == 0, "前のセーブは今日の分を使っていない状態で読む")

func _test_preview() -> void:
	print("先送りプレビュー")
	var w := _world()
	var g := w.garden
	var c := _grown(w, "radish", 0, 0)
	_check(g.growth_ratio(c) == 0.0, "まいた日の育ち具合は 0")
	w.forest.advance_years(1.0)
	_check(is_equal_approx(g.growth_ratio(c), 1.0 / 3.0) and not g.is_ripe(c), "+1 年(1 日ぶん)で見た目だけ育つ")
	w.forest.advance_years(10.0)
	_check(g.growth_ratio(c) == 1.0, "育ち具合の上限は 1")
	_check(g.harvest_at(SPOT) == "preview" and g.crops.size() == 1, "プレビュー中は収穫できない")

func _test_save() -> void:
	print("セーブ")
	var w := _world()
	var c := _grown(w, "radish", 2, 1)
	var sown: int = c.sown_day
	w.garden.seeds.garlic = 3
	w.garden.produce.carrot = 20
	w.garden.water_at(SPOT)
	w.save_game()
	var w2 := _world("autumn", false)
	w2.load_game()
	var g2 := w2.garden
	var c2: Dictionary = g2.crop_at(SPOT)
	_check(c2.kind == "radish" and c2.sown_day == sown and c2.water_days == 2, "まいた野菜・まいた日・水やりの回数が復元される")
	_check(g2.watered_today(c2), "今日水をあげたことが復元される")
	_check(g2.seeds.garlic == 3 and g2.produce.carrot == 20, "野菜の種と収穫物が復元される")

	var w_dirty := _world("autumn", false)
	w_dirty.load_game()
	w_dirty.land.toggle_plot(SPOT + Vector2(3, 0))
	w_dirty.garden.seeds.radish = 1
	w_dirty.garden.sow(SPOT + Vector2(3, 0), "radish")
	var w3 := _world("autumn", false)
	w3.load_game()
	_check(w3.garden.crops.size() == 2, "まいたら自動で保存される")

	# 手順 3-1 までのセーブ: 畑の記録がない
	_remove_save()
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"unit": "m", "seeds": {"birch": 1, "apple": 0, "cedar": 0}, "last_day": "", "today_event": "", "trees": [],
		"land": {"plots": [[1.5, 1.5]]}, "market": {"money": 123},
	}))
	file.close()
	var w4 := _world("autumn", false)
	w4.garden.seeds.radish = 9  # 読み込みで消えることを見る
	w4.load_game()
	_check(w4.garden.crops.is_empty() and w4.garden.seeds.radish == 0 and w4.garden.produce.radish == 0, "前のセーブは野菜なし・種 0 から")
	_check(w4.land.plots.size() == 1 and w4.market.money == 123, "前のセーブの区画と所持金はそのまま")
