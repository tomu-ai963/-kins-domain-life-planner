extends RefCounted

# ── タッチ操作のときの文言 ─────────────────────────────────────
# ゲームの文言はキーボードの言い方で書いてある(「H で作業」など)。タッチのときだけ、画面に出す直前にボタンの名前へ置き換える。
# 元の文言を 2 通り持たなくて済むし、文言が増えても同じ言い方なら自動で置き換わる

# 文言まるごと、または決まった言い回しの置き換え。上から順に当てる
const PHRASES := [
	["WASD か矢印キーで歩ける。\nホイールでカメラを寄せたり引いたりできる。", "左のスティックで歩ける。\n「寄る」「引く」でカメラを動かせる。"],
	["(クリックか 矢印キー + Enter で選ぶ)", "(押して選ぶ)"],
	["H / Esc / Enter で起きる", "「起きる」を押す"],
	["(B / Esc)", ""],
	["(H / Esc)", ""],
	["(C / Esc)", ""],
	["[1][2][3] で", "メニューで"],
	["[4]〜[9] で", "メニューで"],
	["[V] で", "メニューで"],
	["Tab の持ち物", "メニューの持ち物"],
	[" [9]", ""],
	[" [6]", ""],
]

# キーの名前 → そのキーを送るボタンの名前(view/TouchControls.gd の並びと合わせる)
const KEYS := {
	"SPACE": "「植える」", "Q": "「水やり」", "E": "「収穫」", "Z": "「抜く」",
	"C": "「話す」", "B": "「市場」", "U": "「雪かき」", "K": "「ヒント」",
	"F": "メニューの「菜園」", "P": "メニューの「池」", "J": "メニューの「巣箱」",
	"L": "メニューの「餌台」", "X": "メニューの「剪定」", "V": "メニュー",
}

# H のボタンは家具のそばで「使う」に変わる。家具の話をしている行では、その名前で呼ぶ
const FURNITURE_WORDS := ["ストーブ", "ベッド", "腰掛け", "薪割り"]

static var _key_regex: RegEx

static func convert(text: String) -> String:
	if _key_regex == null:
		_key_regex = RegEx.create_from_string("(?<![A-Za-z0-9])(SPACE|[QEZHCBFPJLXUVK]) (?=[でを])")
	for p in PHRASES:
		text = text.replace(p[0], p[1])
	var lines := text.split("\n")
	for i in range(lines.size()):
		lines[i] = _convert_line(lines[i])
	return "\n".join(lines)

static func _convert_line(line: String) -> String:
	var matches := _key_regex.search_all(line)
	matches.reverse()  # 後ろから置き換えると、前の位置がずれない
	for m in matches:
		var start: int = m.get_start()
		# かぎかっこの前の空白は詰める。「小屋: 」のような見出しのあとだけ残す
		if start >= 2 and line[start - 1] == " " and line[start - 2] != ":":
			start -= 1
		line = line.substr(0, start) + _button_name(m.get_string(1), line) + line.substr(m.get_end())
	return line

static func _button_name(key: String, line: String) -> String:
	if key != "H":
		return KEYS[key]
	for word in FURNITURE_WORDS:
		if line.contains(word):
			return "「使う」"
	return "「小屋」"
