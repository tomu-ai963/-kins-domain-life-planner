extends ColorRect

# ── 家族の名前を付け直す画面(2D と 3D で共通。HUD が持つ。2026-11-16) ──────────────
# Y(タッチはメニューの「家族」)で開く。家族 1 人ずつの名前の欄を並べ、「決める」で names_decided({id: 名前})を出す。
# 付け直せるのは名前だけ(顔ぶれ・息子か娘か・年齢は変えられない)。名前のルールは logic/Family.gd(rename)、文言は Main
const Family = preload("res://logic/Family.gd")
const BUTTON_SIZE := Vector2(160, 40)
const TOUCH_BUTTON_SIZE := Vector2(180, 52)
const NAME_WIDTH := 220.0

signal names_decided(names)  # {id: 名前}(Node の renamed と名前がぶつからないように)
signal closed

var touch_mode := false
var _title: Label
var _rows: GridContainer
var _edits := {}       # id → LineEdit
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
	_title.text = "家族の名前"
	box.add_child(_title)
	var note := Label.new()
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.text = "名前を付け直せます(%d文字まで)。空にした人は、今の名前のままです。" % Family.NAME_MAX
	box.add_child(note)
	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.add_theme_constant_override("h_separation", 12)
	_rows.add_theme_constant_override("v_separation", 8)
	box.add_child(_rows)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	for pair in [["決める", _decide], ["やめる", _cancel]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(pair[1])
		buttons.add_child(b)
		_buttons.append(b)

# members は Family.members、ages は {id: 今の年齢}
func open(members: Array, ages: Dictionary) -> void:
	for c in _rows.get_children():
		c.queue_free()
	_edits.clear()
	for m in members:
		var label := Label.new()
		label.text = m.relation if m.role == "spouse" else "%s %d歳" % [m.relation, int(ages.get(m.id, 0))]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_rows.add_child(label)
		var edit := LineEdit.new()
		edit.text = m.name
		edit.max_length = Family.NAME_MAX
		edit.custom_minimum_size = Vector2(NAME_WIDTH, TOUCH_BUTTON_SIZE.y if touch_mode else BUTTON_SIZE.y)
		edit.text_submitted.connect(func(_t): _decide())
		_rows.add_child(edit)
		_edits[m.id] = edit
	for b in _buttons:
		b.custom_minimum_size = TOUCH_BUTTON_SIZE if touch_mode else BUTTON_SIZE
	visible = true
	if not members.is_empty():
		var first: LineEdit = _edits[members[0].id]
		first.call_deferred("grab_focus")

func close() -> void:
	visible = false

func _decide() -> void:
	var names := {}
	for id in _edits:
		names[id] = _edits[id].text
	close()
	names_decided.emit(names)

func _cancel() -> void:
	close()
	closed.emit()

# ── テスト用 ──
func type_name(id: String, text: String) -> void:
	_edits[id].text = text

func name_of(id: String) -> String:
	return _edits[id].text if _edits.has(id) else ""

func press(text: String) -> bool:
	for b in _buttons:
		if b.text == text:
			b.pressed.emit()
			return true
	return false
