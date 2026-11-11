extends SceneTree

# セーブのおかしな値と版の番号(2026-11-11。レビュー S3・S4)のテスト。本物のセーブには触れない。
# おかしな 1 件はその 1 件だけ飛ばし、ほかは読めることを確かめる。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_save_values.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる

const GameWorld = preload("res://logic/GameWorld.gd")
const SaveRead = preload("res://logic/SaveRead.gd")

const TEST_SAVE := "user://test_save_values.json"

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_clean()
	_test_read_helpers()
	_test_bad_items()
	_test_bad_numbers()
	_test_bad_shapes()
	_test_version()
	_clean()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)

func _clean() -> void:
	for n in DirAccess.get_files_at("user://"):
		if n.begins_with("test_save_values"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + n))

func _tree(x, y, species = "birch") -> Dictionary:
	return {"x": x, "y": y, "species": species, "form": "sapling", "planted_at": 1700000000, "start_age": 3.0}

# data を書いて、新しい世界で読む
func _load(data: Dictionary) -> GameWorld:
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.load_game()
	return w

func _base() -> Dictionary:
	return {"version": 1, "unit": "m", "last_day": "", "today_event": "",
		"trees": [_tree(1, 1), _tree(2, 2), _tree(3, 3)],
		"land": {"plots": [[1.5, 1.5], [4.5, 1.5]], "pond": [-20, 20]},
		"garden": {"seeds": {"radish": 2}, "crops": [{"x": 1.5, "y": 1.5, "kind": "radish", "sown_day": 20000}]},
		"market": {"money": 500}}

func _test_read_helpers() -> void:
	print("値を読む道具")
	_check(SaveRead.whole({"a": "12"}, "a") == 12 and SaveRead.whole({"a": 3.7}, "a") == 3, "数の文字や小数も整数で読む")
	_check(SaveRead.whole({"a": "abc"}, "a", 7) == 7 and SaveRead.whole({"a": null}, "a", 7) == 7 and SaveRead.whole({}, "a", 7) == 7, "読めなければ決まった値")
	_check(SaveRead.count({"a": -5}, "a") == 0, "数はマイナスにしない")
	_check(SaveRead.point({"x": 1, "y": "2"}) == Vector2(1, 2) and SaveRead.point({"x": 1}) == null, "位置は x と y がそろっているときだけ")
	_check(SaveRead.pair([1, 2]) == Vector2(1, 2) and SaveRead.pair([1]) == null and SaveRead.pair("1,2") == null, "[x, y] の位置")
	_check(SaveRead.ids(["a", "b", "a", 3, "z"], ["a", "b"]) == ["a", "b"], "id の並びは知っているものだけ・重ならない")
	_check(SaveRead.flag({"a": 1}, "a") and not SaveRead.flag({"a": "x"}, "a"), "真偽")

# レビュー S3 の 10 通りのうち、1 件だけおかしいもの
func _test_bad_items() -> void:
	print("おかしな 1 件だけ飛ばす")
	var d := _base()
	d.trees[1].erase("x")
	var w := _load(d)
	_check(w.forest.trees.size() == 2, "x のない木が 1 本あっても、ほかの 2 本は残る(前は 0 本になった)")
	d = _base()
	d.trees[0].species = "palm"
	d.trees[2].planted_at = "いつか"
	_check(_load(d).forest.trees.size() == 1, "知らない樹種・植えた時刻の読めない木だけ飛ばす")
	d = _base()
	d.land.plots.append("3,3")
	d.land.plots.append([7.5])
	_check(_load(d).land.plots.size() == 2, "おかしな区画だけ飛ばす")
	d = _base()
	d.garden.crops.append({"x": 4.5, "y": 1.5, "kind": "melon", "sown_day": 1})
	d.garden.crops.append({"x": 4.5, "kind": "radish", "sown_day": 1})
	d.garden.crops.append("radish")
	_check(_load(d).garden.crops.size() == 1, "おかしな野菜だけ飛ばす")
	d = _base()
	d["bees"] = {"hives": [{"x": 5, "y": 5}, {"y": 5}, 3]}
	d["feeders"] = {"feeders": [{"x": 9, "y": 9}, {"x": "a", "y": 9}]}
	d["nest_boxes"] = {"boxes": [{"x": 1, "y": 1, "days_done": 2}, {"days_done": 1}]}
	w = _load(d)
	_check(w.bees.hives.size() == 1 and w.feeders.feeders.size() == 1 and w.nest_boxes.boxes.size() == 1, "巣箱・餌台・ムクドリの巣箱も、おかしな 1 つだけ飛ばす")

func _test_bad_numbers() -> void:
	print("おかしな数")
	var d := _base()
	d.market.money = "たくさん"
	_check(_load(d).market.money == 0, "所持金が文字なら 0₽(はじめの所持金に増やさない)")
	d.market.money = -300
	_check(_load(d).market.money == 0, "所持金のマイナスは 0₽")
	d.market.money = "1200"
	_check(_load(d).market.money == 1200, "数の文字は読む")
	d = _base()
	d.market.erase("money")
	_check(_load(d).market.money == 11000, "所持金の記録がないセーブは、はじめの所持金(今までどおり)")
	d = _base()
	d["seeds"] = {"birch": -4, "apple": "x", "cedar": 2}
	d.garden.seeds = {"radish": -1, "carrot": 3}
	var w := _load(d)
	_check(w.forest.seeds.birch == 0 and w.forest.seeds.apple == 0 and w.forest.seeds.cedar == 2, "種の数のマイナスや文字は 0")
	_check(w.garden.seeds.radish == 0 and w.garden.seeds.carrot == 3, "野菜の種も")
	d = _base()
	d["kitchen"] = {"firewood": 999, "stock": {"jam": -2, "sauce": 4}, "pot": {"recipe": "jam", "start_day": "x"}}
	w = _load(d)
	_check(w.kitchen.firewood == w.kitchen.MAX_FIREWOOD and w.kitchen.stock.jam == 0 and w.kitchen.stock.sauce == 4, "薪は積める量まで・保存食のマイナスは 0")
	_check(w.kitchen.pots[0].recipe == "jam" and w.kitchen.pots[0].start_day == 0, "鍋の日付が読めなくても、鍋の中身は残る")
	d = _base()
	d["pond"] = {"days_dug": 99, "water": 250, "seen": ["frog", "dragon"]}
	w = _load(d)
	_check(w.pond.days_dug == 5 and w.pond.water == 100 and w.pond.seen == ["frog"], "池の日数と水は決まった範囲に・知らない生き物は読まない")
	d = _base()
	d["sound_level"] = "大"
	_check(_load(d).sound_level == 3, "音量が読めなければ大")

func _test_bad_shapes() -> void:
	print("形のおかしな記録")
	var d := _base()
	d.trees = "木がたくさん"
	d.land = [1, 2]
	d.garden.crops = {"a": 1}
	var w := _load(d)
	_check(w.forest.trees.is_empty() and w.land.plots.is_empty() and w.garden.crops.is_empty(), "並びでないものは空として読む(読み込みは止まらない)")
	_check(w.market.money == 500, "ほかの記録はふつうに読める")
	d = _base()
	d.unit = "px"
	d.trees = [_tree(40, 80), {"species": "birch", "planted_at": 1}]
	d.land.plots = [[60, 60], "x"]
	d.land.pond = "池"
	w = _load(d)
	_check(w.forest.trees.size() == 1 and w.forest.trees[0].pos == Vector2(1, 2), "px のセーブでも、おかしな木だけ飛ばして m に直す")
	_check(w.land.plots == [Vector2(1.5, 1.5)] and w.land.pond == null, "px のセーブの区画と池も")

func _test_version() -> void:
	print("セーブの版")
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.save_game()
	var saved = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	_check(int(saved.version) == GameWorld.SAVE_VERSION and GameWorld.SAVE_VERSION == 1, "保存すると版 1 を書く")
	var old := _base()
	old.erase("version")
	var w2 := _load(old)
	_check(w2.load_notice == "" and w2.forest.trees.size() == 3, "版のない今までのセーブは、そのまま読める")
	var newer := _base()
	newer.version = 5
	var w3 := _load(newer)
	_check(w3.load_notice.contains("新しい版") and w3.forest.trees.size() == 3, "新しい版のセーブは、読めるところだけ読んで知らせる")
	var kept := Array(DirAccess.get_files_at("user://")).filter(func(n): return n.begins_with("test_save_values.newer_"))
	_check(kept.size() == 1 and int(JSON.parse_string(FileAccess.get_file_as_string("user://" + kept[0])).version) == 5, "上書きする前に、元のセーブを別名で残す")
