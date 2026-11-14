extends RefCounted

# ── ゲーム全体の状態(描画を持たない) ──────────────────────────
# 木と種(Forest)・菜園と池の場所(Land)・畑の野菜(Garden)・池の作り込み(Pond)・小屋(Cabin)・段階クエスト(Quests)・お金と市場(Market)などをまとめ、
# 1 つのセーブファイルに読み書きする。保存が必要な変更(dirty)を出す 13 の部品(_init の dirty.connect の並び)で自動保存する。
# 今日の日付と時刻は WorldTime(time)から読む
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
const NestBoxes = preload("res://logic/NestBoxes.gd")
const Snow = preload("res://logic/Snow.gd")
const Quests = preload("res://logic/Quests.gd")
const Market = preload("res://logic/Market.gd")
const DayClock = preload("res://logic/DayClock.gd")
const WorldTime = preload("res://logic/WorldTime.gd")
const SaveRead = preload("res://logic/SaveRead.gd")
const Region = preload("res://logic/Region.gd")
const Wilds = preload("res://logic/Wilds.gd")
const Well = preload("res://logic/Well.gd")
const Tools = preload("res://logic/Tools.gd")

const SAVE_PATH := "user://kins_domain_save.json"
# セーブの版(2026-11-11 から書く。レビュー S4)。セーブの形を変える変更(名前・単位を変える、意味を変える)をしたら 1 上げ、
# load_game で古い版を新しい形に直す。版のないセーブは 0(キーがあるかないかで古さを見分けていたころのもの。今の読み方で読める)
const SAVE_VERSION := 1
const NEWER_INFIX := ".newer_"   # 新しい版のゲームで保存したセーブを、上書きする前に残す名前
const SAVE_UNIT := "m"           # セーブの座標の単位。この印がない古いセーブは px(40px = 1m)
const OLD_PX_PER_M := 40.0
const BACKUP_DIR := "user://backups"  # セーブの控えの置き場所
const BACKUP_PREFIX := "kins_domain_save_"
const BACKUP_KEEP := 7           # 控えを残す日数
const TMP_SUFFIX := ".tmp"       # 保存のときに先に書く別の名前(書けたら本物の名前に付け替える)
const BROKEN_INFIX := ".broken_" # 読めなかったセーブを残す名前(kins_domain_save.broken_日付_時刻.json)
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
var nest_boxes := NestBoxes.new()
var snow := Snow.new()
var quests := Quests.new()
var market := Market.new()
var time := WorldTime.new()      # ゲームの「今」。日付と時刻はここから読む(テストでは日付を進められる)
var clock := DayClock.new()      # 光の見た目と HUD の時計だけに使う。ルールには使わない
var region := Region.new()       # 土地のある都道府県と気候。はじめに 1 度だけ選ぶ(選ぶ前は今までのルール)
var wilds := Wilds.new()         # 一族の土地の外の自然の林(県から決まる。保存しない)
var well := Well.new()           # 井戸(2026-11-14)
var tools := Tools.new()         # ジョウロ・斧・ガソリンで動く機械(2026-11-14)
var last_pumped := [0, 0]        # 直前にポンプでまとめて水をやった [区画の数, 木の数](文言用・保存しない)
var is_new_game := false         # 読み込むセーブがなかった(新しく始めた)。県を選んだときに、その土地のはじめの種を配る
var sound_level := 3             # 音量の段階(0 = 消す、3 = いちばん大きい)。見た目の設定で、ルールには使わない
var save_path := SAVE_PATH       # テストでは別のファイルに向ける
var backup_dir := ""             # 控えを置くフォルダ。空なら控えを取らない(本物のセーブのときだけ Main が設定する)
var load_notice := ""            # 読み込みで知らせることがあれば、その文(セーブが読めず控えから戻したときなど)

func _init() -> void:
	wilds.forest = forest
	forest.time = time
	clock.time = time
	clock.region = region
	quests.forest = forest
	quests.land = land
	quests.pond = pond
	quests.wildlife = wildlife
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
	forest.harvest_rate = kitchen.harvest_rate
	garden.harvest_rate = kitchen.harvest_rate
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
	bees.taken_nearby = _taken_nearby
	well.forest = forest
	well.is_blocked = bees.is_blocked  # 巣箱と同じ決まり(区画・小屋・池・木・巣箱・餌台・井戸のそばと土地の端には掘れない)
	tools.forest = forest
	market.tools = tools
	market.well = well
	guide.well = well
	guide.tools = tools
	wildlife.feeders = feeders
	market.feeders = feeders
	visitors.feeders = feeders
	guide.feeders = feeders
	nest_boxes.forest = forest
	nest_boxes.cabin = cabin
	wildlife.nest_boxes = nest_boxes
	snow.forest = forest
	snow.land = land
	snow.cabin = cabin
	guide.snow = snow
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
	nest_boxes.dirty.connect(save_game)
	snow.dirty.connect(save_game)
	well.dirty.connect(save_game)
	tools.dirty.connect(save_game)

# 巣箱・餌台・井戸を置く場所に、ほかの物(餌台・井戸)がかかるか(Bees.is_blocked から呼ぶ)
func _taken_nearby(pos: Vector2, radius: float) -> bool:
	return feeders.covers(pos, radius) or well.covers(pos, radius)

# 足元に菜園の区画を置く / 取り消す。小屋にかかる場所には置けない
# 結果: Garden.toggle_plot の結果か cabin / hive / feeder / well
func toggle_plot(pos: Vector2) -> String:
	if land.plot_at(pos) == null and cabin.blocks_plot(land.plot_center(pos)):
		return "cabin"
	if land.plot_at(pos) == null and bees.blocks_plot(land.plot_center(pos), land.PLOT_SIZE * 0.5):
		return "hive"
	if land.plot_at(pos) == null and feeders.blocks_plot(land.plot_center(pos), land.PLOT_SIZE * 0.5):
		return "feeder"
	if land.plot_at(pos) == null and well.blocks_plot(land.plot_center(pos), land.PLOT_SIZE * 0.5):
		return "well"
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
	if well.covers(pos, land.POND_RADIUS + bees.CLEARANCE):
		return "well"
	return land.toggle_pond(pos)

# ── 水と道具(2026-11-14) ────────────────────────────────────
# 足元が水を汲める場所か。結果: well / pond / pond_frozen / pond_empty / ""(どちらのそばでもない)
func water_source(pos: Vector2) -> String:
	if well.is_beside(pos):
		return "well"
	if pond.is_beside(pos):
		if pond.is_frozen():
			return "pond_frozen"
		return "pond" if pond.water > 0 else "pond_empty"
	return ""

# 井戸か池のまわりの、水がいる [区画の数, 木の数](ポンプの案内用)。そばでなければ [0, 0]
func dry_around_source(pos: Vector2) -> Array:
	match water_source(pos):
		"well":
			return [garden.dry_within(well.site, well.WATER_RADIUS), forest.dry_within(well.site, well.WATER_RADIUS)]
		"pond":
			return pond.dry_around()
	return [0, 0]

# Q(井戸か池のそば・エンジンポンプを持っている): まわりの区画と木にまとめて水をやる。ガソリンを使う
# 結果: pumped / no_pump / no_gas / nothing / far / frozen / low(池の水が足りない)
func pump(pos: Vector2) -> String:
	var src := water_source(pos)
	if src == "":
		return "far"
	if not tools.has("pump"):
		return "no_pump"
	if src == "pond_frozen":
		return "frozen"
	var dry := dry_around_source(pos)
	if dry[0] + dry[1] == 0:
		return "nothing"
	if src == "pond" or src == "pond_empty":
		if pond.water < pond.WATER_COST:
			return "low"
	if not tools.can_run("pump"):
		return "no_gas"
	tools.use_gas("pump")
	if src == "well":
		last_pumped = [garden.water_within(well.site, well.WATER_RADIUS), forest.water_within(well.site, well.WATER_RADIUS)]
	else:
		pond.water_around(pos)  # 池の水も少し減る
		last_pumped = pond.last_watered
	return "pumped"

# Q(井戸か池のそば): ジョウロに汲む。結果: filled / full / far / frozen / empty(池に水がない)
func fill_can(pos: Vector2) -> String:
	match water_source(pos):
		"":
			return "far"
		"pond_frozen":
			return "frozen"
		"pond_empty":
			return "empty"
	if tools.can_full():
		return "full"
	tools.fill_can()
	return "filled"

# Q: 足元の区画にジョウロで水をやる(1L)。結果: Garden.water_at の結果か can_empty
func water_plot(pos: Vector2) -> String:
	var c: Dictionary = garden.crop_at(pos)
	if not c.is_empty() and not garden.is_ripe(c) and not garden.watered_today(c) and tools.can_water <= 0:
		return "can_empty"
	var result: String = garden.water_at(pos)
	if result == "watered":
		tools.pour()
	return result

# Q: 2m 以内の木にジョウロで水をやる(1L)。結果: Forest.water_nearest の結果か can_empty
func water_tree(pos: Vector2, max_dist: float) -> String:
	var i: int = forest.nearest_index(pos, max_dist, "")
	if i >= 0 and not forest.watered_today(forest.trees[i]) and tools.can_water <= 0:
		return "can_empty"
	var result: String = forest.water_nearest(pos, max_dist)
	if result == "watered":
		tools.pour()
	return result

# Z: 2m 以内の木が、斧でしか伐れず、今日はもう斧を振れないか(伐る前に見る。倒れる形を作る前に止めるため)
func axe_tired_for(pos: Vector2, max_dist: float) -> bool:
	var i: int = forest.nearest_index(pos, max_dist, "")
	return i >= 0 and forest.wood_yield(forest.trees[i]) > 0 and not tools.can_run("chainsaw") and tools.axe_left() <= 0

# Z: 2m 以内の木を伐る。丸太になる太さの木は斧かチェーンソーで、斧は 1 日 AXE_PER_DAY 本まで(細い木は手で抜くので数えない)。
# 結果: Cabin.fell の結果(丸太の本数。木がなければ -1)。斧がもう振れなければ -2。使った道具は tools.last_machine
func fell(pos: Vector2, max_dist: float) -> int:
	var i: int = forest.nearest_index(pos, max_dist, "")
	tools.last_machine = ""
	if i >= 0 and forest.wood_yield(forest.trees[i]) > 0:
		if tools.use_cutter() == "tired":
			return -2
	return cabin.fell(pos, max_dist)

# H(薪割り台): 薪割り機があってガソリンが足りれば、積める量まで一度に割る。なければ斧で 1 回割る。
# 結果: Kitchen.split の結果。薪割り機を使ったときは tools.last_machine == "splitter"
func split_wood() -> String:
	tools.last_machine = ""
	var k := kitchen
	if not tools.can_run("splitter") or k.firewood >= k.MAX_FIREWOOD:
		return k.split()
	var result: String = k.split()
	if result != "split":
		return result
	while k.split() == "split":
		pass
	tools.use_gas("splitter")
	return result

# I: 井戸の場所を決める / 掘る。結果は Well.act
func well_action(pos: Vector2, front: Vector2) -> String:
	return well.act(pos, front)

# 日付が変わっていたら、その日の発見を起こして id を返す(Forest.check_new_day)。
# 雨は畑にも降り、池にたまる。冬を迎えた野菜は霜で枯れる
func check_new_day() -> String:
	var id: String = forest.check_new_day()
	if id == "":
		visitors.check_today()  # 前のセーブを同じ日に開いたとき
		return id
	wilds.drop_today()  # 外の林で、今日が種の落ちる日の木
	garden.apply_frost()
	if id == "rain":
		garden.water_all()
	pond.catch_up()
	bees.catch_up()
	snow.catch_up()
	market.deliver_orders()  # 冬が終わっていれば、注文した春の種が届く
	visitors.check_today()  # 霜のあとの畑を見て、今日の頼みごとを決める
	return id

# 明日の日付(YYYY-MM-DD)
func tomorrow_date() -> String:
	return Forest.date_of_day(forest.day_number() + 1)

# 明日は雨(冬は雪)か。発見は日付から決まるので、前の日に分かる
func tomorrow_rain() -> bool:
	return forest.roll_daily_event(tomorrow_date()) == "rain"

# 季節は現実の日付と、土地の気候から(Region.ZONES。選ぶ前は 3-5月=春 / 6-8月=夏 / 9-11月=秋 / 12-2月=冬)
func season_for_month(m: int) -> String:
	return region.season_of_month(m)

func refresh_season() -> void:
	forest.set_season(season_for_month(time.month()))

# 県を決める(一度だけ。あとから変えられない)。新しいゲームなら、その土地のはじめの種にする。決めたら保存する
# 結果: chosen / already(もう決まっている) / unknown(知らない id)
func choose_region(id: String) -> String:
	if region.is_chosen():
		return "already"
	if not region.choose(id):
		return "unknown"
	forest.region = region
	refresh_season()
	wilds.refresh()
	if is_new_game:
		forest.start_stock()
	forest.changed.emit()
	save_game()
	return "chosen"

# ── セーブ / ロード ──────────────────────────────────────────
func save_game() -> void:
	var data := forest.to_save()
	data["version"] = SAVE_VERSION
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
	data["nest_boxes"] = nest_boxes.to_save()
	data["snow"] = snow.to_save()
	data["sound_level"] = sound_level
	data["region"] = region.to_save()
	data["quests"] = quests.to_save()
	data["market"] = market.to_save()
	data["well"] = well.to_save()
	data["tools"] = tools.to_save()
	_write_save(JSON.stringify(data))

# 別の名前(.tmp)に書き、書けたことを確かめてから本物の名前に付け替える。
# 途中で落ちても、本物のセーブは前の状態のまま残る
func _write_save(text: String) -> bool:
	var tmp := save_path + TMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("セーブを書けなかった: %s" % tmp)
		return false
	f.store_string(text)
	f.close()
	if FileAccess.get_file_as_string(tmp) != text:
		push_error("セーブを書けなかった(中身が違う): %s" % tmp)
		return false
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(save_path))
	if err != OK:
		push_error("セーブの名前を付け替えられなかった(%d): %s" % [err, save_path])
		return false
	return true

# ファイルを読んで、セーブとして読めれば Dictionary、読めなければ null
static func _read_save(path: String):
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()  # parse_string と違い、読めなくてもエラーを出力しない
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return json.data if typeof(json.data) == TYPE_DICTIONARY else null

func load_game() -> void:
	load_notice = ""
	is_new_game = false
	var data = _read_save(save_path)
	var tmp := save_path + TMP_SUFFIX
	if data == null and FileAccess.file_exists(save_path):
		data = _recover_broken_save()
		if data == null:
			is_new_game = true
			return  # 戻せるものがなかった。新しいゲームで始める(読めなかったファイルは別名で残してある)
	elif data == null:
		# セーブがない。付け替えの途中で落ちたなら、書き終えた .tmp が残っている
		data = _read_save(tmp)
		if data == null:
			is_new_game = true
			return  # はじめて開いた
		_write_save(FileAccess.get_file_as_string(tmp))
		_backup_save()
	else:
		_backup_save()
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	# 新しい版のゲームで保存したセーブ: 知らない記録が消えないよう、上書きする前に別名で残して知らせる
	var version := SaveRead.whole(data, "version", 0)
	if version > SAVE_VERSION:
		var kept := _keep_copy(NEWER_INFIX)
		load_notice = "このセーブは新しい版のゲームで保存されている(版 %d。このゲームは版 %d)。読めるところだけ読んだ。元のセーブは %s として残してある" % [version, SAVE_VERSION, kept.get_file()]
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
	# ムクドリの巣箱の記録がないセーブ(2026-11-11 より前)は、巣箱なしから
	var nbd = data.get("nest_boxes", {})
	if typeof(nbd) != TYPE_DICTIONARY:
		nbd = {}
	var fd = data.get("feeders", {})
	if typeof(fd) != TYPE_DICTIONARY:
		fd = {}
	# 雪かきの記録がないセーブは、道なしから
	var snow_data = data.get("snow", {})
	if typeof(snow_data) != TYPE_DICTIONARY:
		snow_data = {}
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
	nest_boxes.from_save(nbd)
	snow.from_save(snow_data)
	# 井戸と道具の記録がないセーブ(2026-11-14 より前)は、井戸なし・5L のジョウロが満杯から
	well.from_save(SaveRead.dict(data.get("well")))
	tools.from_save(SaveRead.dict(data.get("tools")))
	sound_level = clampi(SaveRead.whole(data, "sound_level", 3), 0, 3)
	# 県の記録がないセーブ(2026-11-11 より前)は、開いたときに一度だけ選ぶ
	region.from_save(data.get("region"))
	forest.region = region if region.is_chosen() else null
	refresh_season()
	market.from_save(md)
	forest.from_save(data)
	quests.from_save(qd)  # 木を読んだあと(木の節目を数えるため)

# 今のセーブを「名前.infix日付_時刻.json」として写して残す。残した名前を返す
func _keep_copy(infix: String) -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "_")
	var path := "%s%s%s.json" % [save_path.get_basename(), infix, stamp]
	DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(path))
	return path

# 読めないセーブを別名で残し、書きかけの .tmp か、いちばん新しい読める控えから戻す。
# 戻せたらその中身を本物のセーブに書き、戻せなければ null(新しいゲームになる)。
# どちらも load_notice で画面に知らせる。この日は控えを取らず、古い控えも消さない
func _recover_broken_save():
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "_")
	var broken := "%s%s%s.json" % [save_path.get_basename(), BROKEN_INFIX, stamp]
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(broken)) != OK:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(broken))
	var kept := "読めなかったファイルは %s として残してある" % broken.get_file()
	var source := ""
	var from := ""
	if _read_save(save_path + TMP_SUFFIX) != null:
		source = save_path + TMP_SUFFIX
		from = "書きかけの保存"
	else:
		for n in _backup_names(true):
			var path := "%s/%s" % [backup_dir, n]
			if _read_save(path) != null:
				source = path
				from = "%s の控え" % n.trim_prefix(BACKUP_PREFIX).get_basename()
				break
	if source == "":
		load_notice = "セーブが読めなかった。戻せる控えもなかったので、新しく始めた。%s" % kept
		return null
	_write_save(FileAccess.get_file_as_string(source))
	load_notice = "セーブが読めなかったので、%sから戻した。%s" % [from, kept]
	return _read_save(save_path)

# 控えのファイル名(日付が入っているので、名前の順 = 古い順)。newest_first なら新しい順
func _backup_names(newest_first := false) -> Array:
	var names := []
	if backup_dir == "" or not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(backup_dir)):
		return names
	for n in DirAccess.get_files_at(backup_dir):
		if n.begins_with(BACKUP_PREFIX):
			names.append(n)
	names.sort()
	if newest_first:
		names.reverse()
	return names

# その日はじめて読めたセーブを、日付つきで控える(読めなかった日は呼ばれない)。新しい BACKUP_KEEP 日ぶんを残す
func _backup_save() -> void:
	if backup_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup_dir))
	var path := "%s/%s%s.json" % [backup_dir, BACKUP_PREFIX, forest.today()]
	if not FileAccess.file_exists(path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(path))
	var names := _backup_names()
	for i in range(names.size() - BACKUP_KEEP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [backup_dir, names[i]]))

static func _px_to_m(data: Dictionary, ld: Dictionary) -> void:
	for t in SaveRead.list(data.get("trees")):
		var pos = SaveRead.point(SaveRead.dict(t))
		if pos != null:  # 位置の読めない木はそのまま(Forest が飛ばす)
			t["x"] = pos.x / OLD_PX_PER_M
			t["y"] = pos.y / OLD_PX_PER_M
	var plots := []
	for p in SaveRead.list(ld.get("plots")):
		var v = SaveRead.pair(p)
		if v != null:
			plots.append([v.x / OLD_PX_PER_M, v.y / OLD_PX_PER_M])
	ld["plots"] = plots
	var pd = SaveRead.pair(ld.get("pond"))
	if pd != null:
		ld["pond"] = [pd.x / OLD_PX_PER_M, pd.y / OLD_PX_PER_M]
