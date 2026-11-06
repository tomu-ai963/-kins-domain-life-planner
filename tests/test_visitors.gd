extends SceneTree

# 訪ねてくる人のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_visitors.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる

const GameWorld = preload("res://logic/GameWorld.gd")
const Visitors = preload("res://logic/Visitors.gd")
const Garden = preload("res://logic/Garden.gd")
const Kitchen = preload("res://logic/Kitchen.gd")

const TEST_SAVE := "user://test_visitors.json"

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_schedule()
	_test_nothing_to_give()
	_test_stuck_detection()
	_test_help()
	_test_request_contents()
	_test_likes()
	_test_rewards_by_season()
	_test_give()
	_test_chat()
	_test_stable_within_day()
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

func _world(season := "autumn") -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.forest.season = season
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birds"
	return w

# 頼みごとになる日を探して作る(話すだけの日を避ける)
func _request_day(w: GameWorld) -> int:
	var base: int = w.forest.day_number()
	for d in range(base, base + 400):
		if Visitors.is_visit_day(d):
			var v: Dictionary = w.visitors._generate(d)
			if v.kind == "request":
				return d
	return -1

func _test_schedule() -> void:
	print("来る日")
	var base := 20000
	var days := []
	for d in range(base, base + 100):
		if Visitors.is_visit_day(d):
			days.append(d)
	_check(days.size() == 40, "5 日に 2 回来る(100 日で %d 回)" % days.size())
	var gaps := {}
	for i in range(1, days.size()):
		gaps[days[i] - days[i - 1]] = true
	_check(gaps.size() == 2 and gaps.has(2) and gaps.has(3), "間は 2 日か 3 日")
	var seen := {}
	for d in days:
		seen[Visitors.who_on(d)] = int(seen.get(Visitors.who_on(d), 0)) + 1
	_check(seen.size() == 4 and seen.values().all(func(n): return n == 10), "4 人が同じ回数ずつ来る")
	_check(Visitors.who_on(days[0]) != Visitors.who_on(days[1]), "続けて同じ人は来ない")
	var w := _world()
	var v: Dictionary = w.visitors._generate(_next_quiet(days))
	_check(not v.has("who"), "来ない日は誰もいない")
	w.visitors.visit = v
	_check(not w.visitors.is_here() and not w.visitors.has_request(), "来ない日は is_here が false")

func _next_quiet(days: Array) -> int:
	for d in range(days[0], days[-1]):
		if not Visitors.is_visit_day(d):
			return d
	return 0

func _test_nothing_to_give() -> void:
	print("渡せるものがない日")
	var w := _world()
	w.market.money = 2000  # 種は買えるので、手詰まりではない
	for d in range(20000, 20060):
		if Visitors.is_visit_day(d):
			var v: Dictionary = w.visitors._generate(d)
			if v.kind != "chat":
				_check(false, "%d 日: 何も持っていないのに %s になった" % [d, v.kind])
				return
	_check(true, "何も持っていなくても、お金があれば話すだけ(種は買える)")

# 手詰まりの世界: お金が種より少なく、種も畑も売れるものもない
func _stuck_world(season := "autumn") -> GameWorld:
	var w := _world(season)
	w.market.money = 20
	return w

func _test_stuck_detection() -> void:
	print("手詰まりの判定")
	var w := _stuck_world()
	var vs := w.visitors
	_check(vs.is_stuck(), "お金 20₽・種なし・畑が空・売るものなしは手詰まり")

	# 手段が 1 つでもあれば手詰まりではない
	w.market.money = 40
	_check(not vs.is_stuck(), "一番安い種(40₽)を買えるなら手詰まりではない")
	w.market.money = 39
	_check(vs.is_stuck(), "39₽ なら手詰まり")
	w.garden.seeds.radish = 1
	_check(not vs.is_stuck(), "野菜の種があれば手詰まりではない")
	w.garden.seeds.radish = 0
	w.garden.crops.append({"pos": Vector2(1.5, 1.5), "kind": "radish", "sown_day": w.garden.day_number(), "water_days": 0, "last_watered": "", "head": 0.0})
	_check(not vs.is_stuck(), "畑に野菜があれば手詰まりではない")
	w.garden.crops.clear()
	for item in ["radish", "apple", "sauce"]:
		w.market.pile_of(item)[item] = 1
		_check(not vs.is_stuck(), "%s を持っていれば売れるので手詰まりではない" % item)
		w.market.pile_of(item)[item] = 0
	w.seedlings.ready.tomato = 1
	_check(not vs.is_stuck(), "育った苗があれば売れるので手詰まりではない")
	w.seedlings.ready.tomato = 0
	w.seedlings.pots.append({"kind": "tomato", "sown_day": w.forest.day_number(), "water_days": 1, "last_watered": w.forest.today()})
	_check(not vs.is_stuck(), "鉢に苗があれば手詰まりではない")
	w.seedlings.pots.clear()
	w.kitchen.pot = {"recipe": "jam", "start_day": w.forest.day_number()}
	_check(not vs.is_stuck(), "鍋に中身があれば手詰まりではない")
	w.kitchen.pot = {}

	# リンゴは実る季節だけ当てになる
	w.forest.trees.append({"pos": Vector2(1, 1), "species": "apple", "form": "sapling", "planted_at": w.forest._now(), "start_age": 8.0, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	w.forest.season = "autumn"
	_check(not vs.is_stuck(), "秋に実るリンゴがあれば手詰まりではない")
	w.forest.season = "spring"
	_check(vs.is_stuck(), "春はリンゴを当てにできないので手詰まり")
	# 丸太や木の種は売れないので、数えない
	w.cabin.materials.log = 50
	w.forest.seeds.birch = 50
	_check(vs.is_stuck(), "丸太や木の種があっても、売れないので手詰まり")

func _test_help() -> void:
	print("手詰まりのときは分けてくれる")
	var w := _stuck_world("autumn")
	var vs := w.visitors
	var d := _visit_day(w)
	var v: Dictionary = vs._generate(d)
	_check(v.kind == "help", "手詰まりなら、来た人が分けてくれる")
	_check(v.reward.type == "crop_seed" and v.reward.kind == "radish" and v.reward.count == Visitors.HELP_SEEDS, "秋は一番安いラディッシュの種を 3 つ")
	var quiet: Dictionary = vs._generate(_quiet_day(w))
	_check(not quiet.has("who"), "来ない日は助けに来ない(次の訪問を待つ)")

	# 季節ごとに、今まけるもの
	for season in ["spring", "summer", "autumn"]:
		var ws := _stuck_world(season)
		var r: Dictionary = ws.visitors._help_reward()
		var crop: Dictionary = Garden.CROPS[r.kind]
		_check(r.type == "crop_seed" and season in crop.seasons and not crop.get("seedling_only", false), "%s は今まける種(%s)" % [season, r.kind])
	var winter: Dictionary = _stuck_world("winter").visitors._help_reward()
	_check(winter.type == "money" and winter.amount == Visitors.HELP_MONEY, "冬はまける種がないのでお金")
	_check(Visitors.HELP_MONEY >= w.market.good("radish_seed").price * Visitors.HELP_SEEDS, "冬のお金で、春に同じだけの種を買える")

	# 受け取ると、手詰まりでなくなる
	vs.visit = v.duplicate(true)
	vs.visit.day = w.forest.day_number()
	_check(vs.has_help() and not vs.has_request() and vs.give() == "none", "分けてくれる日は、頼みごとではない")
	_check(vs.receive_help() == "received" and w.garden.seeds.radish == Visitors.HELP_SEEDS, "受け取ると種が増える")
	_check(not vs.is_here() and vs.receive_help() == "none", "受け取ると帰る。二度はもらえない")
	_check(not vs.is_stuck(), "受け取ると手詰まりでなくなる")
	var next_kind: String = vs._generate(d).kind
	_check(next_kind != "help", "手詰まりでなければ、もう分けてくれない")

	# 今日のうちに手詰まりになったとき
	var w2 := _world()
	w2.market.money = 2000
	var vs2 := w2.visitors
	vs2.visit = {"day": w2.forest.day_number(), "who": "nina", "kind": "chat", "done": false, "line": 0}
	vs2.check_today()
	_check(vs2.visit.kind == "chat", "手詰まりでなければ、話すだけのまま")
	w2.market.money = 10
	vs2.check_today()
	_check(vs2.has_help(), "今日のうちに手詰まりになれば、分けてくれる")
	var w3 := _stuck_world()
	w3.visitors.visit = {"day": w3.forest.day_number(), "who": "nina", "kind": "chat", "done": true, "line": 0}
	w3.visitors.check_today()
	_check(w3.visitors.visit.kind == "chat" and not w3.visitors.is_here(), "もう帰った人は戻ってこない")

	# セーブしても受け取れる(JSON で数が小数になっても)
	var w4 := _stuck_world()
	w4.visitors.visit = {"day": w4.forest.day_number(), "who": "fyodor", "kind": "help", "reward": {"type": "crop_seed", "kind": "radish", "count": 3}, "done": false, "line": 0}
	w4.save_game()
	var w5 := GameWorld.new()
	w5.save_path = TEST_SAVE
	w5.load_game()
	_check(w5.visitors.has_help() and w5.visitors.receive_help() == "received" and w5.garden.seeds.radish == 3, "読み直しても受け取れる")

func _visit_day(w: GameWorld) -> int:
	var d: int = w.forest.day_number()
	while not Visitors.is_visit_day(d):
		d += 1
	return d

func _quiet_day(w: GameWorld) -> int:
	var d: int = w.forest.day_number()
	while Visitors.is_visit_day(d):
		d += 1
	return d

func _test_request_contents() -> void:
	print("頼みごとの中身")
	var w := _world()
	w.garden.produce.tomato = 100
	w.forest.produce.apple = 100
	w.garden.produce.potato = 100
	var requests := 0
	var chats := 0
	var bad := 0
	for d in range(20000, 20500):
		if not Visitors.is_visit_day(d):
			continue
		var v: Dictionary = w.visitors._generate(d)
		if v.kind == "chat":
			chats += 1
			continue
		requests += 1
		var worth: int = w.visitors.value_of(v.item, v.amount)
		if v.amount <= 0 or v.amount > int(Visitors.ASK[v.item]):
			bad += 1
		if v.reward.type == "money" and (v.reward.amount < worth or v.reward.amount > worth * 1.5 + 10):
			bad += 1
	_check(bad == 0, "量とお金のお礼が決まりどおり(%d 件の頼みごとで違反 %d)" % [requests, bad])
	var share := float(chats) / (chats + requests)
	_check(share > 0.15 and share < 0.45, "渡せるものがあっても話すだけの日がある(%.0f%%)" % (share * 100.0))

	# 持っている量より多くは頼まない
	var w2 := _world()
	w2.garden.produce.tomato = 2
	var d: int = _request_day(w2)
	var v2: Dictionary = w2.visitors._generate(d)
	_check(v2.item == "tomato" and v2.amount == 2, "持っているのが 2kg なら 2kg だけ頼む")

	# 今収穫できる畑の分も数える
	var w3 := _world()
	w3.garden.crops.append({"pos": Vector2(1.5, 1.5), "kind": "radish", "sown_day": w3.garden.day_number() - 10, "water_days": 0, "last_watered": "", "head": 0.0})
	_check(w3.visitors.available("radish") == 6, "畑の収穫できる野菜も渡せる量に数える")
	w3.garden.crops[0].sown_day = w3.garden.day_number()
	_check(w3.visitors.available("radish") == 0, "まだ育っている野菜は数えない")

func _test_likes() -> void:
	print("人ごとの好み")
	var w := _world()
	w.garden.produce.tomato = 10
	w.forest.produce.apple = 10
	_check(w.visitors._choose_item("nina") == "tomato", "ニーナさんはトマトを頼む")
	_check(w.visitors._choose_item("tanya") == "apple", "ターニャさんはリンゴを頼む")
	var w2 := _world()
	w2.kitchen.stock.sauce = 3
	_check(w2.visitors._choose_item("pavel") == "sauce", "パーヴェルさんはトマトソースを頼む")
	_check(w2.visitors._choose_item("nina") == "sauce", "好みのものがなければ、渡せるものを頼む")
	for id in Visitors.CAST:
		for item in Visitors.CAST[id].likes:
			_check(Visitors.ASK.has(item), "%s の頼む %s に量がある" % [id, item])
	for item in Visitors.ASK:
		_check(w.market.SELL_PRICES.has(item), "%s に市場の値段がある" % item)

func _test_rewards_by_season() -> void:
	print("季節ごとのお礼")
	var rng := RandomNumberGenerator.new()
	for season in ["spring", "summer", "autumn", "winter"]:
		var w := _world(season)
		var kinds := {}
		var bad := 0
		for s in range(300):
			rng.seed = s
			var r: Dictionary = w.visitors._choose_reward("tomato", 5, rng)
			kinds[r.type] = true
			if r.type == "crop_seed":
				var crop: Dictionary = Garden.CROPS[r.kind]
				if not (season in crop.seasons) or crop.get("seedling_only", false) or r.count < 1:
					bad += 1
			if r.type == "seedling" and not (season in Visitors.SEEDLING_SEASONS):
				bad += 1
		_check(bad == 0, "%s: お礼の種や苗は今の季節に使える" % season)
		_check(kinds.has("money"), "%s: お金のお礼がある" % season)
		match season:
			"spring", "summer":
				_check(kinds.has("crop_seed") and kinds.has("seedling"), "%s: 種も苗ももらえる" % season)
			"autumn":
				_check(kinds.has("crop_seed") and not kinds.has("seedling"), "秋: 種はもらえるが、苗はもらえない")
			"winter":
				_check(kinds.size() == 1, "冬: まける種がないのでお金だけ")

func _test_give() -> void:
	print("渡す")
	var w := _world()
	var vs := w.visitors
	vs.visit = {"day": w.forest.day_number(), "who": "nina", "kind": "request", "item": "tomato", "amount": 5, "reward": {"type": "money", "amount": 260}, "done": false, "line": 0}
	_check(vs.is_here() and vs.has_request(), "頼みごとがある")
	w.garden.produce.tomato = 4
	var money: int = w.market.money
	_check(vs.give() == "short" and w.garden.produce.tomato == 4 and w.market.money == money and vs.is_here(), "足りなければ渡せず、何も変わらない")
	w.garden.produce.tomato = 7
	_check(vs.give() == "given", "足りれば渡せる")
	_check(w.garden.produce.tomato == 2 and w.market.money == money + 260, "トマトが減って、お金が増える")
	_check(not vs.is_here() and vs.give() == "none", "渡したら帰る。二度は渡せない")
	_check(FileAccess.file_exists(TEST_SAVE), "渡すと保存する")

	vs.visit = {"day": w.forest.day_number(), "who": "tanya", "kind": "request", "item": "apple", "amount": 5, "reward": {"type": "crop_seed", "kind": "radish", "count": 3}, "done": false, "line": 0}
	w.forest.produce.apple = 5
	var seeds: int = w.garden.seeds.radish
	_check(vs.give() == "given" and w.forest.produce.apple == 0 and w.garden.seeds.radish == seeds + 3, "リンゴを渡して種をもらう")

	vs.visit = {"day": w.forest.day_number(), "who": "pavel", "kind": "request", "item": "sauce", "amount": 2, "reward": {"type": "seedling", "kind": "tomato", "count": 1}, "done": false, "line": 0}
	w.kitchen.stock.sauce = 2
	_check(vs.give() == "given" and w.kitchen.stock.sauce == 0 and w.seedlings.ready.tomato == 1, "瓶を渡して苗をもらう")

func _test_chat() -> void:
	print("話すだけ")
	var w := _world()
	var vs := w.visitors
	vs.visit = {"day": w.forest.day_number(), "who": "fyodor", "kind": "chat", "done": false, "line": 4}
	_check(vs.is_here() and not vs.has_request() and vs.give() == "none", "話すだけの日は渡せない")
	vs.finish_chat()
	_check(not vs.is_here(), "話し終えると帰る")

func _test_stable_within_day() -> void:
	print("その日の中では変わらない")
	var w := _world()
	var vs := w.visitors
	w.garden.produce.tomato = 50
	vs.visit = {}
	_check(vs.check_today(), "はじめて見た日は決める")
	var first: Dictionary = vs.visit.duplicate(true)
	_check(not vs.check_today(), "同じ日は決め直さない")
	w.garden.produce.tomato = 0
	vs.check_today()
	_check(vs.visit == first, "持ち物が変わっても中身は変わらない")
	vs.visit.day = 1
	_check(vs.check_today() and vs.visit.day == w.forest.day_number(), "次の日になると決め直す")

	# check_new_day からも呼ばれる
	var w2 := _world()
	w2.visitors.visit = {}
	w2.check_new_day()
	_check(w2.visitors.visit.has("day"), "同じ日に開いても今日の訪問が決まる")
	var w3 := _world()
	w3.forest.last_day = "2000-01-01"
	w3.check_new_day()
	_check(int(w3.visitors.visit.day) == w3.forest.day_number(), "日付が変わったときも決まる")

func _test_save() -> void:
	print("セーブ")
	var w := _world()
	var vs := w.visitors
	vs.visit = {"day": w.forest.day_number(), "who": "nina", "kind": "request", "item": "tomato", "amount": 5, "reward": {"type": "money", "amount": 260}, "done": false, "line": 7}
	w.save_game()
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	var vs2 := w2.visitors
	_check(vs2.who() == "nina" and vs2.visit.item == "tomato" and vs2.visit.amount == 5 and vs2.visit.line == 7, "今日の訪問が残る")
	_check(vs2.visit.reward.type == "money" and int(vs2.visit.reward.amount) == 260, "お礼が残る")
	w2.garden.produce.tomato = 5
	_check(vs2.give() == "given", "読み直しても渡せる")
	w2.save_game()
	var w3 := GameWorld.new()
	w3.save_path = TEST_SAVE
	w3.load_game()
	w3.check_new_day()
	_check(not w3.visitors.is_here(), "渡したあとは、開き直しても来ない")
	vs2.from_save({"visit": {"day": 1, "who": "gone", "kind": "chat", "done": false}})
	_check(vs2.visit.is_empty(), "知らない人のセーブは無視する")
	_remove_save()
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"unit": "m", "trees": []}))
	f.close()
	var w4 := GameWorld.new()
	w4.save_path = TEST_SAVE
	w4.load_game()
	_check(w4.visitors.visit.is_empty(), "記録がないセーブは、まだ何も決まっていない")
