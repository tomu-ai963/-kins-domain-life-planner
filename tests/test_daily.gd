extends SceneTree

# 毎日の理由(Phase 2-2: 水やり・日替わりの発見)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v3.6.2-stable_win64.exe --no-window --path . -s res://tests/test_daily.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる

const TEST_SAVE := "user://test_daily.json"

var _failed := 0
var _passed := 0

func _init() -> void:
	_test_watering()
	_test_daily_event_once_per_day()
	_test_daily_event_is_fixed_by_date()
	_test_event_effects()
	_test_save_and_old_format()
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
	var d := Directory.new()
	if d.file_exists(TEST_SAVE):
		d.remove(TEST_SAVE)

func _new_trees(remove_save := true) -> Node2D:
	if remove_save:
		_remove_save()
	var t: Node2D = load("res://Trees.gd").new()
	t.save_path = TEST_SAVE
	t.season = "autumn"
	return t

func _test_watering() -> void:
	print("水やり")
	var t := _new_trees()
	_check(t.water_nearest(Vector2(0, 0), 80.0) == "none", "近くに木がなければ none")
	t.add_tree(Vector2(0, 0), "birch")
	var before: float = t.real_age_years(t.trees[0])
	_check(t.water_nearest(Vector2(10, 0), 80.0) == "watered", "足元の木に水をあげられる")
	_check(abs(t.real_age_years(t.trees[0]) - before - t.WATER_BONUS_YEARS) < 0.01, "判定用の樹齢が +%.1f年" % t.WATER_BONUS_YEARS)
	_check(t.water_nearest(Vector2(10, 0), 80.0) == "done", "同じ木は同じ日に2回あげられない")
	t.trees[0].last_watered = "2000-01-01"
	_check(t.water_nearest(Vector2(10, 0), 80.0) == "watered", "日が変われば同じ木にまたあげられる")
	_check(abs(t.trees[0].bonus_years - 2 * t.WATER_BONUS_YEARS) < 0.001, "ボーナスは日ごとに積み上がる")

	# 水やりで樹齢5年に届いたリンゴは、その場で収穫できる(ボーナスは判定にも効く)
	t.seeds["apple"] = 1
	t.add_tree(Vector2(1000, 0), "apple")
	var apple: Dictionary = t.trees[-1]
	apple.planted_at = OS.get_unix_time() - int(4.7 * 86400)
	_check(t.harvest_nearest(Vector2(1000, 0), 80.0) == "young", "樹齢4.7年のリンゴはまだ実らない")
	t.water_nearest(Vector2(1000, 0), 80.0)
	_check(t.harvest_nearest(Vector2(1000, 0), 80.0) == "harvested", "水やりで5.2年になれば収穫できる")
	t.free()

func _test_daily_event_once_per_day() -> void:
	print("日替わりの発見(1日1回)")
	var t := _new_trees()
	var first: String = t.check_new_day()
	_check(first != "", "その日はじめての確認で発見が起きる")
	_check(t.today_event == first and t.last_day != "", "今日の発見と日付を覚える")
	_check(t.check_new_day() == "", "同じ日の2回目は何も起きない")
	t.last_day = "2000-01-01"
	_check(t.check_new_day() != "", "日付が変われば、また起きる(開かなかった日の分はたまらず1回)")
	t.free()

func _test_daily_event_is_fixed_by_date() -> void:
	print("発見は日付で決まる")
	var t := _new_trees()
	var same := true
	for i in range(5):
		if t.roll_daily_event("2026-10-29") != t.roll_daily_event("2026-10-29"):
			same = false
	_check(same, "同じ日付なら何度引いても同じ")

	# 1年分(365日)の出方。重みは 白樺35 / 杉15 / 雨25 / 鳥25
	var counts := {"birch_seed": 0, "cedar_seed": 0, "rain": 0, "birds": 0}
	for d in range(365):
		var dt := OS.get_datetime_from_unix_time(1767225600 + d * 86400)  # 2026-01-01 から
		var date := "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]
		counts[t.roll_daily_event(date)] += 1
	print("    365日の内訳: ", counts)
	_check(counts.birch_seed > 0 and counts.cedar_seed > 0 and counts.rain > 0 and counts.birds > 0, "4種類とも起きる")
	_check(counts.cedar_seed >= 25 and counts.cedar_seed <= 85, "シベリア杉は1年に25〜85回(重み15%%の目安55回)")
	t.free()

func _test_event_effects() -> void:
	print("発見の効果")
	var t := _new_trees()
	t._apply_event("birch_seed")
	_check(t.seeds.birch == 4, "白樺の種が落ちていた → 白樺 +1")
	t._apply_event("cedar_seed")
	_check(t.seeds.cedar == 1, "リスが実を置いていった → シベリア杉 +1")
	_check(t.add_tree(Vector2(0, 0), "cedar"), "手に入れたシベリア杉の種で植えられる")

	t.add_tree(Vector2(500, 0), "birch")
	t.water_nearest(Vector2(500, 0), 80.0)  # 1本は先に水やり済み
	var bonus_watered: float = t.trees[1].bonus_years
	t._apply_event("rain")
	_check(t.trees[0].last_watered == t._today(), "雨 → まだの木も水やり済みになる")
	_check(t.trees[1].bonus_years == bonus_watered, "雨 → 先にあげた木のボーナスは重ならない")

	# 雨の日は一日中降っている扱い。発見のあとで植えた木も水やり済み
	t.last_day = t._today()
	t.today_event = "rain"
	t.seeds["birch"] += 1
	t.add_tree(Vector2(900, 0), "birch")
	_check(t.trees[-1].last_watered == t._today(), "雨の日はあとから植えた木も水やり済み")
	t.today_event = "birds"
	t.seeds["birch"] += 1
	t.add_tree(Vector2(1200, 0), "birch")
	_check(t.trees[-1].last_watered == "", "雨でない日に植えた木は水やり前")

	var seeds_before: Dictionary = t.seeds.duplicate()
	t._apply_event("birds")
	_check(t.seeds.hash() == seeds_before.hash(), "渡り鳥 → 種は変わらない")
	t.free()

func _test_save_and_old_format() -> void:
	print("セーブ")
	var t := _new_trees()
	t.add_tree(Vector2(0, 0), "birch")
	t.water_nearest(Vector2(0, 0), 80.0)
	var ev: String = t.check_new_day()
	var t2 := _new_trees(false)
	t2.load_game()
	_check(t2.last_day == t.last_day and t2.today_event == ev, "発見の日付と内容が保存・復元される")
	_check(t2.trees[0].last_watered == t._today() and t2.trees[0].bonus_years >= t.WATER_BONUS_YEARS, "水やりの記録とボーナスが保存・復元される")
	_check(t2.check_new_day() == "", "開き直しても同じ日はもう起きない")
	t.free()
	t2.free()

	# 2-1 時点のセーブ(水やり・発見の記録なし)
	_remove_save()
	var f := File.new()
	f.open(TEST_SAVE, File.WRITE)
	f.store_string(to_json({
		"seeds": {"birch": 2, "apple": 1, "cedar": 0},
		"trees": [{"x": 0, "y": 0, "species": "birch", "planted_at": OS.get_unix_time() - 86400, "last_harvest": ""}],
	}))
	f.close()
	var t3 := _new_trees(false)
	t3.load_game()
	_check(t3.trees[0].bonus_years == 0.0 and t3.trees[0].last_watered == "", "旧セーブの木はボーナス0・水やり記録なし")
	_check(t3.check_new_day() != "", "旧セーブでも今日の発見が起きる")
	t3.free()
