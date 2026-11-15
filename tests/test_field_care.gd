extends SceneTree

# 畑を守る(雑草とわら、畑を荒らす生き物と仲良し度)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_field_care.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Garden = preload("res://logic/Garden.gd")
const Pests = preload("res://logic/Pests.gd")
const Feeders = preload("res://logic/Feeders.gd")
const Market = preload("res://logic/Market.gd")
const Wildlife = preload("res://logic/Wildlife.gd")

const TEST_SAVE := "user://test_field_care.json"
const AT := Vector2(-19.5, -19.5)
const FEEDER_AT := Vector2(20, -20)

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_weeds()
	_test_mulch()
	_test_species()
	_test_raids()
	_test_friendship()
	_test_offer()
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

func _world(pref := "") -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.time.set_today("2026-05-10")
	if pref != "":
		w.choose_region(pref)
	w.refresh_season()
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birds"
	w.pests.last_day = w.forest.today()
	return w

# 区画を作って kind をまく
func _crop(w: GameWorld, pos: Vector2, kind := "radish") -> Dictionary:
	w.land.toggle_plot(pos)
	w.garden.seeds[kind] = int(w.garden.seeds.get(kind, 0)) + 1
	w.garden.sow(pos, kind)
	return w.garden.crop_at(pos)

# 日付を進める(日替わりの確認もする)
func _next_day(w: GameWorld, days := 1) -> void:
	w.time.shift_days(days)
	w.check_new_day()

func _test_weeds() -> void:
	print("雑草")
	var w := _world("tokyo")
	var g := w.garden
	var c := _crop(w, AT, "daikon")
	_check(not g.has_weeds(c) and g.weed_loss(c) == 0.0, "まいたばかりは生えていない")
	w.pests.friendship = Pests.FRIEND_MAX  # 荒らされないように
	w.time.shift_days(Garden.WEED_FREE_DAYS)
	_check(not g.has_weeds(c), "%d 日目まではまだ生えない" % Garden.WEED_FREE_DAYS)
	w.time.shift_days(1)
	_check(g.has_weeds(c) and is_equal_approx(g.weed_loss(c), 0.1), "その次の日に生え、収量 -10%")
	_check(g.weedy_count() == 1, "生えている区画を数える")
	_check(g.weed_at(AT) == "weeded" and not g.has_weeds(c), "E で抜く")
	_check(g.weed_at(AT) == "no_weeds", "生えていなければ抜けない")
	_check(is_equal_approx(g.weed_loss(c), 0.1), "それまでに減った分は戻らない")
	w.time.shift_days(Garden.WEED_FREE_DAYS + 2)
	_check(is_equal_approx(g.weed_loss(c), 0.3), "また生え、減り方は足される")
	w.time.shift_days(20)
	_check(is_equal_approx(g.weed_loss(c), Garden.WEED_MAX_LOSS), "減るのは半分まで(枯れない)")
	_check(g.harvest_at(AT) == "harvested" and g.last_weed_loss == 50, "収穫した量に効く(-50%)")
	_check(g.last_harvest_kg < int(Garden.CROPS.daikon.yield_kg), "雑草があると少なくなる(%dkg)" % g.last_harvest_kg)
	# 抜いた区画は今までどおりの量
	var w2 := _world("tokyo")
	var c2 := _crop(w2, AT, "radish")
	c2.sown_day -= 6
	c2.weeded_day = w2.garden.day_number()
	_check(w2.garden.harvest_at(AT) == "harvested" and w2.garden.last_harvest_kg == 6 and w2.garden.last_weed_loss == 0, "雑草がなければ今までどおり(ラディッシュ 6kg)")

func _test_mulch() -> void:
	print("わら")
	var w := _world("tokyo")
	var g := w.garden
	var c := _crop(w, AT, "daikon")
	_check(g.straw == 0 and g.mulch_at(AT) == "no_straw", "わらがなければ敷けない")
	_check(w.market.buy("straw") == "bought" and g.straw == 5 and w.market.money == Market.INITIAL_MONEY - 150, "市場でわら 5 束を 150₽ で買える")
	_check(g.mulch_at(AT) == "mulched" and g.straw == 4 and c.mulched, "E でわらを敷く(1 束)")
	_check(g.mulch_at(AT) == "already" and g.straw == 4, "2 度は敷かない")
	w.time.shift_days(30)
	_check(not g.has_weeds(c) and g.weed_loss(c) == 0.0, "わらを敷いた区画には生えない")
	# 穀物を収穫すると、わらが取れる
	var wheat := _crop(w, AT + Vector2(6, 0), "wheat")
	wheat.sown_day -= 20
	wheat.weeded_day = g.day_number()
	_check(g.harvest_at(AT + Vector2(6, 0)) == "harvested" and g.last_straw == Garden.STRAW_PER_GRAIN and g.straw == 4 + Garden.STRAW_PER_GRAIN, "穀物を収穫するとわら +2 束")
	var radish := _crop(w, AT + Vector2(12, 0), "radish")
	radish.sown_day -= 20
	_check(g.harvest_at(AT + Vector2(12, 0)) == "harvested" and g.last_straw == 0, "野菜からはわらは取れない")
	_check(not Market.good("straw").is_empty() and Market.good("straw").form == "straw", "市場の品にわらがある")

func _test_species() -> void:
	print("畑を荒らす生き物")
	var legacy := _world()
	_check(not legacy.wildlife.lives_here("crow") and not legacy.wildlife.lives_here("boar"), "県を選ぶ前の今までのルールには出てこない")
	for pref in ["tokyo", "okinawa", "hokkaido"]:
		var w := _world(pref)
		_check(w.wildlife.lives_here("crow"), "%s: カラスはどこにでもいる" % pref)
	_check(_world("tokyo").wildlife.lives_here("boar") and not _world("tokyo").wildlife.lives_here("ezo_deer"), "東京: イノシシ(エゾシカはいない)")
	_check(_world("okinawa").wildlife.lives_here("boar"), "沖縄: リュウキュウイノシシ")
	_check(_world("hokkaido").wildlife.lives_here("ezo_deer") and not _world("hokkaido").wildlife.lives_here("boar"), "北海道: エゾシカ(イノシシはいない)")
	for id in Pests.PESTS:
		_check(Wildlife.SPECIES.has(id), "%s は生き物の一覧にある" % id)
	# 来る条件
	var w := _world("tokyo")
	_check(w.pests.present().is_empty(), "畑がなければ荒らす生き物は来ない")
	for i in range(4):
		_crop(w, AT + Vector2(i * 3, 0))
	_check("crow" in w.pests.present() and "hare" in w.pests.present(), "4 区画あるとカラスとノウサギが来る")
	_check(not ("boar" in w.pests.present()), "イノシシは区画 12 から")
	for i in range(8):
		w.land.toggle_plot(AT + Vector2(i * 3, 6))
	_check("boar" in w.pests.present(), "区画 12 でイノシシが来る")

# 畑を荒らされる日を探す(仲良し度 0)。見つかった日の last_damage を返す
func _raid_world(pref: String) -> GameWorld:
	var w := _world(pref)
	for i in range(12):
		_crop(w, AT + Vector2((i % 6) * 3, (i / 6) * 3), ["cabbage", "daikon", "eggplant", "edamame", "potato", "corn"][i % 6])
	return w

func _test_raids() -> void:
	print("夜のあいだの食害")
	var w := _raid_world("tokyo")
	var p := w.pests
	var before: int = w.garden.crops.size()
	var nights := 0
	var damaged := 0
	for d in range(30):
		p.friendship = 0
		_next_day(w)
		nights += 1
		damaged += p.last_damage.size()
		if damaged >= 3:
			break
	_check(damaged > 0, "仲良し度 0 だと、何晩かのうちに荒らされる(%d 晩で %d 件)" % [nights, damaged])
	_check(w.garden.crops.size() <= before, "荒らされた区画は収量が減るか、空く")
	var kinds_ok := true
	for d in p.last_damage:
		if not (Garden.CROPS[d.kind].group in Pests.PESTS[d.id].groups):
			kinds_ok = false
	_check(kinds_ok, "その生き物が食べる組の野菜だけ荒らす")
	# 同じ日付なら同じ結果(開き直しても変わらない)
	var a := _raid_world("tokyo")
	var b := _raid_world("tokyo")
	a.pests.friendship = 0
	b.pests.friendship = 0
	for i in range(5):
		_next_day(a)
		_next_day(b)
		a.pests.friendship = 0
		b.pests.friendship = 0
	_check(a.garden.crops.size() == b.garden.crops.size(), "荒らすかどうかは日付で決まる")
	# 仲良し度が FRIEND_SAFE 以上なら荒らさない
	var safe := _raid_world("tokyo")
	var none := 0
	for d in range(30):
		safe.pests.friendship = Pests.FRIEND_SAFE
		_next_day(safe)
		none += safe.pests.last_damage.size()
	_check(none == 0 and safe.garden.crops.size() == 12, "仲良し度 %d 以上なら 30 晩たっても荒らさない" % Pests.FRIEND_SAFE)
	# かじる / 掘り返す
	var g := w.garden
	var c := _crop(w, Vector2(30, 30), "cabbage")
	_check(not g.bite(c) and c.bites == 1, "1 回かじられても残る")
	_check(not g.bite(c) and g.bite(c) == true and g.crop_at(Vector2(30, 30)).is_empty(), "3 回かじられると食べ尽くされる")
	var c2 := _crop(w, Vector2(36, 30), "cabbage")
	c2.sown_day -= 14
	g.bite(c2)
	_check(g.harvest_at(Vector2(36, 30)) == "harvested" and g.last_bitten and g.last_harvest_kg == ceili(Garden.CROPS.cabbage.yield_kg * 0.5), "かじられた区画の収量は半分")
	_check(Pests.PESTS.boar.dig and Pests.PESTS.ezo_deer.dig and not Pests.PESTS.hare.dig, "イノシシとエゾシカは掘り返す")

func _test_friendship() -> void:
	print("仲良し度")
	var w := _world("tokyo")
	var p := w.pests
	_check(p.friendship == Pests.FRIEND_START, "はじめは %d" % Pests.FRIEND_START)
	_next_day(w)
	_check(p.friendship == Pests.FRIEND_START - Pests.DAILY_FADE, "1 日で %d 下がる" % Pests.DAILY_FADE)
	_next_day(w, 3)
	_check(p.friendship == Pests.FRIEND_START - 4, "閉じていた日数ぶん下がる")
	p.friendship = 50
	w.tools.owned.append("chainsaw")
	w.tools.gas = 100
	w.tools.use_gas("chainsaw")
	_check(p.friendship == 50 - Pests.MACHINE_LOSS, "チェーンソーの音で %d 下がる" % Pests.MACHINE_LOSS)
	w.tools.use_gas("chainsaw")
	_check(p.friendship == 50 - Pests.MACHINE_LOSS, "同じ機械は 1 日 1 回だけ下がる")
	w.tools.owned.append("pump")
	w.tools.use_gas("pump")
	_check(p.friendship == 50 - Pests.MACHINE_LOSS * 2, "ほかの機械はまた下がる")
	p.friendship = 0
	_next_day(w)
	_check(p.friendship == 0, "0 より下がらない")
	p.friendship = 99
	p.befriend(Vector2(1, 1))
	_check(p.friendship == Pests.FRIEND_MAX, "%d より上がらない" % Pests.FRIEND_MAX)

func _test_offer() -> void:
	print("餌台に野菜を置く")
	var w := _world("tokyo")  # 5 月(春)
	var fd := w.feeders
	var p := w.pests
	w.cabin.materials.log = 2
	_check(w.feeder_action(FEEDER_AT, FEEDER_AT) == "placed", "餌台を立てる")
	_check(w.feeder_action(FEEDER_AT) == "not_season" and p.friendship == Pests.FRIEND_START, "春に野菜がなければ置けない")
	w.garden.produce.cabbage = 3
	w.garden.produce.daikon = 10
	_check(w.feeder_action(FEEDER_AT, null, "cabbage") == "offered" and fd.last_offered == "cabbage" and w.garden.produce.cabbage == 2, "選んでいる野菜を 1kg 置く")
	_check(p.friendship == Pests.FRIEND_START + Pests.FEED_GAIN and p.last_gain == Pests.FEED_GAIN, "仲良し度 +%d" % Pests.FEED_GAIN)
	_check(w.feeder_action(FEEDER_AT, null, "cabbage") == "full" and p.friendship == Pests.FRIEND_START + Pests.FEED_GAIN, "同じ餌台は 1 日 1 回")
	w.time.shift_days(1)
	_check(w.feeder_action(FEEDER_AT, null, "tomato") == "offered" and fd.last_offered == "daikon" and w.garden.produce.daikon == 9, "選んでいる野菜がなければ、いちばん多い野菜")
	_check(p.friendship == Pests.FRIEND_START + Pests.FEED_GAIN * 2, "次の日はまた上がる")
	# 秋と冬は種が先、種がなければ野菜
	w.forest.season = "autumn"
	w.time.shift_days(1)
	var sp: String = fd.feed_species()
	w.forest.seeds[sp] = Feeders.FEED_SEEDS
	_check(w.feeder_action(FEEDER_AT) == "fed" and int(w.forest.seeds[sp]) == 0, "秋は種を置く")
	w.time.shift_days(1)
	_check(w.feeder_action(FEEDER_AT) == "offered", "種がなければ野菜を置く")
	w.time.shift_days(1)
	w.garden.produce = Garden._zero_counts()
	_check(w.feeder_action(FEEDER_AT) == "no_seed", "秋に種も野菜もなければ no_seed")

func _test_save() -> void:
	print("セーブ")
	var w := _world("tokyo")
	var c := _crop(w, AT, "daikon")
	c.weed_days = 2
	c.weeded_day -= 5
	c.bites = 1
	w.garden.straw = 7
	_crop(w, AT + Vector2(6, 0), "cabbage")
	w.garden.mulch_at(AT + Vector2(6, 0))
	w.pests.friendship = 63
	w.pests.on_machine("mill")
	w.save_game()
	var r := GameWorld.new()
	r.save_path = TEST_SAVE
	r.time.set_today("2026-05-10")
	r.load_game()
	var rc: Dictionary = r.garden.crop_at(AT)
	_check(int(rc.weed_days) == 2 and r.garden.weeds_now(rc) == w.garden.weeds_now(c) and int(rc.bites) == 1, "雑草とかじられた跡を読み戻す")
	_check(r.garden.crop_at(AT + Vector2(6, 0)).mulched and r.garden.straw == 6, "わらを読み戻す")
	_check(r.pests.friendship == 63 - Pests.MACHINE_LOSS and r.pests.machine_days.get("mill", "") == w.forest.today(), "仲良し度を読み戻す")
	# 記録のない古いセーブ
	var old := GameWorld.new()
	old.time.set_today("2026-05-10")
	old.garden.forest = old.forest
	old.garden.from_save({"crops": [{"x": AT.x, "y": AT.y, "kind": "radish", "sown_day": old.garden.day_number() - 30}]})
	var oc: Dictionary = old.garden.crop_at(AT)
	_check(not oc.is_empty() and not old.garden.has_weeds(oc) and int(oc.bites) == 0 and not oc.mulched, "古いセーブの区画は、読んだ日から雑草を数える")
	old.pests.from_save({})
	_check(old.pests.friendship == Pests.FRIEND_START, "仲良し度のない古いセーブは %d から" % Pests.FRIEND_START)
