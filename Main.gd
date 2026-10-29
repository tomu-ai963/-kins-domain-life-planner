extends Node2D

# スケール: 1m = 40px  →  1ヘクタール(100m×100m) = 4000px×4000px
# ワールド原点(0,0)をドメイン中心とし、±2000px(±50m)が境界

const SEASON_NAMES := {"spring": "春", "summer": "夏", "autumn": "秋", "winter": "冬"}

# 季節ごとの地面パレット
const GROUND := {
	"spring": {"dirt": Color(0.40, 0.30, 0.20), "grass": Color(0.62, 0.82, 0.42), "grid": Color(0.50, 0.70, 0.32)},
	"summer": {"dirt": Color(0.38, 0.28, 0.18), "grass": Color(0.56, 0.77, 0.34), "grid": Color(0.44, 0.65, 0.27)},
	"autumn": {"dirt": Color(0.36, 0.26, 0.16), "grass": Color(0.74, 0.66, 0.32), "grid": Color(0.62, 0.55, 0.26)},
	"winter": {"dirt": Color(0.35, 0.32, 0.30), "grass": Color(0.88, 0.90, 0.92), "grid": Color(0.78, 0.81, 0.85)},
}

var selected_species := "birch"
var season := "summer"

var _season_timer := 0.0

func _ready() -> void:
	_update_season()
	$HUD.setup($Player, $Trees, self)
	$Player.connect("plant_tree", self, "_on_plant_tree")
	$Trees.land = $Land
	$Trees.quests = $Quests
	$Quests.trees = $Trees
	$Quests.land = $Land
	$Trees.load_game()
	_check_new_day()
	_check_quests()  # 旧セーブで条件を満たしていれば、開いた時点で達成する

func _process(delta: float) -> void:
	# 季節と日付は現実の日付から。1 分に 1 回チェックすれば十分(開いたまま日付をまたいでも拾う)
	_season_timer += delta
	if _season_timer >= 60.0:
		_season_timer = 0.0
		_update_season()
		_check_new_day()

func _check_new_day() -> void:
	var id: String = $Trees.check_new_day()
	if id != "":
		$HUD.show_message("今日の発見: " + DAILY_MESSAGES[id], 8.0)

func _update_season() -> void:
	var m: int = OS.get_datetime().month
	var s := "winter"
	if m >= 3 and m <= 5:
		s = "spring"
	elif m >= 6 and m <= 8:
		s = "summer"
	elif m >= 9 and m <= 11:
		s = "autumn"
	season = s
	$Trees.season = s
	update()
	$Trees.update()

# 収穫の結果コード(Trees.harvest_nearest)ごとの文言
const HARVEST_MESSAGES := {
	"harvested": "リンゴを収穫した → リンゴの種 +%d",
	"none": "近くにリンゴの木がない",
	"preview": "未来のプレビュー中は収穫できない",
	"not_season": "リンゴが実るのは秋",
	"young": "まだ実らない(樹齢5年から)",
	"done": "この木は今日もう収穫した",
}

# 水やりの結果コード(Trees.water_nearest)ごとの文言
const WATER_MESSAGES := {
	"watered": "%sに水をあげた(樹齢 +%.1f年)",
	"none": "近くに木がない",
	"done": "この木には今日もう水をあげた",
}

# 日替わりの発見(Trees.DAILY_EVENTS の id)ごとの文言
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
	if not $Trees.add_tree(pos, selected_species):
		$HUD.show_message("%sの種がない" % $Trees.SPECIES[selected_species].name)
		return
	_check_quests()

func _toggle_plot() -> void:
	var result: String = $Land.toggle_plot($Player.global_position)
	var msg: String = PLOT_MESSAGES[result]
	if result == "placed":
		msg = msg % $Land.plots.size()
	$HUD.show_message(msg)
	_after_land_change(result)

func _toggle_pond() -> void:
	var result: String = $Land.toggle_pond($Player.global_position)
	$HUD.show_message(POND_MESSAGES[result])
	_after_land_change(result)

func _after_land_change(result: String) -> void:
	if result == "placed" or result == "removed":
		$Trees.save_game()
		_check_quests()

# クエストを判定し、達成があれば知らせて保存する
func _check_quests() -> void:
	$Quests.update()  # 生垣の区画の印などを描き直す
	var done: Array = $Quests.advance()
	if done.empty():
		return
	$Trees.save_game()
	if done.has("complete"):
		$HUD.show_message("愛の空間が完成した", 12.0)
		return
	var names := []
	for id in done:
		names.append(QUEST_TEXTS[id].name)
	var next: String = $Quests.current_id()
	$HUD.show_message("達成: %s → 次は「%s」" % [PoolStringArray(names).join("・"), QUEST_TEXTS[next].name], 8.0)

# HUD に出すクエストの 1 行
func quest_line() -> String:
	if $Quests.is_complete():
		return "クエスト: 愛の空間が完成した"
	var id: String = $Quests.current_id()
	var t: Dictionary = QUEST_TEXTS[id]
	var p: Array = $Quests.progress(id)
	var count := ""
	if t.unit != "":
		count = " %d/%d%s" % [p[0], p[1], t.unit]
	return "クエスト %d/%d: %s%s(%s)" % [$Quests.stage + 1, $Quests.QUESTS.size(), t.name, count, t.hint]

func _harvest() -> void:
	# 足元 2m 以内のリンゴを収穫する
	var result: String = $Trees.harvest_nearest($Player.global_position, 80.0)
	var msg: String = HARVEST_MESSAGES[result]
	if result == "harvested":
		msg = msg % $Trees.SEEDS_PER_HARVEST
	$HUD.show_message(msg)

func _water() -> void:
	# 足元 2m 以内の木に水をあげる
	var pos: Vector2 = $Player.global_position
	var result: String = $Trees.water_nearest(pos, 80.0)
	var msg: String = WATER_MESSAGES[result]
	if result == "watered":
		var i: int = $Trees.nearest_index(pos, 80.0, "")
		msg = msg % [$Trees.SPECIES[$Trees.trees[i].species].name, $Trees.WATER_BONUS_YEARS]
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
			$Trees.remove_nearest($Player.global_position, 80.0)
			$Quests.update()
		KEY_F:
			_toggle_plot()
		KEY_P:
			_toggle_pond()
		KEY_T:
			$Trees.advance_years(1.0)   # 1年先送り(プレビュー。保存しない)
		KEY_G:
			$Trees.advance_years(10.0)  # 10年先送り
		KEY_R:
			$Trees.reset_preview()      # 今日に戻す

func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		$Trees.save_game()

func _draw() -> void:
	var half := 2000.0
	var grid := 400.0   # 10m グリッド
	var pal: Dictionary = GROUND[season]

	# ドメイン外（土の色）
	draw_rect(Rect2(-6000, -6000, 12000, 12000), pal.dirt)

	# 1ヘクタール草原（冬は雪原）
	draw_rect(Rect2(-half, -half, half * 2, half * 2), pal.grass)

	# 10m グリッド線
	for i in range(-5, 6):
		var p := float(i) * grid
		draw_line(Vector2(p, -half), Vector2(p,  half), pal.grid, 1)
		draw_line(Vector2(-half, p), Vector2( half, p), pal.grid, 1)

	# ── メルカバ（二つの正三角形 / 六芒星）────────────────────────
	# 土地のエネルギー軸を示す黄金色のガイドライン
	# 半径 600px = 15m。頂点はドメイン原点を中心に等分配置
	_draw_merkaba(Vector2.ZERO, 600.0, Color(1.0, 0.82, 0.18, 0.38), 2.0)
	# ────────────────────────────────────────────────────────────────

	# ドメイン境界線
	draw_line(Vector2(-half, -half), Vector2( half, -half), Color(0.18, 0.44, 0.14), 4)
	draw_line(Vector2( half, -half), Vector2( half,  half), Color(0.18, 0.44, 0.14), 4)
	draw_line(Vector2( half,  half), Vector2(-half,  half), Color(0.18, 0.44, 0.14), 4)
	draw_line(Vector2(-half,  half), Vector2(-half, -half), Color(0.18, 0.44, 0.14), 4)

	# 原点マーカー
	draw_circle(Vector2.ZERO, 7, Color(0.92, 0.18, 0.1))

# 正三角形 2 枚を重ねて六芒星（メルカバ）を描く
# △ (上向き): 頂点が上  /  ▽ (下向き): 頂点が下
func _draw_merkaba(center: Vector2, radius: float, color: Color, width: float) -> void:
	var h := sqrt(3.0) * 0.5  # sin(60°) ≈ 0.866

	# 上向き三角形 △
	var u0 := center + Vector2(0,          -radius)
	var u1 := center + Vector2(-radius * h,  radius * 0.5)
	var u2 := center + Vector2( radius * h,  radius * 0.5)
	draw_line(u0, u1, color, width)
	draw_line(u1, u2, color, width)
	draw_line(u2, u0, color, width)

	# 下向き三角形 ▽
	var d0 := center + Vector2(0,           radius)
	var d1 := center + Vector2(-radius * h, -radius * 0.5)
	var d2 := center + Vector2( radius * h, -radius * 0.5)
	draw_line(d0, d1, color, width)
	draw_line(d1, d2, color, width)
	draw_line(d2, d0, color, width)
