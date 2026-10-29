extends SceneTree

# 段階クエスト(Phase 2-3)と菜園・池のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v3.6.2-stable_win64.exe --no-window --path . -s res://tests/test_quests.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる

const TEST_SAVE := "user://test_quests.json"

var _failed := 0
var _passed := 0

func _init() -> void:
	_test_hedge_segments()
	_test_land_toggles()
	_test_sequential_stages()
	_test_family_cedar_rules()
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

# Trees・Land・Quests をつないだ一式。種は十分に持たせる
func _world(remove_save := true) -> Dictionary:
	if remove_save:
		_remove_save()
	var t: Node2D = load("res://Trees.gd").new()
	var l: Node2D = load("res://Land.gd").new()
	var q: Node2D = load("res://Quests.gd").new()
	t.save_path = TEST_SAVE
	t.land = l
	t.quests = q
	q.trees = t
	q.land = l
	t.seeds = {"birch": 200, "apple": 0, "cedar": 5}
	return {"trees": t, "land": l, "quests": q}

func _free(w: Dictionary) -> void:
	for k in w:
		w[k].free()

func _plant_hedge(w: Dictionary, skip := -1) -> void:
	for i in range(w.quests.HEDGE_SEGMENTS):
		if i != skip:
			w.trees.add_tree(w.quests._segment_center(i), "birch")

func _test_hedge_segments() -> void:
	print("生垣の区画")
	var w := _world()
	_check(w.quests.progress("hedge") == [0, 40], "木がなければ 0/40")
	_plant_hedge(w, 7)
	_check(w.quests.progress("hedge") == [39, 40], "1区画だけ空けると 39/40")
	w.trees.add_tree(w.quests._segment_center(7), "birch")
	_check(w.quests.progress("hedge") == [40, 40], "全区画に植えると 40/40")

	var w2 := _world()
	w2.trees.add_tree(Vector2(0, 0), "birch")                 # 中心
	w2.trees.add_tree(Vector2(0, -2000 + 160), "birch")       # 境界から4m(帯の外)
	w2.trees.add_tree(Vector2(0, -2100), "birch")             # 土地の外
	_check(w2.quests.progress("hedge")[0] == 0, "中心・境界から4m・土地の外の木は数えない")
	w2.trees.add_tree(Vector2(0, -2000 + 100), "birch")       # 境界から2.5m
	_check(w2.quests.progress("hedge")[0] == 1, "境界から3m以内の木は数える")
	var w3 := _world()
	w3.trees.add_tree(Vector2(-1990, -1990), "birch")         # 左上の角
	var f: Array = w3.quests.hedge_filled()
	_check(f[0] and f[39] and w3.quests.progress("hedge")[0] == 2, "角の木は上辺と左辺の2区画を埋める")
	_free(w)
	_free(w2)
	_free(w3)

func _test_land_toggles() -> void:
	print("菜園と池")
	var w := _world()
	var l: Node2D = w.land
	_check(l.toggle_plot(Vector2(10, 10)) == "placed", "足元に区画を置ける")
	_check(l.plots[0] == Vector2(60, 60), "区画は3mマスの中心にそろう")
	_check(l.toggle_plot(Vector2(100, 30)) == "removed", "同じマスでもう一度押すと取り消せる")
	_check(l.plots.empty(), "取り消すと区画が消える")
	_check(l.toggle_plot(Vector2(1990, 0)) == "outside", "境界にかかる区画は置けない")

	_check(l.toggle_pond(Vector2(500, 500)) == "placed", "池を掘れる")
	_check(l.toggle_pond(Vector2(-800, 0)) == "one_only", "池はひとつまで")
	_check(l.toggle_pond(Vector2(560, 500)) == "removed", "池の中で押すと埋める")
	_check(l.pond == null, "埋めると池が消える")
	_check(l.toggle_pond(Vector2(1900, 0)) == "outside", "境界にかかる池は掘れない")
	_free(w)

func _test_sequential_stages() -> void:
	print("順番に進む")
	var w := _world()
	var q: Node2D = w.quests
	_check(q.current_id() == "hedge" and q.advance().empty(), "はじめは生垣。条件を満たすまで進まない")

	# 菜園を先に作っておく(段階 2 に来たときにすぐ達成するはず)
	for x in [0, 120, 240, 360]:
		w.land.toggle_plot(Vector2(x + 10, 400))
	_check(q.advance().empty() and q.stage == 0, "生垣が先。菜園だけでは進まない")

	_plant_hedge(w)
	var done: Array = q.advance()
	_check(done == ["hedge", "garden"], "生垣を達成すると、先に作った菜園もすぐ達成")
	_check(q.current_id() == "pond", "次は池")

	w.land.toggle_pond(Vector2(-600, -600))
	_check(q.advance() == ["pond"], "池を掘ると達成")

	w.trees.add_tree(Vector2(100, 0), "cedar")
	done = q.advance()
	_check(done == ["family_cedar", "complete"], "中心に杉を植えると達成し、愛の空間が完成")
	_check(q.is_complete() and q.current_id() == "", "完成したら current_id は空")

	# 達成済みは戻らない
	for i in range(10):
		w.trees.remove_nearest(q._segment_center(i), 80.0)
	w.land.toggle_pond(Vector2(-600, -600))
	_check(q.advance().empty() and q.is_complete(), "あとで木を抜いたり池を埋めても完成は戻らない")
	_free(w)

func _test_family_cedar_rules() -> void:
	print("家族の杉")
	var w := _world()
	w.trees.add_tree(Vector2(0, 0), "birch")
	_check(w.quests.progress("family_cedar") == [0, 1], "中心の白樺は数えない")
	w.trees.add_tree(Vector2(240, 0), "cedar")
	_check(w.quests.progress("family_cedar") == [0, 1], "中心から6mの杉は数えない")
	w.trees.add_tree(Vector2(0, 180), "cedar")
	_check(w.quests.progress("family_cedar") == [1, 1], "中心から4.5mの杉は数える")
	_free(w)

func _test_save_and_old_format() -> void:
	print("セーブ")
	var w := _world()
	w.land.toggle_plot(Vector2(10, 10))
	w.land.toggle_pond(Vector2(-500, 0))
	w.quests.stage = 2
	w.trees.save_game()
	var w2 := _world(false)
	w2.trees.load_game()
	_check(w2.land.plots == [Vector2(60, 60)], "菜園の区画が保存・復元される")
	_check(w2.land.pond == Vector2(-500, 0), "池が保存・復元される")
	_check(w2.quests.stage == 2, "クエストの段階が保存・復元される")
	_free(w)
	_free(w2)

	# 2-2 時点のセーブ(菜園・池・クエストの記録なし)
	_remove_save()
	var f := File.new()
	f.open(TEST_SAVE, File.WRITE)
	f.store_string(to_json({"seeds": {"birch": 1, "apple": 0, "cedar": 0}, "last_day": "", "today_event": "", "trees": []}))
	f.close()
	var w3 := _world(false)
	w3.land.plots.append(Vector2(1, 1))  # 読み込みで消えることを見る
	w3.trees.load_game()
	_check(w3.land.plots.empty() and w3.land.pond == null and w3.quests.stage == 0, "旧セーブは菜園・池なし・段階0から")
	_free(w3)
