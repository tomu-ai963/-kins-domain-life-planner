extends ColorRect

# ── 一緒に暮らす家族を選ぶ画面(2D と 3D で共通。HUD が持つ。2026-11-16) ──────────────
# ゲームのはじめ(家族の記録がないセーブを開いたときも)に一度だけ出す。都道府県を選んだあと。
# あとから変えられないので、決める前に確かめる段を入れる。
#   1 段目: 配偶者(Family.SPOUSES か、いない) → 2 段目: 子どもの人数(0〜3) → 3 段目: 家族を見て「この家族で暮らす」
# 決めたら chosen(配偶者の id か ""、子どもの人数)を出す。ルールは logic/Family.gd、決めたあとの処理は Main
# クリック・タッチ・矢印キー + Enter で選べる(Button のフォーカス)
const Family = preload("res://logic/Family.gd")
const BUTTON_SIZE := Vector2(190, 40)
const TOUCH_BUTTON_SIZE := Vector2(210, 52)  # 指で押せる大きさ

signal chosen(spouse, children)

var touch_mode := false
var step := "spouse"   # spouse / children / confirm(テスト用に見えるようにしておく)
var spouse := ""       # 選んだ配偶者(いなければ "")
var children := -1     # 選んだ子どもの人数
var _title: Label
var _body: Label
var _grid: GridContainer
var _buttons := []

func _init() -> void:
	color = Color(0.05, 0.07, 0.05, 0.92)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # 後ろの画面に触れないように
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 24)
	box.add_child(_title)
	_body = Label.new()
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_body)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(_grid)

func open() -> void:
	visible = true
	show_spouses()

func close() -> void:
	visible = false

# 1 段目: 配偶者
func show_spouses() -> void:
	step = "spouse"
	spouse = ""
	children = -1
	_title.text = "一緒に暮らす家族を選んでください"
	_body.text = "家族は土地で暮らし、毎朝少し手伝ってくれます。話しかけると(C)、ときどき贈り物も。\n一度決めると、あとから変えられません。"
	_clear(2)
	for id in Family.SPOUSE_ORDER:
		var s: Dictionary = Family.SPOUSES[id]
		_add_button("%s(%s)" % [s.name, s.relation], show_children.bind(id))
	_add_button("配偶者はいない", show_children.bind(""))

# 2 段目: 子どもの人数
func show_children(id: String) -> void:
	step = "children"
	spouse = id
	children = -1
	_title.text = "子どもは何人ですか"
	_body.text = "子どもは一月で 1 歳育ちます。%d 歳から畑の雑草を抜いてくれます。" % Family.HELP_AGE
	_clear(2)
	for n in range(Family.MAX_CHILDREN + 1):
		_add_button(children_text(n), show_confirm.bind(n))
	_add_button("← 配偶者を選び直す", show_spouses)

# 「子どもはいない」「2人(ワーニャ 9歳・マーシャ 6歳)」
static func children_text(n: int) -> String:
	if n == 0:
		return "子どもはいない"
	var names := PackedStringArray()
	for i in range(n):
		names.append("%s %d歳" % [Family.CHILDREN[i].name, Family.CHILDREN[i].age])
	return "%d人(%s)" % [n, "・".join(names)]

# 3 段目: 家族を見て決める
func show_confirm(n: int) -> void:
	step = "confirm"
	children = n
	_title.text = "この家族で暮らしますか"
	_body.text = describe(spouse, n)
	_clear(2)
	_add_button("この家族で暮らす", _decide)
	_add_button("選び直す", show_spouses)

static func describe(spouse_id: String, n: int) -> String:
	var lines := PackedStringArray()
	if spouse_id != "":
		var s: Dictionary = Family.SPOUSES[spouse_id]
		lines.append("%s: %s(毎朝、畑や木に %d か所まで水をやる)" % [s.relation, s.name, Family.WATER_HELP])
	for i in range(n):
		var c: Dictionary = Family.CHILDREN[i]
		lines.append("%s: %s %d歳" % [c.relation, c.name, c.age])
	if lines.is_empty():
		lines.append("ひとりで暮らす(あとから家族は増えません)")
	lines.append("小屋が完成するまでは、家族はテントで休みます")
	return "\n".join(lines)

func _decide() -> void:
	if children < 0:
		return
	var s := spouse
	var n := children
	close()
	chosen.emit(s, n)

func _clear(columns: int) -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	_grid.columns = columns

func _add_button(text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = TOUCH_BUTTON_SIZE if touch_mode else BUTTON_SIZE
	b.pressed.connect(action)
	_grid.add_child(b)
	_buttons.append(b)
	if _buttons.size() == 1:
		b.call_deferred("grab_focus")

# 並んでいるボタンの文字(テスト用)
func button_texts() -> Array:
	return _buttons.map(func(b): return b.text)

# 文字が text のボタンを押す(テスト用)
func press(text: String) -> bool:
	for b in _buttons:
		if b.text == text:
			b.pressed.emit()
			return true
	return false
