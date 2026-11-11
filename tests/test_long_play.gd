extends SceneTree

# 何日も続けて遊ぶ通しのテスト(2026-11-11。レビュー C1・C6)。本物のセーブには触れない。
# WorldTime で日付を 1 日ずつ進め、毎日「開く → 日付の確認 → 決まった遊び方 → 閉じる(保存)」を繰り返す。
# 11 月 1 日に始めて、小屋・増築・畑・池・薪・冬の頼みごと・春の種の注文を通り、3 月 1 日まで(121 日)。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_long_play.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Forest = preload("res://logic/Forest.gd")

const TEST_SAVE := "user://test_long_play.json"
const TEST_DIR := "user://test_long_play_backups"
const START := "2026-11-01"
const DAYS := 121                        # 11/1 〜 3/1
const SITE := Vector2(20, 20)            # 小屋
const POND := Vector2(-20, 20)
const PLOTS := [Vector2(1.5, 25.5), Vector2(4.5, 25.5), Vector2(7.5, 25.5), Vector2(10.5, 25.5)]
const OUTSIDE := Vector2(20, 22.5)       # 小屋の南の外
const WEST := Vector2(14.0, 20.0)        # 増築する部屋の西の外
const CHOP := SITE + Vector2(3.4, 0.7)   # 薪割り台

var _failed := 0
var _passed := 0
var _offset := 0          # WorldTime のずれ(開き直しても同じ日付にする)
var _log := {}            # 起きたことの数

func _initialize() -> void:
	_clean()
	_play()
	_test_clock_back()
	_clean()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)

func _clean() -> void:
	for n in DirAccess.get_files_at("user://"):
		if n.begins_with("test_long_play"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + n))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(TEST_DIR)):
		for n in DirAccess.get_files_at(TEST_DIR):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIR + "/" + n))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DIR))

func _count(key: String, n := 1) -> void:
	_log[key] = int(_log.get(key, 0)) + n

# ゲームを開く: 新しい GameWorld でセーブを読み、日付の確認をする(Main._ready と同じ順)
func _open() -> GameWorld:
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.backup_dir = TEST_DIR
	w.time.offset_seconds = _offset
	w.refresh_season()
	w.load_game()
	w.check_new_day()
	return w

func _play() -> void:
	print("11/1 から 3/1 まで毎日遊ぶ")
	var first := GameWorld.new()
	first.save_path = TEST_SAVE  # 本物のセーブの名前に書かないように
	first.time.set_today(START)
	_offset = first.time.offset_seconds
	# 秋のうちに増築まで進められるよう、前の季節に貯めたお金があることにする(はじめの 11,000₽ は小屋の丸太でほぼ使う)
	first.market.money += 20000
	first.save_game()
	var money_low := 999999
	var season_days := {}
	var saved_same := true
	var frost_seen := false
	var frozen_days := 0
	var w: GameWorld
	for day in range(DAYS):
		w = _open()
		_check_day(w, day)
		var date: String = w.forest.today()
		season_days[w.forest.season] = int(season_days.get(w.forest.season, 0)) + 1
		if not w.garden.last_frost.is_empty():
			frost_seen = true
		if w.pond.is_frozen():
			frozen_days += 1
		_play_day(w, day)
		money_low = mini(money_low, w.market.money)
		# 閉じる前の保存と、開き直したときに読めた中身が同じか
		w.save_game()
		var before: String = FileAccess.get_file_as_string(TEST_SAVE)
		var again := GameWorld.new()
		again.save_path = TEST_SAVE
		again.time.offset_seconds = _offset
		again.refresh_season()
		again.load_game()
		again.save_game()
		var after: String = FileAccess.get_file_as_string(TEST_SAVE)
		if after != before:
			saved_same = false
			var at := 0
			while at < mini(before.length(), after.length()) and before[at] == after[at]:
				at += 1
			print("    保存し直すと中身が変わった日: %s … %s → %s" % [date, before.substr(maxi(0, at - 60), 90), after.substr(at, 30)])
		_offset += 86400  # 次の日
	print("    季節ごとの日数: ", season_days)
	print("    起きたこと: ", _log)
	print("    最後の所持金: %d₽(いちばん少ない日 %d₽)" % [w.market.money, money_low])
	_check(w.forest.today() == "2027-03-01" and season_days == {"autumn": 30, "winter": 90, "spring": 1}, "121 日目は 3 月 1 日(秋 30・冬 90・春 1 日)")
	_check(saved_same, "毎日、保存して開き直しても中身が変わらない")
	_check(money_low >= 0, "所持金がマイナスにならない")
	_check(w.cabin.is_complete() and w.cabin.has_extension(), "小屋と増築ができた")
	_check(w.pond.is_dug() and int(_log.get("pond_rain_days", 0)) > 0, "池を掘り、雨(雪)で水がたまった")
	_check(frozen_days >= 80, "冬のあいだ池が凍っていた(%d 日)" % frozen_days)
	_check(not w.pond.is_frozen(), "3 月には氷が解けている")
	_check(frost_seen, "12 月 1 日の霜で、霜に弱い野菜が枯れた")
	_check(int(_log.get("harvest", 0)) > 0 and int(_log.get("sold", 0)) > 0, "秋に収穫して売った")
	_check(int(_log.get("firewood_given", 0)) > 0, "冬に薪を頼まれて渡した(%d 回)" % int(_log.get("firewood_given", 0)))
	_check(int(_log.get("cooked", 0)) > 0 and int(_log.get("cooked_kamado", 0)) > 0, "ストーブとかまどの両方で仕込んだ")
	_check(w.market.orders.is_empty() and w.garden.seeds.radish >= 5, "冬に注文した春の種が 3 月 1 日に届いた")
	_check(int(_log.get("visits", 0)) >= 40 and int(_log.get("visits", 0)) <= 50, "訪問者は 5 日に 2 回(%d 回)" % int(_log.get("visits", 0)))
	var backups: Array = Array(DirAccess.get_files_at(TEST_DIR))
	_check(backups.size() == 7 and backups.has("kins_domain_save_2027-03-01.json"), "控えは新しい 7 日ぶん")

# 開いた直後の確認(毎日)
func _check_day(w: GameWorld, day: int) -> void:
	if w.load_notice != "":
		_check(false, "%d 日目: セーブが読めなかった: %s" % [day, w.load_notice])
	if w.visitors.is_here():
		_count("visits")
	if w.pond.last_gain > 0:
		_count("pond_rain_days")

# 決まった遊び方。小屋 → 増築 → 畑と池 → 薪と料理 → 頼みごと
func _play_day(w: GameWorld, day: int) -> void:
	var c := w.cabin
	var m := w.market
	if day == 0:
		c.place(SITE)
		w.pond_action(POND)
	for p in PLOTS:  # 区画は 1 日 2 つまでなので、2 日かけて作る
		if w.land.plot_at(p) == null:
			w.toggle_plot(p)
	# 小屋(丸太は市場で)
	if not c.is_complete():
		if c.materials.log < 5:
			m.buy("logs")
		c.work(OUTSIDE)
	elif not c.ext_started():
		m.buy("cabin_extension")
	elif c.ext_building():
		if c.materials.log < 4:
			m.buy("logs")
		c.work_extension(WEST)
	# 池
	if not w.pond.is_dug():
		w.pond_action(POND)
	# 畑: 秋は 2 区画にニンニク(冬の漬物用。霜に強い)、2 区画にラディッシュ。収穫して、ラディッシュは売る。毎日水
	for i in range(PLOTS.size()):
		var p: Vector2 = PLOTS[i]
		var kind: String = "garlic" if i < 2 else "radish"
		var crop: Dictionary = w.garden.crop_at(p)
		if not crop.is_empty() and w.garden.is_ripe(crop):
			if w.garden.harvest_at(p) == "harvested":
				_count("harvest")
		if w.garden.crop_at(p).is_empty() and w.forest.season == "autumn":
			if int(w.garden.seeds[kind]) <= 0:
				m.buy(kind + "_seed")
			w.garden.sow(p, kind)
		w.garden.water_at(p)
	if m.sell_all("radish") > 0:
		_count("sold")
	# 薪と料理(小屋ができてから)。薪は 10 回分まで割っておく
	var k := w.kitchen
	if c.is_complete():
		while k.firewood < 10 and (k.log_left > 0 or c.materials.log > 0):
			k.split()
		if c.materials.log <= 0:
			m.buy("logs")
		for i in range(2 if c.has_extension() else 1):
			k.active = i
			if k.is_ready():
				k.collect()
			if k.is_empty():
				if k.start("pickles") == "started" or k.start("garlic_pickle") == "started" or _cook_any(k) == "started":
					_count("cooked_kamado" if i == 1 else "cooked")
		k.active = 0
	# 頼みごと: 渡せるものなら渡す。薪は足りなければ割ってから
	var v := w.visitors
	if v.has_request():
		if v.visit.item == v.FIREWOOD:
			while k.firewood < int(v.visit.amount) and k.split() == "split":
				pass
		if v.give() == "given":
			_count("given")
			if v.visit.item == v.FIREWOOD:
				_count("firewood_given")
	elif v.has_help() or v.has_gift():
		v.receive_help()
	elif v.is_here() and v.visit.kind == "chat":
		v.finish_chat()
	# 冬は春の種を注文する(ラディッシュを 5 つまで)
	if m.can_order() and int(m.orders.get("radish", 0)) < 5:
		m.order("radish")

# 材料のある保存食を 1 つ仕込む
func _cook_any(k) -> String:
	for id in k.RECIPES:
		if k.input_count(id) >= int(k.RECIPES[id].amount):
			return k.start(id)
	return "none"

# 時計が戻ったとき: 前の日の発見や訪問が、もう一度起きない
func _test_clock_back() -> void:
	print("時計が戻ったとき")
	_clean()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.time.set_today("2026-11-20")
	w.refresh_season()
	w.check_new_day()
	var seeds_before: Dictionary = w.forest.seeds.duplicate()
	var event: String = w.forest.today_event
	var visit: Dictionary = w.visitors.visit.duplicate(true)
	w.save_game()
	w.time.shift_days(-1)
	_check(w.forest.today() == "2026-11-19", "日付が 1 日戻った")
	_check(w.check_new_day() == "" and w.forest.last_day == "2026-11-20", "戻った日は新しい日にならない(最後の日は 11/20 のまま)")
	_check(w.forest.seeds == seeds_before and w.forest.today_event == event, "発見や種は増えない")
	_check(w.visitors.visit == visit, "訪問は前の日のものを作り直さない")
	w.time.shift_days(1)
	_check(w.check_new_day() == "" and w.forest.today() == "2026-11-20", "元の日付に戻しても、同じ日の発見は 2 度起きない")
	w.time.shift_days(1)
	_check(w.check_new_day() != "" and w.forest.last_day == "2026-11-21", "次の日はふつうに新しい日になる")
