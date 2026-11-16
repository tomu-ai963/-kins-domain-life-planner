extends ColorRect

# ── 一緒に暮らす家族を選ぶ画面(2D と 3D で共通。HUD が持つ。2026-11-16) ──────────────
# ゲームのはじめ(家族の記録がないセーブを開いたときも)に一度だけ出す。都道府県を選んだあと。
# あとから変えられないので(名前だけは Y で付け直せる)、決める前に確かめる段を入れる。
#   spouse: 配偶者(Family.SPOUSES か、いない) → spouse_name: 配偶者の名前(いないときは飛ばす)
#   → children: 子どもの人数(0〜3) → child: 1 人ずつ名前・息子か娘か・年齢 → confirm: 家族を見て「この家族で暮らす」
# 決めたら chosen({spouse, spouse_name, kids: [{name, sex, age}]})を出す。ルールは logic/Family.gd、決めたあとの処理は Main
# クリック・タッチ・矢印キー + Enter で選べる(Button のフォーカス)。名前は文字の欄に打つ(Enter で次へ)
const Family = preload("res://logic/Family.gd")
const BUTTON_SIZE := Vector2(190, 40)
const TOUCH_BUTTON_SIZE := Vector2(210, 52)  # 指で押せる大きさ
const SMALL_BUTTON := Vector2(56, 40)
const TOUCH_SMALL_BUTTON := Vector2(64, 52)
const NAME_WIDTH := 260.0

signal chosen(choice)

var touch_mode := false
var step := "spouse"   # spouse / spouse_name / children / child / confirm(テスト用に見えるようにしておく)
var spouse := ""       # 選んだ配偶者(いなければ "")
var spouse_name := ""  # 配偶者の名前
var kids := []         # 子どもの並び [{name, sex, age}]
var child_index := -1  # 今決めている子ども(kids の添字)
var _title: Label
var _body: Label
var _form: VBoxContainer    # 名前・息子か娘か・年齢の欄
var _name_edit: LineEdit
var _sex_row: HBoxContainer
var _sex_buttons := {}      # "m" / "f" → Button
var _age_row: HBoxContainer
var _age_label: Label
var _age_buttons := []      # [−, +]
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
	_build_form(box)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(_grid)

func _build_form(box: VBoxContainer) -> void:
	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 10)
	_form.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_form)
	_name_edit = LineEdit.new()
	_name_edit.max_length = Family.NAME_MAX
	_name_edit.custom_minimum_size = Vector2(NAME_WIDTH, 40)
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.placeholder_text = "名前(%d文字まで)" % Family.NAME_MAX
	_name_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_name_edit.text_submitted.connect(func(_t): _next())
	_form.add_child(_name_edit)
	_sex_row = HBoxContainer.new()
	_sex_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_sex_row.add_theme_constant_override("separation", 8)
	_form.add_child(_sex_row)
	for sex in ["m", "f"]:
		var b := Button.new()
		b.toggle_mode = true
		b.pressed.connect(set_sex.bind(sex))
		_sex_row.add_child(b)
		_sex_buttons[sex] = b
	_age_row = HBoxContainer.new()
	_age_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_age_row.add_theme_constant_override("separation", 8)
	_form.add_child(_age_row)
	var minus := Button.new()
	minus.text = "−"
	minus.pressed.connect(change_age.bind(-1))
	_age_row.add_child(minus)
	_age_label = Label.new()
	_age_label.custom_minimum_size = Vector2(80, 0)
	_age_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_age_row.add_child(_age_label)
	var plus := Button.new()
	plus.text = "+"
	plus.pressed.connect(change_age.bind(1))
	_age_row.add_child(plus)
	_age_buttons = [minus, plus]
	_form.visible = false

func open() -> void:
	visible = true
	show_spouses()

func close() -> void:
	visible = false

# 1 段目: 配偶者
func show_spouses() -> void:
	step = "spouse"
	spouse = ""
	spouse_name = ""
	kids = []
	child_index = -1
	_title.text = "一緒に暮らす家族を選んでください"
	_body.text = "家族は土地で暮らし、毎朝少し手伝ってくれます。話しかけると(C)、ときどき贈り物も。\n名前は自分で付けられます。家族の顔ぶれは、一度決めるとあとから変えられません(名前は付け直せます)。"
	_show_form(false, false, false)
	_clear(2)
	for id in Family.SPOUSE_ORDER:
		var s: Dictionary = Family.SPOUSES[id]
		_add_button("%s(%s)" % [s.name, s.relation], show_spouse_name.bind(id))
	_add_button("配偶者はいない", show_children)

# 2 段目: 配偶者の名前
func show_spouse_name(id: String) -> void:
	step = "spouse_name"
	spouse = id
	var s: Dictionary = Family.SPOUSES[id]
	_title.text = "%sの名前" % s.relation
	_body.text = "名前を付けてください(%d文字まで)。そのままでもかまいません。" % Family.NAME_MAX
	_show_form(true, false, false)
	_name_edit.text = s.name if spouse_name == "" else spouse_name
	_clear(2)
	_add_button("次へ", _next)
	_add_button("← 配偶者を選び直す", show_spouses)
	_focus_name()

# 3 段目: 子どもの人数
func show_children() -> void:
	step = "children"
	_title.text = "子どもは何人ですか"
	_body.text = "このあと 1 人ずつ、名前と息子か娘か、年齢を決めます。\n子どもは一月で 1 歳育ち、%d 歳から畑の雑草を抜いてくれます。" % Family.HELP_AGE
	_show_form(false, false, false)
	_clear(2)
	for n in range(Family.MAX_CHILDREN + 1):
		_add_button(children_text(n), _start_children.bind(n))
	_add_button("← 配偶者を選び直す", show_spouses)

static func children_text(n: int) -> String:
	return "子どもはいない" if n == 0 else "%d人" % n

func _start_children(n: int) -> void:
	kids = []
	for i in range(n):
		var c: Dictionary = Family.CHILDREN[i]
		kids.append({"name": c.name, "sex": c.sex, "age": c.age})
	if n == 0:
		show_confirm()
	else:
		show_child(0)

# 4 段目: 子どもを 1 人ずつ
func show_child(i: int) -> void:
	step = "child"
	child_index = i
	var k: Dictionary = kids[i]
	_title.text = "%d人目の子ども" % (i + 1) if kids.size() > 1 else "子ども"
	_body.text = "名前(%d文字まで)・息子か娘か・年齢(0〜%d歳)を決めてください。" % [Family.NAME_MAX, Family.MAX_START_AGE]
	_show_form(true, true, true)
	_name_edit.text = k.name
	_refresh_child()
	_clear(2)
	_add_button("次へ", _next)
	_add_button("← 戻る", _back_from_child)
	_focus_name()

func _back_from_child() -> void:
	_keep_child_name()
	if child_index > 0:
		show_child(child_index - 1)
	else:
		show_children()

# 息子か娘かを選ぶ。名前が決まった名前のままなら、選んだほうの決まった名前にする
func set_sex(sex: String) -> void:
	if step != "child":
		return
	var k: Dictionary = kids[child_index]
	var current := Family.clean_name(_name_edit.text)
	if current == "" or current == Family.default_name(child_index, k.sex):
		_name_edit.text = Family.default_name(child_index, sex)
	k.sex = sex
	_refresh_child()

func change_age(delta: int) -> void:
	if step != "child":
		return
	var k: Dictionary = kids[child_index]
	k.age = clampi(int(k.age) + delta, 0, Family.MAX_START_AGE)
	_refresh_child()

func _refresh_child() -> void:
	var k: Dictionary = kids[child_index]
	for sex in _sex_buttons:
		var b: Button = _sex_buttons[sex]
		b.text = ("● " if k.sex == sex else "") + Family.child_relation(sex)
		b.button_pressed = k.sex == sex
	_age_label.text = "%d歳" % int(k.age)
	_age_buttons[0].disabled = int(k.age) <= 0
	_age_buttons[1].disabled = int(k.age) >= Family.MAX_START_AGE

func _keep_child_name() -> void:
	if step == "child" and child_index >= 0:
		kids[child_index].name = Family.clean_name(_name_edit.text)

# 名前の欄で Enter / 「次へ」
func _next() -> void:
	match step:
		"spouse_name":
			spouse_name = Family.clean_name(_name_edit.text)
			show_children()
		"child":
			_keep_child_name()
			if child_index + 1 < kids.size():
				show_child(child_index + 1)
			else:
				show_confirm()

# 5 段目: 家族を見て決める
func show_confirm() -> void:
	step = "confirm"
	_title.text = "この家族で暮らしますか"
	_body.text = describe(choice())
	_show_form(false, false, false)
	_clear(2)
	_add_button("この家族で暮らす", _decide)
	_add_button("選び直す", show_spouses)

# 選んだ中身(空の名前は決まった名前に置き換えたもの)
func choice() -> Dictionary:
	var out_kids := []
	for i in range(kids.size()):
		var k: Dictionary = kids[i]
		var n := Family.clean_name(str(k.name))
		out_kids.append({"name": n if n != "" else Family.default_name(i, k.sex), "sex": k.sex, "age": int(k.age)})
	var sn := Family.clean_name(spouse_name)
	if spouse != "" and sn == "":
		sn = Family.SPOUSES[spouse].name
	return {"spouse": spouse, "spouse_name": sn if spouse != "" else "", "kids": out_kids}

static func describe(c: Dictionary) -> String:
	var lines := PackedStringArray()
	if c.spouse != "":
		var s: Dictionary = Family.SPOUSES[c.spouse]
		lines.append("%s: %s(毎朝、畑や木に %d か所まで水をやる)" % [s.relation, c.spouse_name, Family.WATER_HELP])
	for k in c.kids:
		lines.append("%s: %s %d歳" % [Family.child_relation(k.sex), k.name, k.age])
	if lines.is_empty():
		lines.append("ひとりで暮らす(あとから家族は増えません)")
	else:
		lines.append("小屋が完成するまでは、家族はテントで休みます")
	return "\n".join(lines)

func _decide() -> void:
	var c := choice()
	close()
	chosen.emit(c)

func _show_form(name_on: bool, sex_on: bool, age_on: bool) -> void:
	_form.visible = name_on or sex_on or age_on
	_name_edit.visible = name_on
	_sex_row.visible = sex_on
	_age_row.visible = age_on
	var small: Vector2 = TOUCH_SMALL_BUTTON if touch_mode else SMALL_BUTTON
	for b in _sex_buttons.values():
		b.custom_minimum_size = Vector2(small.x * 2.0, small.y)
	for b in _age_buttons:
		b.custom_minimum_size = small
	_name_edit.custom_minimum_size.y = small.y

func _focus_name() -> void:
	_name_edit.call_deferred("grab_focus")
	_name_edit.call_deferred("select_all")

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
	if _buttons.size() == 1 and not _form.visible:
		b.call_deferred("grab_focus")

# ── テスト用 ──
func button_texts() -> Array:
	return _buttons.map(func(b): return b.text)

func press(text: String) -> bool:
	for b in _buttons:
		if b.text == text:
			b.pressed.emit()
			return true
	return false

# 名前の欄に打つ(テスト用)
func type_name(text: String) -> void:
	_name_edit.text = text

func name_text() -> String:
	return _name_edit.text

func age_text() -> String:
	return _age_label.text
