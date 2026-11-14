extends SceneTree

# 水と道具(井戸・ジョウロ・斧・エンジンポンプ・チェーンソー・薪割り機・ガソリン)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_water_tools.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Forest = preload("res://logic/Forest.gd")
const Well = preload("res://logic/Well.gd")
const Tools = preload("res://logic/Tools.gd")
const Market = preload("res://logic/Market.gd")

const TEST_SAVE := "user://test_water_tools.json"
const WELL_AT := Vector2(-20, -20)

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_well_dig()
	_test_well_blocks()
	_test_can()
	_test_pump()
	_test_axe_and_chainsaw()
	_test_splitter()
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

func _world() -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.forest.season = "spring"  # ラディッシュをまける季節
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birds"
	return w

# 井戸を掘り終えた状態にする
func _dug_well(w: GameWorld, at := WELL_AT) -> void:
	w.well.site = at
	w.well.days_dug = Well.DIG_DAYS

# 区画を作って種をまく(水がいる状態)
func _crop(w: GameWorld, pos: Vector2) -> Dictionary:
	w.land.toggle_plot(pos)
	w.garden.seeds.radish = int(w.garden.seeds.get("radish", 0)) + 1
	w.garden.sow(pos, "radish")
	return w.garden.crop_at(pos)

# 丸太になる白樺(樹齢 20 年)を植える
func _big_tree(w: GameWorld, pos: Vector2) -> void:
	w.forest.saplings.birch = int(w.forest.saplings.get("birch", 0)) + 1
	w.forest.add_tree(pos, "birch", "sapling")
	w.forest.trees[-1].start_age = 20.0

func _test_well_dig() -> void:
	print("井戸を掘る")
	var w := _world()
	var well := w.well
	_check(not well.is_placed() and w.water_source(WELL_AT) == "", "はじめは井戸がない")
	_check(w.well_action(WELL_AT, WELL_AT) == "placed" and well.site == WELL_AT, "I で前に場所を決める")
	_check(w.water_source(WELL_AT + Vector2(1.5, 0)) == "", "場所を決めただけでは汲めない")
	_check(w.well_action(WELL_AT + Vector2(10, 0), WELL_AT) == "far", "離れていると掘れない")
	_check(w.well_action(WELL_AT + Vector2(1.5, 0), WELL_AT) == "dug" and well.days_dug == 1, "そばで I を押すと 1 日分掘る")
	_check(w.well_action(WELL_AT + Vector2(1.5, 0), WELL_AT) == "done_today", "1 日 1 回まで")
	_check(not well.cancel(WELL_AT + Vector2(1.5, 0)), "掘りはじめたら取り消せない")
	for d in range(1, Well.DIG_DAYS):
		well.last_dug = "2000-01-%02d" % d  # 前の日に掘ったことにする
		var r: String = w.well_action(WELL_AT + Vector2(1.5, 0), WELL_AT)
		_check(r == ("finished" if d == Well.DIG_DAYS - 1 else "dug"), "%d 日目: %s" % [d + 1, r])
	_check(well.is_dug() and Well.DIG_DAYS == 3, "3 日で掘り終える")
	_check(w.water_source(WELL_AT + Vector2(1.5, 0)) == "well", "掘り終えると、そばで汲める")
	_check(w.water_source(WELL_AT + Vector2(3.0, 0)) == "", "縁から 2m より離れると汲めない")
	_check(w.well_action(WELL_AT + Vector2(1.5, 0), WELL_AT) == "already", "掘り終えたら、もう掘らない")
	_check(w.well_action(Vector2(10, 10), Vector2(10, 10)) == "far", "井戸はひとつまで")
	w.forest.season = "winter"
	_check(w.water_source(WELL_AT + Vector2(1.5, 0)) == "well", "冬も凍らない")
	# 掘る前なら取り消せる
	var w2 := _world()
	w2.well_action(WELL_AT, WELL_AT)
	_check(w2.well.cancel(WELL_AT + Vector2(1, 0)) and not w2.well.is_placed(), "掘る前なら Z で取り消せる")

func _test_well_blocks() -> void:
	print("井戸を置ける場所")
	var w := _world()
	w.land.toggle_plot(Vector2(1.5, 1.5))
	_check(w.well_action(Vector2(1.5, 1.5), Vector2(1.5, 1.5)) == "blocked", "区画の上には掘れない")
	w.land.pond = Vector2(20, 20)
	_check(w.well_action(Vector2(20, 25), Vector2(20, 24)) == "blocked", "池のそばには掘れない")
	_check(w.well_action(Vector2(0, 49), Vector2(0, 49)) == "blocked", "土地の端には掘れない")
	_big_tree(w, Vector2(-10, 10))
	_check(w.well_action(Vector2(-10, 10.5), Vector2(-10, 10.5)) == "blocked", "木のそばには掘れない")
	_check(w.well_action(WELL_AT, WELL_AT) == "placed", "空いている場所には掘れる")
	# 井戸のまわりには、ほかの物を置けない
	_check(w.toggle_plot(WELL_AT + Vector2(1.0, 0)) == "well", "井戸にかかる場所には区画を作れない")
	var w2 := _world()
	w2.well_action(WELL_AT, WELL_AT)
	_check(w2.pond_action(WELL_AT + Vector2(3, 0)) == "well", "井戸にかかる場所には池を掘れない")
	_check(w.well.covers(WELL_AT + Vector2(1.5, 0), w.bees.CLEARANCE), "井戸の近くには木を植えない")
	_check(w.bees.is_blocked(WELL_AT + Vector2(1.5, 0)), "井戸のそばには巣箱や餌台を置けない")
	_check(not w.well.covers(WELL_AT + Vector2(4, 0), w.bees.CLEARANCE), "離れていれば植えられる")

func _test_can() -> void:
	print("ジョウロ")
	var w := _world()
	var t := w.tools
	_check(t.can_size() == 5 and t.can_water == 5, "はじめは 5L のジョウロが満杯")
	var crops := []
	for i in range(6):
		crops.append(_crop(w, Vector2(1.5 + 3.0 * i, 10.5)))
	for i in range(5):
		_check(w.water_plot(crops[i].pos) == "watered", "%d か所目に水をやれる" % (i + 1))
	_check(t.can_water == 0, "5 か所で空になる")
	_check(w.water_plot(crops[5].pos) == "can_empty" and not w.garden.watered_today(crops[5]), "空なら水をやれない")
	_check(w.water_plot(crops[0].pos) == "done", "今日もう水をやった区画は、空でも「済んだ」")
	_big_tree(w, Vector2(10, -10))
	_check(w.water_tree(Vector2(10.5, -10), 2.0) == "can_empty", "木も、空なら水をやれない")
	_check(w.water_tree(Vector2(30, 30), 2.0) == "none", "近くに木がなければ none")
	# 汲む
	_check(w.fill_can(WELL_AT) == "far", "井戸も池もなければ汲めない")
	_dug_well(w)
	_check(w.fill_can(WELL_AT + Vector2(1.5, 0)) == "filled" and t.can_water == 5, "井戸のそばで満杯まで汲む")
	_check(w.fill_can(WELL_AT + Vector2(1.5, 0)) == "full", "満杯なら汲まない")
	_check(w.water_tree(Vector2(10.5, -10), 2.0) == "watered" and t.can_water == 4, "木にも 1L で水をやれる")
	# 池から汲む
	var w2 := _world()
	w2.land.pond = Vector2(20, 20)
	w2.pond.days_dug = w2.pond.DIG_DAYS
	w2.pond.water = 50
	w2.tools.can_water = 0
	var shore := Vector2(20, 25)
	_check(w2.fill_can(shore) == "filled" and w2.tools.can_water == 5 and w2.pond.water == 50, "池からも汲める(池の水は減らない)")
	w2.tools.can_water = 0
	w2.pond.water = 0
	_check(w2.fill_can(shore) == "empty", "池に水がなければ汲めない")
	w2.pond.water = 50
	w2.forest.season = "winter"
	_check(w2.pond.is_frozen() and w2.fill_can(shore) == "frozen", "凍った池からは汲めない")
	# 雨の日は、ジョウロを使わずに全部に水が入る
	var w3 := _world()
	var c3 := _crop(w3, Vector2(1.5, 1.5))
	w3.garden.water_all()
	_check(w3.garden.watered_today(c3) and w3.tools.can_water == 5, "雨はジョウロの水を使わない")
	# 10L のジョウロ
	t.receive("big_can")
	_check(t.can_size() == 10 and t.can_water == 10, "10L のジョウロを買うと、1 杯で 10 か所")

func _test_pump() -> void:
	print("エンジンポンプ")
	var w := _world()
	var t := w.tools
	_dug_well(w)
	var near := _crop(w, WELL_AT + Vector2(0, 10.5))
	var far := _crop(w, WELL_AT + Vector2(0, -25.5))
	_big_tree(w, WELL_AT + Vector2(10, 0))
	var at := WELL_AT + Vector2(1.5, 0)
	_check(w.dry_around_source(at) == [1, 1], "井戸から 20m 以内の、水のいる区画と木を数える")
	_check(w.pump(at) == "no_pump", "ポンプがなければ、まとめて水やりはできない")
	t.receive("pump")
	_check(w.pump(at) == "no_gas", "ガソリンがなければ動かない")
	t.receive("gasoline", 50)
	_check(w.pump(at) == "pumped" and w.last_pumped == [1, 1], "井戸から区画 1・木 1 にまとめて水やり")
	_check(t.gas == 45, "ガソリンを 0.5L 使う")
	_check(w.garden.watered_today(near) and not w.garden.watered_today(far), "20m の外には入らない")
	_check(t.can_water == 5, "ジョウロの水は使わない")
	_check(w.pump(at) == "nothing" and t.gas == 45, "水のいるものがなければ、ガソリンは減らない")
	_check(w.pump(Vector2(30, 30)) == "far", "離れていれば使えない")
	# 池から
	var w2 := _world()
	w2.land.pond = Vector2(20, 20)
	w2.pond.days_dug = w2.pond.DIG_DAYS
	w2.pond.water = 100
	w2.tools.receive("pump")
	w2.tools.receive("gasoline", 50)
	_crop(w2, Vector2(20.5 + 1.0, 30.5))
	_check(w2.pump(Vector2(20, 25)) == "pumped" and w2.pond.water == 95 and w2.tools.gas == 45, "池からも使える(池の水 5% とガソリン 0.5L)")
	_crop(w2, Vector2(14.5, 30.5))
	w2.pond.water = 4
	_check(w2.pump(Vector2(20, 25)) == "low" and w2.tools.gas == 45, "池の水が足りなければ使えない")
	w2.pond.water = 50
	w2.forest.season = "winter"
	_check(w2.pump(Vector2(20, 25)) == "frozen", "凍った池では使えない")

func _test_axe_and_chainsaw() -> void:
	print("斧とチェーンソー")
	var w := _world()
	var t := w.tools
	for i in range(5):
		_big_tree(w, Vector2(5.0 * i, 30))
	for i in range(3):
		_check(not w.axe_tired_for(Vector2(5.0 * i, 30.5), 2.0) and w.fell(Vector2(5.0 * i, 30.5), 2.0) == 2, "斧で %d 本目を伐る(丸太 2 本)" % (i + 1))
	_check(t.axe_left() == 0, "斧は 1 日 3 本まで")
	_check(w.axe_tired_for(Vector2(15, 30.5), 2.0), "4 本目は伐る前に分かる")
	_check(w.fell(Vector2(15, 30.5), 2.0) == -2 and w.forest.trees.size() == 2, "4 本目は伐れない(木は残る)")
	# 細い木は手で抜くので数えない
	w.forest.saplings.birch = 1
	w.forest.add_tree(Vector2(-10, 30), "birch", "sapling")
	_check(not w.axe_tired_for(Vector2(-10, 30.5), 2.0) and w.fell(Vector2(-10, 30.5), 2.0) == 0, "丸太にならない若木は、斧の数に関係なく抜ける")
	# 次の日はまた 3 本
	t.axe_day = "2000-01-01"
	_check(t.axe_left() == 3, "次の日はまた 3 本伐れる")
	t.axe_count = 3
	t.axe_day = w.forest.today()
	# チェーンソー
	t.receive("chainsaw")
	_check(w.axe_tired_for(Vector2(15, 30.5), 2.0), "ガソリンがなければチェーンソーは動かない")
	t.receive("gasoline", 4)
	_check(not w.axe_tired_for(Vector2(15, 30.5), 2.0) and w.fell(Vector2(15, 30.5), 2.0) == 2 and t.last_machine == "chainsaw", "チェーンソーなら斧の上限のあとも伐れる")
	_check(t.gas == 2, "1 本でガソリン 0.2L")
	_check(w.fell(Vector2(20, 30.5), 2.0) == 2 and t.gas == 0, "ガソリンがある限り何本でも")

func _test_splitter() -> void:
	print("薪割り機")
	var w := _world()
	var k := w.kitchen
	var t := w.tools
	w.cabin.materials.log = 6
	_check(w.split_wood() == "split" and k.firewood == k.SPLIT_FIRES and t.last_machine == "", "薪割り機がなければ、斧で 1 回(2 回分)")
	t.receive("splitter")
	_check(w.split_wood() == "split" and k.firewood == k.SPLIT_FIRES * 2 and t.last_machine == "", "ガソリンがなければ、斧で 1 回")
	t.receive("gasoline", 10)
	_check(w.split_wood() == "split" and k.firewood == k.MAX_FIREWOOD and t.last_machine == "splitter", "薪割り機は、積める量まで一度に割る")
	_check(t.gas == 5 and int(w.cabin.materials.log) == 2, "ガソリン 0.5L・丸太 4 本(40 回分)を使った")
	_check(w.split_wood() == "full" and t.gas == 5, "いっぱいなら動かさない(ガソリンは減らない)")
	k.firewood = 0
	w.cabin.materials.log = 0
	k.log_left = 0
	_check(w.split_wood() == "no_log" and t.gas == 5, "丸太がなければ動かさない")

func _test_market() -> void:
	print("市場で道具とガソリンを買う")
	var w := _world()
	var m := w.market
	var t := w.tools
	m.money = 50000
	for id in ["big_can", "pump", "chainsaw", "splitter"]:
		var g: Dictionary = Market.good(id)
		var before: int = m.money
		_check(m.buy(id) == "bought" and t.has(id) and m.money == before - int(g.price), "%s を買える(%d₽)" % [id, g.price])
		_check(m.buy(id) == "owned" and m.is_owned(g), "%s はひとつずつ" % id)
	_check(Market.good("big_can").price < Market.good("pump").price, "10L のジョウロは安い")
	for i in range(4):
		_check(m.buy("gasoline") == "bought" and t.gas == 50 * (i + 1), "ガソリンを 5L ずつ買える(%d 回目)" % (i + 1))
	_check(m.buy("gasoline") == "full" and t.gas == Tools.MAX_GAS, "20L より多くは持てない")
	m.money = 100
	t.gas = 0
	_check(m.buy("gasoline") == "no_money", "お金が足りなければ買えない")

func _test_save() -> void:
	print("セーブ")
	var w := _world()
	w.well_action(WELL_AT, WELL_AT)
	w.well.days_dug = 2
	w.well.last_dug = "2026-11-13"
	w.tools.receive("pump")
	w.tools.receive("gasoline", 37)
	w.tools.can_water = 3
	w.tools.axe_day = w.forest.today()
	w.tools.axe_count = 2
	w.save_game()
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	_check(w2.well.site == WELL_AT and w2.well.days_dug == 2 and w2.well.last_dug == "2026-11-13", "井戸の場所と掘った日数が戻る")
	_check(w2.tools.has("pump") and w2.tools.gas == 37 and w2.tools.can_water == 3, "道具・ガソリン・ジョウロの水が戻る")
	_check(w2.tools.axe_left() == 1, "今日斧で伐った本数も戻る")
	# 記録がない古いセーブ
	var old := Tools.new()
	old.from_save({})
	_check(old.can_water == 5 and old.owned.is_empty() and old.gas == 0, "道具の記録がないセーブは、5L のジョウロが満杯・機械なし")
	var old_well := Well.new()
	old_well.from_save({})
	_check(not old_well.is_placed(), "井戸の記録がないセーブは、井戸なし")
	# 壊れた値
	var bad := Tools.new()
	bad.from_save({"can_water": 99, "gas": -5, "owned": ["pump", "rocket", "pump"]})
	_check(bad.can_water == 5 and bad.gas == 0 and bad.owned == ["pump"], "読めない値は範囲に収め、知らない道具は捨てる")
