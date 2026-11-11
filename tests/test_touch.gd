extends SceneTree

# タッチ操作のテスト。指の動きが、歩く・ボタン(キーの入力)・メニューになるか。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_touch.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる

const TouchText = preload("res://view/TouchText.gd")
const TEST_SAVE := "user://test_touch.json"
const VIEW := Vector2(866, 400)

var _failed := 0
var _passed := 0
var main
var tc
var player
var hud

func _initialize() -> void:
	_remove_save()
	main = load("res://Main.tscn").instantiate()
	main.world.save_path = TEST_SAVE
	root.add_child(main)
	_run.call_deferred()

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

func _frames(n := 3) -> void:
	for i in n:
		await process_frame

func _view() -> Vector2:
	return root.get_visible_rect().size

func _pad(id: String) -> Dictionary:
	for p in tc.pads(_view()):
		if p.id == id:
			return p
	return {}

func _center(id: String) -> Vector2:
	return (_pad(id).rect as Rect2).get_center()

# ボタンを押して離す(指の番号は 5 番: スティックの指と別)
func _tap(id: String) -> void:
	tc.touch(5, _center(id), true)
	tc.touch(5, Vector2.ZERO, false)
	await _frames()

func _run() -> void:
	await _frames()
	tc = main.get_node("TouchControls")
	player = main.get_node("Player")
	hud = main.get_node("HUD")
	_test_hidden_on_pc()
	_test_wording()
	_check(hud.status_text().contains("Tab:持ち物"), "PC ではキーの言い方のまま")
	tc.set_active(true)
	await _frames()
	await _test_wording_on_screen()
	tc.set_active(false)
	tc.set_active(true)
	await _frames()
	_check(main.get_node("Sun").directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL, "タッチでは太陽の影を分割しない(特に重いので)")
	_check(not player.get_node("Camera3D/Outline").visible, "タッチでは輪郭線を出さない(草の周りが黒い点になるので)")
	await _test_status_refresh()
	_test_layout()
	await _test_stick()
	await _test_buttons()
	await _test_walk_and_press()
	await _test_menu()
	await _test_context_pads()
	await _test_shop_and_diary()
	await _test_keyboard_hides()
	main.queue_free()
	_remove_save()
	await _frames()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _test_hidden_on_pc() -> void:
	print("PC では出ない")
	_check(not tc.active and tc.pads(VIEW).is_empty(), "タッチ画面がなければボタンを出さない")
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED, "画面の拡大もしない")
	_check(not hud.touch_mode, "市場の行の高さも変えない")

# キーボードの言い方がボタンの名前に変わる
func _test_wording() -> void:
	print("タッチの文言")
	var cases := {
		"WASD か矢印キーで歩ける。\nホイールでカメラを寄せたり引いたりできる。": "左のスティックで歩ける。\n「寄る」「引く」でカメラを動かせる。",
		"小屋: H で足元に場所を決める": "小屋: 「小屋」で足元に場所を決める",
		"ストーブの前(H で料理)": "ストーブの前(「使う」で料理)",
		"薪がない(小屋の東の薪割り台で、H で丸太を割る)": "薪がない(小屋の東の薪割り台で、「使う」で丸太を割る)",
		"区画の上で SPACE を押すと種をまく。": "区画の上で「植える」を押すと種をまく。",
		"F で足元に畑の区画を作れる。": "メニューの「菜園」で足元に畑の区画を作れる。",
		"U を押したまま歩くと、雪をどかせる。": "「雪かき」を押したまま歩くと、雪をどかせる。",
		"閉じる(B / Esc)": "閉じる",
		"市場(クリックか 矢印キー + Enter で選ぶ)": "市場(押して選ぶ)",
		"H / Esc / Enter で起きる": "「起きる」を押す",
		"[1][2][3] で木を選び、[V] で種と苗木を切り替える。": "メニューで木を選び、メニューで種と苗木を切り替える。",
		"苗にできるのはトマト [9] と きゅうり [6]": "苗にできるのはトマト と きゅうり",
		"見かけた生き物は、Tab の持ち物で見られる。": "見かけた生き物は、メニューの持ち物で見られる。",
		"1本 × 15₽(E で売る)": "1本 × 15₽(「収穫」で売る)",
	}
	for raw in cases:
		_check(TouchText.convert(raw) == cases[raw], "%s → %s" % [raw.replace("\n", " "), TouchText.convert(raw).replace("\n", " ")])
	_check(TouchText.convert("OK で進む 10m を歩く") == "OK で進む 10m を歩く", "キーの名前でない英数字は変えない")
	# ゲームのすべての文字列で、キーボードの言い方が残らない
	var leftover := PackedStringArray()
	var strings := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	var keyboard := RegEx.create_from_string("WASD|矢印|ホイール|クリック|Enter|Esc|Tab|F1|SPACE|\\[[0-9A-Z]\\]|(?<![A-Za-z0-9])[A-Z] (で|を)")
	for path in ["res://Main.gd", "res://HUD.gd"]:
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if line.strip_edges().begins_with("#") or line.contains("func _help_lines") or line.contains("Tab:%s") or line.contains("group_keys_text(\"broadleaf\")") or line.contains("var keys := [\"[4]\""):
				continue
			for m in strings.search_all(line):
				var shown: String = TouchText.convert(m.get_string(1).replace("\\n", "\n"))
				if keyboard.search(shown) != null and not _is_pc_help(m.get_string(1)):
					leftover.append(shown)
	_check(leftover.is_empty(), "全部の文字列でキーボードの言い方が残らない(残り %d: %s)" % [leftover.size(), " / ".join(leftover.slice(0, 5))])

# PC の操作説明(F1)の行。タッチでは別の説明を出すので対象外
func _is_pc_help(text: String) -> bool:
	for line in hud._help_lines():
		if line == text:
			return true
	return false

# 実際に画面の文字が置き換わる
func _test_wording_on_screen() -> void:
	_check(hud.status_text().contains("持ち物と操作はメニューから") and not hud.status_text().contains("Tab:"), "左上の文字がタッチの言い方になる")
	_check(hud.status_text().contains("「小屋」で足元に"), "左上の案内がボタンの名前になる")
	hud.help_open = true
	_check(hud.status_text().contains("左のスティック") and not hud.status_text().contains("WASD"), "操作説明がタッチのものになる")
	hud.help_open = false
	hud.show_message("もう一度 Z で伐る")
	_check(hud._message_label.text == "もう一度「抜く」で伐る", "メッセージがボタンの名前になる")
	await create_timer(hud.TOUCH_STATUS_SECONDS + 0.1).timeout
	_check(hud._hint_label.text == "" or hud._hint_label.text.contains("「ヒント」で閉じる"), "ヒントの閉じ方がボタンの名前になる")
	hud._hint_label.text = "ヒント\n" + TouchText.convert("F で足元に畑の区画を作れる。お金はいらない。")
	await process_frame
	await process_frame
	_check(hud._hint_label.autowrap_mode != TextServer.AUTOWRAP_OFF and hud._hint_label.size.x <= hud.TOUCH_HINT_WIDTH + 1.0, "長いヒントは折り返して幅を広げない(%.0f)" % hud._hint_label.size.x)
	var names := []
	for p in tc.pads(_view()):
		names.append(p.sub)
	_check(names.count("") >= names.size() - 1, "ボタンにキーの名前を出さない")

# 左上の文字は間引いて更新するが、変わったら少し待つと出る
func _test_status_refresh() -> void:
	print("左上の文字の更新")
	var money: int = main.world.market.money
	main.world.market.money = money + 123
	await create_timer(hud.TOUCH_STATUS_SECONDS + 0.1).timeout
	_check(hud._label.text.contains(hud._money_text(money + 123)), "所持金が変わると、間もなく表示も変わる")
	main.world.market.money = money
	await create_timer(tc.REFRESH_SECONDS + 0.1).timeout
	_check(tc._last_signature != "", "ボタンの変化を調べている")

func _test_layout() -> void:
	print("並び")
	# 小さいスマホの横向き(論理サイズ)で、ボタンが画面に収まり、重ならない
	for size in [Vector2(866, 400), Vector2(700, 400)]:
		var inside := true
		var apart := true
		tc.menu_open = false
		for round_ in range(2):
			var list: Array = tc.pads(size)
			for i in range(list.size()):
				inside = inside and Rect2(Vector2.ZERO, size).encloses(list[i].rect)
				for j in range(i + 1, list.size()):
					apart = apart and not list[i].rect.intersects(list[j].rect)
			tc.menu_open = true
		tc.menu_open = false
		_check(inside, "%dx%d: ボタンが画面に収まる" % [size.x, size.y])
		_check(apart, "%dx%d: ボタンが重ならない" % [size.x, size.y])
	_check(tc.pads(Vector2(400, 866)).is_empty(), "縦向きではボタンを出さない(横向きの案内を出す)")
	_check(_pad("plant").rect.size.y >= 44.0, "ボタンは指で押せる大きさ")

func _test_stick() -> void:
	print("スティックで歩く")
	var view := _view()
	var start: Vector3 = player.position
	var at := Vector2(100, view.y - 100)
	_check(tc.touch(0, at, true), "画面の左を触るとスティックが出る")
	_check(tc.stick_value() == Vector2.ZERO, "触っただけでは歩かない")
	tc.drag(0, at + Vector2(3, 0))
	_check(player.move_input == Vector2.ZERO, "少し動かしただけでは歩かない")
	tc.drag(0, at + Vector2(0, -tc.STICK_RADIUS))
	_check(player.move_input.y < -0.99 and absf(player.move_input.x) < 0.01, "上へ倒すと北へ、半径いっぱいで全速")
	await physics_frame
	await physics_frame
	await _frames()
	_check(player.position.z < start.z, "北へ歩く(z が減る)")
	tc.drag(0, at + Vector2(tc.STICK_RADIUS * 0.5, -tc.STICK_RADIUS))
	_check(player.move_input.length() >= 0.99 and player.move_input.x > 0.0, "半径の外でも速さは全速まで")
	tc.touch(0, Vector2.ZERO, false)
	_check(player.move_input == Vector2.ZERO, "離すと止まる")
	var right := Vector2(view.x * 0.6, view.y * 0.5)
	_check(not tc.touch(0, right, true) and tc.stick_value() == Vector2.ZERO, "画面の右の何もないところでは歩かない")
	tc.touch(0, Vector2.ZERO, false)

func _test_buttons() -> void:
	print("ボタンはキーの入力と同じ")
	var f = main.world.forest
	f.seeds.birch = 4
	main.selected_species = "birch"
	main.selected_form = "seed"
	var trees: int = f.trees.size()
	await _tap("plant")
	_check(f.trees.size() == trees + 1, "植えるボタンで足元に植わる")
	_check(tc.active, "自分で送ったキーでは、タッチ操作を消さない")
	var dist: float = player.view_distance()
	await _tap("zoom_in")
	_check(player.view_distance() < dist, "寄るボタンでカメラが寄る")
	await _tap("zoom_out")
	_check(is_equal_approx(player.view_distance(), dist), "引くボタンで戻る")

func _test_walk_and_press() -> void:
	print("歩きながら押す")
	var view := _view()
	var at := Vector2(100, view.y - 100)
	tc.touch(0, at, true)
	tc.drag(0, at + Vector2(0, tc.STICK_RADIUS))
	var moving: Vector2 = player.move_input
	var dist: float = player.view_distance()
	tc.touch(1, _center("zoom_in"), true)
	_check(player.view_distance() < dist and player.move_input == moving, "別の指でボタンを押しても歩き続ける")
	tc.touch(1, Vector2.ZERO, false)
	_check(player.move_input == moving, "ボタンを離しても歩き続ける")
	tc.touch(0, Vector2.ZERO, false)
	_check(player.move_input == Vector2.ZERO, "スティックの指を離すと止まる")
	# 雪かきのボタンは押しているあいだだけ(冬のボタンなので、直接送って確かめる)
	var hold := {"id": "shovel", "key": KEY_U, "hold": true, "keep": false}
	tc._held[2] = hold
	tc._press(hold)
	await _frames()
	_check(Input.is_key_pressed(KEY_U), "雪かきのボタンは押しているあいだキーが入ったまま")
	tc.touch(2, Vector2.ZERO, false)
	await _frames()
	_check(not Input.is_key_pressed(KEY_U), "離すとキーも離れる")
	tc._held[2] = hold
	tc._press(hold)
	await _frames()
	tc.release_all()
	await _frames()
	_check(not Input.is_key_pressed(KEY_U) and tc._held.is_empty(), "別のアプリへ移ったら押しっぱなしにしない")

func _test_menu() -> void:
	print("メニュー")
	var ids := []
	await _tap("menu")
	_check(tc.menu_open and _pad("plant").is_empty(), "メニューを開くと、いつものボタンは隠れる")
	for p in tc.pads(_view()):
		ids.append(p.id)
	_check(ids.size() == 25, "メニューに 24 の操作と閉じるボタンがある(%d)" % ids.size())
	_check(not tc.touch(0, Vector2(100, 100), true) and tc.stick_value() == Vector2.ZERO, "メニューのあいだは歩かない")
	tc.touch(0, Vector2.ZERO, false)
	await _tap("cedar")
	_check(main.selected_species == "cedar" and tc.menu_open, "木を選んでも開いたまま")
	_check(_pad("cedar").on and not _pad("birch").on, "選んでいるものは色が変わる")
	main.selected_crop = "radish"
	await _tap("crop_root")
	_check(main.selected_crop == "carrot" and _pad("crop_root").on and _pad("crop_root").text == "にんじん", "野菜を選べる(ラディッシュのとき根菜を押すと にんじん)")
	await _tap("form")
	_check(main.selected_form == "sapling" and _pad("form").text == "苗木で植える", "種と苗木を切り替えられて、文字も変わる")
	await _tap("form")
	var open_before: bool = hud.inventory_open
	await _tap("items")
	_check(hud.inventory_open != open_before and not tc.menu_open, "持ち物を開くと、読めるようにメニューは閉じる")
	await _tap("menu")
	await _tap("items")
	_check(hud.inventory_open == open_before, "もう一度押すと閉じる")
	await _tap("menu")
	await _tap("menu_close")
	_check(not tc.menu_open and not _pad("plant").is_empty(), "閉じるボタンで元に戻る")

func _test_context_pads() -> void:
	print("近くにあるものでボタンが増える")
	_check(_pad("market").is_empty(), "市場から遠いと市場のボタンはない")
	player.global_position = Vector3(main.world.market.POS.x, 0, main.world.market.POS.y)
	await _frames()
	_check(not _pad("market").is_empty(), "市場の前で市場のボタンが出る")
	_check(_pad("cabin").text == "小屋", "ふだんは小屋のボタン")
	player.global_position = Vector3.ZERO
	await _frames()

func _test_shop_and_diary() -> void:
	print("市場と日記")
	player.global_position = Vector3(main.world.market.POS.x, 0, main.world.market.POS.y)
	await _frames()
	await _tap("market")
	_check(hud.is_shop_open(), "市場のボタンで開く")
	_check(tc.pads(_view()).is_empty(), "市場のあいだはボタンを隠す(画面のボタンを押す)")
	_check(not tc.touch(0, Vector2(100, 200), true) and tc.stick_value() == Vector2.ZERO, "市場のあいだは歩かない")
	tc.touch(0, Vector2.ZERO, false)
	var heights := []
	for b in hud._shop_columns[0].get_children():
		heights.append(b.custom_minimum_size.y)
	_check(heights.size() > 0 and heights.min() >= 24.0, "市場の行は指で押せる高さ(%.0f)" % heights.min())
	await process_frame
	_check(hud._shop.get_global_rect().size.y <= _view().y, "市場の画面が画面に収まる")
	_check(not hud._label.visible and not hud._bg.visible, "市場のあいだは左の文字を隠す(重なって読めないので)")
	main._close_shop()
	await _frames()
	_check(not tc.pads(_view()).is_empty(), "閉じるとボタンが戻る")
	_check(hud._label.visible and hud._bg.visible, "閉じると左の文字が戻る")
	player.global_position = Vector3.ZERO
	await _frames()
	hud.open_diary("テスト")
	await _frames()
	_check(tc.pads(_view()).size() == 1 and tc.pads(_view())[0].id == "wake", "日記のあいだは起きるボタンだけ")
	_check(not tc.touch(0, Vector2(100, 200), true) and tc.stick_value() == Vector2.ZERO, "日記のあいだは歩かない")
	tc.touch(0, Vector2.ZERO, false)
	await _tap("wake")
	_check(not hud.is_diary_open(), "起きるボタンで日記を閉じる")

func _test_keyboard_hides() -> void:
	print("キーボード")
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames()
	var up := InputEventKey.new()
	up.keycode = KEY_W
	Input.parse_input_event(up)
	await _frames()
	_check(not tc.active and tc.pads(VIEW).is_empty(), "物理キーを押すとタッチ操作は消える")
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED, "画面の拡大も元に戻る")
	_check(root.msaa_3d == ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d"), "縁のなめらかさも PC の設定に戻る")
	_check(main.get_node("Sun").directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "太陽の影も PC の設定に戻る")
	_check(player.get_node("Camera3D/Outline").visible, "輪郭線も PC の設定に戻る")
	tc.touch(0, Vector2(100, 200), true)
	tc.touch(0, Vector2.ZERO, false)
	_check(tc.active, "また触るとタッチ操作が出る")
