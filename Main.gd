extends Node

# ── つなぎ役: 入力 → ロジック(logic/) → 文言(HUD) ─────────────────
# ゲームの状態とルールは logic/GameWorld.gd 以下、見た目は view/3d/(Main.tscn)か view/2d/(Main2D.tscn)。
# Main はキー入力をロジックに渡し、結果コードを文言にして HUD に出す。
# Main・HUD は 2D と 3D で共通。位置は Player.ground_pos() で m の Vector2(x, y)を受け取る
const GameWorld = preload("res://logic/GameWorld.gd")
const REACH := 2.0    # 足元 2m 以内
const PICKUP_RADIUS := 1.2  # 落ちている種は、これだけ近づくと拾う

const SEASON_NAMES := {"spring": "春", "summer": "夏", "autumn": "秋", "winter": "冬"}
const FORM_NAMES := {"seed": "種", "sapling": "苗木"}

var world := GameWorld.new()
var selected_species := "birch"
var selected_form := "seed"   # V で種 ⇄ 苗木
var selected_crop := "radish" # 4〜8 で選ぶ。区画の上で SPACE を押すとまく

# 野菜を選ぶキー(HUD の並びもこの順)
const CROP_KEYS := {KEY_4: "radish", KEY_5: "carrot", KEY_6: "cucumber", KEY_7: "potato", KEY_8: "garlic"}

var _season_timer := 0.0

func _ready() -> void:
	world.refresh_season()
	$Ground.setup(world.forest)
	$Land.setup(world.land)
	$Garden.setup(world.garden)
	$Pond.setup(world.pond)
	$Cabin.setup(world.cabin)
	$Quests.setup(world.quests)
	$Trees.setup(world.forest)
	$Pickups.setup(world.forest)
	$Market.setup(world.market)
	$HUD.setup($Player, world.forest, self)
	$HUD.shop_action.connect(_on_shop_action)
	$Player.plant_tree.connect(_on_plant_tree)
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
		_check_quests()  # 種から芽が出ると生垣などの数が増える
	_collect_pickups()

func _check_new_day() -> void:
	var f := world.forest
	var id: String = world.check_new_day()
	if id == "":
		return
	var lines := ["今日の発見: " + DAILY_MESSAGES[id]]
	if not f.pickups.is_empty():
		lines.append("育った木の根元に種が落ちている(%dか所)" % f.pickups.size())
	for sp in f.last_failed:
		lines.append("%sの種 %d粒は芽が出なかった" % [f.SPECIES[sp].name, f.last_failed[sp]])
	var pond := world.pond
	if pond.last_gain > 0:
		lines.append("雨で池に水がたまった(%d%%)" % pond.water)
	for c in pond.last_arrivals:
		lines.append("池に%sが来た" % pond.CREATURES[c].name)
	$HUD.show_message("\n".join(PackedStringArray(lines)), 10.0)

# 足元に落ちている種を拾う(歩いて近づくだけ)
func _collect_pickups() -> void:
	if $HUD.is_shop_open():
		return
	var got: Array = world.forest.collect_near(player_pos(), PICKUP_RADIUS)
	for g in got:
		$HUD.show_message("%sの種を拾った(+%d)" % [world.forest.SPECIES[g.species].name, g.amount])

# 収穫の結果コード(Forest.harvest_nearest)ごとの文言
const HARVEST_MESSAGES := {
	"harvested": "リンゴを%d個収穫した(市場で1個%d₽で売れる)",
	"none": "近くにリンゴの木がない",
	"preview": "未来のプレビュー中は収穫できない",
	"not_season": "リンゴが実るのは秋",
	"young": "まだ実らない(樹齢6年から)",
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
	"birch_seed": "風で白樺の種が飛んできた(白樺の種 +1)",
	"cedar_seed": "リスがシベリア杉の実を置いていった(シベリア杉の種 +1)",
	"rain": "雨が降った。今日は全部の木と野菜に水やり済み",
	"birds": "渡り鳥が来て、しばらく休んでいった",
}

# 段階クエスト(Quests.QUESTS の id)ごとの名前と進み具合の単位
const QUEST_TEXTS := {
	"hedge": {"name": "境界を生垣で囲む", "unit": "区画", "hint": "境界から3m以内に、10mごとに1本"},
	"garden": {"name": "菜園を作る", "unit": "区画", "hint": "F で3m四方の区画を置く"},
	"pond": {"name": "池を掘る", "unit": "", "hint": "P で場所を決めて、1日1回 5日かけて掘る"},
	"family_cedar": {"name": "中心に家族の杉を植える", "unit": "", "hint": "中心から5m以内にシベリア杉"},
}

# 菜園・池の結果コード(GameWorld.toggle_plot / pond_action)ごとの文言
const PLOT_MESSAGES := {
	"placed": "菜園の区画を作った(%d区画)",
	"removed": "菜園の区画を草地に戻した",
	"outside": "土地の外には作れない",
	"has_crop": "野菜が育っている区画は戻せない(Z で抜くか、E で収穫してから)",
	"cabin": "小屋にかかる場所には作れない",
}
const POND_MESSAGES := {
	"placed": "ここに池を掘ることにした(P で 1日1回 掘る。掘りはじめる前なら Z で取り消せる)",
	"outside": "土地の外には掘れない",
	"cabin": "小屋にかかる場所には掘れない",
	"dug": "池を掘った(続きは明日)",
	"finished": "池を掘り終えた。あとは雨で水がたまる",
	"far": "池はひとつまで(今の池の近くで P を押すと掘る)",
	"already": "池はもう掘り終えた(水は雨でたまる)",
	"done_today": "今日はもう掘った(1日1回)",
}

# 小屋の場所決め(Cabin.place)の結果ごとの文言
const CABIN_PLACE_MESSAGES := {
	"placed": "ここに小屋を建てることにした(外から H で作業する。始める前なら Z で取り消せる)",
	"edge": "境界の近くには建てられない(生垣のために3m空ける)",
	"center": "中心の近くには建てられない(家族の杉のために5m空ける)",
	"pond": "池にかかる場所には建てられない",
	"plot": "菜園の区画にかかる場所には建てられない",
	"tree": "木がある場所には建てられない(先に Z で伐る)",
}
const CABIN_STAGE_NAMES := {"foundation": "基礎", "walls": "壁", "roof": "屋根"}

# プレイヤーの足元(m)
func player_pos() -> Vector2:
	return $Player.ground_pos()

func _on_plant_tree(pos: Vector2) -> void:
	if $HUD.is_shop_open():
		return
	# 菜園の区画の上では、木ではなく野菜をまく
	if world.land.plot_at(pos) != null:
		_sow(pos)
		return
	if world.cabin.covers(pos):
		$HUD.show_message("小屋の場所には植えられない")
		return
	if not world.forest.add_tree(pos, selected_species, selected_form):
		$HUD.show_message("%sの%sがない(市場で買える)" % [world.forest.SPECIES[selected_species].name, FORM_NAMES[selected_form]])
		return
	if selected_form == "seed":
		$HUD.show_message("種をまいた。芽が出るかは1日たつと分かる")
	_check_quests()

# 選んでいる植えるもの(HUD 用)。例: 「白樺の種」
func selected_name() -> String:
	return world.forest.SPECIES[selected_species].name + "の" + FORM_NAMES[selected_form]

# ── 小屋 ──────────────────────────────────────────────────
# H: まだ場所がなければ足元に決める。決まっていれば今日の作業をする
func _cabin_action() -> void:
	var c := world.cabin
	var pos := player_pos()
	if c.site == null:
		$HUD.show_message(CABIN_PLACE_MESSAGES[c.place(pos)], 5.0)
		return
	var s: Dictionary = c.current_stage()
	match c.work(pos):
		"worked":
			$HUD.show_message("%sの作業をした(丸太 -%d本)。続きは明日" % [CABIN_STAGE_NAMES[s.id], s.logs_per_day], 5.0)
		"stage_done":
			$HUD.show_message("%sができた(丸太 -%d本)。明日から%s" % [CABIN_STAGE_NAMES[s.id], s.logs_per_day, CABIN_STAGE_NAMES[c.current_stage().id]], 5.0)
		"finished":
			$HUD.show_message("小屋が建った", 8.0)
		"complete":
			$HUD.show_message("小屋はもう建っている")
		"far":
			$HUD.show_message("小屋の場所まで行って作業する(%.0fm以内)" % c.REACH)
		"inside":
			$HUD.show_message("建てる場所の外に出て作業する")
		"done_today":
			$HUD.show_message("今日の作業はもう済んだ(1日1回)")
		"no_wood":
			$HUD.show_message("丸太が足りない(%d本 必要。市場で買うか、育った木を Z で伐る)" % s.logs_per_day, 5.0)

# HUD に出す、小屋の 1 行
func cabin_line() -> String:
	var c := world.cabin
	if c.site == null:
		return "小屋: H で足元に場所を決める(丸太%d本・%d日)" % [c.total_logs(), c.total_days()]
	if c.is_complete():
		return "小屋: 完成した"
	var s: Dictionary = c.current_stage()
	var today := "今日の作業は済んだ" if c.worked_today() else "H で作業・丸太%d本" % s.logs_per_day
	return "小屋: %s %d/%d日(%s)" % [CABIN_STAGE_NAMES[s.id], c.days_done, s.days, today]

# ── 池 ────────────────────────────────────────────────────
func _pond_action() -> void:
	var result: String = world.pond_action(player_pos())
	$HUD.show_message(POND_MESSAGES[result], 5.0)
	if result == "placed" or result == "finished":
		world.save_game()
		_check_quests()

# HUD に出す、池の 1 行(小屋と同じ行に並べる)
func pond_line() -> String:
	var p := world.pond
	if not p.is_placed():
		return "池: P で足元に場所を決める(%d日)" % p.DIG_DAYS
	if not p.is_dug():
		return "池: 掘っている %d/%d日(%s)" % [p.days_dug, p.DIG_DAYS, "今日は済んだ" if p.dug_today() else "P で掘る"]
	var names := PackedStringArray()
	for id in p.present():
		names.append(p.CREATURES[id].name)
	var state := "氷が張っている" if p.is_frozen() else "水 %d%%" % p.water
	return "池: %s%s" % [state, "(%s)" % "・".join(names) if not names.is_empty() else ""]

# ── 畑の野菜 ────────────────────────────────────────────────
# まける季節の文言。例: 「春・秋」
func crop_seasons(kind: String) -> String:
	var names := PackedStringArray()
	for s in world.garden.CROPS[kind].seasons:
		names.append(SEASON_NAMES[s])
	return "・".join(names)

func _sow(pos: Vector2) -> void:
	var g := world.garden
	var crop: Dictionary = g.CROPS[selected_crop]
	match g.sow(pos, selected_crop):
		"sown":
			$HUD.show_message("%sをまいた(毎日水をやれば%d日で収穫できる)" % [crop.name, crop.grow_days], 5.0)
		"occupied":
			$HUD.show_message("この区画にはもう%sが育っている" % g.CROPS[g.crop_at(pos).kind].name)
		"not_season":
			$HUD.show_message("%sをまけるのは%s(今は%s)" % [crop.name, crop_seasons(selected_crop), SEASON_NAMES[world.forest.season]])
		"no_seed":
			$HUD.show_message("%sがない(市場で買える)" % crop.seed_name)

# HUD に出す、選んでいる野菜の 1 行
func selected_crop_line() -> String:
	var crop: Dictionary = world.garden.CROPS[selected_crop]
	return "畑にまく: %s(%sにまける・%d日で育つ)" % [crop.name, crop_seasons(selected_crop), crop.grow_days]

# HUD に出す、足元の区画の様子。区画の上でなければ ""
func plot_line() -> String:
	var g := world.garden
	var pos := player_pos()
	if world.land.plot_at(pos) == null:
		return ""
	var c: Dictionary = g.crop_at(pos)
	if c.is_empty():
		return "足元の区画: 空き(SPACE でまく)"
	var crop_name: String = g.CROPS[c.kind].name
	if g.is_ripe(c):
		return "足元の区画: %s 収穫できる(E)" % crop_name
	var water := "水やり済み" if g.watered_today(c) else "Q で水やり"
	return "足元の区画: %s あと%d日(%s)" % [crop_name, g.days_left(c), water]

# HUD に出す、持っている野菜の種の 1 行
func crop_seeds_line() -> String:
	var parts := PackedStringArray()
	for key in CROP_KEYS:
		var kind: String = CROP_KEYS[key]
		parts.append("%s %d" % [world.garden.CROPS[kind].name, world.garden.seeds[kind]])
	return "  ".join(parts)

# HUD に出す、持っている収穫物の 1 行(持っているものだけ)
func produce_line() -> String:
	var parts := PackedStringArray()
	for item in world.market.SELL_PRICES:
		var n := produce_count(item)
		if n > 0:
			parts.append("%s %d%s" % [produce_name(item), n, produce_unit(item)])
	return "  ".join(parts) if not parts.is_empty() else "なし"

func produce_name(item: String) -> String:
	return "リンゴ" if item == "apple" else world.garden.CROPS[item].name

func produce_unit(item: String) -> String:
	return "個" if item == "apple" else "kg"

func produce_count(item: String) -> int:
	return int(world.forest.produce.apple) if item == "apple" else int(world.garden.produce[item])

# ── 市場 ──────────────────────────────────────────────────
# 市場の品の表示名。例: 「白樺の種(10粒)」「リンゴの苗木(樹齢3年)」「じゃがいもの種いも(春にまく)」「丸太(5本)」
func good_name(g: Dictionary) -> String:
	if g.form == "material":
		return "丸太(%d本)" % g.amount
	if g.form == "crop_seed":
		return "%s(%sにまく)" % [world.garden.CROPS[g.species].seed_name, crop_seasons(g.species)]
	var sp: Dictionary = world.forest.SPECIES[g.species]
	if g.form == "sapling":
		return "%sの苗木(樹齢%d年)" % [sp.name, int(sp.sapling_age)]
	return "%sの種(%d粒・発芽率%d%%)" % [sp.name, g.amount, roundi(sp.germination * 100.0)]

# 市場の画面に並べる行 [{id, text, column}]。column 0 = 買う列、1 = 売る列
func shop_rows() -> Array:
	var m := world.market
	var rows := []
	for g in m.GOODS:
		rows.append({"id": g.id, "text": "買う: %s  %d₽" % [good_name(g), g.price], "column": 0})
	for item in m.SELL_PRICES:
		# 野菜は持っているものだけ並べる(行が多くなりすぎないように)
		var n := produce_count(item)
		if item == "apple" or n > 0:
			rows.append({"id": "sell_" + item, "text": "売る: %s %d%s × %d₽" % [produce_name(item), n, produce_unit(item), m.SELL_PRICES[item]], "column": 1})
	rows.append({"id": "close", "text": "閉じる(B / Esc)", "column": 1})
	return rows

func _toggle_shop() -> void:
	if $HUD.is_shop_open():
		_close_shop()
		return
	var m := world.market
	if not m.is_near(player_pos()):
		var d := player_pos().distance_to(m.POS) - m.REACH
		$HUD.show_message("市場は南の境界の外にある(あと%dm)" % ceili(d))
		return
	$Player.set_physics_process(false)  # 買い物中は歩かない
	$HUD.open_shop()

func _close_shop() -> void:
	$HUD.close_shop()
	$Player.set_physics_process(true)

func _on_shop_action(id: String) -> void:
	var m := world.market
	if id == "close":
		_close_shop()
		return
	if id.begins_with("sell_"):
		var item := id.trim_prefix("sell_")
		var income: int = m.sell_all(item)
		$HUD.show_message("%sを売った(+%d₽)" % [produce_name(item), income] if income > 0 else "売る%sがない" % produce_name(item))
	else:
		var g: Dictionary = m.good(id)
		if m.buy(id) == "bought":
			$HUD.show_message("%sを買った(-%d₽)" % [good_name(g), g.price])
		else:
			$HUD.show_message("お金が足りない(%d₽ 必要)" % g.price)
	world.save_game()
	$HUD.refresh_shop()

func _toggle_plot() -> void:
	var result: String = world.toggle_plot(player_pos())
	var msg: String = PLOT_MESSAGES[result]
	if result == "placed":
		msg = msg % world.land.plots.size()
	$HUD.show_message(msg)
	_after_land_change(result)

func _after_land_change(result: String) -> void:
	if result == "placed" or result == "removed":
		world.save_game()
		_check_quests()

# クエストを判定し、達成があれば知らせて保存する
func _check_quests() -> void:
	var done: Array = world.quests.advance()
	if done.is_empty():
		return
	world.save_game()
	if done.has("complete"):
		$HUD.show_message("愛の空間が完成した", 12.0)
		return
	var names := []
	for id in done:
		names.append(QUEST_TEXTS[id].name)
	var next: String = world.quests.current_id()
	$HUD.show_message("達成: %s → 次は「%s」" % ["・".join(PackedStringArray(names)), QUEST_TEXTS[next].name], 8.0)

# HUD に出すクエストの 1 行
func quest_line() -> String:
	var q := world.quests
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
	var g := world.garden
	var pos := player_pos()
	# 足元の区画の野菜を先に。収穫できなければ、近くのリンゴを見る
	var c: Dictionary = g.crop_at(pos)
	var crop: String = g.harvest_at(pos)
	if crop == "harvested":
		var kind: String = c.kind
		$HUD.show_message("%sを%dkg収穫した(市場で1kg %d₽で売れる)" % [g.CROPS[kind].name, g.last_harvest_kg, world.market.SELL_PRICES[kind]])
		return
	if crop == "preview":
		$HUD.show_message(HARVEST_MESSAGES.preview)
		return
	# 足元 2m 以内のリンゴを収穫する
	var result: String = world.forest.harvest_nearest(pos, REACH)
	if crop == "growing" and result != "harvested":
		$HUD.show_message("%sはまだ育っている(あと%d日)" % [g.CROPS[c.kind].name, g.days_left(c)])
		return
	var msg: String = HARVEST_MESSAGES[result]
	if result == "harvested":
		msg = msg % [world.forest.last_harvest_count, world.market.SELL_PRICES.apple]
	$HUD.show_message(msg)

func _water() -> void:
	var f := world.forest
	var g := world.garden
	var pos := player_pos()
	# 足元の区画の野菜を先に。今日もう水をあげていれば、近くの木を見る
	var crop: String = g.water_at(pos)
	if crop == "watered":
		$HUD.show_message("%sに水をあげた(水をやった日は1日ぶん、やらない日は半日ぶん育つ)" % g.CROPS[g.crop_at(pos).kind].name)
		return
	# 足元 2m 以内の木に水をあげる
	var result: String = f.water_nearest(pos, REACH)
	if crop != "none" and result != "watered":
		$HUD.show_message("もう収穫できる(E)" if crop == "ripe" else "この区画には今日もう水をあげた")
		return
	var msg: String = WATER_MESSAGES[result]
	if result == "watered":
		var i: int = f.nearest_index(pos, REACH, "")
		msg = msg % [f.SPECIES[f.trees[i].species].name, f.WATER_BONUS_YEARS]
	$HUD.show_message(msg)

# 足元の野菜を抜く。なければ 2m 以内の木を伐る(育った木は丸太になる。種は戻らない。
# 達成済みのクエストは戻らない)。木もなければ、作業を始める前の小屋・池の場所を取り消す
func _remove() -> void:
	var g := world.garden
	var pos := player_pos()
	var c: Dictionary = g.crop_at(pos)
	if g.remove_at(pos):
		$HUD.show_message("%sを抜いた(種は戻らない)" % g.CROPS[c.kind].name)
		return
	var logs: int = world.cabin.fell(pos, REACH)
	if logs > 0:
		$HUD.show_message("木を伐った(丸太 +%d本)" % logs)
	elif logs == 0:
		$HUD.show_message("木を抜いた(細くて丸太にはならない)")
	elif world.cabin.cancel(pos):
		$HUD.show_message("小屋の場所を取り消した")
	elif world.pond.cancel(pos):
		$HUD.show_message("池の場所を取り消した")

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if $HUD.is_shop_open():
		# 買い物中は B / Esc で閉じるだけ(選ぶのは画面のボタン)
		if event.keycode == KEY_B or event.keycode == KEY_ESCAPE:
			_close_shop()
		return
	if CROP_KEYS.has(event.keycode):
		selected_crop = CROP_KEYS[event.keycode]
		return
	match event.keycode:
		KEY_1:
			selected_species = "birch"
		KEY_2:
			selected_species = "apple"
		KEY_3:
			selected_species = "cedar"
		KEY_V:
			selected_form = "sapling" if selected_form == "seed" else "seed"
		KEY_B:
			_toggle_shop()
		KEY_E:
			_harvest()
		KEY_Q:
			_water()
		KEY_Z:
			_remove()
		KEY_H:
			_cabin_action()
		KEY_F:
			_toggle_plot()
		KEY_P:
			_pond_action()
		KEY_T:
			world.forest.advance_years(1.0)   # 1年先送り(プレビュー。保存しない)
		KEY_G:
			world.forest.advance_years(10.0)  # 10年先送り
		KEY_R:
			world.forest.reset_preview()      # 今日に戻す

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		world.save_game()
