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
	w.market.money = 20
	for d in range(20000, 20060):
		if Visitors.is_visit_day(d):
			var v: Dictionary = w.visitors._generate(d)
			if v.kind != "chat":
				_check(false, "%d 日: 何も持っていないのに頼まれた" % d)
				return
	_check(true, "何も持っていなければ、いつも話すだけ")

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
