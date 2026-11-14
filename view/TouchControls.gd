extends CanvasLayer

# ── タッチ操作 ───────────────────────────────────────────────
# 左: 触った場所に出るスティックで歩く。右下: よく使う作業のボタン。ほかの操作はメニューに並べる。
# ボタンはキーの入力を送るだけで、何が起きるかは Main が決める(キーボードと同じ処理を通る)。
# 文言はタッチのときボタンの名前に置き換わる(view/TouchText.gd)。
# Godot の Button は最初の指にしか反応せず、歩きながら押せないので、指ごとの当たり判定をここで持つ。
# タッチ画面のときだけ出し、物理キーを押すと消す(PC 版の見た目と操作は変えない)
const STICK_RADIUS := 56.0
const STICK_DEADZONE := 0.12  # スティックの半径に対する割合。これより動かしても歩かない
const STICK_AREA := 0.4       # 画面の左からこの割合までを触ると、スティックが出る
const STICK_REST_INSET := 92.0  # 触っていないときにスティックの目印を出す場所(左下の角から)
const MIN_VIEW_HEIGHT := 400  # 画面の高さをこれ以上の論理サイズで扱う(スマホで文字が小さくなりすぎないように)
const MAX_3D_HEIGHT := 480.0  # 3D はこの高さまでで描く(高解像度のスマホでも重くしない。文字はくっきりしたまま)
const SHADOW_ATLAS_SIZE := 2048  # 太陽の影のテクスチャの大きさ
const REFRESH_SECONDS := 0.25    # 出すボタンが変わったかを確かめる間隔(毎フレーム調べると、遅いスマホでは重い)
const ZOOM_STEP := 0.85       # ホイール 1 目盛りと同じ
const PAD_SIZE := Vector2(72, 56)
const MENU_PAD_SIZE := Vector2(112, 52)
const GAP := 6.0
const MARGIN := 8.0

# メニューの並び。[id, 文字, キー, 押したあともメニューを開いておくか]
const MENU := [
	[
		["plot", "菜園", KEY_F, false], ["pond", "池", KEY_P, false], ["hive", "巣箱", KEY_J, false],
		["feeder", "餌台", KEY_L, false], ["prune", "剪定", KEY_X, false], ["talk_menu", "話す", KEY_C, false],
		["market_menu", "市場", KEY_B, false],
	],
	[
		["birch", "白樺", KEY_1, true], ["fruit", "果樹", KEY_2, true], ["cedar", "シベリア杉", KEY_3, true],
		["form", "種/苗木", KEY_V, true], ["well", "井戸", KEY_I, false],
	],
	[
		["crop_root", "根菜", KEY_4, true], ["crop_imo", "いも", KEY_5, true], ["crop_fruit", "実もの", KEY_6, true],
		["crop_leaf", "葉もの", KEY_7, true], ["crop_bean", "豆・穀物", KEY_8, true], ["crop_aroma", "香味", KEY_9, true],
	],
	[
		["items", "持ち物", KEY_TAB, false], ["help", "操作", KEY_F1, false], ["sound", "音量", KEY_M, true],
		["year1", "+1年", KEY_T, true], ["year10", "+10年", KEY_G, true], ["hour1", "+1時間", KEY_N, true],
		["now", "今に戻す", KEY_R, true],
	],
]

var active := false
var menu_open := false
var _main: Node
var _player: Node
var _hud: Node
var _canvas: Control
var _held := {}            # 指の番号 → 押しているボタン
var _stick_finger := -1    # スティックを動かしている指。いなければ -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _dirty := true           # 描き直しが要る
var _refresh_timer := 0.0
var _last_signature := ""
var _pad_style := StyleBoxFlat.new()
var _on_style := StyleBoxFlat.new()
var _down_style := StyleBoxFlat.new()

func setup(main: Node, player: Node, hud: Node) -> void:
	_main = main
	_player = player
	_hud = hud
	layer = 5  # 日記(HUD)より手前。日記を閉じるボタンを出すので
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)
	_pad_style = _style(Color(0.08, 0.10, 0.08, 0.62), Color(1, 1, 1, 0.30))
	_on_style = _style(Color(0.20, 0.30, 0.18, 0.92), Color(0.96, 0.84, 0.46))
	_down_style = _style(Color(0.96, 0.84, 0.46, 0.75), Color(0.96, 0.84, 0.46))
	get_window().size_changed.connect(_apply_scale)
	set_active(DisplayServer.is_touchscreen_available())


static func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	return s

func set_active(on: bool) -> void:
	active = on
	_canvas.visible = on
	_hud.touch_mode = on
	if not on:
		release_all()
		menu_open = false
	_apply_scale()

# タッチのときは画面を拡大して文字を読める大きさにする。スマホの GPU に合わせて、3D は上限の高さまでで描き、
# 縁のなめらかさ(MSAA)と影の柔らかさを落として軽くする。PC に戻ったらプロジェクトの設定に戻す
func _apply_scale() -> void:
	var win := get_window()
	_dirty = true
	var sun: DirectionalLight3D = _player.shadow_light
	var outline: Node3D = _player.get_node("Camera3D/Outline")
	if not active:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		win.scaling_3d_scale = 1.0
		win.msaa_3d = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d")
		RenderingServer.directional_soft_shadow_filter_set_quality(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"))
		RenderingServer.directional_shadow_atlas_set_size(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"), true)
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		outline.visible = true
		return
	win.msaa_3d = Viewport.MSAA_DISABLED
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS_SIZE, true)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL  # 影を分割すると、世界全体を分割の数だけ描き直して特に重い
	outline.visible = false  # 低い解像度では草の周りが黒い点になり、切ると少し軽くもなる
	var short_side: int = mini(win.size.x, win.size.y)
	var side := maxi(MIN_VIEW_HEIGHT, roundi(short_side / DisplayServer.screen_get_scale()))
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = Vector2i(side, side)
	win.scaling_3d_scale = minf(1.0, MAX_3D_HEIGHT / maxf(short_side, 1.0))

func is_portrait(view: Vector2) -> bool:
	return view.y > view.x

# ── 今出すボタン ─────────────────────────────────────────────
func _view() -> Vector2:
	return get_viewport().get_visible_rect().size

# 開いている画面と近くにあるものに合わせて、今出すボタンを返す
func pads(view: Vector2) -> Array:
	if not active or is_portrait(view) or _hud.is_shop_open() or _hud.is_picker_open():  # 市場などの画面には閉じるボタンがある
		return []
	if _hud.is_diary_open():
		var size := Vector2(160, 56)
		return [_pad("wake", "起きる", KEY_H, Rect2(Vector2((view.x - size.x) * 0.5, view.y - size.y - 24.0), size))]
	return _menu_pads(view) if menu_open else _main_pads(view)

func _pad(id: String, text: String, key: int, rect: Rect2, keep := false, hold := false, sub := "") -> Dictionary:
	return {"id": id, "text": text, "sub": sub, "key": key, "rect": rect, "keep": keep, "hold": hold, "on": _is_selected(id)}

func _main_pads(view: Vector2) -> Array:
	var c := func(col: int, row: int) -> Rect2:  # 右下から数えた場所
		return Rect2(view - Vector2(MARGIN, MARGIN) - PAD_SIZE - Vector2(col, row) * (PAD_SIZE + Vector2(GAP, GAP)), PAD_SIZE)
	var list := [
		_pad("plant", "植える", KEY_SPACE, c.call(0, 0)),
		_pad("harvest", "収穫", KEY_E, c.call(1, 0)),
		_pad("remove", "抜く", KEY_Z, c.call(2, 0)),
		_pad("menu", "メニュー", KEY_NONE, c.call(0, 1)),
		_pad("water", "水やり", KEY_Q, c.call(1, 1)),
		_pad("cabin", _cabin_text(), KEY_H, c.call(2, 1)),
		_pad("zoom_out", "引く", KEY_NONE, c.call(0, 3)),
		_pad("zoom_in", "寄る", KEY_NONE, c.call(1, 3)),
	]
	if _main.hint_text() != "":
		list.append(_pad("hint", "ヒント", KEY_K, c.call(2, 3), false, false, "閉じる"))
	# 近くにあるものや季節で増えるボタンは、よく使う列の上に右から並べる
	var col := 0
	if _main.world.market.is_near(_main.player_pos()):
		list.append(_pad("market", "市場", KEY_B, c.call(col, 2)))
		col += 1
	if _main.visitor_line() != "":
		list.append(_pad("talk", "話す", KEY_C, c.call(col, 2)))
		col += 1
	if _main.world.snow.can_clear_now():
		list.append(_pad("shovel", "雪かき", KEY_U, c.call(col, 2), false, true))
	return list

func _cabin_text() -> String:
	return "使う" if _main.furniture_line() != "" else "小屋"

func _menu_pads(view: Vector2) -> Array:
	var list := []
	var columns: int = MENU[0].size()
	# 幅の狭いスマホでは、画面に収まるようにボタンの幅を縮める
	var pad_size := Vector2(minf(MENU_PAD_SIZE.x, (view.x - MARGIN * 2.0 - GAP * (columns - 1)) / columns), MENU_PAD_SIZE.y)
	var step := pad_size + Vector2(GAP, GAP)
	var width: float = columns * step.x - GAP
	var left: float = (view.x - width) * 0.5
	var top: float = view.y - MARGIN - MENU.size() * step.y + GAP
	for r in range(MENU.size()):
		for i in range(MENU[r].size()):
			var m: Array = MENU[r][i]
			var rect := Rect2(Vector2(left, top) + Vector2(i, r) * step, pad_size)
			list.append(_pad(m[0], _menu_text(m[0], m[1]), m[2], rect, m[3]))
	# 2 行目の右の空きに閉じるボタン
	var close_rect := Rect2(Vector2(left, top) + Vector2(columns - 1, 1) * step, pad_size)
	list.append(_pad("menu_close", "閉じる", KEY_NONE, close_rect))
	return list

# 木のボタン(id は今までのまま birch = 広葉樹・cedar = 針葉樹)が受け持つ組
const TREE_GROUPS := {"birch": "broadleaf", "fruit": "fruit", "cedar": "conifer"}

func _menu_text(id: String, text: String) -> String:
	if id == "form":
		return "苗木で植える" if _main.selected_form == "sapling" else "種で植える"
	if id.begins_with("crop_"):
		# 選んでいる野菜、なければその組でこの土地で最初に育つ野菜の名前
		var g = _main.world.garden
		if _is_selected(id):
			return g.CROPS[_main.selected_crop].name
		var crops: Array = g.crops_in(id.trim_prefix("crop_"))
		return g.CROPS[crops[0]].name if not crops.is_empty() else text
	if id == "birch" or id == "cedar":
		# 選んでいる木、なければその土地で最初に育つ木の名前(県を選ぶ前は 白樺・シベリア杉)
		var f = _main.world.forest
		if _is_selected(id):
			return f.SPECIES[_main.selected_species].name
		var list: Array = f.plantable_in(TREE_GROUPS[id])
		return f.SPECIES[list[0]].name if not list.is_empty() else text
	return text

# メニューで今選ばれているものは色を変える
func _is_selected(id: String) -> bool:
	match id:
		"birch", "cedar", "fruit":
			var f = _main.world.forest
			return f.SPECIES.has(_main.selected_species) and f.SPECIES[_main.selected_species].group == TREE_GROUPS[id]
		"crop_root", "crop_imo", "crop_fruit", "crop_leaf", "crop_bean", "crop_aroma":
			return _main.world.garden.CROPS[_main.selected_crop].group == id.trim_prefix("crop_")
	return false

func _pad_at(pos: Vector2) -> Dictionary:
	for p in pads(_view()):
		if p.rect.has_point(pos):
			return p
	return {}

# ── 指の動き ─────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		# 自分で送ったキーは device が DEVICE_ID_EMULATION。物理キーが押されたら PC として遊んでいる
		if active and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
			set_active(false)
	elif event is InputEventScreenTouch:
		if touch(event.index, event.position, event.pressed):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if drag(event.index, event.position):
			get_viewport().set_input_as_handled()

# 指が触れた / 離れた。この操作で受け取ったら true(後ろの画面には渡さない)
func touch(finger: int, pos: Vector2, pressed: bool) -> bool:
	_dirty = true
	if not pressed:
		return _lift(finger)
	if not active:
		set_active(true)
	var pad := _pad_at(pos)
	if not pad.is_empty():
		_held[finger] = pad
		_press(pad)
		return true
	var view := _view()
	if _can_walk(view) and _stick_finger < 0 and pos.x < view.x * STICK_AREA:
		_stick_finger = finger
		_stick_origin = pos
		_stick_pos = pos
		return true
	return false

func _can_walk(view: Vector2) -> bool:
	return active and not menu_open and not is_portrait(view) and not _hud.is_shop_open() and not _hud.is_diary_open() and not _hud.is_picker_open()

func drag(finger: int, pos: Vector2) -> bool:
	if finger != _stick_finger:
		return _held.has(finger)
	_dirty = true
	# 半径より外へ動かしたら、スティックの中心もついてくる(逆へ向き直しやすいように)
	var offset := pos - _stick_origin
	if offset.length() > STICK_RADIUS:
		_stick_origin = pos - offset.normalized() * STICK_RADIUS
	_stick_pos = pos
	_player.move_input = stick_value()
	return true

# スティックの傾き(長さ 0〜1)。上 = 北 = -y
func stick_value() -> Vector2:
	if _stick_finger < 0:
		return Vector2.ZERO
	var v := (_stick_pos - _stick_origin) / STICK_RADIUS
	var length := v.length()
	if length < STICK_DEADZONE:
		return Vector2.ZERO
	return v.normalized() * minf(1.0, (length - STICK_DEADZONE) / (1.0 - STICK_DEADZONE))

func _lift(finger: int) -> bool:
	_dirty = true
	if finger == _stick_finger:
		_stick_finger = -1
		_player.move_input = Vector2.ZERO
		return true
	if not _held.has(finger):
		return false
	var pad: Dictionary = _held[finger]
	_held.erase(finger)
	if pad.hold:
		_send_key(pad.key, false)
	return true

# 指が離れたことを受け取れないとき(別のアプリへ移ったなど)に、押しっぱなしにしない
func release_all() -> void:
	for finger in _held.keys():
		_lift(finger)
	if _stick_finger >= 0:
		_lift(_stick_finger)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_all()

func _press(pad: Dictionary) -> void:
	match pad.id:
		"menu":
			menu_open = true
			if _stick_finger >= 0:
				_lift(_stick_finger)  # メニューを開いているあいだは歩かない
		"menu_close":
			menu_open = false
		"zoom_in":
			_player.zoom(ZOOM_STEP)
		"zoom_out":
			_player.zoom(1.0 / ZOOM_STEP)
		_:
			if menu_open and not pad.keep:
				menu_open = false
			_send_key(pad.key, true)
			if not pad.hold:
				_send_key(pad.key, false)

func _send_key(key: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key as Key
	ev.physical_keycode = key as Key
	ev.pressed = pressed
	ev.device = InputEvent.DEVICE_ID_EMULATION
	Input.parse_input_event(ev)

# ── 描く ─────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if not active:
		return
	# 指が動いたときと、出すボタンが変わったときだけ描き直す
	_refresh_timer += _delta
	if _refresh_timer >= REFRESH_SECONDS:
		_refresh_timer = 0.0
		var signature := _pad_signature()
		if signature != _last_signature:
			_last_signature = signature
			_dirty = true
	if _dirty:
		_dirty = false
		_canvas.queue_redraw()

func _pad_signature() -> String:
	var parts := PackedStringArray()
	for p in pads(_view()):
		parts.append("%s:%s:%s" % [p.id, p.text, p.on])
	return ",".join(parts)

func _draw_controls() -> void:
	var view := _view()
	var font: Font = _canvas.get_theme_default_font()
	if is_portrait(view):
		_canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0.03, 0.03, 0.07, 0.9))
		_canvas.draw_string(font, Vector2(0, view.y * 0.5), "スマホを横向きにしてください", HORIZONTAL_ALIGNMENT_CENTER, view.x, 18)
		return
	if menu_open:
		var box := Rect2(0, view.y - MARGIN - MENU.size() * (MENU_PAD_SIZE.y + GAP) - GAP, view.x, view.y)
		_canvas.draw_rect(box, Color(0, 0, 0, 0.45))
	var held_ids := []
	for pad in _held.values():
		held_ids.append(pad.id)
	for p in pads(view):
		_draw_pad(p, font, p.id in held_ids)
	if _can_walk(view):
		_draw_stick(view)

func _draw_pad(p: Dictionary, font: Font, down: bool) -> void:
	var style := _down_style if down else (_on_style if p.on else _pad_style)
	_canvas.draw_style_box(style, p.rect)
	var has_sub: bool = p.sub != ""
	var mid: float = p.rect.position.y + p.rect.size.y * (0.44 if has_sub else 0.58)
	_canvas.draw_string(font, Vector2(p.rect.position.x, mid), p.text, HORIZONTAL_ALIGNMENT_CENTER, p.rect.size.x, 14)
	if has_sub:
		var sub_y: float = p.rect.position.y + p.rect.size.y - 10.0
		_canvas.draw_string(font, Vector2(p.rect.position.x, sub_y), p.sub, HORIZONTAL_ALIGNMENT_CENTER, p.rect.size.x, 12, Color(1, 1, 1, 0.75))

func _draw_stick(view: Vector2) -> void:
	var touching := _stick_finger >= 0
	var center := _stick_origin if touching else Vector2(STICK_REST_INSET, view.y - STICK_REST_INSET)
	_canvas.draw_circle(center, STICK_RADIUS, Color(0.08, 0.10, 0.08, 0.40 if touching else 0.22))
	_canvas.draw_arc(center, STICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.45 if touching else 0.25), 2.0, true)
	var knob := _stick_pos if touching else center
	_canvas.draw_circle(knob, 24.0, Color(1, 1, 1, 0.55 if touching else 0.25))
