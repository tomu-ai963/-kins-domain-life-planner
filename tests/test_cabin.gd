extends SceneTree

# 小屋(手順 3-3)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_cabin.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Cabin = preload("res://logic/Cabin.gd")

const TEST_SAVE := "user://test_cabin.json"
const DAY := 86400
const SITE := Vector2(20, 20)
const OUTSIDE := Vector2(20, 22.5)  # 小屋(南北 3m)の南、1m 離れたところ

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_place()
	_test_work()
	_test_wood()
	_test_blocks()
	_test_cancel()
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

func _world(remove_save := true) -> GameWorld:
	if remove_save:
		_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.forest.season = "autumn"
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birds"
	return w

# 次の日になった扱いにする
func _next_day(c: Cabin) -> void:
	c.last_worked = ""

func _test_place() -> void:
	print("場所を決める")
	var w := _world()
	var c := w.cabin
	_check(c.work(OUTSIDE) == "none", "場所を決める前は作業できない")
	_check(c.place(Vector2(47, 20)) == "edge", "境界の近く(生垣の帯)には建てられない")
	_check(c.place(Vector2(20, -46.5)) == "edge", "北の境界の近くにも建てられない")
	_check(c.place(Vector2(0, 0)) == "center" and c.place(Vector2(5, 0)) == "center", "中心の近くには建てられない(家族の杉・プレイヤーが出てくる場所)")
	w.land.toggle_pond(Vector2(-20, 20))
	_check(c.place(Vector2(-20, 24)) == "pond", "池にかかる場所には建てられない")
	w.land.toggle_plot(Vector2(-20, -20))
	_check(c.place(Vector2(-20, -20)) == "plot", "菜園の区画にかかる場所には建てられない")
	w.forest.seeds.birch = 1
	w.forest.add_tree(Vector2(20, 21), "birch")
	_check(c.place(SITE) == "tree" and c.site == null, "木がある場所には建てられない")
	w.forest.remove_nearest(Vector2(20, 21), 2.0)
	_check(c.place(SITE + Vector2(0.3, -0.3)) == "placed" and c.site == SITE, "足元を中心に、1m 単位にそろえて決まる")
	_check(c.place(Vector2(-20, 5)) == "exists" and c.site == SITE, "小屋はひとつまで")
	_check(c.rect() == Rect2(18, 18.5, 4, 3), "東西 4m × 南北 3m = 12m²")

func _test_work() -> void:
	print("基礎 → 壁 → 屋根")
	_check(Cabin.total_logs() == 29 and Cabin.total_days() == 7, "ぜんぶで丸太 29 本・7 日")
	var w := _world()
	var c := w.cabin
	c.place(SITE)
	_check(c.work(Vector2(20, 30)) == "far", "離れていると作業できない")
	_check(c.work(SITE) == "inside" and c.work(Vector2(20, 21.8)) == "inside", "建てる場所の中では作業できない(閉じ込められないように)")
	_check(c.work(OUTSIDE) == "no_wood", "丸太がなければ作業できない")
	c.materials.log = 29
	_check(c.work(OUTSIDE) == "worked" and c.materials.log == 26 and c.days_done == 1, "基礎 1 日目: 丸太 3 本")
	_check(c.work(OUTSIDE) == "done_today" and c.materials.log == 26 and c.days_done == 1, "作業は 1 日 1 回(丸太は減らない)")
	_next_day(c)
	_check(c.work(OUTSIDE) == "stage_done" and c.stage == 1 and c.days_done == 0, "基礎 2 日目: 基礎ができて壁に進む")
	_check(not c.has_walls(), "まだ壁は建っていない(当たり判定なし)")
	_next_day(c)
	_check(c.work(OUTSIDE) == "worked" and c.materials.log == 18, "壁 1 日目: 丸太 5 本")
	_next_day(c)
	c.work(OUTSIDE)
	_next_day(c)
	_check(c.work(OUTSIDE) == "stage_done" and c.stage == 2 and c.has_walls(), "壁 3 日目: 壁ができて屋根に進む")
	_next_day(c)
	var keep: int = c.materials.log
	c.materials.log = 3
	_check(c.work(OUTSIDE) == "no_wood" and c.days_done == 0 and not c.worked_today(), "丸太が足りない日は作業が進まない")
	c.materials.log = keep
	_check(c.work(OUTSIDE) == "worked" and c.worked_today(), "屋根 1 日目: 丸太 4 本")
	_next_day(c)
	_check(c.work(OUTSIDE) == "finished" and c.is_complete() and c.materials.log == 0, "屋根 2 日目: 完成(丸太はちょうど使い切る)")
	_next_day(c)
	_check(c.work(OUTSIDE) == "complete" and c.current_stage().is_empty(), "完成したらもう作業はない")
	_check(c.is_inside(SITE) and not c.is_inside(OUTSIDE), "完成した小屋の中にいるかが分かる")
	_check(c.door_pos() == SITE + Vector2(0, 1.5), "ドアは南の壁の真ん中")
	c.stage = 2
	_check(not c.is_inside(SITE), "完成するまでは中に入れない")
	c.stage = 3

func _test_wood() -> void:
	print("木を伐って丸太にする")
	var w := _world()
	var f := w.forest
	var c := w.cabin
	f.germination_rates.birch = 0.0
	f.seeds.birch = 1
	f.add_tree(Vector2(0, 0), "birch")
	_check(f.wood_yield(f.trees[-1]) == 0, "芽が出ていない種は丸太にならない")
	f.trees.clear()
	var cases := [
		["birch", 14.0, 0, "白樺 14 年: まだ細い"],
		["birch", 15.0, 1, "白樺 15 年: 1 本"],
		["birch", 20.0, 2, "白樺 20 年: 2 本"],
		["birch", 60.0, 6, "白樺は 6 本まで"],
		["apple", 19.0, 0, "リンゴ 19 年: まだ"],
		["apple", 30.0, 2, "リンゴ 30 年: 2 本(太くならない)"],
		["cedar", 30.0, 0, "シベリア杉 30 年: まだ(育つのが遅い)"],
		["cedar", 50.0, 2, "シベリア杉 50 年: 2 本"],
	]
	for e in cases:
		f.saplings[e[0]] = 1
		f.add_tree(Vector2(0, 0), e[0], "sapling")
		f.trees[-1].start_age = e[1]
		_check(f.wood_yield(f.trees[-1]) == e[2], e[3])
		f.trees.clear()

	_check(c.fell(Vector2(0, 0), 2.0) == -1, "近くに木がなければ -1")
	f.saplings.birch = 2
	f.add_tree(Vector2(0, 0), "birch", "sapling")
	f.trees[-1].start_age = 20.0
	_check(c.fell(Vector2(0.5, 0), 2.0) == 2 and c.materials.log == 2 and f.trees.is_empty(), "育った白樺を伐ると丸太 2 本になり、木は消える")
	f.add_tree(Vector2(0, 0), "birch", "sapling")
	_check(c.fell(Vector2(0.5, 0), 2.0) == 0 and c.materials.log == 2 and f.trees.is_empty(), "若木は抜けるが丸太にはならない")

	# 先送りプレビューでは増えない
	f.saplings.birch = 1
	f.add_tree(Vector2(0, 0), "birch", "sapling")
	f.advance_years(30.0)
	_check(f.wood_yield(f.trees[-1]) == 0, "先送りプレビューでは丸太は増えない(判定は現実の樹齢)")

func _test_blocks() -> void:
	print("小屋の場所には他のものを置けない")
	var w := _world()
	var c := w.cabin
	c.place(SITE)
	_check(c.covers(SITE) and not c.covers(OUTSIDE), "小屋の敷地が分かる")
	_check(w.toggle_plot(Vector2(19.5, 19.5)) == "cabin" and w.land.plots.is_empty(), "小屋にかかる場所に菜園の区画は置けない")
	_check(w.pond_action(Vector2(20, 25)) == "cabin" and w.land.pond == null, "小屋にかかる場所に池は掘れない")
	_check(w.toggle_plot(Vector2(10, 10)) == "placed", "離れた場所には区画を置ける")
	_check(w.toggle_plot(Vector2(10, 10)) == "removed", "離れた区画は取り消せる")
	_check(w.pond_action(Vector2(-20, -20)) == "placed", "離れた場所には池を掘れる")

func _test_cancel() -> void:
	print("場所の取り消し")
	var w := _world()
	var c := w.cabin
	_check(not c.cancel(OUTSIDE), "場所がなければ取り消せない")
	c.place(SITE)
	_check(not c.cancel(Vector2(0, 0)), "離れていると取り消せない")
	_check(c.cancel(OUTSIDE) and c.site == null, "作業を始める前なら取り消せる")
	c.place(SITE)
	c.materials.log = 3
	c.work(OUTSIDE)
	_check(not c.cancel(OUTSIDE) and c.site == SITE, "作業を始めたら取り消せない")

func _test_market() -> void:
	print("市場で丸太を買う")
	var w2 := _world()
	w2.market.money = 3000
	_check(w2.market.buy("logs") == "bought" and w2.cabin.materials.log == 5 and w2.market.money == 1500, "丸太 5 本を 1,500₽ で買える")
	_check(w2.market.buy("logs") == "bought" and w2.cabin.materials.log == 10 and w2.market.money == 0, "買い足せる")
	_check(w2.market.buy("logs") == "no_money" and w2.cabin.materials.log == 10, "お金が足りなければ買えない")

func _test_save() -> void:
	print("セーブ")
	var w := _world()
	var c := w.cabin
	c.materials.log = 10
	c.place(SITE)
	c.work(OUTSIDE)
	var w2 := _world(false)
	w2.load_game()
	var c2 := w2.cabin
	_check(c2.site == SITE and c2.stage == 0 and c2.days_done == 1, "小屋の場所と進み具合が自動で保存・復元される")
	_check(c2.materials.log == 7 and c2.worked_today(), "丸太の数と今日の作業の記録が復元される")

	# 手順 3-2 までのセーブ: 小屋の記録がない
	_remove_save()
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"unit": "m", "seeds": {"birch": 1, "apple": 0, "cedar": 0}, "last_day": "", "today_event": "", "trees": [],
		"garden": {"seeds": {"radish": 2}}, "market": {"money": 123},
	}))
	file.close()
	var w3 := _world(false)
	w3.cabin.materials.log = 9  # 読み込みで消えることを見る
	w3.load_game()
	_check(w3.cabin.site == null and w3.cabin.stage == 0 and w3.cabin.materials.log == 0, "前のセーブは小屋なし・丸太 0 から")
	_check(w3.garden.seeds.radish == 2 and w3.market.money == 123, "前のセーブの畑と所持金はそのまま")
