extends SceneTree

# 3D / 2D のシーンが組み上がり、ロジックの変化に view が付いてくるかのテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_views.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const TEST_SAVE := "user://test_views.json"
const DAY := 86400

var _failed := 0
var _passed := 0
var _frame := 0
var main  # いま試しているシーン(Main.gd)

func _initialize() -> void:
	_remove_save()
	main = _open("res://Main.tscn")

func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_test_3d_build()
			_test_3d_follows_logic()
			_test_3d_quest_marks()
			_test_3d_seasons_and_growth()
			_test_3d_market_and_pickups()
			_test_3d_garden()
			main.queue_free()
			_remove_save()
			main = _open("res://Main2D.tscn")
		4:
			_test_2d_still_works()
			main.queue_free()
			_remove_save()
		6:
			print("RESULT: %d passed, %d failed" % [_passed, _failed])
			quit(1 if _failed > 0 else 0)
	return false

func _open(path: String) -> Node:
	var m: Node = load(path).instantiate()
	m.world.save_path = TEST_SAVE  # _ready でセーブを読む前に、テスト用のファイルへ向ける
	root.add_child(m)
	return m

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

func _test_3d_build() -> void:
	print("3D のシーン")
	_check(main is Node3D and main.get_node("Player") is CharacterBody3D, "Main.tscn は 3D(Node3D + CharacterBody3D のプレイヤー)")
	_check(main.get_node("Ground").get_child_count() > 0, "地面ができている")
	var cam: Camera3D = main.get_node("Player/Camera3D")
	_check(cam.current and cam.global_position.y > 5.0, "カメラは上から見下ろしている")
	main.get_node("Player").global_position = Vector3(3, 0, -4)
	_check(main.player_pos() == Vector2(3, -4), "3D の (x, z) がロジックの (x, y) になる")

func _test_3d_follows_logic() -> void:
	print("ロジックの変化に付いてくる")
	var f = main.world.forest
	var trees: Node3D = main.get_node("Trees")
	f.today_event = "birds"  # 雨の日だと植えた木が最初から水やり済みになるので、雨でない日にする
	f.seeds["birch"] = 5
	f.seeds["apple"] = 5
	var before := trees.get_child_count()
	main._on_plant_tree(Vector2(10, 10))
	_check(f.trees.size() == 1 and trees.get_child_count() == before + 2, "植えると木(幹と樹冠)が増える")
	var sprout: MeshInstance3D = trees.get_child(1)  # 植えたばかりは苗木(樹冠の位置に芽)
	_check(is_equal_approx(sprout.position.x, 10.0) and is_equal_approx(sprout.position.z, 10.0), "木はロジックの位置(10, 10)に立つ")
	main.get_node("Player").global_position = Vector3(10, 0, 10.5)
	main._water()
	_check(trees.get_child_count() == 3, "水やりすると根元に水色の輪が出る")
	f.remove_nearest(Vector2(10, 10), 2.0)
	_check(trees.get_child_count() == 0, "抜くと木が消える")

	var land: Node3D = main.get_node("Land")
	main.get_node("Player").global_position = Vector3(1, 0, 1)
	main._toggle_plot()
	_check(land.get_child_count() == 4, "菜園の区画(土 + 畝 3 本)ができる")
	main.get_node("Player").global_position = Vector3(-20, 0, -20)
	main._toggle_pond()
	_check(land.get_child_count() == 7, "池(岸・水面・真ん中)ができる")
	main._toggle_pond()
	main.get_node("Player").global_position = Vector3(1, 0, 1)
	main._toggle_plot()
	_check(land.get_child_count() == 0, "取り消すと消える")

func _test_3d_quest_marks() -> void:
	print("クエストの目印")
	var w = main.world
	var marks: Node3D = main.get_node("Quests")
	_check(marks.get_child_count() == 80, "生垣の 40 区画に、まだの印(輪と杭)が出ている")
	w.forest.saplings["birch"] = 50
	w.forest.add_tree(w.quests.segment_center(0), "birch", "sapling")  # 根付いた木だけ数える
	_check(marks.get_child_count() == 79, "1 区画埋めると、その印が緑の丸(1 つ)に変わる")
	w.quests.stage = 3
	w.quests.changed.emit()
	_check(marks.get_child_count() == 1, "家族の杉の段階では中心 5m の輪だけ")
	w.quests.stage = 4
	w.quests.changed.emit()
	_check(marks.get_child_count() == 9, "完成すると光の輪 5 つと金色の縁 4 辺")

func _test_3d_seasons_and_growth() -> void:
	print("季節と成長")
	var f = main.world.forest
	var trees: Node3D = main.get_node("Trees")
	f.germination_rates = {"birch": 1.0, "apple": 1.0, "cedar": 1.0}  # 種は必ず芽が出る
	f.seeds["apple"] = 1
	f.add_tree(Vector2(-10, 5), "apple")
	f.trees[-1].planted_at = int(Time.get_unix_time_from_system()) - 6 * DAY  # 樹齢 6 年
	f.set_season("summer")
	f.set_season("autumn")  # 季節の変化で作り直す
	var n := trees.get_child_count()
	var crown: MeshInstance3D = trees.get_child(n - 6)  # 幹・樹冠・実 5 つの順
	_check(n >= 7, "秋の樹齢 6 年のリンゴには実が 5 つ付く")
	_check(is_equal_approx(crown.scale.x, 2.0 * f.radius_of(f.trees[-1])), "樹冠の幅は樹齢から決まる半径の 2 倍")
	f.advance_years(10.0)  # changed で作り直されるので、樹冠を取り直す
	crown = trees.get_child(trees.get_child_count() - 6)
	_check(crown.scale.x > 2.0 * 2.0, "時間を先送りすると樹冠が大きくなる")
	f.reset_preview()
	f.seeds["birch"] = 1
	f.add_tree(Vector2(-20, 5), "birch")
	f.trees[-1].planted_at = int(Time.get_unix_time_from_system()) - 3 * DAY
	f.set_season("winter")
	var birch_crown: MeshInstance3D = trees.get_child(trees.get_child_count() - 1)
	_check((birch_crown.material_override as StandardMaterial3D).albedo_color.a < 1.0, "冬の白樺は葉が落ちて樹冠が半透明")
	var ground_grass: MeshInstance3D = main.get_node("Ground").get_child(1)
	_check((ground_grass.material_override as StandardMaterial3D).albedo_color.b > 0.9, "冬の地面は雪原の色")

func _test_3d_market_and_pickups() -> void:
	print("市場と落ちた種")
	var w = main.world
	var hud = main.get_node("HUD")
	var player = main.get_node("Player")
	_check(main.get_node("Market").get_child_count() > 0, "南の境界の外に市場の屋台がある")
	player.global_position = Vector3(0, 0, 0)
	main._toggle_shop()
	_check(not hud.is_shop_open(), "市場から遠いと開かない")
	player.global_position = Vector3(0, 0, 54)
	main._toggle_shop()
	_check(hud.is_shop_open() and not player.is_physics_processing(), "市場の前で B を押すと開き、そのあいだは歩かない")
	var money: int = w.market.money
	main._on_shop_action("birch_seed")
	_check(w.market.money == money - 60, "画面から白樺の種を買える")
	w.forest.produce.apple = 4
	main._on_shop_action("sell_apple")
	_check(w.market.money == money - 60 + 60 and w.forest.produce.apple == 0, "画面からリンゴを売れる")
	main._on_shop_action("close")
	_check(not hud.is_shop_open() and player.is_physics_processing(), "閉じるとまた歩ける")

	var pickups: Node3D = main.get_node("Pickups")
	w.forest.pickups.append({"pos": Vector2(5, 5), "species": "birch", "amount": 5})
	w.forest.changed.emit()
	_check(pickups.get_child_count() == 1, "落ちている種が地面に出る")
	var seeds: int = w.forest.seeds.birch
	player.global_position = Vector3(5.5, 0, 5)
	main._collect_pickups()
	_check(pickups.get_child_count() == 0 and w.forest.seeds.birch == seeds + 5, "近づくと拾えて、地面から消える")

func _test_3d_garden() -> void:
	print("畑の野菜")
	var w = main.world
	var g = w.garden
	var hud = main.get_node("HUD")
	var player = main.get_node("Player")
	var view: Node3D = main.get_node("Garden")
	w.forest.today_event = "birds"
	w.forest.last_day = w.forest.today()
	w.forest.set_season("autumn")
	player.global_position = Vector3(1, 0, 1)
	main._toggle_plot()
	_check(view.get_child_count() == 0 and main.plot_line() != "", "空きの区画: 野菜はなく、足元の様子が HUD に出る")

	# 区画の上の SPACE は、木を植えずに野菜をまく
	var trees: int = w.forest.trees.size()
	g.seeds.radish = 1
	main._on_plant_tree(main.player_pos())
	_check(g.crops.size() == 1 and w.forest.trees.size() == trees, "区画の上で SPACE を押すと、木ではなく選んだ野菜をまく")
	_check(view.get_child_count() == 12, "野菜は 3 列 × 4 株で並ぶ")
	var small: Vector3 = view.get_child(0).scale
	main._water()
	_check(view.get_child_count() == 13, "水をあげると土が濡れた色になる")
	w.forest.advance_years(3.0)
	_check(view.get_child_count() == 1 + 12 + 12, "先送りプレビューで、育った姿(実)が見える")
	w.forest.reset_preview()
	_check(view.get_child_count() == 13, "プレビューをやめると今日の姿に戻る")

	var c: Dictionary = g.crop_at(main.player_pos())
	c.sown_day -= 3
	c.water_days = 4
	g.changed.emit()
	_check(view.get_child_count() == 1 + 12 + 12, "収穫できると、株ごとに実が見える")
	_check(view.get_child(1).scale.x > small.x, "育つと葉が大きくなる")
	main._harvest()
	_check(g.produce.radish == 6 and view.get_child_count() == 0, "E で収穫でき、区画は空きに戻る")

	# 市場の画面の行: 持っている野菜だけ売る行が出る
	var has_row := func(id): return main.shop_rows().any(func(r): return r.id == id)
	_check(has_row.call("sell_radish") and not has_row.call("sell_garlic"), "持っている野菜だけ、売る行が出る")
	player.global_position = Vector3(0, 0, 54)
	main._toggle_shop()
	var money: int = w.market.money
	main._on_shop_action("sell_radish")
	_check(w.market.money == money + 240 and g.produce.radish == 0, "画面から野菜を売れる")
	_check(not has_row.call("sell_radish"), "売り切ると、売る行が消える")
	main._on_shop_action("garlic_seed")
	_check(g.seeds.garlic == 1 and w.market.money == money + 240 - 250, "画面から野菜の種を買える")
	main._on_shop_action("close")

	# Z は足元の野菜を先に抜く。区画を取り消せないこと
	player.global_position = Vector3(1, 0, 1)
	g.seeds.garlic = 1
	main.selected_crop = "garlic"
	main._on_plant_tree(main.player_pos())
	_check(g.crop_at(main.player_pos()).kind == "garlic", "選んだ野菜(ニンニク)をまける")
	main._toggle_plot()
	_check(w.land.plot_at(main.player_pos()) != null, "野菜が育っている区画は F で取り消せない")
	main._remove()
	_check(g.crops.is_empty(), "Z で足元の野菜を抜ける")
	main._toggle_plot()
	_check(w.land.plot_at(main.player_pos()) == null, "空きになれば F で取り消せる")
	_check(hud.is_shop_open() == false, "市場の画面は閉じたまま")

func _test_2d_still_works() -> void:
	print("2D のシーン(比較用)")
	_check(main is Node2D, "Main2D.tscn は 2D")
	main.get_node("Player").global_position = Vector2(400, -200)
	_check(main.player_pos() == Vector2(10, -5), "2D の px を m にしてロジックに渡す(400px → 10m)")
	main.world.forest.seeds["birch"] = 1
	main._on_plant_tree(main.player_pos())
	_check(main.world.forest.trees.size() == 1 and main.world.forest.trees[0].pos == Vector2(10, -5), "2D でも植えられる")
	main.world.forest.set_season("autumn")
	main.get_node("Player").global_position = Vector2(-400, -200)
	main._toggle_plot()
	main.world.garden.seeds.radish = 1
	main._on_plant_tree(main.player_pos())
	_check(main.world.garden.crops.size() == 1, "2D でも区画に野菜をまける")
