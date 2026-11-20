extends Node

# ── つなぎ役: 入力 → ロジック(logic/) → 文言(HUD) ─────────────────
# ゲームの状態とルールは logic/GameWorld.gd 以下、見た目は view/3d/(Main.tscn)か view/2d/(Main2D.tscn)。
# Main はキー入力をロジックに渡し、結果コードを文言にして HUD に出す。
# Main・HUD は 2D と 3D で共通。位置は Player.ground_pos() で m の Vector2(x, y)を受け取る
const GameWorld = preload("res://logic/GameWorld.gd")
const WildWoodsView = preload("res://view/3d/WildWoodsView3D.gd")
const RiverView = preload("res://view/3d/RiverView3D.gd")
const WellView = preload("res://view/3d/WellView3D.gd")
const MillView = preload("res://view/3d/MillView3D.gd")
const FamilyView = preload("res://view/3d/FamilyView3D.gd")
const Msg = preload("res://view/main/Messages.gd")
const VisitorTalk = preload("res://view/main/VisitorTalk.gd")
const FamilyTalk = preload("res://view/main/FamilyTalk.gd")
const KitchenPanel = preload("res://view/main/KitchenPanel.gd")
const MarketPanel = preload("res://view/main/MarketPanel.gd")
const REACH := 2.0    # 足元 2m 以内
const PICKUP_RADIUS := 1.2  # 落ちている種は、これだけ近づくと拾う
const FELL_CONFIRM_SECONDS := 4.0  # 根付いた木は、この時間内にもう一度 Z を押すと伐れる
const WILDLIFE_CHECK_SECONDS := 5.0  # はじめて来た生き物がいないか見る間隔
const GUIDE_CHECK_SECONDS := 0.5     # ヒントを見直す間隔
const HIVE_FRONT := 1.2              # 巣箱を置く場所(体の前、m)。足元に置くと当たり判定に埋まる
const SHOVEL_GAP := 0.35             # 雪かきの動きを次に始められるまでの間(秒)
const SOUND_LEVELS := [0.0, 0.3, 0.6, 1.0]        # M で切り替える音量
const SOUND_LEVEL_NAMES := ["消す", "小", "中", "大"]
const TREE_FALL_SOUND_DELAY := 0.45  # 斧を振ってから、木が倒れる音を出すまで(秒)。木が倒れきる時に「どさっ」が合う

const SEASON_NAMES := {"spring": "春", "summer": "夏", "autumn": "秋", "winter": "冬"}
const FORM_NAMES := {"seed": "種", "sapling": "苗木"}

var world := GameWorld.new()
var selected_species := "birch"
var selected_form := "seed"   # V で種 ⇄ 苗木
var selected_crop := "radish" # 4〜8 で選ぶ。区画の上で SPACE を押すとまく

const TOOL_NAMES := {"big_can": "10Lのジョウロ(1杯で10か所)", "pump": "エンジンポンプ(井戸・池・川からまとめて水やり)",
	"chainsaw": "チェーンソー(何本でも伐れる)", "splitter": "薪割り機(薪を一度に割る)",
	"quern": "石臼(穀物を挽いて粉にする)", "mill": "製粉機(石臼のそばで穀物を一度に挽く)"}
const MACHINE_NAMES := {"pump": "エンジンポンプ", "chainsaw": "チェーンソー", "splitter": "薪割り機", "mill": "製粉機"}
const FURNITURE_NAMES := {"shelf": "保存食の棚", "rocking_chair": "揺り椅子", "rug": "じゅうたん", "lamp": "ランプ", "clock": "掛け時計"}

# 野菜の組を選ぶキー(押すたびに、その組のうちこの土地で育つ次の野菜。HUD の並びもこの順)
const CROP_KEYS := {KEY_4: "root", KEY_5: "imo", KEY_6: "fruit", KEY_7: "leaf", KEY_8: "bean", KEY_9: "aroma"}
const CROP_GROUP_NAMES := {"root": "根菜", "imo": "いも", "fruit": "実もの", "leaf": "葉もの", "bean": "豆・穀物", "aroma": "香味"}

var _season_timer := 0.0
var _fell_pending := {}      # Z を 1 回押して確認中の木(Forest.trees の要素)
var _fell_deadline := 0.0    # いつまでにもう一度押せば伐れるか(秒)
var _panel := "market"       # 右の画面に出しているもの: market(市場) / kitchen(ストーブ) / family(家族と話す)
var _wildlife_timer := 0.0
var _guide_timer := 0.0
var _shovel_wait := 0.0

# 機能ごとの画面の部品(view/main/。レビュー C4 で Main から分けた)
var visitor_talk := VisitorTalk.new(self)
var family_talk := FamilyTalk.new(self)
var kitchen_panel := KitchenPanel.new(self)
var market_panel := MarketPanel.new(self)

func _ready() -> void:
	# 本物のセーブのときだけ控えを取る(テストや確認用のセーブでは取らない)
	if world.save_path == world.SAVE_PATH:
		world.backup_dir = world.BACKUP_DIR
	world.refresh_season()
	$Ground.setup(world.forest)
	$Land.setup(world.land)
	$Garden.setup(world.garden)
	$Pond.setup(world.pond)
	$Cabin.setup(world.cabin, world.seedlings)
	$Quests.setup(world.quests)
	$Trees.setup(world.forest)
	$Pickups.setup(world.forest)
	$Market.setup(world.market)
	$HUD.setup($Player, world.forest, self)
	$HUD.shop_action.connect(_on_shop_action)
	$HUD.region_chosen.connect(_on_region_chosen)
	$HUD.family_chosen.connect(_on_family_chosen)
	$HUD.profile_chosen.connect(_on_profile_chosen)
	$HUD.family_renamed.connect(family_talk._on_family_renamed)
	$HUD.family_names_closed.connect(func(): $Player.set_physics_process(true))
	$Player.plant_tree.connect(_on_plant_tree)
	world.save_failed.connect(func(message: String): $HUD.show_message(message, 15.0))
	_setup_3d_only()
	world.load_game()
	_check_new_day()
	_check_quests()  # 旧セーブで条件を満たしていれば、開いた時点で達成する
	var weather := get_node_or_null("Weather")
	if weather != null:
		weather.refresh(true)  # セーブを読んだあとの今日の天気で始める
		$Ground.hide_covered()  # セーブにあった区画や小屋の上には草を生やさない
		$Wildlife.sync_animals()  # セーブにあった木や畑に合わせて、最初からいるように
		_apply_sound_level()
	_apply_profile_look()
	# 自分・県・家族の記録がなければ、その順に決める画面を出す。本物のセーブのときだけ(テストや確認用のセーブでは、要るときに開く)
	if world.save_path == world.SAVE_PATH:
		open_next_picker()

# まだ決めていないものの画面を、自分 → 都道府県 → 家族 の順に 1 つ開く。全部決まっていれば何もしない
func open_next_picker() -> void:
	if not world.profile.chosen:
		open_profile_picker()
	elif not world.region.is_chosen():
		open_region_picker()
	elif not world.family.chosen:
		open_family_picker()  # 家族の記録がないセーブ(2026-11-16 より前)も、一度だけ選ぶ

# ── 自分の名前と性別(いちばんはじめに一度だけ決める。2026-11-16) ──
func open_profile_picker() -> void:
	$Player.set_physics_process(false)
	$HUD.open_profile_picker()

func _on_profile_chosen(player_name: String, sex: String) -> void:
	$Player.set_physics_process(true)
	if world.choose_profile(player_name, sex) != "chosen":
		return
	_apply_profile_look()
	$HUD.show_message("ようこそ、%sさん" % world.profile.name, 5.0)
	if world.save_path == world.SAVE_PATH:
		open_next_picker()

# 性別を見た目(髪)に合わせる(3D だけ)
func _apply_profile_look() -> void:
	if $Player.has_method("set_sex"):
		$Player.set_sex(world.profile.sex)

# 持ち物の見出しのあとに出す、自分の名前と性別
func profile_suffix() -> String:
	var p := world.profile
	if not p.chosen:
		return ""
	return "  %s" % p.name if p.sex == "" else "  %s(%s)" % [p.name, p.SEX_NAMES[p.sex]]

# 言葉の中の呼びかけを置き換える。{呼} は訪問者なら「○○さん、」、配偶者なら「○○、」。{親} は子どもの「お母さん、」「お父さん、」。
# 名前・性別を決めていなければ消す
func with_call(text: String, speaker := "visitor") -> String:
	var p := world.profile
	var address := ""
	if p.chosen:
		address = ("%s、" % p.name) if speaker == "spouse" else ("%sさん、" % p.name)
	var parent: String = p.parent_word() + "、" if p.chosen and p.parent_word() != "" else ""
	return text.replace("{呼}", address).replace("{親}", parent)

# ── 土地のある都道府県(ゲームのはじめに一度だけ選ぶ) ──
func open_region_picker() -> void:
	$Player.set_physics_process(false)  # 選んでいるあいだは歩かない
	$HUD.open_region_picker()

func _on_region_chosen(id: String) -> void:
	$Player.set_physics_process(true)
	if world.choose_region(id) != "chosen":
		return
	_fit_selection()
	var weather := get_node_or_null("Weather")
	if weather != null:
		weather.refresh(true)  # 雪の積もらない土地なら、雪を雨に
	var z: Dictionary = world.region.zone()
	$HUD.show_message("%sに土地を持った(気候: %s)。季節と植えられる木は、この土地に合わせて決まる" % [world.region.pref_name(), z.name], 7.0)
	# 続けて、一緒に暮らす家族を選ぶ。本物のセーブのときだけ(テストや確認用のセーブでは、要るときに開く)
	if world.save_path == world.SAVE_PATH:
		open_next_picker()

# ── 一緒に暮らす家族(都道府県のあとに一度だけ選ぶ。2026-11-16) ──
func open_family_picker() -> void:
	$Player.set_physics_process(false)  # 選んでいるあいだは歩かない
	$HUD.open_family_picker()

func _on_family_chosen(choice: Dictionary) -> void:
	$Player.set_physics_process(true)
	if world.choose_family_custom(choice) != "chosen":
		return
	var f := world.family
	if f.members.is_empty():
		$HUD.show_message("ひとりで土地を暮らしていく", 6.0)
		return
	var names := PackedStringArray()
	for m in f.members:
		names.append(m.name)
	var home := "小屋で暮らす" if world.cabin.is_complete() else "小屋ができるまでは、テントで休む"
	$HUD.show_message("%sと一緒に土地で暮らす。%s(近くで C を押すと話せる)" % ["・".join(names), home], 8.0)

# 昼夜の光と小屋の中は 3D だけ(2D のシーンには DayLight がない)
func _setup_3d_only() -> void:
	var day_light := get_node_or_null("DayLight")
	if day_light == null:
		return
	day_light.night_changed.connect($Player.set_night)
	day_light.night_changed.connect($Cabin.set_night)
	day_light.night_changed.connect($Market.set_night)
	day_light.setup(world.clock, $Sun, $WorldEnvironment.environment)
	$Weather.setup(world.forest, $Player, day_light)
	$Ground.set_land(world.land, world.cabin)
	$Player.shadow_light = $Sun
	$Player.update_shadow_distance()
	$Cabin.set_player($Player)
	$Pond.set_player($Player)
	$Trees.set_player($Player)  # 足元で育った幹に閉じ込められないように
	$Pond.tools = world.tools
	$Cabin.set_tools(world.tools)
	var well_view := WellView.new()
	well_view.name = "Well"
	add_child(well_view)
	well_view.setup(world.well, world.tools, world.pond)
	well_view.set_player($Player)
	var mill_view := MillView.new()
	mill_view.name = "Mill"
	add_child(mill_view)
	mill_view.setup(world.mill, world.tools)
	$Cabin.set_kitchen(world.kitchen)
	$Wildlife.setup(world.wildlife, $Player)
	$Visitor.setup(world.visitors, $Player)
	var family_view := FamilyView.new()
	family_view.name = "Family"
	add_child(family_view)
	family_view.setup(world.family, $Player, {"forest": world.forest, "land": world.land, "cabin": world.cabin,
		"bees": world.bees, "feeders": world.feeders, "well": world.well, "mill": world.mill, "clock": world.clock, "wilds": world.wilds})
	family_view.wildlife_view = $Wildlife
	family_view.spotted.connect(family_talk._on_family_spotted)
	day_light.night_changed.connect(family_view.set_night)
	family_view.set_night(maxf(0.0, day_light.night))
	family_view.extra_avoid = func(): return [$Visitor.ground_pos()] if $Visitor.state() != "away" else []
	$Visitor.extra_avoid = family_view.positions
	$Visitor.extra_obstacles = family_view.obstacle_rects
	$Hives.setup(world.bees)
	$Feeders.setup(world.feeders)
	$NestBoxes.setup(world.nest_boxes, world.forest)
	$SnowPath.setup(world.snow)
	$Footprints.setup(world.snow, $Player, $Wildlife)
	$Footprints.skip_at = world.pond.is_on_ice  # 氷の上には足跡が残らない
	world.guide.has_people = true
	$Audio.setup(world, $Player)
	$Player.work_sound.connect($Audio.play)
	$TouchControls.setup(self, $Player, $HUD)
	var woods := WildWoodsView.new()
	woods.name = "WildWoods"
	add_child(woods)
	woods.setup(world.wilds)
	var river_view := RiverView.new()
	river_view.name = "River"
	add_child(river_view)
	river_view.setup(world.river)

func _process(delta: float) -> void:
	_guide_timer += delta
	if _guide_timer >= GUIDE_CHECK_SECONDS:
		world.guide.update(player_pos(), _guide_timer)
		_guide_timer = 0.0
	_wildlife_timer += delta
	if _wildlife_timer >= WILDLIFE_CHECK_SECONDS:
		_wildlife_timer = 0.0
		check_wildlife()
	# 季節と日付は現実の日付から。1 分に 1 回チェックすれば十分(開いたまま日付をまたいでも拾う)
	_season_timer += delta
	if _season_timer >= 60.0:
		_season_timer = 0.0
		world.refresh_season()
		_check_new_day()
		_check_quests()  # 種から芽が出ると生垣などの数が増える
	_collect_pickups()
	if $Player.has_method("facing"):
		update_shovel(delta, Input.is_key_pressed(KEY_U))

# 雪かき: U を押しているあいだ、足元の雪をどかしながらゆっくり歩く。どかした道の上は速く歩ける
func update_shovel(delta: float, holding: bool) -> void:
	var s := world.snow
	var pos := player_pos()
	var shoveling: bool = holding and world.can_shovel_at(pos) and not $HUD.is_shop_open() and not $HUD.is_diary_open()
	_shovel_wait -= delta
	if shoveling and _shovel_wait <= 0.0 and s.clear_at(pos) == "cleared":
		_shovel_wait = SHOVEL_GAP
		_act("shovel")
		family_talk._family_snow()
	$Player.speed_scale = world.walk_speed(pos, shoveling)
	if "slippery" in $Player:
		$Player.slippery = world.pond.is_on_ice(pos)

func _check_new_day() -> void:
	var f := world.forest
	var id: String = world.check_new_day()
	# 訪問者と話す画面を開いたまま日付をまたいだ: 前の日の人の画面なので閉じる(レビュー S7)。
	# 市場の画面として閉じるのは、今日の人を「話し終えた」ことにして帰さないため
	if _panel == "visitor" and (id != "" or not world.visitors.is_here()):
		_panel = "market"
		_close_shop()
	# セーブが読めず控えから戻したときは、その日のはじめの知らせの先頭に出す(1 回だけ)
	var notice := world.load_notice
	world.load_notice = ""
	if id == "":
		if notice != "":
			$HUD.show_message(notice, 15.0)
		return
	var lines := ["今日の発見: " + daily_message(id)]
	if notice != "":
		lines.push_front(notice)
	var own_drops: int = f.pickups.filter(func(p): return absf(p.pos.x) <= world.land.HALF and absf(p.pos.y) <= world.land.HALF).size()
	if own_drops > 0:
		lines.append("育った木の根元に種が落ちている(%dか所)" % own_drops)
	if not world.wilds.last_drops.is_empty():
		lines.append("外の林で%sの種が落ちている(今日だけ。境界の外の木の根元)" % _names_of(world.wilds.last_drops))
	for sp in f.last_failed:
		lines.append("%sの種 %d粒は芽が出なかった" % [f.SPECIES[sp].name, f.last_failed[sp]])
	var g := world.garden
	for kind in g.last_frost:
		lines.append("霜で%sが枯れた(%d区画)" % [g.CROPS[kind].name, g.last_frost[kind]])
	var p := world.pests
	for d in p.last_damage:
		lines.append(damage_text(d))
	if not p.last_damage.is_empty():
		lines.append("(餌台に餌や野菜を置いて生き物と仲良くなると、畑を荒らさなくなる。仲良し度 %d/%d・%d で荒らさない)" % [p.friendship, p.FRIEND_MAX, p.FRIEND_SAFE])
	var weedy: int = g.weedy_count()
	if weedy > 0:
		lines.append("雑草が生えている区画がある(%d区画。E で抜く。わらを敷いた区画には生えない)" % weedy)
	if g.frost_is_near(f.today()):
		lines.append("もうすぐ霜が降りる(%s)。霜に弱い野菜は枯れるので、早めに収穫を" % g.frost_date_text())
	lines.append_array(family_talk.family_help_lines())
	if has_node("Visitor") and world.visitors.is_here():
		lines.append("%sが訪ねてきた(C で話す)" % world.visitors.CAST[world.visitors.who()].name)
	var pond := world.pond
	if pond.last_gain > 0:
		lines.append("%sで池に水がたまった(%d%%)" % ["雪" if is_snow_day(f.season) else "雨", pond.water])
	for c in pond.last_arrivals:
		lines.append("池に%sが来た" % pond.CREATURES[c].name)
	if world.bees.last_arrivals > 0:
		lines.append("空の巣箱に蜂が入った(%d箱)" % world.bees.last_arrivals)
	if world.snow.last_fell:
		lines.append("雪かきの道が雪で埋まった")
	if not world.market.last_delivered.is_empty():
		lines.append("冬に注文した春の種が届いた(%s)" % orders_text(world.market.last_delivered))
	$HUD.show_message("\n".join(PackedStringArray(lines)), 15.0 if notice != "" else 10.0)

# ゆうべ荒らされた区画の知らせ(Pests.last_damage の 1 件)
func damage_text(d: Dictionary) -> String:
	var who: String = world.wildlife.SPECIES[d.id].name
	var crop: String = world.garden.CROPS[d.kind].name
	if d.dug:
		return "ゆうべ%sが来て、%sの区画を掘り返した(区画が空いた)" % [who, crop]
	if d.gone:
		return "ゆうべ%sが来て、%sを食べ尽くした(区画が空いた)" % [who, crop]
	return "ゆうべ%sが来て、%sをかじった(その区画の収量が半分に)" % [who, crop]

# 持ち物に出す、生き物との仲良し度
func friendship_line() -> String:
	var p := world.pests
	var note := "畑を荒らさない" if p.is_safe() else "%d で畑を荒らさなくなる" % p.FRIEND_SAFE
	return "%d/%d(%s。餌台に餌や野菜を置くと上がり、機械の音で下がる)" % [p.friendship, p.FRIEND_MAX, note]

# ── 巣箱とはちみつ ─────────────────────────────────────────
# J: 足元に巣箱を作る / くり抜く / はちみつを採る
func _bee_action() -> void:
	var b := world.bees
	var pos := player_pos()
	var front = pos + $Player.facing() * HIVE_FRONT if $Player.has_method("facing") else null
	var result: String = b.act(pos, front)
	var near: Dictionary = b.hive_near(pos)
	match result:
		"placed":
			_act("build", near.pos)
			$HUD.show_message("丸太を立てて巣箱にすることにした(丸太 -%d本)。J で1日1回くり抜く(%d日)" % [b.LOG_COST, b.HOLLOW_DAYS], 6.0)
		"hollowed":
			_act("build", near.pos)
			$HUD.show_message("丸太をくり抜いた(%d/%d日)。続きは明日" % [near.days_done, b.HOLLOW_DAYS])
		"finished":
			_act("build", near.pos)
			$HUD.show_message("巣箱ができた。春と夏は自然に蜂が入るのを待てる。フョードルさんに分けてもらうこともできる", 8.0)
		"done_today":
			$HUD.show_message("今日はもうくり抜いた(1日1回)")
		"no_wood":
			$HUD.show_message("自分の木を伐った丸太が%d本いる(今 %d本)。市場の丸太は使えない" % [b.LOG_COST, world.cabin.own_log_count()], 5.0)
		"too_many":
			$HUD.show_message("巣箱は%dつまで" % b.MAX_HIVES)
		"blocked":
			$HUD.show_message("ここには置けない(区画・小屋・池・木のそばや、土地の端は空ける)", 5.0)
		"empty":
			$HUD.show_message("この巣箱にはまだ蜂がいない")
		"not_yet":
			$HUD.show_message("まだ採れるほどたまっていない")
		"harvested":
			_act("pick", near.pos, "honey")
			$HUD.show_message("はちみつを%dkg採った(市場で1kg %d₽で売れる)" % [b.last_harvest, world.market.SELL_PRICES.honey], 5.0)

# HUD に出す、巣箱の 1 行。作れもせず巣箱もなければ ""
func hive_line() -> String:
	var b := world.bees
	if b.hives.is_empty():
		if world.cabin.own_log_count() >= b.LOG_COST:
			return "巣箱: J で足元に作れる(自分の丸太 %d本)" % world.cabin.own_log_count()
		return ""
	var near: Dictionary = b.hive_near(player_pos())
	if not near.is_empty():
		if not b.is_hollowed(near):
			return "巣箱: くり抜き %d/%d日(%s)" % [near.days_done, b.HOLLOW_DAYS, "今日は済んだ" if near.last_worked == world.forest.today() else "J でくり抜く"]
		if not near.occupied:
			return "巣箱: 蜂を待っている"
		if float(near.comb) >= 1.0:
			return "巣箱: はちみつ %dkg 採れる(J)" % floori(float(near.comb))
		return "巣箱: 蜂がいる・はちみつをためている"
	return "巣箱: %d箱・蜂 %d箱・採れる %d箱" % [b.hives.size(), b.occupied_count(), b.ready_count()]

# ── 冬の作業(餌台と剪定) ─────────────────────────────────────
# L: 足元に餌台を立てる / 白樺の種を置く
func _feeder_action() -> void:
	var fd := world.feeders
	var pos := player_pos()
	# 餌台のそばでなく、育った木のそばなら、ムクドリの巣箱の作業
	if fd.feeder_near(pos).is_empty() and world.nest_boxes.is_near(pos):
		_nest_box_action(pos)
		return
	var front = pos + $Player.facing() * HIVE_FRONT if $Player.has_method("facing") else null
	var p := world.pests
	match world.feeder_action(pos, front, selected_crop):
		"placed":
			_act("build", fd.last_fed.pos)
			$HUD.show_message(local_text("鳥の餌台を立てた(丸太 -%d本)。L で白樺の種を%d粒置くと鳥が来る(秋と冬)。畑の野菜を置くと、生き物と仲良くなれる" % [fd.LOG_COST, fd.FEED_SEEDS]), 6.0)
		"fed":
			_act("feed", fd.last_fed.pos)
			$HUD.show_message(local_text("餌台に白樺の種を置いた(-%d粒)。少し離れて待つと鳥が来る(餌は翌日まで残る)" % fd.FEED_SEEDS) + _friend_gain_text(), 6.0)
		"offered":
			_act("feed", fd.last_fed.pos)
			$HUD.show_message("餌台の根元に%sを%dkg置いた。夜のあいだに生き物が食べに来る" % [world.garden.CROPS[fd.last_offered].name, fd.OFFER_KG] + _friend_gain_text(), 6.0)
		"full":
			$HUD.show_message("今日はもうこの餌台に餌を置いた(仲良し度 %d/%d)" % [p.friendship, p.FRIEND_MAX])
		"not_season":
			$HUD.show_message("置く野菜がない(鳥の餌の種を置くのは秋と冬。春と夏は、収穫した野菜を%dkg置ける)" % fd.OFFER_KG, 5.0)
		"no_seed":
			$HUD.show_message(local_text("白樺の種が%d粒いる(今 %d粒。白樺の根元に落ちるのを拾うか、市場で買える)。収穫した野菜があれば、それを置ける" % [fd.FEED_SEEDS, int(world.forest.seeds[fd.feed_species()])]), 5.0)
		"no_wood":
			$HUD.show_message("丸太が%d本いる(市場で買うか、育った木を Z で伐る)" % fd.LOG_COST)
		"too_many":
			$HUD.show_message("餌台は%dつまで(種を置くときは、餌台のそばで L)" % fd.MAX_FEEDERS, 5.0)
		"blocked":
			$HUD.show_message("ここには立てられない(区画・小屋・池・木・巣箱のそばや、土地の端は空ける)", 5.0)

# 餌を置いて上がった仲良し度の文言。例: 「。仲良し度 +5(45/100)」
func _friend_gain_text() -> String:
	var p := world.pests
	if p.last_gain <= 0:
		return "(仲良し度 %d/%d)" % [p.friendship, p.FRIEND_MAX]
	var safe := "。もう畑を荒らさない" if p.is_safe() else ""
	return "。仲良し度 +%d(%d/%d)%s" % [p.last_gain, p.friendship, p.FRIEND_MAX, safe]

# L(育った木のそば): ムクドリの巣箱を作る / 続きを作る
func _nest_box_action(pos: Vector2) -> void:
	var nb := world.nest_boxes
	var result: String = nb.act(pos)
	var b: Dictionary = nb.last_box
	match result:
		"started":
			_act("build", b.pos)
			$HUD.show_message("丸太でムクドリの巣箱を作りはじめた(丸太 -%d本・1/%d日)。続きは明日。春になると、ムクドリが渡ってくる" % [nb.LOG_COST, nb.WORK_DAYS], 7.0)
		"worked":
			_act("build", b.pos)
			$HUD.show_message("巣箱を作った(%d/%d日)。続きは明日" % [b.days_done, nb.WORK_DAYS])
		"finished":
			_act("build", b.pos)
			var soon := "もうすぐムクドリのつがいが来る" if world.forest.season in nb.SEASONS else "春になると、ムクドリのつがいが来る"
			$HUD.show_message("ムクドリの巣箱を木に掛けた。%s" % soon, 7.0)
		"done":
			$HUD.show_message("この木にはもう巣箱が掛かっている(ムクドリが来るのは春と夏)")
		"done_today":
			$HUD.show_message("今日はもう作った(1日1回)")
		"too_many":
			$HUD.show_message("ムクドリの巣箱は%dつまで" % nb.MAX_BOXES)
		"no_wood":
			$HUD.show_message("丸太が%d本いる(市場で買うか、育った木を Z で伐る)" % nb.LOG_COST)

# HUD に出す、育った木のそばのムクドリの巣箱の 1 行。そばにいなければ ""
func nest_box_line() -> String:
	var nb := world.nest_boxes
	var pos := player_pos()
	if not world.feeders.feeder_near(pos).is_empty():
		return ""
	var tree: Dictionary = nb.tree_near(pos)
	if tree.is_empty():
		return ""
	var b: Dictionary = nb.box_on(tree.pos)
	if b.is_empty():
		if nb.boxes.size() >= nb.MAX_BOXES:
			return ""
		return "ムクドリの巣箱: L で作れる(丸太%d本・%d日)" % [nb.LOG_COST, nb.WORK_DAYS]
	if not nb.is_done(b):
		return "ムクドリの巣箱: %d/%d日(%s)" % [b.days_done, nb.WORK_DAYS, "今日は済んだ" if nb.worked_today(b) else "L で続きを作る"]
	if world.forest.season in nb.SEASONS:
		return "ムクドリの巣箱: つがいが出入りしている"
	return "ムクドリの巣箱: 春にムクドリが来る"

# HUD に出す、餌台のそばの 1 行。そばにいなければ ""
func feeder_line() -> String:
	var fd := world.feeders
	var near: Dictionary = fd.feeder_near(player_pos())
	if near.is_empty():
		return ""
	var friend := "  仲良し度 %d/%d" % [world.pests.friendship, world.pests.FRIEND_MAX]
	if fd.offered_today(near):
		return "餌台: 今日は野菜を置いた" + friend
	if not fd.can_feed_now():
		return "餌台: L で収穫した野菜を%dkg置ける" % fd.OFFER_KG + friend
	var birds := _feeder_birds_text(near)
	if fd.fed_today(near):
		return "餌台: 今日は餌を置いた" + birds + friend
	if fd.is_fed(near):
		return local_text("餌台: 餌が残っている(L で足す・白樺の種 %d粒)" % fd.FEED_SEEDS) + birds
	return local_text("餌台: 餌がない(L で白樺の種を %d粒置く)" % fd.FEED_SEEDS)

# 暗くて鳥が見えないときの、昼の様子(餌があるときだけ)。例: 「。昼のあいだにシジュウカラ 2羽が来ていた」
# 冬は 17 時に暗くなるので、夕方からしか開けない人にも餌台の鳥が来ていることを知らせる
func _feeder_birds_text(near: Dictionary) -> String:
	var wl := world.wildlife
	if not world.feeders.is_fed(near) or wl.is_daytime():
		return ""
	var names := PackedStringArray()
	var birds: Dictionary = wl.feeder_birds()
	for id in birds:
		names.append("%s %d羽" % [wl.SPECIES[id].name, birds[id]])
	if names.is_empty():
		return ""
	var who := "・".join(names)
	# 夕方に置いた餌には、まだ来ていない(置いた時刻は持たないので、今日置いた餌は明日の昼に来る言い方にする)
	if wl.is_afternoon() and not world.feeders.fed_today(near):
		return "。昼のあいだに%sが来ていた" % who
	return "。明るくなると%sが来る" % who

# X: 足元の果樹を剪定する
func _prune() -> void:
	var f := world.forest
	var pos := player_pos()
	var result: String = world.prune(pos, REACH)
	var fruit_name: String = f.SPECIES[f.last_prune_item].name if f.last_prune_item != "" else ""
	match result:
		"pruned":
			_act("prune", f.trees[f.nearest_fruit_index(pos, REACH)].pos)
			$HUD.show_message("%sを剪定した。次の収穫が増える。切った枝は薪にした(薪 +%d回分)" % [fruit_name, world.PRUNE_FIRES], 6.0)
		"none":
			$HUD.show_message("近くに果樹がない(剪定できるのはリンゴ・サクランボ・スモモ・ナシ)")
		"preview":
			$HUD.show_message("未来のプレビュー中は剪定できない")
		"not_season":
			$HUD.show_message("剪定は、葉の落ちた冬にする")
		"young":
			$HUD.show_message("%sはまだ若いので、切らなくてよい(実りはじめてから)" % fruit_name)
		"done":
			$HUD.show_message("%sはこの冬もう剪定した" % fruit_name)

# HUD に出す、果樹のそばの 1 行(冬だけ)。そばにいなければ ""
func prune_line() -> String:
	var f := world.forest
	if f.season != "winter" or f.time_offset_years > 0.0:
		return ""
	var i: int = f.nearest_fruit_index(player_pos(), REACH)
	if i < 0:
		return ""
	var tree: Dictionary = f.trees[i]
	var fruit_name: String = f.SPECIES[tree.species].name
	if f.is_pruned(tree):
		return "%s: この冬は剪定した(次の収穫が増える)" % fruit_name
	if f.real_age_years(tree) < float(f.FRUITS[tree.species].age) or not f.is_established(tree):
		return ""
	return "%s: X で剪定できる" % fruit_name

# HUD に出す、今のヒント。なければ ""
func hint_text() -> String:
	var id: String = world.guide.current
	if id == "":
		return ""
	if id == "winter" and not world.forest.snowy_winter():
		return Msg.MILD_WINTER_TEXT if world.region.has_frost() else Msg.WARM_WINTER_TEXT
	return local_text(Msg.GUIDE_TEXTS[id])

# 決まった文言の木の名前を、その土地の木に置き換える(県を選ぶ前は今までの文言のまま)。
# 白樺の種 → 餌台に置く種(その土地の広葉樹)、シベリア杉 → 家族の木、家族の杉 → ガジュマルなら家族の木
func local_text(text: String) -> String:
	var f := world.forest
	var wind: String = f.wind_seed()
	if wind != "birch":
		var sp: Dictionary = f.SPECIES[wind]
		text = text.replace("白樺は樹齢15年から", "%sは樹齢%d年から" % [sp.name, int(sp.wood_age)])
		text = text.replace("白樺の種", sp.name + "の種").replace("白樺の根元", sp.name + "の根元")
	var family: String = world.quests.family_tree()
	if family != "cedar":
		text = text.replace("シベリア杉", f.SPECIES[family].name)
		if family != "sugi":
			text = text.replace("家族の杉", "家族の木")
	return text

# C: 近くの訪問者に話しかける。いなければ近くの家族に
func _talk() -> void:
	var near_visitor: bool = has_node("Visitor") and world.visitors.is_here() and $Visitor.can_talk(player_pos())
	if not near_visitor and family_talk.family_near() != "":
		family_talk._talk_family(family_talk.family_near())
		return
	if not has_node("Visitor") or not world.visitors.is_here():
		return
	if not $Visitor.can_talk(player_pos()):
		$HUD.show_message(visitor_talk.visitor_line())
		return
	world.visitors.check_today()  # 今日のうちに手詰まりになっていたら、助けてくれる
	$Visitor.greet()
	_sfx("open")
	_panel = "visitor"
	$Player.set_physics_process(false)
	$HUD.open_shop()

# HUD に出す、話せる人の 1 行: 訪問者と話せる距離ならその人、家族のそばなら家族、遠くに訪問者が来ていればその案内
func people_line() -> String:
	var visitor := visitor_talk.visitor_line()
	if visitor.ends_with("(C で話す)"):
		return visitor
	var fam := family_talk.family_near()
	if fam != "":
		var m: Dictionary = world.family.member(fam)
		return "%s(%s)(C で話す)" % [m.name, m.relation]
	return visitor

# 向きの文言(画面の上が北)
static func compass(to: Vector2) -> String:
	const NAMES := ["東", "南東", "南", "南西", "西", "北西", "北", "北東"]
	var i: int = posmod(roundi(to.angle() / (TAU / NAMES.size())), NAMES.size())
	return NAMES[i]

# はじめて来た生き物を知らせる(3D だけ。2D には姿がない)。ほかの知らせを消さないよう、出ていないときに見る
func check_wildlife() -> void:
	if not has_node("Wildlife") or $HUD.is_message_visible():
		return
	var names := PackedStringArray()
	for id in world.wildlife.check_arrivals():
		names.append(world.wildlife.SPECIES[id].name)
	if not names.is_empty():
		$HUD.show_message("土地に%sが来るようになった" % "と".join(names), 6.0)

# HUD に出す、見かけた生き物(土地と池)
func creatures_line() -> String:
	var q := world.quests
	var names := PackedStringArray()
	for id in q.guide_seen():
		names.append(_creature_name(id))
	var head := "%d/%d" % [names.size(), q.guide_ids().size()]
	return "%s  %s" % [head, _rows(names, 6)] if not names.is_empty() else "%s  まだ見ていない" % head

# 足元に落ちている種を拾う(歩いて近づくだけ)
func _collect_pickups() -> void:
	if $HUD.is_shop_open():
		return
	var got: Array = world.forest.collect_near(player_pos(), PICKUP_RADIUS)
	for g in got:
		$HUD.show_message("%sの種を拾った(+%d)" % [world.forest.SPECIES[g.species].name, g.amount] + family_talk._family_seeds())

# 果樹の収穫の文言(結果が harvested / not_season / young のとき)
func _fruit_message(result: String) -> String:
	var f := world.forest
	var item: String = f.last_harvest_item
	var fruit: Dictionary = f.FRUITS[item]
	var fruit_name: String = f.SPECIES[item].name
	match result:
		"harvested":
			var extra: String = "剪定で +%d%s。" % [f.last_harvest_extra, fruit.unit] if f.last_harvest_extra > 0 else ""
			if f.last_meal_extra > 0:
				extra += "漬物で +%d%s。" % [f.last_meal_extra, fruit.unit]
			return "%sを%d%s収穫した(%s市場で1%s %d₽で売れる)" % [fruit_name, f.last_harvest_count, fruit.unit, extra, fruit.unit, world.market.SELL_PRICES[item]]
		"not_season":
			var seasons := PackedStringArray()
			for s in fruit.seasons:
				seasons.append(SEASON_NAMES[s])
			return "%sが実るのは%s" % [fruit_name, "・".join(seasons)]
	return "%sはまだ実らない(樹齢%d年から)" % [fruit_name, int(fruit.age)]

# 発見の文言。雨の日は冬なら雪になる(降るものは WeatherView3D と同じ。効き目は雨と同じ)
func daily_message(id: String) -> String:
	var f := world.forest
	if id == "rain" and is_snow_day(f.season):
		return "雪が降った。今日は全部の木と野菜に水やり済み"
	if id == "birch_seed" and f.wind_seed() != "birch":
		var name: String = f.SPECIES[f.wind_seed()].name
		return "%s(%sの種 +1)" % [Msg.SEED_ARRIVALS.get(f.wind_seed(), "風で%sの種が飛んできた") % name, name]
	if id == "cedar_seed" and f.nut_seed() != "cedar":
		var name: String = f.SPECIES[f.nut_seed()].name
		return "%s(%sの種 +1)" % [Msg.SEED_ARRIVALS.get(f.nut_seed(), "風で%sの種が飛んできた") % name, name]
	return Msg.DAILY_MESSAGES[id]

# その季節の雨の日は雪になるか(雪の積もる土地の冬だけ。降るものは WeatherView3D と同じ)
func is_snow_day(season: String) -> bool:
	return season == "winter" and world.forest.snowy_winter()

# その土地のクエストの文言(家族の木は土地で変わる)
func quest_text(id: String) -> Dictionary:
	var t: Dictionary = Msg.QUEST_TEXTS[id].duplicate()
	for k in t:
		t[k] = local_text(t[k])
	return t

const CABIN_STAGE_NAMES := {"foundation": "基礎", "walls": "壁", "roof": "屋根"}

# プレイヤーの足元(m)
func player_pos() -> Vector2:
	return $Player.ground_pos()

# 画面の音を鳴らす(3D だけ)
func _sfx(sound: String) -> void:
	if $Audio.has_method("play"):
		$Audio.play(sound)

# M: 音量を切り替える(大 → 中 → 小 → 消す → 大)
func _next_sound_level() -> void:
	world.sound_level = posmod(world.sound_level - 1, SOUND_LEVELS.size())
	_apply_sound_level()
	world.save_game()
	$HUD.show_message("音量: %s" % SOUND_LEVEL_NAMES[world.sound_level])

func _apply_sound_level() -> void:
	var v: float = SOUND_LEVELS[world.sound_level]
	AudioServer.set_bus_mute(0, v <= 0.0)
	if v > 0.0:
		AudioServer.set_bus_volume_db(0, linear_to_db(v))

# 作業の動きをする(3D だけ)。ルールには関わらない。作業が成功したときに呼ぶ
func _act(kind: String, target = null, item := "") -> void:
	if $Player.has_method("act"):
		$Player.act(kind, target, item)

func _on_plant_tree(pos: Vector2) -> void:
	if $HUD.is_shop_open() or $HUD.is_diary_open() or $HUD.is_picker_open():
		return
	var problem: String = world.tree_spot_problem(pos)
	if problem == "outside":
		$HUD.show_message(Msg.TREE_SPOT_MESSAGES.outside)
		return
	# 菜園の区画の上では、木ではなく野菜をまく
	if world.land.plot_at(pos) != null:
		_sow(pos)
		return
	if problem != "":
		$HUD.show_message(Msg.TREE_SPOT_MESSAGES[problem])
		return
	if selected_form == "seed" and selected_species in world.forest.SAPLING_ONLY:
		$HUD.show_message("%sは苗木から育てる(V で苗木に切り替える。市場で買える)" % world.forest.SPECIES[selected_species].name, 5.0)
		return
	match world.forest.plant_problem(selected_species, selected_form):
		"not_here":
			$HUD.show_message("%sは%sでは育たない(1・2・3 で、この土地で育つ木を選べる)" % [world.forest.SPECIES[selected_species].name, world.region.pref_name()], 5.0)
			return
		"frozen":
			$HUD.show_message("冬は地面が凍っていて植えられない(白樺の種だけは雪の上にまける)", 5.0)
			return
	if not world.forest.add_tree(pos, selected_species, selected_form):
		$HUD.show_message("%sの%sがない(市場で買える)" % [world.forest.SPECIES[selected_species].name, FORM_NAMES[selected_form]])
		return
	_act("plant", pos)
	if selected_form == "seed":
		$HUD.show_message("種をまいた。芽が出るかは1日たつと分かる")
	_check_quests()

# 1・2・3: 押すたびに、その組(広葉樹・果樹・針葉樹)のうち、この土地で育つ次の木を選ぶ。
# 苗木からしか育てない果樹なら、苗木に切り替える。その組に育つ木がなければ選び直さない
func _select_next_in(group: String) -> void:
	var order: Array = world.forest.plantable_in(group)
	if order.is_empty():
		$HUD.show_message("この土地で育つ%sは、まだない" % GROUP_NAMES[group])
		return
	var i: int = order.find(selected_species)
	selected_species = order[(i + 1) % order.size()] if i >= 0 else order[0]
	if selected_species in world.forest.SAPLING_ONLY:
		selected_form = "sapling"

func _select_next_fruit() -> void:
	_select_next_in("fruit")

const GROUP_NAMES := {"broadleaf": "広葉樹", "fruit": "果樹", "conifer": "針葉樹"}

# 操作説明に出す、キーで選べる木。1 種類ならその名前、2 種類以上なら「広葉樹(白樺/コナラ)」。
# with_group = false なら名前だけを / でつなぐ(果樹の行用)
func group_keys_text(group: String, with_group := true) -> String:
	var names := PackedStringArray()
	for sp in world.forest.plantable_in(group):
		names.append(world.forest.SPECIES[sp].name)
	if names.is_empty():
		return "なし" if with_group else "この土地で育つものはまだない"
	if names.size() == 1 or not with_group:
		return "/".join(names)
	return "%s(%s)" % [GROUP_NAMES[group], "/".join(names)]

# 県を決めたあと: 選んでいる木がこの土地で育たなければ、育つ広葉樹に選び直す
func _fit_selection() -> void:
	if world.forest.grows_here(selected_species):
		return
	var list: Array = world.forest.plantable_in("broadleaf")
	if not list.is_empty():
		selected_species = list[0]
		selected_form = "seed"

# 選んでいる植えるもの(HUD 用)。例: 「白樺の種」
func selected_name() -> String:
	return world.forest.SPECIES[selected_species].name + "の" + FORM_NAMES[selected_form]

# ── 小屋 ──────────────────────────────────────────────────
# H: まだ場所がなければ足元に決める。決まっていれば今日の作業をする。
# 完成していれば、ストーブの前なら台所、ベッドのそばなら日記、ほかは苗づくり
func _cabin_action() -> void:
	var c := world.cabin
	var pos := player_pos()
	if world.family.is_at_bedroll(pos):  # テントの中の自分の寝袋(小屋ができるまで)
		kitchen_panel._sleep()
		return
	if c.site == null:
		var taken: String = world.cabin_spot_problem(pos)
		if taken != "":
			$HUD.show_message("%sにかかる場所には建てられない" % Msg.TAKEN_NAMES[taken])
			return
		$HUD.show_message(Msg.CABIN_PLACE_MESSAGES[c.place(pos)], 5.0)
		return
	if c.is_complete():
		if c.is_at_chop_block(pos):
			_split_wood()
		elif c.is_at_stool(pos):
			kitchen_panel._open_table()
		elif c.is_at_kamado(pos):
			kitchen_panel._open_kitchen(1)
		elif c.is_at_stove(pos):
			kitchen_panel._open_kitchen(0)
		elif c.is_at_chair(pos):
			kitchen_panel._sit_chair()
		elif c.is_at_bed(pos):
			kitchen_panel._sleep()
		elif c.is_at_ext_site(pos):
			_extension_work(pos)
		else:
			_seedling_action(pos)
		return
	var s: Dictionary = c.current_stage()
	var result: String = c.work(pos)
	if result in ["worked", "stage_done", "finished"]:
		_act("build", c.site)
	match result:
		"worked":
			$HUD.show_message("%sの作業をした(丸太 -%d本)。続きは明日" % [CABIN_STAGE_NAMES[s.id], s.logs_per_day], 5.0)
		"stage_done":
			$HUD.show_message("%sができた(丸太 -%d本)。明日から%s" % [CABIN_STAGE_NAMES[s.id], s.logs_per_day, CABIN_STAGE_NAMES[c.current_stage().id]], 5.0)
		"finished":
			$HUD.show_message("小屋が建った。南のドアから入れる。窓辺で苗づくり(トマト か きゅうり [6] を選んで H)、ストーブで料理、ベッドで日記", 8.0)
		"far":
			$HUD.show_message("小屋の場所まで行って作業する(%.0fm以内)" % c.REACH)
		"inside":
			$HUD.show_message("建てる場所の外に出て作業する")
		"done_today":
			$HUD.show_message("今日の作業はもう済んだ(1日1回)")
		"no_wood":
			$HUD.show_message("丸太が足りない(%d本 必要。市場で買うか、育った木を Z で伐る)" % s.logs_per_day, 5.0)

# 薪割り台で H: 1 回割る
func _split_wood() -> void:
	var k := world.kitchen
	var before: int = k.firewood
	match world.split_wood():
		"split":
			if world.tools.last_machine == "splitter":
				_act("machine", world.cabin.chop_pos(), "splitter")
				$HUD.show_message("薪割り機で割った(薪 +%d回分で %d回分。ガソリン -%s・残り %s)" % [k.firewood - before, k.firewood, gas_text(world.tools.gas_needed("splitter")), gas_text(world.tools.gas)], 5.0)
				return
			_act("chop", world.cabin.chop_pos())
			var warm := "。体が温まって、いつもの倍割れる" if k.has_effect("warm") else ""
			var no_gas := "。薪割り機はガソリンがなくて動かない" if world.tools.has("splitter") else ""
			$HUD.show_message("薪を割った(薪 %d回分)%s%s" % [k.firewood, warm, no_gas])
		"no_log":
			$HUD.show_message("割る丸太がない(市場で買うか、育った木を Z で伐る)", 5.0)
		"full":
			$HUD.show_message("薪はもう十分ある(%d回分)" % k.firewood)

# 完成した小屋で H: 育った苗を受け取る → 世話をする → 種をまく
func _seedling_action(pos: Vector2) -> void:
	var sl := world.seedlings
	var crop: Dictionary = world.garden.CROPS[selected_crop]
	var sill: Vector2 = world.cabin.site + Vector2(world.cabin.WIDTH * 0.5 - 0.3, 0.2)  # 東の窓辺の鉢
	match sl.act(pos, selected_crop):
		"collected":
			_act("pick", sill, "tomato")
			$HUD.show_message("苗が%d鉢育った(春に畑へ植えるか、市場で売れる)" % sl.last_count, 5.0)
		"tended":
			_act("water", sill)
			$HUD.show_message("苗の世話をした(%d鉢)" % sl.last_count)
		"sown":
			_act("plant", sill)
			$HUD.show_message("%sの種を鉢にまいた(%d/%d鉢。毎日世話をすれば%d日で苗になる)" % [crop.name, sl.pots.size(), sl.max_pots(), sl.GROW_DAYS], 5.0)
		"far":
			$HUD.show_message("小屋まで行って作業する(%.0fm以内)" % world.cabin.REACH)
		"not_seedling":
			$HUD.show_message("苗にできるのはトマト と きゅうり [6]")
		"full":
			$HUD.show_message("窓辺はいっぱい(%d鉢)。今日の世話は済んだ" % sl.max_pots())
		"no_seed":
			$HUD.show_message("%sがない(市場で買える)" % crop.seed_name)

# 「トマト 10kg」のような材料の文言
func _amount_text(item: String, n: int) -> String:
	return "%s %d%s" % [produce_name(item), n, produce_unit(item)]

# ── 小屋の増築と揺り椅子 ────────────────────────────────────────
func _ext_total_days() -> int:
	var n := 0
	for s in world.cabin.EXT_STAGES:
		n += int(s.days)
	return n

# 西の外で H: 増築の作業をする
func _extension_work(pos: Vector2) -> void:
	var c := world.cabin
	var s: Dictionary = c.ext_current_stage()
	var result: String = c.work_extension(pos)
	if result in ["worked", "stage_done", "finished"]:
		_act("build", c.ext_rect().get_center())
	match result:
		"worked":
			$HUD.show_message("増築の%sの作業をした(丸太 -%d本)。続きは明日" % [CABIN_STAGE_NAMES[s.id], s.logs_per_day], 5.0)
		"stage_done":
			$HUD.show_message("増築の%sができた(丸太 -%d本)。明日から%s" % [CABIN_STAGE_NAMES[s.id], s.logs_per_day, CABIN_STAGE_NAMES[c.ext_current_stage().id]], 5.0)
		"finished":
			$HUD.show_message("増築ができた。小屋の中から西の部屋に入れる。かまどで2つ目の鍋が使え、西の窓辺にも鉢を置ける(%d鉢まで)。家具は市場で買える" % world.seedlings.max_pots(), 9.0)
		"inside":
			$HUD.show_message("建てる場所の外に出て作業する")
		"done_today":
			$HUD.show_message("今日の増築の作業はもう済んだ(1日1回)")
		"no_wood":
			$HUD.show_message("丸太が足りない(%d本 必要。市場で買うか、育った木を Z で伐る)" % s.logs_per_day, 5.0)

# HUD に出す、家具のそばでの案内。そばにいなければ ""
func furniture_line() -> String:
	var c := world.cabin
	var pos := player_pos()
	if c.is_at_chop_block(pos):
		return "薪割り台(H で割る・薪 %d回分・丸太 %d本)" % [world.kitchen.firewood, int(c.materials.log)]
	if c.is_at_stool(pos):
		return "腰掛けのそば(H で座って食べる)"
	if c.is_at_stove(pos):
		return "ストーブの前(H で料理)"
	if c.is_at_bed(pos):
		return "ベッドのそば(H で休んで日記を見る)"
	if world.family.is_at_bedroll(pos):
		return "寝袋のそば(H で休んで日記を見る)"
	if world.family.is_in_tent(pos):
		return "テントの中(西のいちばん端が自分の寝袋)"
	return ""

# 樹種の名前を「・」でつなぐ。例: 「ブナ・ミズナラ」
func _names_of(species: Array) -> String:
	return "・".join(PackedStringArray(species.map(func(sp): return world.forest.SPECIES[sp].name)))

static func _bullets(items: PackedStringArray, empty_text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for item in items:
		out.append("・" + item)
	if out.is_empty():
		out.append("・" + empty_text)
	return out

# HUD に出す、小屋の 1 行
func cabin_line() -> String:
	var c := world.cabin
	if c.site == null:
		return "小屋: H で足元に場所を決める(丸太%d本・%d日)" % [c.total_logs(), c.total_days()]
	if c.ext_building():
		var es: Dictionary = c.ext_current_stage()
		var ext_today := "今日の作業は済んだ" if c.ext_last_worked == world.forest.today() else "西の外から H・丸太%d本" % es.logs_per_day
		return "小屋の増築: %s %d/%d日(%s)" % [CABIN_STAGE_NAMES[es.id], c.ext_days_done, es.days, ext_today]
	if c.is_complete():
		var sl := world.seedlings
		if sl.pots.is_empty():
			return "小屋: 完成(H で苗づくり)"
		var left: int = sl.days_left()
		var todo := "H で受け取る" if left == 0 else ("H で世話" if sl.needs_care() else "世話は済んだ")
		return "小屋: 苗 %d/%d鉢 あと%d日(%s)" % [sl.pots.size(), sl.max_pots(), left, todo]
	var s: Dictionary = c.current_stage()
	var today := "今日の作業は済んだ" if c.worked_today() else "H で作業・丸太%d本" % s.logs_per_day
	return "小屋: %s %d/%d日(%s)" % [CABIN_STAGE_NAMES[s.id], c.days_done, s.days, today]

# ── 池 ────────────────────────────────────────────────────
func _pond_action() -> void:
	var result: String = world.pond_action(player_pos())
	$HUD.show_message(Msg.POND_MESSAGES[result], 5.0)
	if result == "dug" or result == "finished":
		_act("dig", world.land.pond)
	if result == "placed" or result == "finished":
		world.save_game()
		_check_quests(Msg.POND_MESSAGES[result])

# 水の出どころ(GameWorld.water_source)の名前
func source_name(source: String) -> String:
	return {"well": "井戸", "river": "川"}.get(source, "池")

# 水の出どころへ向く場所(人物の動き用)。川は足元の近くの川の中
func source_spot(source: String, pos: Vector2) -> Vector2:
	match source:
		"well":
			return world.well.site
		"river":
			return Vector2(pos.x, world.river.center_y(pos.x))
	return world.land.pond

# HUD に出す、井戸か池か川のそばでの案内。そばにいなければ ""
func pond_beside_line() -> String:
	var pos := player_pos()
	var source: String = world.water_source(pos)
	if source == "" or source == "pond_frozen" or source == "pond_empty":
		return ""
	var t := world.tools
	var place := source_name(source)
	var dry: Array = world.dry_around_source(pos)
	if t.can_run("pump") and dry[0] + dry[1] > 0 and (source != "pond" or world.pond.water >= world.pond.WATER_COST):
		var cost := "池の水 -%d%%・" % world.pond.WATER_COST if source == "pond" else ""
		return "%sのそば: Q でポンプ 区画 %d・木 %d にまとめて水やり(%sガソリン -%s)" % [place, dry[0], dry[1], cost, gas_text(t.gas_needed("pump"))]
	if not t.can_full():
		return "%sのそば: Q でジョウロに汲む(%d/%dL)" % [place, t.can_water, t.can_size()]
	return ""

# HUD に出す、池の 1 行
func pond_line() -> String:
	var p := world.pond
	if not p.is_placed():
		return "池: P で足元に場所を決める(%d日)" % p.DIG_DAYS
	if not p.is_dug():
		return "池: 掘っている %d/%d日(%s)" % [p.days_dug, p.DIG_DAYS, "今日は済んだ" if p.dug_today() else "P で掘る"]
	var names := PackedStringArray()
	for id in p.present():
		names.append(p.CREATURES[id].name)
	var state := ("氷が張っている(上を歩くと滑る)" if p.is_dug() else "氷が張っている") if p.is_frozen() else "水 %d%%" % p.water
	return "池: %s%s" % [state, "(%s)" % "・".join(names) if not names.is_empty() else ""]

# ── 畑の野菜 ────────────────────────────────────────────────
# まける季節の文言(土地の気候で変わる)。例: 「春・秋」
func crop_seasons(kind: String) -> String:
	var names := PackedStringArray()
	for s in ["spring", "summer", "autumn", "winter"]:
		if world.garden.can_sow_in(kind, s):
			names.append(SEASON_NAMES[s])
	return "・".join(names)

func _sow(pos: Vector2) -> void:
	var g := world.garden
	var crop: Dictionary = g.CROPS[selected_crop]
	var planted_by: Dictionary = world.plant_crop(pos, selected_crop)  # 育った苗があれば、種より先に苗を使う
	var from_seedling: bool = planted_by.from_seedling
	match planted_by.result:
		"sown":
			_act("plant", world.land.plot_center(pos))
			var verb := "の苗を植えた" if from_seedling else "をまいた"
			var planted: Dictionary = g.crop_at(pos)
			if g.misses_frost(planted):
				# まくのは止めない。間に合わないことだけ知らせる
				$HUD.show_message("%s%s。ただ、霜(%s)まであと%d日で、育ちきる(%d日)前に枯れてしまう" % [crop.name, verb, g.frost_date_text(), g.days_to_frost(), g.days_left(planted)], 7.0)
			elif g.CROPS[selected_crop].get("paddy", false):
				var text := "%sを田植えした(田んぼに水を張った)。毎日水をやれば%d日で収穫できる。水を切らすとほとんど育たない" % [crop.seed_name, g.days_left(planted)]
				$HUD.show_message(text + family_talk._family_rice(world.land.plot_center(pos)), 6.0)
			else:
				$HUD.show_message("%s%s(毎日水をやれば%d日で収穫できる)" % [crop.name, verb, g.days_left(planted)], 5.0)
		"needs_seedling":
			$HUD.show_message("%sは苗から育てる(完成した小屋で H を押して鉢にまく)" % crop.name, 5.0)
		"needs_paddy":
			$HUD.show_message("田んぼは、川か池から水が引ける区画にだけ作れる(川か、掘った池から %dm 以内)" % int(world.river.PADDY_REACH), 6.0)
		"occupied":
			$HUD.show_message("この区画にはもう%sが育っている" % g.CROPS[g.crop_at(pos).kind].name)
		"not_season":
			$HUD.show_message("%sをまけるのは%s(今は%s)" % [crop.name, crop_seasons(selected_crop), SEASON_NAMES[world.forest.season]])
		"no_seed":
			$HUD.show_message("%sがない(市場で買える)" % crop.seed_name)

# HUD に出す、選んでいるものの 1 行(いくつ持っているかも分かるように)
func selection_line() -> String:
	var f := world.forest
	var stock: Dictionary = f.saplings if selected_form == "sapling" else f.seeds
	var crop: Dictionary = world.garden.CROPS[selected_crop]
	var seedlings := ""
	if selected_crop in world.seedlings.SEEDLING_CROPS:
		seedlings = "・苗 %d" % world.seedlings.ready[selected_crop]
	return "植える: %s %d   畑にまく: %s 種 %d%s(%sにまける・%d日で育つ)" % [
		selected_name(), stock[selected_species],
		crop.name, world.garden.seeds[selected_crop], seedlings, crop_seasons(selected_crop), crop.grow_days,
	]

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
	if g.is_spoiled(c):
		return "足元の区画: %s 傷みはじめた(E で収穫・量は半分)" % crop_name
	if g.is_ripe(c):
		return "足元の区画: %s 収穫できる(E・あと%d日で傷む)" % [crop_name, g.days_until_spoiled(c)]
	var water := "水やり済み" if g.watered_today(c) else "Q で水やり"
	if g.CROPS[c.kind].get("paddy", false):
		crop_name = "田んぼの稲"
		if not g.watered_today(c):
			water = "Q で水やり・水を切らすとほとんど育たない"
	if g.has_weeds(c):
		water += "・雑草 E で抜く"
	elif c.get("mulched", false):
		water += "・わら"
	elif g.straw > 0:
		water += "・E でわらを敷く"
	if int(c.get("bites", 0)) > 0:
		water += "・かじられた"
	return "足元の区画: %s あと%d日(%s)" % [crop_name, g.days_left(c), water]

# n 個ごとに折り返して並べる(市場の画面と重ならない幅にするため)
static func _rows(parts: PackedStringArray, n: int) -> String:
	var rows := PackedStringArray()
	for i in range(0, parts.size(), n):
		rows.append("  ".join(parts.slice(i, i + n)))
	return "\n    ".join(rows)

# HUD に出す、持っている野菜の種
# 「ラディッシュ 3・にんじん 2」
func orders_text(orders: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind in orders:
		parts.append("%s %d" % [world.garden.CROPS[kind].name, int(orders[kind])])
	return "・".join(parts)

# 持ち物の野菜の種: この土地で育つ野菜と、持っている野菜(組の順)
func crop_seeds_line() -> String:
	var parts := PackedStringArray()
	var g := world.garden
	for group in g.GROUPS:
		for kind in g.CROPS:
			if g.CROPS[kind].group == group and (g.grows_here(kind) or int(g.seeds[kind]) > 0):
				parts.append("%s %d" % [g.CROPS[kind].name, g.seeds[kind]])
	return _rows(parts, 4)

# 4〜9: 押すたびに、その組のうちこの土地で育つ次の野菜を選ぶ
func _select_next_crop(group: String) -> void:
	var order: Array = world.garden.crops_in(group)
	if order.is_empty():
		$HUD.show_message("この土地で育つ%sは、まだない" % CROP_GROUP_NAMES[group])
		return
	var i: int = order.find(selected_crop)
	selected_crop = order[(i + 1) % order.size()] if i >= 0 else order[0]

# 操作説明の、野菜の組のキー。例: 「[4]根菜 [5]いも …」
func crop_keys_text() -> String:
	var parts := PackedStringArray()
	var keys := ["[4]", "[5]", "[6]", "[7]", "[8]", "[9]"]
	for i in range(world.garden.GROUPS.size()):
		parts.append(keys[i] + CROP_GROUP_NAMES[world.garden.GROUPS[i]])
	return " ".join(parts) + "(押すたびに次の野菜)"

# HUD に出す、持っている収穫物(持っているものだけ。苗は seedlings_line、保存食は food_line)
func produce_line() -> String:
	var parts := PackedStringArray()
	for item in world.market.SELL_PRICES:
		var n := produce_count(item)
		if n > 0 and not item.begins_with("seedling_") and not item.begins_with("seed_") and not world.kitchen.RECIPES.has(item):
			parts.append(_amount_text(item, n))
	return _rows(parts, 4) if not parts.is_empty() else "なし"

# HUD に出す、持っている保存食(名前が長いので 2 つごとに折り返す)
func food_line() -> String:
	var parts := PackedStringArray()
	for id in world.kitchen.RECIPES:
		var n := produce_count(id)
		if n > 0:
			parts.append(_amount_text(id, n))
	return _rows(parts, 2) if not parts.is_empty() else "なし"

# HUD に出す、育った苗の 1 行
func seedlings_line() -> String:
	var ready: Dictionary = world.seedlings.ready
	return "トマト %d鉢  きゅうり %d鉢" % [ready.tomato, ready.cucumber]

func produce_name(item: String) -> String:
	if item == world.visitors.FIREWOOD:
		return "薪"
	if item.begins_with("seed_"):
		return world.forest.SPECIES[item.trim_prefix("seed_")].name + "の種"
	if world.forest.FRUITS.has(item):
		return world.forest.SPECIES[item].name
	if item == "honey":
		return "はちみつ"
	if item.begins_with("seedling_"):
		return world.garden.CROPS[item.trim_prefix("seedling_")].name + "の苗"
	if world.kitchen.RECIPES.has(item):
		return world.kitchen.RECIPES[item].name
	if item.begins_with("flour_"):
		return world.mill.FLOURS[item.trim_prefix("flour_")].name
	return world.garden.CROPS[item].name

func produce_unit(item: String) -> String:
	if item == world.visitors.FIREWOOD:
		return "回分"
	if item.begins_with("seed_"):
		return "粒"
	if world.forest.FRUITS.has(item):
		return world.forest.FRUITS[item].unit
	if world.kitchen.RECIPES.has(item):
		return world.kitchen.RECIPES[item].unit
	return "鉢" if item.begins_with("seedling_") else "kg"

func produce_count(item: String) -> int:
	if item.begins_with("seed_"):
		return int(world.forest.seeds.get(item.trim_prefix("seed_"), 0))
	if world.forest.FRUITS.has(item):
		return int(world.forest.produce[item])
	if item == "honey":
		return int(world.bees.stock.honey)
	if item.begins_with("seedling_"):
		return int(world.seedlings.ready[item.trim_prefix("seedling_")])
	if world.kitchen.RECIPES.has(item):
		return int(world.kitchen.stock[item])
	if item.begins_with("flour_"):
		return int(world.mill.flour[item.trim_prefix("flour_")])
	return int(world.garden.produce[item])

# 右の画面の見出し
func shop_title() -> String:
	if _panel == "family":
		var m: Dictionary = world.family.member(family_talk._family_talk.get("id", ""))
		return "%s(%s)" % [m.get("name", ""), m.get("relation", "")]
	if _panel == "visitor":
		var v := world.visitors
		return "%s(%s)" % [v.CAST[v.who()].name, v.LEVEL_NAMES[v.level_of(v.who())]]
	if _panel == "table":
		return "腰掛け(クリックか 矢印キー + Enter で選ぶ)"
	if _panel == "chair":
		return "揺り椅子"
	if _panel == "kitchen":
		return "%s(クリックか 矢印キー + Enter で選ぶ)" % kitchen_panel.POT_PLACES[world.kitchen.active]
	return "市場(クリックか 矢印キー + Enter で選ぶ)"

# 右の画面の 2 行目
func shop_header() -> String:
	if _panel == "family":
		return family_talk._family_talk.get("text", "")
	if _panel == "visitor":
		return visitor_talk.visitor_text()
	if _panel == "chair":
		return "ゆらゆら揺れながら、窓の外を眺めている"
	if _panel == "table":
		var k := world.kitchen
		if k.eaten_today().is_empty():
			return "食べたもので調子が変わる(同じものは1日1つ、%d種類まで)" % k.MEAL_KINDS
		return "今日は %d/%d種類 食べた: %s" % [k.eaten_today().size(), k.MEAL_KINDS, kitchen_panel._effects_text()]
	if _panel == "kitchen":
		return "薪: %d回分   丸太: %d本(丸太1本で%d回分)" % [world.kitchen.firewood, int(world.cabin.materials.log), world.kitchen.LOG_FIRES]
	return "所持金: %s₽" % $HUD._money_text(world.market.money)

# 右の画面に並べる行 [{id, text, column}]。市場は column 0 = 買う列、1 = 売る列
func shop_rows() -> Array:
	if _panel == "kitchen":
		return kitchen_panel.kitchen_rows()
	if _panel == "table":
		return kitchen_panel.table_rows()
	if _panel == "visitor":
		return visitor_talk.visitor_rows()
	if _panel == "family":
		return family_talk.family_rows()
	if _panel == "chair":
		return [{"id": "close", "text": "立つ(H / Esc)", "column": 0}]
	return market_panel.market_rows()

# 右の画面に今出す行。市場は、今のページの品とページを送る行(ほかの画面は全部)
func visible_shop_rows() -> Array:
	var left: int = kitchen_panel._cook_page if _panel == "kitchen" or _panel == "table" else market_panel._buy_page
	return shop_rows().filter(func(r): return not r.has("page") or r.page == (left if r.column == 0 else market_panel._sell_page))

func _toggle_shop() -> void:
	if $HUD.is_shop_open():
		_close_shop()
		return
	var m := world.market
	if not m.is_near(player_pos()):
		var d := player_pos().distance_to(m.POS) - m.REACH
		$HUD.show_message("市場は南の境界の外にある(あと%dm)" % ceili(d))
		return
	_panel = "market"
	_sfx("open")
	$Player.set_physics_process(false)  # 買い物中は歩かない
	$HUD.open_shop()

func _close_shop() -> void:
	var was_chat: bool = _panel == "visitor" and not world.visitors.has_request()
	var was_sitting: bool = _panel == "table" or _panel == "chair"
	if _panel == "chair" and $Player.has_method("set_rocking"):
		$Player.set_rocking(false)
		$Cabin.set_rocking(false)
	_sfx("click")
	$HUD.close_shop()
	$Player.set_physics_process(true)
	if was_sitting and $Player.has_method("stand_up"):
		$Player.stand_up()
	if was_chat:
		world.visitors.finish_chat()  # 話し終えると帰っていく
		var up := visitor_talk._take_level_up()
		if up != "":
			$HUD.show_message(up, 6.0)
	_panel = "market"

func _on_shop_action(id: String) -> void:
	if id == "close":
		_close_shop()
		return
	if _panel == "kitchen":
		_sfx("click")
		kitchen_panel._kitchen_action(id)
		return
	if _panel == "table":
		_sfx("click")
		kitchen_panel._table_action(id)
		return
	if _panel == "visitor":
		visitor_talk._visitor_action(id)
		return
	if _panel == "family":
		_sfx("click")
		family_talk._family_action(id)
		return
	market_panel._market_action(id)

func _toggle_plot() -> void:
	var result: String = world.toggle_plot(player_pos())
	var msg: String = Msg.PLOT_MESSAGES[result]
	if result == "placed":
		msg = msg % world.land.plots.size()
	elif result == "limit":
		msg = msg % world.garden.NEW_PLOTS_PER_DAY
	$HUD.show_message(msg)
	if result == "placed" or result == "removed":
		_act("dig", world.land.plot_center(player_pos()))
	_after_land_change(result)

func _after_land_change(result: String) -> void:
	if result == "placed" or result == "removed":
		world.save_game()
		_check_quests()

# クエストを判定し、達成があれば知らせて保存する
# クエスト・木の節目・図鑑に新しいことがあれば知らせる。prefix は、その前に出ていた知らせ(上書きして消さないように前に並べる)
func _check_quests(prefix := "") -> void:
	var q := world.quests
	var done: Array = q.advance()
	var reached: Array = q.check_milestones()
	var guide_full: bool = q.take_guide_complete()
	if done.is_empty() and reached.is_empty() and not guide_full:
		return
	world.save_game()
	var lines := PackedStringArray()
	if prefix == "" and $HUD.is_message_visible():
		prefix = $HUD._message  # 今日の発見など、出ている知らせは消さずに前に残す
	if prefix != "":
		lines.append(prefix)
	if done.has("complete"):
		lines.append("愛の空間が完成した。これからは、生き物の図鑑をそろえ、木の節目を迎えていこう")
	elif not done.is_empty():
		var names := PackedStringArray()
		for id in done:
			names.append(quest_text(id).name)
		var left := PackedStringArray()
		for id in q.remaining():
			left.append(quest_text(id).short)
		lines.append("達成: %s(%d/%d。残り: %s)" % ["・".join(names), q.done.size(), q.QUESTS.size(), "・".join(left)])
	for m in reached:
		lines.append(milestone_text(m))
	if guide_full:
		lines.append("生き物の図鑑がそろった(%d種類)" % q.guide_ids().size())
	$HUD.show_message("
".join(lines), 12.0 if done.has("complete") else 8.0)

# 「家族の杉が樹齢10年になった」のような、木の節目の文言
func milestone_text(m: Dictionary) -> String:
	return "木の節目: いちばん年上の%sが樹齢%d年になった" % [world.forest.SPECIES[m.species].name, m.age]

# HUD に出すクエストの 1 行
func quest_line() -> String:
	var q := world.quests
	if q.is_complete():
		return "愛の空間: 図鑑 %d/%d・木の節目 %d/%d%s" % [q.guide_seen().size(), q.guide_ids().size(), q.milestones.size(), q.milestone_total(), _next_goal_text()]
	# まだのうち、いちばん前のものを詳しく。ほかは名前だけ
	var id: String = q.current_id()
	var t: Dictionary = quest_text(id)
	var p: Array = q.progress(id)
	var count := ""
	if t.unit != "":
		count = " %d/%d%s" % [p[0], p[1], t.unit]
	var others := PackedStringArray()
	for other in q.remaining():
		if other != id:
			others.append(quest_text(other).short)
	var rest := "・ほかに %s" % "・".join(others) if not others.is_empty() else ""
	return "クエスト %d/%d 済: %s%s(%s)%s" % [q.done.size(), q.QUESTS.size(), t.name, count, t.hint, rest]

# 完成のあとの次の目標: まだ見ていない生き物 1 つと、次の木の節目
func _next_goal_text() -> String:
	var q := world.quests
	var missing: Array = q.guide_missing()
	if not missing.is_empty():
		return "(次: %s・%s)" % [_creature_name(missing[0]), local_text(Msg.GUIDE_HINTS[missing[0]])]
	var m: Dictionary = q.next_milestone()
	if not m.is_empty():
		return "(次の節目: %s 樹齢%d年まで あと%d日)" % [world.forest.SPECIES[m.species].name, m.age, m.days]
	return ""

func _creature_name(id: String) -> String:
	if world.wildlife.SPECIES.has(id):
		return world.wildlife.SPECIES[id].name
	return world.pond.CREATURES[id].name

# 持ち物に出す、木の節目(樹種ごとに迎えた樹齢)。例: 「白樺 10・25年 / シベリア杉 10年」
func milestones_line() -> String:
	var q := world.quests
	var parts := PackedStringArray()
	for sp in world.forest.SPECIES:
		var ages := PackedStringArray()
		for age in q.MILESTONE_AGES:
			if "%s:%d" % [sp, age] in q.milestones:
				ages.append(str(age))
		if not ages.is_empty():
			parts.append("%s %s年" % [world.forest.SPECIES[sp].name, "・".join(ages)])
	return "%d/%d  %s" % [q.milestones.size(), q.milestone_total(), " / ".join(parts)] if not parts.is_empty() else "まだない"

func _harvest() -> void:
	var g := world.garden
	var pos := player_pos()
	# 足元の区画の野菜を先に。収穫できなければ、近くのリンゴを見る
	var c: Dictionary = g.crop_at(pos)
	var crop: String = g.harvest_at(pos)
	if crop == "harvested":
		var kind: String = c.kind
		_act("pick", c.pos, kind)
		var spoiled := "傷んでいて半分だけ。" if g.last_harvest_spoiled else ""
		if g.last_weed_loss > 0:
			spoiled += "雑草で -%d%%。" % g.last_weed_loss
		if g.last_bitten:
			spoiled += "かじられていた。"
		if g.last_straw > 0:
			spoiled += "わら +%d束。" % g.last_straw
		if g.last_meal_extra > 0:
			spoiled += "漬物で +%dkg。" % g.last_meal_extra
		var text := "%sを%dkg収穫した(%s市場で1kg %d₽で売れる)" % [g.CROPS[kind].name, g.last_harvest_kg, spoiled, world.market.SELL_PRICES[kind]]
		$HUD.show_message(text + family_talk._family_harvest(c.pos, pos))
		return
	if crop == "preview":
		$HUD.show_message(Msg.HARVEST_MESSAGES.preview)
		return
	# 育っている区画に雑草が生えていれば抜く
	if crop == "growing" and g.weed_at(pos) == "weeded":
		_act("pull", c.pos)
		var lost := "。ここまでで収量 -%d%%" % roundi(g.weed_loss(c) * 100.0) if g.weed_loss(c) > 0.0 else ""
		var tip := "" if g.straw > 0 else "。わらを敷くと生えない(穀物の収穫か市場で)"
		$HUD.show_message("%sの区画の雑草を抜いた%s。%d日たつとまた生える%s" % [g.CROPS[c.kind].name, lost, g.WEED_FREE_DAYS, tip], 5.0)
		return
	# 足元 2m 以内の果樹を収穫する
	var result: String = world.forest.harvest_nearest(pos, REACH)
	if crop == "growing" and result != "harvested":
		# 果樹がなければ、わらを敷く
		if g.mulch_at(pos) == "mulched":
			_act("plant", c.pos)
			$HUD.show_message("%sの区画にわらを敷いた(残り %d束)。収穫まで雑草が生えない" % [g.CROPS[c.kind].name, g.straw])
			return
		$HUD.show_message("%sはまだ育っている(あと%d日)" % [g.CROPS[c.kind].name, g.days_left(c)])
		return
	if result == "harvested":
		_act("pick_high", world.forest.trees[world.forest.nearest_fruit_index(pos, REACH)].pos, world.forest.last_harvest_item)
	if result == "done":
		$HUD.show_message(Msg.HARVEST_MESSAGES.done % world.forest.last_harvest_wait)
		return
	$HUD.show_message(Msg.HARVEST_MESSAGES[result] if Msg.HARVEST_MESSAGES.has(result) else _fruit_message(result))

# Q: 井戸か池のそばなら、エンジンポンプでまとめて水をやるか、ジョウロに汲む。
# そうでなければ、足元の区画の野菜か 2m 以内の木に、ジョウロで水をやる(1L で 1 か所)
func _water() -> void:
	var f := world.forest
	var g := world.garden
	var t := world.tools
	var pos := player_pos()
	var source: String = world.water_source(pos)
	var pump_result := ""
	if source != "":
		pump_result = world.pump(pos)
		if pump_result == "pumped":
			var n: Array = world.last_pumped
			var place := source_name(source)
			var left := "池の水 %d%%・" % world.pond.water if source == "pond" else ""
			_act("machine", source_spot(source, pos), "pump")
			$HUD.show_message("エンジンポンプで%sの水をまいた(区画 %d・木 %d に水やり。%sガソリン -%s・残り %s)" % [place, n[0], n[1], left, gas_text(t.gas_needed("pump")), gas_text(t.gas)], 5.0)
			return
		var fill: String = world.fill_can(pos)
		if fill == "filled":
			_act("draw", source_spot(source, pos))
			var note := "。ポンプはガソリンがなくて動かない" if pump_result == "no_gas" else ""
			$HUD.show_message("%sの水をジョウロに汲んだ(%d/%dL)%s" % [source_name(source), t.can_water, t.can_size(), note])
			return
		if Msg.FILL_MESSAGES.has(fill) and g.crop_at(pos).is_empty() and f.nearest_index(pos, REACH, "") < 0:
			$HUD.show_message(Msg.PUMP_MESSAGES.get(pump_result, Msg.FILL_MESSAGES[fill]))
			return
	# 足元の区画の野菜を先に。今日もう水をあげていれば、近くの木を見る
	var crop: String = world.water_plot(pos)
	if crop == "watered":
		_act("water", g.crop_at(pos).pos)
		$HUD.show_message("%sに水をあげた(ジョウロ 残り %d/%dL。水をやった日は1日ぶん、やらない日は半日ぶん育つ)" % [g.CROPS[g.crop_at(pos).kind].name, t.can_water, t.can_size()])
		return
	if crop == "can_empty":
		$HUD.show_message(can_empty_text(), 5.0)
		return
	# 足元 2m 以内の木に水をあげる
	var result: String = world.water_tree(pos, REACH)
	if crop != "none" and result != "watered":
		$HUD.show_message("もう収穫できる(E)" if crop == "ripe" else "この区画には今日もう水をあげた")
		return
	if result == "can_empty":
		$HUD.show_message(can_empty_text(), 5.0)
		return
	# 足元に何もない井戸か池のそば: なぜ何もしなかったかを知らせる
	if result == "none" and source != "":
		if pump_result == "nothing" or (pump_result == "no_pump" and t.can_full()):
			$HUD.show_message("まわりに水のいる木や区画がない(ジョウロは満杯 %dL)" % t.can_size() if t.can_full() else "まわりに水のいる木や区画がない")
			return
		if pump_result == "no_gas":
			$HUD.show_message("エンジンポンプのガソリンがない(市場で買える)。ジョウロは満杯(%dL)" % t.can_size())
			return
		if Msg.PUMP_MESSAGES.has(pump_result):
			$HUD.show_message(Msg.PUMP_MESSAGES[pump_result])
			return
	var msg: String = Msg.WATER_MESSAGES[result]
	if result == "watered":
		var i: int = f.nearest_index(pos, REACH, "")
		msg = msg % [f.SPECIES[f.trees[i].species].name, f.WATER_BONUS_YEARS, t.can_water, t.can_size()]
		_act("water", f.trees[i].pos)
	$HUD.show_message(msg)

# ジョウロが空のときの文言(汲める場所を添える)
func can_empty_text() -> String:
	var where := "井戸か池" if world.well.is_dug() and world.pond.is_dug() else ("井戸" if world.well.is_dug() else ("池" if world.pond.is_dug() else ""))
	if world.river.exists():
		where = "川" if where == "" else where + "か川"
	if where == "":
		return "ジョウロが空(I で井戸を掘ると汲める。雨の日は畑にも木にも降る)"
	return "ジョウロが空(%sのそばで Q を押して汲む)" % where

# ガソリンの量の文言(0.1L 単位の整数 → 「4.5L」)
func gas_text(n: int) -> String:
	return "%.1fL" % (n / 10.0)

# 直前に伐った道具の文言
func cutter_text() -> String:
	var t := world.tools
	if t.last_machine == "chainsaw":
		return "チェーンソー。ガソリン -%s・残り %s" % [gas_text(t.gas_needed("chainsaw")), gas_text(t.gas)]
	return "斧。今日あと%d本" % t.axe_left()

# I: 井戸の場所を決める / 掘る
func _well_action() -> void:
	var front: Vector2 = player_pos() + $Player.facing() * HIVE_FRONT if $Player.has_method("facing") else player_pos()
	var result: String = world.well_action(player_pos(), front)
	var msg: String = Msg.WELL_MESSAGES[result]
	if result == "placed":
		msg = msg % world.well.DIG_DAYS
	$HUD.show_message(msg, 5.0)
	if result == "dug" or result == "finished":
		_act("dig", world.well.site)

# O: 石臼を置く / 挽く。選んでいる野菜が穀物なら、それを先に挽く
func _mill_action() -> void:
	var m := world.mill
	var front: Vector2 = player_pos() + $Player.facing() * HIVE_FRONT if $Player.has_method("facing") else player_pos()
	var result: String = world.mill_action(player_pos(), front, selected_crop)
	match result:
		"ground":
			var g: String = m.last_ground.keys()[0]
			_act("grind", m.site)
			var helper: String = $Family.mill_helper() if has_node("Family") else ""
			var together := ""
			if helper != "":
				$Family.play_action(helper, "grind", m.site)
				together = "。%sと 2 人で回している" % world.family.member(helper).name
			$HUD.show_message("%sを%dkg挽いた(%s %dkg。手で今日あと%dkg%s)" % [world.garden.CROPS[g].name, int(m.last_ground[g]), m.FLOURS[g].name, int(m.flour[g]), m.hand_left(), together])
		"engine":
			var parts := PackedStringArray()
			for g in m.last_ground:
				parts.append("%s %dkg" % [m.FLOURS[g].name, int(m.last_ground[g])])
			_act("machine", m.site, "mill")
			$HUD.show_message("製粉機で挽いた(%s。ガソリン -%s・残り %s)" % ["・".join(parts), gas_text(world.tools.gas_needed("mill")), gas_text(world.tools.gas)], 5.0)
		"placed":
			_act("build", m.site)
			$HUD.show_message(Msg.MILL_MESSAGES.placed, 5.0)
		"tired":
			$HUD.show_message(Msg.MILL_MESSAGES.tired % m.hand_limit(), 5.0)
		_:
			$HUD.show_message(Msg.MILL_MESSAGES[result], 5.0)

# HUD に出す、石臼のそばでの案内。そばにいなければ ""
func mill_line() -> String:
	var m := world.mill
	if not m.is_near(player_pos()):
		return ""
	if m.total_grain() <= 0:
		return "石臼のそば: 挽く穀物がない"
	var how := "製粉機で全部挽く(ガソリン -%s)" % gas_text(world.tools.gas_needed("mill")) if world.tools.can_run("mill") else "1kg挽く(手で今日あと%dkg)" % m.hand_left()
	return "石臼のそば: O で%s  穀物 %dkg" % [how, m.total_grain()]

# HUD に出す、井戸の 1 行(掘っているあいだだけ)
func well_line() -> String:
	var w := world.well
	if not w.is_placed() or w.is_dug():
		return ""
	return "井戸: 掘っている %d/%d日(%s)" % [w.days_dug, w.DIG_DAYS, "今日は済んだ" if w.dug_today() else "I で掘る"]

# HUD に出す、道具の 1 行。例: 「ジョウロ 3/5L  ガソリン 4.5L  斧: 今日あと2本」
func tools_line() -> String:
	var t := world.tools
	var parts := PackedStringArray(["ジョウロ %d/%dL" % [t.can_water, t.can_size()]])
	if t.has_machine() or t.gas > 0:
		parts.append("ガソリン %s" % gas_text(t.gas))
	if t.axe_left() < t.AXE_PER_DAY:
		parts.append("斧: 今日あと%d本" % t.axe_left())
	return "道具: " + "  ".join(parts)

# 持ち物の道具の並び。例: 「5Lのジョウロ・斧・エンジンポンプ」
func tools_owned_text() -> String:
	var t := world.tools
	var names := PackedStringArray(["%dLのジョウロ" % t.can_size(), "斧"])
	for m in t.MACHINES:
		if t.has(m):
			names.append(MACHINE_NAMES[m])
	var straw := "  わら %d束" % world.garden.straw if world.garden.straw > 0 else ""
	return "・".join(names) + "  ガソリン %s(%sまで)" % [gas_text(t.gas), gas_text(t.MAX_GAS)] + straw

# 足元の野菜を抜く。なければ 2m 以内の木を伐る(育った木は丸太になる。種は戻らない。
# 達成済みのクエストは戻らない)。木もなければ、作業を始める前の小屋・池の場所を取り消す
func _remove() -> void:
	var g := world.garden
	var pos := player_pos()
	var c: Dictionary = g.crop_at(pos)
	if g.remove_at(pos):
		_act("pull", c.pos)
		$HUD.show_message("%sを抜いた(種は戻らない)" % g.CROPS[c.kind].name)
		return
	if _needs_fell_confirm(pos):
		return
	# 消える前に、倒れる形を作る(幹のある木だけ。苗木や種は抜く動き)
	var nearest: int = world.forest.nearest_index(pos, REACH, "")
	var felled: Dictionary = world.forest.trees[nearest] if nearest >= 0 else {}
	if world.axe_tired_for(pos, REACH):
		var saw := "(チェーンソーはガソリンがなくて動かない)" if world.tools.has("chainsaw") else "(チェーンソーなら何本でも伐れる。市場で買える)"
		$HUD.show_message("今日はもう斧で%d本伐って、腕が上がらない。続きは明日%s" % [world.tools.AXE_PER_DAY, saw], 5.0)
		return
	var falls: bool = not felled.is_empty() and $Trees.has_method("start_fall") and $Trees.start_fall(felled, pos)
	var had_box: bool = not felled.is_empty() and not world.nest_boxes.box_on(felled.pos).is_empty()
	var logs: int = world.fell(pos, REACH)
	world.nest_boxes.drop_missing()  # 伐った木に掛けていた巣箱もなくなる
	var sawed: bool = world.tools.last_machine == "chainsaw"
	if not felled.is_empty():
		_act(("saw" if sawed else "chop") if falls else "pull", felled.pos)
	if falls and $Audio.has_method("play_after"):
		$Audio.play_after("tree_fall", TREE_FALL_SOUND_DELAY)
	if logs > 0:
		$HUD.show_message("木を伐った(丸太 +%d本・%s)%s" % [logs, cutter_text(), "。掛けていたムクドリの巣箱も外れた" if had_box else ""])
	elif logs == 0:
		$HUD.show_message("木を抜いた(細くて丸太にはならない)")
	elif world.cabin.cancel(pos):
		$HUD.show_message("小屋の場所を取り消した")
	elif world.well.cancel(pos):
		$HUD.show_message("井戸の場所を取り消した")
	elif world.pond.cancel(pos):
		$HUD.show_message("池の場所を取り消した")

# 根付いた木を間違えて伐らないように、1 回目は確認の文言だけ出す。確認を出したら true
func _needs_fell_confirm(pos: Vector2) -> bool:
	var f := world.forest
	var i: int = f.nearest_index(pos, REACH, "")
	if i < 0 or not f.is_established(f.trees[i]):
		return false
	var tree: Dictionary = f.trees[i]
	var now: float = Time.get_ticks_msec() / 1000.0
	if is_same(tree, _fell_pending) and now <= _fell_deadline:
		_fell_pending = {}
		return false
	_fell_pending = tree
	_fell_deadline = now + FELL_CONFIRM_SECONDS
	var logs: int = f.wood_yield(tree)
	var wood := "丸太%d本" % logs if logs > 0 else "細くて丸太にはならない"
	$HUD.show_message("もう一度 Z で伐る: %s 樹齢%d年(%s)" % [f.SPECIES[tree.species].name, int(f.real_age_years(tree)), wood], FELL_CONFIRM_SECONDS)
	return true

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if $HUD.is_picker_open():
		return  # 選ぶのは画面のボタン(矢印キー + Enter でも選べる)
	if $HUD.is_diary_open():
		if event.keycode == KEY_H or event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER:
			kitchen_panel._wake()
		return
	if $HUD.is_shop_open():
		# 開いているあいだは閉じるキーだけ(選ぶのは画面のボタン)。市場は B、ストーブは H、訪問者は C でも閉じる
		var close_key: int = {"kitchen": KEY_H, "table": KEY_H, "chair": KEY_H, "visitor": KEY_C, "family": KEY_C}.get(_panel, KEY_B)
		if event.keycode == close_key or event.keycode == KEY_ESCAPE:
			_close_shop()
		return
	if CROP_KEYS.has(event.keycode):
		_select_next_crop(CROP_KEYS[event.keycode])
		return
	match event.keycode:
		KEY_TAB:
			$HUD.inventory_open = not $HUD.inventory_open
		KEY_F1:
			$HUD.help_open = not $HUD.help_open
		KEY_1:
			_select_next_in("broadleaf")
		KEY_2:
			_select_next_fruit()
		KEY_3:
			_select_next_in("conifer")
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
		KEY_C:
			_talk()
		KEY_K:
			world.guide.dismiss()
		KEY_J:
			_bee_action()
		KEY_U:
			if not world.snow.can_clear_now():
				$HUD.show_message("雪かきは冬にする")
		KEY_L:
			_feeder_action()
		KEY_X:
			_prune()
		KEY_M:
			_next_sound_level()
		KEY_F:
			_toggle_plot()
		KEY_P:
			_pond_action()
		KEY_I:
			_well_action()
		KEY_O:
			_mill_action()
		KEY_Y:
			family_talk._open_family_names()
		KEY_T:
			world.forest.advance_years(1.0)   # 1年先送り(プレビュー。保存しない)
		KEY_G:
			world.forest.advance_years(10.0)  # 10年先送り
		KEY_N:
			world.clock.advance_preview()     # 1時間先送り(光のプレビュー。ルールには効かない)
		KEY_R:
			world.forest.reset_preview()      # 今日に戻す
			world.clock.reset_preview()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		world.save_game()

# HUD などが Main から呼ぶので残す(中身は family_talk)
func family_line() -> String:
	return family_talk.family_line()

# HUD などが Main から呼ぶので残す(中身は kitchen_panel)
func kitchen_line() -> String:
	return kitchen_panel.kitchen_line()

# HUD などが Main から呼ぶので残す(中身は kitchen_panel)
func meal_line() -> String:
	return kitchen_panel.meal_line()

# HUD などが Main から呼ぶので残す(中身は visitor_talk)
func neighbors_line() -> String:
	return visitor_talk.neighbors_line()
