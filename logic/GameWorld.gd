extends RefCounted

# ── ゲーム全体の状態(描画を持たない) ──────────────────────────
# 木と種(Forest)・菜園と池の場所(Land)・畑の野菜(Garden)・池の作り込み(Pond)・小屋(Cabin)・段階クエスト(Quests)・お金と市場(Market)をまとめ、
# 1 つのセーブファイルに読み書きする。Forest・Garden・Pond・Cabin の保存が必要な変更(dirty)で自動保存する
# 座標の単位は m(ドメイン中心が原点、境界は ±50m)
const Forest = preload("res://logic/Forest.gd")
const Land = preload("res://logic/Land.gd")
const Garden = preload("res://logic/Garden.gd")
const Cabin = preload("res://logic/Cabin.gd")
const Pond = preload("res://logic/Pond.gd")
const Seedlings = preload("res://logic/Seedlings.gd")
const Kitchen = preload("res://logic/Kitchen.gd")
const Wildlife = preload("res://logic/Wildlife.gd")
const Visitors = preload("res://logic/Visitors.gd")
const Guide = preload("res://logic/Guide.gd")
const Bees = preload("res://logic/Bees.gd")
const Feeders = preload("res://logic/Feeders.gd")
const Quests = preload("res://logic/Quests.gd")
const Market = preload("res://logic/Market.gd")
const DayClock = preload("res://logic/DayClock.gd")

const SAVE_PATH := "user://kins_domain_save.json"
const SAVE_UNIT := "m"           # セーブの座標の単位。この印がない古いセーブは px(40px = 1m)
const OLD_PX_PER_M := 40.0
const BACKUP_DIR := "user://backups"  # セーブの控えの置き場所
const BACKUP_PREFIX := "kins_domain_save_"
const BACKUP_KEEP := 7           # 控えを残す日数
const PRUNE_FIRES := 1           # 剪定 1 本で切った枝からできる薪(回分。仮の数字)

var forest := Forest.new()
var land := Land.new()
var garden := Garden.new()
var cabin := Cabin.new()
var pond := Pond.new()
var seedlings := Seedlings.new()
var kitchen := Kitchen.new()
var wildlife := Wildlife.new()
var visitors := Visitors.new()
var guide := Guide.new()
var bees := Bees.new()
var feeders := Feeders.new()
var quests := Quests.new()
var market := Market.new()
var clock := DayClock.new()      # 光の見た目と HUD の時計だけに使う。ルールには使わない
var sound_level := 3             # 音量の段階(0 = 消す、3 = いちばん大きい)。見た目の設定で、ルールには使わない
var save_path := SAVE_PATH       # テストでは別のファイルに向ける
var backup_dir := ""             # 控えを置くフォルダ。空なら控えを取らない(本物のセーブのときだけ Main が設定する)

func _init() -> void:
	quests.forest = forest
	quests.land = land
	quests.pond = pond
	pond.forest = forest
	pond.land = land
	pond.garden = garden
	garden.forest = forest
	garden.land = land
	cabin.forest = forest
	cabin.land = land
	market.forest = forest
	market.garden = garden
	market.cabin = cabin
	market.seedlings = seedlings
	market.kitchen = kitchen
	seedlings.forest = forest
	seedlings.garden = garden
	seedlings.cabin = cabin
	kitchen.forest = forest
	kitchen.garden = garden
	kitchen.cabin = cabin
	kitchen.bees = bees
	wildlife.forest = forest
	wildlife.land = land
	wildlife.garden = garden
	wildlife.cabin = cabin
	wildlife.clock = clock
	visitors.forest = forest
	visitors.garden = garden
	visitors.seedlings = seedlings
	visitors.market = market
	visitors.kitchen = kitchen
	visitors.bees = bees
	bees.forest = forest
	bees.land = land
	bees.garden = garden
	bees.cabin = cabin
	market.bees = bees
	wildlife.bees = bees
	guide.bees = bees
	feeders.forest = forest
	feeders.land = land
	feeders.cabin = cabin
	feeders.bees = bees
	bees.taken_nearby = feeders.covers
	wildlife.feeders = feeders
	visitors.feeders = feeders
	guide.feeders = feeders
	guide.forest = forest
	guide.land = land
	guide.garden = garden
	guide.cabin = cabin
	guide.pond = pond
	guide.market = market
	guide.kitchen = kitchen
	guide.visitors = visitors
	guide.wildlife = wildlife
	forest.dirty.connect(save_game)
	garden.dirty.connect(save_game)
	cabin.dirty.connect(save_game)
	pond.dirty.connect(save_game)
	seedlings.dirty.connect(save_game)
	kitchen.dirty.connect(save_game)
	wildlife.dirty.connect(save_game)
	visitors.dirty.connect(save_game)
	guide.dirty.connect(save_game)
	bees.dirty.connect(save_game)
	feeders.dirty.connect(save_game)

# 足元に菜園の区画を置く / 取り消す。小屋にかかる場所には置けない
# 結果: Garden.toggle_plot の結果か cabin / hive / feeder
func toggle_plot(pos: Vector2) -> String:
	if land.plot_at(pos) == null and cabin.blocks_plot(land.plot_center(pos)):
		return "cabin"
	if land.plot_at(pos) == null and bees.blocks_plot(land.plot_center(pos), land.PLOT_SIZE * 0.5):
		return "hive"
	if land.plot_at(pos) == null and feeders.blocks_plot(land.plot_center(pos), land.PLOT_SIZE * 0.5):
		return "feeder"
	return garden.toggle_plot(pos)

# X: 足元の果樹を剪定する。切った枝は薪になる。結果は Forest.prune_nearest
func prune(pos: Vector2, max_dist: float) -> String:
	var result: String = forest.prune_nearest(pos, max_dist)
	if result == "pruned":
		kitchen.add_firewood(PRUNE_FIRES)
	return result

# P: 池がなければ足元を池の場所に決める。あれば今日の分を掘る
# 結果: placed / outside / cabin(場所を決めるとき)、Pond.dig の結果(掘るとき)
func pond_action(pos: Vector2) -> String:
	if land.pond != null:
		return pond.dig(pos)
	if cabin.blocks_pond(pos):
		return "cabin"
	if bees.covers(pos, land.POND_RADIUS + bees.CLEARANCE):
		return "hive"
	if feeders.covers(pos, land.POND_RADIUS + bees.CLEARANCE):
		return "feeder"
	return land.toggle_pond(pos)

# 日付が変わっていたら、その日の発見を起こして id を返す(Forest.check_new_day)。
# 雨は畑にも降り、池にたまる。冬を迎えた野菜は霜で枯れる
func check_new_day() -> String:
	var id: String = forest.check_new_day()
	if id == "":
		visitors.check_today()  # 前のセーブを同じ日に開いたとき
		return id
	garden.apply_frost()
	if id == "rain":
		garden.water_all()
	pond.catch_up()
	bees.catch_up()
	visitors.check_today()  # 霜のあとの畑を見て、今日の頼みごとを決める
	return id

# 明日の日付(YYYY-MM-DD)
func tomorrow_date() -> String:
	return Forest.date_of_day(forest.day_number() + 1)

# 明日は雨(冬は雪)か。発見は日付から決まるので、前の日に分かる
func tomorrow_rain() -> bool:
	return forest.roll_daily_event(tomorrow_date()) == "rain"

# 季節は現実の日付から(3-5月=春 / 6-8月=夏 / 9-11月=秋 / 12-2月=冬)
static func season_for_month(m: int) -> String:
	if m >= 3 and m <= 5:
		return "spring"
	if m >= 6 and m <= 8:
		return "summer"
	if m >= 9 and m <= 11:
		return "autumn"
	return "winter"

func refresh_season() -> void:
	forest.set_season(season_for_month(Time.get_datetime_dict_from_system().month))

# ── セーブ / ロード ──────────────────────────────────────────
func save_game() -> void:
	var data := forest.to_save()
	data["unit"] = SAVE_UNIT
	data["land"] = land.to_save()
	data["garden"] = garden.to_save()
	data["cabin"] = cabin.to_save()
	data["pond"] = pond.to_save()
	data["seedlings"] = seedlings.to_save()
	data["kitchen"] = kitchen.to_save()
	data["wildlife"] = wildlife.to_save()
	data["visitors"] = visitors.to_save()
	data["guide"] = guide.to_save()
	data["bees"] = bees.to_save()
	data["feeders"] = feeders.to_save()
	data["sound_level"] = sound_level
	data["quests"] = quests.to_save()
	data["market"] = market.to_save()
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()

func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	_backup_save()
	# 2-2 以前のセーブには菜園・池・クエストの記録がない(空・段階 0 から)
	var ld = data.get("land", {})
	if typeof(ld) != TYPE_DICTIONARY:
		ld = {}
	var qd = data.get("quests", {})
	if typeof(qd) != TYPE_DICTIONARY:
		qd = {}
	# お金の記録がないセーブ(2026-11-03 より前)は、はじめの所持金から
	var md = data.get("market", {})
	if typeof(md) != TYPE_DICTIONARY:
		md = {}
	# 畑の記録がないセーブ(手順 3-1 まで)は、野菜なし・種 0 から
	var gd = data.get("garden", {})
	if typeof(gd) != TYPE_DICTIONARY:
		gd = {}
	# 小屋の記録がないセーブ(手順 3-2 まで)は、小屋なし・丸太 0 から
	var cd = data.get("cabin", {})
	if typeof(cd) != TYPE_DICTIONARY:
		cd = {}
	# 池の作り込みの記録がないセーブ(手順 3-3 まで)は、Pond.from_save が今ある池を満杯として扱う
	var pod = data.get("pond", {})
	if typeof(pod) != TYPE_DICTIONARY:
		pod = {}
	# 苗の記録がないセーブ(手順 3-4 まで)は、鉢も苗もなしから
	var sd = data.get("seedlings", {})
	if typeof(sd) != TYPE_DICTIONARY:
		sd = {}
	# 台所の記録がないセーブ(2026-11-06 より前)は、鍋は空・薪 0 から
	var kd = data.get("kitchen", {})
	if typeof(kd) != TYPE_DICTIONARY:
		kd = {}
	# 生き物の記録がないセーブ(2026-11-06 より前)は、まだ何も来ていない
	var wd = data.get("wildlife", {})
	if typeof(wd) != TYPE_DICTIONARY:
		wd = {}
	# 訪問者の記録がないセーブ(2026-11-06 より前)は、開いたときに今日の訪問を決める
	var vd = data.get("visitors", {})
	if typeof(vd) != TYPE_DICTIONARY:
		vd = {}
	# ヒントの記録がないセーブ(2026-11-06 より前)は、まだどのヒントも出ていない
	var gud = data.get("guide", {})
	if typeof(gud) != TYPE_DICTIONARY:
		gud = {}
	# 巣箱の記録がないセーブ(2026-11-06 より前)は、巣箱なしから
	var bd = data.get("bees", {})
	if typeof(bd) != TYPE_DICTIONARY:
		bd = {}
	# 餌台の記録がないセーブは、餌台なしから
	var fd = data.get("feeders", {})
	if typeof(fd) != TYPE_DICTIONARY:
		fd = {}
	# Godot 3 版(2026-11 より前)のセーブは座標が px。読むときに m に直す
	if data.get("unit", "px") != SAVE_UNIT:
		_px_to_m(data, ld)
	land.from_save(ld)
	pond.from_save(pod)
	garden.from_save(gd)
	cabin.from_save(cd)
	seedlings.from_save(sd)
	kitchen.from_save(kd)
	wildlife.from_save(wd)
	visitors.from_save(vd)
	guide.from_save(gud)
	bees.from_save(bd)
	feeders.from_save(fd)
	sound_level = clampi(int(data.get("sound_level", 3)), 0, 3)
	quests.from_save(qd)
	market.from_save(md)
	forest.from_save(data)

# その日はじめて読めたセーブを、日付つきで控える(壊れたセーブは呼ばれない)。新しい BACKUP_KEEP 日ぶんを残す
func _backup_save() -> void:
	if backup_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup_dir))
	var path := "%s/%s%s.json" % [backup_dir, BACKUP_PREFIX, forest.today()]
	if not FileAccess.file_exists(path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(path))
	var names := []
	for n in DirAccess.get_files_at(backup_dir):
		if n.begins_with(BACKUP_PREFIX):
			names.append(n)
	names.sort()  # 名前に日付が入っているので、古い順になる
	for i in range(names.size() - BACKUP_KEEP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [backup_dir, names[i]]))

static func _px_to_m(data: Dictionary, ld: Dictionary) -> void:
	for t in data.get("trees", []):
		if typeof(t) == TYPE_DICTIONARY:
			t["x"] = float(t.get("x", 0.0)) / OLD_PX_PER_M
			t["y"] = float(t.get("y", 0.0)) / OLD_PX_PER_M
	var plots := []
	for p in ld.get("plots", []):
		plots.append([float(p[0]) / OLD_PX_PER_M, float(p[1]) / OLD_PX_PER_M])
	ld["plots"] = plots
	var pd = ld.get("pond", null)
	if typeof(pd) == TYPE_ARRAY and pd.size() == 2:
		ld["pond"] = [float(pd[0]) / OLD_PX_PER_M, float(pd[1]) / OLD_PX_PER_M]
