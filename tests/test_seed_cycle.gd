extends SceneTree

# 種の循環(Phase 2-1)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v3.6.2-stable_win64.exe --path . -s res://tests/test_seed_cycle.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる

const TEST_SAVE := "user://test_seed_cycle.json"
const DAY := 86400

var _failed := 0
var _passed := 0

func _init() -> void:
	_test_initial_seeds_and_planting()
	_test_harvest_rules()
	_test_preview_is_not_saved()
	_test_old_save_format()
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

func _new_trees() -> Node2D:
	_remove_save()
	var t: Node2D = load("res://Trees.gd").new()
	t.save_path = TEST_SAVE
	t.season = "autumn"
	return t

func _remove_save() -> void:
	var d := Directory.new()
	if d.file_exists(TEST_SAVE):
		d.remove(TEST_SAVE)

# リンゴを1本植えて、樹齢を days 年ぶん(= days 日前に植えた扱い)にする
func _plant_apple_aged(t: Node2D, pos: Vector2, days: int) -> Dictionary:
	t.seeds["apple"] += 1
	t.add_tree(pos, "apple")
	var tree: Dictionary = t.trees[-1]
	tree.planted_at = OS.get_unix_time() - days * DAY
	return tree

func _test_initial_seeds_and_planting() -> void:
	print("初期の種と植樹")
	var t := _new_trees()
	_check(t.seeds.birch == 3 and t.seeds.apple == 1 and t.seeds.cedar == 0, "初期は 白樺3・リンゴ1・シベリア杉0")
	_check(t.add_tree(Vector2(0, 0), "birch"), "白樺を植えられる")
	_check(t.seeds.birch == 2, "植えると白樺の種が1減る")
	t.add_tree(Vector2(100, 0), "birch")
	t.add_tree(Vector2(200, 0), "birch")
	_check(not t.add_tree(Vector2(300, 0), "birch"), "白樺の種が0なら植えられない")
	_check(t.trees.size() == 3, "植えられなかった木は増えない")
	_check(not t.add_tree(Vector2(400, 0), "cedar"), "シベリア杉は種0なので植えられない")
	t.free()

func _test_harvest_rules() -> void:
	print("収穫")
	var t := _new_trees()
	_check(t.harvest_nearest(Vector2(0, 0), 80.0) == "none", "近くにリンゴがなければ none")

	t.add_tree(Vector2(0, 0), "apple")  # 植えたばかり
	_check(t.harvest_nearest(Vector2(0, 0), 80.0) == "young", "樹齢5年未満は young")

	var ripe := _plant_apple_aged(t, Vector2(1000, 0), 6)
	t.season = "summer"
	_check(t.harvest_nearest(Vector2(1000, 0), 80.0) == "not_season", "秋以外は not_season")

	t.season = "autumn"
	var before: int = t.seeds.apple
	_check(t.harvest_nearest(Vector2(1000, 0), 80.0) == "harvested", "樹齢6年・秋なら収穫できる")
	_check(t.seeds.apple == before + t.SEEDS_PER_HARVEST, "収穫でリンゴの種が %d 増える" % t.SEEDS_PER_HARVEST)
	_check(t.harvest_nearest(Vector2(1000, 0), 80.0) == "done", "同じ木は同じ日に2回収穫できない")

	# 前日に収穫した記録なら、今日はまた採れる(1日1回)
	ripe.last_harvest = "2000-01-01"
	_check(t.harvest_nearest(Vector2(1000, 0), 80.0) == "harvested", "日が変われば同じ木からまた収穫できる")

	# 遠い木は対象外。白樺は収穫対象にならない
	t.seeds["birch"] = 1
	t.add_tree(Vector2(5000, 0), "birch")
	_check(t.harvest_nearest(Vector2(5000, 0), 80.0) == "none", "白樺は収穫の対象にならない")
	t.free()

func _test_preview_is_not_saved() -> void:
	print("時間先送りプレビュー")
	var t := _new_trees()
	t.add_tree(Vector2(0, 0), "apple")  # 植えたばかりのリンゴ
	t.advance_years(10.0)
	_check(t.age_years(t.trees[0]) >= 10.0, "プレビュー中は見た目の樹齢が10年以上")
	_check(t.real_age_years(t.trees[0]) < 1.0, "判定用の樹齢は現実のまま")
	_check(t.harvest_nearest(Vector2(0, 0), 80.0) == "preview", "プレビュー中は収穫できない")

	t.reset_preview()
	_check(t.time_offset_years == 0.0, "R(reset_preview)で先送りが 0 に戻る")
	_check(t.age_years(t.trees[0]) < 1.0, "戻すと見た目の樹齢も現実に戻る")
	_check(t.harvest_nearest(Vector2(0, 0), 80.0) == "young", "戻した後はプレビューの制限が外れる")
	t.advance_years(10.0)

	t.save_game()
	var f := File.new()
	f.open(TEST_SAVE, File.READ)
	var data = parse_json(f.get_as_text())
	f.close()
	_check(not data.has("time_offset_years"), "セーブに先送りの年数を書かない")

	var t2 := _new_trees_keep_save()
	t2.load_game()
	_check(t2.time_offset_years == 0.0, "読み込み後の先送りは 0")
	_check(t2.trees.size() == 1 and t2.seeds.apple == 0, "木と種の所持数は保存・復元される")
	t.free()
	t2.free()

func _new_trees_keep_save() -> Node2D:
	var t: Node2D = load("res://Trees.gd").new()
	t.save_path = TEST_SAVE
	t.season = "autumn"
	return t

func _test_old_save_format() -> void:
	print("旧形式のセーブ")
	_remove_save()
	var f := File.new()
	f.open(TEST_SAVE, File.WRITE)
	f.store_string(to_json({
		"time_offset_years": 483,
		"trees": [{"x": 10, "y": 20, "species": "apple", "planted_at": OS.get_unix_time() - 7 * DAY}],
	}))
	f.close()
	var t := _new_trees_keep_save()
	t.load_game()
	_check(t.time_offset_years == 0.0, "旧セーブの +483年 は読まない")
	_check(t.seeds.birch == 3 and t.seeds.apple == 1 and t.seeds.cedar == 0, "種の記録がない旧セーブは初期の種から")
	_check(t.trees.size() == 1 and t.trees[0].last_harvest == "", "旧セーブの木は残り、収穫記録は空")
	_check(t.harvest_nearest(Vector2(10, 20), 80.0) == "harvested", "旧セーブの樹齢7年のリンゴも収穫できる")
	t.free()
