extends SceneTree

# 土地に来る生き物のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_wildlife.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Wildlife = preload("res://logic/Wildlife.gd")

const TEST_SAVE := "user://test_wildlife.json"
const NOON := {"month": 10, "day": 15, "hour": 12, "minute": 0, "second": 0}
const MIDNIGHT := {"month": 10, "day": 15, "hour": 23, "minute": 30, "second": 0}
# 10 月 15 日の日の入りのころ(暗くなりはじめ)
const DUSK := {"month": 10, "day": 15, "hour": 17, "minute": 10, "second": 0}

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_nothing_on_empty_land()
	_test_trees_bring_birds_and_squirrels()
	_test_crops_bring_insects()
	_test_plots_bring_night_animals()
	_test_time_of_day()
	_test_seasons()
	_test_rain()
	_test_daily_events()
	_test_arrivals()
	_test_preview_not_counted()
	_test_save()
	_test_places()
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

# 秋の昼の、何もない土地
func _world() -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.forest.season = "autumn"
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birch_seed"
	w.forest.trees.clear()
	w.clock.fixed_now = NOON
	return w

func _add_trees(w: GameWorld, n: int, age: float) -> void:
	for i in range(n):
		w.forest.trees.append({"pos": Vector2(i * 3 - 20, 10), "species": "birch", "form": "sapling", "planted_at": w.forest._now(), "start_age": age, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})

func _add_crops(w: GameWorld, n: int) -> void:
	for i in range(n):
		w.garden.crops.append({"pos": Vector2(i * 3 + 1.5, 1.5), "kind": "radish", "sown_day": w.garden.day_number(), "water_days": 0, "last_watered": "", "head": 0.0})

func _add_plots(w: GameWorld, n: int) -> void:
	for i in range(n):
		w.land.plots.append(Vector2((i % 20) * 3 + 1.5, (int(i / 20.0)) * 3 + 1.5))

func _test_nothing_on_empty_land() -> void:
	print("何もない土地")
	var w := _world()
	_check(w.wildlife.counts().is_empty(), "昼は何も来ない")
	w.clock.fixed_now = MIDNIGHT
	_check(w.wildlife.counts().is_empty(), "夜も何も来ない")

func _test_trees_bring_birds_and_squirrels() -> void:
	print("木が増えると来る")
	var w := _world()
	var wl := w.wildlife
	_add_trees(w, 2, 1.0)
	_check(not wl.counts().has("sparrow"), "木 2 本では小鳥は来ない")
	_add_trees(w, 1, 1.0)
	_check(wl.counts().sparrow == 1, "木 3 本で小鳥が来る")
	_add_trees(w, 21, 1.0)
	_check(wl.counts().sparrow == 6, "小鳥は木が増えると増える(24 本で 6 羽)")
	_add_trees(w, 40, 1.0)
	_check(wl.counts().sparrow == 6, "小鳥は 6 羽まで")
	_check(not wl.counts().has("squirrel"), "若い木だけならリスは来ない")
	var w2 := _world()
	_add_trees(w2, 2, 6.0)
	_check(not w2.wildlife.counts().has("squirrel"), "育った木 2 本ではリスは来ない")
	_add_trees(w2, 1, 6.0)
	_check(w2.wildlife.counts().squirrel == 1, "育った木 3 本でリスが来る")
	_add_trees(w2, 40, 6.0)
	_check(w2.wildlife.counts().squirrel == 3, "リスは 3 匹まで")
	var w3 := _world()
	w3.forest.trees.append({"pos": Vector2(1, 1), "species": "birch", "form": "seed", "planted_at": w3.forest._now(), "start_age": 0.0, "sprouts": false, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	w3.forest.trees.append(w3.forest.trees[0].duplicate())
	w3.forest.trees.append(w3.forest.trees[0].duplicate())
	_check(not w3.wildlife.counts().has("sparrow"), "芽が出ていない種は木に数えない")

func _test_crops_bring_insects() -> void:
	print("野菜があると虫が来る")
	var w := _world()
	_add_plots(w, 2)
	_check(not w.wildlife.counts().has("butterfly"), "区画だけでは虫は来ない")
	_add_crops(w, 1)
	_check(w.wildlife.counts().butterfly == 1 and w.wildlife.counts().bee == 2, "野菜が 1 区画でチョウとミツバチが来る")
	_add_crops(w, 40)
	_check(w.wildlife.counts().butterfly == 5 and w.wildlife.counts().bee == 6, "増えても上限まで")

func _test_plots_bring_night_animals() -> void:
	print("夜の生き物")
	var w := _world()
	w.clock.fixed_now = MIDNIGHT
	_add_plots(w, 3)
	_check(not w.wildlife.counts().has("hare") and not w.wildlife.counts().has("hedgehog"), "区画 3 つでは来ない")
	_add_plots(w, 1)
	_check(w.wildlife.counts().hare == 1 and w.wildlife.counts().hedgehog == 1, "区画 4 つでノウサギとハリネズミが来る")
	_add_plots(w, 76)
	_check(w.wildlife.counts().hare == 2 and w.wildlife.counts().hedgehog == 2, "区画が増えると増える(2 匹まで)")
	var w2 := _world()
	w2.clock.fixed_now = MIDNIGHT
	_add_trees(w2, 10, 1.0)
	_check(w2.wildlife.counts().has("hedgehog") and not w2.wildlife.counts().has("hare"), "木が 10 本あればハリネズミは来る。ノウサギは来ない")

func _test_time_of_day() -> void:
	print("時間帯")
	var w := _world()
	var wl := w.wildlife
	_add_trees(w, 10, 6.0)
	_add_crops(w, 4)
	_add_plots(w, 8)
	var day: Dictionary = wl.counts()
	_check(day.has("sparrow") and day.has("squirrel") and day.has("butterfly") and day.has("bee"), "昼は小鳥・リス・チョウ・ミツバチ")
	_check(not day.has("hare") and not day.has("hedgehog"), "昼はノウサギもハリネズミもいない")
	_check(wl.darkness() < 0.01, "前提: 昼の暗さは 0")
	w.clock.fixed_now = MIDNIGHT
	var night: Dictionary = wl.counts()
	_check(night.has("hare") and night.has("hedgehog"), "夜はノウサギとハリネズミ")
	_check(not night.has("sparrow") and not night.has("bee"), "夜は小鳥も虫もいない")
	_check(wl.darkness() > 0.99, "前提: 夜の暗さは 1")
	w.clock.fixed_now = DUSK
	var d: float = wl.darkness()
	var dusk: Dictionary = wl.counts()
	_check(d >= wl.DUSK_DARKNESS and d < wl.NIGHT_DARKNESS, "前提: 夕方の暗さは途中(%.2f)" % d)
	_check(dusk.has("hare") and not dusk.has("hedgehog"), "夕方はノウサギが出て、ハリネズミはまだ")
	w.clock.fixed_now = NOON
	w.clock.preview_hours = 11.5
	_check(wl.counts().has("hedgehog"), "N のプレビューの時間にも合う")

func _test_seasons() -> void:
	print("季節")
	var w := _world()
	_add_trees(w, 10, 6.0)
	_add_crops(w, 4)
	_add_plots(w, 8)
	for s in ["spring", "summer", "autumn"]:
		w.forest.season = s
		_check(w.wildlife.counts().has("butterfly"), "%s はチョウがいる" % s)
	w.forest.season = "winter"
	var winter: Dictionary = w.wildlife.counts()
	_check(not winter.has("butterfly") and not winter.has("bee"), "冬は虫がいない")
	_check(winter.has("sparrow") and winter.has("squirrel"), "冬も小鳥とリスはいる")
	w.clock.fixed_now = MIDNIGHT
	var winter_night: Dictionary = w.wildlife.counts()
	_check(not winter_night.has("hedgehog") and winter_night.has("hare"), "冬の夜: ハリネズミは冬眠。ノウサギはいる")
	_check(not winter_night.has("woodpecker"), "冬の夜: アカゲラはいない")
	w.clock.fixed_now = NOON
	_check(int(winter.get("woodpecker", 0)) == 2, "冬の昼: 育った木 10 本でアカゲラが 2 羽")
	w.forest.season = "autumn"
	_check(not w.wildlife.counts().has("woodpecker"), "アカゲラが来るのは冬")

	# アカゲラは育った木が 3 本から
	var w2 := _world()
	w2.forest.season = "winter"
	_add_trees(w2, 2, 6.0)
	_check(not w2.wildlife.counts().has("woodpecker"), "育った木 2 本では来ない")
	_add_trees(w2, 3, 1.0)
	_check(not w2.wildlife.counts().has("woodpecker"), "若い木は数えない")
	w2.forest.trees.append({"pos": Vector2(30, 30), "species": "birch", "form": "sapling", "planted_at": w2.forest._now(), "start_age": 6.0, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	_check(int(w2.wildlife.counts().get("woodpecker", 0)) == 1, "育った木 3 本で 1 羽")
	var rng := RandomNumberGenerator.new()
	var homes := {}
	for i in range(30):
		homes[w2.wildlife.home_for("woodpecker", rng, Vector2.ZERO)] = true
	_check(homes.keys().all(func(p): return w2.forest.trees.any(func(t): return t.pos == p and w2.forest.real_age_years(t) >= 5.0)), "とまるのは育った木の幹")

func _test_rain() -> void:
	print("雨")
	var w := _world()
	_add_trees(w, 10, 6.0)
	_add_crops(w, 4)
	w.forest.today_event = "rain"
	var rainy: Dictionary = w.wildlife.counts()
	_check(not rainy.has("butterfly") and not rainy.has("bee"), "雨の日は虫が飛ばない")
	_check(rainy.has("sparrow"), "雨の日も小鳥はいる")

func _test_daily_events() -> void:
	print("今日の発見")
	var w := _world()
	_check(not w.wildlife.counts().has("migrant"), "ふだんは渡り鳥はいない")
	w.forest.today_event = "birds"
	_check(w.wildlife.counts().migrant == Wildlife.MIGRANT_FLOCK, "渡り鳥の発見の日は、木がなくても群れが来る")
	w.forest.last_day = "2000-01-01"
	_check(not w.wildlife.counts().has("migrant"), "前の日の発見では来ない")
	var w2 := _world()
	w2.forest.today_event = "cedar_seed"
	_check(w2.wildlife.counts().squirrel == 1, "杉の実を置いていった日は、木がなくてもリスがいる")
	w2.clock.fixed_now = MIDNIGHT
	_check(not w2.wildlife.counts().has("squirrel"), "その日でも夜はいない")

func _test_arrivals() -> void:
	print("はじめて来た")
	var w := _world()
	var wl := w.wildlife
	_check(wl.check_arrivals().is_empty(), "何も来ていなければ空")
	_add_trees(w, 3, 1.0)
	_check(wl.check_arrivals() == ["sparrow"], "はじめて来たら知らせる")
	_check(wl.check_arrivals().is_empty(), "二度は知らせない")
	_check(FileAccess.file_exists(TEST_SAVE), "覚えたら保存する")
	w.clock.fixed_now = MIDNIGHT
	wl.check_arrivals()
	w.clock.fixed_now = NOON
	_check(wl.check_arrivals().is_empty(), "いなくなって戻っても、また知らせない")

func _test_preview_not_counted() -> void:
	print("プレビューでは覚えない")
	var w := _world()
	_add_plots(w, 8)
	w.clock.preview_hours = 11.5
	_check(w.wildlife.counts().has("hare"), "前提: プレビューの夜にはノウサギが見える")
	_check(w.wildlife.check_arrivals().is_empty() and w.wildlife.seen.is_empty(), "時間のプレビュー中は覚えない")
	w.clock.preview_hours = 0.0
	_add_trees(w, 3, 1.0)
	w.forest.time_offset_years = 5.0
	_check(w.wildlife.check_arrivals().is_empty(), "年のプレビュー中も覚えない")
	w.forest.time_offset_years = 0.0
	_check(w.wildlife.check_arrivals() == ["sparrow"], "プレビューをやめると覚える")

func _test_save() -> void:
	print("セーブ")
	var w := _world()
	_add_trees(w, 3, 1.0)
	w.wildlife.check_arrivals()
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	_check(w2.wildlife.seen == ["sparrow"], "見かけた生き物が残る")
	w2.wildlife.from_save({"seen": ["sparrow", "gone", "hare"]})
	_check(w2.wildlife.seen == ["sparrow", "hare"], "知らない生き物のセーブは無視する")
	_remove_save()
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"unit": "m", "trees": []}))
	f.close()
	var w3 := GameWorld.new()
	w3.save_path = TEST_SAVE
	w3.load_game()
	_check(w3.wildlife.seen.is_empty(), "記録がないセーブは、まだ何も来ていない")

func _test_places() -> void:
	print("行ける場所")
	var w := _world()
	var wl := w.wildlife
	_check(wl.is_free(Vector2(0, 0)), "土地の中は行ける")
	_check(not wl.is_free(Vector2(50, 0)) and not wl.is_free(Vector2(0, -60)), "土地の外へは行かない")
	w.cabin.site = Vector2(20, 20)
	_check(not wl.is_free(Vector2(20, 20)) and not wl.is_free(Vector2(22.2, 20)), "小屋の上へは行かない")
	_check(wl.is_free(Vector2(23, 20)), "小屋の外は行ける")
	w.land.pond = Vector2(-20, -20)
	_check(not wl.is_free(Vector2(-20, -20)) and wl.is_free(Vector2(-25, -20)), "池の上へは行かない")

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_add_trees(w, 3, 1.0)
	var tree_home: Vector2 = wl.home_for("sparrow", rng, Vector2.ZERO)
	_check(w.forest.trees.any(func(t): return t.pos == tree_home), "小鳥の住みかは木")
	_add_crops(w, 2)
	var crop_home: Vector2 = wl.home_for("bee", rng, Vector2.ZERO)
	_check(w.garden.crops.any(func(c): return c.pos == crop_home), "ミツバチの住みかは畑")
	_add_plots(w, 2)
	_check(wl.home_for("hare", rng, Vector2.ZERO) in w.land.plots, "ノウサギの住みかは区画")
	var near := Vector2(40, 0)
	var flock: Vector2 = wl.home_for("migrant", rng, near)
	_check(flock.distance_to(near) == Wildlife.MIGRANT_NEAR and flock.x < near.x, "渡り鳥は足元の近く、土地の内側に降りる")
	_check(wl.home_for("migrant", rng, Vector2.ZERO).distance_to(Vector2.ZERO) == Wildlife.MIGRANT_NEAR, "土地の真ん中でも降りられる")
