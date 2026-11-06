extends SceneTree

# 丸太の巣箱とはちみつのロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_bees.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Bees = preload("res://logic/Bees.gd")
const Visitors = preload("res://logic/Visitors.gd")

const TEST_SAVE := "user://test_bees.json"
const AT := Vector2(-30, -30)

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_own_logs()
	_test_place()
	_test_blocked()
	_test_hollow()
	_test_natural_swarm()
	_test_share()
	_test_honey()
	_test_market()
	_test_catch_up()
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

func _world(season := "summer") -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.forest.season = season
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birds"
	w.market.money = 5000
	return w

# 育った白樺を足元に足して伐り、自分の丸太にする
func _fell_tree(w: GameWorld, age := 20.0) -> int:
	var pos := Vector2(10, -10)
	w.forest.trees.append({"pos": pos, "species": "birch", "form": "sapling", "planted_at": w.forest._now(), "start_age": age, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	return w.cabin.fell(pos, 1.0)

# くり抜いた巣箱を 1 つ作る
func _ready_hive(w: GameWorld, pos := AT) -> Dictionary:
	w.cabin.materials.log += 2
	w.cabin.own_logs += 2
	w.bees.act(pos)
	var h: Dictionary = w.bees.hive_near(pos)
	h.days_done = Bees.HOLLOW_DAYS
	h.hollowed_day = w.forest.day_number() - 1
	return h

func _test_own_logs() -> void:
	print("自分の木の丸太")
	var w := _world()
	var c := w.cabin
	_check(c.own_log_count() == 0, "はじめは 0")
	w.market.buy("logs")
	_check(c.materials.log == 5 and c.own_log_count() == 0, "市場の丸太は自分の木に数えない")
	var n := _fell_tree(w)
	_check(n == 2 and c.materials.log == 7 and c.own_log_count() == 2, "育てた木を伐ると、自分の木の丸太が増える(樹齢 20 年で 2 本)")
	# 小屋には市場の丸太から使う
	c.site = Vector2(20, 20)
	c.work(Vector2(20, 22.5))
	_check(c.materials.log == 4 and c.own_log_count() == 2, "小屋に使っても、市場の分があるうちは自分の丸太は減らない")
	c.last_worked = ""
	c.work(Vector2(20, 22.5))
	_check(c.materials.log == 1 and c.own_log_count() == 1, "足りなくなると自分の丸太も使う")
	# 減ったあとに買っても、自分の木の丸太は増えない
	w.market.buy("logs")
	_check(c.materials.log == 6 and c.own_log_count() == 1, "買い足しても自分の丸太は増えない")
	# 薪にしても同じ
	var w2 := _world()
	_fell_tree(w2)
	w2.garden.produce.potato = 4
	w2.kitchen.start("pirozhki")
	_check(w2.cabin.materials.log == 1 and w2.cabin.own_log_count() == 1, "薪に割ると自分の丸太も減る")

func _test_place() -> void:
	print("巣箱を置く")
	var w := _world()
	var b := w.bees
	_check(b.act(AT) == "no_wood" and b.hives.is_empty(), "丸太がないと置けない")
	w.market.buy("logs")
	_check(b.act(AT) == "no_wood" and w.cabin.materials.log == 5, "市場の丸太では作れない。丸太は減らない")
	_fell_tree(w)
	_check(b.act(AT) == "placed" and b.hives.size() == 1, "自分の丸太で置ける")
	_check(w.cabin.materials.log == 5 and w.cabin.own_log_count() == 0, "自分の丸太を 2 本使う(市場の 5 本は残る)")
	_check(FileAccess.file_exists(TEST_SAVE), "置くと保存する")
	# 上限
	var w2 := _world()
	for i in range(Bees.MAX_HIVES):
		w2.cabin.materials.log += 2
		w2.cabin.own_logs += 2
		_check(w2.bees.act(AT + Vector2(i * 5, 0)) == "placed", "%d つ目を置ける" % (i + 1))
	w2.cabin.materials.log += 2
	w2.cabin.own_logs += 2
	_check(w2.bees.act(AT + Vector2(20, 0)) == "too_many" and w2.cabin.own_log_count() == 2, "%d つまで。丸太は減らない" % Bees.MAX_HIVES)

func _test_blocked() -> void:
	print("置けない場所")
	var w := _world()
	var b := w.bees
	w.cabin.materials.log = 20
	w.cabin.own_logs = 20
	_check(b.act(Vector2(49, 0)) == "blocked", "境界のそばには置けない")
	w.land.plots.append(Vector2(1.5, 1.5))
	_check(b.act(Vector2(1.5, 1.5)) == "blocked", "区画の上には置けない")
	_check(b.act(Vector2(3.5, 1.5)) == "blocked", "区画のすぐそばにも置けない")
	w.cabin.site = Vector2(20, 20)
	_check(b.act(Vector2(20, 20)) == "blocked", "小屋の上には置けない")
	w.land.pond = Vector2(-20, 20)
	_check(b.act(Vector2(-20, 24)) == "blocked", "池にかかる場所には置けない")
	w.forest.trees.append({"pos": Vector2(30, 0), "species": "birch", "form": "sapling", "planted_at": w.forest._now(), "start_age": 3.0, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	_check(b.act(Vector2(30.5, 0)) == "blocked", "木のそばには置けない")
	_check(w.cabin.own_log_count() == 20, "置けなければ丸太は減らない")
	_check(b.act(AT) == "placed", "開けた場所には置ける")
	_check(b.act(AT + Vector2(1.5, 0)) != "placed", "巣箱の近くでは、新しく置かない(その巣箱の作業になる)")
	_check(b.hives.size() == 1, "前提: まだ 1 つ")
	_check(b.act(AT + Vector2(2.5, 0)) == "placed" and b.hives.size() == 2, "離れていれば置ける")

	# ほかのものも巣箱に重ねられない
	var w2 := _world()
	w2.cabin.materials.log = 2
	w2.cabin.own_logs = 2
	w2.bees.act(Vector2(1.5, 1.5))
	_check(w2.toggle_plot(Vector2(1.5, 1.5)) == "hive", "巣箱の上に区画を作れない")
	_check(w2.pond_action(Vector2(3, 1.5)) == "hive", "巣箱にかかる場所に池を掘れない")
	_check(not w2.wildlife.is_free(Vector2(1.5, 1.5)), "生き物は巣箱の上に行かない")

func _test_hollow() -> void:
	print("くり抜く")
	var w := _world()
	var b := w.bees
	w.cabin.materials.log = 2
	w.cabin.own_logs = 2
	b.act(AT)
	var h: Dictionary = b.hive_near(AT)
	_check(not Bees.is_hollowed(h) and not b.has_empty_hive(), "置いただけではまだ巣箱ではない")
	_check(b.act(AT) == "hollowed" and h.days_done == 1, "1 日目をくり抜く")
	_check(b.act(AT) == "done_today" and h.days_done == 1, "1 日 1 回")
	h.last_worked = ""
	_check(b.act(AT) == "hollowed" and h.days_done == 2, "2 日目")
	h.last_worked = ""
	_check(b.act(AT) == "finished" and Bees.is_hollowed(h), "3 日でできあがる")
	_check(b.has_empty_hive() and int(h.hollowed_day) == w.forest.day_number(), "空の巣箱になる")
	_check(b.act(AT) == "empty", "蜂がいないと採れない")
	_check(b.act(AT + Vector2(1.0, 1.0)) == "empty", "そばからでも同じ巣箱の作業になる")
	var w2 := _world()
	w2.cabin.materials.log = 2
	w2.cabin.own_logs = 2
	_check(w2.bees.act(AT, AT + Vector2(0, 1.2)) == "placed" and w2.bees.hives[0].pos == AT + Vector2(0, 1.2), "体の前に置ける")
	_check(w2.bees.hive_near(AT).pos == AT + Vector2(0, 1.2), "置いた場所から、そのまま作業できる")

func _test_natural_swarm() -> void:
	print("自然に蜂が入る")
	# 季節と確率: 1 年を数える。日付で決まるので毎回同じ
	var w := _world()
	var b := w.bees
	var hits := {"spring": 0, "summer": 0}
	var days := {"spring": 0, "summer": 0}
	for d in range(20000, 21095):  # 3 年
		var s := Bees.season_of(d)
		if s in Bees.SWARM_SEASONS:
			days[s] += 1
			if b._swarm_roll(d, 0):
				hits[s] += 1
	var total: int = hits.spring + hits.summer
	var rate: float = float(total) / (days.spring + days.summer)
	_check(rate > 0.05 and rate < 0.12, "春と夏の 1 日あたり 8%% 前後(実測 %.1f%%)" % (rate * 100.0))
	_check(b._swarm_roll(20100, 0) == b._swarm_roll(20100, 0), "同じ日付なら同じ結果(開き直しても変わらない)")
	_check(Bees.season_of(20763) == "autumn", "2026-11-06 は秋")

	# 春の日に確実に入る日を探す
	var spring_hit := -1
	for d in range(20000, 21000):
		if Bees.season_of(d) == "spring" and b._swarm_roll(d, 0):
			spring_hit = d
			break
	_check(spring_hit > 0, "前提: 春に入る日がある")
	# 冬や秋は入らない
	var autumn_or_winter := 0
	var w2 := _world()
	var h2 := _ready_hive(w2)
	var today: int = w2.forest.day_number()
	h2.hollowed_day = today - 400
	w2.bees.last_checked_day = today - 1
	# 今日が秋なら、今日の分だけ数えても入らない
	if not (Bees.season_of(today) in Bees.SWARM_SEASONS):
		w2.bees.catch_up()
		autumn_or_winter = 1 if h2.occupied else 0
		_check(autumn_or_winter == 0, "%s は自然には入らない" % Bees.season_of(today))
	# 閉じているあいだの分も数える: 1 年前から。春夏を通るのでいずれ入る
	var w3 := _world()
	var h3 := _ready_hive(w3)
	h3.hollowed_day = w3.forest.day_number() - 400
	w3.bees.last_checked_day = w3.forest.day_number() - 300
	w3.bees.catch_up()
	_check(h3.occupied and w3.bees.last_arrivals == 1, "閉じていたあいだに春夏があれば、入っている")
	_check(w3.bees.last_checked_day == w3.forest.day_number(), "数え終えた日を覚える")
	# くり抜く前は入らない
	var w4 := _world()
	w4.cabin.materials.log = 2
	w4.cabin.own_logs = 2
	w4.bees.act(AT)
	w4.bees.last_checked_day = w4.forest.day_number() - 300
	w4.bees.catch_up()
	_check(not w4.bees.hive_near(AT).occupied, "くり抜く前の巣箱には入らない")

func _fyodor_day() -> int:
	var d := 20000
	while not (Visitors.is_visit_day(d) and Visitors.who_on(d) == "fyodor"):
		d += 1
	return d

func _test_share() -> void:
	print("分けてもらう")
	var w := _world("autumn")
	var vs := w.visitors
	var d := _fyodor_day()
	_check(vs._generate(d).kind != "bees", "巣箱がなければ分けてくれない")
	var h := _ready_hive(w)
	_check(vs._generate(d).kind == "bees", "空の巣箱があれば、フョードルさんが分けてくれる")
	var other := d
	while not (Visitors.is_visit_day(other) and Visitors.who_on(other) == "nina"):
		other += 1
	_check(vs._generate(other).kind != "bees", "ほかの人は分けてくれない")
	for season in ["spring", "summer", "autumn"]:
		w.forest.season = season
		_check(vs._generate(d).kind == "bees", "%s は分けてもらえる" % season)
	w.forest.season = "winter"
	_check(vs._generate(d).kind != "bees", "冬は分けてもらえない")
	w.forest.season = "autumn"

	vs.visit = vs._generate(d)
	vs.visit.day = w.forest.day_number()
	_check(vs.has_bees() and not vs.has_request() and vs.give() == "none", "蜂の日は頼みごとではない")
	_check(vs.receive_bees() == "received" and h.occupied and not vs.is_here(), "分けてもらうと巣箱に蜂が入り、帰る")
	_check(vs.receive_bees() == "none", "二度はもらえない")
	_check(vs._generate(d).kind != "bees", "空の巣箱がなければ、もう分けない")

	# 今日のうちに巣箱ができたとき
	var w2 := _world("autumn")
	w2.visitors.visit = {"day": w2.forest.day_number(), "who": "fyodor", "kind": "chat", "done": false, "line": 0}
	w2.visitors.check_today()
	_check(w2.visitors.visit.kind == "chat", "巣箱がなければ話すだけ")
	_ready_hive(w2)
	w2.visitors.check_today()
	_check(w2.visitors.has_bees(), "今日のうちに巣箱ができれば、分けてくれる")
	# 手詰まりのほうを先に助ける
	var w3 := _world("autumn")
	_ready_hive(w3)
	w3.market.money = 10
	_check(w3.visitors.is_stuck() and w3.visitors._generate(d).kind == "help", "手詰まりなら、先に種を分けてくれる")

func _test_honey() -> void:
	print("はちみつ")
	var w := _world("summer")
	var b := w.bees
	var h := _ready_hive(w)
	h.occupied = true
	_check(b.act(AT) == "not_yet" and int(b.stock.honey) == 0, "たまっていなければ採れない")
	_check(b.ready_count() == 0, "採れる巣箱はまだない")
	h.comb = 0.9
	_check(b.act(AT) == "not_yet", "1kg に満たなければ採れない")
	h.comb = 3.5
	_check(b.ready_count() == 1, "1kg たまると採れる")
	_check(b.act(AT) == "harvested" and b.last_harvest == 3 and int(b.stock.honey) == 3, "kg 単位で採れる")
	_check(is_equal_approx(float(h.comb), 0.5) and h.occupied, "端数は残り、蜂はいなくならない")

	# ためられる量と、季節ごとの増え方
	_check(b._rate_on("summer") == Bees.HONEY_RATE.summer, "畑が空なら基本の速さ")
	_check(b._rate_on("winter") == 0.0, "冬はたまらない")
	w.garden.crops.append({"pos": Vector2(1.5, 1.5), "kind": "radish", "sown_day": w.garden.day_number(), "water_days": 0, "last_watered": "", "head": 0.0})
	_check(is_equal_approx(b._rate_on("summer"), Bees.HONEY_RATE.summer + Bees.FLOWER_BONUS), "畑に野菜があると少し増える")
	_check(b._rate_on("winter") == 0.0, "冬は畑があってもたまらない")
	w.garden.crops.clear()
	h.comb = 0.0
	b.last_checked_day = w.forest.day_number() - 3
	var month_rate: float = 0.0
	for d in range(b.last_checked_day + 1, w.forest.day_number() + 1):
		month_rate += float(Bees.HONEY_RATE[Bees.season_of(d)])
	b.catch_up()
	_check(is_equal_approx(float(h.comb), month_rate), "閉じていたあいだの分もたまる(%.1fkg)" % float(h.comb))
	h.comb = 4.9
	b.last_checked_day = w.forest.day_number() - 100
	b.catch_up()
	_check(float(h.comb) == Bees.COMB_MAX, "ためられるのは %.0fkg まで" % Bees.COMB_MAX)
	b.stock.honey = 0
	h.comb = 0.9
	_check(b.ready_tomorrow() == (1 if 0.9 + b._rate_on(Bees.season_of(w.forest.day_number() + 1)) >= 1.0 else 0), "明日採れるかが分かる")

func _test_market() -> void:
	print("売る")
	var w := _world()
	w.bees.stock.honey = 3
	_check(w.market.count_of("honey") == 3, "市場で持っている数が分かる")
	var money: int = w.market.money
	_check(w.market.sell_all("honey") == 600 and w.market.money == money + 600 and int(w.bees.stock.honey) == 0, "はちみつ 3kg で 600₽")
	_check(w.market.sell_all("honey") == 0, "なければ売れない")
	w.bees.stock.honey = 1
	_check(w.visitors.available("honey") == 1, "訪問者に渡せる")
	_check(w.visitors._choose_item("tanya") == "honey", "ターニャさんははちみつを頼む")
	var w2 := _world()
	w2.market.money = 10
	w2.bees.stock.honey = 1
	_check(not w2.visitors.is_stuck(), "お金がなくても、はちみつがあれば売れるので手詰まりではない")

func _test_catch_up() -> void:
	print("日付の確認")
	var w := _world()
	var b := w.bees
	b.catch_up()
	_check(b.last_checked_day == w.forest.day_number(), "はじめての確認は、今日から数える")
	var h := _ready_hive(w)
	h.occupied = true
	h.comb = 0.0
	b.catch_up()
	_check(float(h.comb) == 0.0, "同じ日に何度確認しても増えない")
	# GameWorld の日付の確認から呼ばれる
	var w2 := _world()
	var h2 := _ready_hive(w2)
	h2.occupied = true
	w2.bees.last_checked_day = w2.forest.day_number() - 2
	w2.forest.last_day = "2000-01-01"
	w2.check_new_day()
	_check(w2.bees.last_checked_day == w2.forest.day_number(), "日付が変わると数える")

func _test_save() -> void:
	print("セーブ")
	var w := _world()
	var b := w.bees
	w.cabin.materials.log = 5
	w.cabin.own_logs = 5
	b.act(AT)
	var h: Dictionary = b.hive_near(AT)
	h.days_done = Bees.HOLLOW_DAYS
	h.hollowed_day = 100
	h.occupied = true
	h.comb = 2.5
	b.stock.honey = 7
	b.last_checked_day = 12345
	w.save_game()
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	var b2 := w2.bees
	var h2: Dictionary = b2.hive_near(AT)
	_check(b2.hives.size() == 1 and h2.pos == AT and h2.days_done == Bees.HOLLOW_DAYS, "巣箱が残る")
	_check(h2.occupied and is_equal_approx(float(h2.comb), 2.5) and int(h2.hollowed_day) == 100, "蜂とはちみつが残る")
	_check(int(b2.stock.honey) == 7 and b2.last_checked_day == 12345, "持っているはちみつと確認した日が残る")
	_check(w2.cabin.own_log_count() == 3 and w2.cabin.materials.log == 3, "自分の丸太が残る")
	_remove_save()
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"unit": "m", "trees": [], "cabin": {"site": [10, 20], "stage": 0, "days_done": 1, "logs": 2}}))
	f.close()
	var w3 := GameWorld.new()
	w3.save_path = TEST_SAVE
	w3.load_game()
	_check(w3.bees.hives.is_empty() and int(w3.bees.stock.honey) == 0, "記録がないセーブは、巣箱なしから")
	_check(w3.cabin.materials.log == 2 and w3.cabin.own_log_count() == 0, "前のセーブの丸太は、自分の木に数えない")
