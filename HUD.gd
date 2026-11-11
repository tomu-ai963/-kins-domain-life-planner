extends CanvasLayer

# ── 画面の文字表示(2D と 3D で共通) ─────────────────────────────
# 左上: いつも見たいこと(日付・所持金・発見・クエスト・小屋・池・選択・足元)。
# Tab で持ち物(市場を開いているあいだは自動で出す)、F1 で操作説明を足す。
# 下の中央: 数秒だけのメッセージ。右: 市場の画面(ストーブでも同じ画面を使う)。
# 右上: ヒント(logic/Guide.gd)。市場の画面や日記を開いているあいだは隠す。
# 全体を覆う日記: ベッドで休むと、暗くなって出る。
# 文言の中身は Main が決める(shop_rows・quest_line など)。ここは並べて出すだけ
const Forest = preload("res://logic/Forest.gd")
const TouchText = preload("res://view/TouchText.gd")
const RegionPicker = preload("res://view/RegionPicker.gd")
const MESSAGE_SECONDS := 3.0
const DIARY_FADE_SECONDS := 0.6
const TOUCH_STATUS_SECONDS := 0.25  # タッチのときに左上の文字を更新する間隔
const TOUCH_HINT_WIDTH := 280.0   # タッチのときのヒントの文字の幅
const TOUCH_ROW_HEIGHT := 38.0    # タッチのときの市場の行の高さ
const SHOP_HEADER_HEIGHT := 70.0  # 市場の画面の見出しと余白
const SHOP_ROW_GAP := 4.0         # 行のあいだ(VBoxContainer の既定)

signal shop_action(id)  # 市場の画面のボタン(品の id / "sell_<収穫物>" / "close")
signal region_chosen(id)  # 土地のある都道府県を決めた(view/RegionPicker.gd)

@onready var _label: Label = $PositionLabel
@onready var _bg: ColorRect = $BG

var _player: Node
var _trees: Forest
var _main: Node

var _message := ""
var _message_timer := 0.0
var _message_panel: PanelContainer
var _message_label: Label
var inventory_open := false  # Tab
var help_open := false       # F1
var touch_mode := false      # タッチ操作のとき(市場の画面のボタンを指で押せる大きさにする)
var _status_timer := 0.0
var _shop: PanelContainer
var _shop_columns := []  # 買う列と売る列(VBoxContainer)
var _shop_money: Label
var _shop_title: Label
var _diary: ColorRect
var _diary_label: Label
var _diary_fade: Tween
var _hint_panel: PanelContainer
var _hint_label: Label
var picker: RegionPicker  # 都道府県を選ぶ画面(ゲームのはじめに一度だけ)

func setup(player: Node, trees: Forest, main: Node) -> void:
	_player = player
	_trees = trees
	_main = main
	_build_message()
	_build_shop()
	_build_hint()
	_build_diary()
	picker = RegionPicker.new()
	picker.chosen.connect(func(id): region_chosen.emit(id))
	add_child(picker)

# ── 都道府県を選ぶ画面 ──
func open_region_picker() -> void:
	picker.touch_mode = touch_mode
	picker.open()

func is_picker_open() -> bool:
	return picker != null and picker.visible

# 植えられない・収穫した などを数秒だけ出す
func show_message(text: String, seconds: float = MESSAGE_SECONDS) -> void:
	_message = text
	_message_timer = seconds
	_message_label.text = _shown(text)
	_message_panel.visible = true

func is_message_visible() -> bool:
	return _message_panel != null and _message_panel.visible

func _build_message() -> void:
	_message_panel = PanelContainer.new()
	_message_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_message_panel.offset_top = -16.0
	_message_panel.offset_bottom = -16.0
	_message_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_message_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_panel.visible = false
	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_panel.add_child(_message_label)
	add_child(_message_panel)

# ── 市場の画面 ──────────────────────────────────────────────
func _build_shop() -> void:
	_shop = PanelContainer.new()
	# 左の文字表示(持ち物が見える)と重ならないよう、右に寄せる
	_shop.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_shop.offset_left = -8.0
	_shop.offset_right = -8.0
	_shop.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_shop.grow_vertical = Control.GROW_DIRECTION_BOTH
	_shop.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_shop.add_child(box)
	_shop_title = Label.new()
	box.add_child(_shop_title)
	_shop_money = Label.new()
	box.add_child(_shop_money)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	box.add_child(columns)
	for i in range(2):
		var col := VBoxContainer.new()
		columns.add_child(col)
		_shop_columns.append(col)
	add_child(_shop)

func is_shop_open() -> bool:
	return _shop != null and _shop.visible

func open_shop() -> void:
	_shop.visible = true
	_status_timer = 0.0  # ヒントをすぐ隠す
	refresh_shop()

func close_shop() -> void:
	_shop.visible = false
	_status_timer = 0.0

# 所持金と品の並びを作り直す(買う・売るたびに呼ぶ)
func refresh_shop() -> void:
	# 作り直しても、同じ列の同じ行にフォーカスを残す
	var focused_col := 0
	var focused_row := 0
	for c in range(_shop_columns.size()):
		var col: VBoxContainer = _shop_columns[c]
		for i in range(col.get_child_count()):
			if col.get_child(i).has_focus():
				focused_col = c
				focused_row = i
		for b in col.get_children():
			col.remove_child(b)
			b.queue_free()
	_shop_title.text = _shown(_main.shop_title())
	_shop_money.text = _shown(_main.shop_header())
	var rows: Array = _main.visible_shop_rows()
	var row_height := _touch_row_height(rows)
	for row in rows:
		var b := Button.new()
		b.text = _shown(row.text)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = row_height
		b.pressed.connect(func(): shop_action.emit(row.id))
		_shop_columns[row.column].add_child(b)
	if is_shop_open():
		var col: VBoxContainer = _shop_columns[focused_col]
		col.get_child(mini(focused_row, col.get_child_count() - 1)).grab_focus()

# タッチのときの行の高さ。指で押せる高さにしたいが、行が多い画面は画面に収まる高さにする
func _touch_row_height(rows: Array) -> float:
	if not touch_mode:
		return 0.0
	var counts := [0, 0]
	for row in rows:
		counts[row.column] += 1
	var room: float = get_viewport().get_visible_rect().size.y - SHOP_HEADER_HEIGHT
	return clampf(room / maxi(counts.max(), 1) - SHOP_ROW_GAP, 0.0, TOUCH_ROW_HEIGHT)

# ── ヒント ────────────────────────────────────────────────
func _build_hint() -> void:
	_hint_panel = PanelContainer.new()
	_hint_panel.name = "Hint"
	_hint_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hint_panel.offset_left = -8.0
	_hint_panel.offset_right = -8.0
	_hint_panel.offset_top = 8.0
	_hint_panel.offset_bottom = 8.0
	_hint_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.30, 0.18, 0.92)
	style.border_color = Color(0.96, 0.84, 0.46)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_hint_panel.add_theme_stylebox_override("panel", style)
	_hint_label = Label.new()
	_hint_panel.add_child(_hint_label)
	add_child(_hint_panel)

func _update_hint() -> void:
	var text: String = _main.hint_text()
	var show: bool = text != "" and not is_shop_open() and not is_diary_open()
	_hint_panel.visible = show
	if show:
		# タッチの狭い画面では、左の文字に重ならないよう幅を決めて折り返す
		_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if touch_mode else TextServer.AUTOWRAP_OFF
		_hint_label.custom_minimum_size.x = TOUCH_HINT_WIDTH if touch_mode else 0.0
		_hint_label.text = _shown("ヒント\n%s\n(K で閉じる)" % text)

# ── 日記(ベッドで休む) ─────────────────────────────────────
func _build_diary() -> void:
	_diary = ColorRect.new()
	_diary.color = Color(0.03, 0.03, 0.07, 0.8)  # 眠っている姿がうっすら見える暗さ
	_diary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_diary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_diary.visible = false
	_diary_label = Label.new()
	_diary_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_diary_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_diary_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_diary_label.add_theme_font_size_override("font_size", 20)
	_diary.add_child(_diary_label)
	add_child(_diary)

func is_diary_open() -> bool:
	return _diary != null and _diary.visible

# delay 秒たってから暗くなる(横になる動きを見せるため)
func open_diary(text: String, delay := 0.0) -> void:
	_diary_label.text = _shown(text)
	_diary.visible = true
	_diary.modulate.a = 0.0
	if _diary_fade != null:
		_diary_fade.kill()
	_diary_fade = create_tween()
	_diary_fade.tween_property(_diary, "modulate:a", 1.0, DIARY_FADE_SECONDS).set_delay(delay)

func close_diary() -> void:
	if _diary_fade != null:
		_diary_fade.kill()
	_diary.visible = false

static func _money_text(n: int) -> String:
	# 3 桁ごとにカンマ(例: 2,000)
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

func _process(delta: float) -> void:
	if _player == null:
		return
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message = ""
			_message_panel.visible = false
	# タッチのとき(遅いスマホ)は文字を組み直す回数を減らす。PC では毎フレーム
	_status_timer -= delta
	if not touch_mode or _status_timer <= 0.0:
		_status_timer = TOUCH_STATUS_SECONDS
		_label.text = status_text()
		_update_hint()
		# 背景は文字の量に合わせる
		_bg.size = _label.get_combined_minimum_size() + Vector2(12, 8)
	# タッチの狭い画面では、市場の画面と左の文字が重なるので、開いているあいだは文字を隠す(所持金は市場の画面にも出る)
	var hide_status: bool = touch_mode and is_shop_open()
	_label.visible = not hide_status
	_bg.visible = not hide_status

# 左上に出す文字
func status_text() -> String:
	var lines := _status_lines()
	# 市場を開いているあいだは持ち物を自動で出す。ストーブの画面は行の中に持っている数が出るので、重ならないよう出さない
	var in_kitchen: bool = is_shop_open() and (_main._panel == "kitchen" or _main._panel == "table")
	var talking: bool = is_shop_open() and _main._panel == "visitor"  # 話しているときも、持っている数は行の中に出る
	if (inventory_open or is_shop_open()) and not in_kitchen and not talking:
		lines.append_array(_inventory_lines())
	if help_open:
		lines.append_array(_touch_help_lines() if touch_mode else _help_lines())
	return _shown("\n".join(lines))

# いつも見たいこと
func _status_lines() -> PackedStringArray:
	var dt: Dictionary = _main.world.time.now_local()  # 検証で日付を進めたときも、その日付を出す
	var season_jp: String = _main.SEASON_NAMES[_trees.season]
	var offset := ""
	if _trees.time_offset_years > 0.0:
		offset = "  (+%d年後をプレビュー中)" % int(_trees.time_offset_years)
	var clock = _main.world.clock
	if clock.is_preview():
		offset += "  (+%d時間をプレビュー中)" % int(clock.preview_hours)

	var lines := PackedStringArray()
	lines.append("%04d/%02d/%02d %s  %s%s   所持金: %s₽   丸太: %d本" % [
		dt.year, dt.month, dt.day, clock.time_text(), season_jp, offset,
		_money_text(_main.world.market.money), int(_main.world.cabin.materials.log),
	])
	# 今日の発見は一日中見られるように常に出す
	if _trees.last_day == _trees.today() and _trees.today_event != "":
		lines.append("今日の発見: " + _main.daily_message(_trees.today_event))
	lines.append(_main.quest_line())
	lines.append(_main.cabin_line())
	var pot: String = _main.kitchen_line()
	if pot != "":
		lines.append(pot)
	var meal: String = _main.meal_line()
	if meal != "":
		lines.append(meal)
	lines.append(_main.pond_line())
	var hive: String = _main.hive_line()
	if hive != "":
		lines.append(hive)
	lines.append(_main.selection_line())
	# その場所でだけ意味があること
	if _main.world.market.is_near(_main.player_pos()) and not is_shop_open():
		lines.append("市場の前(B で開く)")
	var furniture: String = _main.furniture_line()
	if furniture != "":
		lines.append(furniture)
	var visitor: String = _main.visitor_line()
	if visitor != "":
		lines.append(visitor)
	var plot: String = _main.plot_line()
	if plot != "":
		lines.append(plot)
	var beside: String = _main.pond_beside_line()
	if beside != "":
		lines.append(beside)
	var feeder: String = _main.feeder_line()
	if feeder != "":
		lines.append(feeder)
	var nest: String = _main.nest_box_line()
	if nest != "":
		lines.append(nest)
	var prune: String = _main.prune_line()
	if prune != "":
		lines.append(prune)
	if touch_mode:
		lines.append("持ち物と操作はメニューから")
	else:
		lines.append("Tab:%s  F1:%s" % ["持ち物を閉じる" if inventory_open else "持ち物", "操作を閉じる" if help_open else "操作"])
	return lines

# 持ち物(Tab)
func _inventory_lines() -> PackedStringArray:
	var pos: Vector2 = _main.player_pos()
	return PackedStringArray([
		"─ 持ち物 ─",
		"種: " + _stock_text(_trees.seeds, false),
		"苗木: " + _stock_text(_trees.saplings, true),
		"野菜の種: " + _main.crop_seeds_line() + _orders_suffix(),
		"苗: " + _main.seedlings_line(),
		"収穫物: " + _main.produce_line(),
		"保存食: " + _main.food_line(),
		"生き物の図鑑: " + _main.creatures_line(),
		"木の節目: " + _main.milestones_line(),
		"近所の人: " + _main.neighbors_line(),
		"植えた木: %d本   いる場所: X %.0fm  Y %.0fm" % [_trees.trees.size(), pos.x, pos.y],
	])

# 持ち物の木の種・苗木の並び。この土地で育つ木と、持っている木だけ。3 つごとに折り返す。
# 例: 「白樺 3  リンゴ 1  シベリア杉 0」(種には、苗木からしか育てない果樹は出さない)
func _stock_text(stock: Dictionary, with_sapling_only: bool) -> String:
	var order: Array = Forest.SPECIES.keys().filter(func(sp): return not sp in Forest.SAPLING_ONLY)
	if with_sapling_only:
		order.append_array(Forest.SAPLING_ONLY)
	var parts := PackedStringArray()
	for sp in order:
		if _trees.grows_here(sp) or int(stock.get(sp, 0)) > 0:
			parts.append("%s %d" % [Forest.SPECIES[sp].name, int(stock.get(sp, 0))])
	var rows := PackedStringArray()
	for i in range(0, parts.size(), 3):
		rows.append("  ".join(parts.slice(i, i + 3)))
	return "\n      ".join(rows) if not rows.is_empty() else "なし"

# 注文した春の種があれば、持ち物の野菜の種の行のあとに出す
func _orders_suffix() -> String:
	var m = _main.world.market
	if m.orders.is_empty():
		return ""
	return "
      注文中(%d/1に届く): " % _main.world.region.winter_end_month() + _main.orders_text(m.orders)

# タッチのときは、キーの言い方をボタンの名前に置き換えて出す
func _shown(text: String) -> String:
	return TouchText.convert(text) if touch_mode else text

# 操作説明(タッチ。メニューの「操作」)
func _touch_help_lines() -> PackedStringArray:
	return PackedStringArray([
		"─ 操作 ─",
		"左のスティック: 歩く  寄る/引く: カメラ",
		"植える: 木を植える/区画にまく  水やり  収穫  抜く: 抜く/伐る",
		"小屋: 場所を決める/作業/苗づくり  使う: 家具のそばで使う",
		"市場・話す・雪かき: 使えるときだけボタンが出る(市場は南の境界の外)",
		"メニュー: 菜園 池 巣箱 餌台 剪定",
		"メニュー: 植える木と野菜を選ぶ  種/苗木  持ち物  音量",
		"メニュー: +1年 +10年 +1時間 今に戻す(未来をプレビュー)",
	])

# 操作説明(F1)
func _help_lines() -> PackedStringArray:
	return PackedStringArray([
		"─ 操作 ─",
		"J:丸太の巣箱を作る/くり抜く/はちみつを採る  M:音量(大/中/小/消す)",
		_main.local_text("L:鳥の餌台を立てる/白樺の種を置く(秋と冬)/育った木にムクドリの巣箱  X:果樹を剪定する(冬)"),
		"U:押したまま歩いて雪かき(冬)  H:小屋の東の台で薪を割る / 腰掛けで食べる",
		"WASD/矢印:歩く  ホイール:ズーム  B:市場(南の境界の外)  C:訪問者と話す",
		"[1]%s [2]果樹(押すたびに %s) [3]%s [V]種/苗木" % [_main.group_keys_text("broadleaf"), _main.group_keys_text("fruit", false), _main.group_keys_text("conifer")],
		"[4]ラディッシュ [5]にんじん [6]きゅうり [7]じゃがいも [8]ニンニク [9]トマト",
		"SPACE:植える/区画にまく  Q:水やり  E:収穫  Z:抜く/伐る",
		"F:菜園  P:池  H:小屋(完成したら 苗づくり / ストーブの前で料理 / ベッドのそばで日記)  K:ヒントを閉じる",
		"T:+1年  G:+10年  N:+1時間  R:今に戻す(未来をプレビュー)",
	])
