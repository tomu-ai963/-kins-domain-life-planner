extends CanvasLayer

# ── 画面の文字表示(2D と 3D で共通) ─────────────────────────────
# 左上: いつも見たいこと(日付・所持金・発見・クエスト・小屋・池・選択・足元)。
# Tab で持ち物(市場を開いているあいだは自動で出す)、F1 で操作説明を足す。
# 下の中央: 数秒だけのメッセージ。右: 市場の近くで B を押すと市場の画面が開く。
# 文言の中身は Main が決める(shop_rows・quest_line など)。ここは並べて出すだけ
const Forest = preload("res://logic/Forest.gd")
const MESSAGE_SECONDS := 3.0

signal shop_action(id)  # 市場の画面のボタン(品の id / "sell_<収穫物>" / "close")

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
var _shop: PanelContainer
var _shop_columns := []  # 買う列と売る列(VBoxContainer)
var _shop_money: Label

func setup(player: Node, trees: Forest, main: Node) -> void:
	_player = player
	_trees = trees
	_main = main
	_build_message()
	_build_shop()

# 植えられない・収穫した などを数秒だけ出す
func show_message(text: String, seconds: float = MESSAGE_SECONDS) -> void:
	_message = text
	_message_timer = seconds
	_message_label.text = text
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
	var title := Label.new()
	title.text = "市場(クリックか 矢印キー + Enter で選ぶ)"
	box.add_child(title)
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
	refresh_shop()

func close_shop() -> void:
	_shop.visible = false

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
	_shop_money.text = "所持金: %s₽" % _money_text(_main.world.market.money)
	for row in _main.shop_rows():
		var b := Button.new()
		b.text = row.text
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): shop_action.emit(row.id))
		_shop_columns[row.column].add_child(b)
	if is_shop_open():
		var col: VBoxContainer = _shop_columns[focused_col]
		col.get_child(mini(focused_row, col.get_child_count() - 1)).grab_focus()

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
	_label.text = status_text()
	# 背景は文字の量に合わせる
	_bg.size = _label.get_combined_minimum_size() + Vector2(12, 8)

# 左上に出す文字
func status_text() -> String:
	var lines := _status_lines()
	if inventory_open or is_shop_open():
		lines.append_array(_inventory_lines())
	if help_open:
		lines.append_array(_help_lines())
	return "\n".join(lines)

# いつも見たいこと
func _status_lines() -> PackedStringArray:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var season_jp: String = _main.SEASON_NAMES[_trees.season]
	var offset := ""
	if _trees.time_offset_years > 0.0:
		offset = "  (+%d年後をプレビュー中)" % int(_trees.time_offset_years)

	var lines := PackedStringArray()
	lines.append("%04d/%02d/%02d  %s%s   所持金: %s₽   丸太: %d本" % [
		dt.year, dt.month, dt.day, season_jp, offset,
		_money_text(_main.world.market.money), int(_main.world.cabin.materials.log),
	])
	# 今日の発見は一日中見られるように常に出す
	if _trees.last_day == _trees.today() and _trees.today_event != "":
		lines.append("今日の発見: " + _main.DAILY_MESSAGES[_trees.today_event])
	lines.append(_main.quest_line())
	lines.append(_main.cabin_line())
	lines.append(_main.pond_line())
	lines.append(_main.selection_line())
	# その場所でだけ意味があること
	if _main.world.market.is_near(_main.player_pos()) and not is_shop_open():
		lines.append("市場の前(B で開く)")
	var plot: String = _main.plot_line()
	if plot != "":
		lines.append(plot)
	lines.append("Tab:%s  F1:%s" % ["持ち物を閉じる" if inventory_open else "持ち物", "操作を閉じる" if help_open else "操作"])
	return lines

# 持ち物(Tab)
func _inventory_lines() -> PackedStringArray:
	var pos: Vector2 = _main.player_pos()
	var seeds: Dictionary = _trees.seeds
	var sap: Dictionary = _trees.saplings
	return PackedStringArray([
		"─ 持ち物 ─",
		"種: 白樺 %d  リンゴ %d  シベリア杉 %d" % [seeds.birch, seeds.apple, seeds.cedar],
		"苗木: 白樺 %d  リンゴ %d  シベリア杉 %d" % [sap.birch, sap.apple, sap.cedar],
		"野菜の種: " + _main.crop_seeds_line(),
		"収穫物: " + _main.produce_line(),
		"植えた木: %d本   いる場所: X %.0fm  Y %.0fm" % [_trees.trees.size(), pos.x, pos.y],
	])

# 操作説明(F1)
func _help_lines() -> PackedStringArray:
	return PackedStringArray([
		"─ 操作 ─",
		"WASD/矢印:歩く  ホイール:ズーム  B:市場(南の境界の外)",
		"[1]白樺 [2]リンゴ [3]シベリア杉 [V]種/苗木",
		"[4]ラディッシュ [5]にんじん [6]きゅうり [7]じゃがいも [8]ニンニク",
		"SPACE:植える/区画にまく  Q:水やり  E:収穫  Z:抜く/伐る",
		"F:菜園  P:池  H:小屋",
		"T:+1年  G:+10年  R:今日に戻す(未来をプレビュー)",
	])
