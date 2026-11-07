extends SceneTree

# チュートリアル(ヒント)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_guide.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる

const GameWorld = preload("res://logic/GameWorld.gd")
const Guide = preload("res://logic/Guide.gd")
const MainScript = preload("res://Main.gd")

const TEST_SAVE := "user://test_guide.json"
const FAR := Vector2(-40, -40)

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_every_hint_has_text()
	_test_new_game_flow()
	_test_notice_times_out()
	_test_dismiss()
	_test_not_relevant_any_more()
	_test_one_at_a_time()
	_test_current_save_shape()
	_test_stuck()
	_test_bee_hints()
	_test_cabin_hints()
	_test_season_and_pond()
	_test_people()
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
	w.forest.season = "summer"
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birds"
	return w

# 次のヒントが出るところまで進める(今のヒントが出ていれば、そのまま)
func _tick(w: GameWorld, pos := FAR) -> String:
	w.guide.update(pos, Guide.GAP_SECONDS + 0.1)
	return w.guide.current

func _add_tree(w: GameWorld, age := 3.0, species := "birch") -> void:
	w.forest.trees.append({"pos": Vector2(w.forest.trees.size() * 3 - 30, 30), "species": species, "form": "sapling", "planted_at": w.forest._now(), "start_age": age, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})

func _add_crop(w: GameWorld, sown_ago := 0, water_days := 0) -> Dictionary:
	var c := {"pos": Vector2(w.garden.crops.size() * 3 + 1.5, 1.5), "kind": "radish", "sown_day": w.garden.day_number() - sown_ago, "water_days": water_days, "last_watered": "", "head": 0.0}
	w.garden.crops.append(c)
	return c

func _test_every_hint_has_text() -> void:
	print("文言")
	var texts: Dictionary = MainScript.GUIDE_TEXTS
	for id in Guide.HINTS:
		_check(texts.has(id) and texts[id].contains("\n"), "%s の文言があり、2 行で読める" % id)
		var widest := 0
		for line in texts[id].split("\n"):
			widest = maxi(widest, line.length())
		_check(widest <= 36, "%s の 1 行は長すぎない(%d 字)" % [id, widest])
	for id in Guide.NOTICES:
		_check(id in Guide.HINTS, "%s は HINTS にある" % id)
	_check(texts.size() == Guide.HINTS.size(), "余分な文言がない")

func _test_new_game_flow() -> void:
	print("はじめから順に")
	var w := _world()
	var g := w.guide
	w.garden.seeds.radish = 0
	_check(_tick(w) == "walk", "はじめは歩き方")
	_check(_tick(w) == "walk", "歩くまで出ている")
	_tick(w, FAR + Vector2(5, 0))
	_check("walk" in g.seen and g.current == "", "歩くと消えて、もう出ない")
	_check(_tick(w, FAR) == "plant", "次は木の植え方")
	_add_tree(w)
	_tick(w)
	_check("plant" in g.seen and g.current == "", "植えると消える")
	_check(_tick(w) == "plot", "次は畑の区画")
	w.land.plots.append(Vector2(1.5, 1.5))
	_tick(w)
	_check("plot" in g.seen, "区画を作ると消える")
	_check(_tick(w) == "buy_seeds", "種がなければ、市場で買うことを案内する")
	w.garden.seeds.radish = 1
	_tick(w)
	_check("buy_seeds" in g.seen, "種を手に入れると消える")
	_check(_tick(w) == "sow", "種をまくことを案内する")
	w.garden.seeds.radish = 0
	var c := _add_crop(w)
	_tick(w)
	_check("sow" in g.seen, "まくと消える")
	_check(_tick(w) == "water", "水やりを案内する")
	c.water_days = 1
	c.last_watered = w.forest.today()
	_tick(w)
	_check("water" in g.seen, "水をやると消える")
	c.sown_day -= 10
	_check(_tick(w) == "harvest", "育つと収穫を案内する")
	w.garden.crops.clear()
	w.garden.produce.radish = 6
	_tick(w)
	_check("harvest" in g.seen, "収穫すると消える")
	_check(_tick(w) == "sell", "収穫物があると、売ることを案内する")
	w.garden.produce.radish = 0
	_tick(w)
	_check("sell" in g.seen, "売ると消える")
	# 一度出たものは、状況が戻っても出ない
	w.garden.produce.radish = 6
	_tick(w)
	_check(g.current != "sell", "一度出たヒントは二度と出ない")

func _test_notice_times_out() -> void:
	print("お知らせは時間で消える")
	var w := _world()
	var g := w.guide
	_add_tree(w)
	w.land.plots.append(Vector2(1.5, 1.5))
	g.seen = ["walk", "plant", "plot", "buy_seeds", "sow", "water", "harvest", "sell", "broke"]
	w.forest.season = "winter"
	_check(_tick(w) == "winter", "冬のお知らせが出る")
	g.update(FAR, Guide.SHOW_SECONDS - 1.0)
	_check(g.current == "winter", "しばらくは出ている")
	g.update(FAR, 2.0)
	_check(g.current == "" and "winter" in g.seen, "時間がたつと消える")
	g.update(FAR, 0.5)
	_check(g.current == "", "次のヒントまで間をあける")

func _test_dismiss() -> void:
	print("K で閉じる")
	var w := _world()
	var g := w.guide
	_tick(w)
	_check(g.current == "walk", "前提: 出ている")
	g.dismiss()
	_check(g.current == "" and "walk" in g.seen, "閉じると消えて、もう出ない")
	_check(FileAccess.file_exists(TEST_SAVE), "閉じると保存する")
	g.dismiss()
	_check(g.seen.count("walk") == 1, "何も出ていないときは何もしない")

func _test_not_relevant_any_more() -> void:
	print("関係なくなったヒント")
	var w := _world()
	var g := w.guide
	g.seen = ["walk", "plant", "plot", "buy_seeds", "sow"]
	_add_tree(w)
	w.land.plots.append(Vector2(1.5, 1.5))
	var c := _add_crop(w)
	_check(_tick(w) == "water", "前提: 水やりのヒント")
	w.forest.today_event = "rain"
	g.update(FAR, 0.5)
	_check(g.current == "" and not ("water" in g.seen), "雨が降れば引っ込める(まだ見たことにしない)")
	w.forest.today_event = "birds"
	_check(_tick(w) == "water", "また水が必要になれば出る")
	c.water_days = 1
	g.update(FAR, 0.5)
	_check("water" in g.seen, "水をやれば済む")

func _test_one_at_a_time() -> void:
	print("1 つずつ")
	var w := _world()
	var g := w.guide
	_tick(w)
	var first: String = g.current
	w.forest.season = "winter"
	_tick(w)
	_check(g.current == first, "出ているあいだは、ほかのヒントに変わらない")

func _test_current_save_shape() -> void:
	print("途中のセーブ(2026-11-06 の本物のセーブと同じ形)")
	var w := _world()
	var g := w.guide
	# 木 22 本・区画 76・野菜 6 区画(水やり済み)・種 0・所持金 20₽・小屋は基礎の 1 日目・丸太 2 本
	for i in range(22):
		_add_tree(w)
	for i in range(76):
		w.land.plots.append(Vector2((i % 20) * 3 + 1.5, int(i / 20.0) * 3 + 1.5))
	for i in range(6):
		_add_crop(w, 0, 1)
		w.garden.crops[-1].last_watered = w.forest.today()
	for k in w.garden.seeds:
		w.garden.seeds[k] = 0
	w.market.money = 20
	w.cabin.site = Vector2(10, 20)
	w.cabin.days_done = 1
	w.cabin.materials.log = 2
	_check(g._logs_needed() == 26, "小屋の残りの丸太は 26 本")
	var shown := []
	for _i in range(12):
		var id := _tick(w)
		if id == "":
			break
		shown.append(id)
		g.dismiss()
	_check(not ("walk" in shown or "plant" in shown or "plot" in shown or "sow" in shown), "済んでいることのヒントは出ない: %s" % str(shown))
	_check(shown.size() >= 2 and shown[0] == "broke", "最初はお金と種が足りないときのヒント: %s" % str(shown))
	_check("cabin_logs" in shown, "丸太の集め方も出る: %s" % str(shown))

func _test_stuck() -> void:
	print("手詰まりのとき")
	var w := _world()
	var g := w.guide
	g.has_people = true
	g.seen = ["walk", "plant", "plot", "buy_seeds", "sow", "water", "harvest", "sell"]
	_add_tree(w)
	w.land.plots.append(Vector2(1.5, 1.5))
	w.market.money = 20
	_check(w.visitors.is_stuck(), "前提: 手詰まり")
	_check(_tick(w) == "stuck", "手詰まりなら、訪問者に話すことを案内する")
	_check(not g._wants("broke"), "手詰まりなら「収穫して売ろう」は出さない")
	w.garden.seeds.radish = 3
	_tick(w)
	_check("stuck" in g.seen, "種が手に入ると消える")
	# 畑に野菜があるときは「収穫して売ろう」
	var w2 := _world()
	var g2 := w2.guide
	g2.has_people = true
	g2.seen = ["walk", "plant", "plot", "buy_seeds", "sow", "water", "harvest", "sell"]
	_add_tree(w2)
	w2.land.plots.append(Vector2(1.5, 1.5))
	_add_crop(w2, 0, 1)
	w2.market.money = 20
	_check(_tick(w2) == "broke" and not w2.visitors.is_stuck(), "畑に野菜があれば、収穫して売ることを案内する")
	# 2D には訪問者がいないので案内しない
	var w3 := _world()
	w3.guide.seen = ["walk", "plant", "plot", "buy_seeds", "sow", "water", "harvest", "sell"]
	_add_tree(w3)
	w3.land.plots.append(Vector2(1.5, 1.5))
	w3.market.money = 20
	_check(_tick(w3) != "stuck", "2D では訪問者の案内を出さない")

func _test_bee_hints() -> void:
	print("巣箱")
	var w := _world()
	var g := w.guide
	g.seen = ["walk", "plant", "plot", "buy_seeds", "sow", "water", "harvest", "sell", "stuck", "broke", "cabin_site"]
	_add_tree(w)
	w.land.plots.append(Vector2(1.5, 1.5))
	_check(_tick(w) == "", "自分の丸太がなければ案内しない")
	w.cabin.materials.log = 5
	_check(_tick(w) == "", "市場の丸太では案内しない")
	w.cabin.own_logs = 2
	_check(_tick(w) == "hive_make", "自分の丸太があると巣箱を案内する")
	w.bees.act(FAR)
	_tick(w)
	_check("hive_make" in g.seen, "置くと消える")
	var h: Dictionary = w.bees.hive_near(FAR)
	h.days_done = w.bees.HOLLOW_DAYS
	_check(_tick(w) == "hive_bees", "空の巣箱ができると、蜂の入れ方を案内する")
	h.occupied = true
	_tick(w)
	_check("hive_bees" in g.seen, "蜂が入ると消える")
	h.comb = 2.0
	_check(_tick(w) == "honey", "たまると採り方を案内する")
	h.comb = 0.0
	_tick(w)
	_check("honey" in g.seen, "採ると消える")

func _test_cabin_hints() -> void:
	print("小屋")
	var w := _world()
	var g := w.guide
	g.seen = ["walk", "plant", "plot", "buy_seeds", "sow", "water", "harvest", "sell", "broke"]
	_add_tree(w)
	for i in range(3):
		w.land.plots.append(Vector2(i * 3 + 1.5, 1.5))
	_check(_tick(w) == "", "区画が少ないうちは小屋を案内しない")
	w.land.plots.append(Vector2(10.5, 1.5))
	_check(_tick(w) == "cabin_site", "区画が増えると小屋を案内する")
	w.cabin.site = Vector2(20, 20)
	_tick(w)
	_check("cabin_site" in g.seen, "場所を決めると消える")
	_check(_tick(w) == "cabin_logs", "丸太の集め方を案内する")
	w.cabin.materials.log = 29
	_tick(w)
	_check("cabin_logs" in g.seen, "丸太がそろうと消える")
	w.cabin.stage = 3
	_check(_tick(w) == "cabin_inside", "完成すると中に入れることを案内する")
	_tick(w, Vector2(20, 20))
	_check("cabin_inside" in g.seen, "中に入ると消える")
	_check(_tick(w, Vector2(20, 20)) == "split", "薪がなければ、薪割りを案内する")
	w.cabin.materials.log = 1
	w.kitchen.split()
	_tick(w, Vector2(20, 20))
	_check("split" in g.seen, "割ると消える")
	w.kitchen.firewood = 0
	w.garden.produce.potato = 4
	g.seen.append("sell")
	_check(_tick(w, Vector2(20, 20)) == "stove", "中で収穫物を持っていると、ストーブを案内する")
	w.kitchen.firewood = 9
	_tick(w, Vector2(20, 20))
	_check(not ("stove" in g.seen), "薪があるだけでは消えない(薪は剪定の枝でも増える)")
	w.garden.produce.potato = 4
	w.kitchen.start("pirozhki")
	_tick(w, Vector2(20, 20))
	_check("stove" in g.seen, "一度料理すると消える")
	_check(_tick(w, Vector2(20, 20)) == "bed", "ベッドを案内する")

func _test_season_and_pond() -> void:
	print("季節と池")
	var w := _world()
	var g := w.guide
	g.seen = ["walk", "plant", "plot", "buy_seeds", "sow", "water", "harvest", "sell", "broke", "cabin_site"]
	_add_tree(w, 8.0, "apple")
	w.land.plots.append(Vector2(1.5, 1.5))
	w.forest.season = "summer"
	_check(_tick(w) == "", "夏はリンゴのヒントが出ない")
	w.forest.season = "autumn"
	_check(_tick(w) == "apple", "秋で実る木があるとリンゴのヒント")
	g.dismiss()
	w.land.pond = Vector2(-20, 20)
	w.pond.days_dug = w.pond.DIG_DAYS
	w.pond.water = 0
	_check(_tick(w) == "pond_rain", "空の池には、雨でたまることを案内する")
	g.dismiss()
	w.pond.water = 50
	_add_crop(w)
	_check(_tick(w, FAR) == "", "池から離れていると、まとめて水やりは案内しない")
	_check(_tick(w, Vector2(-20, 25)) == "pond_water", "池のそばで水のいるものがあれば、まとめて水やりを案内する")

func _test_people() -> void:
	print("訪問者と生き物(3D だけ)")
	var w := _world()
	var g := w.guide
	g.seen = ["walk", "plant", "plot", "buy_seeds", "sow", "water", "harvest", "sell", "broke", "cabin_site"]
	_add_tree(w)
	w.land.plots.append(Vector2(1.5, 1.5))
	w.visitors.visit = {"day": w.forest.day_number(), "who": "nina", "kind": "chat", "done": false, "line": 0}
	w.wildlife.seen = ["sparrow"]
	_check(_tick(w) == "", "2D では訪問者も生き物も案内しない")
	g.has_people = true
	_check(_tick(w) == "visitor", "3D では訪問者を案内する")
	w.visitors.finish_chat()
	_tick(w)
	_check("visitor" in g.seen, "話し終えると消える")
	_check(_tick(w) == "creatures", "見かけた生き物の見方を案内する")

func _test_save() -> void:
	print("セーブ")
	var w := _world()
	w.guide.seen = ["walk", "water"]
	w.guide.current = "plant"
	w.save_game()
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	_check(w2.guide.seen == ["walk", "water"], "出し終えたヒントが残る")
	_check(w2.guide.current == "", "出していたヒントは、見たことにしない(また出る)")
	w2.guide.from_save({"seen": ["walk", "gone"]})
	_check(w2.guide.seen == ["walk"], "知らないヒントは無視する")
	_remove_save()
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"unit": "m", "trees": []}))
	f.close()
	var w3 := GameWorld.new()
	w3.save_path = TEST_SAVE
	w3.load_game()
	_check(w3.guide.seen.is_empty(), "記録がないセーブは、まだ何も出ていない")
