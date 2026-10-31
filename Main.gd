extends Node2D

# ── つなぎ役: 入力 → ロジック(logic/) → 文言(HUD) ─────────────────
# ゲームの状態とルールは logic/GameWorld.gd 以下、見た目は view/ 以下。
# Main はキー入力をロジックに渡し、結果コードを文言にして HUD に出す
const GameWorld = preload("res://logic/GameWorld.gd")

const SEASON_NAMES := {"spring": "春", "summer": "夏", "autumn": "秋", "winter": "冬"}

var world := GameWorld.new()
var selected_species := "birch"

var _season_timer := 0.0

func _ready() -> void:
	world.refresh_season()
	$Ground.setup(world.forest)
	$Land.setup(world.land)
	$Quests.setup(world.quests)
	$Trees.setup(world.forest)
	$HUD.setup($Player, world.forest, self)
	$Player.connect("plant_tree", self, "_on_plant_tree")
	world.load_game()
	_check_new_day()
	_check_quests()  # 旧セーブで条件を満たしていれば、開いた時点で達成する

func _process(delta: float) -> void:
	# 季節と日付は現実の日付から。1 分に 1 回チェックすれば十分(開いたまま日付をまたいでも拾う)
	_season_timer += delta
	if _season_timer >= 60.0:
		_season_timer = 0.0
		world.refresh_season()
		_check_new_day()

func _check_new_day() -> void:
	var id: String = world.forest.check_new_day()
	if id != "":
		$HUD.show_message("今日の発見: " + DAILY_MESSAGES[id], 8.0)

# 収穫の結果コード(Forest.harvest_nearest)ごとの文言
const HARVEST_MESSAGES := {
	"harvested": "リンゴを収穫した → リンゴの種 +%d",
	"none": "近くにリンゴの木がない",
	"preview": "未来のプレビュー中は収穫できない",
	"not_season": "リンゴが実るのは秋",
	"young": "まだ実らない(樹齢5年から)",
	"done": "この木は今日もう収穫した",
}

# 水やりの結果コード(Forest.water_nearest)ごとの文言
const WATER_MESSAGES := {
	"watered": "%sに水をあげた(樹齢 +%.1f年)",
	"none": "近くに木がない",
	"done": "この木には今日もう水をあげた",
}

# 日替わりの発見(Forest.DAILY_EVENTS の id)ごとの文言
const DAILY_MESSAGES := {
	"birch_seed": "白樺の種が落ちていた(白樺の種 +1)",
	"cedar_seed": "リスがシベリア杉の実を置いていった(シベリア杉の種 +1)",
	"rain": "雨が降った。今日は全部の木に水やり済み",
	"birds": "渡り鳥が来て、しばらく休んでいった",
}

# 段階クエスト(Quests.QUESTS の id)ごとの名前と進み具合の単位
const QUEST_TEXTS := {
	"hedge": {"name": "境界を生垣で囲む", "unit": "区画", "hint": "境界から3m以内に、10mごとに1本"},
	"garden": {"name": "菜園を作る", "unit": "区画", "hint": "F で3m四方の区画を置く"},
	"pond": {"name": "池を掘る", "unit": "", "hint": "P で足元に池を掘る"},
	"family_cedar": {"name": "中心に家族の杉を植える", "unit": "", "hint": "中心から5m以内にシベリア杉"},
}

# 菜園・池の結果コード(Land.toggle_plot / toggle_pond)ごとの文言
const PLOT_MESSAGES := {
	"placed": "菜園の区画を作った(%d区画)",
	"removed": "菜園の区画を草地に戻した",
	"outside": "土地の外には作れない",
}
const POND_MESSAGES := {
	"placed": "池を掘った",
	"removed": "池を埋めた",
	"one_only": "池はひとつまで(池の中で P を押すと埋める)",
	"outside": "土地の外には掘れない",
}

func _on_plant_tree(pos: Vector2) -> void:
	if not world.forest.add_tree(pos, selected_species):
		$HUD.show_message("%sの種がない" % world.forest.SPECIES[selected_species].name)
		return
	_check_quests()

func _toggle_plot() -> void:
	var result: String = world.land.toggle_plot($Player.global_position)
	var msg: String = PLOT_MESSAGES[result]
	if result == "placed":
		msg = msg % world.land.plots.size()
	$HUD.show_message(msg)
	_after_land_change(result)

func _toggle_pond() -> void:
	var result: String = world.land.toggle_pond($Player.global_position)
	$HUD.show_message(POND_MESSAGES[result])
	_after_land_change(result)

func _after_land_change(result: String) -> void:
	if result == "placed" or result == "removed":
		world.save_game()
		_check_quests()

# クエストを判定し、達成があれば知らせて保存する
func _check_quests() -> void:
	var done: Array = world.quests.advance()
	if done.empty():
		return
	world.save_game()
	if done.has("complete"):
		$HUD.show_message("愛の空間が完成した", 12.0)
		return
	var names := []
	for id in done:
		names.append(QUEST_TEXTS[id].name)
	var next: String = world.quests.current_id()
	$HUD.show_message("達成: %s → 次は「%s」" % [PoolStringArray(names).join("・"), QUEST_TEXTS[next].name], 8.0)

# HUD に出すクエストの 1 行
func quest_line() -> String:
	var q: Reference = world.quests
	if q.is_complete():
		return "クエスト: 愛の空間が完成した"
	var id: String = q.current_id()
	var t: Dictionary = QUEST_TEXTS[id]
	var p: Array = q.progress(id)
	var count := ""
	if t.unit != "":
		count = " %d/%d%s" % [p[0], p[1], t.unit]
	return "クエスト %d/%d: %s%s(%s)" % [q.stage + 1, q.QUESTS.size(), t.name, count, t.hint]

func _harvest() -> void:
	# 足元 2m 以内のリンゴを収穫する
	var result: String = world.forest.harvest_nearest($Player.global_position, 80.0)
	var msg: String = HARVEST_MESSAGES[result]
	if result == "harvested":
		msg = msg % world.forest.SEEDS_PER_HARVEST
	$HUD.show_message(msg)

func _water() -> void:
	# 足元 2m 以内の木に水をあげる
	var f: Reference = world.forest
	var pos: Vector2 = $Player.global_position
	var result: String = f.water_nearest(pos, 80.0)
	var msg: String = WATER_MESSAGES[result]
	if result == "watered":
		var i: int = f.nearest_index(pos, 80.0, "")
		msg = msg % [f.SPECIES[f.trees[i].species].name, f.WATER_BONUS_YEARS]
	$HUD.show_message(msg)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.scancode:
		KEY_1:
			selected_species = "birch"
		KEY_2:
			selected_species = "apple"
		KEY_3:
			selected_species = "cedar"
		KEY_E:
			_harvest()
		KEY_Q:
			_water()
		KEY_Z:
			# 足元 2m 以内の木を抜く(種は戻らない。達成済みのクエストは戻らない)
			world.forest.remove_nearest($Player.global_position, 80.0)
		KEY_F:
			_toggle_plot()
		KEY_P:
			_toggle_pond()
		KEY_T:
			world.forest.advance_years(1.0)   # 1年先送り(プレビュー。保存しない)
		KEY_G:
			world.forest.advance_years(10.0)  # 10年先送り
		KEY_R:
			world.forest.reset_preview()      # 今日に戻す

func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		world.save_game()
