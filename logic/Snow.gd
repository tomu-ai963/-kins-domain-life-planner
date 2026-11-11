extends RefCounted

# ── 雪かき(描画を持たない) ─────────────────────────────────────
# 冬、足元の雪をどかして道を作る(CELL 四方のマスごと)。どかした道の上は速く歩ける。雪の上は今までどおりの速さ。
# 雪の日(Forest の発見の rain。冬は雪になる)に全部埋まり、冬が終わると消える。閉じていたあいだの雪も数える。
# 文言は Main、見た目は view/ が決める。座標の単位は m
const SaveRead = preload("res://logic/SaveRead.gd")
const Forest = preload("res://logic/Forest.gd")
const Land = preload("res://logic/Land.gd")
const Cabin = preload("res://logic/Cabin.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const CELL := 1.5           # どかすマスの大きさ(m)
const PATH_SPEED := 1.3     # どかした道の上を歩く速さの倍率(仮の数字)
const SHOVEL_SPEED := 0.5   # 雪かきしながら歩く速さの倍率(1 マスに約 0.6 秒。仮の数字)
const LIMIT := 78.0         # どかせる範囲(市場への道も作れるように、歩ける範囲と同じ)
const MAX_CATCH_UP_DAYS := 365

var forest: Forest  # GameWorld が設定する
var land: Land
var cabin: Cabin

var cells := {}             # どかしたマス {Vector2i: true}
var last_checked_day := 0   # 雪を数え終えた日
var last_fell := false      # 今日の確認で道が埋まったか(知らせる用・保存しない)

func _commit() -> void:
	dirty.emit()
	changed.emit()

static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))

static func center_of(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * CELL

# 雪をどかせるか(雪の積もる土地の冬だけ)
func can_clear_now() -> bool:
	return forest.season == "winter" and forest.snowy_winter()

func is_cleared(pos: Vector2) -> bool:
	return can_clear_now() and cells.has(cell_of(pos))

# そのマスは雪をどかせない場所か(区画・小屋・池の上と、歩ける範囲の外)
func _is_blocked(pos: Vector2) -> bool:
	if absf(pos.x) > LIMIT or absf(pos.y) > LIMIT:
		return true
	if land.plot_at(pos) != null or cabin.covers(pos):
		return true
	return land.pond != null and pos.distance_to(land.pond) < land.POND_RADIUS

# 足元の雪をどかす。結果: cleared / done / not_season / blocked
func clear_at(pos: Vector2) -> String:
	if not can_clear_now():
		return "not_season"
	if _is_blocked(pos):
		return "blocked"
	var c := cell_of(pos)
	if cells.has(c):
		return "done"
	cells[c] = true
	_commit()
	return "cleared"

# その日に道が埋まるか(雪の日か、冬でない日)
func _buries_on(day: int) -> bool:
	var date: String = Forest.date_of_day(day)
	if not forest.climate().is_snow_month(int(date.substr(5, 2))):
		return true
	return forest.roll_daily_event(date) == "rain"

# 日付が変わったときに呼ぶ。閉じていたあいだの雪も数える
func catch_up() -> void:
	advance_to(forest.day_number())

func advance_to(today: int) -> void:
	last_fell = false
	if last_checked_day <= 0:
		last_checked_day = today
		dirty.emit()
		return
	if today <= last_checked_day:
		return
	var from: int = maxi(last_checked_day + 1, today - MAX_CATCH_UP_DAYS + 1)
	var buried := false
	for d in range(from, today + 1):
		if _buries_on(d):
			buried = true
			break
	last_checked_day = today
	if buried and not cells.is_empty():
		cells.clear()
		last_fell = true
		_commit()
		return
	dirty.emit()

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	var list := []
	for c in cells:
		list.append([c.x, c.y])
	return {"cells": list, "last_checked_day": last_checked_day}

func from_save(d: Dictionary) -> void:
	cells.clear()
	for c in SaveRead.list(d.get("cells")):
		var v = SaveRead.pair(c)
		if v != null:
			cells[Vector2i(v)] = true
	last_checked_day = SaveRead.whole(d, "last_checked_day")
	changed.emit()
