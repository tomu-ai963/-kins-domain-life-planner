extends RefCounted

# ── 自分(プレイヤー)の名前と性別(描画を持たない。2026-11-16) ──────────────────
# ゲームのいちばんはじめ(自分の記録がないセーブを開いたときも)に一度だけ決める。
# 名前は 1〜NAME_MAX 文字で、あとから付け直せる(rename)。性別は m(男性)/ f(女性)/ ""(決めない)で、あとから変えられない(とむ決定)。
# 名前は日記の見出し・持ち物・家族と近所の人の言葉に使う(文言は Main)。性別は見た目(髪)と、子どもの呼び方(お母さん / お父さん)に使う
const SaveRead = preload("res://logic/SaveRead.gd")
const Family = preload("res://logic/Family.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const NAME_MAX := Family.NAME_MAX   # 家族の名前と同じ 8 文字
const SEXES := ["m", "f", ""]       # 男性・女性・決めない
const SEX_NAMES := {"m": "男性", "f": "女性", "": "決めない"}

var chosen := false
var name := ""
var sex := ""

func _commit() -> void:
	changed.emit()
	dirty.emit()

# 名前と性別を決める(一度だけ)。結果: chosen / already / empty / too_long / unknown(知らない性別)
func choose(new_name: String, new_sex: String) -> String:
	if chosen:
		return "already"
	if not new_sex in SEXES:
		return "unknown"
	var n := Family.clean_name(new_name)
	if n == "":
		return "empty"
	if n.length() > NAME_MAX:
		return "too_long"
	name = n
	sex = new_sex
	chosen = true
	_commit()
	return "chosen"

# 名前を付け直す。結果: renamed / same / empty / too_long / unknown(まだ決めていない)
func rename(new_name: String) -> String:
	if not chosen:
		return "unknown"
	var n := Family.clean_name(new_name)
	if n == "":
		return "empty"
	if n.length() > NAME_MAX:
		return "too_long"
	if n == name:
		return "same"
	name = n
	_commit()
	return "renamed"

# 子どもの呼び方(性別を決めないときは "")
func parent_word() -> String:
	return {"m": "お父さん", "f": "お母さん"}.get(sex, "")

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	return {"chosen": chosen, "name": name, "sex": sex}

# 自分の記録がないセーブ(2026-11-16 より前)は、まだ決めていない(開いたときに一度だけ決める)
func from_save(d: Dictionary) -> void:
	var n := Family.clean_name(SaveRead.text(d, "name"))
	chosen = SaveRead.flag(d, "chosen", false) and n != "" and n.length() <= NAME_MAX
	name = n if chosen else ""
	sex = SaveRead.text(d, "sex") if chosen and SaveRead.text(d, "sex") in SEXES else ""
	changed.emit()
