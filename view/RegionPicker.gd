extends ColorRect

# ── 土地のある都道府県を選ぶ画面(2D と 3D で共通。HUD が持つ) ──────────────
# ゲームのはじめ(県の記録がないセーブを開いたときも)に一度だけ出す。あとから変えられないので、決める前に確かめる段を入れる。
#   1 段目: 地方(Region.AREAS) → 2 段目: 都道府県 → 3 段目: 気候と植えられる木を見て「ここに決める」
# 決めたら chosen(都道府県の id)を出す。ルールは logic/Region.gd、決めたあとの処理は Main(GameWorld.choose_region)
# クリック・タッチ・矢印キー + Enter で選べる(Button のフォーカス)
const Region = preload("res://logic/Region.gd")
const Forest = preload("res://logic/Forest.gd")
const SEASON_NAMES := {"spring": "春", "summer": "夏", "autumn": "秋", "winter": "冬"}
const BUTTON_SIZE := Vector2(150, 40)
const TOUCH_BUTTON_SIZE := Vector2(170, 52)  # 指で押せる大きさ

signal chosen(id)

var touch_mode := false
var step := "area"   # area / pref / confirm(テスト用に見えるようにしておく)
var area := -1       # 選んでいる地方(Region.AREAS の添字)
var pref := ""       # 確かめている都道府県
var _title: Label
var _body: Label
var _grid: GridContainer
var _buttons := []   # 今並んでいるボタン(テスト用)

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
	show_areas()

func close() -> void:
	visible = false

# 1 段目: 地方
func show_areas() -> void:
	step = "area"
	area = -1
	pref = ""
	_title.text = "あなたの土地は、どこにありますか"
	_body.text = "選んだ都道府県の気候で季節がめぐり、植えられる木が変わります。\n一度決めると、あとから変えられません。"
	_clear(4)
	for i in range(Region.AREAS.size()):
		_add_button(Region.AREAS[i].name, show_prefs.bind(i))

# 2 段目: その地方の都道府県
func show_prefs(i: int) -> void:
	step = "pref"
	area = i
	pref = ""
	_title.text = Region.AREAS[i].name
	_body.text = "都道府県を選んでください"
	_clear(4)
	for id in Region.AREAS[i].prefs:
		_add_button(Region.PREFS[id].name, show_confirm.bind(id))
	_add_button("← 地方を選び直す", show_areas)

# 3 段目: 気候と植えられる木を見て決める
func show_confirm(id: String) -> void:
	step = "confirm"
	pref = id
	_title.text = "%sに決めますか" % Region.PREFS[id].name
	_body.text = describe(id)
	_clear(2)
	_add_button("ここに決める", _decide)
	_add_button("選び直す", show_prefs.bind(area) if area >= 0 else show_areas)

# 決める前に見せる、その土地の気候と植えられる木
static func describe(id: String) -> String:
	var zone_id: String = Region.PREFS[id].zone
	var z: Dictionary = Region.ZONES[zone_id]
	var lines := PackedStringArray()
	lines.append("気候: %s" % z.name)
	lines.append("季節: %s" % _months_text(z.months))
	var winter := "雪が積もり、地面と池が凍る" if z.snow else ("霜は降りるが、雪は積もらない" if z.frost else "霜も雪もない(冬も野菜をまける)")
	lines.append("冬: %s" % winter)
	var rain: int = int(z.rain)
	lines.append("雨: %s" % ("多い" if rain >= 32 else ("少ない" if rain <= 22 else "ふつう")))
	for group in Forest.GROUPS:
		var names := PackedStringArray()
		for sp in (Forest.FRUIT_ORDER if group == "fruit" else Forest.SPECIES.keys()):
			var s: Dictionary = Forest.SPECIES[sp]
			if s.group == group and zone_id in s.zones and not s.get("wild_only", false):
				names.append(s.name)
		lines.append("%s: %s" % [{"broadleaf": "広葉樹", "fruit": "果樹", "conifer": "針葉樹"}[group], "・".join(names) if not names.is_empty() else "なし"])
	var wild := PackedStringArray()
	for sp in Forest.SPECIES:
		var s: Dictionary = Forest.SPECIES[sp]
		if s.get("wild", false) and zone_id in s.zones:
			wild.append(s.name)
	lines.append("外の林: %s" % "・".join(wild))
	return "\n".join(lines)

# 例: 「春 4〜5月・夏 6〜8月・秋 9〜10月・冬 11〜3月」
static func _months_text(months: Array) -> String:
	var parts := PackedStringArray()
	for season in ["spring", "summer", "autumn", "winter"]:
		# 季節が始まる月(前の月が別の季節)から、続くあいだ数える
		for m in range(12):
			if months[m] == season and months[(m + 11) % 12] != season:
				var last := m
				while months[(last + 1) % 12] == season and (last + 1) % 12 != m:
					last += 1
				var first_m := m + 1
				var last_m := last % 12 + 1
				parts.append("%s %s" % [SEASON_NAMES[season], ("%d月" % first_m) if first_m == last_m else "%d〜%d月" % [first_m, last_m]])
				break
	return "・".join(parts)

func _decide() -> void:
	if pref == "":
		return
	var id := pref
	close()
	chosen.emit(id)

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
