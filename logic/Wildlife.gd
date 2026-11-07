extends RefCounted

# ── 土地に来る生き物(描画を持たない) ──────────────────────────────
# 土地の様子・季節・時間帯・天気から、今どの生き物が何匹いるかを決める。見て楽しむだけで、ルールには関わらない。
# 木や畑が増えると来る生き物が増える(現実でも、木と作物があると生き物が集まる)。
# はじめて来た生き物だけ覚えて知らせる。池の生き物は logic/Pond.gd が持つ。
# 文言は Main、見た目は view/ が決める。座標の単位は m
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

# seasons: 見られる季節 / time: day(昼) dusk(夕方〜朝) night(夜) any(いつでも) / fair: 雨や雪の日は出ない
const SPECIES := {
	"sparrow": {"name": "小鳥", "seasons": ALL_YEAR, "time": "day", "fair": false},
	"squirrel": {"name": "リス", "seasons": ALL_YEAR, "time": "day", "fair": false},
	"butterfly": {"name": "チョウ", "seasons": WARM, "time": "day", "fair": true},
	"bee": {"name": "ミツバチ", "seasons": WARM, "time": "day", "fair": true},
	"hare": {"name": "ノウサギ", "seasons": ALL_YEAR, "time": "dusk", "fair": false},
	"hedgehog": {"name": "ハリネズミ", "seasons": WARM, "time": "night", "fair": false},
	"migrant": {"name": "渡り鳥", "seasons": ALL_YEAR, "time": "any", "fair": false},
	"tit": {"name": "シジュウカラ", "seasons": ["autumn", "winter"], "time": "day", "fair": false},
	"bullfinch": {"name": "ウソ", "seasons": ["winter"], "time": "day", "fair": false},
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

var seen := []       # 一度でも来た生き物の id

# 今の暗さ(0 = 昼、1 = 夜)。N のプレビューも含む(見た目を光に合わせるため)
func darkness() -> float:
	var hours: float = fposmod(clock.real_hours() + clock.preview_hours, 24.0)
	return DayClock.darkness(DayClock.elevation_deg(DayClock.to_sun(hours, clock.today_of_year())))

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
	match id:
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
	return 0

# 今いる生き物の数 {id: 数}。いないものは入らない
func counts() -> Dictionary:
	var out := {}
	for id in SPECIES:
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
	if cabin.site != null and cabin.rect().grow(CABIN_MARGIN).has_point(pos):
		return false
	if bees != null and bees.covers(pos):
		return false
	if feeders != null and feeders.covers(pos):
		return false
	return land.pond == null or pos.distance_to(land.pond) > land.POND_RADIUS

# その生き物の住みか。木のそば・畑・区画など。near は足元(渡り鳥は足元の近くに降りる)
func home_for(id: String, rng: RandomNumberGenerator, near: Vector2) -> Vector2:
	match id:
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
		"tit", "bullfinch":  # 餌のある餌台
			var fed: Array = feeders.feeders.filter(func(f): return feeders.is_fed(f)) if feeders != null else []
			if not fed.is_empty():
				return fed[rng.randi_range(0, fed.size() - 1)].pos
	return near

# ── セーブ用(ファイルの読み書きは GameWorld) ───────────────────────
func to_save() -> Dictionary:
	return {"seen": seen}

func from_save(d: Dictionary) -> void:
	seen = []
	for id in d.get("seen", []):
		if SPECIES.has(str(id)):
			seen.append(str(id))
