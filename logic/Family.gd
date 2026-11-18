extends RefCounted

# ── 家族(描画を持たない。2026-11-16) ──────────────────────────────
# ゲームのはじめ(家族の記録がないセーブを開いたときも)に一度だけ、配偶者と子どもを選ぶ。あとから変えられない。
# 名前は自分で付けられ(はじめは決まった名前が入っている)、あとからも付け直せる(rename。2026-11-16 とむ決定)。
# 子どもは 1 人ずつ、息子か娘かと年齢(0〜MAX_START_AGE 歳)も選ぶ。
# 家族は最初から土地で暮らす。小屋が完成するまでは、夜はテントで休む(テントの場所はここで決める)。
# テントには南の入口から歩いて入れる。中には寝袋が並び、自分の寝袋のそばで H を押すと休める(日記。2026-11-16 とむ)。
# 小屋が完成したら、家族は小屋で暮らす: 夜はベッドで寝る。昼もときどき小屋に入って過ごす(見た目は view。2026-11-16 とむ)。
#   配偶者は自分と同じ大きいベッドの北の半分、子どもは北の壁際の 2 段ベッド(1 人なら 1 段)と、3 人目は小さいベッド(2026-11-18 とむ: 小屋を広げて家族もベッドで)
# 寝る時刻は時計で決める(BEDTIME。暗くなってから寝るまでは家の中で起きている。2026-11-18 とむ「寝るのが少し早い」)。
# 毎朝(日付が変わった最初の確認で)小さな手伝いをする:
#   配偶者: 水のいる区画か木に WATER_HELP か所まで水をやる(井戸・池・川のどれかで汲めるときだけ。雨の日は要らない)
#   子ども: HELP_AGE 歳から、雑草の生えた区画を 1 つ抜く(WEED_MORE_AGE 歳から 2 つ)
# 話しかける(C)と、その日はじめてのときに GIFT_CHANCE で贈り物をくれる(配偶者は料理、子どもは拾った木の種)。
# 話す画面から「一緒に○○しよう」と誘える(2026-11-18 とむ決定。人ごと・作業ごとに 1 日 1 回。得は少しだけ):
#   収穫(配偶者と HELP_AGE 歳からの子ども): ついてきて、自分が区画を収穫すると近くの区画をもう 1 つ採る
#   料理(配偶者・小屋ができてから): ストーブの前で待ち、仕込むと横でかき混ぜて、できる数が 2 割増える(Kitchen.COOK_HELP_RATE)
#   夕食(小屋ができてから・暗くなってから寝るまで): 家族がテーブルに座り、自分が食べると「みんなで食べた」。翌朝の手伝いが増える
#   生き物探し(子ども): ついてきて、近くの生き物を見つけて教える。見つけるたびに生き物との仲良し度が上がる(Pests。1 日 EXPLORE_SPOTS 種類まで)
#   種拾い(HELP_AGE 歳からの子ども・外の林に種が落ちている日): ついてきて、自分が外の林で種を拾うと、近くに落ちている種をもう 1 つ拾う
# 子どもは AGE_DAYS 日で 1 歳育ち、ADULT_AGE で止まる(木は 1 日 1 年だが、人は一月で 1 歳にした。仮の数字)。
# 文言は Main、姿と歩く道は view/3d/FamilyView3D.gd が決める
const SaveRead = preload("res://logic/SaveRead.gd")
const Forest = preload("res://logic/Forest.gd")

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
# 子どもの枠。上の子から順にこの並び。id は並びの印(名前を変えても変わらない)。name・sex・age は選ぶ画面のはじめの値
const CHILDREN := [
	{"id": "vanya", "name": "ワーニャ", "sex": "m", "relation": "息子", "age": 9},
	{"id": "masha", "name": "マーシャ", "sex": "f", "relation": "娘", "age": 6},
	{"id": "polya", "name": "ポーリャ", "sex": "f", "relation": "娘", "age": 3},
]
# 子どもの名前を空にしたときに使う名前(枠ごと。息子か娘かで変わる)。はじめの値は CHILDREN の名前と同じ
const DEFAULT_NAMES := {"m": ["ワーニャ", "ペーチャ", "コーリャ"], "f": ["ダーシャ", "マーシャ", "ポーリャ"]}
const MAX_CHILDREN := 3
const MAX_START_AGE := 17     # 選べる子どもの年齢の上限
const NAME_MAX := 8           # 名前の文字数の上限

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
const INVITE_KINDS := ["harvest", "cook", "dinner", "explore", "seeds"]  # 誘える作業
const HARVEST_REACH := 4.0    # 一緒に収穫するとき、家族が採る区画の範囲(自分の足元から m)
const DINNER_WATER_HELP := 5  # みんなで夕食を食べた翌朝、配偶者が水をやる数(ふだんは WATER_HELP)
const DINNER_WEED_MORE := 1   # みんなで夕食を食べた翌朝、子どもが余分に抜く区画
const EXPLORE_GAIN := 2       # 子どもが生き物を見つけて教えてくれたとき、上がる仲良し度
const EXPLORE_SPOTS := 3      # 1 日に仲良し度が上がる、見つけた生き物の種類の数
const SEEDS_REACH := 8.0      # 外の林で一緒に種拾いするとき、子どもが拾う種の範囲(自分の足元から m)
# テント(2026-11-16 とむ: 歩いて入れて、中で休める)。人が立てる大きさ。入口は南の真ん中
const TENT_SIZE := Vector2(3.2, 3.6)   # 東西 × 南北(m)
const TENT_DOOR := 1.0                 # 入口の幅(m)
const BEDROLL_SIZE := Vector2(0.62, 1.9)  # 寝袋 1 枚(東西 × 南北)。北の奥に頭を向けて並べる
const BEDROLL_REACH := 0.6             # 寝袋からこの距離までなら H で休める
const TENT_SAMPLE := 1.0               # テントを張れるか確かめる点の間隔(m)
# 小屋の子どものベッド(小屋の中心から。2026-11-18)。北の壁際に東西に置く(枕は西)。2 段ベッドは北西の隅、3 人目の小さいベッドはその東。
# 背の高い 2 段ベッドを奥(北)に置いて、見下ろすカメラから大きいベッドを隠さない
const BUNK_OFFSET := Vector2(-2.0, -1.45)
const BUNK_SIZE := Vector2(1.7, 0.85)    # 東西 × 南北
const COT_OFFSET := Vector2(-0.45, -1.58)  # 3 人目の子どもの小さいベッド
const COT_SIZE := Vector2(1.25, 0.6)
# 寝る時刻(時。現実の時計)と、起きる時刻。暗くなってから寝るまでは家の中で起きている(2026-11-18。仮の数字)
const BEDTIME := {"child": 20.5, "spouse": 22.0}
const WAKE_HOUR := 6.0
const DOOR_OUT := 1.0                   # 小屋の戸口の外、この距離のところで出入りする
const TENT_SEARCH := 30.0     # テントの場所を探す範囲(目安の場所からの距離)
const CENTER_CLEAR := 5.0     # 中心は家族の杉のために空ける(Quests.FAMILY_CEDAR_RADIUS と同じ)

var forest = null        # GameWorld が設定する
var garden = null
var cabin = null
var market = null
var pests = null         # 生き物との仲良し度(子どもと生き物探し。GameWorld が設定する)
var wilds = null         # 外の林(子どもと種拾い。GameWorld が設定する)
var is_blocked: Callable  # 物を置けない場所か(Bees.is_blocked。GameWorld が設定する)
var can_draw_water: Callable  # 手伝いの水を汲めるか(GameWorld が設定する)

var chosen := false      # 家族を決めたか(決める前は誰もいない)
var members := []        # [{id, name, sex, relation, role: spouse/child, age(はじめの年齢), joined_day}]
var tent = null          # テントの中心 Vector2(小屋が完成するまで)。まだなければ null
var talked := {}         # 人ごとに、最後に話しかけた日の通し番号
var invited := {}        # "人の id:作業" → 誘った日の通し番号(1 日 1 回。夕食はみんなで 1 回なので "all:dinner")
var dined_day := -1      # みんなで夕食を食べた日の通し番号(翌朝の手伝いが増える)
var spotted := []        # 今日、子どもが見つけて教えてくれた生き物の id(仲良し度が上がったもの。保存しない)
var spotted_day := -1
var helped_day := -1     # 最後に手伝った日
var last_help := []      # 今朝の手伝い [{who, kind: water/weed, pos}](文言と姿の動き用。保存しない)
var last_gift := {}      # 直前にもらった贈り物 {who, type, item/species, count}(文言用)

func _commit() -> void:
	changed.emit()
	dirty.emit()

func day_number() -> int:
	return forest.day_number()

# 家族を決める(一度だけ)。名前・息子か娘か・年齢は、はじめの値のまま。結果は choose_custom
func choose(spouse: String, children: int) -> String:
	if children < 0 or children > MAX_CHILDREN:
		return "unknown"
	var kids := []
	for i in range(children):
		kids.append({"name": CHILDREN[i].name, "sex": CHILDREN[i].sex, "age": CHILDREN[i].age})
	return choose_custom(spouse, "", kids)

# 家族を決める(一度だけ)。spouse は SPOUSES の id か ""(いない)。spouse_name が空なら決まった名前。
# kids は子どもの並び [{name, sex: m/f, age}]。名前が空なら、その枠の決まった名前。
# 結果: chosen / already / unknown(知らない配偶者・人数・性別・年齢) / too_long(名前が長すぎる)
func choose_custom(spouse: String, spouse_name: String, kids: Array) -> String:
	if chosen:
		return "already"
	if spouse != "" and not SPOUSES.has(spouse):
		return "unknown"
	if kids.size() > MAX_CHILDREN:
		return "unknown"
	for k in kids:
		if typeof(k) != TYPE_DICTIONARY or not str(k.get("sex", "")) in ["m", "f"]:
			return "unknown"
		if typeof(k.get("age")) != TYPE_INT and typeof(k.get("age")) != TYPE_FLOAT:
			return "unknown"
		if int(k.age) < 0 or int(k.age) > MAX_START_AGE:
			return "unknown"
		if clean_name(str(k.get("name", ""))).length() > NAME_MAX:
			return "too_long"
	if clean_name(spouse_name).length() > NAME_MAX:
		return "too_long"
	members.clear()
	var today := day_number()
	if spouse != "":
		var s: Dictionary = SPOUSES[spouse]
		var sn := clean_name(spouse_name)
		members.append({"id": spouse, "name": sn if sn != "" else s.name, "sex": s.sex, "relation": s.relation, "role": "spouse", "age": ADULT_AGE, "joined_day": today})
	for i in range(kids.size()):
		var k: Dictionary = kids[i]
		var kn := clean_name(str(k.get("name", "")))
		members.append({"id": CHILDREN[i].id, "name": kn if kn != "" else default_name(i, k.sex), "sex": k.sex, "relation": child_relation(k.sex),
			"role": "child", "age": int(k.age), "joined_day": today})
	chosen = true
	ensure_tent()
	_commit()
	return "chosen"

# 子どもの枠 i の、息子か娘かに合う決まった名前
static func default_name(i: int, sex: String) -> String:
	return DEFAULT_NAMES["m" if sex == "m" else "f"][clampi(i, 0, MAX_CHILDREN - 1)]

static func child_relation(sex: String) -> String:
	return "息子" if sex == "m" else "娘"

# 名前の前後の空白と改行を取る
static func clean_name(text: String) -> String:
	return text.replace("\n", "").replace("\r", "").replace("\t", "").strip_edges()

# 名前を付け直す。結果: renamed / same(変わらない) / empty / too_long / unknown(その人がいない)
func rename(id: String, new_name: String) -> String:
	var m := member(id)
	if m.is_empty():
		return "unknown"
	var n := clean_name(new_name)
	if n == "":
		return "empty"
	if n.length() > NAME_MAX:
		return "too_long"
	if n == m.name:
		return "same"
	m.name = n
	_commit()
	return "renamed"

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
	var dined: bool = dined_day == today - 1  # ゆうべ、みんなで夕食を食べた
	if not s.is_empty() and (not can_draw_water.is_valid() or can_draw_water.call()):
		_water_help(s.id, DINNER_WATER_HELP if dined else WATER_HELP)
	for c in children():
		var age := age_of(c)
		if age >= HELP_AGE:
			_weed_help(c.id, (2 if age >= WEED_MORE_AGE else 1) + (DINNER_WEED_MORE if dined else 0))
	dirty.emit()
	if not last_help.is_empty():
		changed.emit()
	return not last_help.is_empty()

# 水のいる区画を先に、次に木へ、合わせて count か所まで
func _water_help(who: String, count: int) -> void:
	var left := count
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

# ── 一緒にする作業(2026-11-18) ───────────────────────────────
# 誘えない理由。誘えるなら ""。unknown / young(小さい子は収穫できない) / spouse_only / no_cabin / done_today(今日はもう誘った)
# 時刻(収穫は明るいうち、夕食は暗くなってから)は姿の view が知っているので、Main が見る
func invite_problem(id: String, kind: String) -> String:
	var m := member(id)
	if m.is_empty() or not kind in INVITE_KINDS:
		return "unknown"
	match kind:
		"harvest":
			if m.role == "child" and age_of(m) < HELP_AGE:
				return "young"
		"cook":
			if m.role != "spouse":
				return "spouse_only"
			if not cabin.is_complete():
				return "no_cabin"
		"dinner":
			if not cabin.is_complete():
				return "no_cabin"
		"explore":
			if m.role != "child":
				return "child_only"
		"seeds":
			if m.role != "child":
				return "child_only"
			if age_of(m) < HELP_AGE:
				return "young"
	return "done_today" if invited_today(id, kind) else ""

func invited_today(id: String, kind: String) -> bool:
	return int(invited.get(_invite_key(id, kind), -1)) == day_number()

static func _invite_key(id: String, kind: String) -> String:
	return ("all" if kind == "dinner" else id) + ":" + kind

# 誘う。結果: invited か、invite_problem の理由
func invite(id: String, kind: String) -> String:
	var problem := invite_problem(id, kind)
	if problem != "":
		return problem
	invited[_invite_key(id, kind)] = day_number()
	dirty.emit()
	return "invited"

# pos から reach 以内で、いちばん近い収穫できる区画(exclude の区画は除く)。なければ null
func ripe_near(pos: Vector2, reach: float, exclude: Array = []):
	var best = null
	var best_d := reach
	for c in garden.crops:
		if c.pos in exclude or not garden.is_ripe(c):
			continue
		var d: float = pos.distance_to(c.pos)
		if d <= best_d:
			best_d = d
			best = c.pos
	return best

func any_ripe() -> bool:
	return garden.crops.any(func(c): return garden.is_ripe(c))

# 子どもが生き物を見つけて教えてくれた。今日はじめての種類なら、1 日 EXPLORE_SPOTS 種類まで仲良し度が上がる。上がった量を返す
func spot_creature(creature: String) -> int:
	if spotted_day != day_number():
		spotted = []
		spotted_day = day_number()
	if creature in spotted or spotted.size() >= EXPLORE_SPOTS or pests == null:
		return 0
	spotted.append(creature)
	return pests.gain(EXPLORE_GAIN)

# 外の林に落ちている種(一族の土地の外の Forest.pickups)
func wild_pickups() -> Array:
	return forest.pickups.filter(func(p): return Forest.is_outside_land(p.pos))

# pos から reach 以内で、いちばん近い外の林の種(なければ {})
func wild_pickup_near(pos: Vector2, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for p in wild_pickups():
		var d: float = pos.distance_to(p.pos)
		if d <= best_d:
			best_d = d
			best = p
	return best

# 次に外の林で種が落ちる日 {day, species}(今日より後。なければ {})
func next_wild_drop() -> Dictionary:
	if wilds == null:
		return {}
	var today := day_number()
	var best := {}
	for sp in wilds.species_here():
		var d: int = wilds.next_drop(sp, today + 1)
		if d >= 0 and (best.is_empty() or d < int(best.day)):
			best = {"day": d, "species": sp}
	return best

# みんなで夕食を食べた(翌朝の手伝いが増える)
func dine_together() -> void:
	dined_day = day_number()
	dirty.emit()

func dined_today() -> bool:
	return dined_day == day_number()

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
		return cabin.door_pos() + Vector2(0, DOOR_OUT)  # 戸口の外(ここから戸口を通って中へ入る)
	ensure_tent()
	return tent + Vector2(0, TENT_SIZE.y * 0.5 + 0.5) if tent != null else null

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

# p を中心にテントを張れるか: 家族の杉の場所を空け、テントの上の点がどれも物を置ける場所(Bees.is_blocked でない)
func _tent_fits(p: Vector2) -> bool:
	if p.length() < CENTER_CLEAR + TENT_SIZE.length() * 0.5:
		return false
	var keep = tent
	tent = null  # 自分のテントにはかからないように
	var ok := true
	if is_blocked.is_valid():
		var half := TENT_SIZE * 0.5
		var x := -half.x
		while ok and x <= half.x + 0.01:
			var y := -half.y
			while y <= half.y + 0.01:
				if is_blocked.call(p + Vector2(x, y)):
					ok = false
					break
				y += minf(TENT_SAMPLE, half.y)
			x += minf(TENT_SAMPLE, half.x)
	tent = keep
	return ok

# 目安の場所(小屋の場所が決まっていればその戸口の南西、なければ中心の南西)から近い順に探す
func _find_tent_spot():
	var anchor := Vector2(-8, 8)
	if cabin.site != null:
		anchor = cabin.site + Vector2(-(cabin.WIDTH * 0.5 + 2.5), cabin.DEPTH * 0.5 + 3.5)
	var r := 0.0
	while r <= TENT_SEARCH:
		var steps: int = maxi(1, int(r * 1.5))
		for i in range(steps):
			var p: Vector2 = anchor + Vector2(r, 0).rotated(TAU * i / steps)
			if _tent_fits(p):
				return p
		r += 1.0
	return null

# テントの床の長方形
func tent_rect() -> Rect2:
	return Rect2(tent - TENT_SIZE * 0.5, TENT_SIZE)

# その場所にテントがかかるか(区画や池・井戸を置くときに見る)
func covers(pos: Vector2, radius := 0.6) -> bool:
	return has_tent() and tent_rect().grow(radius).has_point(pos)

# 区画(中心 c)がテントにかかるか
func blocks_plot(c: Vector2, half: float) -> bool:
	return has_tent() and Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0).grow(0.3).intersects(tent_rect())

# 足元がテントの中か
func is_in_tent(pos: Vector2) -> bool:
	return has_tent() and tent_rect().grow(-0.05).has_point(pos)

# 寝袋の中心の並び。西から プレイヤー・配偶者・子ども(上から)の順。テントがなければ空
func bedroll_spots() -> Array:
	if not has_tent():
		return []
	var count := members.size() + 1
	var step: float = TENT_SIZE.x / count
	var out := []
	for i in range(count):
		out.append(Vector2(tent.x - TENT_SIZE.x * 0.5 + (i + 0.5) * step, tent.y - TENT_SIZE.y * 0.5 + BEDROLL_SIZE.y * 0.5 + 0.15))
	return out

# 寝袋 1 枚の幅(人数で狭くなる)
func bedroll_width() -> float:
	return minf(BEDROLL_SIZE.x, TENT_SIZE.x / (members.size() + 1) - 0.06)

# その人の寝袋の中心(プレイヤーは "")。なければ null
func bedroll_of(id: String):
	var spots := bedroll_spots()
	if spots.is_empty():
		return null
	if id == "":
		return spots[0]
	var i := members.map(func(m): return m.id).find(id)
	return spots[i + 1] if i >= 0 else null

# テントの中で、自分の寝袋のそばにいるか(H で休める)
func is_at_bedroll(pos: Vector2) -> bool:
	if not is_in_tent(pos):
		return false
	var spot = bedroll_of("")
	var r := Rect2(spot - Vector2(bedroll_width(), BEDROLL_SIZE.y) * 0.5, Vector2(bedroll_width(), BEDROLL_SIZE.y))
	return r.grow(BEDROLL_REACH).has_point(pos)

# ── 寝る時刻 ──────────────────────────────────────────────
# その人が寝ている時刻か(hours は 0〜24 の時刻)
static func is_bedtime(role: String, hours: float) -> bool:
	return hours >= float(BEDTIME.get(role, BEDTIME.spouse)) or hours < WAKE_HOUR

# ── 小屋のベッド ──────────────────────────────────────────
# 家族の寝る場所 [{id, kind, pos(寝る人の体の中心), feet(足の裏), head(west / north), approach(そばの床)}]。小屋が完成していなければ空。
# kind: double(配偶者。自分と同じベッドの北の半分) / bunk_low・bunk_high(2 段ベッドの下・上) / single(子どもが 1 人なら 2 段ベッドの代わり) / cot(3 人目)
# 子どもは上の子から 2 段ベッドの上 → 下 → 小さいベッド(1 人だけなら 1 段のベッド)
func bed_spots() -> Array:
	if not chosen or members.is_empty() or not cabin.is_complete():
		return []
	var site: Vector2 = cabin.site
	var out := []
	var bed_c: Vector2 = site + cabin.BED_OFFSET
	var bed_s: Vector2 = cabin.BED_SIZE
	var kids := children()
	for m in members:
		if m.role != "child":
			var z: float = bed_c.y - bed_s.y * 0.25  # 北の半分
			out.append({"id": m.id, "kind": "double", "pos": Vector2(bed_c.x, z), "feet": Vector2(bed_c.x + bed_s.x * 0.5 - 0.15, z), "head": "west",
				"approach": Vector2(bed_c.x + bed_s.x * 0.5 + 0.35, bed_c.y)})
	for i in range(kids.size()):
		var m: Dictionary = kids[i]
		if i < 2:
			var bunk: Vector2 = site + BUNK_OFFSET
			var kind := "single" if kids.size() == 1 else ("bunk_high" if i == 0 else "bunk_low")
			out.append({"id": m.id, "kind": kind, "pos": bunk, "feet": Vector2(bunk.x + BUNK_SIZE.x * 0.5 - 0.12, bunk.y), "head": "west",
				"approach": Vector2(bunk.x + 0.3, bunk.y + BUNK_SIZE.y * 0.5 + 0.35)})
		else:
			var cot: Vector2 = site + COT_OFFSET
			out.append({"id": m.id, "kind": "cot", "pos": cot, "feet": Vector2(cot.x + COT_SIZE.x * 0.5 - 0.1, cot.y), "head": "west",
				"approach": Vector2(cot.x, cot.y + COT_SIZE.y * 0.5 + 0.35)})
	return out

func bed_of(id: String) -> Dictionary:
	for b in bed_spots():
		if b.id == id:
			return b
	return {}

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	var today := day_number()
	var keep := {}
	for k in invited:  # 今日の分だけ残す
		if int(invited[k]) == today:
			keep[k] = invited[k]
	var d := {"chosen": chosen, "members": members, "talked": talked, "helped_day": helped_day, "invited": keep, "dined_day": dined_day}
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
		# 名前は付け直せるので保存したもの(読めなければ決まった名前)。子どもの息子か娘かも保存したもの
		var sex: String = info.sex
		if role == "child" and SaveRead.text(m, "sex") in ["m", "f"]:
			sex = SaveRead.text(m, "sex")
		var saved_name := clean_name(SaveRead.text(m, "name"))
		if saved_name == "" or saved_name.length() > NAME_MAX:
			saved_name = info.name if role == "spouse" else default_name(CHILDREN.map(func(c): return c.id).find(id), sex)
		members.append({"id": id, "name": saved_name, "sex": sex, "relation": child_relation(sex) if role == "child" else info.relation, "role": role,
			"age": mini(SaveRead.count(m, "age"), MAX_START_AGE) if role == "child" else ADULT_AGE, "joined_day": SaveRead.whole(m, "joined_day", day_number())})
	talked = {}
	var t := SaveRead.dict(d.get("talked"))
	for id in t:
		if known.has(id):
			talked[id] = SaveRead.whole(t, id, -1)
	helped_day = SaveRead.whole(d, "helped_day", -1)
	invited = {}
	var inv := SaveRead.dict(d.get("invited"))
	for k in inv:
		invited[str(k)] = SaveRead.whole(inv, k, -1)
	dined_day = SaveRead.whole(d, "dined_day", -1)
	tent = SaveRead.pair(d.get("tent"))
	last_help = []
	last_gift = {}
	changed.emit()
