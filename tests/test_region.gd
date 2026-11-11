extends SceneTree

# 都道府県と気候のテスト(logic/Region.gd と、それを読む木・畑・雪・池・市場・選ぶ画面)。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_region.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Region = preload("res://logic/Region.gd")
const Forest = preload("res://logic/Forest.gd")
const Garden = preload("res://logic/Garden.gd")
const DayClock = preload("res://logic/DayClock.gd")
const RegionPicker = preload("res://view/RegionPicker.gd")

const TEST_SAVE := "user://test_region.json"
const SPOT := Vector2(1, 1)   # 区画(1.5, 1.5)の中
const TREE_SPOT := Vector2(12, -12)

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_data()
	_test_zones_playable()
	_test_choose()
	_test_seasons()
	_test_frost()
	_test_sowing()
	_test_planting()
	_test_snow_and_pond()
	_test_daily_events()
	_test_start_stock()
	_test_market()
	_test_quest_and_feeder()
	_test_prune_year()
	_test_save()
	_test_sun()
	_test_picker_text()
	_run_scene.call_deferred()

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

# その県の、日付を決めたゲーム(セーブは書かない場所に向ける)
func _world(pref: String, date: String) -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.load_game()
	w.time.set_today(date)
	if pref != "":
		w.choose_region(pref)
	w.refresh_season()
	return w

func _test_data() -> void:
	print("都道府県の表")
	_check(Region.PREFS.size() == 47, "47 都道府県ある(%d)" % Region.PREFS.size())
	var listed := []
	for a in Region.AREAS:
		listed.append_array(a.prefs)
	_check(listed.size() == 47 and listed.all(func(id): return Region.PREFS.has(id)), "地方の並びに 47 都道府県が 1 回ずつ入っている")
	var dup := {}
	for id in listed:
		dup[id] = true
	_check(dup.size() == 47, "地方の並びに重なりがない")
	_check(Region.PREFS.values().all(func(p): return Region.ZONES.has(p.zone)), "どの県の気候区分もある")
	_check(Region.ZONES.size() == 8, "気候区分は 8 つ")
	var used := {}
	for p in Region.PREFS.values():
		used[p.zone] = true
	_check(used.size() == 8, "8 つの気候区分のどれにも県がある")
	_check(Region.ZONES.values().all(func(z): return z.months.size() == 12), "どの気候区分も 12 か月ぶんの季節がある")
	_check(Region.PREFS.values().all(func(p): return p.lat > 24.0 and p.lat < 46.0 and p.lon > 122.0 and p.lon < 146.0), "緯度・経度が日本の中")
	_check(Region.PREFS.hokkaido.zone == "hokkaido" and Region.PREFS.okinawa.zone == "nansei" and Region.PREFS.tokyo.zone == "pacific", "北海道・沖縄・東京の気候区分")

# どの土地でも、種から育つ広葉樹・針葉樹と、果樹がある(遊べる)
func _test_zones_playable() -> void:
	print("どの土地でも遊べる")
	for zid in Region.ZONES:
		var z: Dictionary = Region.ZONES[zid]
		var groups := {"broadleaf": 0, "fruit": 0, "conifer": 0}
		for sp in Forest.SPECIES:
			if zid in Forest.SPECIES[sp].zones:
				groups[Forest.SPECIES[sp].group] += 1
		_check(groups.broadleaf > 0 and groups.fruit > 0 and groups.conifer > 0, "%s: 広葉樹 %d・果樹 %d・針葉樹 %d" % [z.name, groups.broadleaf, groups.fruit, groups.conifer])
		for key in ["wind_seed", "nut_seed", "family"]:
			_check(zid in Forest.SPECIES[z[key]].zones, "%s: %s(%s)が育つ" % [z.name, key, Forest.SPECIES[z[key]].name])
		_check(Forest.SPECIES[z.wind_seed].group == "broadleaf" and Forest.SPECIES[z.wind_seed].germination > 0.0, "%s: 運ばれてくる種は、種から育つ広葉樹" % z.name)
		_check(Forest.SPECIES[z.nut_seed].group == "conifer" and Forest.SPECIES[z.nut_seed].germination > 0.0, "%s: リスの実は、種から育つ針葉樹" % z.name)
	_check(Forest.SPECIES.values().all(func(s): return s.has("group") and s.has("zones") and s.zones.all(func(z): return Region.ZONES.has(z))), "どの木にも組と、ある気候区分の一覧がある")

func _test_choose() -> void:
	print("県を決める")
	var r := Region.new()
	_check(not r.is_chosen() and r.zone() == Region.LEGACY, "はじめは選んでいない(今までのルール)")
	_check(not r.choose("atlantis"), "知らない県は選べない")
	_check(r.choose("tokyo") and r.pref == "tokyo", "東京都を選べる")
	_check(not r.choose("okinawa") and r.pref == "tokyo", "一度決めたら変えられない")
	var w := _world("", "2026-11-11")
	_check(w.choose_region("hokkaido") == "chosen" and w.forest.region == w.region, "GameWorld で決めると、木のルールにも伝わる")
	_check(w.choose_region("okinawa") == "already" and w.region.pref == "hokkaido", "GameWorld でも変えられない")
	_check(_world("", "2026-11-11").choose_region("x") == "unknown", "知らない id は unknown")

func _test_seasons() -> void:
	print("季節")
	var hk := _world("hokkaido", "2026-11-05")
	_check(hk.forest.season == "winter", "北海道は 11 月が冬")
	hk.time.set_today("2026-04-10")
	hk.refresh_season()
	_check(hk.forest.season == "spring", "北海道は 4 月が春")
	hk.time.set_today("2026-03-20")
	hk.refresh_season()
	_check(hk.forest.season == "winter", "北海道は 3 月も冬")
	var tk := _world("tokyo", "2026-03-10")
	_check(tk.forest.season == "spring", "東京は 3 月が春")
	var ok := _world("okinawa", "2026-05-10")
	_check(ok.forest.season == "summer", "沖縄は 5 月が夏")
	ok.time.set_today("2026-10-20")
	ok.refresh_season()
	_check(ok.forest.season == "summer", "沖縄は 10 月も夏")
	var ks := _world("kagoshima", "2026-09-15")
	_check(ks.forest.season == "summer", "鹿児島は 9 月も夏")
	var legacy := _world("", "2026-11-11")
	_check(legacy.forest.season == "autumn" and legacy.season_for_month(12) == "winter" and legacy.season_for_month(3) == "spring", "選ぶ前は今までの季節")
	_check(legacy.forest.is_summer_date("2026-07-01") and not legacy.forest.is_summer_date("2026-09-01"), "選ぶ前は 6〜8 月が夏(池の水が減る)")
	_check(ok.forest.is_summer_date("2026-09-01"), "沖縄は 9 月も池の水が減る")
	_check(Region.new().winter_start_month() == 12, "選ぶ前の冬は 12 月から")
	_check(hk.region.winter_start_month() == 11 and hk.region.winter_end_month() == 4, "北海道の冬は 11 月から 3 月まで")
	_check(tk.region.winter_end_month() == 3, "東京の冬は 2 月まで")

func _test_frost() -> void:
	print("霜")
	var hk := _world("hokkaido", "2026-10-25")
	hk.land.toggle_plot(SPOT)
	hk.garden.seeds.radish = 1
	hk.garden.sow(SPOT, "radish")
	_check(hk.garden.days_to_frost() == 7, "北海道の霜は 11 月 1 日から(10/25 から 7 日)")
	_check(hk.garden.frost_is_near(hk.forest.today()), "北海道は 10 月の終わりに霜が近いと分かる")
	_check(hk.garden.frost_date_text() == "11月1日", "霜の日の文言")
	hk.time.set_today("2026-11-01")
	hk.refresh_season()
	hk.garden.apply_frost()
	_check(hk.garden.crops.is_empty() and hk.garden.last_frost.get("radish", 0) == 1, "北海道は 11 月 1 日に霜で枯れる")
	var tk := _world("tokyo", "2026-11-01")
	tk.land.toggle_plot(SPOT)
	tk.garden.seeds.radish = 1
	tk.garden.sow(SPOT, "radish")
	tk.garden.apply_frost()
	_check(tk.garden.crops.size() == 1 and not tk.garden.frost_is_near(tk.forest.today()), "東京の 11 月 1 日はまだ霜が降りない")
	var ok := _world("okinawa", "2026-12-15")
	ok.land.toggle_plot(SPOT)
	ok.garden.seeds.radish = 1
	_check(ok.garden.sow(SPOT, "radish") == "sown", "沖縄は冬もラディッシュをまける")
	ok.time.set_today("2027-01-20")
	ok.refresh_season()
	ok.garden.apply_frost()
	_check(ok.garden.crops.size() == 1, "沖縄は冬も霜で枯れない")
	_check(ok.garden.days_to_frost() == 366 and not ok.garden.misses_frost(ok.garden.crops[0]), "沖縄には霜の日がない")

func _test_sowing() -> void:
	print("まける季節")
	var tk := _world("tokyo", "2026-12-15")
	_check(not tk.garden.can_sow_now("radish") and not tk.garden.can_sow_now("garlic"), "東京の冬は何もまけない")
	var ok := _world("okinawa", "2026-12-15")
	_check(ok.garden.can_sow_now("radish") and ok.garden.can_sow_now("potato") and ok.garden.can_sow_now("garlic"), "沖縄の冬は春か秋の野菜をまける")
	_check(not ok.garden.can_sow_in("cucumber", "winter") or "spring" in Garden.CROPS.cucumber.seasons, "冬にまけるのは春か秋の野菜だけ")

func _test_planting() -> void:
	print("植えられる木")
	var tk := _world("tokyo", "2026-11-11")
	var f := tk.forest
	_check(f.plant_problem("birch", "seed") == "not_here" and f.plant_problem("cedar", "sapling") == "not_here", "東京では白樺とシベリア杉は育たない")
	_check(f.can_plant("konara", "seed") and f.can_plant("sugi", "seed") and f.can_plant("mikan", "sapling"), "東京ではコナラ・スギ・ミカンが育つ")
	_check(f.species_in("broadleaf") == ["konara"] and f.species_in("conifer") == ["sugi"], "東京のキー 1・3 で選べる木")
	_check(f.species_in("fruit") == ["plum", "pear", "kaki", "mikan"], "東京の果樹(%s)" % str(f.species_in("fruit")))
	f.seeds.birch = 1
	_check(f.add_tree(TREE_SPOT, "birch", "seed"), "持っている種は add_tree では植えられる(画面で止めるのは Main)")
	tk.time.set_today("2027-01-10")
	tk.refresh_season()
	_check(f.season == "winter" and f.can_plant("konara", "sapling"), "東京の冬は地面が凍らず、苗木も植えられる")
	var hk := _world("hokkaido", "2026-11-11")
	_check(hk.forest.plant_problem("ezomatsu", "sapling") == "frozen", "北海道の 11 月は地面が凍って苗木を植えられない")
	_check(hk.forest.can_plant("birch", "seed"), "北海道の冬も白樺の種はまける")
	_check(hk.forest.plant_problem("sugi", "seed") == "not_here" and hk.forest.grows_here("ezomatsu"), "北海道はスギでなくエゾマツ")
	var ok := _world("okinawa", "2026-11-11")
	_check(ok.forest.species_in("broadleaf") == ["gajumaru"] and ok.forest.species_in("conifer") == ["ryukyu_pine"] and ok.forest.species_in("fruit") == ["shikuwasa"], "沖縄はガジュマル・リュウキュウマツ・シークヮーサー")
	var legacy := _world("", "2026-11-11")
	_check(legacy.forest.species_in("broadleaf") == ["birch"] and legacy.forest.species_in("conifer") == ["cedar"], "選ぶ前は今までの木だけ")
	_check(legacy.forest.species_in("fruit") == ["apple", "cherry", "plum", "pear"], "選ぶ前の果樹も今までのまま")

func _test_snow_and_pond() -> void:
	print("雪と池")
	var tk := _world("tokyo", "2027-01-10")
	_check(not tk.snow.can_clear_now(), "東京の冬は雪かきできない(積もらない)")
	tk.land.toggle_pond(Vector2(-20, -20))
	tk.pond.water = 50
	_check(not tk.pond.is_frozen(), "東京の池は凍らない")
	var hk := _world("hokkaido", "2026-11-20")
	_check(hk.snow.can_clear_now(), "北海道は 11 月から雪かきできる")
	hk.land.toggle_pond(Vector2(-20, -20))
	hk.pond.water = 50
	_check(hk.pond.is_frozen(), "北海道の 11 月は池が凍る")
	_check(not hk.region.is_snow_month(4) and hk.region.is_snow_month(3), "北海道の雪は 3 月まで")

func _test_daily_events() -> void:
	print("日替わりの発見")
	for pref in ["", "okayama", "akita", "okinawa"]:
		var w := _world(pref, "2026-11-11")
		var total := 0
		for e in w.forest.daily_events():
			total += e[1]
		_check(total == 100, "%s: 発見の重みは合わせて 100" % (pref if pref != "" else "選ぶ前"))
	var setouchi := _world("okayama", "2026-11-11")
	var snowy := _world("akita", "2026-11-11")
	var rains := [0, 0]
	for d in range(365):
		var date := Forest.date_of_day(20454 + d)
		if setouchi.forest.roll_daily_event(date) == "rain":
			rains[0] += 1
		if snowy.forest.roll_daily_event(date) == "rain":
			rains[1] += 1
	_check(rains[0] < rains[1], "瀬戸内(岡山 %d 日)は日本海側(秋田 %d 日)より雨が少ない" % rains)
	var tk := _world("tokyo", "2026-11-11")
	var before: int = int(tk.forest.seeds.konara)
	tk.forest._apply_event("birch_seed")
	_check(int(tk.forest.seeds.konara) == before + 1, "東京では風の種の日にコナラの種が増える")
	tk.forest._apply_event("cedar_seed")
	_check(int(tk.forest.seeds.sugi) == 1, "東京ではリスの実の日にスギの種が増える")

func _test_start_stock() -> void:
	print("はじめの種")
	var tk := _world("", "2026-11-11")
	_check(tk.is_new_game, "セーブがなければ新しいゲーム")
	tk.choose_region("tokyo")
	_check(int(tk.forest.seeds.konara) == Forest.START_WIND_SEEDS and int(tk.forest.seeds.birch) == 0 and int(tk.forest.seeds.apple) == 0, "東京で始めると、コナラの種 3 粒(白樺・リンゴはなし)")
	var hk := _world("", "2026-11-11")
	hk.choose_region("hokkaido")
	_check(int(hk.forest.seeds.birch) == 3 and int(hk.forest.seeds.apple) == 1, "北海道で始めると、白樺 3・リンゴ 1(今までと同じ)")
	# 遊んでいたセーブ(県の記録なし)で選んでも、持ち物は変えない
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.forest.seeds.birch = 7
	w.save_game()
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	_check(not w2.is_new_game and not w2.region.is_chosen(), "県の記録がないセーブは、選んでいない")
	w2.choose_region("tokyo")
	_check(int(w2.forest.seeds.birch) == 7 and int(w2.forest.seeds.konara) == 0, "遊んでいたセーブで選んでも、持ち物はそのまま")
	_remove_save()

func _test_market() -> void:
	print("市場")
	var tk := _world("tokyo", "2026-11-11")
	var m := tk.market
	_check(not m.sells(m.good("birch_seed")) and m.sells(m.good("konara_seed")) and m.sells(m.good("mikan_sapling")), "東京の市場に白樺はなく、コナラとミカンがある")
	var money := m.money
	_check(m.buy("birch_sapling") == "unknown" and m.money == money, "並んでいない品は買えない")
	_check(m.buy("konara_seed") == "bought" and int(tk.forest.seeds.konara) == 3 + 10, "コナラの種を買える")
	_check(m.sells(m.good("radish_seed")) and m.sells(m.good("logs")), "野菜の種と丸太はどこでも並ぶ")
	var legacy := _world("", "2026-11-11")
	_check(not legacy.market.sells(legacy.market.good("konara_seed")) and legacy.market.sells(legacy.market.good("birch_seed")), "選ぶ前は今までの品だけ")
	for zid in Region.ZONES:
		var pref: String = Region.PREFS.keys().filter(func(p): return Region.PREFS[p].zone == zid)[0]
		var w := _world(pref, "2026-11-11")
		var trees := w.market.GOODS.filter(func(g): return (g.form == "seed" or g.form == "sapling") and w.market.sells(g))
		_check(trees.size() + 1 <= 15, "%s: 木の種と苗木のページは 15 行まで(%d 品)" % [Region.ZONES[zid].name, trees.size()])
		_check(Market_fruits_ok(w), "%s: 育つ果物には買い取り値がある" % Region.ZONES[zid].name)

func Market_fruits_ok(w: GameWorld) -> bool:
	return w.forest.species_in("fruit").all(func(sp): return w.market.SELL_PRICES.has(sp))

func _test_quest_and_feeder() -> void:
	print("家族の木と餌台")
	var tk := _world("tokyo", "2026-11-11")
	_check(tk.quests.family_tree() == "sugi" and tk.feeders.feed_species() == "konara", "東京の家族の木はスギ、餌はコナラの種")
	tk.forest.saplings.sugi = 1
	tk.forest.add_tree(Vector2(1, 1), "sugi", "sapling")
	_check(tk.quests.progress("family_cedar") == [1, 1], "中心にスギを植えると家族の木のクエストが進む")
	var ok := _world("okinawa", "2026-11-11")
	_check(ok.quests.family_tree() == "gajumaru", "沖縄の家族の木はガジュマル")
	var legacy := _world("", "2026-11-11")
	_check(legacy.quests.family_tree() == "cedar" and legacy.feeders.feed_species() == "birch", "選ぶ前はシベリア杉と白樺")
	_check(tk.quests.milestone_total() == tk.forest.SPECIES.keys().filter(func(sp): return tk.forest.grows_here(sp)).size() * tk.quests.MILESTONE_AGES.size() + 0, "木の節目は、その土地で育つ樹種のぶん")

func _test_prune_year() -> void:
	print("剪定が効く年")
	var hk := _world("hokkaido", "2026-11-20")
	_check(hk.forest.harvest_year_on("2026-11-20") == 2027, "北海道の 11 月の剪定は翌年の収穫に効く")
	var tk := _world("tokyo", "2026-11-20")
	_check(tk.forest.harvest_year_on("2026-11-20") == 2026 and tk.forest.harvest_year_on("2026-12-05") == 2027, "東京の 11 月は秋(その年)、12 月の剪定は翌年")
	_check(tk.forest.harvest_year_on("2027-02-05") == 2027, "年が明けてからの剪定はその年")
	var legacy := _world("", "2026-11-20")
	_check(legacy.forest.harvest_year_on("2026-12-05") == Forest.harvest_year_of("2026-12-05"), "選ぶ前は今までと同じ")

func _test_save() -> void:
	print("セーブ")
	var w := _world("", "2026-11-11")
	w.choose_region("miyagi")
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	_check(w2.region.pref == "miyagi" and w2.forest.region == w2.region, "選んだ県はセーブに残る(決めたときに保存する)")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	_check(data.get("region") == "miyagi", "セーブには region: 県の id")
	data["region"] = "atlantis"
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var w3 := GameWorld.new()
	w3.save_path = TEST_SAVE
	w3.load_game()
	_check(not w3.region.is_chosen() and w3.forest.region == null, "知らない県のセーブは、選んでいない扱い(もう一度選ぶ)")
	data["region"] = 12
	f = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	w3.load_game()
	_check(not w3.region.is_chosen(), "文字でない県の記録も、選んでいない扱い")
	_remove_save()

func _test_sun() -> void:
	print("太陽")
	var june := DayClock.day_of_year(6, 21)
	var noon_naha := DayClock.elevation_deg(DayClock.to_sun(12.5, june, 26.21, 127.68))
	var noon_sapporo := DayClock.elevation_deg(DayClock.to_sun(11.5, june, 43.06, 141.35))
	_check(noon_naha > 80.0 and noon_sapporo < 72.0, "夏至の昼、那覇の太陽は札幌より高い(%.0f度 / %.0f度)" % [noon_naha, noon_sapporo])
	var w := _world("hokkaido", "2026-06-21")
	var c := w.clock
	_check(c.sun_dir(4.5, june).y > 0.0 and DayClock.to_sun(4.5, june).y < 0.0, "夏至の 4 時半、札幌は日が出ていて、日本のまんなかはまだ")
	var legacy := _world("", "2026-06-21")
	_check(legacy.clock.sun_dir(9.0, june) == DayClock.to_sun(9.0, june), "選ぶ前は今までの緯度・経度")

func _test_picker_text() -> void:
	print("選ぶ画面の文言")
	var tokyo := RegionPicker.describe("tokyo")
	_check(tokyo.contains("太平洋側") and tokyo.contains("冬 12〜2月") and tokyo.contains("コナラ") and not tokyo.contains("白樺"), "東京の説明: 気候・冬の月・育つ木")
	var hk := RegionPicker.describe("hokkaido")
	_check(hk.contains("冬 11〜3月") and hk.contains("雪が積もり") and hk.contains("エゾマツ"), "北海道の説明")
	var ok := RegionPicker.describe("okinawa")
	_check(ok.contains("霜も雪もない") and ok.contains("ガジュマル") and ok.contains("夏 5〜10月"), "沖縄の説明")

# 画面: 選ぶ画面を開いて、地方 → 県 → 決める
func _run_scene() -> void:
	print("選ぶ画面")
	_remove_save()
	var main = load("res://Main.tscn").instantiate()
	main.world.save_path = TEST_SAVE
	root.add_child(main)
	for i in 3:
		await process_frame
	var hud = main.get_node("HUD")
	var player = main.get_node("Player")
	_check(not hud.is_picker_open(), "テストのセーブでは自動で開かない(本物のセーブのときだけ)")
	main.open_region_picker()
	await process_frame
	var picker = hud.picker
	_check(hud.is_picker_open() and picker.step == "area" and picker.button_texts().size() == 8, "開くと 8 つの地方が並ぶ")
	_check(not player.is_physics_processing(), "選んでいるあいだは歩かない")
	var ev := InputEventKey.new()
	ev.keycode = KEY_1
	ev.pressed = true
	main._unhandled_input(ev)
	_check(main.selected_species == "birch", "選んでいるあいだはキーで木を選び直さない")
	picker.press("関東")
	_check(picker.step == "pref" and picker.button_texts().has("東京都") and picker.button_texts().has("← 地方を選び直す"), "関東を押すと都県が並ぶ")
	picker.press("← 地方を選び直す")
	_check(picker.step == "area", "地方を選び直せる")
	picker.press("関東")
	picker.press("東京都")
	_check(picker.step == "confirm" and picker.button_texts() == ["ここに決める", "選び直す"], "県を押すと、決める前に確かめる")
	picker.press("選び直す")
	_check(picker.step == "pref" and picker.area == 2, "選び直すと、同じ地方の県に戻る")
	picker.press("東京都")
	picker.press("ここに決める")
	await process_frame
	_check(not hud.is_picker_open() and main.world.region.pref == "tokyo", "決めると閉じて、東京都になる")
	_check(player.is_physics_processing(), "決めたら歩ける")
	_check(main.selected_species == "konara", "選んでいた白樺は育たないので、コナラに選び直す")
	_check(hud.is_message_visible() and hud._message.contains("東京都"), "決めた県を知らせる")
	hud.inventory_open = true
	var text: String = hud.status_text()
	_check(text.contains("コナラ 3") and not text.contains("白樺"), "持ち物はこの土地の木で並ぶ")
	hud.inventory_open = false
	hud.help_open = true
	_check(hud.status_text().contains("[1]コナラ") and hud.status_text().contains("[3]スギ"), "操作説明の 1・3 はこの土地の木")
	hud.help_open = false
	main._unhandled_input(ev)
	_check(main.selected_species == "konara", "1 を押してもコナラのまま(東京の広葉樹は 1 種類)")
	ev.keycode = KEY_2
	main._unhandled_input(ev)
	_check(main.selected_species == "plum" and main.selected_form == "sapling", "2 で東京の最初の果樹(スモモの苗木)")
	main.selected_species = "birch"
	main.selected_form = "seed"
	main.world.forest.seeds.birch = 1
	main._on_plant_tree(Vector2(15, 15))
	_check(hud._message.contains("白樺は東京都では育たない") and main.world.forest.trees.is_empty(), "育たない木を植えようとすると止めて知らせる")
	main.selected_species = "konara"
	main._on_plant_tree(Vector2(15, 15))
	_check(main.world.forest.trees.size() == 1 and main.world.forest.trees[0].species == "konara", "コナラは植えられる")
	# 市場: 白樺は並ばず、コナラは並ぶ
	main._panel = "market"
	var ids: Array = main.shop_rows().map(func(r): return r.id)
	_check(ids.has("konara_seed") and ids.has("mikan_sapling") and not ids.has("birch_seed") and not ids.has("cedar_sapling"), "市場にはこの土地の木だけが並ぶ")
	_check(main.local_text("餌台に白樺の種を置いた") == "餌台にコナラの種を置いた", "白樺の種の文言はコナラになる")
	_check(main.quest_text("family_cedar").hint.contains("スギ"), "家族の木のクエストはスギ")
	_check(main.daily_message("birch_seed").contains("コナラのどんぐり"), "風の種の発見はコナラのどんぐり")
	main.world.time.set_today("2027-01-10")
	main.world.refresh_season()
	main.world.forest.last_day = main.world.forest.today()
	main.world.forest.today_event = "rain"
	_check(main.daily_message("rain").begins_with("雨が降った"), "東京の冬は雨(雪にならない)")
	_check(not main.world.snow.can_clear_now(), "東京の冬は雪かきのボタンを出さない")
	var weather = main.get_node("Weather")
	weather.refresh(true)
	_check(not weather._snow.emitting and weather._rain.emitting, "東京の冬の雨は雨粒で降る")
	var ground = main.get_node("Ground")
	_check(ground.look_season() == "winter_dry", "東京の冬の地面は枯れ草の色(雪で白くしない)")
	main.world.guide.current = "winter"
	_check(main.hint_text() == main.MILD_WINTER_TEXT, "東京の冬のヒントは霜のこと")
	main.queue_free()
	await process_frame
	_remove_save()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
