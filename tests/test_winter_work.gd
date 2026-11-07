extends SceneTree

# 冬の作業(果樹の剪定と鳥の餌台)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_winter_work.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Forest = preload("res://logic/Forest.gd")
const Feeders = preload("res://logic/Feeders.gd")
const Wildlife = preload("res://logic/Wildlife.gd")

const TEST_SAVE := "user://test_winter_work.json"
const AT := Vector2(20, 20)

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_prune_rules()
	_test_prune_year()
	_test_prune_harvest()
	_test_prune_firewood()
	_test_prune_save()
	_test_feeder_place()
	_test_feed()
	_test_feed_days()
	_test_birds()
	_test_feeder_blocks()
	_test_feeder_save()
	_test_stove_hint()
	_test_snow_rules()
	_test_snow_burying()
	_test_snow_save()
	_test_chop_place()
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

func _world(season := "winter") -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.forest.season = season
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birds"
	return w

func _fruit_tree(w: GameWorld, species := "apple", age := 30.0, pos := AT) -> Dictionary:
	w.forest.trees.append({"pos": pos, "species": species, "form": "sapling", "planted_at": w.forest._now(), "start_age": age, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	return w.forest.trees[-1]

# ── 剪定 ──────────────────────────────────────────────────────
func _test_prune_rules() -> void:
	print("剪定の決まり")
	var w := _world()
	var f := w.forest
	_check(w.prune(AT, 2.0) == "none", "近くに果樹がなければできない")
	_fruit_tree(w, "birch")
	_check(w.prune(AT, 2.0) == "none", "白樺は果樹ではない")
	f.trees.clear()
	var t := _fruit_tree(w, "apple", 5.0)
	_check(not f._is_bearing(t) and w.prune(AT, 2.0) == "young", "実りはじめる前の木は切らない")
	_check(f.last_prune_item == "apple", "どの木かを覚える(文言用)")
	t.start_age = 30.0
	_check(f.prunable_count() == 1 and f.pruned_count() == 0, "剪定できる木を数える")
	f.advance_years(1.0)
	_check(w.prune(AT, 2.0) == "preview", "未来のプレビュー中はできない")
	f.reset_preview()
	for season in ["spring", "summer", "autumn"]:
		f.season = season
		_check(w.prune(AT, 2.0) == "not_season", "%s は剪定できない" % season)
	f.season = "winter"
	_check(w.prune(AT, 2.0) == "pruned" and f.is_pruned(t), "冬に剪定できる")
	_check(f.prunable_count() == 0 and f.pruned_count() == 1, "剪定した木は数えない")
	_check(w.prune(AT, 2.0) == "done", "ひと冬に 1 回だけ")
	_check(f.is_pruned(t) and not f.is_pruned({"pruned_year": 0}) and not f.is_pruned({}), "記録がない木はまだ剪定していない")
	for id in Forest.FRUITS:
		f.trees.clear()
		_fruit_tree(w, id)
		_check(w.prune(AT, 2.0) == "pruned", "%s を剪定できる" % id)

func _test_prune_year() -> void:
	print("剪定が効く年")
	_check(Forest.harvest_year_of("2026-12-15") == 2027, "12 月の剪定は翌年の収穫に")
	_check(Forest.harvest_year_of("2027-01-10") == 2027 and Forest.harvest_year_of("2027-02-28") == 2027, "1〜2 月の剪定はその年の収穫に")
	_check(Forest.harvest_year_of("2027-09-01") == 2027, "9 月の収穫は、前の冬の剪定を見る")
	_check(Forest.harvest_year_of("2027-12-01") == 2028, "次の 12 月からは、もう一度剪定できる")

func _test_prune_harvest() -> void:
	print("剪定と収穫")
	for id in Forest.FRUITS:
		var fruit: Dictionary = Forest.FRUITS[id]
		var w := _world(fruit.seasons[0])
		var f := w.forest
		var t := _fruit_tree(w, id)
		var plain: int = Forest.fruit_yield(id, f.real_age_years(t))
		_check(f.harvest_nearest(AT, 2.0) == "harvested" and f.last_harvest_count == plain and f.last_harvest_extra == 0, "%s: 剪定しないと %d" % [id, plain])
		t.last_harvest = ""
		t.pruned_year = Forest.harvest_year_of(f.today())
		var before: int = f.produce[id]
		_check(f.harvest_nearest(AT, 2.0) == "harvested" and f.last_harvest_count > plain, "%s: 剪定すると増える(%d → %d)" % [id, plain, f.last_harvest_count])
		_check(f.last_harvest_count <= ceili(plain * Forest.PRUNE_BONUS) and f.last_harvest_extra == f.last_harvest_count - plain, "%s: 増えるのは 1.25 倍まで" % id)
		_check(f.produce[id] == before + f.last_harvest_count, "%s: 持ち物も増える" % id)
		t.last_harvest = ""
		t.pruned_year = Forest.harvest_year_of(f.today()) - 1
		_check(f.harvest_nearest(AT, 2.0) == "harvested" and f.last_harvest_count == plain, "%s: 前の年の剪定は効かない" % id)

func _test_prune_firewood() -> void:
	print("切った枝は薪になる")
	var w := _world()
	_fruit_tree(w)
	_check(w.kitchen.firewood == 0, "はじめは薪がない")
	w.prune(AT, 2.0)
	_check(w.kitchen.firewood == GameWorld.PRUNE_FIRES and w.cabin.materials.log == 0, "剪定すると薪が増える(丸太は使わない)")
	w.prune(AT, 2.0)
	_check(w.kitchen.firewood == GameWorld.PRUNE_FIRES, "切らなければ増えない")
	w.garden.produce.tomato = 10
	_check(w.kitchen.start("sauce") == "started" and w.kitchen.firewood == GameWorld.PRUNE_FIRES - 1, "枝の薪でストーブを焚ける")

func _test_prune_save() -> void:
	print("剪定のセーブ")
	var w := _world()
	var t := _fruit_tree(w)
	w.prune(AT, 2.0)
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	w2.forest.season = "winter"
	_check(w2.forest.trees[0].pruned_year == t.pruned_year and w2.forest.is_pruned(w2.forest.trees[0]), "剪定が残る")
	_check(w2.kitchen.firewood == GameWorld.PRUNE_FIRES, "薪が残る")
	_check(w2.prune(AT, 2.0) == "done", "読み直しても 2 回はできない")
	_remove_save()
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"unit": "m", "trees": [{"x": 20, "y": 20, "species": "apple", "planted_at": 1, "start_age": 30.0}]}))
	file.close()
	var w3 := GameWorld.new()
	w3.save_path = TEST_SAVE
	w3.load_game()
	_check(int(w3.forest.trees[0].pruned_year) == 0 and not w3.forest.is_pruned(w3.forest.trees[0]), "記録がないセーブの木は、まだ剪定していない")
	_check(w3.feeders.feeders.is_empty(), "記録がないセーブは、餌台なしから")

# ── 餌台 ──────────────────────────────────────────────────────
func _test_feeder_place() -> void:
	print("餌台を立てる")
	var w := _world()
	var fd := w.feeders
	_check(fd.act(AT, AT + Vector2(0, 1.2)) == "no_wood" and fd.feeders.is_empty(), "丸太がないと立てられない")
	w.cabin.materials.log = 5
	_check(fd.act(AT, AT + Vector2(0, 1.2)) == "placed" and fd.feeders[0].pos == AT + Vector2(0, 1.2), "体の前に立つ")
	_check(w.cabin.materials.log == 5 - Feeders.LOG_COST, "丸太を 1 本使う")
	_check(not fd.is_fed(fd.feeders[0]) and fd.fed_count() == 0, "立てただけでは餌がない")
	var w2 := _world("summer")
	w2.cabin.materials.log = 5
	_check(w2.feeders.act(AT) == "placed", "夏でも立てられる")
	# 2 つまで
	var far := AT + Vector2(10, 0)
	_check(fd.act(far) == "placed" and fd.feeders.size() == 2, "2 つ目を立てられる")
	_check(fd.act(far + Vector2(10, 0)) == "too_many" and w.cabin.materials.log == 5 - 2 * Feeders.LOG_COST, "3 つ目は立てられず、丸太も減らない")
	_check(fd.feeder_near(AT + Vector2(0, 1.0)) == fd.feeders[0] and fd.feeder_near(AT + Vector2(5, 0)).is_empty(), "2m 以内の餌台を見つける")

func _test_feed() -> void:
	print("餌を置く")
	var w := _world()
	var fd := w.feeders
	var f := w.forest
	w.cabin.materials.log = 1
	fd.act(AT)
	f.seeds.birch = 2
	_check(fd.act(AT) == "no_seed" and f.seeds.birch == 2 and not fd.ever_fed(), "種が足りないと置けない")
	f.seeds.birch = Feeders.FEED_SEEDS + 1
	_check(fd.hungry_count() == 1, "餌のない餌台を数える")
	_check(fd.act(AT) == "fed" and f.seeds.birch == 1, "白樺の種を 3 粒使う")
	_check(fd.is_fed(fd.feeders[0]) and fd.fed_today(fd.feeders[0]) and fd.ever_fed() and fd.hungry_count() == 0, "餌が入る")
	f.seeds.birch = 10
	_check(fd.act(AT) == "full" and f.seeds.birch == 10, "今日はもう足せない")
	f.season = "spring"
	_check(fd.act(AT) == "not_season" and f.seeds.birch == 10, "春は置かない")
	_check(fd.hungry_count() == 0, "春は足さなくてよい")
	f.season = "autumn"
	fd.feeders[0].fed_day = f.day_number() - 1
	_check(fd.act(AT) == "fed" and f.seeds.birch == 7, "秋も置ける。前の日の餌が残っていても足せる")

func _test_feed_days() -> void:
	print("餌が残る日数")
	var w := _world()
	var fd := w.feeders
	var d: int = w.forest.day_number()
	var c := {"pos": AT, "fed_day": d}
	_check(fd.is_fed(c), "置いた日は残っている")
	c.fed_day = d - 1
	_check(fd.is_fed(c) and not fd.fed_today(c), "翌日も残っている")
	c.fed_day = d - 2
	_check(not fd.is_fed(c), "翌々日にはなくなる")
	c.fed_day = -1
	_check(not fd.is_fed(c), "一度も置いていなければない")

# 昼か夜かは時計で決まるので、テストでは暗さの判定をまねず counts の前に _wanted を見る
func _test_birds() -> void:
	print("餌台に来る鳥")
	var w := _world()
	var fd := w.feeders
	var wl := w.wildlife
	_check(Wildlife.SPECIES.has("tit") and Wildlife.SPECIES.has("bullfinch"), "シジュウカラとウソがいる")
	_check("winter" in Wildlife.SPECIES.bullfinch.seasons and not ("autumn" in Wildlife.SPECIES.bullfinch.seasons), "ウソは冬だけ")
	_check("autumn" in Wildlife.SPECIES.tit.seasons and "winter" in Wildlife.SPECIES.tit.seasons and not ("summer" in Wildlife.SPECIES.tit.seasons), "シジュウカラは秋と冬")
	_check(wl._wanted("tit") == 0 and wl._wanted("bullfinch") == 0, "餌台がなければ来ない")
	w.cabin.materials.log = 2
	w.forest.seeds.birch = 20
	fd.act(AT)
	_check(wl._wanted("tit") == 0, "餌を置くまで来ない")
	fd.act(AT)
	_check(wl._wanted("tit") == Wildlife.TITS_PER_FEEDER and wl._wanted("bullfinch") == Wildlife.BULLFINCHES_PER_FEEDER, "餌を置くと来る")
	var far := AT + Vector2(20, 0)
	fd.act(far)
	fd.act(far)
	_check(wl._wanted("tit") == Wildlife.TITS_PER_FEEDER * 2, "餌台が 2 つなら倍")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var homes := {}
	for _i in range(30):
		homes[wl.home_for("tit", rng, Vector2.ZERO)] = true
	_check(homes.has(AT) and homes.has(far) and homes.size() == 2, "住みかは餌のある餌台")
	fd.feeders[1].fed_day = w.forest.day_number() - 2
	_check(wl.home_for("bullfinch", rng, Vector2.ZERO) == AT, "餌の切れた餌台には行かない")
	fd.feeders[0].fed_day = w.forest.day_number() - 2
	_check(wl._wanted("tit") == 0 and wl._wanted("bullfinch") == 0, "餌が切れると来なくなる")
	_check(not wl.is_free(AT) and wl.is_free(AT + Vector2(0, 3)), "ほかの生き物は餌台の上に行かない")

func _test_feeder_blocks() -> void:
	print("餌台と、ほかの物の場所")
	var w := _world()
	var fd := w.feeders
	w.cabin.materials.log = 10
	fd.act(AT)
	_check(fd.covers(AT) and not fd.covers(AT + Vector2(3, 0)), "餌台のある場所が分かる")
	_check(fd.is_blocked(AT + Vector2(1, 0)), "餌台のすぐ隣には立てられない")
	_check(w.bees.is_blocked(AT + Vector2(1, 0)), "餌台のすぐ隣には巣箱も置けない")
	_check(w.toggle_plot(AT) == "feeder" and w.land.plots.is_empty(), "餌台の上に区画を作れない")
	var w2 := _world()
	w2.cabin.materials.log = 5
	w2.feeders.act(AT)
	_check(w2.pond_action(AT) == "feeder" and w2.land.pond == null, "餌台の上に池を掘れない")
	var w3 := _world()
	w3.cabin.materials.log = 5
	_fruit_tree(w3, "birch", 10.0, AT + Vector2(0.5, 0))
	_check(w3.feeders.act(AT) == "blocked" and w3.feeders.feeders.is_empty() and w3.cabin.materials.log == 5, "木のそばには立てられず、丸太も減らない")
	var w4 := _world()
	w4.cabin.materials.log = 5
	w4.land.toggle_plot(AT)
	_check(w4.feeders.act(AT) == "blocked", "区画の上には立てられない")
	_check(w4.feeders.act(Vector2(49.5, 0)) == "blocked", "土地の端には立てられない")

func _test_feeder_save() -> void:
	print("餌台のセーブ")
	var w := _world()
	w.cabin.materials.log = 2
	w.forest.seeds.birch = 3
	w.feeders.act(AT)
	w.feeders.act(AT)
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	_check(w2.feeders.feeders.size() == 1 and w2.feeders.feeders[0].pos == AT, "餌台が残る")
	_check(w2.feeders.is_fed(w2.feeders.feeders[0]), "餌が残る")
	_check(w2.forest.seeds.birch == 0 and w2.cabin.materials.log == 1, "使った種と丸太は戻らない")
	var fd := Feeders.new()
	fd.from_save({"feeders": [{"x": 1, "y": 2}, "bad"]})
	_check(fd.feeders.size() == 1 and int(fd.feeders[0].fed_day) == -1, "おかしな記録は無視し、餌なしにする")

# ── 雪かき ────────────────────────────────────────────────────
func _test_snow_rules() -> void:
	print("雪かきの決まり")
	var w := _world()
	var s := w.snow
	_check(not s.is_cleared(AT), "はじめは雪の上")
	_check(s.clear_at(AT) == "cleared" and s.is_cleared(AT), "足元の雪をどかせる")
	_check(s.clear_at(AT) == "done", "同じマスは 2 回どかさなくてよい")
	_check(s.is_cleared(AT + Vector2(0.1, 0.1)) or s.cell_of(AT) != s.cell_of(AT + Vector2(0.1, 0.1)), "同じマスの中は道")
	_check(not s.is_cleared(AT + Vector2(3, 3)), "離れたマスは雪のまま")
	_check(s.PATH_SPEED > 1.0 and s.SHOVEL_SPEED < 1.0, "道の上は速く、雪かきしながらは遅い")
	_check(s.clear_at(Vector2(0, 56)) == "cleared", "土地の外の市場への道もどかせる")
	_check(s.clear_at(Vector2(0, 79)) == "blocked", "歩ける範囲の外はどかせない")
	w.land.toggle_plot(Vector2(10, 10))
	_check(s.clear_at(Vector2(10, 10)) == "blocked", "区画の上はどかせない")
	w.cabin.site = Vector2(-20, 20)
	_check(s.clear_at(Vector2(-20, 20)) == "blocked", "小屋の上はどかせない")
	w.land.pond = Vector2(-20, -20)
	_check(s.clear_at(Vector2(-20, -20)) == "blocked", "池の上はどかせない")
	for season in ["spring", "summer", "autumn"]:
		w.forest.season = season
		_check(s.clear_at(Vector2(30, 30)) == "not_season" and not s.is_cleared(AT), "%s は雪かきしない" % season)

# 2027 年 1 月の中から、雪の日か、雪でない日を探す
func _january_day(w: GameWorld, snowy: bool) -> int:
	var first := int(Time.get_unix_time_from_datetime_string("2027-01-05") / 86400.0)
	for d in range(first, first + 20):
		if (w.forest.roll_daily_event(Forest.date_of_day(d)) == "rain") == snowy:
			return d
	return -1

func _test_snow_burying() -> void:
	print("雪で道が埋まる")
	var w := _world()
	var s := w.snow
	var dry := _january_day(w, false)
	var snowy := _january_day(w, true)
	_check(dry > 0 and snowy > 0, "前提: 1 月に雪の日と雪でない日がある")
	s.clear_at(AT)
	s.advance_to(dry)
	_check(s.last_checked_day == dry and s.is_cleared(AT) and not s.last_fell, "はじめて数える日は埋まらない")
	s.advance_to(dry)
	_check(s.is_cleared(AT), "同じ日は何も起きない")
	s.last_checked_day = dry - 1
	s.advance_to(dry)
	_check(s.is_cleared(AT) and not s.last_fell, "雪でない日は道が残る")
	s.last_checked_day = snowy - 1
	s.advance_to(snowy)
	_check(not s.is_cleared(AT) and s.cells.is_empty() and s.last_fell, "雪の日に道が埋まる")
	s.last_checked_day = snowy - 1
	s.advance_to(snowy)
	_check(not s.last_fell, "道がなければ知らせない")
	# 閉じていたあいだの雪も数える
	s.clear_at(AT)
	s.last_checked_day = snowy - 1
	s.advance_to(snowy + 1)
	_check(s.cells.is_empty(), "閉じていたあいだの雪でも埋まる")
	# 冬が終わると消える
	s.clear_at(AT)
	var march := int(Time.get_unix_time_from_datetime_string("2027-03-15") / 86400.0)
	s.last_checked_day = march - 1
	s.advance_to(march)
	_check(s.cells.is_empty(), "冬が終わると道も消える")

func _test_snow_save() -> void:
	print("雪かきのセーブ")
	var w := _world()
	w.snow.clear_at(AT)
	w.snow.clear_at(AT + Vector2(1.5, 0))
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	w2.forest.season = "winter"
	_check(w2.snow.cells.size() == 2 and w2.snow.is_cleared(AT) and w2.snow.is_cleared(AT + Vector2(1.5, 0)), "道が残る")
	var plain := GameWorld.new()
	plain.snow.from_save({"cells": [[1, 2], "bad", [3]]})
	_check(plain.snow.cells.size() == 1 and plain.snow.cells.has(Vector2i(1, 2)), "おかしな記録は無視する")
	plain.snow.from_save({})
	_check(plain.snow.cells.is_empty() and plain.snow.last_checked_day == 0, "記録がないセーブは、道なしから")

# ── 薪割り台の場所 ───────────────────────────────────────────────
func _test_chop_place() -> void:
	print("薪割り台の場所")
	var w := _world()
	var c := w.cabin
	_check(not c.in_yard(AT) and not c.blocks_plot(AT), "小屋の場所を決める前は、庭はない")
	c.site = AT
	var chop: Vector2 = c.chop_pos()
	_check(not c.is_at_chop_block(chop + Vector2(0.5, 0)), "完成するまでは薪割りできない")
	c.stage = c.STAGES.size()
	_check(c.is_at_chop_block(chop + Vector2(1.0, 0)) and not c.is_at_chop_block(chop + Vector2(2.0, 0)), "台のそばだけ")
	_check(not c.is_at_stove(chop) and not c.is_inside(chop), "台は小屋の外にある")
	_check(not c.is_at_chop_block(AT + Vector2(1.9, 0.7)), "小屋の中からは割れない")
	_check(c.in_yard(chop) and not c.in_yard(AT + Vector2(5, 0)), "台は東の庭の中にある")
	_check(w.bees.is_blocked(chop), "東の庭には巣箱を置けない")
	w.cabin.materials.log = 1
	_check(w.feeders.act(chop) == "blocked", "東の庭には餌台を立てられない")
	var w2 := _world()
	w2.cabin.site = AT
	_check(w2.toggle_plot(AT + Vector2(3.5, 0)) == "cabin", "東の庭には区画を作れない")
	_check(w2.cabin.blocks_pond(AT + Vector2(5, 0)), "東の庭には池を掘れない")

func _test_stove_hint() -> void:
	print("ヒント: 枝の薪があっても、ストーブの案内は消えない")
	var w := _world()
	_fruit_tree(w)
	w.prune(AT, 2.0)
	_check(w.kitchen.firewood > 0 and not w.guide._is_done("stove"), "薪があるだけでは、料理したことにならない")
	w.garden.produce.tomato = 10
	w.kitchen.start("sauce")
	_check(w.guide._is_done("stove"), "仕込むと案内が済む")
	var saved: Dictionary = w.kitchen.to_save()
	var k = load("res://logic/Kitchen.gd").new()
	k.from_save(saved)
	_check(k.cooked, "セーブに残る")
	k.from_save({"firewood": 4, "stock": {}})
	_check(k.cooked, "記録がないセーブは、薪があれば料理したことがある(当時は仕込まないと薪にならなかった)")
	k.from_save({})
	_check(not k.cooked, "何もなければ、まだ料理していない")
