extends SceneTree

# 3D / 2D のシーンが組み上がり、ロジックの変化に view が付いてくるかのテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_views.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const TEST_SAVE := "user://test_views.json"
const DAY := 86400
const WorldMaterial = preload("res://view/3d/WorldMaterial.gd")

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
			_test_tree_shapes()
			_test_player_figure()
			_test_ground()
			_test_3d_market_and_pickups()
			_test_3d_garden()
			_test_3d_cabin()
			_test_3d_pond()
			_test_fell_confirm()
			_test_hud()
			_test_plot_limit()
			_test_toon()
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
	_check(trees.is_bare("birch") and birch_crown.material_override == trees.twig_material("birch"), "冬の白樺は葉が落ちて枝だけになる")
	_check(birch_crown.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "冬の枝にも影が落ちる")
	var ground_grass: MeshInstance3D = main.get_node("Ground").get_child(1)
	_check(ground_grass.material_override.albedo_color.b > 0.9, "冬の地面は雪原の色")

# 面の向き(表が外)と、箱に収まっているかを、形ごとに確かめる
func _mesh_faces_outward(mesh: ArrayMesh) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var face := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		if face.dot(normals[a] + normals[b] + normals[c]) > 0.0:  # Godot は時計回りが表
			return false
	return indices.size() > 0

func _test_tree_shapes() -> void:
	print("木の形")
	const Shapes = preload("res://view/3d/TreeShapes3D.gd")
	var fits := true
	var outward := true
	var anchored := true
	for species in ["birch", "apple", "cedar"]:
		for v in range(Shapes.VARIANTS):
			var c: Dictionary = Shapes.crown(species, v)
			var box: AABB = c.mesh.get_aabb()
			# かたまりの表面の波打ちの分だけ、はみ出してもよい
			fits = fits and box.position.y > -0.56 and box.end.y < 0.56 and box.position.x > -0.56 and box.end.x < 0.56 and box.position.z > -0.56 and box.end.z < 0.56
			outward = outward and _mesh_faces_outward(c.mesh) and _mesh_faces_outward(Shapes.trunk(species, v))
			if species != "cedar":
				outward = outward and _mesh_faces_outward(Shapes.bare_branches(species, v))
				anchored = anchored and c.anchors.size() >= 5
	_check(fits, "樹冠は幅・高さ 1 の箱に収まる(scale で樹冠の大きさがそのまま決まる)")
	_check(outward, "樹冠・幹・枝の面はすべて外を向いている")
	_check(anchored, "リンゴと白樺の樹冠には、実を付ける場所が 5 つ以上ある")
	_check(_mesh_faces_outward(Shapes.sprout()), "苗木の面も外を向いている")
	var a0: ArrayMesh = Shapes.crown("birch", 0).mesh
	var a1: ArrayMesh = Shapes.crown("birch", 1).mesh
	var a0_again: ArrayMesh = Shapes.crown("birch", 0).mesh
	_check(a0.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != a1.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "種類が違えば形も違う")
	_check(a0.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == a0_again.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "同じ種類は毎回同じ形")

	# 実は樹冠の表面にある(樹冠の外や中に浮かない)
	var f = main.world.forest
	var trees: Node3D = main.get_node("Trees")
	f.seeds["apple"] = 1
	f.add_tree(Vector2(-30, 5), "apple")
	f.trees[-1].planted_at = int(Time.get_unix_time_from_system()) - 6 * DAY
	f.set_season("summer")
	f.set_season("autumn")
	var n := trees.get_child_count()
	var crown: MeshInstance3D = trees.get_child(n - 6)
	var near := true
	for i in range(5):
		var local := crown.basis.inverse() * ((trees.get_child(n - 5 + i) as Node3D).position - crown.position)
		near = near and local.length() > 0.2 and local.length() < 0.6
	_check(near, "リンゴの実は葉のかたまりの表面に付く")
	f.remove_nearest(Vector2(-30, 5), 2.0)

func _test_player_figure() -> void:
	print("プレイヤーの体")
	var player = main.get_node("Player")
	var figure: Node3D = player.get_node("Body/Figure")
	_check(figure.get_node("Hips/Upper/Head/Face") != null and figure.get_node("Hips/LegL") != null \
			and figure.get_node("Hips/Upper/ArmRSpread/ArmR/Hand") != null, "顔と手足がある")
	var eye: Node3D = figure.get_node("Hips/Upper/Head/Eye")
	_check(eye.position.z < 0.0, "目は体の正面(-z)にある")
	figure.moving = false
	figure._process(1.0)
	_check(is_zero_approx(figure.swing_amount()), "立っているとき足は振れない")
	figure.moving = true
	var biggest := 0.0
	for i in range(30):
		figure._process(0.03)
		biggest = maxf(biggest, figure.swing_amount())
	_check(biggest > 0.5, "歩くと足を振る")
	figure.moving = false
	for i in range(60):
		figure._process(0.03)
	_check(figure.swing_amount() < 0.01, "止まると足がそろう")
	var lantern: Node3D = player._lantern
	_check(lantern.get_parent() == figure.right_hand, "ランタンは右手に持っている")
	player.set_night(1.0)
	_check(lantern.visible and figure.holding_lantern, "夜はランタンを手に持ってともす")
	player.set_night(0.0)
	_check(not lantern.visible and not figure.holding_lantern, "昼はしまう")
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	player._process(0.016)
	_check(not figure.moving, "市場を開いて止まっている間は歩かない")
	player.set_physics_process(true)

func _test_ground() -> void:
	print("地面の作り込み")
	var ground: Node3D = main.get_node("Ground")
	var player = main.get_node("Player")
	var f = main.world.forest
	var w = main.world

	# 曲がる世界: 中心は下がらず、遠いほど下がる。奥行きのほうが強く曲がる
	_check(WorldMaterial.drop(0, 0) == 0.0, "カメラが見ている場所は下がらない")
	_check(WorldMaterial.drop(0, 40) > WorldMaterial.drop(0, 20) and WorldMaterial.drop(0, 20) > 0.0, "遠いほど下がる")
	_check(WorldMaterial.drop(0, 30) > WorldMaterial.drop(30, 0), "東西より奥行きのほうが強く曲がる")
	_check(WorldMaterial.drop(3, 3) < 0.05, "足元の近くはほとんど曲がらない(小屋や畑の形が崩れない)")
	var opaque := WorldMaterial.new(Color.RED)
	var clear := WorldMaterial.new(Color(1, 0, 0, 0.5))
	_check(opaque.shader != clear.shader and clear.shader.code.contains("ALPHA") and not opaque.shader.code.contains("ALPHA"), "半透明の色だけ半透明のシェーダーになる")
	_check(WorldMaterial.new(Color.BLUE).shader == opaque.shader, "同じ種類の材質はシェーダーを使い回す")
	opaque.albedo_color = Color(1, 0, 0, 0.5)
	_check(opaque.shader == clear.shader, "あとから半透明にしても切り替わる")
	var unlit := WorldMaterial.new(Color.RED, true)
	_check(unlit.shader.code.contains("unshaded") and not unlit.shader.code.contains("diffuse_toon"), "光を受けない材質はトゥーンにしない")

	# 長い帯は頂点があるので曲がる
	var strip := main.get_node("Ground").get_child(2) as MeshInstance3D
	_check((strip.mesh as PlaneMesh).subdivide_width >= 40, "グリッドの長い帯は細かく分かれている(曲がれる)")

	# 起伏は土地の外だけ
	var flat := true
	for p in [Vector2(0, 0), Vector2(49, 49), Vector2(0, 54), Vector2(78, 78), Vector2(-78, 0)]:
		flat = flat and is_equal_approx(ground.height_at(p.x, p.y), -0.02)
	_check(flat, "土地・市場・歩ける範囲は平ら")
	_check(ground.height_at(200, 0) > 5.0 and ground.height_at(0, -200) > 5.0, "外には丘がある")
	_check(ground.height_at(170, 30) != ground.height_at(170, 110), "丘の高さは場所で変わる(起伏がある)")
	_check(player.WALK_LIMIT < ground.HILL_START, "歩ける範囲は丘の手前まで")
	_check(ground.get_child(0).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "丘は土地に影を落とさない")

	# 歩ける範囲の外へは出られない
	player.global_position = Vector3(500, 0, -500)
	player._physics_process(0.016)
	_check(player.global_position.x == player.WALK_LIMIT and player.global_position.z == -player.WALK_LIMIT, "歩いて丘へは入れない")
	player.global_position = Vector3.ZERO

	# 草の株と花
	f.set_season("summer")
	_check(ground._tufts.visible and ground._flowers.visible, "夏は草の株と花がある")
	_check(ground._tufts.multimesh.instance_count == ground.TUFT_COUNT, "草の株が土地に散らばっている")
	f.set_season("autumn")
	_check(ground._tufts.visible and not ground._flowers.visible, "秋は花が終わる")
	f.set_season("winter")
	_check(not ground._tufts.visible and not ground._flowers.visible, "冬は雪の下")
	f.set_season("summer")

	# 区画・池・小屋の上には生えない
	var first: Transform3D = ground._tufts.get_meta("base")[0]
	var pos := Vector2(first.origin.x, first.origin.z)
	var plots_before: Array = w.land.plots.duplicate()
	w.land.plots = []
	w.land.changed.emit()
	var before: int = ground.hidden_count()
	_check(ground._tufts.get_meta("hidden")[0] == 0, "はじめは株が見えている")
	w.land.plots.append(w.land.plot_center(pos))
	w.land.changed.emit()
	_check(ground._tufts.get_meta("hidden")[0] == 1 and ground.hidden_count() > before, "区画を置くと、その上の株が隠れる")
	w.land.plots = []
	w.land.changed.emit()
	_check(ground._tufts.get_meta("hidden")[0] == 0 and ground.hidden_count() == before, "区画を取り消すと、また生える")
	w.land.pond = pos
	w.land.changed.emit()
	_check(ground._tufts.get_meta("hidden")[0] == 1, "池の上にも生えない")
	w.land.pond = null
	var c = w.cabin
	var site_before = c.site
	c.site = pos
	c.changed.emit()
	_check(ground._tufts.get_meta("hidden")[0] == 1, "小屋の下にも生えない")
	c.site = site_before
	w.land.plots = plots_before
	c.changed.emit()
	w.land.changed.emit()

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
	_check(main.plot_line().contains("あと3日で傷む"), "HUD に傷むまでの日数が出る")
	var fruit_before: Color = view.get_child(2).material_override.albedo_color
	c.sown_day -= 8
	g.changed.emit()
	_check(main.plot_line().contains("傷みはじめた"), "傷むと HUD が変わる")
	_check(view.get_child(2).material_override.albedo_color != fruit_before, "傷むと実の色が変わる")
	main._harvest()
	_check(g.produce.radish == 3 and main.get_node("HUD")._message.contains("半分"), "傷んだ野菜は半分だけ採れて、そう知らせる")
	g.produce.radish = 0
	g.seeds.radish = 1
	main._on_plant_tree(main.player_pos())
	main._water()
	c = g.crop_at(main.player_pos())
	c.sown_day -= 3
	c.water_days = 4
	g.changed.emit()
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
	_check(main.cabin_line().contains("苗づくり"), "完成すると苗づくりの案内が出る")

	# 苗づくりと、窓辺の鉢の見た目
	var sl = main.world.seedlings
	var g = main.world.garden
	var done: int = pieces.call()
	main.selected_crop = "tomato"
	g.seeds.tomato = 1
	main._cabin_action()
	_check(sl.pots.size() == 1 and pieces.call() == done + 3, "H で鉢にまくと、棚と鉢と芽が見える")
	_check(main.cabin_line().contains("あと5日") and main.cabin_line().contains("世話は済んだ"), "HUD に残りの日数が出る")
	sl.pots[0].sown_day -= 5
	sl.pots[0].water_days = 6
	sl.changed.emit()
	_check(main.cabin_line().contains("H で受け取る"), "育つと受け取る案内が出る")
	main._cabin_action()
	_check(sl.ready.tomato == 1 and pieces.call() == done, "H で受け取ると、鉢が片づく")
	main.selected_crop = "radish"

	# 苗を売る行と、畑に植える
	_check(main.shop_rows().any(func(r): return r.id == "sell_seedling_tomato" and r.text.contains("トマトの苗 1鉢")), "育った苗は市場で売れる")
	main.world.forest.set_season("spring")
	player.global_position = Vector3(30, 0, -30)
	main._toggle_plot()
	main.selected_crop = "tomato"
	main._on_plant_tree(main.player_pos())
	_check(sl.ready.tomato == 0 and g.crop_at(main.player_pos()).kind == "tomato", "苗があれば、SPACE で苗を植える")
	_check(g.days_left(g.crop_at(main.player_pos())) == 5, "苗から植えると 2 日早い")
	main._on_plant_tree(main.player_pos())
	g.remove_at(main.player_pos())
	main._on_plant_tree(main.player_pos())
	_check(g.crops.is_empty() and main.get_node("HUD")._message.contains("苗から育てる"), "苗がないとトマトはまけない")
	main._toggle_plot()
	main.selected_crop = "radish"

	# 冬の地面
	main.world.forest.set_season("winter")
	var f = main.world.forest
	f.saplings.birch = 1
	f.seeds.apple = 1
	var trees_before: int = f.trees.size()
	main.selected_form = "sapling"
	main.selected_species = "birch"
	main._on_plant_tree(Vector2(40, -40))
	_check(f.trees.size() == trees_before and main.get_node("HUD")._message.contains("凍って"), "冬は苗木を植えられない")
	main.selected_form = "seed"
	main.selected_species = "apple"
	main._on_plant_tree(Vector2(40, -40))
	_check(f.trees.size() == trees_before and f.seeds.apple == 1, "冬はリンゴの種をまけない")
	f.seeds.birch = 1
	main.selected_species = "birch"
	main._on_plant_tree(Vector2(40, -40))
	_check(f.trees.size() == trees_before + 1, "冬でも白樺の種はまける")
	f.remove_nearest(Vector2(40, -40), 2.0)
	f.set_season("autumn")
	player.global_position = Vector3(20, 0, 20)
	main.world.forest.seeds.birch = 3
	var n: int = main.world.forest.trees.size()
	main._on_plant_tree(main.player_pos())
	_check(main.world.forest.trees.size() == n, "小屋の場所には木を植えられない")
	player.global_position = Vector3(20, 0, 23)

func _test_3d_cabin_collision() -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var at_wall := Transform3D(Basis.IDENTITY, Vector3(21.2, 0, 23))
	var at_door := Transform3D(Basis.IDENTITY, Vector3(20, 0, 23))
	var indoors := Transform3D(Basis.IDENTITY, Vector3(20, 0, 20))
	_check(player.test_move(at_wall, Vector3(0, 0, -3)), "南の壁には歩いてぶつかる(通り抜けられない)")
	_check(not player.test_move(at_door, Vector3(5, 0, 0)), "小屋の外は歩ける")
	_check(not player.test_move(at_door, Vector3(0, 0, -2.5)), "南のドアからは中へ入れる")
	_check(not player.test_move(indoors, Vector3(0, 0, 3)), "中からドアを通って外へ出られる")
	_check(player.test_move(indoors, Vector3(3, 0, 0)) and player.test_move(indoors, Vector3(-3, 0, 0)), "中からは東西の壁にぶつかる")
	_check(player.test_move(indoors, Vector3(0, 0, -3)), "中からは北の壁にぶつかる")
	_check(player.test_move(Transform3D(Basis.IDENTITY, Vector3(19.1, 0, 20)), Vector3(0, 0, -1)), "ベッドにぶつかる(上に乗れない)")
	_check(player.test_move(Transform3D(Basis.IDENTITY, Vector3(21.45, 0, 20)), Vector3(0, 0, -1)), "ストーブにぶつかる")
	_check(player.test_move(Transform3D(Basis.IDENTITY, Vector3(18.8, 0, 19.9)), Vector3(0, 0, 1)), "テーブルにぶつかる")
	_check(not player.test_move(Transform3D(Basis.IDENTITY, Vector3(21.45, 0, 19.75)), Vector3(0, 0, 0.5)), "ストーブの南は空いている")
	_test_cabin_inside()
	_test_furniture()

func _test_cabin_inside() -> void:
	print("小屋の中")
	var player: CharacterBody3D = main.get_node("Player")
	var view: Node3D = main.get_node("Cabin")
	var c = main.world.cabin
	var spot: Node3D = view.get_child(0)
	var room: Node3D = spot.get_node("Interior")
	var roof: MeshInstance3D = view._cut_pieces.filter(func(n): return n.mesh is PrismMesh)[0]
	var sl = main.world.seedlings
	var shows := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var hides := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_check(room.get_child_count() >= 15, "部屋にベッド・ストーブ・テーブルなどがある(%d 個)" % room.get_child_count())

	# 外: 屋根が見え、部屋の明かりは消えている
	player.global_position = Vector3(20, 0, 30)
	view._process(0.1)
	_check(roof.cast_shadow == shows and view._inside_pieces.all(func(n): return not n.visible), "外にいると屋根が見え、部屋の明かりは消えている")
	view._process(10.0)
	_check(view._door_hinge.rotation.y == 0.0, "離れているとドアは閉まっている")

	# ドアの前に来ると開く
	player.global_position = Vector3(20, 0, 22.5)
	view._process(10.0)
	_check(is_equal_approx(view._door_hinge.rotation.y, view.DOOR_OPEN_ANGLE), "近づくとドアが開く")
	_check(not c.is_inside(player.ground_pos()) and roof.cast_shadow == shows, "ドアの前はまだ外")

	# 中に入る: 屋根と南の壁を見せず、カメラが寄る
	var far_dist: float = player.view_distance()
	player.global_position = Vector3(20, 0, 20)
	view._process(0.1)
	_check(c.is_inside(player.ground_pos()), "ドアを入ると中にいる")
	_check(view._cut_pieces.size() >= 6 and view._cut_pieces.all(func(n): return n.cast_shadow == hides), "中では屋根と南の壁を見せない(影だけ落とす)")
	_check(view._inside_pieces.all(func(n): return n.visible), "中では部屋の明かりと腰の高さの壁を見せる")
	_check(player.view_distance() == player.INDOOR_CAM_DIST and player.view_distance() < far_dist, "中ではカメラが寄る")
	player._process(10.0)
	_check(is_equal_approx(player.get_node("Body").position.y, view.FLOOR_Y), "体が床の高さに上がる")

	# 中でのズームは外の距離を変えない
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	player._unhandled_input(wheel)
	_check(player.view_distance() > player.INDOOR_CAM_DIST and player._cam_dist == far_dist, "中のズームは外の距離を変えない")

	# 中で苗づくりができる。見た目を作り直しても中のまま
	main.selected_crop = "cucumber"
	main.world.garden.seeds.cucumber = 1
	var pots: int = sl.pots.size()
	main._cabin_action()
	_check(sl.pots.size() == pots + 1, "中からも H で苗づくりができる")
	var roof2: MeshInstance3D = view._cut_pieces.filter(func(n): return n.mesh is PrismMesh)[0]
	_check(roof2.cast_shadow == hides and view._inside_pieces.all(func(n): return n.visible), "作り直しても中の見え方のまま")
	sl.pots.clear()
	sl.changed.emit()
	main.selected_crop = "radish"

	# 夜の明かりと一緒に動いても大丈夫
	view.set_night(1.0)
	_check(view._lamp_light.visible, "中にいても夜の軒の明かりはつく")
	view.set_night(0.0)

	# 外へ出ると戻る
	player.global_position = Vector3(20, 0, 23)
	view._process(0.1)
	_check(view._cut_pieces.all(func(n): return n.cast_shadow == shows), "外へ出ると屋根と南の壁が戻る")
	_check(view._inside_pieces.all(func(n): return not n.visible), "外へ出ると部屋の明かりが消える")
	_check(player.view_distance() == far_dist, "外へ出るとカメラが元の距離に戻る")
	player._process(10.0)
	_check(player.get_node("Body").position.y == 0.0, "体が地面の高さに戻る")

# 名前が name で始まる、部屋の中の形
func _room_pieces(view: Node3D, prefix: String) -> Array:
	var room: Node3D = view.get_child(0).get_node("Interior")
	return room.get_children().filter(func(n): return str(n.name).contains(prefix))

func _test_furniture() -> void:
	print("ストーブとベッド")
	var w = main.world
	var k = w.kitchen
	var view: Node3D = main.get_node("Cabin")
	var player: CharacterBody3D = main.get_node("Player")
	var hud = main.get_node("HUD")
	var c = w.cabin
	var site: Vector2 = c.site
	var key := func(code: int) -> void:
		var e := InputEventKey.new()
		e.keycode = code
		e.pressed = true
		main._unhandled_input(e)

	# ストーブの前: H で台所が開く(苗づくりにはならない)
	player.global_position = Vector3(site.x + c.STOVE_OFFSET.x - 0.65, 0, site.y + c.STOVE_OFFSET.y)
	_check(main.furniture_line().contains("ストーブ"), "ストーブの前で案内が出る")
	_check(main.kitchen_line() == "", "はじめは鍋の行が出ない")
	_check(_room_pieces(view, "CookPot").size() == 1 and _room_pieces(view, "PotInside").size() == 1 and _room_pieces(view, "PotLid").is_empty(), "空でも鍋はストーブの上に見える(蓋なし)")
	_check(view._steam_puffs.is_empty(), "空の鍋から湯気は出ない")
	var fire: MeshInstance3D = _room_pieces(view, "StoveFire")[0]
	_check(not fire.material_override.emission_enabled, "はじめは火が消えている")
	var logs_before: int = int(c.materials.log)
	c.materials.log = 2
	w.garden.produce.tomato = 10
	key.call(KEY_H)
	_check(hud.is_shop_open() and main._panel == "kitchen" and not player.is_physics_processing(), "H で台所が開き、歩かなくなる")
	_check(main.shop_title().contains("ストーブ") and main.shop_header().contains("薪"), "見出しが台所になる")
	_check(main.kitchen_rows().any(func(r): return r.id == "cook_sauce" and r.text.contains("トマト 10kg") and r.text.contains("5瓶")), "料理の一覧に材料とできる数が出る")

	# 仕込む: 鍋と火と薪が見える
	main._on_shop_action("cook_sauce")
	_check(not k.is_empty() and k.pot.recipe == "sauce" and w.garden.produce.tomato == 0, "画面から仕込める")
	_check(hud._message.contains("トマトソース") and hud._message.contains("割って"), "仕込んだ文言が出る")
	_check(_room_pieces(view, "CookPot").size() == 1 and _room_pieces(view, "PotLid").size() == 1 and _room_pieces(view, "PotInside").is_empty(), "仕込むと鍋に蓋がのる")
	_check(view._steam_puffs.size() == view.STEAM_PUFFS, "仕込んでいるあいだは湯気が出る")
	var puff: MeshInstance3D = view._steam_puffs[0]
	var puff_y: float = puff.position.y
	view._animate_steam(view.STEAM_SECONDS * 0.2)
	_check(puff.position.y != puff_y and puff.scale.x > 0.0, "湯気が動く")
	var pot_piece: MeshInstance3D = _room_pieces(view, "CookPot")[0]
	var stove_x: float = c.STOVE_OFFSET.x
	_check(is_equal_approx(pot_piece.position.x, stove_x) and pot_piece.position.y > view.STOVE_H, "鍋はストーブの上にある")
	var fire2: MeshInstance3D = _room_pieces(view, "StoveFire")[0]
	_check(fire2.material_override.emission_enabled, "火が見える")
	_check(_room_pieces(view, "Firewood").size() == view.WOOD_PILES_MAX, "割った薪が積まれる")
	_check(main.kitchen_line().contains("あと1日"), "HUD に鍋の残り日数が出る")
	_check(main.kitchen_rows().any(func(r): return r.id == "pot_wait" and r.text.contains("あと1日")), "台所にも残り日数が出る")
	main._on_shop_action("cook_sauce")
	_check(hud._message.contains("鍋は使っている"), "鍋がふさがっていると仕込めない")
	key.call(KEY_H)
	_check(not hud.is_shop_open() and player.is_physics_processing(), "もう一度 H で閉じる")

	# 次の日: 受け取るとテーブルに並び、市場で売れる
	k.pot.start_day -= 1
	k.changed.emit()
	_check(main.kitchen_line().contains("できた"), "できると HUD で知らせる")
	_check(_room_pieces(view, "PotFood").size() == 1 and _room_pieces(view, "PotLid").is_empty() and view._steam_puffs.is_empty(), "できると蓋が取れて中身が見え、湯気は止まる")
	_check(not _room_pieces(view, "StoveFire")[0].material_override.emission_enabled, "できると火は落ちている")
	main._open_kitchen()
	_check(main.kitchen_rows().any(func(r): return r.id == "pot_collect" and r.text.contains("5瓶")), "受け取りの行が出る")
	main._on_shop_action("pot_collect")
	_check(k.stock.sauce == 5 and k.is_empty() and _room_pieces(view, "PotInside").size() == 1 and _room_pieces(view, "PotFood").is_empty(), "受け取ると鍋が空く")
	_check(_room_pieces(view, "Food").size() == 5, "できた瓶がテーブルに並ぶ")
	_check(not _room_pieces(view, "StoveFire")[0].material_override.emission_enabled, "火が消える")
	main._on_shop_action("close")
	_check(main.food_line().contains("トマトソース 5瓶") and not main.produce_line().contains("トマトソース"), "持ち物の保存食の行に出る")
	main._open_kitchen()
	_check(not hud.status_text().contains("─ 持ち物 ─"), "ストーブの画面には持ち物を重ねない")
	main._close_shop()
	main._panel = "market"
	hud.open_shop()
	_check(hud.status_text().contains("保存食: トマトソース 5瓶"), "市場の画面では持ち物に保存食が出る")
	main._close_shop()
	main._panel = "market"
	_check(main.shop_rows().any(func(r): return r.id == "sell_sauce" and r.text.contains("トマトソース 5瓶 × 150₽")), "市場に売る行が出る")
	var money: int = w.market.money
	main._on_shop_action("sell_sauce")
	_check(w.market.money == money + 750 and _room_pieces(view, "Food").is_empty(), "売るとお金が増え、テーブルから消える")
	k.stock.pickles = 100
	k.changed.emit()
	_check(_room_pieces(view, "Food").size() == view.JARS_SHOWN, "たくさんあっても机に収まる数だけ並べる")
	k.stock.pickles = 0
	k.firewood = 0
	c.materials.log = logs_before
	k.changed.emit()

	# ベッド: 暗くなって日記が出る。時間は進まない
	player.global_position = Vector3(site.x + c.BED_OFFSET.x, 0, site.y + c.BED_OFFSET.y + 0.73)
	view._process(0.1)  # 小屋の中にいることを view が知る
	_check(main.furniture_line().contains("ベッド"), "ベッドのそばで案内が出る")
	var day_before: String = w.forest.today()
	key.call(KEY_H)
	_check(hud.is_diary_open() and not player.is_physics_processing(), "H で休むと日記が出て、歩かなくなる")
	var stand_pos: Vector2 = player.ground_pos()
	var body: Node3D = player.get_node("Body")
	_check(player.is_lying() and body.position.length() < 0.5, "横になる動きが始まる(まだ立っている近く)")
	_check(hud._diary.modulate.a == 0.0, "横になるあいだは、まだ暗くならない")
	player._pose.custom_step(10.0)
	hud._diary_fade.custom_step(10.0)
	_check(is_equal_approx(hud._diary.modulate.a, 1.0), "横になったあと暗くなる")
	var head: Node3D = player.get_node("Body/Figure/Hips/Upper/Head")
	var pillow_x: float = site.x + c.BED_OFFSET.x - 0.65
	var head_p: Vector3 = head.global_position
	_check(absf(head_p.x - pillow_x) < 0.15 and absf(head_p.z - (site.y + c.BED_OFFSET.y)) < 0.1, "頭が枕の上にある(%.2f, %.2f)" % [head_p.x, head_p.z])
	_check(head_p.y > view.FLOOR_Y + 0.39, "頭は敷布団より上(高さ %.2f)" % head_p.y)
	var face_dir: Vector3 = -body.global_basis.z
	_check(face_dir.dot(Vector3.UP) > 0.99, "顔が上を向いている")
	var foot_x: float = view.lying_spot().x
	_check(foot_x < site.x + c.BED_OFFSET.x + c.BED_SIZE.x * 0.5, "足はベッドからはみ出ない")
	_check(player.ground_pos() == stand_pos, "足元の位置(当たり判定)は動かない")
	view._cover_tween.custom_step(10.0)
	var cover: MeshInstance3D = _room_pieces(view, "SleepCover")[0]
	_check(cover.visible and cover.scale.is_equal_approx(view.COVER_SCALE), "掛け布団がかかる")
	k.changed.emit()  # 寝ているあいだに作り直しても
	_check(_room_pieces(view, "SleepCover")[0].visible, "作り直しても布団はかかったまま")
	var text: String = hud._diary_label.text
	_check(text.contains("の日記") and text.contains("今日") and text.contains("明日"), "日記に今日と明日がある")
	_check(w.forest.today() == day_before, "寝ても日付は変わらない")
	main._on_plant_tree(main.player_pos())
	key.call(KEY_Q)
	_check(hud.is_diary_open(), "日記を開いているあいだ、ほかのキーは効かない")
	key.call(KEY_H)
	_check(not hud.is_diary_open() and player.is_physics_processing(), "H で起きる")
	_check(not player.is_lying(), "起き上がる動きが始まる")
	player._pose.custom_step(10.0)
	view._cover_tween.custom_step(10.0)
	_check(body.position.is_equal_approx(Vector3(0, view.FLOOR_Y, 0)) and absf((-body.global_basis.z).dot(Vector3.UP)) < 0.01, "立った姿勢に戻る")
	_check(not _room_pieces(view, "SleepCover")[0].visible, "掛け布団が片づく")
	key.call(KEY_H)
	key.call(KEY_ESCAPE)  # 横になっている途中で起きても
	_check(not hud.is_diary_open(), "Esc でも起きる")
	player._pose.custom_step(10.0)
	view._cover_tween.custom_step(10.0)
	_check(body.position.is_equal_approx(Vector3(0, view.FLOOR_Y, 0)), "途中で起きても立った姿勢に戻る")
	player.set_night(1.0)
	key.call(KEY_H)
	_check(not player.get_node("Body/Figure").holding_lantern, "夜に横になるとランタンを持たない")
	key.call(KEY_H)
	player._pose.custom_step(10.0)
	view._cover_tween.custom_step(10.0)
	_check(player.get_node("Body/Figure").holding_lantern, "起きるとランタンを持つ")
	player.set_night(0.0)

	# 日記の中身は今の状態に合わせて変わる
	var g = w.garden
	g.crops.clear()
	g.crops.append({"pos": Vector2(40, 40), "kind": "radish", "sown_day": g.day_number() - 5, "water_days": 0, "last_watered": "", "head": 0.0})
	var d: String = main.diary_text()
	_check(d.contains("収穫できる区画: 1") and d.contains("まだ水をやっていない区画が 1"), "明日収穫できる区画とやり残しが出る")
	_check(d.contains("鍋が空いている"), "鍋が空いていると出る")
	g.crops.clear()
	k.pot = {"recipe": "jam", "start_day": k.forest.day_number()}
	_check(main.diary_text().contains("鍋のリンゴジャムを受け取れる"), "明日できる鍋が出る")
	k.pot = {"recipe": "pickles", "start_day": k.forest.day_number()}
	var d2: String = main.diary_text()
	_check(not d2.contains("鍋の") and not d2.contains("鍋が"), "まだできない鍋は出さない")
	k.pot = {}
	k.changed.emit()
	player.global_position = Vector3(20, 0, 23)
	view._process(0.1)

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
	# 池のそばの Q: まとめて水やり。足元に何もなければ、運べない理由を出す
	var hud = main.get_node("HUD")
	f.today_event = "birds"
	f.last_day = f.today()
	f.saplings.birch = 1
	f.add_tree(Vector2(-20, -12), "birch", "sapling")
	_check(main.pond_beside_line().contains("木 1"), "池のそばに、まとめて水やりの案内が出る")
	var water_before: int = p.water
	main._water()
	_check(f.watered_today(f.trees[-1]) and p.water == water_before - 5 and hud._message.contains("木 1"), "Q でまとめて水やりでき、池の水が減る")
	_check(main.pond_beside_line() == "", "水のいるものがなくなると、案内は消える")
	main._water()
	_check(hud._message.contains("水のいる木や区画がない") and p.water == water_before - 5, "もう何もなければ、その理由を出す(水は減らない)")
	f.trees.remove_at(f.trees.size() - 1)
	p.water = 100
	f.changed.emit()
	var strider: Node3D = view.get_child(0).get_child(4)
	var before: Vector3 = strider.position
	view._process(1.0)
	_check(strider.position != before, "生き物はゆっくり動く")
	f.set_season("winter")
	_check(pieces.call() == 3 + 16 and main.pond_line().contains("氷"), "冬: 氷が張り、ガマだけ残る")
	f.set_season("autumn")

func _test_fell_confirm() -> void:
	print("木を伐る前の確認")
	var w = main.world
	_check(w.backup_dir == "", "テストのセーブでは控えを取らない(Main は本物のセーブのときだけ設定する)")
	var f = w.forest
	var hud = main.get_node("HUD")
	var player = main.get_node("Player")
	var cabin = w.cabin
	f.saplings.birch = 2
	f.add_tree(Vector2(35, 35), "birch", "sapling")
	f.trees[-1].start_age = 20.0
	f.add_tree(Vector2(36, 35), "birch", "sapling")
	var old_tree: Dictionary = f.trees[-2]
	player.global_position = Vector3(34.9, 0, 35)
	var n: int = f.trees.size()
	var logs: int = cabin.materials.log
	main._remove()
	_check(f.trees.size() == n and hud._message.contains("もう一度 Z") and hud._message.contains("樹齢20年") and hud._message.contains("丸太2本"), "1 回目は伐らず、樹齢と採れる丸太を知らせる")
	main._fell_deadline = 0.0
	main._remove()
	_check(f.trees.size() == n and hud._message.contains("もう一度 Z"), "時間が過ぎていれば、もう一度確認する")
	# 確認中に別の木の近くへ移ると、その木は伐らずに確認し直す
	player.global_position = Vector3(36.1, 0, 35)
	main._remove()
	_check(f.trees.size() == n and hud._message.contains("細くて"), "別の木に移ると、そちらの確認になる")
	player.global_position = Vector3(34.9, 0, 35)
	main._remove()
	_check(f.trees.size() == n, "元の木に戻っても、いきなり伐らない")
	main._remove()
	_check(f.trees.size() == n - 1 and not f.trees.has(old_tree) and cabin.materials.log == logs + 2, "時間内にもう一度押すと伐れて、丸太が増える")
	# 芽が出ていない種は確認なしで抜ける
	f.remove_nearest(Vector2(36, 35), 2.0)
	f.germination_rates.birch = 0.0
	f.seeds.birch = 1
	f.add_tree(Vector2(35, 35), "birch")
	n = f.trees.size()
	main._remove()
	_check(f.trees.size() == n - 1, "まいたばかりの種は 1 回で抜ける")

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

func _test_plot_limit() -> void:
	print("耕す上限")
	var w = main.world
	var hud = main.get_node("HUD")
	var player = main.get_node("Player")
	var keep: Vector3 = player.global_position
	w.garden.tilled_day = ""
	w.garden.tilled_count = 0
	var spots := [Vector3(-40, 0, 40), Vector3(-37, 0, 40), Vector3(-34, 0, 40)]
	var plots: int = w.land.plots.size()
	for s in spots:
		player.global_position = s
		main._toggle_plot()
	_check(w.land.plots.size() == plots + 2, "F で耕せるのは 1 日 2 区画まで")
	_check(hud._message.contains("1日2区画まで") and hud._message.contains("明日"), "上限になると、その理由を出す")
	_check(main.QUEST_TEXTS.garden.hint.contains("1日2区画"), "クエストの案内にも上限が書いてある")
	for i in range(2):
		player.global_position = spots[i]
		main._toggle_plot()
	_check(w.land.plots.size() == plots, "取り消すと元に戻る")
	player.global_position = keep

# シーンの中の形を全部たどって、材質を集める
func _collect_materials(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		if mi.material_override != null:
			out.append(mi.material_override)
		for i in range(mi.get_surface_override_material_count()):
			if mi.get_surface_override_material(i) != null:
				out.append(mi.get_surface_override_material(i))
	for c in n.get_children():
		_collect_materials(c, out)

func _test_toon() -> void:
	print("トゥーン")
	var mats := []
	_collect_materials(main, mats)
	var bad := 0
	var toon := 0
	var bending := 0
	for m in mats:
		# 共通の材質(世界といっしょに曲がる)は、光を受けるならトゥーンで作ってある
		if m is WorldMaterial:
			bending += 1
			if not m.unshaded:
				toon += 1
				bad += 0 if m.shader.code.contains("diffuse_toon") else 1
			continue
		var s := m as StandardMaterial3D
		if s == null or s.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			continue
		if s.diffuse_mode == BaseMaterial3D.DIFFUSE_TOON and s.specular_mode == BaseMaterial3D.SPECULAR_DISABLED:
			toon += 1
		else:
			bad += 1
	print("    トゥーンの材質 %d 個 / それ以外 %d 個 / 世界といっしょに曲がる材質 %d 個" % [toon, bad, bending])
	_check(bending > 20, "地面・木・小屋などの材質は世界といっしょに曲がる")
	_check(toon > 20 and bad == 0, "光を受ける材質は全部トゥーン(地面・木・小屋・プレイヤーなど)")
	var outline: MeshInstance3D = main.get_node("Player/Camera3D/Outline")
	var outline_mat := outline.get_surface_override_material(0) as ShaderMaterial
	_check(outline.visible and outline_mat != null and outline_mat.shader != null, "カメラの前に輪郭線の板がある")
	_check(outline.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "輪郭線の板は影を落とさない")

	var player = main.get_node("Player")
	var sun: DirectionalLight3D = main.get_node("Sun")
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	for i in range(30):
		player._unhandled_input(wheel)
	_check(sun.directional_shadow_max_distance == player.SHADOW_DIST_MAX, "カメラを引くと影を遠くまで描く")
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	for i in range(30):
		player._unhandled_input(wheel)
	_check(sun.directional_shadow_max_distance == player.SHADOW_DIST_MIN, "寄ると影の範囲を狭めてくっきりさせる")
	player._cam_dist = 28.0
	player.update_shadow_distance()

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
