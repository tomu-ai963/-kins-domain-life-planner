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
const STOOL_OFFSET := Vector2(-0.45, 0.75)  # テーブルの東の腰掛け
const STOOL_REACH := 0.55 # 腰掛けの中心からこの距離までなら座れる(部屋の真ん中は苗づくりに残す)
# 東の庭(小屋の外)。薪割り台と、壁際に積んだ薪の山を置く
const CHOP_OFFSET := Vector2(3.4, 0.7)
const CHOP_REACH := 1.4   # 薪割り台の中心からこの距離までなら割れる
const YARD_RECT := Rect2(2.0, -1.5, 2.2, 3.0)  # 小屋の中心からの範囲。区画や木を置かない

# ── 増築(2026-11-11 とむ決定) ──
# 完成した小屋の西に、もう 1 部屋(3m × 3m)を建て足す。市場で頼む(窓ガラス・かまど・釘の代金)と西に杭が立ち、
# 西の外から H で 1 日 1 回、丸太を使って建てる。できると小屋は 7m × 3m になり、窓辺の鉢が 12 に、鍋が 2 つ(かまど)になる。
# 家具(市場で買う)は新しい部屋(居間)に置く
const EXT_WIDTH := 3.0    # 増築する部屋の東西の幅(m)
const EXT_STAGES := [
	{"id": "foundation", "days": 1, "logs_per_day": 3},
	{"id": "walls", "days": 2, "logs_per_day": 4},
	{"id": "roof", "days": 1, "logs_per_day": 3},
]
const PASS_Z := -0.05     # 母屋と新しい部屋のあいだの出入り口の中心(南北。ベッドとテーブルのあいだ)
const PASS_W := 0.8       # 出入り口の幅(m)
const KAMADO_OFFSET := Vector2(-4.45, -1.0)  # 新しい部屋の北西のかまど(2 つ目の鍋)
const KAMADO_SIZE := Vector2(0.7, 0.7)
const KAMADO_REACH := 1.0
const CHAIR_OFFSET := Vector2(-3.0, 0.75)    # 揺り椅子
const CHAIR_REACH := 0.6
const SHELF_OFFSET := Vector2(-3.1, -1.22)   # 保存食の棚(北の壁際)
const SHELF_SIZE := Vector2(1.3, 0.3)
# 買える家具(市場の GOODS の species と同じ id)。新しい部屋ができてから置ける
const FURNITURE := ["shelf", "rocking_chair", "rug", "lamp", "clock"]

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
var ext_stage := -1          # 増築の段階。-1 = 頼んでいない / 0〜2 = 建てている / 3 = できた
var ext_days_done := 0       # 増築のいまの段階で作業した日数
var ext_last_worked := ""    # 増築の作業をした最後の日
var furniture := []          # 置いた家具の id(FURNITURE のうち)

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

# 完成した小屋の中にいるか(南のドアから歩いて入る)。西の部屋はできてから
func is_inside(pos: Vector2) -> bool:
	if not is_complete():
		return false
	return rect().has_point(pos) or (has_extension() and ext_rect().has_point(pos))

# 中でストーブの前にいるか
func is_at_stove(pos: Vector2) -> bool:
	return is_inside(pos) and pos.distance_to(site + STOVE_OFFSET) <= STOVE_REACH

# 中でベッドのそばにいるか
func is_at_bed(pos: Vector2) -> bool:
	return is_inside(pos) and Rect2(site + BED_OFFSET - BED_SIZE * 0.5, BED_SIZE).grow(BED_REACH).has_point(pos)

# 中で腰掛けのそばにいるか
func is_at_stool(pos: Vector2) -> bool:
	return is_inside(pos) and pos.distance_to(site + STOOL_OFFSET) <= STOOL_REACH

func chop_pos() -> Vector2:
	return site + CHOP_OFFSET

# 完成した小屋の外で、薪割り台のそばにいるか
func is_at_chop_block(pos: Vector2) -> bool:
	return is_complete() and not covers(pos) and pos.distance_to(chop_pos()) <= CHOP_REACH

# 東の庭にかかるか(木や巣箱を置かない)
func in_yard(pos: Vector2) -> bool:
	return site != null and Rect2(site + YARD_RECT.position, YARD_RECT.size).has_point(pos)

# ドアの位置(南の壁の真ん中)
func door_pos() -> Vector2:
	return site + Vector2(0.0, DEPTH * 0.5)

# 足元に立っているのが小屋の敷地か(木は植えられない)。増築を頼んだら西の部屋の場所も含む
func covers(pos: Vector2) -> bool:
	if site == null:
		return false
	return rect().has_point(pos) or (ext_started() and ext_rect().has_point(pos))

# 小屋が占める長方形(増築を頼んだら西の部屋も)。ほかの物を置かない範囲を調べる用
func footprints() -> Array:
	if site == null:
		return []
	return [rect(), ext_rect()] if ext_started() else [rect()]

# ── 増築 ──
func ext_started() -> bool:
	return ext_stage >= 0

func has_extension() -> bool:
	return ext_stage >= EXT_STAGES.size()

func ext_building() -> bool:
	return ext_started() and not has_extension()

func ext_rect() -> Rect2:
	return Rect2(site + Vector2(-WIDTH * 0.5 - EXT_WIDTH, -DEPTH * 0.5), Vector2(EXT_WIDTH, DEPTH))

func ext_current_stage() -> Dictionary:
	return EXT_STAGES[ext_stage] if ext_building() else {}

static func ext_total_logs() -> int:
	var n := 0
	for s in EXT_STAGES:
		n += int(s.days) * int(s.logs_per_day)
	return n

# 西の部屋を建てられない理由(建てられるなら "")。小屋が完成していないなら no_cabin、もう頼んでいれば exists。
# 巣箱・餌台など Cabin が知らない物は Market が調べる
func ext_problem() -> String:
	if not is_complete():
		return "no_cabin"
	if ext_started():
		return "exists"
	var r := ext_rect()
	var limit := land.HALF - EDGE_MARGIN
	if r.position.x < -limit:
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
	return ""

# 増築を頼む(お金は Market が払う)。西の部屋の場所に杭が立つ
func start_extension() -> void:
	ext_stage = 0
	ext_days_done = 0
	ext_last_worked = ""
	_commit()

# 西の外で、増築の作業ができる場所か(西の部屋のまわり REACH 以内で、母屋の外)
func is_at_ext_site(pos: Vector2) -> bool:
	return ext_building() and ext_rect().grow(REACH).has_point(pos) and not rect().has_point(pos)

# 増築の作業。結果: worked / stage_done / finished / none / inside / done_today / no_wood
func work_extension(pos: Vector2) -> String:
	if not ext_building():
		return "none"
	if ext_rect().grow(BODY_MARGIN).has_point(pos):
		return "inside"
	if ext_last_worked == forest.today():
		return "done_today"
	var s: Dictionary = EXT_STAGES[ext_stage]
	if int(materials.log) < int(s.logs_per_day):
		return "no_wood"
	materials.log -= int(s.logs_per_day)
	clamp_own_logs()
	ext_last_worked = forest.today()
	ext_days_done += 1
	var result := "worked"
	if ext_days_done >= int(s.days):
		ext_stage += 1
		ext_days_done = 0
		result = "finished" if has_extension() else "stage_done"
	_commit()
	return result

# 西の部屋の壁まで建っているか(当たり判定を付ける)
func ext_has_walls() -> bool:
	return ext_stage >= 2

# 中で、かまどの前にいるか
func is_at_kamado(pos: Vector2) -> bool:
	return has_extension() and is_inside(pos) and pos.distance_to(site + KAMADO_OFFSET) <= KAMADO_REACH

func has_furniture(id: String) -> bool:
	return id in furniture

# 家具を置く(お金は Market が払う)。結果: placed / no_room / owned / unknown
func add_furniture(id: String) -> String:
	if not (id in FURNITURE):
		return "unknown"
	if not has_extension():
		return "no_room"
	if has_furniture(id):
		return "owned"
	furniture.append(id)
	_commit()
	return "placed"

# 中で、揺り椅子のそばにいるか
func is_at_chair(pos: Vector2) -> bool:
	return has_furniture("rocking_chair") and is_inside(pos) and pos.distance_to(site + CHAIR_OFFSET) <= CHAIR_REACH

# 区画(中心 c)を置くと小屋にかかるか
func blocks_plot(c: Vector2) -> bool:
	if site == null:
		return false
	if ext_started() and ext_rect().intersects(_plot_rect(c)):
		return true
	return rect().intersects(_plot_rect(c)) or Rect2(site + YARD_RECT.position, YARD_RECT.size).intersects(_plot_rect(c))

# 池(中心 c)を掘ると小屋(東の庭を含む)にかかるか
func blocks_pond(c: Vector2) -> bool:
	if site == null:
		return false
	if ext_started() and _distance(ext_rect(), c) < land.POND_RADIUS:
		return true
	return _distance(rect(), c) < land.POND_RADIUS or _distance(Rect2(site + YARD_RECT.position, YARD_RECT.size), c) < land.POND_RADIUS

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
	var d := {"stage": stage, "days_done": days_done, "last_worked": last_worked, "logs": materials.log, "own_logs": own_logs,
		"ext_stage": ext_stage, "ext_days_done": ext_days_done, "ext_last_worked": ext_last_worked, "furniture": furniture}
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
	# 増築と家具の記録がないセーブ(2026-11-11 より前)は、増築なし・家具なし
	ext_stage = clampi(int(d.get("ext_stage", -1)), -1, EXT_STAGES.size())
	ext_days_done = int(d.get("ext_days_done", 0))
	ext_last_worked = str(d.get("ext_last_worked", ""))
	furniture = []
	var fl = d.get("furniture", [])
	if typeof(fl) == TYPE_ARRAY:
		for id in fl:
			if str(id) in FURNITURE and not (str(id) in furniture):
				furniture.append(str(id))
	changed.emit()
