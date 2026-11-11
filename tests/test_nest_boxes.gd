extends SceneTree

# ムクドリの巣箱(2026-11-11)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_nest_boxes.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Forest = preload("res://logic/Forest.gd")

const TEST_SAVE := "user://test_nest_boxes.json"
const BIG := Vector2(10, 10)    # 育った白樺
const SMALL := Vector2(20, 10)  # 若い白樺

var _failed := 0
var _passed := 0

# 今日の日付を決めた Forest(1 日 1 回の作業を進めるため)
class DateForest extends Forest:
	var date := "2026-12-10"
	func today() -> String:
		return date

func _initialize() -> void:
	_test_build()
	_test_limits()
	_test_starlings()
	_test_felled()
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

func _world() -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	var f := DateForest.new()
	f.season = "winter"
	f.last_day = f.today()
	f.today_event = "birds"
	w.forest = f
	w.nest_boxes.forest = f
	w.wildlife.forest = f
	_tree(w, BIG, 20.0)
	_tree(w, SMALL, 1.0)
	w.cabin.materials.log = 5
	return w

func _tree(w: GameWorld, pos: Vector2, age: float) -> void:
	w.forest.trees.append({"pos": pos, "species": "birch", "form": "sapling", "planted_at": w.forest._now(), "start_age": age, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0, "pruned_year": 0})

func _next_day(w: GameWorld) -> void:
	var f: DateForest = w.forest
	f.date = Forest.date_of_day(f.day_number() + 1)

func _test_build() -> void:
	print("作る")
	var w := _world()
	var nb := w.nest_boxes
	_check(nb.can_hold(w.forest.trees[0]) and not nb.can_hold(w.forest.trees[1]), "育った木には掛けられる・若い木(樹冠 %.2fm)には掛けられない" % w.forest.radius_of(w.forest.trees[1]))
	_check(nb.act(Vector2(40, 40)) == "no_tree" and nb.act(SMALL + Vector2(0.5, 0)) == "no_tree", "木のそばでないと作れない")
	_check(nb.is_near(BIG + Vector2(1.0, 0)) and not nb.is_near(BIG + Vector2(2.0, 0)), "幹から 1.6m まで")
	_check(nb.act(BIG + Vector2(1, 0)) == "started" and w.cabin.materials.log == 4, "1 日目: 丸太 1 本で作りはじめる")
	_check(nb.boxes.size() == 1 and nb.boxes[0].pos == BIG and nb.boxes[0].days_done == 1, "巣箱はその木の位置で覚える")
	_check(nb.act(BIG) == "done_today" and nb.boxes[0].days_done == 1 and w.cabin.materials.log == 4, "1 日 1 回")
	_next_day(w)
	_check(nb.act(BIG) == "worked" and nb.boxes[0].days_done == 2 and w.cabin.materials.log == 4, "2 日目: 丸太は使わない")
	_check(nb.done_count() == 0, "まだ掛けていない")
	_next_day(w)
	_check(nb.act(BIG) == "finished" and nb.is_done(nb.boxes[0]) and nb.done_count() == 1, "3 日目で掛け終える")
	_next_day(w)
	_check(nb.act(BIG) == "done" and nb.boxes[0].days_done == 3, "掛け終えたら、それ以上は作らない")
	_check(FileAccess.file_exists(TEST_SAVE), "作業すると保存する")

func _test_limits() -> void:
	print("上限と丸太")
	var w := _world()
	var nb := w.nest_boxes
	w.cabin.materials.log = 0
	_check(nb.act(BIG) == "no_wood" and nb.boxes.is_empty(), "丸太がなければ作れない")
	w.cabin.materials.log = 10
	for i in range(3):
		_tree(w, Vector2(30 + i * 5, 30), 20.0)
		_check(nb.act(Vector2(30 + i * 5, 30)) == "started", "%d つ目を作りはじめる" % (i + 1))
	_check(nb.act(BIG) == "too_many" and nb.boxes.size() == 3 and w.cabin.materials.log == 7, "3 つまで")
	_check(nb.act(Vector2(30, 30)) == "done_today", "上限でも、作りかけの巣箱では断らない(今日はもう作った)")

func _test_starlings() -> void:
	print("ムクドリ")
	var w := _world()
	var nb := w.nest_boxes
	for i in range(3):
		nb.act(BIG)
		_next_day(w)
	_check(nb.done_count() == 1, "掛けた")
	_check(nb.starlings() == 0, "冬は来ない")
	w.forest.season = "spring"
	_check(nb.starlings() == 2, "春は、つがい 2 羽")
	w.forest.season = "summer"
	_check(nb.starlings() == 2, "夏もいる")
	w.forest.season = "autumn"
	_check(nb.starlings() == 0, "秋には南へ渡っていく")
	w.forest.season = "spring"
	_check(w.wildlife._wanted("starling") == 2, "生き物として数える(巣箱 1 つにつがい 1 組)")
	var rng := RandomNumberGenerator.new()
	_check(w.wildlife.home_for("starling", rng, Vector2(-30, -30)) == BIG, "住みかは巣箱の木")
	nb.boxes.append({"pos": SMALL, "days_done": 1, "last_worked": ""})
	_check(nb.starlings() == 2, "作りかけの巣箱には来ない")

func _test_felled() -> void:
	print("木を伐る")
	var w := _world()
	var nb := w.nest_boxes
	nb.act(BIG)
	_check(not nb.drop_missing() and nb.boxes.size() == 1, "木があれば巣箱は残る")
	w.forest.trees.remove_at(0)
	_check(nb.drop_missing() and nb.boxes.is_empty(), "木を伐ると巣箱もなくなる")

func _test_save() -> void:
	print("セーブ")
	var w := _world()
	var nb := w.nest_boxes
	nb.act(BIG)
	_next_day(w)
	nb.act(BIG)
	w.save_game()
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	var b: Dictionary = w2.nest_boxes.box_on(BIG)
	_check(not b.is_empty() and b.days_done == 2 and b.last_worked == w.forest.today(), "作った日数と日付が戻る")
	_check(w2.nest_boxes.box_on(w2.forest.trees[0].pos) == b, "読み直した木の位置で見つかる")
	var w3 := GameWorld.new()
	w3.nest_boxes.from_save({})
	_check(w3.nest_boxes.boxes.is_empty(), "記録がないセーブは巣箱なし")
	w3.nest_boxes.from_save({"boxes": [{"x": 1, "y": 2, "days_done": 9}, {"y": 1}, "x"]})
	_check(w3.nest_boxes.boxes.size() == 1 and w3.nest_boxes.boxes[0].days_done == 3, "おかしな記録は読まない・日数は 3 まで")
