extends RefCounted

# ── 木と種のゲームロジック(描画を持たない) ─────────────────────
# 見た目は view/ が changed を受けて描く。2D でも 3D でも同じロジックを使う。
# 状態が変わると changed(描き直し)を出し、保存が必要な変更では dirty も出す(GameWorld が保存する)
# 座標の単位は m

const SaveRead = preload("res://logic/SaveRead.gd")
const Region = preload("res://logic/Region.gd")

signal changed  # 見た目に関わる状態が変わった
signal dirty    # セーブに入る状態が変わった

# ── 現実時間で成長するシステム ──────────────────────────────
# 1 現実日 = 樹齢 1 年。アプリを閉じている間も現実時間ぶん育つ。
# T / G キーで時間を先送りしてプレビューできる(見た目だけ。セーブしない)。
const SECONDS_PER_YEAR := 86400.0

# ── 種と苗木(現実寄り。2026-11-03 とむの方針) ─────────────────────
# 種は安いが、芽が出ないことがある(植えて 1 日 = 樹齢 1 年で分かる。出なければ翌日消える)。
# 苗木は市場で買う。必ず根付き、樹齢 2〜4 年から始まる。
# 育った木は実る季節に根元へ種を落とす(拾わなかった分は翌日には消える)。
# リンゴは樹齢 6 年から秋に実り、収穫すると「リンゴ」が手に入る(市場で売れる。種は増えない)
# 県を選ぶ前の(今までの)はじめの種。県を選んで新しく始めたときは start_stock で決め直す
const INITIAL_SEEDS := {"birch": 3, "apple": 1}
const START_WIND_SEEDS := 3  # 県を選んで新しく始めたときの、その土地の広葉樹の種(今までの白樺 3 粒と同じ)
const APPLE_FRUIT_AGE := 6.0
# 果樹。seasons: 実る季節 / age: 実りはじめる樹齢 / first: はじめの収穫量 / step: 1 年で増える量 / most: 上限(1 本の 1 日)
# unit: 単位(文言用)。リンゴの 300₽/日 を超えない数字にした(仮の数字)
const FRUITS := {
	"apple": {"seasons": ["autumn"], "age": APPLE_FRUIT_AGE, "first": 5, "step": 5, "most": 20, "unit": "個"},
	"cherry": {"seasons": ["summer"], "age": 4.0, "first": 1, "step": 1, "most": 3, "unit": "kg"},
	"plum": {"seasons": ["summer"], "age": 5.0, "first": 1, "step": 1, "most": 5, "unit": "kg"},
	"pear": {"seasons": ["autumn"], "age": 6.0, "first": 4, "step": 4, "most": 15, "unit": "個"},
	# 県を選ぶようにして足した果樹(2026-11-11)。カキは接ぎ木の苗木で 5〜6 年(種からだと「柿八年」)。
	# ミカン・シークヮーサーは秋の終わりから冬に色づく常緑樹
	"kaki": {"seasons": ["autumn"], "age": 6.0, "first": 4, "step": 4, "most": 15, "unit": "個"},
	"mikan": {"seasons": ["autumn", "winter"], "age": 5.0, "first": 5, "step": 5, "most": 20, "unit": "個"},
	"shikuwasa": {"seasons": ["autumn", "winter"], "age": 4.0, "first": 1, "step": 1, "most": 5, "unit": "kg"},
	# 2026-11-11 に足した果樹。クリは「桃栗三年」で樹齢 3 年から。ウメは初夏(ゲームでは夏)に青い実を採る。パパイヤは一年中実る
	"ume": {"seasons": ["summer"], "age": 4.0, "first": 1, "step": 1, "most": 5, "unit": "kg"},
	"kuri": {"seasons": ["autumn"], "age": 3.0, "first": 1, "step": 1, "most": 5, "unit": "kg"},
	"mango": {"seasons": ["summer"], "age": 4.0, "first": 2, "step": 2, "most": 10, "unit": "個"},
	"papaya": {"seasons": ["spring", "summer", "autumn", "winter"], "age": 2.0, "first": 2, "step": 2, "most": 8, "unit": "個"},
}
const FRUIT_ORDER := ["apple", "cherry", "plum", "pear", "kaki", "mikan", "shikuwasa", "ume", "kuri", "mango", "papaya"]  # 果樹を選ぶ順番(キーの 2)
# 収穫してから次に実るまでの日数(2026-11-11 とむ決定。前は毎日採れて、季節の売上が野菜の区画並みだった。仮の数字)
const FRUIT_INTERVAL := 3
const SAPLING_ONLY := ["cherry", "plum", "pear", "kaki", "mikan", "shikuwasa", "ume", "kuri", "mango", "papaya"]  # 接ぎ木の苗木から育てる(現実でも、種からだと親と同じ実にならない)
const GERMINATION_YEARS := 1.0  # 種から芽が出るまで(= 1 日)
# 剪定: 葉の落ちた冬に果樹の枝を切ると、次の収穫が増える(現実でも果樹の剪定は冬の仕事)。1 本につきひと冬 1 回
const PRUNE_BONUS := 1.25  # 剪定した木の収穫の倍率(仮の数字)

# ── 毎日の理由 ──────────────────────────────────────────────
# 水やり: 1 本につき 1 日 1 回、樹齢にボーナスが付く(収穫などの判定にも効く)
# 日替わりの発見: その日はじめて開いたときに 1 つ起きる。開かなかった日の分はたまらない。
# 何が起きるかは日付から決まるので、同じ日に開き直しても引き直しにならない
const WATER_BONUS_YEARS := 0.5
const DAILY_EVENTS := [
	# [id, 重み]。文言は Main が決める
	["birch_seed", 35],  # 風で白樺の種が飛んできた(+1)。県を選んだら、その土地の広葉樹(Region.wind_seed)
	["cedar_seed", 15],  # リスがシベリア杉の実を置いていった(+1)。県を選んだら、その土地の針葉樹(Region.nut_seed)
	["rain", 25],        # 全部の木に水やり済み。重みは土地の雨の多さ(Region.rain_weight)
	["birds", 25],       # 演出のみ。重みは 50 − 雨の重み(合わせて 100 のまま)
]

# 樹種ごとのパラメータ(色などの見た目は view 側が持つ)。数値は現実の目安から
#   max_r: 成熟時の樹冠半径(m)
#   tau, p: 成長曲線 r = max_r × (1 − e^(−樹齢/tau))^p。p が大きいほど若いうちはゆっくり
#           (白樺: 1 年で高さ 0.1m 台・10 年で約 9m / 杉: 10 年で約 1m・25 年で約 5m)
#   evergreen: 常緑樹か(冬に葉が残る)
#   germination: 種の発芽率 / sapling_age: 市場の苗木の樹齢
#   seed_age: 根元に種を落としはじめる樹齢(0 = 落とさない) / seed_seasons: 落とす季節
#   seed_drop: 1 本が 1 日に落とす種の数(ひとかたまりで落ちている)
#   wood_age: 伐って丸太(約 0.1m³)が採れはじめる樹齢 / wood_years: 丸太 1 本増えるのにかかる年数 / wood_max: 上限
#             (白樺: 20 年で 2 本ほど = 約 0.2m³・40 年で 6 本 / 杉は育つのが遅い / リンゴは太くならない)
#   group: broadleaf(広葉樹。キーの 1)/ fruit(果樹。キーの 2)/ conifer(針葉樹。キーの 3)
#   zones: 植えられる気候区分(Region.ZONES)。現実に育つところの目安。植物を足すときはここに書く
#   regional: 県を選んでから植えられる木(選ぶ前の今までのルールには出てこない)
const COLD := ["hokkaido", "tohoku", "snowy", "highland"]
const NOT_ISLANDS := ["hokkaido", "tohoku", "snowy", "highland", "pacific", "setouchi", "south"]
const HONSHU_TO_KYUSHU := ["tohoku", "snowy", "highland", "pacific", "setouchi", "south"]
const WARM := ["pacific", "setouchi", "south"]
const SPECIES := {
	"birch": {
		"group": "broadleaf", "zones": COLD,
		"name": "白樺", "max_r": 3.5, "tau": 6.0, "p": 2.5, "evergreen": false,
		"germination": 0.4, "sapling_age": 2.0,
		"seed_age": 10.0, "seed_seasons": ["autumn", "winter"], "seed_drop": 5,
		"wood_age": 15.0, "wood_years": 5.0, "wood_max": 6,
	},
	"apple": {
		"group": "fruit", "zones": COLD,
		"name": "リンゴ", "max_r": 3.0, "tau": 5.0, "p": 2.0, "evergreen": false,
		"germination": 0.6, "sapling_age": 1.0,
		"seed_age": 0.0, "seed_seasons": [], "seed_drop": 0,
		"wood_age": 20.0, "wood_years": 10.0, "wood_max": 2,
	},
	"cherry": {
		"group": "fruit", "zones": COLD,
		"name": "サクランボ", "max_r": 2.6, "tau": 4.0, "p": 2.0, "evergreen": false,
		"germination": 0.0, "sapling_age": 1.0,
		"seed_age": 0.0, "seed_seasons": [], "seed_drop": 0,
		"wood_age": 20.0, "wood_years": 10.0, "wood_max": 2,
	},
	"plum": {
		"group": "fruit", "zones": NOT_ISLANDS,
		"name": "スモモ", "max_r": 2.4, "tau": 4.0, "p": 2.0, "evergreen": false,
		"germination": 0.0, "sapling_age": 1.0,
		"seed_age": 0.0, "seed_seasons": [], "seed_drop": 0,
		"wood_age": 20.0, "wood_years": 10.0, "wood_max": 2,
	},
	"pear": {
		"group": "fruit", "zones": NOT_ISLANDS,
		"name": "ナシ", "max_r": 2.8, "tau": 6.0, "p": 2.0, "evergreen": false,
		"germination": 0.0, "sapling_age": 1.0,
		"seed_age": 0.0, "seed_seasons": [], "seed_drop": 0,
		"wood_age": 25.0, "wood_years": 10.0, "wood_max": 3,
	},
	"cedar": {
		"group": "conifer", "zones": COLD,
		"name": "シベリア杉", "max_r": 6.0, "tau": 40.0, "p": 2.0, "evergreen": true,
		"germination": 0.5, "sapling_age": 4.0,
		"seed_age": 25.0, "seed_seasons": ["autumn"], "seed_drop": 5,
		"wood_age": 40.0, "wood_years": 10.0, "wood_max": 8,
	},
	# ── 県を選ぶようにして足した木(2026-11-11)。数字は現実の目安から置いた仮の数字 ──
	"konara": {  # コナラ: 北海道から九州の雑木林。どんぐりはよく芽が出る。15〜20 年ごとに伐って薪にしてきた
		"group": "broadleaf", "zones": NOT_ISLANDS, "regional": true,
		"name": "コナラ", "max_r": 4.0, "tau": 8.0, "p": 2.2, "evergreen": false,
		"germination": 0.6, "sapling_age": 2.0,
		"seed_age": 15.0, "seed_seasons": ["autumn"], "seed_drop": 5,
		"wood_age": 15.0, "wood_years": 5.0, "wood_max": 6,
	},
	"gajumaru": {  # ガジュマル: 沖縄の常緑樹。実を食べた鳥が種を運ぶ。幹は丸太には向かない
		"group": "broadleaf", "zones": ["nansei"], "regional": true,
		"name": "ガジュマル", "max_r": 5.0, "tau": 12.0, "p": 2.0, "evergreen": true,
		"germination": 0.3, "sapling_age": 2.0,
		"seed_age": 8.0, "seed_seasons": ["summer", "autumn"], "seed_drop": 5,
		"wood_age": 25.0, "wood_years": 8.0, "wood_max": 4,
	},
	"kaki": {
		"group": "fruit", "zones": HONSHU_TO_KYUSHU, "regional": true,
		"name": "カキ", "max_r": 3.0, "tau": 6.0, "p": 2.0, "evergreen": false,
		"germination": 0.0, "sapling_age": 1.0,
		"seed_age": 0.0, "seed_seasons": [], "seed_drop": 0,
		"wood_age": 25.0, "wood_years": 10.0, "wood_max": 3,
	},
	"mikan": {  # ミカン(温州みかん): 冬に霜の少ない、海に近い暖かいところ
		"group": "fruit", "zones": WARM, "regional": true,
		"name": "ミカン", "max_r": 2.2, "tau": 5.0, "p": 2.0, "evergreen": true,
		"germination": 0.0, "sapling_age": 1.0,
		"seed_age": 0.0, "seed_seasons": [], "seed_drop": 0,
		"wood_age": 20.0, "wood_years": 10.0, "wood_max": 2,
	},
	"shikuwasa": {  # シークヮーサー: 沖縄の小さな柑橘
		"group": "fruit", "zones": ["nansei"], "regional": true,
		"name": "シークヮーサー", "max_r": 2.0, "tau": 5.0, "p": 2.0, "evergreen": true,
		"germination": 0.0, "sapling_age": 1.0,
		"seed_age": 0.0, "seed_seasons": [], "seed_drop": 0,
		"wood_age": 20.0, "wood_years": 10.0, "wood_max": 2,
	},
	"sugi": {  # スギ: 東北から九州。日本でいちばん多く植えられてきた木。シベリア杉より速く育つ
		"group": "conifer", "zones": HONSHU_TO_KYUSHU, "regional": true,
		"name": "スギ", "max_r": 3.0, "tau": 15.0, "p": 2.0, "evergreen": true,
		"germination": 0.3, "sapling_age": 3.0,
		"seed_age": 20.0, "seed_seasons": ["autumn"], "seed_drop": 5,
		"wood_age": 20.0, "wood_years": 6.0, "wood_max": 8,
	},
	"ezomatsu": {  # エゾマツ: 北海道の針葉樹。寒さに強く、育つのはゆっくり
		"group": "conifer", "zones": ["hokkaido"], "regional": true,
		"name": "エゾマツ", "max_r": 3.0, "tau": 25.0, "p": 2.0, "evergreen": true,
		"germination": 0.4, "sapling_age": 4.0,
		"seed_age": 30.0, "seed_seasons": ["autumn"], "seed_drop": 5,
		"wood_age": 35.0, "wood_years": 8.0, "wood_max": 8,
	},
	# ── 2026-11-11 に足した木(2 回目。関東より西と沖縄が手薄だったので) ──
	"keyaki": {  # ケヤキ: 本州から九州。扇のように広がる大きな木。材は丈夫
		"group": "broadleaf", "zones": HONSHU_TO_KYUSHU, "regional": true,
		"name": "ケヤキ", "max_r": 5.0, "tau": 12.0, "p": 2.2, "evergreen": false,
		"germination": 0.4, "sapling_age": 2.0,
		"seed_age": 20.0, "seed_seasons": ["autumn"], "seed_drop": 5,
		"wood_age": 25.0, "wood_years": 6.0, "wood_max": 8,
	},
	"kunugi": {  # クヌギ: 本州から九州の雑木林。10〜15 年ごとに伐って薪やしいたけの原木にしてきた。コナラより早く太る
		"group": "broadleaf", "zones": HONSHU_TO_KYUSHU, "regional": true,
		"name": "クヌギ", "max_r": 4.0, "tau": 8.0, "p": 2.2, "evergreen": false,
		"germination": 0.6, "sapling_age": 2.0,
		"seed_age": 12.0, "seed_seasons": ["autumn"], "seed_drop": 5,
		"wood_age": 12.0, "wood_years": 4.0, "wood_max": 6,
	},
	"deigo": {  # デイゴ: 沖縄の県の花。春に赤い花が咲く。冬に葉を落とす
		"group": "broadleaf", "zones": ["nansei"], "regional": true,
		"name": "デイゴ", "max_r": 4.5, "tau": 8.0, "p": 2.0, "evergreen": false,
		"germination": 0.5, "sapling_age": 2.0,
		"seed_age": 8.0, "seed_seasons": ["summer", "autumn"], "seed_drop": 5,
		"wood_age": 20.0, "wood_years": 8.0, "wood_max": 3,
	},
	"fukugi": {  # フクギ: 沖縄で家のまわりに植える防風林の木。細く高く、葉が厚い。育つのはゆっくり
		"group": "broadleaf", "zones": ["nansei"], "regional": true,
		"name": "フクギ", "max_r": 2.5, "tau": 15.0, "p": 2.0, "evergreen": true,
		"germination": 0.5, "sapling_age": 2.0,
		"seed_age": 15.0, "seed_seasons": ["summer"], "seed_drop": 5,
		"wood_age": 30.0, "wood_years": 10.0, "wood_max": 5,
	},
	"ume": {
		"group": "fruit", "zones": NOT_ISLANDS, "regional": true,
		"name": "ウメ", "max_r": 2.4, "tau": 5.0, "p": 2.0, "evergreen": false,
		"germination": 0.0, "sapling_age": 1.0,
		"seed_age": 0.0, "seed_seasons": [], "seed_drop": 0,
		"wood_age": 25.0, "wood_years": 10.0, "wood_max": 2,
	},
	"kuri": {
		"group": "fruit", "zones": NOT_ISLANDS, "regional": true,
		"name": "クリ", "max_r": 3.5, "tau": 6.0, "p": 2.0, "evergreen": false,
		"germination": 0.0, "sapling_age": 1.0,
		"seed_age": 0.0, "seed_seasons": [], "seed_drop": 0,
		"wood_age": 20.0, "wood_years": 8.0, "wood_max": 4,
	},
	"mango": {
		"group": "fruit", "zones": ["nansei"], "regional": true,
		"name": "マンゴー", "max_r": 3.0, "tau": 6.0, "p": 2.0, "evergreen": true,
		"germination": 0.0, "sapling_age": 1.0,
		"seed_age": 0.0, "seed_seasons": [], "seed_drop": 0,
		"wood_age": 25.0, "wood_years": 10.0, "wood_max": 2,
	},
	"papaya": {  # パパイヤ: 幹が木にならない大きな草のような木。植えて 1〜2 年で実り、一年中採れる。丸太は採れない
		"group": "fruit", "zones": ["nansei"], "regional": true,
		"name": "パパイヤ", "max_r": 1.6, "tau": 2.0, "p": 1.5, "evergreen": true,
		"germination": 0.0, "sapling_age": 1.0,
		"seed_age": 0.0, "seed_seasons": [], "seed_drop": 0,
		"wood_age": 5.0, "wood_years": 10.0, "wood_max": 0,
	},
	"hinoki": {  # ヒノキ: 東北の南から九州。スギより育つのが遅いが、材はいちばん上等
		"group": "conifer", "zones": HONSHU_TO_KYUSHU, "regional": true,
		"name": "ヒノキ", "max_r": 2.8, "tau": 20.0, "p": 2.0, "evergreen": true,
		"germination": 0.3, "sapling_age": 3.0,
		"seed_age": 20.0, "seed_seasons": ["autumn"], "seed_drop": 5,
		"wood_age": 25.0, "wood_years": 6.0, "wood_max": 8,
	},
	"ryukyu_pine": {  # リュウキュウマツ: 沖縄の松。やせた土地でも速く育つ
		"group": "conifer", "zones": ["nansei"], "regional": true,
		"name": "リュウキュウマツ", "max_r": 4.0, "tau": 10.0, "p": 2.0, "evergreen": true,
		"germination": 0.6, "sapling_age": 2.0,
		"seed_age": 10.0, "seed_seasons": ["autumn", "winter"], "seed_drop": 5,
		"wood_age": 15.0, "wood_years": 5.0, "wood_max": 6,
	},
}
const GROUPS := ["broadleaf", "fruit", "conifer"]  # キーの 1・2・3

var time = null  # WorldTime(GameWorld が設定する)。今日の日付と今の時刻はここから読む
var region = null  # Region(GameWorld が設定する)。季節・植えられる木・雨の多さ。県を選ぶまでは null(今までのルール)
var _legacy := Region.new()  # 県を選ぶ前の気候(今までのルール)
# [{pos: Vector2(m), species, form: "seed"/"sapling"/""(移行前の木), planted_at: int,
#   start_age: float(苗木の樹齢), sprouts: bool(種が芽を出すか), last_harvest, last_watered, bonus_years,
#   pruned_year: int(剪定が効く収穫の年。0 = まだ)}]
var trees := []
var seeds := initial_seeds()      # 樹種ごとの種の所持数
var saplings := zero_counts()     # 樹種ごとの苗木の所持数
var produce := fruit_counts()     # 果樹ごとの収穫物(市場で売る)
var pickups := []             # 今日、地面に落ちている種 [{pos, species, amount}]
var last_failed := {}         # 今日の確認で芽が出なかった種の数 {species: 本数}(保存しない)
var germination_rates := {}   # 発芽率(テストで 1.0 にできるように変数にする)
var last_day := ""            # 日替わりの発見を最後に起こした日(YYYY-MM-DD)
var today_event := ""         # その日の発見の id(HUD で一日中見られるように保存する)
var time_offset_years := 0.0  # 時間先送りプレビュー(年)。セーブしない
var season := "summer"        # GameWorld が現実の日付から設定する

func _init() -> void:
	for sp in SPECIES:
		germination_rates[sp] = SPECIES[sp].germination

# 樹種ごとに 0 の数
static func zero_counts() -> Dictionary:
	var d := {}
	for sp in SPECIES:
		d[sp] = 0
	return d

static func fruit_counts() -> Dictionary:
	var d := {}
	for sp in FRUITS:
		d[sp] = 0
	return d

# 県を選ぶ前の(今までの)はじめの種
static func initial_seeds() -> Dictionary:
	var d := zero_counts()
	d.merge(INITIAL_SEEDS, true)
	return d

# 県を選んで新しく始めたとき: その土地の広葉樹の種と、育つならリンゴの種 1 粒(今までの白樺 3・リンゴ 1 に合わせた)
func start_stock() -> void:
	seeds = zero_counts()
	seeds[wind_seed()] = START_WIND_SEEDS
	if grows_here("apple"):
		seeds["apple"] = 1
	saplings = zero_counts()
	_commit()

# この土地で植えられる木か(県を選ぶ前は、今までの木だけ)
func grows_here(species: String) -> bool:
	if not SPECIES.has(species):
		return false
	if region == null:
		return not SPECIES[species].get("regional", false)
	return region.allows(SPECIES[species])

# その組(broadleaf / fruit / conifer)で、この土地で植えられる木(SPECIES の順。果樹は FRUIT_ORDER の順)
func species_in(group: String) -> Array:
	var order: Array = FRUIT_ORDER if group == "fruit" else SPECIES.keys()
	return order.filter(func(sp): return SPECIES[sp].group == group and grows_here(sp))

# 風や鳥が運んでくる広葉樹の種 / リスや風が運んでくる針葉樹の種(日替わりの発見)
func wind_seed() -> String:
	return region.wind_seed() if region != null else "birch"

func nut_seed() -> String:
	return region.nut_seed() if region != null else "cedar"

# 土地の気候(季節・雪・霜)。県を選ぶ前は今までのルール
func climate():
	return region if region != null else _legacy

# 冬に雪が積もって地面が凍る土地か
func snowy_winter() -> bool:
	return climate().has_snow()

# 保存が必要な変更のあと: 保存してから描き直す
func _commit() -> void:
	dirty.emit()
	changed.emit()

func set_season(s: String) -> void:
	if season == s:
		return
	season = s
	changed.emit()

# 今の季節に植えられるか。冬は地面が凍っているので苗木は植えられない。
# 種は、雪の上にまく方法がある白樺だけ。雪が積もらない土地では冬も植えられる
func can_plant(species: String, form: String) -> bool:
	return plant_problem(species, form) == ""

# 植えられない理由。"" = 植えられる / not_here = この土地では育たない / frozen = 冬で地面が凍っている
func plant_problem(species: String, form: String) -> String:
	if not grows_here(species):
		return "not_here"
	if season != "winter" or not snowy_winter():
		return ""
	return "" if form == "seed" and species == "birch" else "frozen"

# 種(form = "seed")か苗木("sapling")を 1 つ使って植える。持っていなければ植えずに false
func add_tree(pos: Vector2, species: String, form := "seed") -> bool:
	var stock: Dictionary = saplings if form == "sapling" else seeds
	if int(stock.get(species, 0)) <= 0:
		return false
	stock[species] -= 1
	var now := _now()
	var sprouts := true
	var start_age := 0.0
	if form == "sapling":
		start_age = SPECIES[species].sapling_age
	else:
		# 芽が出るかどうかは植えた場所と時刻から決まる(開き直しても変わらない)
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%s:%.2f:%.2f:%d" % [species, pos.x, pos.y, now]).hash()
		sprouts = rng.randf() < float(germination_rates.get(species, 1.0))
	trees.append({
		"pos": pos, "species": species, "form": form, "planted_at": now,
		"start_age": start_age, "sprouts": sprouts,
		"last_harvest": "", "last_watered": "", "bonus_years": 0.0, "pruned_year": 0,
	})
	# 雨の日は一日中降っている扱い。あとから植えた木も水やり済みにする
	if is_raining():
		_water(trees[-1])
	_commit()
	return true

# 今日は雨の日か(一日中降っている扱い)
func is_raining() -> bool:
	return last_day == today() and today_event == "rain"

# 根付いているか(苗木・移行前の木はいつも。種は芽が出て 1 日たってから)
func is_established(tree: Dictionary) -> bool:
	if tree.form != "seed":
		return true
	return tree.sprouts and real_age_years(tree) >= GERMINATION_YEARS

# 種のまま、まだ芽が出ていない(見た目は土の盛り上がり)
func is_seed(tree: Dictionary) -> bool:
	return tree.form == "seed" and (not tree.sprouts or age_years(tree) < GERMINATION_YEARS)

# 芽が出なかったと分かった種(翌日の確認で消える)
func has_failed(tree: Dictionary) -> bool:
	return tree.form == "seed" and not tree.sprouts and real_age_years(tree) >= GERMINATION_YEARS

# 足元の木に水をあげる。結果コードを返す: watered / none / done
func water_nearest(pos: Vector2, max_dist: float) -> String:
	var best := nearest_index(pos, max_dist, "")
	if best < 0:
		return "none"
	if not _water(trees[best]):
		return "done"
	_commit()
	return "watered"

# まだ今日水をあげていない木すべてに水をあげる(雨の日)。あげた本数を返す
func water_all() -> int:
	var n := 0
	for t in trees:
		if _water(t):
			n += 1
	if n > 0:
		_commit()
	return n

# center から radius 以内の、まだ今日水をあげていない木の数
func dry_within(center: Vector2, radius: float) -> int:
	var n := 0
	for t in trees:
		if t.pos.distance_to(center) <= radius and not watered_today(t):
			n += 1
	return n

# center から radius 以内の木に、まとめて水をあげる(池から)。あげた本数を返す
func water_within(center: Vector2, radius: float) -> int:
	var n := 0
	for t in trees:
		if t.pos.distance_to(center) <= radius and _water(t):
			n += 1
	if n > 0:
		_commit()
	return n

func _water(tree: Dictionary) -> bool:
	if tree.last_watered == today():
		return false
	tree.last_watered = today()
	tree.bonus_years += WATER_BONUS_YEARS
	return true

# pos から max_dist 未満でいちばん近い木の添字。species が空なら全樹種。なければ -1
func nearest_index(pos: Vector2, max_dist: float, species: String) -> int:
	var best := -1
	var best_d := max_dist
	for i in range(trees.size()):
		if species != "" and trees[i].species != species:
			continue
		var d: float = trees[i].pos.distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best

# 日付が変わっていたら、その日の発見を 1 つ起こして id を返す。変わっていなければ ""
# あわせて: 芽が出なかった種を片づけ(last_failed に数を残す)、育った木が今日落とした種を地面に置く
func check_new_day() -> String:
	var t := today()
	if last_day == t:
		return ""
	# 時計が前の日に戻ったとき(PC の時計を直したなど)は、新しい日にしない。戻した日の発見や種がもう一度起きないように
	# (日付は YYYY-MM-DD なので、文字の順 = 日付の順)
	if last_day != "" and t < last_day:
		return ""
	last_day = t
	last_failed = {}
	for i in range(trees.size() - 1, -1, -1):
		if has_failed(trees[i]):
			var sp: String = trees[i].species
			last_failed[sp] = int(last_failed.get(sp, 0)) + 1
			trees.remove_at(i)
	drop_seeds(t)
	today_event = roll_daily_event(t)
	_apply_event(today_event)
	_commit()
	return today_event

# 育った木が、実る季節なら根元に種を落とす。前の日の分は消える(たまらない)
func drop_seeds(date: String) -> void:
	pickups.clear()
	for i in range(trees.size()):
		var tree: Dictionary = trees[i]
		var sp: Dictionary = SPECIES[tree.species]
		if sp.seed_age <= 0.0 or not (season in sp.seed_seasons):
			continue
		if not is_established(tree) or real_age_years(tree) < sp.seed_age:
			continue
		# 落ちる場所は日付と木から決まる(根元から 1〜2.5m)
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%s:%d:%.2f:%.2f" % [date, i, tree.pos.x, tree.pos.y]).hash()
		var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.0, 2.5)
		pickups.append({"pos": tree.pos + off, "species": tree.species, "amount": int(sp.seed_drop)})

# pos から radius 以内に落ちている種を拾う。拾ったもの [{species, amount}] を返す
func collect_near(pos: Vector2, radius: float) -> Array:
	var got := []
	for i in range(pickups.size() - 1, -1, -1):
		var p: Dictionary = pickups[i]
		if p.pos.distance_to(pos) <= radius:
			seeds[p.species] = int(seeds.get(p.species, 0)) + int(p.amount)
			got.append({"species": p.species, "amount": int(p.amount)})
			pickups.remove_at(i)
	if not got.is_empty():
		_commit()
	return got

# 日付から決まる発見の id(同じ日付なら必ず同じ)
func roll_daily_event(date: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = date.hash()
	var events := daily_events()
	var total := 0
	for e in events:
		total += e[1]
	var r := rng.randi_range(0, total - 1)
	for e in events:
		if r < e[1]:
			return e[0]
		r -= e[1]
	return events[-1][0]

# 日替わりの発見と重み。雨の重みは土地で変わり、そのぶん鳥(演出だけ)を減らす
func daily_events() -> Array:
	if region == null:
		return DAILY_EVENTS
	var rain: int = clampi(region.rain_weight(), 0, 50)
	return [DAILY_EVENTS[0], DAILY_EVENTS[1], ["rain", rain], ["birds", 50 - rain]]

func _apply_event(id: String) -> void:
	match id:
		"birch_seed":
			seeds[wind_seed()] += 1
		"cedar_seed":
			seeds[nut_seed()] += 1
		"rain":
			water_all()

# リンゴ 1 本の 1 年(= 1 日)の収穫量。樹齢 6 年で 5 個、1 年ごとに 5 個ずつ増えて上限まで。
# 現実の 1 年分より少ない。秋のあいだ毎日採れるので、多いと畑が要らなくなる
const APPLE_MAX_YIELD := 20
static func apple_yield(age: float) -> int:
	return fruit_yield("apple", age)

# 果樹 1 本の 1 年(= 1 日)の収穫量。実りはじめから、1 年ごとに増えて上限まで
static func fruit_yield(species: String, age: float) -> int:
	var f: Dictionary = FRUITS[species]
	return clampi(int(f.first) + int((age - float(f.age)) * float(f.step)), int(f.first), int(f.most))

var last_harvest_count := 0  # 直前の収穫で採れた量(文言用)
var last_harvest_item := ""  # 直前に収穫した果物、または収穫できなかった果樹(文言用)
var last_harvest_extra := 0  # 直前の収穫のうち、剪定で増えた量(文言用)
var last_harvest_wait := 0   # 直前に収穫できなかった果樹が、次に実るまでの日数(文言用)
var last_meal_extra := 0     # 直前の収穫のうち、食べたもので増えた量(文言用)
var harvest_rate := Callable()  # () -> float。GameWorld が Kitchen.harvest_rate を設定する(台所は森を持つので、互いに持つと解放されない)
var last_prune_item := ""    # 直前に剪定した、または剪定できなかった果樹(文言用)

# 実をつける年になったリンゴの本数(季節は見ない)
func fruiting_apples() -> int:
	var n := 0
	for tree in trees:
		if tree.species == "apple" and is_established(tree) and real_age_years(tree) >= APPLE_FRUIT_AGE:
			n += 1
	return n

# その季節に実る、実をつける年になった果樹の本数(日記・ヒント・手詰まりの判定用)
func fruiting_in(in_season: String) -> int:
	var n := 0
	for tree in trees:
		if FRUITS.has(tree.species) and in_season in FRUITS[tree.species].seasons \
				and is_established(tree) and real_age_years(tree) >= float(FRUITS[tree.species].age):
			n += 1
	return n

# 収穫した果樹が次に実るまでの日数(0 = 今日採れる)。収穫してから FRUIT_INTERVAL 日で、また実る
func days_until_ripe(tree: Dictionary) -> int:
	var last: String = str(tree.get("last_harvest", ""))
	if last == "":
		return 0
	var since: int = day_number() - int(Time.get_unix_time_from_datetime_string(last) / 86400.0)
	return maxi(0, FRUIT_INTERVAL - since)

# その季節に実る果樹のうち、days_ahead 日後までに収穫できる本数(日記用。0 = 今日)
func ripe_fruit_count(in_season: String, days_ahead := 0) -> int:
	return trees.filter(func(t): return FRUITS.has(t.species) and in_season in FRUITS[t.species].seasons 			and is_established(t) and real_age_years(t) + days_ahead >= float(FRUITS[t.species].age) 			and days_until_ripe(t) <= days_ahead).size()

# pos から max_dist 以内で、いちばん近い果樹の番号(なければ -1)
func nearest_fruit_index(pos: Vector2, max_dist: float) -> int:
	var best := -1
	var best_d := max_dist
	for i in range(trees.size()):
		if FRUITS.has(trees[i].species):
			var d: float = trees[i].pos.distance_to(pos)
			if d <= best_d:
				best_d = d
				best = i
	return best

# 足元の果樹を収穫する。結果を表すコードを返す(文言は Main が決める)
#   harvested / none / preview / not_season / young / done
func harvest_nearest(pos: Vector2, max_dist: float) -> String:
	var best := nearest_fruit_index(pos, max_dist)
	if best < 0:
		return "none"
	# 先送りで若木を実らせて収穫できないよう、判定は現実の樹齢で行い、プレビュー中は収穫させない
	if time_offset_years > 0.0:
		return "preview"
	var tree: Dictionary = trees[best]
	var f: Dictionary = FRUITS[tree.species]
	last_harvest_item = tree.species
	if not (season in f.seasons):
		return "not_season"
	if not is_established(tree) or real_age_years(tree) < float(f.age):
		return "young"
	last_harvest_wait = days_until_ripe(tree)
	if last_harvest_wait > 0:
		return "done"
	tree.last_harvest = today()
	var base := fruit_yield(tree.species, real_age_years(tree))
	last_harvest_extra = ceili(base * PRUNE_BONUS) - base if is_pruned(tree) else 0
	last_harvest_count = base + last_harvest_extra
	var before_meal := last_harvest_count
	if harvest_rate.is_valid():
		last_harvest_count = ceili(last_harvest_count * float(harvest_rate.call()))
	last_meal_extra = last_harvest_count - before_meal
	produce[tree.species] = int(produce.get(tree.species, 0)) + last_harvest_count
	_commit()
	return "harvested"

# 12 月の剪定は翌年の収穫に、1〜2 月の剪定はその年の収穫に効く。その日の剪定が効く収穫の年(今までのルール)
static func harvest_year_of(date: String) -> int:
	var year := int(date.substr(0, 4))
	return year + 1 if int(date.substr(5, 2)) == 12 else year

# 土地の冬で数える: 年の後半の冬(北海道は 11 月から)の剪定は翌年の収穫に、年が明けてからの冬の剪定はその年の収穫に効く
func harvest_year_on(date: String) -> int:
	var year := int(date.substr(0, 4))
	return year + 1 if int(date.substr(5, 2)) >= 7 and season_of_date(date) == "winter" else year

# この冬(と、次の収穫まで)剪定が効いているか
func is_pruned(tree: Dictionary) -> bool:
	return int(tree.get("pruned_year", 0)) == harvest_year_on(today())

# 実をつける年になった果樹か
func _is_bearing(tree: Dictionary) -> bool:
	return FRUITS.has(tree.species) and is_established(tree) and real_age_years(tree) >= float(FRUITS[tree.species].age)

# まだ剪定していない、実をつける年になった果樹の本数(日記とヒント用)
func prunable_count() -> int:
	return trees.filter(func(t): return _is_bearing(t) and not is_pruned(t)).size()

func pruned_count() -> int:
	return trees.filter(func(t): return _is_bearing(t) and is_pruned(t)).size()

# 足元の果樹を剪定する。結果: pruned / none / preview / not_season / young / done
func prune_nearest(pos: Vector2, max_dist: float) -> String:
	var best := nearest_fruit_index(pos, max_dist)
	if best < 0:
		return "none"
	if time_offset_years > 0.0:
		return "preview"
	var tree: Dictionary = trees[best]
	last_prune_item = tree.species
	if season != "winter":
		return "not_season"
	if not _is_bearing(tree):
		return "young"
	if is_pruned(tree):
		return "done"
	tree.pruned_year = harvest_year_on(today())
	_commit()
	return "pruned"

# 今日(現地時間の YYYY-MM-DD)。GameWorld が渡す WorldTime から読む(なければ現実の時計)
func today() -> String:
	return time.today() if time != null else Time.get_date_string_from_system()

# 暦の日の通し番号(日付をまたぐと 1 増える。時刻によらない)
func day_number() -> int:
	return int(Time.get_unix_time_from_datetime_string(today()) / 86400.0)

# その日付が夏か(池の水が蒸発する)。土地の季節で決まる(今までのルールでは 6〜8 月)。テストで差し替えられるようにメソッドにしておく
func is_summer_date(date: String) -> bool:
	return season_of_date(date) == "summer"

# その日付の季節(土地の気候で決まる)
func season_of_date(date: String) -> String:
	return climate().season_of_date(date)

# 通し番号から日付(YYYY-MM-DD)に戻す
static func date_of_day(n: int) -> String:
	return Time.get_date_string_from_unix_time(n * 86400)

func _now() -> int:
	return time.now_unix() if time != null else int(Time.get_unix_time_from_system())

# 伐ったときに採れる丸太の本数(判定は現実の樹齢。先送りプレビューでは増えない)
func wood_yield(tree: Dictionary) -> int:
	if not is_established(tree):
		return 0
	var sp: Dictionary = SPECIES[tree.species]
	var age := real_age_years(tree)
	if age < sp.wood_age:
		return 0
	return mini(1 + int((age - sp.wood_age) / sp.wood_years), int(sp.wood_max))

func remove_nearest(pos: Vector2, max_dist: float) -> bool:
	var best := nearest_index(pos, max_dist, "")
	if best >= 0:
		trees.remove_at(best)
		_commit()
		return true
	return false

func advance_years(years: float) -> void:
	time_offset_years += years
	changed.emit()

# プレビューをやめて今日の姿に戻す
func reset_preview() -> void:
	time_offset_years = 0.0
	changed.emit()

# 表示用の樹齢(プレビューの先送りを含む)
func age_years(tree: Dictionary) -> float:
	return real_age_years(tree) + time_offset_years

# ゲームの判定用の樹齢(現実時間 + 苗木の樹齢 + 水やりのボーナス。プレビューは含まない)
func real_age_years(tree: Dictionary) -> float:
	return (_now() - tree.planted_at) / SECONDS_PER_YEAR + tree.start_age + tree.bonus_years

# 表示用の樹冠半径(m)。芽が出る前の種は 0
func radius_of(tree: Dictionary) -> float:
	if is_seed(tree):
		return 0.0
	var sp: Dictionary = SPECIES[tree.species]
	return sp.max_r * pow(1.0 - exp(-age_years(tree) / sp.tau), sp.p)

# 実が見えているか(果樹・実る季節・表示用の樹齢が実りはじめ以上・今日まだ収穫していない)
func shows_fruit(tree: Dictionary) -> bool:
	if not FRUITS.has(tree.species) or not (season in FRUITS[tree.species].seasons):
		return false
	return not is_seed(tree) and age_years(tree) >= float(FRUITS[tree.species].age) and days_until_ripe(tree) == 0

func watered_today(tree: Dictionary) -> bool:
	return tree.last_watered == today()

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
# 時間先送りはプレビューなので保存しない
func to_save() -> Dictionary:
	var data := {
		"seeds": seeds, "saplings": saplings, "produce": produce,
		"last_day": last_day, "today_event": today_event, "trees": [], "pickups": [],
	}
	for t in trees:
		data.trees.append({
			"x": t.pos.x, "y": t.pos.y,
			"species": t.species, "form": t.form, "planted_at": t.planted_at,
			"start_age": t.start_age, "sprouts": t.sprouts,
			"last_harvest": t.last_harvest,
			"last_watered": t.last_watered, "bonus_years": t.bonus_years,
			"pruned_year": int(t.get("pruned_year", 0)),
		})
	for p in pickups:
		data.pickups.append({"x": p.pos.x, "y": p.pos.y, "species": p.species, "amount": p.amount})
	return data

static func _counts(saved, base: Dictionary) -> Dictionary:
	var d := base.duplicate()
	var s := SaveRead.dict(saved)
	for k in base:
		if s.has(k):
			d[k] = SaveRead.count(s, k)  # 読めない数・マイナスは 0
	return d

func from_save(data: Dictionary) -> void:
	# 旧形式のセーブにある time_offset_years は読まない(先送りは 0 から)
	time_offset_years = 0.0
	# 記録がない旧形式のセーブは、初期の種・苗木 0・収穫物 0 から始める
	seeds = _counts(data.get("seeds", {}), initial_seeds())
	saplings = _counts(data.get("saplings", {}), zero_counts())
	produce = _counts(data.get("produce", {}), fruit_counts())
	# 記録がない旧形式のセーブは、次に開いたとき(= 今)その日の発見が起きる
	last_day = SaveRead.text(data, "last_day")
	today_event = SaveRead.text(data, "today_event")
	# 1 本ずつ確かめ、おかしな木だけ飛ばす(位置・樹種・植えた時刻のどれかが読めないもの)
	trees.clear()
	for item in SaveRead.list(data.get("trees")):
		var t := SaveRead.dict(item)
		var pos = SaveRead.point(t)
		var species := SaveRead.text(t, "species")
		if pos == null or not (species in SPECIES) or not SaveRead.is_num(t.get("planted_at")):
			continue
		trees.append({
			"pos": pos,
			"species": species,
			# form がない木は種・苗木を分ける前に植えたもの(根付いている扱い)
			"form": SaveRead.text(t, "form"),
			"planted_at": SaveRead.whole(t, "planted_at"),
			"start_age": maxf(0.0, SaveRead.num(t, "start_age")),
			"sprouts": SaveRead.flag(t, "sprouts", true),
			"last_harvest": SaveRead.text(t, "last_harvest"),
			"last_watered": SaveRead.text(t, "last_watered"),
			"bonus_years": maxf(0.0, SaveRead.num(t, "bonus_years")),
			"pruned_year": SaveRead.whole(t, "pruned_year"),
		})
	pickups.clear()
	for item in SaveRead.list(data.get("pickups")):
		var p := SaveRead.dict(item)
		var pos = SaveRead.point(p)
		if pos != null and SaveRead.text(p, "species") in SPECIES:
			pickups.append({"pos": pos, "species": p.species, "amount": SaveRead.count(p, "amount")})
	changed.emit()
