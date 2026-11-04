extends CanvasLayer

# ── 画面の文字表示(2D と 3D で共通) ─────────────────────────────
# 左上: 日付・位置・持ち物・クエスト・操作・メッセージ。市場の近くで B を押すと、真ん中に市場の画面が開く。
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
var _shop: PanelContainer
var _shop_columns := []  # 買う列と売る列(VBoxContainer)
var _shop_money: Label

func setup(player: Node, trees: Forest, main: Node) -> void:
	_player = player
	_trees = trees
	_main = main
	_build_shop()

# 植えられない・収穫した などを数秒だけ出す
func show_message(text: String, seconds: float = MESSAGE_SECONDS) -> void:
	_message = text
	_message_timer = seconds

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

	var pos_m: Vector2 = _main.player_pos()
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var season_jp: String = _main.SEASON_NAMES[_trees.season]
	var seeds: Dictionary = _trees.seeds
	var sap: Dictionary = _trees.saplings

	var offset := ""
	if _trees.time_offset_years > 0.0:
		offset = "  (+%d年後をプレビュー中)" % int(_trees.time_offset_years)

	# 今日の発見は一日中見られるように常に出す
	var today: String = _trees.today()
	var found := ""
	if _trees.last_day == today and _trees.today_event != "":
		found = _main.DAILY_MESSAGES[_trees.today_event]

	var market_hint := ""
	if _main.world.market.is_near(pos_m):
		market_hint = "  ← 市場の前(B で開く)"

	_label.text = (
		"%04d/%02d/%02d  %s%s\n" +
		"X:%6.1f m  Y:%6.1f m   木: %d本%s\n" +
		"所持金: %s₽   丸太: %d本   収穫物: %s\n" +
		"種:   白樺 %d  リンゴ %d  シベリア杉 %d\n" +
		"苗木: 白樺 %d  リンゴ %d  シベリア杉 %d\n" +
		"野菜の種: %s\n" +
		"選択: %s\n" +
		"%s\n" +
		"今日の発見: %s\n" +
		"%s\n" +
		"%s\n" +
		"[1]白樺 [2]リンゴ [3]シベリア杉 [V]種/苗木  B:市場(南の境界の外)\n" +
		"[4]ラディッシュ [5]にんじん [6]きゅうり [7]じゃがいも [8]ニンニク\n" +
		"SPACE:植える/区画にまく  Q:水やり  E:収穫  Z:抜く/伐る  F:菜園  P:池  H:小屋\n" +
		"T:+1年  G:+10年  R:今日に戻す (未来をプレビュー)  ホイール:ズーム\n" +
		"%s\n" +
		"%s"
	) % [
		dt.year, dt.month, dt.day, season_jp, offset,
		pos_m.x, pos_m.y, _trees.trees.size(), market_hint,
		_money_text(_main.world.market.money), int(_main.world.cabin.materials.log), _main.produce_line(),
		seeds.birch, seeds.apple, seeds.cedar,
		sap.birch, sap.apple, sap.cedar,
		_main.crop_seeds_line(),
		_main.selected_name(),
		_main.selected_crop_line(),
		found,
		_main.quest_line(),
		_main.cabin_line(),
		_main.plot_line(),
		_message,
	]
	# 背景は文字の量に合わせる
	_bg.size = _label.get_combined_minimum_size() + Vector2(12, 8)
