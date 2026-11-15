extends SceneTree

# 土地の外の川と、田んぼの米のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_river.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m(北は -y)

const GameWorld = preload("res://logic/GameWorld.gd")
const Garden = preload("res://logic/Garden.gd")
const River = preload("res://logic/River.gd")
const Market = preload("res://logic/Market.gd")
const Mill = preload("res://logic/Mill.gd")
const Kitchen = preload("res://logic/Kitchen.gd")
const Pests = preload("res://logic/Pests.gd")

const TEST_SAVE := "user://test_river.json"
const BANK := Vector2(10, -55.0)         # 川の南の岸のあたり(土地の北の境界の 5m 外)
const NEAR_PLOT := Vector2(10.5, -46.5)  # 川から 20m 以内の区画
const FAR_PLOT := Vector2(10.5, 10.5)    # 土地のまんなかの区画

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_shape()
	_test_water()
	_test_pump()
	_test_paddy()
	_test_rice()
	_test_wilds()
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

func _world(pref := "tokyo", date := "2026-05-20") -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.time.set_today(date)
	if pref != "":
		w.choose_region(pref)
	w.refresh_season()
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birds"
	w.pests.last_day = w.forest.today()
	w.pests.friendship = Pests.FRIEND_MAX  # 荒らされないように
	return w

func _plant(w: GameWorld, pos: Vector2, kind := "rice") -> String:
	w.land.toggle_plot(pos)
	w.garden.seeds[kind] = int(w.garden.seeds.get(kind, 0)) + 1
	return w.garden.sow(pos, kind)

func _test_shape() -> void:
	print("川の形")
	var pts := River.points()
	_check(pts[0].x <= -78.0 and pts[-1].x >= 78.0, "東西の歩ける端まで流れる")
	var all_out := true
	for p in pts:
		if p.y > -50.0 - River.HALF_WIDTH - 3.0 or p.y < -75.0:
			all_out = false
	_check(all_out, "北の境界の外(土地にかからない・外の林の帯の中)")
	_check(River.line_distance(Vector2(0, River.center_y(0))) < 0.01, "中心の線の上は距離 0")
	var legacy := _world("")
	_check(not legacy.river.exists() and legacy.water_source(BANK) == "", "県を選ぶ前は川がない")
	var w := _world()
	_check(w.river.exists(), "県を選ぶと川が現れる")

func _test_water() -> void:
	print("川で汲む")
	var w := _world()
	_check(w.water_source(BANK) == "river", "岸で汲める")
	_check(w.water_source(Vector2(10, River.center_y(10))) == "river", "川の中に立っていても汲める")
	_check(w.water_source(Vector2(10, -45)) == "", "土地の中からは汲めない")
	w.tools.can_water = 0
	_check(w.fill_can(BANK) == "filled" and w.tools.can_water == w.tools.can_size(), "ジョウロを満杯にできる")
	_check(w.fill_can(BANK) == "full", "満杯なら汲まない")
	var winter := _world("hokkaido", "2026-01-15")
	winter.tools.can_water = 0
	_check(winter.water_source(BANK) == "river" and winter.fill_can(BANK) == "filled", "北海道の冬も凍らない")

func _test_pump() -> void:
	print("川からポンプ")
	var w := _world()
	_plant(w, Vector2(10.5, -46.5), "radish")
	_plant(w, Vector2(10.5, -40.5), "radish")
	_plant(w, FAR_PLOT, "radish")
	_check(w.pump(BANK) == "no_pump", "ポンプがなければまとめて水をやれない")
	w.tools.owned.append("pump")
	w.tools.gas = 10
	_check(w.dry_around_source(BANK) == [2, 0], "足元から 20m の区画を数える")
	_check(w.pump(BANK) == "pumped" and w.last_pumped == [2, 0] and w.tools.gas == 5, "20m 以内の区画に水が入る(ガソリン 0.5L)")
	_check(not w.garden.watered_today(w.garden.crop_at(FAR_PLOT)), "遠い区画には届かない")
	_check(w.pests.friendship == Pests.FRIEND_MAX - Pests.MACHINE_LOSS, "ポンプの音で仲良し度が下がる")

func _test_paddy() -> void:
	print("田んぼ")
	var w := _world()
	_check(_plant(w, FAR_PLOT) == "needs_paddy" and int(w.garden.seeds.rice) == 1, "川から遠い区画には田植えできない(苗は減らない)")
	_check(_plant(w, NEAR_PLOT) == "sown", "川から 20m 以内の区画は田んぼになる")
	# 池から水を引く
	w.land.pond = Vector2(10, 20)
	_check(_plant(w, Vector2(10.5, 25.5)) == "needs_paddy", "掘り終える前の池からは引けない")
	w.pond.days_dug = w.pond.DIG_DAYS
	_check(_plant(w, Vector2(10.5, 31.5)) == "sown", "掘り終えた池から 20m 以内なら田んぼになる")
	_check(_world("").garden.grows_here("rice") == false, "県を選ぶ前の今までのルールには米はない")
	for pref in ["hokkaido", "tokyo", "okinawa"]:
		_check(_world(pref).garden.grows_here("rice"), "%s で米を作れる" % pref)
	var winter := _world("tokyo", "2026-01-15")
	_check(_plant(winter, NEAR_PLOT) == "not_season", "冬は田植えできない")
	_check(not Market.good("rice_seed").is_empty() and Garden.CROPS.rice.group == "bean", "稲の苗は市場の豆と穀物のページにある")

func _test_rice() -> void:
	print("米の育ち")
	var w := _world()
	var g := w.garden
	_plant(w, NEAR_PLOT)
	var c: Dictionary = g.crop_at(NEAR_PLOT)
	w.time.shift_days(5)
	_check(is_equal_approx(g.growth_days(c), 1.0), "水をやらないと 1 日 0.2 日ぶんしか育たない(5 日で 1 日ぶん)")
	var w2 := _world()
	_plant(w2, NEAR_PLOT)
	var c2: Dictionary = w2.garden.crop_at(NEAR_PLOT)
	for d in range(7):
		w2.garden.water_at(NEAR_PLOT)
		w2.time.shift_days(1)
	_check(w2.garden.is_ripe(c2), "毎日水をやれば 7 日で実る")
	c2.weeded_day = w2.garden.day_number()
	_check(w2.garden.harvest_at(NEAR_PLOT) == "harvested" and w2.garden.last_harvest_kg == 5 and int(w2.garden.produce.rice) == 5, "米が 5kg 取れる")
	_check(w2.garden.last_straw == Garden.STRAW_PER_GRAIN, "稲わらが取れる")
	_check(Market.SELL_PRICES.rice > 0 and w2.market.sell_all("rice") == 5 * Market.SELL_PRICES.rice, "米は市場で売れる")
	_check(not Mill.FLOURS.has("rice"), "米は石臼では挽かない")
	_check(Kitchen.RECIPES.onigiri.input == "rice" and Kitchen.from_grain("onigiri"), "米でおにぎりを作れる(穀物と粉のページ)")
	# 傷むまでの日数は、実ってからの日数で数える
	var w3 := _world()
	_plant(w3, NEAR_PLOT)
	var c3: Dictionary = w3.garden.crop_at(NEAR_PLOT)
	c3.water_days = 7
	c3.sown_day -= 7
	_check(w3.garden.is_ripe(c3) and w3.garden.days_until_spoiled(c3) == Garden.CROPS.rice.keep_days, "実った日は、傷むまで %d 日" % Garden.CROPS.rice.keep_days)
	w3.time.shift_days(Garden.CROPS.rice.keep_days + 1)
	_check(w3.garden.is_spoiled(c3), "放っておくと傷む")

func _test_wilds() -> void:
	print("外の林と川")
	var w := _world("tokyo")
	var in_river := w.wilds.trees.filter(func(t): return River.line_distance(t.pos) < River.HALF_WIDTH + 1.0)
	_check(w.wilds.trees.size() > 40 and in_river.is_empty(), "外の林の木は川の中に生えない(%d 本)" % w.wilds.trees.size())
