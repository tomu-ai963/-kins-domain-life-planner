extends RefCounted

# ── 土地に来る生き物(描画を持たない) ──────────────────────────────
# 土地の様子・季節・時間帯・天気から、今どの生き物が何匹いるかを決める。見て楽しむだけで、ルールには関わらない。
# 木や畑が増えると来る生き物が増える(現実でも、木と作物があると生き物が集まる)。
# はじめて来た生き物だけ覚えて知らせる。池の生き物は logic/Pond.gd が持つ。
# 文言は Main、見た目は view/ が決める。座標の単位は m
const SaveRead = preload("res://logic/SaveRead.gd")
const Forest = preload("res://logic/Forest.gd")
const Land = preload("res://logic/Land.gd")
const Garden = preload("res://logic/Garden.gd")
const Cabin = preload("res://logic/Cabin.gd")
const DayClock = preload("res://logic/DayClock.gd")

signal dirty  # セーブに入る状態が変わった

const MATURE_AGE := 5.0   # 実や種をつけはじめる目安の樹齢(年)。リスはこの木に来る
const DAY_DARKNESS := 0.5 # 暗さがこれ以下なら昼の生き物が出る
const DUSK_DARKNESS := 0.2  # 暗さがこれ以上ならノウサギが出る(夕方から朝まで)
const NIGHT_DARKNESS := 0.9 # 暗さがこれ以上ならハリネズミが出る
const EDGE_MARGIN := 0.5  # 土地の端からこの幅には行かない
const CABIN_MARGIN := 0.4 # 小屋の周りでこの幅には行かない

const ALL_YEAR := ["spring", "summer", "autumn", "winter"]
const WARM := ["spring", "summer", "autumn"]

# 気候区分(Region.ZONES)の組
const COLD_ZONES := ["hokkaido", "tohoku", "snowy", "highland"]
const WARM_ZONES := ["pacific", "setouchi", "south"]
const HONSHU_TO_KYUSHU := ["tohoku", "snowy", "highland", "pacific", "setouchi", "south"]

# seasons: 見られる季節 / time: day(昼) dusk(夕方〜朝) night(夜) any(いつでも) / fair: 雨や雪の日は出ない
# role: 来る条件と住みか(_wanted・home_for)を、どの生き物と同じにするか(なければ自分の id)
# zones: いる気候区分(なければどこにでもいる。空なら、県を選ぶ前の今までのルールでだけ出る)。現実の分布の目安から
# regional: 県を選んでから出る生き物(選ぶ前の今までのルールには出てこない)
const SPECIES := {
	"sparrow": {"name": "小鳥", "seasons": ALL_YEAR, "time": "day", "fair": false},
	"squirrel": {"name": "リス", "seasons": ALL_YEAR, "time": "day", "fair": false,
		"zones": ["tohoku", "snowy", "highland", "pacific", "setouchi"]},  # ニホンリス: 本州と四国(九州ではほとんど見られない。沖縄にはいない)
	"butterfly": {"name": "チョウ", "seasons": WARM, "time": "day", "fair": true},
	"bee": {"name": "ミツバチ", "seasons": WARM, "time": "day", "fair": true},
	"hare": {"name": "ノウサギ", "seasons": ALL_YEAR, "time": "dusk", "fair": false, "zones": HONSHU_TO_KYUSHU},
	"hedgehog": {"name": "ハリネズミ", "seasons": WARM, "time": "night", "fair": false, "zones": []},  # 日本には野生のハリネズミがいない
	"migrant": {"name": "渡り鳥", "seasons": ALL_YEAR, "time": "any", "fair": false},
	"tit": {"name": "シジュウカラ", "seasons": ["autumn", "winter"], "time": "day", "fair": false},
	"bullfinch": {"name": "ウソ", "seasons": ["winter"], "time": "day", "fair": false, "zones": COLD_ZONES},
	"woodpecker": {"name": "アカゲラ", "seasons": ["winter"], "time": "day", "fair": false, "zones": COLD_ZONES},
	"starling": {"name": "ムクドリ", "seasons": ["spring", "summer"], "time": "day", "fair": false},
	# ── 県を選ぶようにして足した生き物(2026-11-11) ──
	"ezo_squirrel": {"name": "エゾリス", "seasons": ALL_YEAR, "time": "day", "fair": false, "role": "squirrel", "zones": ["hokkaido"], "regional": true},
	"snow_hare": {"name": "エゾユキウサギ", "seasons": ALL_YEAR, "time": "dusk", "fair": false, "role": "hare", "zones": ["hokkaido"], "regional": true},  # 冬は白い毛になる
	"kuina": {"name": "ヤンバルクイナ", "seasons": ALL_YEAR, "time": "dusk", "fair": false, "role": "hare", "zones": ["nansei"], "regional": true},  # 飛べない鳥。朝夕に畑のまわりを歩く
	"tanuki": {"name": "タヌキ", "seasons": ALL_YEAR, "time": "night", "fair": false, "role": "hedgehog", "zones": HONSHU_TO_KYUSHU, "regional": true},
	"fox": {"name": "キタキツネ", "seasons": ALL_YEAR, "time": "dusk", "fair": false, "role": "hedgehog", "zones": ["hokkaido"], "regional": true},
	"fruit_bat": {"name": "オリイオオコウモリ", "seasons": ALL_YEAR, "time": "night", "fair": false, "zones": ["nansei"], "regional": true},  # 夜、木の実や花の蜜を食べに来る
	"yamagara": {"name": "ヤマガラ", "seasons": ["autumn", "winter"], "time": "day", "fair": false, "role": "bullfinch", "zones": WARM_ZONES, "regional": true},  # どんぐりが好き
	"mejiro": {"name": "メジロ", "seasons": ["autumn", "winter"], "time": "day", "fair": false, "role": "bullfinch", "zones": ["nansei"], "regional": true},
	"kogera": {"name": "コゲラ", "seasons": ["winter"], "time": "day", "fair": false, "role": "woodpecker", "zones": ["pacific", "setouchi", "south", "nansei"], "regional": true},
}
const TITS_PER_FEEDER := 2       # 餌のある餌台 1 つに来るシジュウカラ(秋と冬)
const BULLFINCHES_PER_FEEDER := 1  # 餌のある餌台 1 つに来るウソ(冬だけ。雪の上で赤い胸が映える冬の鳥)
const MIGRANT_FLOCK := 7     # 渡り鳥の群れの数(発見の日だけ来る)
const MIGRANT_NEAR := 9.0    # 渡り鳥は、足元からこの距離に降りる

var forest: Forest   # GameWorld が設定する
var land: Land
var garden: Garden
var cabin: Cabin
var clock: DayClock
var bees = null      # GameWorld が設定する(巣箱の上には行かない)
var feeders = null   # GameWorld が設定する(餌があると鳥が来る)
var nest_boxes = null  # GameWorld が設定する(掛けた巣箱にムクドリが来る)

var seen := []       # 一度でも来た生き物の id

# 今の暗さ(0 = 昼、1 = 夜)。N のプレビューも含む(見た目を光に合わせるため)
func darkness() -> float:
	var hours: float = fposmod(clock.real_hours() + clock.preview_hours, 24.0)
	return DayClock.darkness(DayClock.elevation_deg(clock.sun_dir(hours, clock.today_of_year())))

func _time_fits(time: String) -> bool:
	var d := darkness()
	match time:
		"day":
			return d <= DAY_DARKNESS
		"dusk":
			return d >= DUSK_DARKNESS
		"night":
			return d >= NIGHT_DARKNESS
	return true

# 昼の生き物が出る明るさか
func is_daytime() -> bool:
	return _time_fits("day")

# 午後か(暗いときに「昼のあいだに来ていた」か「明るくなると来る」かを分ける)。N のプレビューも含む
func is_afternoon() -> bool:
	return fposmod(clock.real_hours() + clock.preview_hours, 24.0) >= 12.0

# この土地にいる生き物か(県を選ぶ前は、今までの生き物だけ)
func lives_here(id: String) -> bool:
	var s: Dictionary = SPECIES[id]
	if forest == null or forest.region == null:
		return not s.get("regional", false)
	return not s.has("zones") or forest.region.zone_id() in s.zones

# 来る条件と住みかが同じ生き物の id(エゾリスならリス)
static func role_of(id: String) -> String:
	return str(SPECIES[id].get("role", id))

# この土地にいる生き物の id(SPECIES の順)
func local_species() -> Array:
	return SPECIES.keys().filter(func(id): return lives_here(id))

# 餌のある餌台 1 つに来る鳥の数 {id: 数}。時間帯は見ない(暗くて見えないときに、昼の様子を知らせる用)
func feeder_birds() -> Dictionary:
	var out := {}
	var per := {"tit": TITS_PER_FEEDER, "bullfinch": BULLFINCHES_PER_FEEDER}
	for id in local_species():
		var role := role_of(id)
		if per.has(role) and forest.season in SPECIES[id].seasons:
			out[id] = per[role]
	return out

# 根付いた木の数と、そのうち育った木の数 [根付いた木, 育った木]
func _tree_counts() -> Array:
	var all := 0
	var mature := 0
	for t in forest.trees:
		if forest.is_established(t):
			all += 1
			if forest.real_age_years(t) >= MATURE_AGE:
				mature += 1
	return [all, mature]

# 土地の様子から決まる数(季節・時間帯は見ない)
func _wanted(id: String) -> int:
	var today_event: String = forest.today_event if forest.last_day == forest.today() else ""
	var trees: Array = _tree_counts()
	var crops: int = garden.crops.size()
	var plots: int = land.plots.size()
	match role_of(id):
		"sparrow":  # 木が 3 本あれば来る
			return mini(6, ceili(trees[0] / 4.0)) if trees[0] >= 3 else 0
		"squirrel":  # 育った木が 3 本あれば来る。杉の実を置いていった日は必ずいる
			var n: int = mini(3, 1 + int(trees[1] / 10.0)) if trees[1] >= 3 else 0
			return maxi(n, 1) if today_event == "cedar_seed" else n
		"butterfly":  # 畑に野菜があれば来る
			return mini(5, 1 + int(crops / 4.0)) if crops >= 1 else 0
		"bee":
			return mini(6, 2 + int(crops / 4.0)) if crops >= 1 else 0
		"hare":  # 区画が 4 つあれば来る
			return mini(2, 1 + int(plots / 40.0)) if plots >= 4 else 0
		"hedgehog":  # 区画か木が多ければ来る
			return mini(2, 1 + int(plots / 40.0)) if plots >= 4 or trees[0] >= 10 else 0
		"migrant":  # 渡り鳥の発見の日だけ
			return MIGRANT_FLOCK if today_event == "birds" else 0
		"tit":  # 餌台に餌があるあいだだけ
			return TITS_PER_FEEDER * feeders.fed_count() if feeders != null else 0
		"bullfinch":
			return BULLFINCHES_PER_FEEDER * feeders.fed_count() if feeders != null else 0
		"woodpecker":  # 冬、育った木が 3 本あれば来る(幹の中の虫を探す)。10 本で 2 羽
			return mini(2, 1 + int(trees[1] / 10.0)) if trees[1] >= 3 else 0
		"starling":  # 掛けた巣箱 1 つにつがい 1 組
			return nest_boxes.starlings() if nest_boxes != null else 0
		"fruit_bat":  # 夜、育った木が 3 本あれば来る。10 本で 2 匹
			return mini(3, 1 + int(trees[1] / 10.0)) if trees[1] >= 3 else 0
	return 0

# 今いる生き物の数 {id: 数}。いないものは入らない
func counts() -> Dictionary:
	var out := {}
	for id in local_species():
		var s: Dictionary = SPECIES[id]
		if not (forest.season in s.seasons) or not _time_fits(s.time):
			continue
		if s.fair and forest.is_raining():
			continue
		var n := _wanted(id)
		if n > 0:
			out[id] = n
	return out

# 今いる生き物のうち、はじめて来たものの id を返して覚える。
# プレビュー中は数えない(プレビューは保存しない約束)
func check_arrivals() -> Array:
	if clock.is_preview() or forest.time_offset_years > 0.0:
		return []
	var arrivals := []
	for id in counts():
		if not (id in seen):
			seen.append(id)
			arrivals.append(id)
	if not arrivals.is_empty():
		dirty.emit()
	return arrivals

# 生き物が行ける場所か(土地の中で、小屋と池の上ではない)
func is_free(pos: Vector2) -> bool:
	var limit: float = land.HALF - EDGE_MARGIN
	if absf(pos.x) > limit or absf(pos.y) > limit:
		return false
	if cabin.footprints().any(func(r): return r.grow(CABIN_MARGIN).has_point(pos)):
		return false
	if bees != null and bees.covers(pos):
		return false
	if feeders != null and feeders.covers(pos):
		return false
	return land.pond == null or pos.distance_to(land.pond) > land.POND_RADIUS

# その生き物の住みか。木のそば・畑・区画など。near は足元(渡り鳥は足元の近くに降りる)
func home_for(id: String, rng: RandomNumberGenerator, near: Vector2) -> Vector2:
	match role_of(id):
		"sparrow", "squirrel":
			var spots := []
			for t in forest.trees:
				if forest.is_established(t):
					spots.append(t.pos)
			if not spots.is_empty():
				return spots[rng.randi_range(0, spots.size() - 1)]
		"butterfly", "bee":
			if not garden.crops.is_empty():
				return garden.crops[rng.randi_range(0, garden.crops.size() - 1)].pos
		"hare", "hedgehog":
			if not land.plots.is_empty():
				return land.plots[rng.randi_range(0, land.plots.size() - 1)]
		"migrant":
			# 土地の内側へ少し離れたところ。足元が中心なら東へ
			var inward: Vector2 = -near.normalized() if near.length() > 1.0 else Vector2.RIGHT
			return near + inward * MIGRANT_NEAR
		"woodpecker", "fruit_bat":  # 育った木の幹 / 育った木の上
			var big := []
			for t in forest.trees:
				if forest.is_established(t) and forest.real_age_years(t) >= MATURE_AGE:
					big.append(t.pos)
			if not big.is_empty():
				return big[rng.randi_range(0, big.size() - 1)]
		"starling":  # 巣箱を掛けた木
			var hung: Array = nest_boxes.boxes.filter(func(b): return nest_boxes.is_done(b)) if nest_boxes != null else []
			if not hung.is_empty():
				return hung[rng.randi_range(0, hung.size() - 1)].pos
		"tit", "bullfinch":  # 餌のある餌台
			var fed: Array = feeders.feeders.filter(func(f): return feeders.is_fed(f)) if feeders != null else []
			if not fed.is_empty():
				return fed[rng.randi_range(0, fed.size() - 1)].pos
	return near

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	return {"seen": seen}

func from_save(d: Dictionary) -> void:
	seen = SaveRead.ids(d.get("seen"), SPECIES)
