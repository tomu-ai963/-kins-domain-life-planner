extends SceneTree

# 段階クエスト(Phase 2-3)と菜園・池のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_quests.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")

const TEST_SAVE := "user://test_quests.json"
const REACH := 2.0  # 足元 2m

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_hedge_segments()
	_test_land_toggles()
	_test_sequential_stages()
	_test_family_cedar_rules()
	_test_save_and_old_format()
	_test_guide_and_milestones()
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

func _write_save(data: Dictionary) -> void:
	_remove_save()
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

# Forest・Land・Quests をつないだ一式(GameWorld)。種は十分に持たせる
func _world(remove_save := true) -> GameWorld:
	if remove_save:
		_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.forest.seeds = {"birch": 200, "apple": 0, "cedar": 5}
	w.forest.saplings = {"birch": 200, "apple": 0, "cedar": 5}  # 根付いた木を植えるときは苗木で
	return w

func _plant_hedge(w: GameWorld, skip := -1) -> void:
	for i in range(w.quests.HEDGE_SEGMENTS):
		if i != skip:
			w.forest.add_tree(w.quests.segment_center(i), "birch", "sapling")

func _test_hedge_segments() -> void:
	print("生垣の区画")
	var w := _world()
	_check(w.quests.progress("hedge") == [0, 40], "木がなければ 0/40")
	_plant_hedge(w, 7)
	_check(w.quests.progress("hedge") == [39, 40], "1区画だけ空けると 39/40")
	w.forest.add_tree(w.quests.segment_center(7), "birch", "sapling")
	_check(w.quests.progress("hedge") == [40, 40], "全区画に植えると 40/40")

	var w2 := _world()
	w2.forest.add_tree(Vector2(0, 0), "birch", "sapling")          # 中心
	w2.forest.add_tree(Vector2(0, -50 + 4), "birch", "sapling")    # 境界から4m(帯の外)
	w2.forest.add_tree(Vector2(0, -52.5), "birch", "sapling")      # 土地の外
	_check(w2.quests.progress("hedge")[0] == 0, "中心・境界から4m・土地の外の木は数えない")
	w2.forest.add_tree(Vector2(0, -50 + 2.5), "birch", "sapling")  # 境界から2.5m
	_check(w2.quests.progress("hedge")[0] == 1, "境界から3m以内の木は数える")
	var w3 := _world()
	w3.forest.add_tree(Vector2(-49.75, -49.75), "birch", "sapling")  # 左上の角
	var f: Array = w3.quests.hedge_filled()
	_check(f[0] and f[39] and w3.quests.progress("hedge")[0] == 2, "角の木は上辺と左辺の2区画を埋める")
	var w4 := _world()
	w4.forest.add_tree(w4.quests.segment_center(3), "birch")  # 種のまま(芽が出る前)
	_check(w4.quests.progress("hedge")[0] == 0, "芽が出る前の種は生垣に数えない")
	w4.forest.trees[0].planted_at -= 86400  # 1 日たって芽が出た
	w4.forest.trees[0].sprouts = true
	_check(w4.quests.progress("hedge")[0] == 1, "芽が出て根付いたら数える")
	w4.forest.trees[0].sprouts = false
	_check(w4.quests.progress("hedge")[0] == 0, "芽が出なかった種は数えない")

func _test_land_toggles() -> void:
	print("菜園と池")
	var w := _world()
	var l := w.land
	_check(l.toggle_plot(Vector2(0.25, 0.25)) == "placed", "足元に区画を置ける")
	_check(l.plots[0] == Vector2(1.5, 1.5), "区画は3mマスの中心にそろう")
	_check(l.toggle_plot(Vector2(2.5, 0.75)) == "removed", "同じマスでもう一度押すと取り消せる")
	_check(l.plots.is_empty(), "取り消すと区画が消える")
	_check(l.toggle_plot(Vector2(49.75, 0)) == "outside", "境界にかかる区画は置けない")

	_check(l.toggle_pond(Vector2(12.5, 12.5)) == "placed", "池を掘れる")
	_check(l.toggle_pond(Vector2(-20, 0)) == "one_only", "池はひとつまで")
	_check(l.toggle_pond(Vector2(14, 12.5)) == "removed", "池の中で押すと埋める")
	_check(l.pond == null, "埋めると池が消える")
	_check(l.toggle_pond(Vector2(47.5, 0)) == "outside", "境界にかかる池は掘れない")

func _test_sequential_stages() -> void:
	print("どれからでも達成(2026-11-11 とむ決定)")
	var w := _world()
	var q := w.quests
	_check(q.current_id() == "hedge" and q.advance().is_empty(), "はじめは何も達成していない(いちばん前は生垣)")

	# 生垣より先に菜園を作る
	for x in [0.0, 3.0, 6.0, 9.0]:
		w.land.toggle_plot(Vector2(x + 0.25, 10))
	_check(q.advance() == ["garden"] and q.is_done("garden") and q.done.size() == 1, "生垣の前でも、菜園を作れば達成")
	_check(q.current_id() == "hedge" and q.remaining() == ["hedge", "pond", "family_cedar"], "残りは生垣・池・家族の杉")

	_plant_hedge(w)
	var done: Array = q.advance()
	_check(done == ["hedge"], "生垣を達成")
	_check(q.current_id() == "pond", "残りのいちばん前は池")

	w.pond_action(Vector2(-15, -15))
	_check(q.advance().is_empty(), "場所を決めただけでは達成しない")
	for i in range(w.pond.DIG_DAYS):
		w.pond.last_dug = ""
		w.pond_action(Vector2(-15, -15))
	_check(q.advance() == ["pond"], "池を掘り終えると達成")

	w.forest.add_tree(Vector2(2.5, 0), "cedar", "sapling")
	done = q.advance()
	_check(done == ["family_cedar", "complete"], "中心に杉を植えると達成し、愛の空間が完成")
	_check(q.is_complete() and q.current_id() == "", "完成したら current_id は空")

	# 達成済みは戻らない
	for i in range(10):
		w.forest.remove_nearest(q.segment_center(i), REACH)
	w.land.toggle_pond(Vector2(-15, -15))
	_check(q.advance().is_empty() and q.is_complete(), "あとで木を抜いたり池を埋めても完成は戻らない")

func _test_family_cedar_rules() -> void:
	print("家族の杉")
	var w := _world()
	w.forest.add_tree(Vector2(0, 0), "birch", "sapling")
	_check(w.quests.progress("family_cedar") == [0, 1], "中心の白樺は数えない")
	w.forest.add_tree(Vector2(6, 0), "cedar", "sapling")
	_check(w.quests.progress("family_cedar") == [0, 1], "中心から6mの杉は数えない")
	w.forest.add_tree(Vector2(0, 3), "cedar")  # 種のまま
	_check(w.quests.progress("family_cedar") == [0, 1], "中心に杉の種をまいただけでは数えない")
	w.forest.add_tree(Vector2(0, 4.5), "cedar", "sapling")
	_check(w.quests.progress("family_cedar") == [1, 1], "中心から4.5mの杉は数える")

func _test_save_and_old_format() -> void:
	print("セーブ")
	var w := _world()
	w.land.toggle_plot(Vector2(0.25, 0.25))
	w.land.toggle_pond(Vector2(-12.5, 0))
	w.quests.done = ["garden", "hedge"]
	w.save_game()
	var w2 := _world(false)
	w2.load_game()
	_check(w2.land.plots == [Vector2(1.5, 1.5)], "菜園の区画が保存・復元される")
	_check(w2.land.pond == Vector2(-12.5, 0), "池が保存・復元される")
	_check(w2.quests.done == ["garden", "hedge"], "達成したクエストが保存・復元される")

	# 2-2 時点のセーブ(菜園・池・クエストの記録なし)
	_write_save({"seeds": {"birch": 1, "apple": 0, "cedar": 0}, "last_day": "", "today_event": "", "trees": []})
	var w3 := _world(false)
	w3.land.plots.append(Vector2(1, 1))  # 読み込みで消えることを見る
	w3.load_game()
	_check(w3.land.plots.is_empty() and w3.land.pond == null and w3.quests.done.is_empty(), "旧セーブは菜園・池なし・クエストはまだ")

	# Godot 3 版(2-3)のセーブ: 菜園・池の座標は px
	_write_save({"seeds": {"birch": 1, "apple": 0, "cedar": 0}, "last_day": "", "today_event": "", "trees": [],
			"land": {"plots": [[60, 60], [-1860, 300]], "pond": [-500, 0]}, "quests": {"stage": 3}})
	var w4 := _world(false)
	w4.load_game()
	_check(w4.land.plots == [Vector2(1.5, 1.5), Vector2(-46.5, 7.5)], "px のセーブの菜園は m に直す")
	_check(w4.land.pond == Vector2(-12.5, 0), "px のセーブの池は m に直す")
	_check(w4.quests.done == ["hedge", "garden", "pond"], "順番に進めていたころのセーブ(段階 3)は、前の 3 つを達成済みにする")

func _test_guide_and_milestones() -> void:
	print("生き物の図鑑と木の節目(2026-11-11)")
	var w := _world()
	var q := w.quests
	_check(q.guide_ids().size() == 16 and q.guide_seen().is_empty(), "図鑑は 16 種類(土地 11・池 5)。はじめは 0")
	w.wildlife.seen = ["sparrow", "woodpecker"]
	w.pond.seen = ["strider"]
	_check(q.guide_seen() == ["sparrow", "woodpecker", "strider"] and q.guide_missing().size() == 13, "土地と池で見かけた生き物を数える")
	_check(not q.take_guide_complete(), "そろうまでは知らせない")
	w.wildlife.seen = w.wildlife.SPECIES.keys()
	w.pond.seen = w.pond.CREATURES.keys()
	_check(q.take_guide_complete() and not q.take_guide_complete(), "そろったら 1 回だけ知らせる")

	_check(q.milestone_total() == 24, "木の節目は 6 樹種 × 樹齢 10・25・50・100 年 = 24")
	w.forest.trees.append({"pos": Vector2(10, 10), "species": "birch", "form": "sapling", "planted_at": w.forest._now(), "start_age": 12.0, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	w.forest.trees.append({"pos": Vector2(12, 10), "species": "cedar", "form": "sapling", "planted_at": w.forest._now(), "start_age": 4.0, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	var reached: Array = q.check_milestones()
	_check(reached == [{"species": "birch", "age": 10}] and q.milestones == ["birch:10"], "白樺(樹齢 12 年)が 10 年の節目を迎える")
	_check(q.check_milestones().is_empty(), "同じ節目は 2 度知らせない")
	var next: Dictionary = q.next_milestone()
	_check(next.species == "cedar" and next.age == 10 and next.days == 6, "次の節目は シベリア杉 10 年まで あと 6 日")
	w.forest.trees[0].start_age = 60.0
	_check(q.check_milestones().size() == 2 and q.milestones == ["birch:10", "birch:25", "birch:50"], "一度に 2 つ迎えることもある")

	# 保存
	q.done = ["garden"]
	q.guide_done = true
	w.save_game()
	var w2 := _world(false)
	w2.load_game()
	_check(w2.quests.milestones == ["birch:10", "birch:25", "birch:50"] and w2.quests.guide_done and w2.quests.done == ["garden"], "節目と図鑑の知らせが保存される")
	# 節目の記録がない古いセーブは、もう迎えた節目を黙って記録する
	_write_save({"unit": "m", "last_day": "", "today_event": "", "quests": {"stage": 1},
		"trees": [{"x": 10, "y": 10, "species": "birch", "form": "sapling", "planted_at": int(Time.get_unix_time_from_system()), "start_age": 30.0}]})
	var w3 := _world(false)
	w3.load_game()
	_check(w3.quests.milestones == ["birch:10", "birch:25"] and w3.quests.check_milestones().is_empty(), "古いセーブを開いても、昔の節目をまとめて知らせない")
	_check(w3.quests.done == ["hedge"], "段階 1 のセーブは生垣を達成済み")
