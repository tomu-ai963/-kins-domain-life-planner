extends ColorRect

# ── 自分の名前と性別を決める画面(2D と 3D で共通。HUD が持つ。2026-11-16) ──────────────
# ゲームのいちばんはじめ(自分の記録がないセーブを開いたときも)に一度だけ出す。このあと都道府県・家族を選ぶ。
#   input: 名前の欄と 男性 / 女性 / 決めない → confirm: 確かめて「これで始める」
# 性別はあとから変えられないので、確かめる段を入れる(名前は Y で付け直せる)。
# 決めたら chosen(名前, 性別)を出す。ルールは logic/Profile.gd、決めたあとの処理は Main
const Profile = preload("res://logic/Profile.gd")
const Family = preload("res://logic/Family.gd")
const BUTTON_SIZE := Vector2(190, 40)
const TOUCH_BUTTON_SIZE := Vector2(210, 52)
const NAME_WIDTH := 260.0

signal chosen(player_name, sex)

var touch_mode := false
var step := "input"   # input / confirm(テスト用に見えるようにしておく)
var sex := ""
var _title: Label
var _body: Label
var _name_edit: LineEdit
var _sex_row: HBoxContainer
var _sex_buttons := {}
var _grid: GridContainer
var _buttons := []

func _init() -> void:
	color = Color(0.05, 0.07, 0.05, 0.92)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
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
	_name_edit = LineEdit.new()
	_name_edit.max_length = Profile.NAME_MAX
	_name_edit.custom_minimum_size = Vector2(NAME_WIDTH, 40)
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.placeholder_text = "名前(%d文字まで)" % Profile.NAME_MAX
	_name_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_name_edit.text_submitted.connect(func(_t): next())
	box.add_child(_name_edit)
	_sex_row = HBoxContainer.new()
	_sex_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_sex_row.add_theme_constant_override("separation", 8)
	box.add_child(_sex_row)
	for s in Profile.SEXES:
		var b := Button.new()
		b.toggle_mode = true
		b.pressed.connect(set_sex.bind(s))
		_sex_row.add_child(b)
		_sex_buttons[s] = b
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(_grid)

func open() -> void:
	visible = true
	_name_edit.text = ""
	sex = ""
	show_input()

func close() -> void:
	visible = false

# 1 段目: 名前と性別
func show_input(note := "") -> void:
	step = "input"
	_title.text = "あなたのこと"
	_body.text = note if note != "" else "あなたの名前(%d文字まで)と性別を決めてください。\n名前は日記や、家族・近所の人の言葉に出ます。名前はあとから Y で付け直せます。" % Profile.NAME_MAX
	_name_edit.visible = true
	_sex_row.visible = true
	_refresh_sex()
	_clear(1)
	_add_button("次へ", next)
	_name_edit.call_deferred("grab_focus")

func set_sex(s: String) -> void:
	sex = s
	_refresh_sex()

func _refresh_sex() -> void:
	var size: Vector2 = TOUCH_BUTTON_SIZE if touch_mode else BUTTON_SIZE
	for s in _sex_buttons:
		var b: Button = _sex_buttons[s]
		b.text = ("● " if sex == s else "") + Profile.SEX_NAMES[s]
		b.button_pressed = sex == s
		b.custom_minimum_size = Vector2(size.x * 0.6, size.y)

# 名前の欄で Enter / 「次へ」
func next() -> void:
	if step != "input":
		return
	if typed_name() == "":
		show_input("名前を入れてください(%d文字まで)" % Profile.NAME_MAX)
		return
	show_confirm()

func typed_name() -> String:
	return Family.clean_name(_name_edit.text)

# 2 段目: 確かめる
func show_confirm() -> void:
	step = "confirm"
	_title.text = "%sさんで始めますか" % typed_name()
	_body.text = "名前: %s\n性別: %s\n(性別はあとから変えられません。名前は Y で付け直せます)" % [typed_name(), Profile.SEX_NAMES[sex]]
	_name_edit.visible = false
	_sex_row.visible = false
	_clear(2)
	_add_button("これで始める", _decide)
	_add_button("直す", show_input)

func _decide() -> void:
	var n := typed_name()
	if n == "":
		show_input()
		return
	close()
	chosen.emit(n, sex)

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

# ── テスト用 ──
func button_texts() -> Array:
	return _buttons.map(func(b): return b.text)

func press(text: String) -> bool:
	for b in _buttons:
		if b.text == text:
			b.pressed.emit()
			return true
	return false

func type_name(text: String) -> void:
	_name_edit.text = text

func body_text() -> String:
	return _body.text
