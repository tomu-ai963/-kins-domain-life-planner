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
const Quests = preload("res://logic/Quests.gd")
const Market = preload("res://logic/Market.gd")

const SAVE_PATH := "user://kins_domain_save.json"
const SAVE_UNIT := "m"           # セーブの座標の単位。この印がない古いセーブは px(40px = 1m)
const OLD_PX_PER_M := 40.0
const BACKUP_DIR := "user://backups"  # セーブの控えの置き場所
const BACKUP_PREFIX := "kins_domain_save_"
const BACKUP_KEEP := 7           # 控えを残す日数

var forest := Forest.new()
var land := Land.new()
var garden := Garden.new()
var cabin := Cabin.new()
var pond := Pond.new()
var quests := Quests.new()
var market := Market.new()
var save_path := SAVE_PATH       # テストでは別のファイルに向ける
var backup_dir := ""             # 控えを置くフォルダ。空なら控えを取らない(本物のセーブのときだけ Main が設定する)

func _init() -> void:
	quests.forest = forest
	quests.land = land
	quests.pond = pond
	pond.forest = forest
	pond.land = land
	garden.forest = forest
	garden.land = land
	cabin.forest = forest
	cabin.land = land
	market.forest = forest
	market.garden = garden
	market.cabin = cabin
	forest.dirty.connect(save_game)
	garden.dirty.connect(save_game)
	cabin.dirty.connect(save_game)
	pond.dirty.connect(save_game)

# 足元に菜園の区画を置く / 取り消す。小屋にかかる場所には置けない
# 結果: Garden.toggle_plot の結果か cabin
func toggle_plot(pos: Vector2) -> String:
	if land.plot_at(pos) == null and cabin.blocks_plot(land.plot_center(pos)):
		return "cabin"
	return garden.toggle_plot(pos)

# P: 池がなければ足元を池の場所に決める。あれば今日の分を掘る
# 結果: placed / outside / cabin(場所を決めるとき)、Pond.dig の結果(掘るとき)
func pond_action(pos: Vector2) -> String:
	if land.pond != null:
		return pond.dig(pos)
	if cabin.blocks_pond(pos):
		return "cabin"
	return land.toggle_pond(pos)

# 日付が変わっていたら、その日の発見を起こして id を返す(Forest.check_new_day)。雨は畑にも降り、池にたまる
func check_new_day() -> String:
	var id: String = forest.check_new_day()
	if id == "rain":
		garden.water_all()
	if id != "":
		pond.catch_up()
	return id

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
	# Godot 3 版(2026-11 より前)のセーブは座標が px。読むときに m に直す
	if data.get("unit", "px") != SAVE_UNIT:
		_px_to_m(data, ld)
	land.from_save(ld)
	pond.from_save(pod)
	garden.from_save(gd)
	cabin.from_save(cd)
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
