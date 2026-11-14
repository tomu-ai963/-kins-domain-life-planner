extends SceneTree

# 穀物と粉(小麦・ライ麦・ソバ・キビ、石臼・製粉機、粉の料理)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_grain.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Garden = preload("res://logic/Garden.gd")
const Mill = preload("res://logic/Mill.gd")
const Kitchen = preload("res://logic/Kitchen.gd")
const Market = preload("res://logic/Market.gd")

const TEST_SAVE := "user://test_grain.json"
const AT := Vector2(-20, -20)
const GRAINS := ["wheat", "rye", "soba", "kibi"]

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_crops()
	_test_regions()
	_test_quern()
	_test_engine_mill()
	_test_flour_market()
	_test_recipes()
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

func _world(pref := "tokyo", date := "2026-05-10") -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.load_game()
	w.time.set_today(date)
	if pref != "":
		w.choose_region(pref)
	w.refresh_season()
	return w

func _test_crops() -> void:
	print("穀物の作物")
	for g in GRAINS:
		var c: Dictionary = Garden.CROPS[g]
		_check(c.group == "bean" and c.get("grain", false) and Mill.FLOURS.has(g), "%s: 8 キー(豆・穀物)の組で、挽ける穀物" % c.name)
		_check(int(c.grow_days) >= 3 and int(c.grow_days) <= 7 and int(c.yield_kg) > 0, "%s: %d 日で %dkg" % [c.name, c.grow_days, c.yield_kg])
	_check(Garden.CROPS.wheat.get("hardy", false) and Garden.CROPS.rye.get("hardy", false), "小麦とライ麦は霜に強い(秋にまいて冬を越す)")
	_check(not Garden.CROPS.soba.get("hardy", false) and not Garden.CROPS.kibi.get("hardy", false), "ソバとキビは霜で枯れる")
	_check(Garden.CROPS.rye.seasons == ["autumn"], "ライ麦は秋まき")
	_check("spring" in Garden.CROPS.soba.seasons and "summer" in Garden.CROPS.soba.seasons, "ソバは春か夏にまく")

func _test_regions() -> void:
	print("穀物が育つ土地")
	var hk := _world("hokkaido")
	var tk := _world("tokyo")
	var oy := _world("okayama")
	var ok := _world("okinawa")
	for g in GRAINS:
		_check(hk.garden.grows_here(g), "北海道では%sが育つ" % Garden.CROPS[g].name)
	_check(tk.garden.grows_here("rye") and not oy.garden.grows_here("rye"), "ライ麦は東京まで(瀬戸内では作らない)")
	_check(not ok.garden.grows_here("wheat") and not ok.garden.grows_here("soba") and not ok.garden.grows_here("rye"), "沖縄では小麦・ソバ・ライ麦は作らない")
	_check(ok.garden.grows_here("kibi"), "キビは沖縄でも育つ")
	_check(ok.market.sells(Market.good("kibi_seed")) and not ok.market.sells(Market.good("wheat_seed")), "市場には、その土地で育つ穀物の種だけ並ぶ")
	_check(not ok.kitchen.grows_here("udon") and ok.kitchen.grows_here("kibi_dango"), "沖縄のストーブには、きびだんごは並ぶが、うどんは並ばない")
	# 秋にまいた小麦は冬を越す
	var w := _world("tokyo", "2026-11-10")
	w.land.toggle_plot(Vector2(1.5, 1.5))
	w.land.toggle_plot(Vector2(4.5, 1.5))
	w.garden.seeds.wheat = 1
	w.garden.seeds.soba = 1
	_check(w.garden.sow(Vector2(1.5, 1.5), "wheat") == "sown", "秋に小麦をまける")
	_check(w.garden.sow(Vector2(4.5, 1.5), "soba") == "not_season", "秋にはソバはまけない")

func _quern_world() -> GameWorld:
	var w := _world()
	w.tools.receive("quern")
	w.mill_action(AT, AT)
	return w

func _test_quern() -> void:
	print("石臼で手で挽く")
	var w := _world()
	var m := w.mill
	_check(w.mill_action(AT, AT) == "no_quern" and not m.is_placed(), "石臼を買うまでは置けない")
	w.tools.receive("quern")
	w.land.toggle_plot(Vector2(1.5, 1.5))
	_check(w.mill_action(Vector2(1.5, 1.5), Vector2(1.5, 1.5)) == "blocked", "区画の上には置けない")
	_check(w.mill_action(AT, AT) == "placed" and m.site == AT, "O で体の前に置く")
	_check(w.toggle_plot(AT + Vector2(0.5, 0)) == "mill", "石臼にかかる場所には区画を作れない")
	_check(w.bees.is_blocked(AT + Vector2(1.0, 0)), "石臼のそばには巣箱や井戸を置けない")
	_check(w.mill_action(AT + Vector2(1, 0), AT) == "no_grain", "穀物がなければ挽けない")
	w.garden.produce.wheat = 4
	w.garden.produce.rye = 3
	_check(w.mill_action(AT + Vector2(10, 0), AT) == "far", "離れていると挽けない")
	_check(w.mill_action(AT + Vector2(1, 0), AT) == "ground" and m.flour.wheat == 1 and w.garden.produce.wheat == 3, "手で 1 回 1kg 挽く(小麦 1kg → 小麦粉 1kg)")
	_check(w.mill_action(AT + Vector2(1, 0), AT, "rye") == "ground" and m.flour.rye == 1 and w.garden.produce.rye == 2, "選んでいる穀物を先に挽く")
	for i in range(3):
		w.mill_action(AT + Vector2(1, 0), AT)
	_check(m.hand_left() == 0 and m.flour.wheat + m.flour.rye == Mill.HAND_KG_PER_DAY, "手で挽けるのは 1 日 5kg まで")
	_check(w.mill_action(AT + Vector2(1, 0), AT) == "tired" and w.mill.total_grain() == 2, "6 回目は腕が疲れて挽けない")
	m.hand_day = "2000-01-01"
	_check(m.hand_left() == Mill.HAND_KG_PER_DAY, "次の日はまた 5kg 挽ける")
	_check(w.mill_action(Vector2(30, 30), Vector2(30, 30)) == "far", "石臼はひとつ(離れた場所で O を押しても置かない)")

func _test_engine_mill() -> void:
	print("製粉機")
	var w := _quern_world()
	var m := w.mill
	var t := w.tools
	w.garden.produce.wheat = 4
	w.garden.produce.soba = 2
	t.receive("mill")
	_check(w.mill_action(AT + Vector2(1, 0), AT) == "ground", "ガソリンがなければ手で挽く")
	t.receive("gasoline", 50)
	_check(w.mill_action(AT + Vector2(1, 0), AT) == "engine" and m.flour.wheat == 4 and m.flour.soba == 2 and m.total_grain() == 0, "製粉機は持っている穀物を全部挽く")
	_check(t.gas == 45 and t.last_machine == "mill", "ガソリン 0.5L を使う")
	_check(m.hand_left() == Mill.HAND_KG_PER_DAY - 1, "製粉機は手で挽ける量を減らさない")
	_check(w.mill_action(AT + Vector2(1, 0), AT) == "no_grain" and t.gas == 45, "穀物がなければ動かさない(ガソリンは減らない)")

func _test_flour_market() -> void:
	print("市場")
	var w := _world()
	var m := w.market
	m.money = 20000
	_check(m.buy("quern") == "bought" and w.tools.has("quern") and m.money == 18000, "石臼を 2,000₽ で買える")
	_check(m.buy("quern") == "owned", "石臼はひとつ")
	_check(m.buy("mill") == "bought" and w.tools.has("mill") and m.money == 10000, "製粉機を 8,000₽ で買える")
	_check(m.buy("wheat_seed") == "bought" and w.garden.seeds.wheat == 1, "小麦の種もみを買える")
	w.mill.flour.wheat = 3
	w.garden.produce.wheat = 2
	var before: int = m.money
	_check(m.sell_all("flour_wheat") == 3 * 60 and w.mill.flour.wheat == 0 and m.money == before + 180, "小麦粉を売れる(1kg 60₽)")
	_check(m.sell_all("wheat") == 2 * 40, "小麦も売れる(1kg 40₽)")
	for g in GRAINS:
		_check(Market.SELL_PRICES["flour_" + g] > Market.SELL_PRICES[g], "%sは穀物より高く売れる" % Mill.FLOURS[g].name)

func _test_recipes() -> void:
	print("粉の料理")
	var w := _world()
	var k := w.kitchen
	k.firewood = 10
	_check(k.start("rye_bread") == "no_input", "ライ麦粉がなければライ麦パンは焼けない")
	w.mill.flour.rye = 3
	_check(k.input_count("rye_bread") == 3, "材料の数は粉の持ち物から数える")
	_check(k.start("rye_bread") == "started" and w.mill.flour.rye == 1, "ライ麦粉 2kg でライ麦パンを仕込む")
	k.pot = {}
	w.garden.produce.soba = 1
	_check(k.start("kasha") == "started" and w.garden.produce.soba == 0, "カーシャはそばの実(粉にしない)を使う")
	for id in ["rye_bread", "bliny", "udon", "soba_noodle", "kibi_dango", "kasha"]:
		_check(Kitchen.from_grain(id) and not Kitchen.from_tree(id), "%s は「穀物と粉」のページ" % Kitchen.RECIPES[id].name)
	_check(not Kitchen.from_grain("pirozhki") and not Kitchen.from_grain("zunda"), "ピロシキ・ずんだ餅は今までのページのまま")
	# 料理の値段は材料を売るよりおよそ 2 倍(今までと同じ置き方)
	for id in ["rye_bread", "bliny", "udon", "soba_noodle", "kibi_dango", "kasha"]:
		var r: Dictionary = Kitchen.RECIPES[id]
		var raw: int = int(Market.SELL_PRICES[r.input]) * int(r.amount)
		var made: int = int(Market.SELL_PRICES[id]) * int(r.output)
		_check(made >= raw * 1.8 and made <= raw * 2.2, "%s: 材料 %d₽ → %d₽" % [r.name, raw, made])

func _test_save() -> void:
	print("セーブ")
	var w := _quern_world()
	w.mill.flour.soba = 7
	w.mill.hand_day = w.forest.today()
	w.mill.hand_kg = 3
	w.save_game()
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	w2.time.set_today("2026-05-10")  # 保存したときと同じ日
	_check(w2.mill.site == AT and w2.mill.flour.soba == 7 and w2.mill.hand_left() == 2, "石臼の場所・粉・今日手で挽いた量が戻る")
	var old := Mill.new()
	old.from_save({})
	_check(not old.is_placed() and old.flour.wheat == 0, "石臼の記録がないセーブは、石臼なし・粉なし")
	var bad := Mill.new()
	bad.from_save({"flour": {"wheat": -3, "rice": 5}, "hand_kg": 99})
	_check(bad.flour.wheat == 0 and not bad.flour.has("rice") and bad.hand_kg == Mill.HAND_KG_PER_DAY, "読めない値は範囲に収め、知らない粉は捨てる")
