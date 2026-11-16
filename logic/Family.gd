extends RefCounted

# ── 家族(描画を持たない。2026-11-16) ──────────────────────────────
# ゲームのはじめ(家族の記録がないセーブを開いたときも)に一度だけ、配偶者と子どもの人数を選ぶ。あとから変えられない。
# 家族は最初から土地で暮らす。小屋が完成するまでは、夜はテントで休む(テントの場所はここで決める)。
# 毎朝(日付が変わった最初の確認で)小さな手伝いをする:
#   配偶者: 水のいる区画か木に WATER_HELP か所まで水をやる(井戸・池・川のどれかで汲めるときだけ。雨の日は要らない)
#   子ども: HELP_AGE 歳から、雑草の生えた区画を 1 つ抜く(WEED_MORE_AGE 歳から 2 つ)
# 話しかける(C)と、その日はじめてのときに GIFT_CHANCE で贈り物をくれる(配偶者は料理、子どもは拾った木の種)。
# 子どもは AGE_DAYS 日で 1 歳育ち、ADULT_AGE で止まる(木は 1 日 1 年だが、人は一月で 1 歳にした。仮の数字)。
# 文言は Main、姿と歩く道は view/3d/FamilyView3D.gd が決める
const SaveRead = preload("res://logic/SaveRead.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

# 選べる配偶者。sex は服と呼び方(妻 / 夫)だけに使う
const SPOUSES := {
	"alyona": {"name": "アリョーナ", "sex": "f", "relation": "妻"},
	"vera": {"name": "ヴェーラ", "sex": "f", "relation": "妻"},
	"ilya": {"name": "イリヤ", "sex": "m", "relation": "夫"},
	"mikhail": {"name": "ミハイル", "sex": "m", "relation": "夫"},
}
const SPOUSE_ORDER := ["alyona", "vera", "ilya", "mikhail"]
# 子どもは人数だけ選ぶ。上の子から順にこの並び(名前と、はじめの年齢)
const CHILDREN := [
	{"id": "vanya", "name": "ワーニャ", "sex": "m", "relation": "息子", "age": 9},
	{"id": "masha", "name": "マーシャ", "sex": "f", "relation": "娘", "age": 6},
	{"id": "polya", "name": "ポーリャ", "sex": "f", "relation": "娘", "age": 3},
]
const MAX_CHILDREN := 3

const AGE_DAYS := 30          # 子どもが 1 歳育つ日数(仮の数字)
const ADULT_AGE := 18         # ここで育つのを止める
const HELP_AGE := 6           # 子どもが雑草を抜きはじめる年齢
const WEED_MORE_AGE := 10     # この年齢から 1 日 2 区画
const WATER_HELP := 3         # 配偶者が 1 日に水をやる区画と木の数
const GIFT_CHANCE := 0.3      # 話しかけた日に贈り物をくれる割合(1 人 1 日 1 回まで)
const SPOUSE_GIFTS := {       # 配偶者の贈り物(季節の料理。品と数)
	"spring": {"item": "bliny", "count": 3},
	"summer": {"item": "pirozhki", "count": 3},
	"autumn": {"item": "jam", "count": 1},
	"winter": {"item": "sbiten", "count": 2},
}
const CHILD_GIFT_SEEDS := 2   # 子どもが拾ってくる木の種の数
const TENT_RADIUS := 1.2      # テントの大きさ(中心からの半径。区画や池をここに置けない)
const TENT_CLEARANCE := 1.4   # テントの中心から、まわりの物までこれだけ空ける
const TENT_SEARCH := 30.0     # テントの場所を探す範囲(目安の場所からの距離)
const CENTER_CLEAR := 5.0     # 中心は家族の杉のために空ける(Quests.FAMILY_CEDAR_RADIUS と同じ)

var forest = null        # GameWorld が設定する
var garden = null
var cabin = null
var market = null
var is_blocked: Callable  # 物を置けない場所か(Bees.is_blocked。GameWorld が設定する)
var can_draw_water: Callable  # 手伝いの水を汲めるか(GameWorld が設定する)

var chosen := false      # 家族を決めたか(決める前は誰もいない)
var members := []        # [{id, name, sex, relation, role: spouse/child, age(はじめの年齢), joined_day}]
var tent = null          # テントの中心 Vector2(小屋が完成するまで)。まだなければ null
var talked := {}         # 人ごとに、最後に話しかけた日の通し番号
var helped_day := -1     # 最後に手伝った日
var last_help := []      # 今朝の手伝い [{who, kind: water/weed, pos}](文言と姿の動き用。保存しない)
var last_gift := {}      # 直前にもらった贈り物 {who, type, item/species, count}(文言用)

func _commit() -> void:
	changed.emit()
	dirty.emit()

func day_number() -> int:
	return forest.day_number()

# 家族を決める(一度だけ)。spouse は SPOUSES の id か ""(いない)。結果: chosen / already / unknown
func choose(spouse: String, children: int) -> String:
	if chosen:
		return "already"
	if spouse != "" and not SPOUSES.has(spouse):
		return "unknown"
	if children < 0 or children > MAX_CHILDREN:
		return "unknown"
	members.clear()
	var today := day_number()
	if spouse != "":
		var s: Dictionary = SPOUSES[spouse]
		members.append({"id": spouse, "name": s.name, "sex": s.sex, "relation": s.relation, "role": "spouse", "age": ADULT_AGE, "joined_day": today})
	for i in range(children):
		var c: Dictionary = CHILDREN[i]
		members.append({"id": c.id, "name": c.name, "sex": c.sex, "relation": c.relation, "role": "child", "age": c.age, "joined_day": today})
	chosen = true
	ensure_tent()
	_commit()
	return "chosen"

func member(id: String) -> Dictionary:
	for m in members:
		if m.id == id:
			return m
	return {}

func spouse() -> Dictionary:
	for m in members:
		if m.role == "spouse":
			return m
	return {}

func children() -> Array:
	return members.filter(func(m): return m.role == "child")

# 今の年齢(子どもは AGE_DAYS 日で 1 歳。ADULT_AGE で止まる)
func age_of(m: Dictionary) -> int:
	if m.role != "child":
		return int(m.age)
	var grown: int = int(maxi(0, day_number() - int(m.joined_day)) / float(AGE_DAYS))
	return mini(ADULT_AGE, int(m.age) + grown)

# ── 毎朝の手伝い ──────────────────────────────────────────
# 日付が変わった最初の確認で呼ぶ(GameWorld.check_new_day)。手伝ったら true。同じ日に 2 回はしない
func help_today() -> bool:
	last_help = []
	var today := day_number()
	if not chosen or today <= helped_day:
		return false
	helped_day = today
	var s := spouse()
	if not s.is_empty() and (not can_draw_water.is_valid() or can_draw_water.call()):
		_water_help(s.id)
	for c in children():
		var age := age_of(c)
		if age >= HELP_AGE:
			_weed_help(c.id, 2 if age >= WEED_MORE_AGE else 1)
	dirty.emit()
	if not last_help.is_empty():
		changed.emit()
	return not last_help.is_empty()

# 水のいる区画を先に、次に木へ、合わせて WATER_HELP か所まで
func _water_help(who: String) -> void:
	var left := WATER_HELP
	for c in garden.crops:
		if left <= 0:
			return
		if garden.is_ripe(c) or garden.watered_today(c):
			continue
		if garden.water_at(c.pos) == "watered":
			last_help.append({"who": who, "kind": "water", "pos": c.pos})
			left -= 1
	for t in forest.trees:
		if left <= 0:
			return
		if not forest.is_established(t) or forest.watered_today(t):
			continue
		if forest.water_nearest(t.pos, 0.05) == "watered":
			last_help.append({"who": who, "kind": "water", "pos": t.pos})
			left -= 1

func _weed_help(who: String, count: int) -> void:
	for c in garden.crops:
		if count <= 0:
			return
		if garden.has_weeds(c) and garden.weed_at(c.pos) == "weeded":
			last_help.append({"who": who, "kind": "weed", "pos": c.pos})
			count -= 1

# 今朝の手伝いを人ごとにまとめる {who: {water: n, weed: n}}(文言用)
func help_summary() -> Dictionary:
	var out := {}
	for h in last_help:
		if not out.has(h.who):
			out[h.who] = {"water": 0, "weed": 0}
		out[h.who][h.kind] += 1
	return out

# ── 話す・贈り物 ──────────────────────────────────────────
# 話しかけた。その日はじめてなら、ときどき贈り物をくれる(受け取ったものは持ち物に入る)。
# 結果: gift(贈り物をもらった) / chat / none(その人がいない)
func talk(id: String) -> String:
	var m := member(id)
	if m.is_empty():
		return "none"
	var today := day_number()
	var first: bool = int(talked.get(id, -1)) < today
	talked[id] = today
	last_gift = {}
	if first and _gift_roll(id, today):
		last_gift = _make_gift(m)
		if not last_gift.is_empty():
			_receive(last_gift)
	dirty.emit()
	if not last_gift.is_empty():
		changed.emit()
		return "gift"
	return "chat"

func talked_today(id: String) -> bool:
	return int(talked.get(id, -1)) == day_number()

# 贈り物をくれる日か(日付と人で決まる。開き直しても変わらない)
static func _gift_roll(id: String, day: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("family_gift:%s:%d" % [id, day]).hash()
	return rng.randf() < GIFT_CHANCE

# 話す言葉を選ぶ数(日付と人で決まる)
func line_index(id: String) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("family_line:%s:%d" % [id, day_number()]).hash()
	return rng.randi_range(0, 99)

func _make_gift(m: Dictionary) -> Dictionary:
	if m.role == "spouse":
		var g: Dictionary = SPOUSE_GIFTS.get(forest.season, SPOUSE_GIFTS.autumn)
		return {"who": m.id, "type": "item", "item": g.item, "count": g.count}
	if age_of(m) < HELP_AGE - 2:
		return {}  # 小さい子は拾いに行かない
	# 子どもは、その土地で育つ木の種を拾ってくる(秋は木の実、ほかの季節は風で飛ぶ種)
	var species: String = forest.nut_seed() if forest.season == "autumn" else forest.wind_seed()
	return {"who": m.id, "type": "tree_seed", "species": species, "count": CHILD_GIFT_SEEDS}

func _receive(g: Dictionary) -> void:
	match g.type:
		"item":
			var pile: Dictionary = market.pile_of(g.item)
			var key: String = market.key_of(g.item)
			pile[key] = int(pile.get(key, 0)) + int(g.count)
			market.changed.emit()
		"tree_seed":
			forest.seeds[g.species] = int(forest.seeds.get(g.species, 0)) + int(g.count)
			forest.changed.emit()

# ── 家(夜に休む場所) ──────────────────────────────────────
# 夜に帰る場所: 小屋が完成していれば小屋の戸口、まだならテントの入口。家族がいなければ null
func home_pos():
	if not chosen or members.is_empty():
		return null
	if cabin.is_complete():
		return cabin.door_pos()
	ensure_tent()
	return tent + Vector2(0, TENT_RADIUS + 0.4) if tent != null else null

func has_tent() -> bool:
	return chosen and not members.is_empty() and tent != null and not cabin.is_complete()

# テントの場所を決める・確かめる。小屋が完成したら片付ける。あとから物が置かれてかかったら、場所を移す
func ensure_tent() -> void:
	if not chosen or members.is_empty() or cabin.is_complete():
		if tent != null:
			tent = null
			_commit()
		return
	if tent != null and _tent_fits(tent):
		return
	var spot = _find_tent_spot()
	if spot != tent:
		tent = spot
		_commit()

func _tent_fits(p: Vector2) -> bool:
	if p.length() < CENTER_CLEAR + TENT_CLEARANCE:
		return false
	var keep = tent
	tent = null  # 自分のテントにはかからないように
	var ok := true
	if is_blocked.is_valid():
		for d in [Vector2.ZERO, Vector2(TENT_CLEARANCE, 0), Vector2(-TENT_CLEARANCE, 0), Vector2(0, TENT_CLEARANCE), Vector2(0, -TENT_CLEARANCE)]:
			if is_blocked.call(p + d):
				ok = false
				break
	tent = keep
	return ok

# 目安の場所(小屋の場所が決まっていればその戸口の南西、なければ中心の南西)から近い順に探す
func _find_tent_spot():
	var anchor := Vector2(-8, 8)
	if cabin.site != null:
		anchor = cabin.site + Vector2(-(cabin.WIDTH * 0.5 + 1.5), cabin.DEPTH * 0.5 + 3.0)
	var r := 0.0
	while r <= TENT_SEARCH:
		var steps: int = maxi(1, int(r * 1.5))
		for i in range(steps):
			var p: Vector2 = anchor + Vector2(r, 0).rotated(TAU * i / steps)
			if _tent_fits(p):
				return p
		r += 1.0
	return null

# その場所にテントがかかるか(区画や池・井戸を置くときに見る)
func covers(pos: Vector2, radius := 0.6) -> bool:
	return has_tent() and tent.distance_to(pos) < TENT_RADIUS + radius

# 区画(中心 c)がテントにかかるか
func blocks_plot(c: Vector2, half: float) -> bool:
	return has_tent() and absf(tent.x - c.x) <= half + TENT_RADIUS and absf(tent.y - c.y) <= half + TENT_RADIUS

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	var d := {"chosen": chosen, "members": members, "talked": talked, "helped_day": helped_day}
	if tent != null:
		d["tent"] = [tent.x, tent.y]
	return d

# 家族の記録がないセーブ(2026-11-16 より前)は、まだ決めていない(開いたときに一度だけ選ぶ)
func from_save(d: Dictionary) -> void:
	chosen = SaveRead.flag(d, "chosen", false)
	members = []
	var known := {}
	for id in SPOUSES:
		known[id] = SPOUSES[id]
	for c in CHILDREN:
		known[c.id] = c
	for raw in SaveRead.list(d.get("members")):
		var m := SaveRead.dict(raw)
		var id := SaveRead.text(m, "id")
		if not known.has(id) or members.any(func(x): return x.id == id):
			continue
		var info: Dictionary = known[id]
		var role := "spouse" if SPOUSES.has(id) else "child"
		members.append({"id": id, "name": info.name, "sex": info.sex, "relation": info.relation, "role": role,
			"age": SaveRead.count(m, "age") if role == "child" else ADULT_AGE, "joined_day": SaveRead.whole(m, "joined_day", day_number())})
	talked = {}
	var t := SaveRead.dict(d.get("talked"))
	for id in t:
		if known.has(id):
			talked[id] = SaveRead.whole(t, id, -1)
	helped_day = SaveRead.whole(d, "helped_day", -1)
	tent = SaveRead.pair(d.get("tent"))
	last_help = []
	last_gift = {}
	changed.emit()
