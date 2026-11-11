extends SceneTree

# 小屋の増築と家具(2026-11-11)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_extension.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Cabin = preload("res://logic/Cabin.gd")

const TEST_SAVE := "user://test_extension.json"
const SITE := Vector2(20, 20)
const WEST := Vector2(14.0, 20.0)   # 西の部屋(x 15〜18)の西、1m の外
const IN_EXT := Vector2(16.5, 20.0) # 西の部屋の中
const IN_MAIN := Vector2(20.0, 20.5)

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_buy_extension()
	_test_blocked()
	_test_build()
	_test_rooms()
	_test_two_pots()
	_test_pots_12()
	_test_furniture()
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

# 小屋が完成している世界
func _world(complete := true) -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.forest.season = "autumn"
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birds"
	w.cabin.site = SITE
	w.cabin.stage = 3 if complete else 1
	w.market.money = 50000
	return w

# 増築を頼んで、建て終えた世界
func _extended() -> GameWorld:
	var w := _world()
	w.market.buy("cabin_extension")
	w.cabin.ext_stage = Cabin.EXT_STAGES.size()
	return w

func _test_buy_extension() -> void:
	print("増築を頼む")
	var w := _world(false)
	var m := w.market
	_check(m.buy("cabin_extension") == "no_cabin" and m.money == 50000, "小屋ができる前は頼めない")
	w.cabin.stage = 3
	_check(m.buy("furniture_rug") == "no_room", "増築する前は家具を買えない")
	_check(m.buy("cabin_extension") == "bought" and m.money == 42000, "完成した小屋なら 8,000₽ で頼める")
	_check(w.cabin.ext_started() and w.cabin.ext_building() and not w.cabin.has_extension(), "頼むと建てはじめる(まだできていない)")
	_check(m.is_owned(m.good("cabin_extension")) and m.buy("cabin_extension") == "exists", "二度は頼めない")
	_check(w.cabin.ext_rect() == Rect2(15, 18.5, 3, 3), "西の部屋は小屋の西に 3m × 3m")
	_check(w.cabin.covers(Vector2(16, 20)) and w.cabin.blocks_plot(Vector2(16.5, 20)), "頼んだら西の部屋の場所には区画を置けない")
	_check(w.toggle_plot(Vector2(16.5, 19.5)) != "placed", "区画の操作でも置けない")
	_check(not w.cabin.is_inside(Vector2(16, 20)), "建てている間は中に入れない")
	w.market.money = 10
	var w2 := _world()
	w2.market.money = 7999
	_check(w2.market.buy("cabin_extension") == "no_money" and not w2.cabin.ext_started(), "お金が足りなければ頼めない")

func _test_blocked() -> void:
	print("西がふさがっている")
	var w := _world()
	w.land.toggle_plot(Vector2(16.5, 19.5))
	_check(w.market.buy("cabin_extension") == "plot" and w.market.money == 50000, "西に区画があれば頼めない(お金は減らない)")
	w.land.plots.clear()
	w.forest.trees.append({"pos": Vector2(16, 21), "species": "birch", "form": "sapling", "planted_at": w.forest._now(), "start_age": 3.0, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	_check(w.market.buy("cabin_extension") == "tree", "西に木があれば頼めない")
	w.forest.trees.clear()
	w.bees.hives.append({"pos": Vector2(14.5, 20), "days_done": 0, "last_worked": "", "hollowed_day": -1, "occupied": false, "comb": 0.0})
	_check(w.market.buy("cabin_extension") == "hive", "西のすぐそばに巣箱があれば頼めない")
	w.bees.hives.clear()
	w.feeders.feeders.append({"pos": Vector2(16, 18), "fed_day": -1})
	_check(w.market.buy("cabin_extension") == "feeder", "餌台があっても頼めない")
	w.feeders.feeders.clear()
	var edge := _world()
	edge.cabin.site = Vector2(-42.5, 20)
	_check(edge.market.buy("cabin_extension") == "edge", "西が境界に近ければ頼めない")
	var center := _world()
	center.cabin.site = Vector2(9, 0)
	_check(center.market.buy("cabin_extension") == "center", "西が中心に近ければ頼めない")

func _test_build() -> void:
	print("建てる")
	var w := _world()
	var c := w.cabin
	w.market.buy("cabin_extension")
	c.materials.log = 20
	_check(c.is_at_ext_site(WEST) and not c.is_at_ext_site(IN_MAIN) and not c.is_at_ext_site(Vector2(25, 20)), "西の外で作業できる(母屋の中や東ではできない)")
	_check(c.work_extension(IN_EXT) == "inside", "建てる場所の中では作業しない")
	var results := []
	var logs := [c.materials.log]
	for i in range(4):
		results.append(c.work_extension(WEST))
		if i == 0:
			_check(c.work_extension(WEST) == "done_today", "1 日 1 回")
		c.ext_last_worked = ""
		logs.append(c.materials.log)
	print("    結果: ", results, " 丸太: ", logs)
	_check(results == ["stage_done", "worked", "stage_done", "finished"], "基礎 1 日・壁 2 日・屋根 1 日")
	_check(logs == [20, 17, 13, 9, 6] and c.ext_total_logs() == 14, "丸太は 3 → 4 → 4 → 3 本、計 14 本")
	_check(c.has_extension() and not c.ext_building(), "4 日でできる")
	_check(c.work_extension(WEST) == "none" and not c.is_at_ext_site(WEST), "できたらもう作業はない")
	var w2 := _world()
	w2.market.buy("cabin_extension")
	w2.cabin.materials.log = 2
	_check(w2.cabin.work_extension(WEST) == "no_wood", "丸太が足りなければ作業できない")

func _test_rooms() -> void:
	print("部屋")
	var w := _extended()
	var c := w.cabin
	_check(c.is_inside(IN_EXT) and c.is_inside(IN_MAIN), "西の部屋にも入れる(小屋は 7m × 3m)")
	_check(c.footprints().size() == 2 and c.covers(IN_EXT), "小屋の範囲は 2 つの長方形")
	_check(c.is_at_kamado(SITE + Cabin.KAMADO_OFFSET + Vector2(0.3, 0.6)) and not c.is_at_kamado(IN_MAIN), "西の部屋の北西にかまど")
	_check(not c.is_at_stove(SITE + Cabin.KAMADO_OFFSET), "かまどはストーブとは別")
	_check(w.snow.clear_at(IN_EXT) != "cleared", "西の部屋の中は雪かきしない")

func _test_two_pots() -> void:
	print("鍋が 2 つ")
	var w := _extended()
	var k := w.kitchen
	k.firewood = 5
	w.forest.produce.apple = 40
	k.active = 0
	_check(k.start("jam") == "started", "ストーブで仕込む")
	_check(k.start("jam") == "busy", "ストーブの鍋はふさがる")
	k.active = 1
	_check(k.is_empty() and k.start("jam") == "started", "かまどの鍋で、もう 1 つ仕込める")
	_check(not k.all_empty() and k.pots[0].recipe == "jam" and k.pots[1].recipe == "jam", "2 つの鍋が別々に仕込まれている")
	_check(k.any_cooking(), "仕込んでいる鍋がある")
	k.pots[0].start_day -= 30
	k.active = 0
	_check(k.collect() == "collected" and k.pots[0].is_empty() and not k.pots[1].is_empty(), "ストーブの鍋だけ受け取る")
	_check(k.with_pot(1, func(): return k.days_left()) > 0 and k.active == 0, "with_pot は使う鍋を元に戻す")
	k.active = 1
	k.pots[1] = {}
	_check(k.all_empty(), "どちらも空")
	# セーブ
	k.pots[1] = {"recipe": "pickles", "start_day": 5}
	w.save_game()
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	_check(w2.kitchen.pots[1] == {"recipe": "pickles", "start_day": 5} and w2.kitchen.pots[0].is_empty() and w2.kitchen.active == 0, "かまどの鍋も保存される")
	var w3 := GameWorld.new()
	w3.kitchen.from_save({"pot": {"recipe": "jam", "start_day": 1}})
	_check(w3.kitchen.pots[0].recipe == "jam" and w3.kitchen.pots[1].is_empty(), "かまどの記録がないセーブは、かまどは空")

func _test_pots_12() -> void:
	print("窓辺の鉢")
	var w := _world()
	var sl := w.seedlings
	_check(sl.max_pots() == 6, "増築する前は 6 鉢")
	w.garden.seeds.tomato = 20
	for i in range(6):
		sl.pots.append({"kind": "tomato", "sown_day": w.forest.day_number(), "water_days": 1, "last_watered": w.forest.today()})
	_check(sl.act(SITE + Vector2(0, 2.0), "tomato") == "full", "6 鉢でいっぱい")
	w.cabin.ext_stage = 3
	_check(sl.max_pots() == 12 and sl.act(SITE + Vector2(0, 2.0), "tomato") == "sown" and sl.pots.size() == 7, "増築すると 12 鉢まで")

func _test_furniture() -> void:
	print("家具")
	var w := _extended()
	var m := w.market
	var c := w.cabin
	var money: int = m.money
	var prices := 0
	for id in Cabin.FURNITURE:
		var g: Dictionary = m.good("furniture_" + id)
		_check(not g.is_empty() and m.buy(g.id) == "bought" and c.has_furniture(id), "%s を買って置く(%d₽)" % [id, g.price])
		prices += int(g.price)
	_check(m.money == money - prices and prices == 11200, "家具の合計は 11,200₽")
	_check(m.buy("furniture_rug") == "owned" and m.money == money - prices, "同じ家具は 1 つまで")
	_check(c.add_furniture("sofa") == "unknown", "知らない家具は置かない")
	_check(c.is_at_chair(SITE + Cabin.CHAIR_OFFSET + Vector2(0.3, 0)) and not c.is_at_chair(IN_MAIN), "揺り椅子のそばで座れる")
	var w2 := _extended()
	_check(not w2.cabin.is_at_chair(SITE + Cabin.CHAIR_OFFSET), "揺り椅子がなければ座れない")

func _test_save() -> void:
	print("セーブ")
	var w := _extended()
	w.cabin.ext_stage = 1
	w.cabin.ext_days_done = 1
	w.cabin.ext_last_worked = "2026-11-11"
	w.cabin.furniture = ["clock"]
	w.save_game()
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	var c: Cabin = w2.cabin
	_check(c.ext_stage == 1 and c.ext_days_done == 1 and c.ext_last_worked == "2026-11-11", "増築の段階が保存される")
	_check(c.furniture == ["clock"], "家具が保存される")
	var c3 := Cabin.new()
	c3.from_save({"site": [1, 2], "stage": 3})
	_check(c3.ext_stage == -1 and c3.furniture.is_empty() and not c3.ext_started(), "記録がないセーブは増築なし・家具なし")
	c3.from_save({"site": [1, 2], "stage": 3, "ext_stage": 99, "furniture": ["rug", "rug", "sofa"]})
	_check(c3.ext_stage == 3 and c3.furniture == ["rug"], "おかしな記録は読まない")
