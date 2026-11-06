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
var _wait_until := 0  # この時刻(ms)まで次へ進まない(当たり判定が物理サーバーに入るのを待つ)
var main  # いま試しているシーン(Main.gd)

func _initialize() -> void:
	_remove_save()
	main = _open("res://Main.tscn")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() < _wait_until:
		return false
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
			_prepare_visitor_collision()
			_wait_until = Time.get_ticks_msec() + 200
		11:
			_test_visitor_collision()
			_test_hive_collision()
			_test_tree_collision()
			_wait_until = Time.get_ticks_msec() + 200
		12:
			_test_visitor_collision_off()
			_test_tree_collision_gone()
			main.queue_free()
			_remove_save()
			main = _open("res://Main2D.tscn")
		14:
			_test_2d_still_works()
			main.queue_free()
			_remove_save()
		16:
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
	_test_work_motions()
	_test_wildlife_view()
	_test_visitor_view()
	_test_hint_panel()
	_test_hive_view()
	_test_fruit_view()
	_test_sound_view()

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

# 訪問者を開けた場所で待たせる(当たり判定が物理サーバーに入るのを、次の段階まで待つ)
func _prepare_visitor_collision() -> void:
	var w = main.world
	var view: Node3D = main.get_node("Visitor")
	var player: CharacterBody3D = main.get_node("Player")
	w.forest.trees.clear()
	player.global_position = Vector3(-30, 0, -35)
	w.visitors.visit = {"day": w.forest.day_number(), "who": "nina", "kind": "chat", "done": false, "line": 0}
	view.sync_visit()
	_check(view._solid_shape.disabled, "歩いているあいだは当たり判定がない(プレイヤーを押さない)")
	for _i in range(600):
		if view.state() == "wait":
			break
		view.step(0.1)
	_check(view.state() == "wait" and not view._solid_shape.disabled, "待っているあいだは当たり判定がある")
	_prepare_tree_collision()

# 離れた場所に、育った木・幹のない苗木・種を置く(当たり判定が物理サーバーに入るのを、次の段階まで待つ)
func _prepare_tree_collision() -> void:
	var f = main.world.forest
	var view: Node3D = main.get_node("Trees")
	var add := func(at: Vector2, form: String, age: float, sprouts := true) -> void:
		f.trees.append({"pos": at, "species": "birch", "form": form, "planted_at": f._now(), "start_age": age, "sprouts": sprouts, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	add.call(Vector2(30, -30), "sapling", 30.0)
	add.call(Vector2(36, -30), "sapling", 0.2)
	add.call(Vector2(42, -30), "seed", 0.0, true)
	f.changed.emit()
	print("木の当たり判定(準備)")
	_check(not view._items[0].trunk_body.disabled and view._items[0].trunk.visible, "幹のある木には当たり判定がある")
	_check(view._items[1].trunk_body.disabled and not view._items[1].trunk.visible, "幹のない苗木にはない")
	_check(view._items[2].trunk_body.disabled, "種にはない")
	var old_r: float = view._items[0].trunk_body.shape.radius
	f.trees[0].start_age = 3.0
	view._layout()
	var young_r: float = view._items[0].trunk_body.shape.radius
	_check(young_r < old_r and young_r >= view.TRUNK_BODY_MIN, "若い木の当たり判定は細い(%.2fm → %.2fm)" % [young_r, old_r])
	f.trees[0].start_age = 30.0
	view._layout()
	_check(old_r < 0.45, "幹の判定は太すぎない(半径 %.2fm。葉の下は歩ける)" % old_r)

func _test_tree_collision() -> void:
	print("木の当たり判定")
	var player: CharacterBody3D = main.get_node("Player")
	var south := Transform3D(Basis.IDENTITY, Vector3(30, 0, -27))
	_check(player.test_move(south, Vector3(0, 0, -6)), "育った木は通り抜けられない")
	_check(not player.test_move(Transform3D(Basis.IDENTITY, Vector3(30, 0, -27)), Vector3(1.5, 0, 0)), "木の横は歩ける")
	# 幹の 1m 横を通っても引っかからない(葉の下は歩ける)
	_check(not player.test_move(Transform3D(Basis.IDENTITY, Vector3(31.2, 0, -27)), Vector3(0, 0, -6)), "幹の横を通り過ぎられる")
	_check(not player.test_move(Transform3D(Basis.IDENTITY, Vector3(36, 0, -27)), Vector3(0, 0, -6)), "幹のない苗木は通り抜けられる")
	_check(not player.test_move(Transform3D(Basis.IDENTITY, Vector3(42, 0, -27)), Vector3(0, 0, -6)), "種は通り抜けられる")
	# 伐ると判定も消える(次の段階で確かめる)
	var f = main.world.forest
	f.trees.remove_at(0)
	f.changed.emit()

func _test_tree_collision_gone() -> void:
	var player: CharacterBody3D = main.get_node("Player")
	_check(not player.test_move(Transform3D(Basis.IDENTITY, Vector3(30, 0, -27)), Vector3(0, 0, -6)), "伐ると通れるようになる")

func _test_visitor_collision() -> void:
	print("待っている訪問者の当たり判定")
	var w = main.world
	var view: Node3D = main.get_node("Visitor")
	var player: CharacterBody3D = main.get_node("Player")
	var at: Vector2 = view.ground_pos()
	var south := Transform3D(Basis.IDENTITY, Vector3(at.x, 0, at.y + 2.0))
	_check(player.test_move(south, Vector3(0, 0, -2.0)), "プレイヤーは待っている訪問者を通り抜けられない")
	_check(not player.test_move(south, Vector3(1.5, 0, 0)), "訪問者の横は歩ける")
	_check(view.can_talk(Vector2(at.x, at.y + 0.7)), "ぶつかるまで近づいても話せる")
	w.visitors.finish_chat()
	view.sync_visit()
	_check(view.state() == "leave" and view._solid_shape.disabled, "帰りはじめると当たり判定が消える")

func _test_visitor_collision_off() -> void:
	var view: Node3D = main.get_node("Visitor")
	var player: CharacterBody3D = main.get_node("Player")
	var at: Vector2 = view.ground_pos()
	var south := Transform3D(Basis.IDENTITY, Vector3(at.x, 0, at.y + 2.0))
	_check(not player.test_move(south, Vector3(0, 0, -2.0)), "帰っているあいだは通り抜けられる(閉じ込められない)")

func _test_sound_view() -> void:
	print("音")
	var w = main.world
	var f = w.forest
	var audio: Node = main.get_node("Audio")
	var player: CharacterBody3D = main.get_node("Player")
	var figure: Node3D = player.get_node("Body/Figure")
	var saved_trees: Array = f.trees.duplicate()
	var noon := {"month": 10, "day": 15, "hour": 12, "minute": 0, "second": 0}
	f.trees.clear()
	f.set_season("autumn")
	f.today_event = "birds"
	f.last_day = f.today()
	w.clock.fixed_now = noon
	w.kitchen.pot = {}
	player.global_position = Vector3(-40, 0, -40)

	# 流し続ける音
	for sound in audio.LOOPS:
		var l: Dictionary = audio._loops[sound]
		_check(l.player.playing and l.player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s がくり返し鳴る" % sound)
	audio.update_ambient()
	var loops: Dictionary = audio._loops
	_check(loops.wind.goal > 0.0 and loops.brook.goal > 0.0, "風と遠くの川はいつも聞こえる")
	_check(loops.brook.goal < loops.wind.goal, "川は遠くの音なので、風より小さい")
	_check(loops.leaves.goal == 0.0, "まわりに木がないと葉の音はしない")
	_check(loops.rain.goal == 0.0 and loops.fire.goal == 0.0, "晴れていれば雨の音はなく、火の音もない")

	# 葉の音はまわりの木で変わる
	var tree := func(age: float, at: Vector2) -> void:
		f.trees.append({"pos": at, "species": "birch", "form": "sapling", "planted_at": f._now(), "start_age": age, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	tree.call(0.5, Vector2(-40, -38))
	_check(audio.leafy_trees_near(main.player_pos()) == 0, "小さな苗木は数えない")
	f.trees.clear()
	tree.call(20.0, Vector2(-40, -38))
	audio.update_ambient()
	var one: float = loops.leaves.goal
	_check(one > 0.0, "木のそばで葉の音がする")
	for i in range(5):
		tree.call(20.0, Vector2(-38 + i, -36))
	audio.update_ambient()
	_check(loops.leaves.goal > one, "木が多いと葉の音が大きい")
	var full: float = loops.leaves.goal
	f.trees.append({"pos": Vector2(40, 40), "species": "birch", "form": "sapling", "planted_at": f._now(), "start_age": 20.0, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	audio.update_ambient()
	_check(loops.leaves.goal == full and audio.leafy_trees_near(Vector2(40, 40)) == 1, "遠くの木は聞こえない")
	f.set_season("winter")
	audio.update_ambient()
	_check(loops.leaves.goal == 0.0, "冬の白樺は葉がないので音がしない")
	var winter_wind: float = loops.wind.goal
	f.trees.append({"pos": Vector2(-40, -38), "species": "cedar", "form": "sapling", "planted_at": f._now(), "start_age": 40.0, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	audio.update_ambient()
	_check(loops.leaves.goal > 0.0, "冬でも杉の葉は鳴る")
	f.set_season("autumn")
	audio.update_ambient()
	_check(loops.wind.goal < winter_wind, "冬は風が強い")

	# 雨(冬の雪は音がしない)
	f.today_event = "rain"
	audio.update_ambient()
	_check(loops.rain.goal > 0.0, "雨の日は雨の音がする")
	var rainy_leaves: float = loops.leaves.goal
	f.today_event = "birds"
	audio.update_ambient()
	_check(rainy_leaves < loops.leaves.goal, "雨の日は葉の音が小さい")
	f.set_season("winter")
	f.today_event = "rain"
	audio.update_ambient()
	_check(loops.rain.goal == 0.0, "雪は音がしない")
	f.set_season("autumn")
	f.today_event = "birds"

	# 小屋の中
	var c = w.cabin
	player.global_position = Vector3(c.site.x, 0, c.site.y)
	var outdoor_wind: float = 0.2
	audio.update_ambient()
	_check(c.is_inside(main.player_pos()) and loops.wind.goal < outdoor_wind * 0.5, "小屋の中では外の音が小さい")
	_check(loops.fire.goal == 0.0, "鍋が空なら火の音はしない")
	w.kitchen.pot = {"recipe": "pickles", "start_day": f.day_number()}
	audio.update_ambient()
	_check(loops.fire.goal > 0.0, "仕込んでいると、小屋の中で火の音がする")
	player.global_position = Vector3(c.site.x, 0, c.site.y + 6)
	audio.update_ambient()
	_check(loops.fire.goal == 0.0, "小屋の外では火の音はしない")
	w.kitchen.pot = {"recipe": "jam", "start_day": f.day_number() - 1}
	player.global_position = Vector3(c.site.x, 0, c.site.y)
	audio.update_ambient()
	_check(loops.fire.goal == 0.0, "できあがった鍋は火が落ちているので音がしない")
	w.kitchen.pot = {}

	# 強さはゆっくり変わる
	audio._ambient_timer = 0.0  # 見直しで goal が書き換わらないように
	loops.rain.level = 0.0
	loops.rain.goal = 1.0
	audio._process(0.1)
	_check(loops.rain.level > 0.0 and loops.rain.level < 0.1, "急に大きくならない(%.2f)" % loops.rain.level)
	loops.rain.goal = 0.0
	audio._process(5.0)
	_check(loops.rain.level == 0.0, "ゆっくり消える")

	# 足音: 歩く場所で変わる
	var plot: Vector2 = w.land.plots[0] if not w.land.plots.is_empty() else Vector2.ZERO
	_check(audio.surface_at(Vector2(c.site.x, c.site.y)) == "step_wood", "小屋の中は床の音")
	if not w.land.plots.is_empty():
		_check(audio.surface_at(plot) == "step_soil", "区画の上は土の音")
	_check(audio.surface_at(Vector2(-47, -47)) == "step_grass", "ほかは草の音")
	player.global_position = Vector3(-47, 0, -47)
	player.velocity = Vector3.ZERO
	audio.last_played = ""
	audio._update_steps(1.0)
	_check(audio.last_played == "", "止まっているときは足音がしない")

	# 作業音: 道具が当たるときに鳴る
	for kind in ["water", "dig", "chop", "build", "pick", "pick_high", "plant", "pull"]:
		audio.last_played = ""
		player.act(kind, Vector2(-47, -44))
		_check(audio.last_played == "", "%s: 押した瞬間にはまだ鳴らない" % kind)
		player._effect_tween.custom_step(10.0)
		_check(audio.last_played == audio.ALIASES.get(kind, kind), "%s の音が鳴る" % kind)
		figure._process(10.0)
	audio.play("no_such_sound")
	_check(audio.last_played != "no_such_sound", "知らない音は鳴らさない(止まらない)")
	# たくさん同時に鳴らしても止まらない
	for _i in range(audio.VOICES * 2):
		audio.play("click")
	_check(audio.last_played == "click", "同時に鳴らしすぎても大丈夫")

	# 画面の音
	w.market.money = 5000
	main._panel = "market"
	player.global_position = Vector3(0, 0, 54)
	audio.last_played = ""
	main._toggle_shop()
	_check(audio.last_played == "open", "市場を開く音")
	main._on_shop_action("birch_seed")
	_check(audio.last_played == "coin", "買うとお金の音")
	f.produce.apple = 2
	main._on_shop_action("sell_apple")
	_check(audio.last_played == "coin", "売るとお金の音")
	main._on_shop_action("sell_apple")
	_check(audio.last_played == "click", "売るものがなければ、お金の音はしない")
	w.market.money = 0
	main._on_shop_action("cedar_sapling")
	_check(audio.last_played == "click", "買えなければ、お金の音はしない")
	main._on_shop_action("close")
	_check(audio.last_played == "click", "閉じる音")

	# 音量
	var hud = main.get_node("HUD")
	w.sound_level = 3
	main._apply_sound_level()
	_check(not AudioServer.is_bus_mute(0) and absf(AudioServer.get_bus_volume_db(0)) < 0.01, "はじめは大")
	var key := InputEventKey.new()
	key.keycode = KEY_M
	key.pressed = true
	main._unhandled_input(key)
	_check(w.sound_level == 2 and hud._message.contains("中") and AudioServer.get_bus_volume_db(0) < -1.0, "M で中")
	main._unhandled_input(key)
	_check(w.sound_level == 1 and hud._message.contains("小"), "M で小")
	main._unhandled_input(key)
	_check(w.sound_level == 0 and AudioServer.is_bus_mute(0) and hud._message.contains("消す"), "M で消す")
	main._unhandled_input(key)
	_check(w.sound_level == 3 and not AudioServer.is_bus_mute(0) and absf(AudioServer.get_bus_volume_db(0)) < 0.01, "M で大に戻る")

	# 音量はセーブに残る
	w.sound_level = 1
	w.save_game()
	var w2 = load("res://logic/GameWorld.gd").new()
	w2.save_path = TEST_SAVE
	w2.load_game()
	_check(w2.sound_level == 1, "音量がセーブに残る")
	w.sound_level = 3
	main._apply_sound_level()
	w.save_game()

	# 木が倒れる音はあとで鳴る
	audio.last_played = ""
	f.trees.clear()
	f.trees.append({"pos": Vector2(-47, -45), "species": "birch", "form": "sapling", "planted_at": f._now(), "start_age": 30.0, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	f.changed.emit()
	player.global_position = Vector3(-47, 0, -44)
	main._remove()
	main._remove()
	_check(f.trees.is_empty(), "前提: 木を伐った")
	_check(audio.last_played != "tree_fall", "倒れる音は、斧のあとで鳴る")
	audio.play("tree_fall")
	_check(audio.last_played == "tree_fall", "倒れる音が鳴る")
	figure._process(10.0)
	if player._effect_tween != null:
		player._effect_tween.kill()

	f.trees.assign(saved_trees)
	f.changed.emit()
	w.clock.fixed_now = {}
	player.global_position = Vector3(20, 0, 23)

func _test_fruit_view() -> void:
	print("果樹")
	var w = main.world
	var f = w.forest
	var hud = main.get_node("HUD")
	var view: Node3D = main.get_node("Trees")
	var player: CharacterBody3D = main.get_node("Player")
	var figure: Node3D = player.get_node("Body/Figure")
	var saved_trees: Array = f.trees.duplicate()
	f.trees.clear()
	figure._process(10.0)
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	main.selected_species = "birch"
	main.selected_form = "seed"

	# キーで選ぶ
	main._unhandled_input(key)
	_check(main.selected_species == "apple" and main.selected_form == "seed", "2 でリンゴ(種のまま)")
	main._unhandled_input(key)
	_check(main.selected_species == "cherry" and main.selected_form == "sapling", "もう一度でサクランボ(苗木に切り替わる)")
	_check(main.selected_name() == "サクランボの苗木", "HUD の名前: %s" % main.selected_name())
	main._unhandled_input(key)
	main._unhandled_input(key)
	_check(main.selected_species == "pear", "スモモ、ナシと進む")
	main._unhandled_input(key)
	_check(main.selected_species == "apple", "一回りしてリンゴに戻る")

	# 種からは植えられない
	main.selected_species = "plum"
	main.selected_form = "seed"
	player.global_position = Vector3(-15, 0, 42)
	main._on_plant_tree(main.player_pos())
	_check(f.trees.is_empty() and hud._message.contains("苗木から育てる"), "種では植えられないと知らせる")

	# 苗木を買って植える
	main._panel = "market"
	w.market.money = 5000
	_check(main.shop_rows().any(func(r): return r.id == "cherry_sapling" and r.text.contains("サクランボの苗木") and r.text.contains("700₽")), "市場に苗木が並ぶ")
	main._on_shop_action("cherry_sapling")
	_check(f.saplings.cherry == 1 and hud._message.contains("サクランボの苗木"), "市場で買える")
	main.selected_species = "cherry"
	main.selected_form = "sapling"
	main._on_plant_tree(main.player_pos())
	_check(f.trees.size() == 1 and f.trees[0].species == "cherry", "植えられる")
	figure._process(10.0)

	# 見た目: 季節ごと
	var tree: Dictionary = f.trees[0]
	tree.start_age = 30.0
	f.set_season("summer")
	f.changed.emit()
	var item: Dictionary = view._items[0]
	_check(item.fruits.size() == 5, "夏はサクランボに実がなる")
	_check(item.fruits[0].material_override.albedo_color == view.FRUIT_LOOKS.cherry.color, "サクランボの色の実")
	_check(item.fruits[0].scale.x <= 0.3 * view.FRUIT_LOOKS.cherry.scale + 0.001, "サクランボの実はリンゴより小さい")
	f.set_season("autumn")
	_check(view._items[0].fruits.is_empty(), "秋のサクランボに実はない")
	f.set_season("spring")
	var spring_color: Color = view._leaf_color("cherry")
	_check(spring_color.r > 0.8, "春は花の色になる")
	f.set_season("winter")
	_check(view.is_bare("cherry") and view._items[0].crown_mesh != null, "冬は枝だけ")
	f.set_season("summer")
	for id in ["plum", "pear", "apple"]:
		_check(view.KINDS.has(id) and view.FRUIT_LOOKS.has(id) and view.BLOSSOMS.has(id), "%s の見た目がある" % id)
		var shape: Dictionary = view._shape(id, 0)
		_check(shape.crown != null and shape.trunk != null and shape.bare != null and not shape.anchors.is_empty(), "%s の形が作れる" % id)

	# 収穫: 動きと文言
	player.global_position = Vector3(tree.pos.x + 1.0, 0, tree.pos.y)
	main._harvest()
	_check(f.produce.cherry == 3 and hud._message.contains("サクランボを3kg") and hud._message.contains("60₽"), "E で収穫: %s" % hud._message)
	_check(figure.current_action() == "pick_high", "手を上げて採る")
	player._effect_tween.custom_step(10.0)
	_check(player.get_node("WorkEffects")._mats.has(view.FRUIT_LOOKS.cherry.color), "サクランボの色の玉が飛ぶ")
	figure._process(10.0)
	_check(view._items[0].fruits.is_empty(), "採ると、今日は実が消える")
	main._harvest()
	_check(hud._message.contains("今日もう"), "1 日 1 回")
	f.set_season("autumn")
	main._harvest()
	_check(hud._message == "サクランボが実るのは夏", "季節の文言: %s" % hud._message)
	f.set_season("summer")
	tree.start_age = 3.0
	tree.last_harvest = ""
	main._harvest()
	_check(hud._message.contains("樹齢4年から"), "樹齢の文言: %s" % hud._message)

	# 持ち物と料理
	_check(main.produce_line().contains("サクランボ 3kg"), "持ち物に出る")
	_check(main.shop_rows().any(func(r): return r.id == "sell_cherry" and r.text.contains("サクランボ 3kg × 60₽")), "市場に売る行が出る")
	main._on_shop_action("sell_cherry")
	_check(f.produce.cherry == 0, "売れる")
	_check(main.kitchen_rows().any(func(r): return r.id == "cook_cherry_jam" and r.text.contains("サクランボ 3kg") and r.text.contains("4瓶")), "ストーブの料理に出る")
	var room: Node3D = main.get_node("Cabin")
	w.kitchen.stock.cherry_jam = 1
	w.kitchen.changed.emit()
	_check(room.FOOD_COLORS.has("cherry_jam") and room.FOOD_COLORS.has("plum_jam") and room.FOOD_COLORS.has("pear_compote"), "保存食の色がある")
	w.kitchen.stock.cherry_jam = 0
	w.kitchen.changed.emit()
	_check(main.diary_text().contains("果物を収穫できる木") == (f.fruiting_in(w.season_for_month(int(w.tomorrow_date().substr(5, 2)))) > 0), "日記の果物の行は、明日の季節に合う")
	_check(hud.status_text() != "", "HUD が崩れない")
	hud.inventory_open = true
	_check(hud.status_text().contains("サクランボ") and hud.status_text().contains("ナシ"), "持ち物に苗木の枠が出る")
	hud.inventory_open = false

	f.set_season("autumn")
	f.trees.assign(saved_trees)
	f.changed.emit()
	main.selected_species = "birch"
	main.selected_form = "seed"

func _test_hive_view() -> void:
	print("巣箱")
	var w = main.world
	var b = w.bees
	var view: Node3D = main.get_node("Hives")
	var player: CharacterBody3D = main.get_node("Player")
	var hud = main.get_node("HUD")
	var figure: Node3D = player.get_node("Body/Figure")
	var at := Vector2(-40, 40)
	var names := func() -> Array:
		var spot: Node3D = view.get_child(0)
		return spot.get_children().map(func(n): return str(n.name))
	var has_piece := func(prefix: String) -> bool:
		return names.call().any(func(n): return n.contains(prefix))
	figure._process(10.0)
	player.global_position = Vector3(at.x, 0, at.y)
	b.hives.clear()
	b.changed.emit()
	w.cabin.materials.log = 0
	w.cabin.own_logs = 0
	_check(view.get_child_count() == 0 and main.hive_line() == "", "はじめは巣箱がなく、案内も出ない")
	var key := InputEventKey.new()
	key.keycode = KEY_J
	key.pressed = true
	main._unhandled_input(key)
	_check(hud._message.contains("自分の木を伐った丸太"), "丸太がないと、何がいるかを知らせる")
	w.cabin.materials.log = 2
	w.cabin.own_logs = 2
	_check(main.hive_line().contains("J で足元に作れる"), "自分の丸太があると案内する")
	main._unhandled_input(key)
	_check(view.get_child_count() == 1 and not has_piece.call("HiveRoof"), "J で丸太が立つ(まだ屋根はない)")
	_check(is_equal_approx(b.hives[0].pos.distance_to(at), main.HIVE_FRONT), "体の前に立つ(足元に埋まらない)")
	_check(figure.current_action() == "build", "作業の動きをする")
	figure._process(10.0)
	_check(main.hive_line().contains("くり抜き 0/3日") and main.hive_line().contains("J でくり抜く"), "そばではくり抜きの案内が出る: %s" % main.hive_line())
	main._unhandled_input(key)
	_check(hud._message.contains("1/3日") and main.hive_line().contains("今日は済んだ"), "くり抜くと進む")
	main._unhandled_input(key)
	_check(hud._message.contains("1日1回"), "今日はもうくり抜けない")
	figure._process(10.0)
	var h: Dictionary = b.hive_near(at)
	h.days_done = 2
	h.last_worked = ""
	main._unhandled_input(key)
	_check(has_piece.call("HiveRoof") and has_piece.call("HiveDoor"), "できあがると屋根と入口が付く")
	_check(hud._message.contains("フョードルさん"), "蜂の入れ方を知らせる")
	_check(not has_piece.call("HiveBee"), "まだ蜂はいない")
	figure._process(10.0)
	_check(main.hive_line().contains("蜂を待っている"), "そばで分かる")

	# フョードルさんに分けてもらう
	var vs = w.visitors
	vs.visit = {"day": w.forest.day_number(), "who": "fyodor", "kind": "bees", "done": false, "line": 0}
	var visitor: Node3D = main.get_node("Visitor")
	visitor._state = "away"
	visitor.sync_visit()
	for _i in range(600):
		if visitor.state() == "wait":
			break
		visitor.step(0.1)
	_check(visitor._mark.get_child(0).material_override == visitor._request_mat, "蜂を分けてくれる人は橙の印")
	main._talk()
	_check(main.shop_header().contains("蜂を一群れ"), "言葉: %s" % main.shop_header())
	_check(main.visitor_rows().any(func(r): return r.id == "receive_bees"), "受け取る行が出る")
	main._on_shop_action("receive_bees")
	_check(h.occupied and not vs.is_here() and not hud.is_shop_open(), "分けてもらうと巣箱に蜂が入る")
	_check(has_piece.call("HiveBee"), "蜂が飛ぶ")
	var bee: MeshInstance3D = view._flying[0].node
	var bee_from: Vector3 = bee.position
	view._process(0.4)
	_check(bee.position != bee_from and bee.position.distance_to(Vector3(0, view.LOG_H * 0.7, 0)) < view.BEE_ORBIT * 2.0, "入口のまわりを飛ぶ")
	visitor.sync_visit()
	for _i in range(600):
		if visitor.state() == "away":
			break
		visitor.step(0.1)
	_check(main.hive_line().contains("ためている"), "そばで分かる")
	main._unhandled_input(key)
	_check(hud._message.contains("まだ採れるほど"), "たまるまで採れない")

	# はちみつを採って売る
	h.comb = 3.0
	b.changed.emit()
	_check(has_piece.call("HiveHoney"), "たまると金色になる")
	_check(main.hive_line().contains("3kg 採れる"), "採れる量が分かる: %s" % main.hive_line())
	_check(main.diary_text().contains("はちみつが採れる巣箱が 1"), "日記に出る")
	figure._process(10.0)
	main._unhandled_input(key)
	_check(int(b.stock.honey) == 3 and hud._message.contains("3kg") and figure.current_action() == "pick", "J で採る")
	_check(not has_piece.call("HiveHoney"), "採ると金色が消える")
	_check(main.produce_line().contains("はちみつ 3kg"), "持ち物に出る")
	main._panel = "market"
	_check(main.shop_rows().any(func(r): return r.id == "sell_honey" and r.text.contains("はちみつ 3kg × 200₽")), "市場に売る行が出る")
	var money: int = w.market.money
	main._on_shop_action("sell_honey")
	_check(w.market.money == money + 600, "売れる")
	figure._process(10.0)

	# 離れていると全体の様子
	player.global_position = Vector3(0, 0, 0)
	_check(main.hive_line().contains("1箱") and main.hive_line().contains("蜂 1箱"), "離れていると数が出る: %s" % main.hive_line())
	var hive_at: Vector2 = b.hives[0].pos
	player.global_position = Vector3(hive_at.x + 0.5, 0, hive_at.y)
	main._on_plant_tree(main.player_pos())
	_check(hud._message.contains("巣箱の近くには"), "巣箱の近くには木を植えられない")
	# 訪問者は巣箱を回り込む
	_check(visitor._obstacles().any(func(r): return r.has_point(hive_at)), "訪問者は巣箱を回り込む")
	# 当たり判定(物理サーバーに入るのを待って _test_hive_collision で確かめる)
	_check(view.get_child(0).get_node("HiveBody") is StaticBody3D, "巣箱に当たり判定がある")

func _test_hive_collision() -> void:
	var player: CharacterBody3D = main.get_node("Player")
	var at: Vector2 = main.world.bees.hives[0].pos
	var south := Transform3D(Basis.IDENTITY, Vector3(at.x, 0, at.y + 2.0))
	_check(player.test_move(south, Vector3(0, 0, -2.0)), "巣箱は通り抜けられない")
	_check(not player.test_move(south, Vector3(1.5, 0, 0)), "巣箱の横は歩ける")

func _test_hint_panel() -> void:
	print("ヒントの表示")
	var w = main.world
	var g = w.guide
	var hud = main.get_node("HUD")
	var panel: PanelContainer = hud._hint_panel
	var press := func(code: int) -> void:
		var e := InputEventKey.new()
		e.keycode = code
		e.pressed = true
		main._unhandled_input(e)
	g.current = ""
	hud._update_hint()
	_check(not panel.visible, "ヒントがなければ何も出ない")
	g.current = "broke"
	hud._update_hint()
	_check(panel.visible and hud._hint_label.text.contains("お金と種") and hud._hint_label.text.contains("K で閉じる"), "ヒントが右上に出る")
	main._panel = "market"
	hud.open_shop()
	hud._update_hint()
	_check(not panel.visible, "市場の画面を開いているあいだは隠す")
	hud.close_shop()
	hud.open_diary("日記")
	hud._update_hint()
	_check(not panel.visible, "日記を開いているあいだは隠す")
	hud.close_diary()
	hud._update_hint()
	_check(panel.visible, "閉じるとまた出る")
	press.call(KEY_K)
	_check(g.current == "" and "broke" in g.seen, "K で閉じる")
	hud._update_hint()
	_check(not panel.visible, "閉じると消える")
	g.seen.erase("broke")

func _test_visitor_view() -> void:
	print("訪ねてくる人")
	var w = main.world
	var vs = w.visitors
	var view: Node3D = main.get_node("Visitor")
	var player: CharacterBody3D = main.get_node("Player")
	var hud = main.get_node("HUD")
	var today: int = w.forest.day_number()
	# 歩かせる: 動かなくなるまで進める
	var walk := func(state: String) -> void:
		for _i in range(400):
			if view.state() == state:
				return
			view.step(0.1)
	var press := func(code: int) -> void:
		var e := InputEventKey.new()
		e.keycode = code
		e.pressed = true
		main._unhandled_input(e)

	# 来ない日
	vs.visit = {"day": today}
	view.sync_visit()
	_check(view.state() == "away" and main.visitor_line() == "", "来ない日は誰もいない")
	player.global_position = Vector3(-20, 0, -10)
	press.call(KEY_C)
	_check(not hud.is_shop_open(), "誰もいなければ C を押しても何も起きない")

	# 頼みごとの日: 入口から歩いて来て、足元の近くで待つ
	vs.visit = {"day": today, "who": "nina", "kind": "request", "item": "tomato", "amount": 5, "reward": {"type": "money", "amount": 260}, "done": false, "line": 0}
	w.garden.produce.tomato = 3
	view.sync_visit()
	_check(view.state() == "arrive" and view.ground_pos() == view.GATE, "土地の入口から来る")
	var figure: Node3D = view._figure
	_check(figure != null and figure.name.contains("nina"), "ニーナさんの姿が出る")
	view.step(0.1)
	_check(figure.moving and view.ground_pos() != view.GATE, "歩いて来る")
	walk.call("wait")
	var spot: Vector2 = view.ground_pos()
	_check(view.state() == "wait" and not figure.moving, "着くと止まる")
	_check(spot.distance_to(main.player_pos()) <= view.GOAL_RADII[0] + 0.01, "足元の近くで待つ(%.1fm)" % spot.distance_to(main.player_pos()))
	_check(spot.y < main.player_pos().y, "プレイヤーの北に立つ(顔がカメラのほうを向く)")
	_check(figure.current_action() == "wave", "着くと手を振る")
	figure._process(0.5)
	_check(figure._arm_r.rotation.x > 1.0, "手を上げている")
	figure._process(10.0)
	_check(not figure.is_acting() and absf(figure._arm_r.get_parent().rotation.z - figure.ARM_SPREAD) < 0.01, "振り終えると腕が戻る")
	view.step(0.1)
	var facing: Vector3 = -figure.global_basis.z
	view.step(10.0)
	facing = -figure.global_basis.z
	var to_player: Vector2 = (main.player_pos() - spot).normalized()
	_check(Vector2(facing.x, facing.z).dot(to_player) > 0.95, "プレイヤーのほうを向く")
	_check(view._mark.visible and view._mark.get_child(0).material_override == view._request_mat, "頼みごとがあると橙の印が出る")

	# 色は人ごとに違い、プレイヤーの色は変わらない
	var tunic: MeshInstance3D = figure.get_node("Hips/Upper/Tunic")
	var player_tunic: MeshInstance3D = player.get_node("Body/Figure/Hips/Upper/Tunic")
	_check(tunic.material_override.albedo_color == view.LOOKS.nina.look.TUNIC, "ニーナさんの服の色になっている")
	_check(player_tunic.material_override.albedo_color == player.get_node("Body/Figure").TUNIC, "プレイヤーの服の色は変わらない")

	# HUD の案内: 離れていると向きと距離、近いと C
	player.global_position = Vector3(spot.x + 20, 0, spot.y)
	var far_line: String = main.visitor_line()
	_check(far_line.contains("ニーナさん") and far_line.contains("西") and far_line.contains("20m") and far_line.contains("頼みごと"), "離れていると向きと距離が出る: %s" % far_line)
	press.call(KEY_C)
	_check(not hud.is_shop_open(), "離れていると話せない")
	_check(hud._message.contains("ニーナさん"), "どこにいるかを知らせる")
	player.global_position = Vector3(spot.x + 2, 0, spot.y)
	_check(main.visitor_line().contains("C で話す"), "近いと C の案内が出る")
	_check(main.diary_text().contains("ニーナさんの頼みごとがまだ"), "日記にも出る")
	_check(main.compass(Vector2(1, 0)) == "東" and main.compass(Vector2(0, -1)) == "北" and main.compass(Vector2(-1, 1)) == "南西", "向きの文言が合う")

	# 話す: 足りないと渡せない
	press.call(KEY_C)
	_check(hud.is_shop_open() and main._panel == "visitor" and not player.is_physics_processing(), "C で話す画面が開き、歩かなくなる")
	_check(figure.current_action() == "wave", "話しかけると手を振る")
	_check(main.shop_title() == "ニーナさん", "見出しが名前になる")
	var text: String = main.shop_header()
	_check(text.contains("トマト") and text.contains("5kg") and text.contains("260₽"), "何を頼むかが分かる: %s" % text)
	_check(not hud.status_text().contains("─ 持ち物 ─"), "話す画面には持ち物を重ねない")
	_check(main.visitor_rows().any(func(r): return r.id == "give" and r.text.contains("トマト 3kg")), "持っている量が分かる")
	main._on_shop_action("give")
	_check(hud._message.contains("あと2kg足りない") and vs.is_here() and hud.is_shop_open(), "足りなければ足りない量を知らせる")
	press.call(KEY_C)
	_check(not hud.is_shop_open() and player.is_physics_processing() and vs.is_here(), "C で閉じても、まだ待っている(断っても罰はない)")
	_check(main._panel == "market", "閉じると市場の画面に戻る")

	# 渡す: お礼をもらって帰っていく
	w.garden.produce.tomato = 5
	var money: int = w.market.money
	press.call(KEY_C)
	main._on_shop_action("give")
	_check(w.market.money == money + 260 and w.garden.produce.tomato == 0, "渡すとお礼をもらう")
	_check(hud._message.contains("260₽") and hud._message.contains("ありがとう"), "お礼の文言: %s" % hud._message)
	_check(not hud.is_shop_open() and player.get_node("Body/Figure").current_action() == "pick", "画面が閉じて、渡す動きをする")
	player.get_node("Body/Figure")._process(10.0)
	view.sync_visit()
	_check(view.state() == "leave" and not view._mark.visible, "帰っていく。印は消える")
	walk.call("away")
	_check(view.state() == "away" and view._figure == null, "入口まで行くと消える")
	_check(main.visitor_line() == "", "帰ると案内が消える")

	# 話すだけの日: 話し終えると帰る
	vs.visit = {"day": today, "who": "pavel", "kind": "chat", "done": false, "line": 0}
	player.global_position = Vector3(-20, 0, -10)
	view.sync_visit()
	walk.call("wait")
	_check(view._mark.get_child(0).material_override == view._chat_mat, "話すだけの日は白い印")
	_check(view._figure.get_node("Hips/Upper/Head").get_child_count() > 2, "帽子などが付いている")
	press.call(KEY_C)
	_check(main.shop_title() == "パーヴェルさん" and main.shop_header().contains("明日は"), "パーヴェルさんは明日の空模様を話す: %s" % main.shop_header())
	_check(main.visitor_rows().any(func(r): return r.id == "chat_end"), "別れの行が出る")
	main._on_shop_action("chat_end")
	_check(not hud.is_shop_open() and not vs.is_here(), "話し終えると用が済む")
	view.sync_visit()
	_check(view.state() == "leave", "帰っていく")
	view.sync_visit()
	press.call(KEY_ESCAPE)
	walk.call("away")

	# Esc で閉じても帰る
	vs.visit = {"day": today, "who": "tanya", "kind": "chat", "done": false, "line": 1}
	view.sync_visit()
	walk.call("wait")
	var tanya_scale: float = view._figure.scale.x
	_check(tanya_scale < 1.0, "ターニャさんは体が小さい")
	press.call(KEY_C)
	press.call(KEY_ESCAPE)
	_check(not vs.is_here(), "Esc で閉じても話し終えたことになる")
	view.sync_visit()
	walk.call("away")

	# 小屋があると回り込む。小屋の上で待たない
	var c = w.cabin
	var cabin_rect: Rect2 = c.rect()
	var inside := false
	var north: Vector2 = c.site + Vector2(0, -6)
	var pts: Array = view.route(view.GATE, north)
	var at: Vector2 = view.GATE
	for p in pts:
		for i in range(21):
			if cabin_rect.has_point(at.lerp(p, i / 20.0)):
				inside = true
		at = p
	_check(pts.size() >= 2 and not inside and pts[-1] == north, "小屋を通り抜けず、回り込む(%d 点)" % pts.size())
	var straight: Array = view.route(Vector2(0, 49), Vector2(0, 40))
	_check(straight == [Vector2(0, 40)], "何もなければまっすぐ")
	var goal: Vector2 = view.goal_near(c.site)
	_check(not cabin_rect.has_point(goal) and view._is_free(goal), "小屋の中にいるときは、外で待つ")
	var pond_save = w.land.pond
	w.land.pond = Vector2(0, 35)
	var pond_pts: Array = view.route(view.GATE, Vector2(0, 25))
	var in_pond := false
	at = view.GATE
	for p in pond_pts:
		for i in range(21):
			if at.lerp(p, i / 20.0).distance_to(w.land.pond) < w.land.POND_RADIUS:
				in_pond = true
		at = p
	_check(not in_pond, "池も回り込む")
	w.land.pond = pond_save
	var edge_goal: Vector2 = view.goal_near(Vector2(0, 56))
	_check(absf(edge_goal.y) <= 49.5, "プレイヤーが土地の外にいても、土地の中で待つ")

	# プレイヤーをすり抜けない: 北で待っていて、南の入口へ帰るとき
	var f = w.forest
	var saved_trees: Array = f.trees.duplicate()
	f.trees.clear()  # 前のテストの木で立つ場所が変わらないように
	vs.visit = {"day": today, "who": "nina", "kind": "chat", "done": false, "line": 0}
	player.global_position = Vector3(0, 0, 8)  # 入口の真北。まっすぐ帰ると体を通る
	view.sync_visit()
	walk.call("wait")
	_check(view.ground_pos().y < main.player_pos().y and absf(view.ground_pos().x - main.player_pos().x) < 0.01, "前提: プレイヤーの真北で待っている")
	vs.finish_chat()
	view.sync_visit()
	var closest := 99.0
	for _i in range(400):
		if view.state() == "away":
			break
		view.step(0.05)
		closest = minf(closest, view.ground_pos().distance_to(main.player_pos()))
	_check(view.state() == "away" and closest >= view.AVOID_RADIUS - 0.05, "帰るときプレイヤーをすり抜けない(いちばん近くて %.2fm)" % closest)

	# 来るときも、プレイヤーをすり抜けない(プレイヤーの北へ回り込む)
	vs.visit = {"day": today, "who": "nina", "kind": "chat", "done": false, "line": 0}
	player.global_position = Vector3(0, 0, 30)  # 入口の真北
	view.sync_visit()
	closest = 99.0
	for _i in range(400):
		if view.state() == "wait":
			break
		view.step(0.05)
		closest = minf(closest, view.ground_pos().distance_to(main.player_pos()))
	_check(view.state() == "wait" and closest >= view.AVOID_RADIUS - 0.05, "来るときプレイヤーをすり抜けない(いちばん近くて %.2fm)" % closest)

	# 歩いている途中にプレイヤーが道へ入っても、よけて進む
	vs.finish_chat()
	view.sync_visit()
	view.step(0.2)
	var ahead: Vector2 = view.ground_pos() + (view._route_points[0] - view.ground_pos()).normalized() * 1.5
	player.global_position = Vector3(ahead.x, 0, ahead.y)
	closest = 99.0
	for _i in range(400):
		if view.state() == "away":
			break
		view.step(0.05)
		closest = minf(closest, view.ground_pos().distance_to(main.player_pos()))
	_check(view.state() == "away", "道をふさがれても、よけて帰り着く")
	_check(closest >= view.AVOID_RADIUS - 0.2, "途中で入ってきたプレイヤーをよける(いちばん近くて %.2fm)" % closest)

	# 行き先にプレイヤーが立っていても、止まらない(周りを回り続けない)
	vs.visit = {"day": today, "who": "nina", "kind": "chat", "done": false, "line": 0}
	player.global_position = Vector3(0, 0, 20)
	view.sync_visit()
	var goal_spot: Vector2 = view._route_points[-1]
	player.global_position = Vector3(goal_spot.x, 0, goal_spot.y)  # 待つはずの場所へ先回りする
	for _i in range(400):
		if view.state() == "wait":
			break
		view.step(0.05)
	_check(view.state() == "wait" and view.can_talk(main.player_pos()), "待つ場所にプレイヤーが立っていても、そばで止まって話せる")
	vs.finish_chat()
	view.sync_visit()
	player.global_position = Vector3(view.GATE.x, 0, view.GATE.y)  # 入口に立ちふさがる
	for _i in range(400):
		if view.state() == "away":
			break
		view.step(0.05)
	_check(view.state() == "away", "入口にプレイヤーが立っていても帰れる")

	# 木をすり抜けない
	for z in [40.0, 30.0, 20.0]:
		f.trees.append({"pos": Vector2(0, z), "species": "birch", "form": "sapling", "planted_at": f._now(), "start_age": 20.0, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	# 芽が出ていない種は避けない
	f.trees.append({"pos": Vector2(0, 45), "species": "birch", "form": "seed", "planted_at": f._now(), "start_age": 0.0, "sprouts": false, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	player.global_position = Vector3(30, 0, 0)
	var tree_pts: Array = view.route(view.GATE, Vector2(0, 10))
	var hit_tree := false
	at = view.GATE
	for p in tree_pts:
		var d: float = at.distance_to(p)
		for i in range(int(d * 10.0) + 1):
			var q: Vector2 = at.lerp(p, i / maxf(d * 10.0, 1.0))
			for z in [40.0, 30.0, 20.0]:
				if q.distance_to(Vector2(0, z)) < 0.5:
					hit_tree = true
		at = p
	_check(not hit_tree and tree_pts.size() > 1, "幹の並びを回り込む(%d 点)" % tree_pts.size())
	_check(view.route(view.GATE, Vector2(0, 47)) == [Vector2(0, 47)], "芽が出ていない種は避けない")
	_check(not view._is_free(Vector2(0, 30.3)), "木のすぐそばには立たない")
	f.trees.assign(saved_trees)
	vs.visit = {"day": today}
	view.sync_visit()

	# 手詰まりのとき: 分けてくれる
	var keep_money: int = w.market.money
	var keep_seeds: Dictionary = w.garden.seeds.duplicate()
	var keep_produce: Dictionary = w.garden.produce.duplicate()
	var keep_stock: Dictionary = w.kitchen.stock.duplicate()
	var keep_apple: int = int(f.produce.apple)
	var keep_crops: Array = w.garden.crops.duplicate()
	var keep_pots: Array = w.seedlings.pots.duplicate()
	var keep_ready: Dictionary = w.seedlings.ready.duplicate()
	var keep_trees: Array = f.trees.duplicate()
	var keep_pot: Dictionary = w.kitchen.pot.duplicate()
	f.trees.clear()  # 秋に実るリンゴがあると手詰まりにならない
	w.kitchen.pot = {}
	w.market.money = 20
	for k in w.garden.seeds:
		w.garden.seeds[k] = 0
	for k in w.garden.produce:
		w.garden.produce[k] = 0
	for k in w.kitchen.stock:
		w.kitchen.stock[k] = 0
	for k in w.seedlings.ready:
		w.seedlings.ready[k] = 0
	f.produce.apple = 0
	w.garden.crops.clear()
	w.seedlings.pots.clear()
	f.set_season("autumn")
	_check(vs.is_stuck(), "前提: 手詰まり")
	vs.visit = {"day": today, "who": "tanya", "kind": "chat", "done": false, "line": 0}
	player.global_position = Vector3(-20, 0, 8)
	view.sync_visit()
	walk.call("wait")
	press.call(KEY_C)
	_check(vs.has_help() and hud.is_shop_open(), "話しかけると、手詰まりなら分けてくれる")
	var help_text: String = main.shop_header()
	_check(help_text.contains("ラディッシュの種 3つ"), "何をくれるかが分かる: %s" % help_text)
	_check(main.visitor_rows().any(func(r): return r.id == "receive"), "受け取る行が出る")
	press.call(KEY_C)
	_check(vs.has_help() and vs.is_here(), "閉じても、まだ待っている")
	view.sync_visit()
	_check(view._mark.get_child(0).material_override == view._request_mat, "分けてくれるものがあると橙の印")
	player.global_position = Vector3(-20, 0, 40)
	_check(main.visitor_line().contains("渡したいものがある"), "離れていても分かる: %s" % main.visitor_line())
	player.global_position = Vector3(view.ground_pos().x, 0, view.ground_pos().y + 2)
	press.call(KEY_C)
	main._on_shop_action("receive")
	_check(w.garden.seeds.radish == 3 and not vs.is_here() and not hud.is_shop_open(), "受け取ると種が増えて、帰っていく")
	_check(hud._message.contains("ターニャさん") and hud._message.contains("3つ"), "もらった文言: %s" % hud._message)
	view.sync_visit()
	_check(view.state() == "leave", "受け取ると帰っていく")
	walk.call("away")
	# 冬はお金
	w.garden.seeds.radish = 0
	f.set_season("winter")
	vs.visit = {"day": today, "who": "pavel", "kind": "chat", "done": false, "line": 0}
	player.global_position = Vector3(-20, 0, 8)
	view.sync_visit()
	walk.call("wait")
	press.call(KEY_C)
	_check(main.shop_header().contains("200₽") and main.shop_header().contains("冬"), "冬はお金をくれる: %s" % main.shop_header())
	main._on_shop_action("receive")
	_check(w.market.money == 220, "受け取ると所持金が増える")
	view.sync_visit()
	walk.call("away")
	f.set_season("autumn")
	w.market.money = keep_money
	w.garden.seeds.assign(keep_seeds)
	w.garden.produce.assign(keep_produce)
	w.kitchen.stock.assign(keep_stock)
	w.seedlings.ready.assign(keep_ready)
	f.produce.apple = keep_apple
	w.garden.crops.assign(keep_crops)
	w.seedlings.pots.assign(keep_pots)
	f.trees.assign(keep_trees)
	w.kitchen.pot = keep_pot

	# 日記に明日来る人が出る
	var tomorrow: int = today + 1
	if vs.is_visit_day(tomorrow):
		_check(main.diary_text().contains("%sが来そう" % vs.CAST[vs.who_on(tomorrow)].name), "明日来る人が日記に出る")
	else:
		_check(not main.diary_text().contains("が来そう"), "明日来ない日は出ない")
	vs.visit = {"day": today}
	player.global_position = Vector3(20, 0, 23)

func _test_wildlife_view() -> void:
	print("土地に来る生き物")
	var w = main.world
	var f = w.forest
	var wl = w.wildlife
	var view: Node3D = main.get_node("Wildlife")
	var player: CharacterBody3D = main.get_node("Player")
	var hud = main.get_node("HUD")
	const NOON := {"month": 10, "day": 15, "hour": 12, "minute": 0, "second": 0}
	const MIDNIGHT := {"month": 10, "day": 15, "hour": 23, "minute": 30, "second": 0}
	# まっさらにして始める
	var saved_trees: Array = f.trees.duplicate()
	var saved_crops: Array = w.garden.crops.duplicate()
	var saved_plots: Array = w.land.plots.duplicate()
	f.trees.clear()
	w.garden.crops.clear()
	w.land.plots.clear()
	f.set_season("autumn")
	f.last_day = f.today()
	f.today_event = "birch_seed"
	w.clock.fixed_now = NOON
	player.global_position = Vector3(-30, 0, 30)
	view.sync_animals()
	_check(view._animals.is_empty(), "何もない土地には何もいない")

	# 木と畑を足すと現れる
	for i in range(12):
		f.trees.append({"pos": Vector2(i * 4 - 20, -30), "species": "birch", "form": "sapling", "planted_at": f._now(), "start_age": 8.0, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	for i in range(8):
		w.land.plots.append(Vector2(i * 3 + 1.5, -40.5))
	w.garden.crops.append({"pos": Vector2(1.5, -40.5), "kind": "radish", "sown_day": w.garden.day_number(), "water_days": 0, "last_watered": "", "head": 0.0})
	view.sync_animals()
	var want: Dictionary = wl.counts()
	for id in want:
		_check(view.count(id) == want[id], "%s が %d 匹いる" % [wl.SPECIES[id].name, want[id]])
	_check(want.has("sparrow") and want.has("squirrel") and want.has("butterfly") and want.has("bee"), "前提: 昼の 4 種類")
	view.sync_animals()
	_check(view.count("sparrow") == want.sparrow, "見直しても増えすぎない")
	for a in view._animals:
		var ok: bool = a.node.get_child_count() > 0 and wl.is_free(a.pos) and a.node.is_inside_tree()
		if not ok:
			_check(false, "%s の置き場所" % a.id)
	_check(view._animals.all(func(a): return a.pos.distance_to(a.home) <= 3.5), "住みかの近くにいる")

	# 歩く: 止まっている時間がすぎると動く
	var bird: Dictionary = view._animals.filter(func(a): return a.id == "sparrow")[0]
	bird.wait = 0.0
	var from: Vector2 = bird.pos
	view._walk(bird, 0.01, Vector2(500, 500))
	_check(bird.mode == "walk", "時間がたつと歩きだす")
	for _i in range(20):
		view._walk(bird, 0.05, Vector2(500, 500))
	_check(bird.pos != from or bird.mode == "idle", "歩いて動く")
	_check(bird.pos.distance_to(bird.home) <= view.MOVES.sparrow.roam + 0.01, "住みかの範囲にいる")

	# プレイヤーが近づくと逃げる
	bird.mode = "idle"
	bird.wait = 5.0
	var near: Vector2 = bird.pos + Vector2(1.0, 0)
	view._walk(bird, 0.02, near)
	_check(bird.mode == "flee", "近づくと小鳥が逃げる")
	_check(bird.target.distance_to(near) > bird.pos.distance_to(near), "プレイヤーから離れる向きに逃げる")
	_check(bird.target.distance_to(bird.from) > view.MOVES.sparrow.roam, "住みかの範囲より遠くまで逃げる(%.1fm)" % bird.target.distance_to(bird.from))
	# 土地の端では、向きを振って土地の中へ逃げる
	var edge_goal: Vector2 = view._flee_goal(Vector2(49, 0), Vector2.RIGHT, 12.0, bird)
	_check(wl.is_free(edge_goal) and edge_goal.distance_to(Vector2(48, 0)) > 3.0, "土地の端でも、外へ出ずに逃げる")
	var flap_max := 0.0
	for _i in range(10):
		view._walk(bird, 0.05, near)
		flap_max = maxf(flap_max, absf(bird.wings[0].rotation.z))
	_check(bird.node.position.y > 0.1, "小鳥は飛んで逃げる(高さ %.2f)" % bird.node.position.y)
	_check(flap_max > 0.3 and is_equal_approx(bird.wings[0].rotation.z, -bird.wings[1].rotation.z), "飛ぶときは左右の羽で羽ばたく(%.2f rad)" % flap_max)
	_check(bird.wings[0].rotation.y == 0.0, "飛ぶときは羽を広げる")
	var landed_at: Vector2 = bird.target
	for _i in range(100):
		if bird.mode != "flee":
			break
		view._walk(bird, 0.05, Vector2(500, 500))
	_check(bird.mode == "idle" and bird.node.position.y < 0.2, "逃げ終わると地面に降りる")
	_check(bird.pos == landed_at and bird.wait >= view.FLEE_REST_MIN, "逃げたあとはしばらくそこに留まる(%.1f 秒)" % bird.wait)
	# 羽の先が尾のほう(+z)を向いていれば、たためている
	var wing_tip: Vector3 = bird.wings[1].basis * Vector3.RIGHT
	var wing_tip_l: Vector3 = bird.wings[0].basis * Vector3.LEFT
	_check(wing_tip.z > 0.9 and wing_tip_l.z > 0.9, "降りると羽を背中へたたむ")

	# 虫はひらひら飛ぶ。住みかから離れすぎない
	var butterfly: Dictionary = view._animals.filter(func(a): return a.id == "butterfly")[0]
	var y_seen := []
	var far_seen := 0.0
	for _i in range(60):
		view._flutter(butterfly, 0.1)
		y_seen.append(butterfly.node.position.y)
		far_seen = maxf(far_seen, Vector2(butterfly.node.position.x, butterfly.node.position.z).distance_to(butterfly.home))
	_check(y_seen.min() > 0.3 and y_seen.max() < 1.5, "チョウは野菜の上を飛ぶ")
	_check(far_seen < view.FLUTTER_RADIUS * 1.3, "チョウは畑から離れすぎない(%.1fm)" % far_seen)

	# 夜になると入れかわる
	w.clock.fixed_now = MIDNIGHT
	view.sync_animals()
	_check(view.count("sparrow") == 0 and view.count("butterfly") == 0, "夜は小鳥もチョウもいなくなる")
	_check(view.count("hare") == wl.counts().hare and view.count("hedgehog") == wl.counts().hedgehog, "夜はノウサギとハリネズミが出る")
	var hedgehog: Dictionary = view._animals.filter(func(a): return a.id == "hedgehog")[0]
	hedgehog.mode = "walk"
	var stay: Vector2 = hedgehog.pos
	view._walk(hedgehog, 0.1, stay + Vector2(0.5, 0))
	_check(hedgehog.mode == "idle" and hedgehog.pos == stay, "ハリネズミは逃げず、じっとする")
	var hare: Dictionary = view._animals.filter(func(a): return a.id == "hare")[0]
	hare.mode = "idle"
	view._walk(hare, 0.05, hare.pos + Vector2(1, 0))
	view._walk(hare, 0.1, hare.pos + Vector2(1, 0))
	_check(hare.mode == "flee" and hare.node.position.y > 0.0, "ノウサギは跳ねて逃げる")
	w.clock.fixed_now = NOON

	# 渡り鳥の日は群れで、足元の近くに降りる
	f.today_event = "birds"
	player.global_position = Vector3(-30, 0, 30)
	view.sync_animals()
	var flock: Array = view._animals.filter(func(a): return a.id == "migrant")
	_check(flock.size() == wl.MIGRANT_FLOCK, "渡り鳥の発見の日は群れが見える(%d 羽)" % flock.size())
	_check(flock.all(func(a): return a.home == flock[0].home), "群れは同じ場所に降りる")
	_check(flock[0].home.distance_to(main.player_pos()) < 12.0, "足元の近くに降りる")
	f.today_event = "birch_seed"
	view.sync_animals()
	_check(view.count("migrant") == 0, "次の日にはいない")

	# はじめて来たら知らせる。ほかの知らせは消さない
	wl.seen.clear()
	hud.show_message("先の知らせ", 5.0)
	main.check_wildlife()
	_check(hud._message == "先の知らせ" and wl.seen.is_empty(), "ほかの知らせが出ているあいだは待つ")
	hud._process(10.0)
	main.check_wildlife()
	_check(hud._message.contains("来るようになった") and hud._message.contains("小鳥"), "はじめて来ると知らせる: %s" % hud._message)
	_check(main.creatures_line().contains("小鳥"), "持ち物に見かけた生き物が出る")
	hud._process(10.0)
	main.check_wildlife()
	_check(not hud.is_message_visible(), "二度は知らせない")

	# 元に戻す
	f.trees.assign(saved_trees)
	w.garden.crops.assign(saved_crops)
	w.land.plots.assign(saved_plots)
	w.clock.fixed_now = {}
	view.sync_animals()

func _test_work_motions() -> void:
	print("作業の動き")
	var w = main.world
	var f = w.forest
	var g = w.garden
	var player: CharacterBody3D = main.get_node("Player")
	var figure: Node3D = player.get_node("Body/Figure")
	var effects: Node3D = player.get_node("WorkEffects")
	var arm_r: Node3D = figure._arm_r
	var finish := func() -> void:
		figure._process(10.0)
		if player._effect_tween != null:
			player._effect_tween.kill()
	f.set_season("autumn")
	f.last_day = f.today()
	f.today_event = "birds"
	player.global_position = Vector3(-30, 0, -30)
	player.set_indoors(false)

	# 耕す: くわを持って振る
	finish.call()
	_check(not figure.is_acting() and figure.current_tool() == "", "はじめは何もしておらず、道具も持っていない")
	g.tilled_day = ""
	main._toggle_plot()
	_check(figure.current_action() == "dig" and figure.current_tool() == "hoe", "耕すと、くわを持つ")
	figure._process(0.28)  # 振りかぶったところ
	var raised: float = arm_r.rotation.x
	_check(raised > 1.0, "くわを振りかぶる(腕 %.2f rad)" % raised)
	figure._process(0.14)  # 振り下ろしたところ
	_check(arm_r.rotation.x < raised, "くわを振り下ろす(腕 %.2f rad)" % arm_r.rotation.x)
	player._effect_tween.custom_step(10.0)
	_check(effects.get_child_count() >= 7, "土が飛ぶ(%d 個)" % effects.get_child_count())
	figure._process(10.0)
	_check(not figure.is_acting() and figure.current_tool() == "", "終わると道具をしまう")
	figure._process(0.1)
	_check(absf(arm_r.rotation.x) < 0.01, "腕が元に戻る")

	# 種まき・水やり・収穫: 成功したときだけ動く
	var plot_pos: Vector2 = main.player_pos()
	g.seeds.radish = 1
	main.selected_crop = "radish"
	main._on_plant_tree(plot_pos)
	_check(figure.current_action() == "plant", "種をまくとかがむ")
	finish.call()
	main._water()
	_check(figure.current_action() == "water" and figure.current_tool() == "can", "水やりでじょうろを持つ")
	figure._process(0.5)
	var spout: Vector3 = figure.spout_pos()
	_check(spout.y > 0.3 and spout.y < 1.6 and Vector2(spout.x, spout.z).distance_to(plot_pos) > 0.2, "注ぎ口は体の前の高さにある(高さ %.2f)" % spout.y)
	var before_drop: int = effects.get_child_count()
	effects._drop()
	_check(effects.get_child_count() == before_drop + 1, "水の粒が落ちる")
	finish.call()
	main._water()
	_check(not figure.is_acting(), "今日もう水をあげた区画では動かない")
	var crop: Dictionary = g.crop_at(plot_pos)
	crop.sown_day -= 10
	main._harvest()
	_check(figure.current_action() == "pick" and g.crop_at(plot_pos).is_empty(), "収穫するとかがんで手を伸ばす")
	player._effect_tween.custom_step(10.0)  # 収穫の玉を飛ばす
	_check(effects._mats.has(load("res://view/3d/GardenView3D.gd").LOOKS.radish.ripe), "収穫物の色の玉が飛ぶ")
	finish.call()
	main._harvest()
	_check(not figure.is_acting(), "収穫するものがなければ動かない")

	# 実ったリンゴは手を上げて採る
	f.trees.append({"pos": Vector2(-31, -30), "species": "apple", "form": "sapling", "planted_at": f._now(), "start_age": 8.0, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	f.changed.emit()
	var apples: int = int(f.produce.apple)
	main._harvest()
	_check(figure.current_action() == "pick_high" and int(f.produce.apple) > apples, "リンゴは手を上げて採る")
	finish.call()
	f.trees.pop_back()
	f.changed.emit()

	# 作業の相手のほうを向く
	var body: Node3D = player.get_node("Body")
	body.rotation.y = 0.0
	player.act("water", Vector2(-25, -30))  # 東
	player._process(10.0)
	_check((-body.global_basis.z).dot(Vector3.RIGHT) > 0.99, "作業の相手のほうを向く")
	finish.call()
	player._face_yaw = null

	# 夜はランタンを置いて作業する
	player.set_night(1.0)
	_check(figure.holding_lantern, "夜はランタンを持っている")
	player.act("dig")
	_check(not figure.holding_lantern and not player.get_node("Body").find_child("Lantern", true, false).visible, "作業のあいだはランタンを持たない")
	figure._process(10.0)
	_check(figure.holding_lantern, "終わるとランタンを持つ")
	player.set_night(0.0)
	if player._effect_tween != null:
		player._effect_tween.kill()

	# 育った木を伐る: 斧を振って、反対側へ倒れる
	var tree_at := Vector2(-30, -27)
	f.trees.append({"pos": tree_at, "species": "birch", "form": "sapling", "planted_at": f._now(), "start_age": 30.0, "sprouts": true, "last_harvest": "", "last_watered": "", "bonus_years": 0.0})
	f.changed.emit()
	player.global_position = Vector3(-30, 0, -28.5)
	var trees_view: Node3D = main.get_node("Trees")
	main._remove()
	_check(not figure.is_acting(), "確認の 1 回目では動かない")
	var logs_before: int = int(w.cabin.materials.log)
	main._remove()
	_check(figure.current_action() == "chop" and figure.current_tool() == "axe", "伐ると斧を振る")
	_check(int(w.cabin.materials.log) > logs_before and f.nearest_index(tree_at, 0.5, "") < 0, "ルールの結果はすぐ入る(丸太が増え、木はなくなる)")
	var falling: Array = main.get_children().filter(func(n): return str(n.name).contains("FallingTree"))
	_check(not falling.is_empty(), "倒れる木の形ができる")
	var pivot: Node3D = falling[-1]  # 前のテストで倒した木も、まだ動いている途中で残っている
	_check(pivot.get_child_count() >= 2 and pivot.quaternion.is_equal_approx(Quaternion.IDENTITY), "はじめは立っている")
	trees_view.last_fall.custom_step(trees_view.FALL_WAIT + trees_view.FALL_SECONDS)
	var top: Vector3 = pivot.quaternion * Vector3.UP
	_check(top.z > 0.9 and absf(top.x) < 0.01, "足元の反対側(南)へ倒れる")
	trees_view.last_fall.custom_step(trees_view.FALL_FADE + 0.1)
	_check(pivot.is_queued_for_deletion(), "倒れたあと消える")
	finish.call()

	# 幹のない苗木は倒れず、抜く動きになる
	f.saplings.birch = 1
	main.selected_species = "birch"
	main.selected_form = "sapling"
	player.global_position = Vector3(-35, 0, -35)
	main._on_plant_tree(Vector2(-35, -35))
	finish.call()
	f.trees[-1].start_age = 0.1
	f.changed.emit()
	var count_before: int = main.get_child_count()
	main._remove()
	main._remove()
	_check(figure.current_action() == "pull", "幹のない苗木は抜く動きになる")
	_check(main.get_child_count() == count_before, "苗木は倒れない")
	finish.call()
	main.selected_form = "seed"

	# 寝ているあいだは動かない
	player.lie_down(Vector3(-35, 0.7, -35))
	player.act("dig")
	_check(not figure.is_acting(), "横になっているあいだは作業の動きをしない")
	player.get_up()
	player._pose.custom_step(10.0)

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
	player.get_node("Body/Figure")._process(10.0)  # 前の作業の動きを終わらせる(このテストは 1 フレームの中で進む)
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
	main._act("dig", Vector2(10, -5))  # 2D のプレイヤーには作業の動きがない
	_check(not main.get_node("Player").has_method("act"), "2D では作業の動きを呼ばない")
	main.check_wildlife()
	_check(main.world.wildlife.seen.is_empty(), "2D には生き物の姿がないので、来たと数えない")
	main.world.visitors.visit = {"day": main.world.forest.day_number(), "who": "nina", "kind": "chat", "done": false, "line": 0}
	main._talk()
	_check(main.visitor_line() == "" and not main.get_node("HUD").is_shop_open(), "2D には訪問者の姿がないので、話せない")
	main.world.visitors.visit = {}
	main._sfx("click")  # 2D には音がない
	_check(not main.get_node("Audio").has_method("play"), "2D では音を鳴らさない")
	main.world.guide.update(main.player_pos(), 10.0)
	main.get_node("HUD")._update_hint()
	_check(not main.world.guide.has_people, "2D では訪問者と生き物のヒントを出さない")
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
