extends RefCounted

# ── ゲーム全体の状態(描画を持たない) ──────────────────────────
# 木と種(Forest)・菜園と池(Land)・段階クエスト(Quests)・お金と市場(Market)をまとめ、
# 1 つのセーブファイルに読み書きする。Forest の保存が必要な変更(dirty)で自動保存する
# 座標の単位は m(ドメイン中心が原点、境界は ±50m)
const Forest = preload("res://logic/Forest.gd")
const Land = preload("res://logic/Land.gd")
const Quests = preload("res://logic/Quests.gd")
const Market = preload("res://logic/Market.gd")

const SAVE_PATH := "user://kins_domain_save.json"
const SAVE_UNIT := "m"           # セーブの座標の単位。この印がない古いセーブは px(40px = 1m)
const OLD_PX_PER_M := 40.0

var forest := Forest.new()
var land := Land.new()
var quests := Quests.new()
var market := Market.new()
var save_path := SAVE_PATH       # テストでは別のファイルに向ける

func _init() -> void:
	quests.forest = forest
	quests.land = land
	market.forest = forest
	forest.dirty.connect(save_game)

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
	# Godot 3 版(2026-11 より前)のセーブは座標が px。読むときに m に直す
	if data.get("unit", "px") != SAVE_UNIT:
		_px_to_m(data, ld)
	land.from_save(ld)
	quests.from_save(qd)
	market.from_save(md)
	forest.from_save(data)

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
