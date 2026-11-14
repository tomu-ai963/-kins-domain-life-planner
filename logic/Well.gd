extends RefCounted

# ── 井戸(描画を持たない) ─────────────────────────────────────
# 場所を決める → 1 日 1 回掘る(DIG_DAYS 日) → 掘り終えると、いつでも水を汲める(冬も凍らない、汲んでも減らない)。
# ジョウロに汲むのは Tools、まとめて水をやる(エンジンポンプ)のは GameWorld。
# 井戸はひとつまで。掘りはじめる前なら Z で取り消せる。文言は Main、見た目は view/ が決める。座標の単位は m
const SaveRead = preload("res://logic/SaveRead.gd")
const Forest = preload("res://logic/Forest.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const DIG_DAYS := 3      # 掘る日数(手掘りの浅い井戸は現実では数週間。池の 5 日より短くした仮の数字)
const RADIUS := 0.8      # 井戸の石の縁の半径(m)
const REACH := 2.0       # 縁からこの距離までなら作業できる(池と同じ)
const WATER_RADIUS := 20.0  # ポンプでまとめて水をやれる距離(m)。池と同じ

var forest: Forest  # GameWorld が設定する
var is_blocked := Callable()  # GameWorld が設定する(区画・小屋・池・木・巣箱・餌台のそばと土地の端には掘れない)

var site = null       # 井戸の中心 Vector2。なければ null
var days_dug := 0
var last_dug := ""    # 最後に掘った日(YYYY-MM-DD)

func is_placed() -> bool:
	return site != null

func is_dug() -> bool:
	return is_placed() and days_dug >= DIG_DAYS

func dug_today() -> bool:
	return last_dug == forest.today()

func _commit() -> void:
	dirty.emit()
	changed.emit()

# 井戸のそば(縁から REACH まで)か。場所を決めただけでも true
func is_near(pos: Vector2) -> bool:
	return is_placed() and pos.distance_to(site) <= RADIUS + REACH

# 掘り終えた井戸のそばか(水を汲める)
func is_beside(pos: Vector2) -> bool:
	return is_dug() and is_near(pos)

# I: 井戸がなければ front に場所を決める。あれば今日の分を掘る
# 結果: placed / blocked(場所を決めるとき)、dug / finished / far / already / done_today(掘るとき)
func act(pos: Vector2, front: Vector2) -> String:
	if not is_placed():
		if is_blocked.is_valid() and is_blocked.call(front):
			return "blocked"
		site = front
		_commit()
		return "placed"
	if not is_near(pos):
		return "far"
	if is_dug():
		return "already"
	if dug_today():
		return "done_today"
	days_dug += 1
	last_dug = forest.today()
	_commit()
	return "finished" if is_dug() else "dug"

# 掘りはじめる前なら、場所を取り消せる。取り消したら true
func cancel(pos: Vector2) -> bool:
	if not is_near(pos) or days_dug > 0:
		return false
	site = null
	_commit()
	return true

# その場所に井戸がかかるか(radius は調べる範囲)。区画や木を置くときに見る
func covers(pos: Vector2, radius := 0.6) -> bool:
	return is_placed() and pos.distance_to(site) < radius + RADIUS

# 区画(中心 c・半分の幅 half)が井戸にかかるか
func blocks_plot(c: Vector2, half: float) -> bool:
	return is_placed() and absf(site.x - c.x) <= half + RADIUS and absf(site.y - c.y) <= half + RADIUS

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	var d := {"days_dug": days_dug, "last_dug": last_dug}
	if site != null:
		d["site"] = [site.x, site.y]
	return d

# 井戸の記録がないセーブ(2026-11-14 より前)は、井戸なしから
func from_save(d: Dictionary) -> void:
	site = SaveRead.pair(d.get("site"))
	days_dug = clampi(SaveRead.whole(d, "days_dug"), 0, DIG_DAYS) if site != null else 0
	last_dug = SaveRead.text(d, "last_dug") if site != null else ""
	changed.emit()
