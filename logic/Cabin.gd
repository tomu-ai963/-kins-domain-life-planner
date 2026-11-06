extends RefCounted

# ── 小屋(描画を持たない) ─────────────────────────────────────
# 丸太を集め(市場で買う / 育った木を伐る)、基礎 → 壁 → 屋根と何日かかけて建てる。小屋はひとつまで。
# 作業は暦の 1 日に 1 回、外から行う。1 回ごとにその段階の丸太を使う。
# 文言は Main、値段は Market、見た目は view/ が決める。座標の単位は m
const Forest = preload("res://logic/Forest.gd")
const Land = preload("res://logic/Land.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const WIDTH := 4.0   # 東西の幅(m)。12m² の小さな小屋
const DEPTH := 3.0   # 南北の奥行き(m)
const REACH := 2.0   # 小屋からこの距離までなら作業できる
const BODY_MARGIN := 0.5  # 壁ができたときに閉じ込められないよう、これより内側では作業しない
const EDGE_MARGIN := 3.0  # 境界からこの幅は生垣クエストのために空ける(Quests.HEDGE_BAND と同じ)
const CENTER_CLEAR := 5.0 # 中心からこの範囲は家族の杉のために空ける(Quests.FAMILY_CEDAR_RADIUS と同じ)
const TREE_CLEARANCE := 0.3  # 小屋の周りでこの距離に木があると建てられない

# 部屋の家具(小屋の中心からの位置 m)。使える範囲はロジック、形は view/ が同じ値を読む
const STOVE_OFFSET := Vector2(1.45, -1.0)
const STOVE_SIZE := Vector2(0.7, 0.7)
const STOVE_REACH := 1.1  # ストーブの中心からこの距離までなら使える(東の窓辺は苗づくりに残す)
const BED_OFFSET := Vector2(-0.9, -0.95)
const BED_SIZE := Vector2(1.9, 0.85)
const BED_REACH := 0.5    # ベッドの縁からこの距離までなら使える(部屋の真ん中は苗づくりに残す)

# days: 作業する日数 / logs_per_day: 1 回の作業で使う丸太(1 本 = 長さ 3m・径 20cm ほど = 約 0.1m³)
const STAGES := [
	{"id": "foundation", "days": 2, "logs_per_day": 3},
	{"id": "walls", "days": 3, "logs_per_day": 5},
	{"id": "roof", "days": 2, "logs_per_day": 4},
]

var forest: Forest  # GameWorld が設定する
var land: Land

var site = null          # 小屋の中心 Vector2。まだ場所を決めていなければ null
var stage := 0           # いまの段階(0〜2)。3 で完成
var days_done := 0       # いまの段階で作業した日数
var last_worked := ""    # 最後に作業した日(YYYY-MM-DD)
var materials := {"log": 0}  # 丸太の本数(市場の GOODS から買い足せるよう Dictionary にする)
var own_logs := 0            # そのうち、自分の木を伐った丸太の本数(巣箱に使う)。小屋や薪には市場の丸太を先に使う

static func total_logs() -> int:
	var n := 0
	for s in STAGES:
		n += int(s.days) * int(s.logs_per_day)
	return n

static func total_days() -> int:
	var n := 0
	for s in STAGES:
		n += int(s.days)
	return n

func is_complete() -> bool:
	return stage >= STAGES.size()

# 自分の木を伐った丸太の本数(丸太全体より多くはならない)
func own_log_count() -> int:
	return mini(own_logs, int(materials.log))

# 自分の木の丸太を使う(巣箱)
func spend_own_logs(n: int) -> void:
	own_logs = own_log_count() - n
	materials.log = int(materials.log) - n

# 丸太全体が減ったあとに呼ぶ(市場の丸太から先に使ったことにする)
func clamp_own_logs() -> void:
	own_logs = own_log_count()

# 壁まで建っているか(当たり判定を付ける)
func has_walls() -> bool:
	return stage >= 2

func current_stage() -> Dictionary:
	return {} if is_complete() else STAGES[stage]

func worked_today() -> bool:
	return last_worked == forest.today()

func _commit() -> void:
	dirty.emit()
	changed.emit()

func rect_at(center: Vector2) -> Rect2:
	return Rect2(center - Vector2(WIDTH, DEPTH) * 0.5, Vector2(WIDTH, DEPTH))

func rect() -> Rect2:
	return rect_at(site)

# 長方形から点までの距離(中なら 0)
static func _distance(r: Rect2, p: Vector2) -> float:
	return p.distance_to(p.clamp(r.position, r.end))

# 足元を中心に、建てる場所を決める。結果: placed / exists / edge / center / pond / plot / tree
func place(pos: Vector2) -> String:
	if site != null:
		return "exists"
	var c := pos.round()
	var r := rect_at(c)
	var limit := land.HALF - EDGE_MARGIN
	if r.position.x < -limit or r.end.x > limit or r.position.y < -limit or r.end.y > limit:
		return "edge"
	if _distance(r, Vector2.ZERO) < CENTER_CLEAR:
		return "center"
	if land.pond != null and _distance(r, land.pond) < land.POND_RADIUS:
		return "pond"
	for p in land.plots:
		if r.intersects(_plot_rect(p)):
			return "plot"
	for t in forest.trees:
		if _distance(r, t.pos) < TREE_CLEARANCE:
			return "tree"
	site = c
	_commit()
	return "placed"

func _plot_rect(center: Vector2) -> Rect2:
	var s: float = land.PLOT_SIZE
	return Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s))

# 足元で作業する。結果: worked / stage_done / finished / none / complete / far / inside / done_today / no_wood
func work(pos: Vector2) -> String:
	if site == null:
		return "none"
	if is_complete():
		return "complete"
	if not is_near(pos):
		return "far"
	if rect().grow(BODY_MARGIN).has_point(pos):
		return "inside"
	if worked_today():
		return "done_today"
	var s: Dictionary = STAGES[stage]
	if int(materials.log) < int(s.logs_per_day):
		return "no_wood"
	materials.log -= int(s.logs_per_day)
	clamp_own_logs()
	last_worked = forest.today()
	days_done += 1
	var result := "worked"
	if days_done >= int(s.days):
		stage += 1
		days_done = 0
		result = "finished" if is_complete() else "stage_done"
	_commit()
	return result

func is_near(pos: Vector2) -> bool:
	return site != null and rect().grow(REACH).has_point(pos)

# 完成した小屋の中にいるか(南のドアから歩いて入る)
func is_inside(pos: Vector2) -> bool:
	return is_complete() and covers(pos)

# 中でストーブの前にいるか
func is_at_stove(pos: Vector2) -> bool:
	return is_inside(pos) and pos.distance_to(site + STOVE_OFFSET) <= STOVE_REACH

# 中でベッドのそばにいるか
func is_at_bed(pos: Vector2) -> bool:
	return is_inside(pos) and Rect2(site + BED_OFFSET - BED_SIZE * 0.5, BED_SIZE).grow(BED_REACH).has_point(pos)

# ドアの位置(南の壁の真ん中)
func door_pos() -> Vector2:
	return site + Vector2(0.0, DEPTH * 0.5)

# 足元に立っているのが小屋の敷地か(木は植えられない)
func covers(pos: Vector2) -> bool:
	return site != null and rect().has_point(pos)

# 区画(中心 c)を置くと小屋にかかるか
func blocks_plot(c: Vector2) -> bool:
	return site != null and rect().intersects(_plot_rect(c))

# 池(中心 c)を掘ると小屋にかかるか
func blocks_pond(c: Vector2) -> bool:
	return site != null and _distance(rect(), c) < land.POND_RADIUS

# 作業を始める前なら、場所を取り消せる(丸太を使っていないので損はない)。取り消したら true
func cancel(pos: Vector2) -> bool:
	if not is_near(pos) or stage > 0 or days_done > 0:
		return false
	site = null
	_commit()
	return true

# 足元の木を伐る。採れた丸太の本数を返す(小さくて木材にならなければ 0、近くに木がなければ -1)
func fell(pos: Vector2, max_dist: float) -> int:
	var i: int = forest.nearest_index(pos, max_dist, "")
	if i < 0:
		return -1
	var n: int = forest.wood_yield(forest.trees[i])
	materials.log += n
	own_logs += n
	forest.remove_nearest(pos, max_dist)  # ここで保存される
	changed.emit()
	return n

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	var d := {"stage": stage, "days_done": days_done, "last_worked": last_worked, "logs": materials.log, "own_logs": own_logs}
	if site != null:
		d["site"] = [site.x, site.y]
	return d

func from_save(d: Dictionary) -> void:
	site = null
	var s = d.get("site", null)
	if typeof(s) == TYPE_ARRAY and s.size() == 2:
		site = Vector2(float(s[0]), float(s[1]))
	stage = int(d.get("stage", 0))
	days_done = int(d.get("days_done", 0))
	last_worked = str(d.get("last_worked", ""))
	materials = {"log": int(d.get("logs", 0))}
	own_logs = int(d.get("own_logs", 0))  # 記録がないセーブの丸太は、どこから来たか分からないので自分の木に数えない
	changed.emit()
