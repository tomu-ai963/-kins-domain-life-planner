extends RefCounted

# ── ムクドリの巣箱(描画を持たない) ─────────────────────────────
# 丸太 1 本から、1 日 1 回・3 日かけて小鳥の巣箱を作り、育った木の幹に掛ける(2026-11-11 とむ決定)。
# ロシアでは冬の終わりにムクドリの巣箱(スクヴォレーチニク)を作って掛け、春に渡ってくるのを待つ習慣がある。
# 掛け終えた巣箱には、春と夏にムクドリのつがいが来る(数は Wildlife が決める)。見て楽しむもので、ルールには関わらない。
# 巣箱は木の位置で覚える。その木を伐ると巣箱もなくなる。文言は Main、見た目は view/ が決める。座標の単位は m
const Forest = preload("res://logic/Forest.gd")
const Cabin = preload("res://logic/Cabin.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const MAX_BOXES := 3     # 巣箱の数の上限
const LOG_COST := 1      # 巣箱 1 つに使う丸太(市場の丸太でもよい)
const WORK_DAYS := 3     # 作る日数(1 日 1 回)
const REACH := 1.6       # 木の幹からこの距離までなら作業できる
const MIN_RADIUS := 0.8  # 掛けられる木の樹冠の半径(m)。白樺なら幹の高さ 1.8m ほど
const SAME_SPOT := 0.05  # 木と巣箱の位置がこれより近ければ同じ木(セーブで小数が丸まっても見つかるように)
const SEASONS := ["spring", "summer"]  # ムクドリが巣箱にいる季節(春に渡ってきて、夏にひなが巣立つ)

var forest: Forest  # GameWorld が設定する
var cabin: Cabin

var boxes := []     # [{pos: Vector2(木の位置), days_done: int, last_worked: String}]
var last_box := {}  # 直前に作業した巣箱(文言用)

func _commit() -> void:
	dirty.emit()
	changed.emit()

func is_done(b: Dictionary) -> bool:
	return int(b.days_done) >= WORK_DAYS

func done_count() -> int:
	return boxes.filter(func(b): return is_done(b)).size()

func worked_today(b: Dictionary) -> bool:
	return b.last_worked == forest.today()

# 巣箱を掛けられる木か(根付いていて、幹が育っている)
func can_hold(tree: Dictionary) -> bool:
	return forest.is_established(tree) and forest.radius_of(tree) >= MIN_RADIUS

# pos のそばの、巣箱を掛けられる木(なければ空)
func tree_near(pos: Vector2) -> Dictionary:
	var i: int = forest.nearest_index(pos, REACH, "")
	if i < 0 or not can_hold(forest.trees[i]):
		return {}
	return forest.trees[i]

# その木の巣箱(なければ空)
func box_on(tree_pos: Vector2) -> Dictionary:
	for b in boxes:
		if b.pos.distance_to(tree_pos) < SAME_SPOT:
			return b
	return {}

# pos のそばに巣箱の作業ができる木があるか(L を巣箱と餌台のどちらに使うかを Main が決める)
func is_near(pos: Vector2) -> bool:
	return not tree_near(pos).is_empty()

# 伐った木の巣箱をなくす。なくしたら true
func drop_missing() -> bool:
	var before := boxes.size()
	boxes = boxes.filter(func(b): return forest.trees.any(func(t): return t.pos.distance_to(b.pos) < SAME_SPOT))
	if boxes.size() == before:
		return false
	_commit()
	return true

# L: そばの木で巣箱を作りはじめる / 続きを作る。
# 結果: started / worked / finished / no_tree / done / done_today / too_many / no_wood
func act(pos: Vector2) -> String:
	drop_missing()
	var tree := tree_near(pos)
	if tree.is_empty():
		return "no_tree"
	var b := box_on(tree.pos)
	if b.is_empty():
		if boxes.size() >= MAX_BOXES:
			return "too_many"
		if int(cabin.materials.log) < LOG_COST:
			return "no_wood"
		cabin.materials.log = int(cabin.materials.log) - LOG_COST
		cabin.clamp_own_logs()
		b = {"pos": tree.pos, "days_done": 1, "last_worked": forest.today()}
		boxes.append(b)
		last_box = b
		_commit()
		return "finished" if is_done(b) else "started"
	last_box = b
	if is_done(b):
		return "done"
	if worked_today(b):
		return "done_today"
	b.days_done = int(b.days_done) + 1
	b.last_worked = forest.today()
	_commit()
	return "finished" if is_done(b) else "worked"

# 今、巣箱にムクドリが来ている数(つがい = 2 羽 × 掛け終えた巣箱)。時間帯は Wildlife が見る
func starlings() -> int:
	if not (forest.season in SEASONS):
		return 0
	return 2 * done_count()

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	var list := []
	for b in boxes:
		list.append({"x": b.pos.x, "y": b.pos.y, "days_done": b.days_done, "last_worked": b.last_worked})
	return {"boxes": list}

func from_save(d: Dictionary) -> void:
	boxes.clear()
	for b in d.get("boxes", []):
		if typeof(b) == TYPE_DICTIONARY and b.has("x") and b.has("y"):
			boxes.append({
				"pos": Vector2(float(b.x), float(b.y)),
				"days_done": clampi(int(b.get("days_done", 0)), 0, WORK_DAYS),
				"last_worked": str(b.get("last_worked", "")),
			})
	changed.emit()
