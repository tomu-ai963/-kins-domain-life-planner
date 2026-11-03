extends SceneTree

# 種の循環(Phase 2-1)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_seed_cycle.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Forest = preload("res://logic/Forest.gd")

const TEST_SAVE := "user://test_seed_cycle.json"
const DAY := 86400
const REACH := 2.0  # 足元 2m

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_initial_seeds_and_planting()
	_test_harvest_rules()
	_test_preview_is_not_saved()
	_test_old_save_format()
	_test_px_save_is_converted_once()
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

# ロジック一式(GameWorld)を作る。木と種は w.forest
func _new_world() -> GameWorld:
	_remove_save()
	return _new_world_keep_save()

func _new_world_keep_save() -> GameWorld:
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.forest.season = "autumn"
	w.forest.germination_rates = {"birch": 1.0, "apple": 1.0, "cedar": 1.0}  # 種は必ず芽が出る(発芽は test_market で見る)
	return w

func _remove_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func _write_save(data: Dictionary) -> void:
	_remove_save()
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

func _now() -> int:
	return int(Time.get_unix_time_from_system())

# リンゴを1本植えて、樹齢を days 年ぶん(= days 日前に植えた扱い)にする
func _plant_apple_aged(t: Forest, pos: Vector2, days: int) -> Dictionary:
	t.seeds["apple"] += 1
	t.add_tree(pos, "apple")
	var tree: Dictionary = t.trees[-1]
	tree.planted_at = _now() - days * DAY
	return tree

func _test_initial_seeds_and_planting() -> void:
	print("初期の種と植樹")
	var w := _new_world()
	var t := w.forest
	_check(t.seeds.birch == 3 and t.seeds.apple == 1 and t.seeds.cedar == 0, "初期は 白樺3・リンゴ1・シベリア杉0")
	_check(t.add_tree(Vector2(0, 0), "birch"), "白樺を植えられる")
	_check(t.seeds.birch == 2, "植えると白樺の種が1減る")
	t.add_tree(Vector2(2.5, 0), "birch")
	t.add_tree(Vector2(5, 0), "birch")
	_check(not t.add_tree(Vector2(7.5, 0), "birch"), "白樺の種が0なら植えられない")
	_check(t.trees.size() == 3, "植えられなかった木は増えない")
	_check(not t.add_tree(Vector2(10, 0), "cedar"), "シベリア杉は種0なので植えられない")

func _test_harvest_rules() -> void:
	print("収穫")
	var w := _new_world()
	var t := w.forest
	_check(t.harvest_nearest(Vector2(0, 0), REACH) == "none", "近くにリンゴがなければ none")

	t.add_tree(Vector2(0, 0), "apple")  # 植えたばかり
	_check(t.harvest_nearest(Vector2(0, 0), REACH) == "young", "樹齢5年未満は young")

	var ripe := _plant_apple_aged(t, Vector2(25, 0), 6)
	t.season = "summer"
	_check(t.harvest_nearest(Vector2(25, 0), REACH) == "not_season", "秋以外は not_season")

	t.season = "autumn"
	var seeds_before: int = t.seeds.apple
	_check(t.harvest_nearest(Vector2(25, 0), REACH) == "harvested", "樹齢6年・秋なら収穫できる")
	_check(t.produce.apple == 5 and t.last_harvest_count == 5, "樹齢6年のリンゴは 5 個採れる")
	_check(t.seeds.apple == seeds_before, "収穫しても種は増えない(種は市場で買う)")
	_check(t.harvest_nearest(Vector2(25, 0), REACH) == "done", "同じ木は同じ日に2回収穫できない")

	# 前日に収穫した記録なら、今日はまた採れる(1日1回)
	ripe.last_harvest = "2000-01-01"
	_check(t.harvest_nearest(Vector2(25, 0), REACH) == "harvested", "日が変われば同じ木からまた収穫できる")
	_check(t.produce.apple == 10, "収穫したリンゴはたまっていく")

	# 遠い木は対象外。白樺は収穫対象にならない
	t.seeds["birch"] = 1
	t.add_tree(Vector2(125, 0), "birch")
	_check(t.harvest_nearest(Vector2(125, 0), REACH) == "none", "白樺は収穫の対象にならない")

func _test_preview_is_not_saved() -> void:
	print("時間先送りプレビュー")
	var w := _new_world()
	var t := w.forest
	t.add_tree(Vector2(0, 0), "apple")  # 植えたばかりのリンゴ
	t.advance_years(10.0)
	_check(t.age_years(t.trees[0]) >= 10.0, "プレビュー中は見た目の樹齢が10年以上")
	_check(t.real_age_years(t.trees[0]) < 1.0, "判定用の樹齢は現実のまま")
	_check(t.harvest_nearest(Vector2(0, 0), REACH) == "preview", "プレビュー中は収穫できない")

	t.reset_preview()
	_check(t.time_offset_years == 0.0, "R(reset_preview)で先送りが 0 に戻る")
	_check(t.age_years(t.trees[0]) < 1.0, "戻すと見た目の樹齢も現実に戻る")
	_check(t.harvest_nearest(Vector2(0, 0), REACH) == "young", "戻した後はプレビューの制限が外れる")
	t.advance_years(10.0)

	w.save_game()
	var f := FileAccess.open(TEST_SAVE, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	_check(not data.has("time_offset_years"), "セーブに先送りの年数を書かない")

	var w2 := _new_world_keep_save()
	w2.load_game()
	var t2 := w2.forest
	_check(t2.time_offset_years == 0.0, "読み込み後の先送りは 0")
	_check(t2.trees.size() == 1 and t2.seeds.apple == 0, "木と種の所持数は保存・復元される")

func _test_old_save_format() -> void:
	print("旧形式のセーブ")
	# Phase 1 のセーブ: 種の記録なし・先送りの年数あり・座標は px
	_write_save({
		"time_offset_years": 483,
		"trees": [{"x": 10, "y": 20, "species": "apple", "planted_at": _now() - 7 * DAY}],
	})
	var w := _new_world_keep_save()
	w.load_game()
	var t := w.forest
	_check(t.time_offset_years == 0.0, "旧セーブの +483年 は読まない")
	_check(t.seeds.birch == 3 and t.seeds.apple == 1 and t.seeds.cedar == 0, "種の記録がない旧セーブは初期の種から")
	_check(t.trees.size() == 1 and t.trees[0].last_harvest == "", "旧セーブの木は残り、収穫記録は空")
	_check(t.trees[0].pos == Vector2(0.25, 0.5), "旧セーブの座標(px)は m に直す(10px,20px → 0.25m,0.5m)")
	_check(t.harvest_nearest(Vector2(0.25, 0.5), REACH) == "harvested", "旧セーブの樹齢7年のリンゴも収穫できる")

func _test_px_save_is_converted_once() -> void:
	print("座標の単位(px → m)")
	# Godot 3 版の最後の形式(2-3): 単位の印なし = px
	_write_save({
		"seeds": {"birch": 1, "apple": 0, "cedar": 0}, "last_day": "", "today_event": "",
		"trees": [{"x": 2000, "y": -1840, "species": "birch", "planted_at": _now(), "last_harvest": "",
				"last_watered": "", "bonus_years": 0.0}],
	})
	var w := _new_world_keep_save()
	w.load_game()
	_check(w.forest.trees[0].pos == Vector2(50, -46), "px のセーブは 40 で割って読む(2000px → 50m)")
	w.save_game()
	var f := FileAccess.open(TEST_SAVE, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	_check(data.get("unit", "") == "m", "保存し直すと単位の印 m が付く")
	var w2 := _new_world_keep_save()
	w2.load_game()
	_check(w2.forest.trees[0].pos == Vector2(50, -46), "m のセーブはそのまま読む(二重に割らない)")
