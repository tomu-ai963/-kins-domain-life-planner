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
			_test_3d_cabin()
			_test_3d_pond()
			_test_hud()
		10:
			_test_3d_cabin_collision()  # 当たり判定が物理サーバーに入るのを待ってから
			main.queue_free()
			_remove_save()
			main = _open("res://Main2D.tscn")
		12:
			_test_2d_still_works()
			main.queue_free()
			_remove_save()
		14:
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

func _test_3d_cabin() -> void:
	print("小屋")
	var c = main.world.cabin
	var player = main.get_node("Player")
	var view: Node3D = main.get_node("Cabin")
	var pieces := func() -> int: return view.get_child(0).get_child_count() if view.get_child_count() > 0 else 0
	_check(view.get_child_count() == 0 and main.cabin_line().contains("H で足元"), "はじめは何も建っていない")
	player.global_position = Vector3(20, 0, 20)
	main._cabin_action()
	_check(c.site == Vector2(20, 20) and pieces.call() == 8, "H で足元に場所を決めると、杭 4 本と縄 4 本が立つ")
	player.global_position = Vector3(20, 0, 22.5)
	main._remove()
	_check(c.site == null and view.get_child_count() == 0, "作業を始める前なら Z で取り消せる")
	player.global_position = Vector3(20, 0, 20)
	main._cabin_action()
	player.global_position = Vector3(20, 0, 22.5)
	c.materials.log = 29

	var counts := []
	for i in range(c.total_days()):
		c.last_worked = ""
		main._cabin_action()
		counts.append(pieces.call())
	print("    作業の日ごとの部品の数: ", counts)
	_check(c.is_complete() and c.materials.log == 0, "7 日作業すると完成し、丸太 29 本を使う")
	_check(counts[0] == 2 and counts[1] == 5, "基礎: 1 日目は長い辺の土台、2 日目で四辺の土台と床")
	_check(counts[2] == 10 and counts[3] == 10, "壁 1〜2 日目: 土台の上に壁 5 枚(ドアの開口を空ける)")
	_check(counts[4] > counts[3], "壁 3 日目: ドアの上の壁とドア・窓が付く")
	_check(counts[5] > counts[4], "屋根 1 日目: 垂木が付く")
	_check(counts[6] < counts[5] and main.cabin_line().contains("完成"), "屋根 2 日目: 垂木が屋根に変わって完成")
	var walls: MeshInstance3D = view.get_child(0).get_child(5)
	_check(walls.scale.y > 2.0, "できあがりの壁は 2m を超える")
	_check(view.get_child(0).has_node("Collider"), "壁ができると当たり判定が付く")
	player.global_position = Vector3(20, 0, 20)
	main.world.forest.seeds.birch = 3
	var n: int = main.world.forest.trees.size()
	main._on_plant_tree(main.player_pos())
	_check(main.world.forest.trees.size() == n, "小屋の場所には木を植えられない")
	player.global_position = Vector3(20, 0, 23)

func _test_3d_cabin_collision() -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var from_south := Transform3D(Basis.IDENTITY, Vector3(20, 0, 23))
	_check(player.test_move(from_south, Vector3(0, 0, -3)), "南から歩いて小屋にぶつかる(通り抜けられない)")
	_check(not player.test_move(from_south, Vector3(5, 0, 0)), "小屋の外は歩ける")

func _test_3d_pond() -> void:
	print("池")
	var w = main.world
	var p = w.pond
	var player = main.get_node("Player")
	var view: Node3D = main.get_node("Pond")
	var pieces := func() -> int: return view.get_child(0).get_child_count() if view.get_child_count() > 0 else 0
	_check(view.get_child_count() == 0 and main.pond_line().contains("P で足元"), "はじめは池がない")
	player.global_position = Vector3(-20, 0, -20)
	main._pond_action()
	_check(pieces.call() == 9, "P で場所を決めると、縄の輪と杭 8 本が立つ")
	player.global_position = Vector3(-20, 0, -20)
	main._remove()
	_check(not p.is_placed() and view.get_child_count() == 0, "掘りはじめる前なら Z で取り消せる")
	main._pond_action()
	main._pond_action()
	_check(pieces.call() == 3 and main.pond_line().contains("1/5"), "掘ると岸・穴・掘った土の山が見える")
	var hole: float = (view.get_child(0).get_child(1).mesh as CylinderMesh).top_radius
	var dirt: float = view.get_child(0).get_child(2).scale.x
	p.last_dug = ""
	main._pond_action()
	_check((view.get_child(0).get_child(1).mesh as CylinderMesh).top_radius > hole, "掘るたびに穴が広がる")
	_check(view.get_child(0).get_child(2).scale.x > dirt, "掘った土の山が大きくなる")
	for i in range(3):
		p.last_dug = ""
		main._pond_action()
	_check(p.is_dug() and pieces.call() == 2, "掘り終えると、岸と空の穴だけになる(水はまだ)")
	_check(main.pond_line().contains("水 0%"), "HUD に水の量が出る")

	p.water = 25
	p.changed.emit()
	_check(pieces.call() == 4, "水がたまると水面(2 枚)が出る")
	var small: float = (view.get_child(0).get_child(2).mesh as CylinderMesh).top_radius
	p.water = 100
	p.changed.emit()
	_check((view.get_child(0).get_child(2).mesh as CylinderMesh).top_radius > small, "水が増えると水面が広がる")

	var f = w.forest
	f.set_season("summer")
	p.wet_since_day = f.day_number() - 20
	p.changed.emit()
	_check(pieces.call() == 4 + 5 + 16 + 2 + 3 + 2, "夏・20 日後: アメンボ 5・ガマ 8 本(葉と穂)・カエル 2・トンボ 3・カモ 2 が出る")
	_check(main.pond_line().contains("カモ"), "HUD にいる生き物が出る")
	var strider: Node3D = view.get_child(0).get_child(4)
	var before: Vector3 = strider.position
	view._process(1.0)
	_check(strider.position != before, "生き物はゆっくり動く")
	f.set_season("winter")
	_check(pieces.call() == 3 + 16 and main.pond_line().contains("氷"), "冬: 氷が張り、ガマだけ残る")
	f.set_season("autumn")

func _press(keycode: int) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	main._unhandled_input(e)

func _test_hud() -> void:
	print("HUD")
	var hud = main.get_node("HUD")
	var player = main.get_node("Player")
	player.global_position = Vector3(30, 0, 30)
	hud.inventory_open = false
	hud.help_open = false
	var base: int = hud.status_text().split("\n").size()
	print("    いつも出る行数: ", base)
	_check(base <= 8, "いつも出るのは 8 行まで")
	var text: String = hud.status_text()
	_check(text.contains("所持金") and text.contains("丸太") and text.contains("クエスト") and text.contains("小屋") and text.contains("池"), "所持金・丸太・クエスト・小屋・池はいつも出る")
	_check(text.contains("植える: ") and text.contains("畑にまく: "), "選んでいるものはいつも出る")
	_check(not text.contains("苗木:") and not text.contains("SPACE"), "持ち物と操作説明はふだん出さない")

	_press(KEY_TAB)
	_check(hud.status_text().contains("苗木:") and hud.status_text().contains("収穫物:"), "Tab で持ち物が出る")
	_press(KEY_TAB)
	_check(not hud.status_text().contains("苗木:"), "もう一度 Tab で閉じる")
	_press(KEY_F1)
	_check(hud.status_text().contains("SPACE") and hud.status_text().contains("H:小屋"), "F1 で操作説明が出る")
	_press(KEY_F1)
	_check(not hud.status_text().contains("SPACE"), "もう一度 F1 で閉じる")

	# 市場を開いているあいだは持ち物が出る(閉じれば戻る)
	player.global_position = Vector3(0, 0, 54)
	_check(hud.status_text().contains("市場の前"), "市場の前では、その案内が出る")
	main._toggle_shop()
	_check(hud.status_text().contains("苗木:"), "市場を開いているあいだは持ち物が出る")
	_check(not hud.status_text().contains("市場の前"), "開いているあいだは、市場の前の案内を出さない")
	main._close_shop()
	_check(not hud.status_text().contains("苗木:"), "閉じると元に戻る")

	# メッセージは下の中央に別に出て、数秒で消える
	hud.show_message("てすと", 1.0)
	_check(hud.is_message_visible() and not hud.status_text().contains("てすと"), "メッセージは左上とは別に出る")
	hud._process(0.5)
	_check(hud.is_message_visible(), "時間が来るまでは出ている")
	hud._process(0.6)
	_check(not hud.is_message_visible(), "時間が来ると消える")
	player.global_position = Vector3(20, 0, 23)  # 次の当たり判定のテストのために小屋の南へ戻す

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
	main.get_node("Player").global_position = Vector2(800, 800)
	main._cabin_action()
	_check(main.world.cabin.site == Vector2(20, 20), "2D でも小屋の場所を決められる")
	main.get_node("Player").global_position = Vector2(-800, 800)
	main._pond_action()
	main._pond_action()
	_check(main.world.pond.days_dug == 1, "2D でも池を掘れる")
