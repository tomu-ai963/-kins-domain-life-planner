extends Reference

# ── ゲーム全体の状態(描画を持たない) ──────────────────────────
# 木と種(Forest)・菜園と池(Land)・段階クエスト(Quests)をまとめ、
# 1 つのセーブファイルに読み書きする。Forest の保存が必要な変更(dirty)で自動保存する
const Forest = preload("res://logic/Forest.gd")
const Land = preload("res://logic/Land.gd")
const Quests = preload("res://logic/Quests.gd")

const SAVE_PATH := "user://kins_domain_save.json"

var forest := Forest.new()
var land := Land.new()
var quests := Quests.new()
var save_path := SAVE_PATH       # テストでは別のファイルに向ける

func _init() -> void:
	quests.forest = forest
	quests.land = land
	forest.connect("dirty", self, "save_game")

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
	forest.set_season(season_for_month(OS.get_datetime().month))

# ── セーブ / ロード ──────────────────────────────────────────
func save_game() -> void:
	var data := forest.to_save()
	data["land"] = land.to_save()
	data["quests"] = quests.to_save()
	var f := File.new()
	if f.open(save_path, File.WRITE) == OK:
		f.store_string(to_json(data))
		f.close()

func load_game() -> void:
	var f := File.new()
	if not f.file_exists(save_path):
		return
	if f.open(save_path, File.READ) != OK:
		return
	var data = parse_json(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	# 2-2 以前のセーブには菜園・池・クエストの記録がない(空・段階 0 から)
	var ld = data.get("land", {})
	land.from_save(ld if typeof(ld) == TYPE_DICTIONARY else {})
	var qd = data.get("quests", {})
	quests.from_save(qd if typeof(qd) == TYPE_DICTIONARY else {})
	forest.from_save(data)
