extends SceneTree

# 「ここに置けるか」などのルールのロジックテスト(レビュー C3。前は Main にあり、ロジックのテストで守られていなかった)。
# 木を植えられない場所・小屋と増築を建てられない場所・雪かきと歩く速さ・苗を種より先に使う。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_places.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Cabin = preload("res://logic/Cabin.gd")
const Kitchen = preload("res://logic/Kitchen.gd")
const Snow = preload("res://logic/Snow.gd")

const TEST_SAVE := "user://test_places.json"
const OPEN := Vector2(-30, 30)  # 何もない場所

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_tree_spots()
	_test_cabin_spots()
	_test_extension_spots()
	_test_walk_speed()
	_test_plant_crop()
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
	w.forest.season = "spring"
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birds"
	return w

func _hive(w: GameWorld, at: Vector2) -> void:
	w.bees.hives.append({"pos": at, "days_done": 0, "last_worked": "", "hollowed_day": -1, "occupied": false, "comb": 0.0})

func _feeder(w: GameWorld, at: Vector2) -> void:
	w.feeders.feeders.append({"pos": at, "fed_day": -1, "offered_day": -1})

func _test_tree_spots() -> void:
	print("木を植えられない場所")
	var w := _world()
	var r: float = w.bees.CLEARANCE
	_check(w.tree_spot_problem(OPEN) == "", "何もない場所には植えられる")
	_check(w.tree_spot_problem(Vector2(w.forest.LAND_HALF + 1.0, 0)) == "outside", "土地の外には植えられない")
	_hive(w, Vector2(-30, 20))
	_check(w.tree_spot_problem(Vector2(-30, 20 + r * 0.5)) == "hive", "巣箱の近くには植えられない")
	_check(w.tree_spot_problem(Vector2(-30, 20 + r + 1.0)) == "", "巣箱から離れれば植えられる")
	_feeder(w, Vector2(-20, 20))
	_check(w.tree_spot_problem(Vector2(-20, 20)) == "feeder", "餌台の近くには植えられない")
	w.well.site = Vector2(-10, 20)
	_check(w.tree_spot_problem(Vector2(-10, 20)) == "well", "井戸の近くには植えられない")
	w.mill.site = Vector2(0, 20)
	_check(w.tree_spot_problem(Vector2(0, 20)) == "mill", "石臼の近くには植えられない")
	w.family.choose("alyona", 0)
	w.family.tent = Vector2(10, 20)
	_check(w.family.has_tent() and w.tree_spot_problem(Vector2(10, 20)) == "tent", "テントの近くには植えられない")
	w.cabin.site = Vector2(30, -20)
	_check(w.tree_spot_problem(Vector2(30, -20)) == "cabin", "小屋の場所には植えられない")
	var yard: Vector2 = Vector2(30, -20) + Cabin.YARD_RECT.get_center()
	_check(not w.cabin.covers(yard) and w.tree_spot_problem(yard) == "yard", "小屋の東の庭には植えられない")
	# 土地の外は、ほかの物より先に断る(外の林では種を拾うだけ)
	w.well.site = Vector2(w.forest.LAND_HALF + 1.0, 0)
	_check(w.tree_spot_problem(w.well.site) == "outside", "土地の外は、ほかの理由より先")

func _test_cabin_spots() -> void:
	print("小屋を建てはじめられない場所")
	var w := _world()
	_check(w.cabin_spot_problem(OPEN) == "", "何もない場所には建てられる")
	var half := Vector2(Cabin.WIDTH, Cabin.DEPTH) * 0.5
	_hive(w, OPEN + Vector2(half.x + 0.2, 0))
	_check(w.cabin_spot_problem(OPEN) == "hive", "巣箱にかかる場所には建てられない")
	w = _world()
	_feeder(w, OPEN + Vector2(0, half.y))
	_check(w.cabin_spot_problem(OPEN) == "feeder", "餌台にかかる場所には建てられない")
	w = _world()
	w.well.site = OPEN + Vector2(-half.x - w.well.RADIUS, 0)
	_check(w.cabin_spot_problem(OPEN) == "well", "井戸にかかる場所には建てられない(井戸の大きさも数える)")
	w = _world()
	w.mill.site = OPEN + Vector2(0, -half.y - w.mill.RADIUS)
	_check(w.cabin_spot_problem(OPEN) == "mill", "石臼にかかる場所には建てられない(石臼の大きさも数える)")
	w = _world()
	w.mill.site = OPEN + Vector2(half.x + w.bees.CLEARANCE + w.mill.RADIUS + 1.0, 0)
	_check(w.cabin_spot_problem(OPEN) == "", "離れていれば建てられる")
	_check(w.cabin_spot_problem(OPEN + Vector2(0.3, 0.2)) == "", "足元は四捨五入した場所で見る(Cabin.place と同じ)")

func _test_extension_spots() -> void:
	print("増築する場所にかかる物(市場で頼むとき)")
	var w := _world()
	_check(w.rect_problem(Rect2(OPEN, Vector2(4, 4))) == "", "何もなければかからない")
	_hive(w, OPEN + Vector2(2, 2))
	_check(w.rect_problem(Rect2(OPEN, Vector2(4, 4))) == "hive", "巣箱がかかる")
	_check(w.market.rect_problem.is_valid(), "市場の増築の確認も同じ関数を使う(GameWorld が渡す)")
	_check(w.market.rect_problem.call(Rect2(OPEN, Vector2(4, 4))) == "hive", "市場から呼んでも同じ結果")

func _test_walk_speed() -> void:
	print("雪かきと歩く速さ")
	var w := _world()
	_check(not w.can_shovel_at(OPEN) and is_equal_approx(w.walk_speed(OPEN, false), 1.0), "冬でなければ雪かきできず、ふつうの速さ")
	w.forest.season = "winter"
	if not w.forest.snowy_winter():
		_check(false, "(前提) テストの土地は雪の積もる冬")
		return
	_check(w.can_shovel_at(OPEN), "雪の冬は雪かきできる")
	_check(is_equal_approx(w.walk_speed(OPEN, true), Snow.SHOVEL_SPEED), "雪かきしながらは遅い")
	_check(w.snow.clear_at(OPEN) == "cleared" and is_equal_approx(w.walk_speed(OPEN, false), Snow.PATH_SPEED), "かいた道の上は速い")
	w.cabin.site = Vector2(30, -20)
	_check(not w.can_shovel_at(Vector2(30, -20)), "小屋の中では雪かきしない")
	var warm: String = Kitchen.RECIPES.keys().filter(func(id): return Kitchen.RECIPES[id].meal == "warm")[0]
	w.kitchen.ate_day = w.forest.day_number()
	w.kitchen.ate_foods = [warm]
	_check(is_equal_approx(w.walk_speed(Vector2(-30, 10), true), Kitchen.MEAL_SHOVEL_SPEED), "温まる食事のあとは雪かきが楽")
	var strong: String = Kitchen.RECIPES.keys().filter(func(id): return Kitchen.RECIPES[id].meal == "strength")[0]
	w.kitchen.ate_foods = [strong]
	_check(is_equal_approx(w.walk_speed(Vector2(-30, 10), false), Kitchen.MEAL_SPEED), "力がつく食事のあとは速く歩ける")
	_check(is_equal_approx(w.walk_speed(OPEN, false), Snow.PATH_SPEED * Kitchen.MEAL_SPEED), "かいた道と食事の効果は掛け合わせる")

func _test_plant_crop() -> void:
	print("野菜を植える: 苗があれば種より先に苗")
	var w := _world()
	var a := Vector2(-30, -30)
	var b := Vector2(-30, -26)
	w.land.toggle_plot(a)
	w.land.toggle_plot(b)
	w.garden.seeds.cucumber = 1
	w.seedlings.ready.cucumber = 1
	var first: Dictionary = w.plant_crop(a, "cucumber")
	_check(first.result == "sown" and first.from_seedling and w.seedlings.ready.cucumber == 0 and w.garden.seeds.cucumber == 1, "苗があれば苗を使い、種は残る")
	var second: Dictionary = w.plant_crop(b, "cucumber")
	_check(second.result == "sown" and not second.from_seedling and w.garden.seeds.cucumber == 0, "苗がなくなれば種をまく")
	var third: Dictionary = w.plant_crop(a, "cucumber")
	_check(third.result == "occupied" and not third.from_seedling, "結果は Garden.sow のまま返す")
