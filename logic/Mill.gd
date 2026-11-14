extends RefCounted

# ── 石臼と粉(描画を持たない) ──────────────────────────────────
# 畑で採れた穀物(小麦・ライ麦・ソバ・キビ)を、石臼で挽いて粉にする(2026-11-14)。
# 石臼は市場で買い、土地の好きな場所に置く(O)。そばで O を押すと手で挽く: 1 回 1kg、1 日 HAND_KG_PER_DAY kg まで(腕が疲れる)。
# 製粉機(市場で買う。ガソリンで動く)があれば、持っている穀物を一度に全部挽く。
# 粉は全粒粉として、穀物 1kg から 1kg(ふすまを除かない)。粉は市場で売れて、ストーブで料理に使える。
# 置き場所・道具の持ち物は Tools、文言は Main、見た目は view/ が決める。座標の単位は m
const SaveRead = preload("res://logic/SaveRead.gd")
const Forest = preload("res://logic/Forest.gd")
const Garden = preload("res://logic/Garden.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

const GRIND_KG := 1          # 手で 1 回に挽く量(kg)
const HAND_KG_PER_DAY := 5   # 手で 1 日に挽ける量(kg)。手回しの石臼は 1 時間に 1〜2kg ほど
const ENGINE_MAX_KG := 50    # 製粉機で 1 回に挽ける量(kg)
const RADIUS := 0.5          # 石臼の台の半径(m)
const REACH := 2.0           # 台からこの距離までなら作業できる
# 挽ける穀物 → 粉の名前(挽く順番もこの順)
const FLOURS := {
	"wheat": {"name": "小麦粉"},
	"rye": {"name": "ライ麦粉"},
	"soba": {"name": "そば粉"},
	"kibi": {"name": "きび粉"},
}

var forest: Forest  # GameWorld が設定する
var garden: Garden  # GameWorld が設定する(穀物の持ち物は Garden にある)
var tools = null    # GameWorld が設定する(石臼と製粉機を持っているか・ガソリン)
var is_blocked := Callable()  # GameWorld が設定する(区画・小屋・池・木・巣箱・餌台・井戸のそばと土地の端には置けない)

var site = null       # 石臼の場所 Vector2。置く前は null
var flour := {}       # 粉の持ち物 {穀物の id: kg}
var hand_day := ""    # 手で挽いた日(YYYY-MM-DD)
var hand_kg := 0      # その日に手で挽いた量(kg)
var last_ground := {} # 直前に挽いた {穀物の id: kg}(文言用・保存しない)

func _init() -> void:
	flour = _zero_counts()

static func _zero_counts() -> Dictionary:
	var d := {}
	for k in FLOURS:
		d[k] = 0
	return d

static func flour_id(grain: String) -> String:
	return "flour_" + grain

func _commit() -> void:
	dirty.emit()
	changed.emit()

func is_placed() -> bool:
	return site != null

func is_near(pos: Vector2) -> bool:
	return is_placed() and pos.distance_to(site) <= RADIUS + REACH

# 今日あと何 kg 手で挽けるか
func hand_left() -> int:
	if hand_day != forest.today():
		return HAND_KG_PER_DAY
	return maxi(0, HAND_KG_PER_DAY - hand_kg)

# 持っている穀物(kg)
func grain_count(grain: String) -> int:
	return int(garden.produce.get(grain, 0))

func total_grain() -> int:
	var n := 0
	for g in FLOURS:
		n += grain_count(g)
	return n

# 挽く穀物。prefer を持っていればそれ、なければ FLOURS の順で最初に持っているもの。なければ ""
func pick_grain(prefer := "") -> String:
	if FLOURS.has(prefer) and grain_count(prefer) > 0:
		return prefer
	for g in FLOURS:
		if grain_count(g) > 0:
			return g
	return ""

# O: 石臼がなければ front に置く(市場で買ってあれば)。あれば挽く
# 結果: placed / no_quern / blocked(置くとき)、Mill.grind の結果(挽くとき)
func act(pos: Vector2, front: Vector2, prefer := "") -> String:
	if not is_placed():
		if not tools.has("quern"):
			return "no_quern"
		if is_blocked.is_valid() and is_blocked.call(front):
			return "blocked"
		site = front
		_commit()
		return "placed"
	return grind(pos, prefer)

# 石臼のそばで挽く。製粉機を動かせれば全部を一度に、なければ手で 1kg。
# 結果: ground / engine / far / no_grain / tired(今日はもう手で挽けない)
func grind(pos: Vector2, prefer := "") -> String:
	last_ground = {}
	if not is_near(pos):
		return "far"
	if total_grain() <= 0:
		return "no_grain"
	if tools.can_run("mill"):
		tools.use_gas("mill")
		var left := ENGINE_MAX_KG
		for g in FLOURS:
			var n: int = mini(grain_count(g), left)
			if n > 0:
				_turn(g, n)
				left -= n
		_commit()
		return "engine"
	if hand_left() <= 0:
		return "tired"
	var grain := pick_grain(prefer)
	if hand_day != forest.today():
		hand_day = forest.today()
		hand_kg = 0
	var kg: int = mini(GRIND_KG, grain_count(grain))
	_turn(grain, kg)
	hand_kg += kg
	_commit()
	return "ground"

func _turn(grain: String, kg: int) -> void:
	garden.produce[grain] = grain_count(grain) - kg
	flour[grain] = int(flour[grain]) + kg
	last_ground[grain] = int(last_ground.get(grain, 0)) + kg

# その場所に石臼がかかるか(radius は調べる範囲)。区画や木を置くときに見る
func covers(pos: Vector2, radius := 0.6) -> bool:
	return is_placed() and pos.distance_to(site) < radius + RADIUS

# 区画(中心 c・半分の幅 half)が石臼にかかるか
func blocks_plot(c: Vector2, half: float) -> bool:
	return is_placed() and absf(site.x - c.x) <= half + RADIUS and absf(site.y - c.y) <= half + RADIUS

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	var d := {"flour": flour, "hand_day": hand_day, "hand_kg": hand_kg}
	if site != null:
		d["site"] = [site.x, site.y]
	return d

# 石臼の記録がないセーブ(2026-11-14 より前)は、石臼なし・粉なしから
func from_save(d: Dictionary) -> void:
	site = SaveRead.pair(d.get("site"))
	flour = _zero_counts()
	var fd := SaveRead.dict(d.get("flour"))
	for g in FLOURS:
		flour[g] = SaveRead.count(fd, g)
	hand_day = SaveRead.text(d, "hand_day")
	hand_kg = clampi(SaveRead.whole(d, "hand_kg"), 0, HAND_KG_PER_DAY)
	changed.emit()
