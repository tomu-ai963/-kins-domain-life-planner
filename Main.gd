extends Node

# ── つなぎ役: 入力 → ロジック(logic/) → 文言(HUD) ─────────────────
# ゲームの状態とルールは logic/GameWorld.gd 以下、見た目は view/3d/(Main.tscn)か view/2d/(Main2D.tscn)。
# Main はキー入力をロジックに渡し、結果コードを文言にして HUD に出す。
# Main・HUD は 2D と 3D で共通。位置は Player.ground_pos() で m の Vector2(x, y)を受け取る
const GameWorld = preload("res://logic/GameWorld.gd")
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

# ヒント(logic/Guide.gd の id)の文言。実際のルールに合わせて書く
const GUIDE_TEXTS := {
	"walk": "WASD か矢印キーで歩ける。\nホイールでカメラを寄せたり引いたりできる。",
	"plant": "SPACE で足元に木を植える。\n[1][2][3] で木を選び、[V] で種と苗木を切り替える。",
	"plot": "F で足元に畑の区画を作れる。お金はいらない。\n手で耕すので、新しく作れるのは1日2区画まで。",
	"buy_seeds": "野菜の種は市場で買える。\n市場は南の境界の外にある(前に立って B で開く)。",
	"sow": "区画の上で SPACE を押すと種をまく。\n[4]〜[9] で野菜を選ぶ。まける季節は野菜ごとに違う。",
	"water": "野菜の上で Q を押すと水をやれる。\n水をやった日は1日ぶん、やらない日は半日ぶん育つ。",
	"harvest": "育った野菜は E で収穫する。\n放っておくと傷んで、収穫が半分になる。",
	"sell": "収穫物は市場で売れる。\n市場は南の境界の外(前に立って B で開く)。",
	"broke": "お金と種が足りないときは、畑の野菜を収穫して市場で売ろう。\n訪ねてくる人の頼みごとでも、お金や種がもらえる。",
	"stuck": "お金も種も、売るものもなくなったら、訪ねてくる人に話そう。\n2〜3日に1人来て、種を少し分けてくれる。",
	"apple": "果樹に実がなっている(季節と樹齢で実る)。\n木のそばで E を押すと収穫できる。",
	"visitor": "訪ねてくる人がいる。そばで C を押すと話せる。\n頼みごとは断ってもいい。",
	"pond_rain": "池の水は雨でたまる。\n半分を超えると、生き物が来るようになる。",
	"pond_water": "池のそばで Q を押すと、まわりの畑と木にまとめて水をやれる。\n池の水は少し減る。",
	"cabin_site": "H で足元を小屋の場所に決められる。\n丸太を集めて、1日1回ずつ建てていく。",
	"cabin_logs": "小屋の丸太は、市場で買う(5本 1,500₽)か、\n育った木を Z で伐って集める(白樺は樹齢15年から)。",
	"cabin_inside": "小屋が建った。南のドアから中に入れる。\n窓辺で苗づくり、ストーブで料理、ベッドで日記。",
	"split": "小屋の東の薪割り台で H を押すと、丸太を割れる。\n料理には薪がいる。丸太1本で10回分。",
	"stove": "ストーブの前で H を押すと、収穫物を保存食にできる。\n生より高く、冬と春はもっと高く売れる。薪を1回分使う。",
	"bed": "ベッドのそばで H を押すと、横になって日記を見る。\n明日の予定が分かる。寝ても時間は進まない。",
	"table": "腰掛けのそばで H を押すと、座って保存食を食べられる。\n食べた日は少し速く歩ける。同じものは1日1つまで。",
	"hive_make": "自分の木を伐った丸太で、巣箱を作れる(J・丸太2本)。\n3日かけてくり抜く。市場の丸太は使えない。",
	"hive_bees": "巣箱に蜂が入るのを待とう(春と夏)。\nフョードルさんが来たら、分けてもらうこともできる。",
	"honey": "はちみつが採れる。巣箱のそばで J を押す。\n市場で売れて、ストーブで料理にも使える。採っても蜂はいなくならない。",
	"winter": "冬は地面が凍って、苗木を植えられない(白樺の種だけはまける)。\n小屋の窓辺なら、冬でも苗が育つ。",
	"shovel": "U を押したまま歩くと、雪をどかせる。\nどかした道は速く歩ける。次の雪で埋まる。",
	"prune": "冬は果樹のそばで X を押すと剪定できる。\n次の収穫が増えて、切った枝は薪になる。",
	"feeder": "L を押すと、丸太1本で鳥の餌台を立てられる。\n秋と冬に白樺の種を置くと、鳥が集まる。",
	"feed": "餌台のそばで L を押すと、白樺の種を3粒置ける。\n餌は翌日まで残る。近づきすぎると鳥は逃げる。",
	"creatures": "見かけた生き物は、Tab の持ち物で見られる。\n木や畑が増えると、来る生き物も増える。",
}

const SEASON_NAMES := {"spring": "春", "summer": "夏", "autumn": "秋", "winter": "冬"}
const FORM_NAMES := {"seed": "種", "sapling": "苗木"}

var world := GameWorld.new()
var selected_species := "birch"
var selected_form := "seed"   # V で種 ⇄ 苗木
var selected_crop := "radish" # 4〜8 で選ぶ。区画の上で SPACE を押すとまく

# 市場のページ。買う列は品の種類(Market.GOODS の form)で、売る列は収穫物と保存食で分ける
const BUY_PAGES := [
	{"name": "木の種と苗木", "forms": ["seed", "sapling"]},
	{"name": "野菜の種", "forms": ["crop_seed"]},
	{"name": "丸太", "forms": ["material"]},
]
const SELL_PAGES := ["収穫物", "保存食"]

# 野菜を選ぶキー(HUD の並びもこの順)
const CROP_KEYS := {KEY_4: "radish", KEY_5: "carrot", KEY_6: "cucumber", KEY_7: "potato", KEY_8: "garlic", KEY_9: "tomato"}

var _season_timer := 0.0
var _fell_pending := {}      # Z を 1 回押して確認中の木(Forest.trees の要素)
var _fell_deadline := 0.0    # いつまでにもう一度押せば伐れるか(秒)
var _panel := "market"       # 右の画面に出しているもの: market(市場) / kitchen(ストーブ)
var _wildlife_timer := 0.0
var _guide_timer := 0.0
var _shovel_wait := 0.0
var _buy_page := 0           # 市場の買う列の今のページ(閉じても覚えておく)
var _sell_page := 0          # 市場の売る列の今のページ

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
	$Player.plant_tree.connect(_on_plant_tree)
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
	$Cabin.set_kitchen(world.kitchen)
	$Wildlife.setup(world.wildlife, $Player)
	$Visitor.setup(world.visitors, $Player)
	$Hives.setup(world.bees)
	$Feeders.setup(world.feeders)
	$SnowPath.setup(world.snow)
	world.guide.has_people = true
	$Audio.setup(world, $Player)
	$Player.work_sound.connect($Audio.play)

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
	var shoveling: bool = holding and s.can_clear_now() and not $HUD.is_shop_open() and not $HUD.is_diary_open() and not world.cabin.covers(pos)
	_shovel_wait -= delta
	if shoveling and _shovel_wait <= 0.0 and s.clear_at(pos) == "cleared":
		_shovel_wait = SHOVEL_GAP
		_act("shovel")
	var speed := 1.0
	if shoveling:
		speed = s.SHOVEL_SPEED
	elif s.is_cleared(pos):
		speed = s.PATH_SPEED
	if world.kitchen.ate_today():
		speed *= world.kitchen.MEAL_SPEED
	$Player.speed_scale = speed

func _check_new_day() -> void:
	var f := world.forest
	var id: String = world.check_new_day()
	if id == "":
		return
	var lines := ["今日の発見: " + daily_message(id)]
	if not f.pickups.is_empty():
		lines.append("育った木の根元に種が落ちている(%dか所)" % f.pickups.size())
	for sp in f.last_failed:
		lines.append("%sの種 %d粒は芽が出なかった" % [f.SPECIES[sp].name, f.last_failed[sp]])
	var g := world.garden
	for kind in g.last_frost:
		lines.append("霜で%sが枯れた(%d区画)" % [g.CROPS[kind].name, g.last_frost[kind]])
	if g.frost_is_near(f.today()):
		lines.append("もうすぐ霜が降りる(12月)。ニンニク以外の野菜は枯れるので、早めに収穫を")
	if has_node("Visitor") and world.visitors.is_here():
		lines.append("%sが訪ねてきた(C で話す)" % world.visitors.CAST[world.visitors.who()].name)
	var pond := world.pond
	if pond.last_gain > 0:
		lines.append("%sで池に水がたまった(%d%%)" % ["雪" if f.season == "winter" else "雨", pond.water])
	for c in pond.last_arrivals:
		lines.append("池に%sが来た" % pond.CREATURES[c].name)
	if world.bees.last_arrivals > 0:
		lines.append("空の巣箱に蜂が入った(%d箱)" % world.bees.last_arrivals)
	if world.snow.last_fell:
		lines.append("雪かきの道が雪で埋まった")
	$HUD.show_message("\n".join(PackedStringArray(lines)), 10.0)

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
	var front = pos + $Player.facing() * HIVE_FRONT if $Player.has_method("facing") else null
	match fd.act(pos, front):
		"placed":
			_act("build", fd.last_fed.pos)
			$HUD.show_message("鳥の餌台を立てた(丸太 -%d本)。L で白樺の種を%d粒置くと鳥が来る(秋と冬)" % [fd.LOG_COST, fd.FEED_SEEDS], 6.0)
		"fed":
			_act("feed", fd.last_fed.pos)
			$HUD.show_message("餌台に白樺の種を置いた(-%d粒)。少し離れて待つと鳥が来る(餌は翌日まで残る)" % fd.FEED_SEEDS, 6.0)
		"full":
			$HUD.show_message("今日はもう餌を置いた(翌日まで残る)")
		"not_season":
			$HUD.show_message("餌を置くのは秋と冬(ほかの季節は、鳥は自分で餌を見つけられる)", 5.0)
		"no_seed":
			$HUD.show_message("白樺の種が%d粒いる(今 %d粒。白樺の根元に落ちるのを拾うか、市場で買える)" % [fd.FEED_SEEDS, world.forest.seeds.birch], 5.0)
		"no_wood":
			$HUD.show_message("丸太が%d本いる(市場で買うか、育った木を Z で伐る)" % fd.LOG_COST)
		"too_many":
			$HUD.show_message("餌台は%dつまで(種を置くときは、餌台のそばで L)" % fd.MAX_FEEDERS, 5.0)
		"blocked":
			$HUD.show_message("ここには立てられない(区画・小屋・池・木・巣箱のそばや、土地の端は空ける)", 5.0)

# HUD に出す、餌台のそばの 1 行。そばにいなければ ""
func feeder_line() -> String:
	var fd := world.feeders
	var near: Dictionary = fd.feeder_near(player_pos())
	if near.is_empty():
		return ""
	if not fd.can_feed_now():
		return "餌台(餌を置くのは秋と冬)"
	if fd.fed_today(near):
		return "餌台: 今日は餌を置いた"
	if fd.is_fed(near):
		return "餌台: 餌が残っている(L で足す・白樺の種 %d粒)" % fd.FEED_SEEDS
	return "餌台: 餌がない(L で白樺の種を %d粒置く)" % fd.FEED_SEEDS

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
	return GUIDE_TEXTS[id] if id != "" else ""

# ── 訪ねてくる人(3D だけ) ──────────────────────────────────────
# 話すだけの日の言葉。{tomorrow} は明日の空模様に置き換える
const VISITOR_CHATS := {
	"nina": [
		"区画はお金がいらないけど、耕すのは1日2区画まで。\n欲張らず少しずつね。",
		"水をやった日は1日ぶん、やらない日は半日ぶん育つよ。\n毎日見てあげて。",
		"冬が来る前に、ニンニク以外は収穫しておくんだよ。\n霜は待ってくれないからね。",
	],
	"fyodor": [
		"自分の木で丸太の巣箱を作るといい。\nくり抜いてあれば、蜂を分けてあげるよ。",
		"ミツバチは野菜の花が好きでね。\n畑が増えると、うちの蜂も喜ぶよ。",
		"木が増えると小鳥が来る。\n育った木にはリスも来るさ。",
		"丸太は育った木を伐れば手に入る。\n市場で買うと高いからね。",
	],
	"tanya": [
		"夜に畑へ行くと、ノウサギがいるんだよ!\nそっと近づいてもすぐ逃げちゃうけど。",
		"ハリネズミは逃げないの。\nじっとしてるんだよ。",
		"渡り鳥を見た?\n近づくと、みんなで飛んでっちゃうんだ。",
	],
	"pavel": [
		"{tomorrow}",
		"この先の家まで配達です。\nまた寄りますね。",
		"小屋の窓辺なら、冬でも苗が育つそうですね。\n春が楽しみだ。",
	],
}
const VISITOR_REQUESTS := {
	"nina": "%sを%s分けてもらえない?\nお礼に%sをあげる。",
	"fyodor": "%sを%s譲ってくれないか。\nお礼に%sを持ってきたんだ。",
	"tanya": "%sを%sちょうだい!\nかわりに%sをあげるね。",
	"pavel": "%sを%s分けていただけませんか。\nお礼に%sをお渡しします。",
}
# 手詰まりのときに分けてくれる言葉(種のとき / 冬のお金のとき)
const VISITOR_HELP := {
	"nina": ["畑が空っぽじゃない。困ってるんでしょう。\n%sを持っていって。まけばまた始められるよ。", "冬は苦しいよね。\n%sあげるから、春になったら種を買いなさい。"],
	"fyodor": ["手元が寂しそうだな。\n%sを分けよう。また育てればいい。", "冬は誰でも苦しいものさ。\n%sを持っていくといい。春に種を買うんだ。"],
	"tanya": ["畑、なんにもないね。\nお母さんが%sを持っていけって!", "雪だと畑はお休みだよね。\nお母さんが%sを持っていけって!"],
	"pavel": ["差し出がましいですが、お困りのようで。\n%sをどうぞ。村のみんなからです。", "冬の間は大変でしょう。\n%sをどうぞ。村のみんなからです。"],
}
# フョードルさんが蜂を分けてくれるときの言葉
const VISITOR_BEES := "いい巣箱ができたじゃないか。\nうちの蜂を一群れ分けよう。入れておくよ。"
const VISITOR_THANKS := {
	"nina": "ありがとう、助かったよ。",
	"fyodor": "ありがたい。また来るよ。",
	"tanya": "やったあ!ありがとう!",
	"pavel": "助かりました。では、配達に戻ります。",
}

# 「ラディッシュの種 6つ」「トマトの苗 1鉢」「260₽」
func reward_text(r: Dictionary) -> String:
	match r.type:
		"crop_seed":
			return "%s %dつ" % [world.garden.CROPS[r.kind].seed_name, r.count]
		"seedling":
			return "%sの苗 %d鉢" % [world.garden.CROPS[r.kind].name, r.count]
	return "%s₽" % $HUD._money_text(int(r.amount))

# 訪問者の言葉
func visitor_text() -> String:
	var v := world.visitors
	var who: String = v.who()
	if v.has_bees():
		return VISITOR_BEES
	if v.has_help():
		var winter: bool = v.visit.reward.type == "money"
		return VISITOR_HELP[who][1 if winter else 0] % reward_text(v.visit.reward)
	if v.has_request():
		var item: String = v.visit.item
		return VISITOR_REQUESTS[who] % [produce_name(item), "%d%s" % [v.visit.amount, produce_unit(item)], reward_text(v.visit.reward)]
	var lines: Array = VISITOR_CHATS[who]
	var line: String = lines[int(v.visit.line) % lines.size()]
	if line == "{tomorrow}":
		var rainy: bool = world.tomorrow_rain()
		return "明日は降りそうですよ。\n水やりは休めますね。" if rainy else "明日は降らなそうです。\n畑の水やりを忘れずに。"
	return line

# C: 近くの訪問者に話しかける
func _talk() -> void:
	if not has_node("Visitor") or not world.visitors.is_here():
		return
	if not $Visitor.can_talk(player_pos()):
		$HUD.show_message(visitor_line())
		return
	world.visitors.check_today()  # 今日のうちに手詰まりになっていたら、助けてくれる
	$Visitor.greet()
	_sfx("open")
	_panel = "visitor"
	$Player.set_physics_process(false)
	$HUD.open_shop()

func visitor_rows() -> Array:
	var v := world.visitors
	var rows := []
	if v.has_bees():
		rows.append({"id": "receive_bees", "text": "ありがとう(巣箱に入れてもらう)", "column": 0})
		rows.append({"id": "close", "text": "今はいい(C / Esc)", "column": 0})
	elif v.has_help():
		rows.append({"id": "receive", "text": "ありがとう(%sをもらう)" % reward_text(v.visit.reward), "column": 0})
		rows.append({"id": "close", "text": "今はいい(C / Esc)", "column": 0})
	elif v.has_request():
		var item: String = v.visit.item
		var have: int = world.market.count_of(item)
		rows.append({"id": "give", "text": "渡す(%s 持っている)" % _amount_text(item, have), "column": 0})
		rows.append({"id": "close", "text": "今はいい(C / Esc)", "column": 0})
	else:
		rows.append({"id": "chat_end", "text": "またね(C / Esc)", "column": 0})
	return rows

func _visitor_action(id: String) -> void:
	var v := world.visitors
	var who: String = v.who()
	if id == "chat_end":
		_close_shop()
		return
	if id == "receive_bees":
		if v.receive_bees() == "received":
			$HUD.show_message("フョードルさんが巣箱に蜂を入れてくれた。はちみつがたまるのを待とう", 6.0)
		_close_shop()
		return
	if id == "receive":
		var person: String = v.CAST[who].name
		if v.receive_help() == "received":
			_sfx("coin")
			$HUD.show_message("%sから%sをもらった" % [person, reward_text(v.last_reward)], 6.0)
			_close_shop()
			_act("pick", $Visitor.ground_pos(), "radish")
		return
	var item: String = v.visit.item
	if v.give() == "given":
		_sfx("coin")
		$HUD.show_message("%s(%sをもらった)" % [VISITOR_THANKS[who], reward_text(v.last_reward)], 6.0)
		_close_shop()
		_act("pick", $Visitor.ground_pos(), item)
		return
	var need: int = int(v.visit.amount) - world.market.count_of(item)
	var ripe := "。畑に収穫できるものがある" if world.garden.crops.any(func(c): return c.kind == item and world.garden.is_ripe(c)) else ""
	$HUD.show_message("%sがあと%d%s足りない%s" % [produce_name(item), need, produce_unit(item), ripe], 5.0)

# HUD に出す、訪問者の 1 行。いなければ ""
func visitor_line() -> String:
	if not has_node("Visitor") or not world.visitors.is_here():
		return ""
	var v := world.visitors
	var person: String = v.CAST[v.who()].name
	var errand := "話がしたいらしい"
	if v.has_request():
		errand = "頼みごとがあるらしい"
	elif v.has_help():
		errand = "渡したいものがあるらしい"
	elif v.has_bees():
		errand = "蜂を分けてくれるらしい"
	if $Visitor.can_talk(player_pos()):
		return "%s(C で話す)" % person
	var to: Vector2 = $Visitor.ground_pos() - player_pos()
	return "%sが来ている・%s(%sへ%dm)" % [person, errand, compass(to), ceili(to.length())]

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
	var names := PackedStringArray()
	for id in world.wildlife.seen:
		names.append(world.wildlife.SPECIES[id].name)
	for id in world.pond.seen:
		names.append(world.pond.CREATURES[id].name)
	return _rows(names, 6) if not names.is_empty() else "まだ見ていない"

# 足元に落ちている種を拾う(歩いて近づくだけ)
func _collect_pickups() -> void:
	if $HUD.is_shop_open():
		return
	var got: Array = world.forest.collect_near(player_pos(), PICKUP_RADIUS)
	for g in got:
		$HUD.show_message("%sの種を拾った(+%d)" % [world.forest.SPECIES[g.species].name, g.amount])

# 収穫の結果コード(Forest.harvest_nearest)ごとの文言
const HARVEST_MESSAGES := {
	"none": "近くに実のなる木がない",
	"preview": "未来のプレビュー中は収穫できない",
	"done": "この木は今日もう収穫した",
}

# 果樹の収穫の文言(結果が harvested / not_season / young のとき)
func _fruit_message(result: String) -> String:
	var f := world.forest
	var item: String = f.last_harvest_item
	var fruit: Dictionary = f.FRUITS[item]
	var fruit_name: String = f.SPECIES[item].name
	match result:
		"harvested":
			var extra: String = "剪定で +%d%s。" % [f.last_harvest_extra, fruit.unit] if f.last_harvest_extra > 0 else ""
			return "%sを%d%s収穫した(%s市場で1%s %d₽で売れる)" % [fruit_name, f.last_harvest_count, fruit.unit, extra, fruit.unit, world.market.SELL_PRICES[item]]
		"not_season":
			var seasons := PackedStringArray()
			for s in fruit.seasons:
				seasons.append(SEASON_NAMES[s])
			return "%sが実るのは%s" % [fruit_name, "・".join(seasons)]
	return "%sはまだ実らない(樹齢%d年から)" % [fruit_name, int(fruit.age)]

# 水やりの結果コード(Forest.water_nearest)ごとの文言
const WATER_MESSAGES := {
	"watered": "%sに水をあげた(樹齢 +%.1f年)",
	"none": "近くに木がない",
	"done": "この木には今日もう水をあげた",
}

# 発見の文言。雨の日は冬なら雪になる(降るものは WeatherView3D と同じ。効き目は雨と同じ)
func daily_message(id: String) -> String:
	if id == "rain" and world.forest.season == "winter":
		return "雪が降った。今日は全部の木と野菜に水やり済み"
	return DAILY_MESSAGES[id]

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
	"garden": {"name": "菜園を作る", "unit": "区画", "hint": "F で3m四方の区画を置く・1日2区画まで"},
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
	"hive": "巣箱にかかる場所には作れない",
	"feeder": "餌台にかかる場所には作れない",
	"limit": "新しく耕せるのは1日%d区画まで(続きは明日)",
}
const POND_MESSAGES := {
	"placed": "ここに池を掘ることにした(P で 1日1回 掘る。掘りはじめる前なら Z で取り消せる)",
	"outside": "土地の外には掘れない",
	"cabin": "小屋にかかる場所には掘れない",
	"hive": "巣箱にかかる場所には掘れない",
	"feeder": "餌台にかかる場所には掘れない",
	"dug": "池を掘った(続きは明日)",
	"finished": "池を掘り終えた。あとは雨で水がたまる",
	"far": "池はひとつまで(今の池の近くで P を押すと掘る)",
	"already": "池はもう掘り終えた(水は雨でたまる)",
	"done_today": "今日はもう掘った(1日1回)",
}

# 池からまとめて水をやれないとき(Pond.water_around)の文言
const POND_WATER_MESSAGES := {
	"frozen": "池が凍っていて水を汲めない",
	"low": "池の水が足りない(雨でたまる)",
	"nothing": "まわりに水のいる木や区画がない",
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
	if $HUD.is_shop_open() or $HUD.is_diary_open():
		return
	# 菜園の区画の上では、木ではなく野菜をまく
	if world.land.plot_at(pos) != null:
		_sow(pos)
		return
	if world.cabin.covers(pos):
		$HUD.show_message("小屋の場所には植えられない")
		return
	if world.bees.covers(pos, world.bees.CLEARANCE):
		$HUD.show_message("巣箱の近くには植えられない")
		return
	if world.feeders.covers(pos, world.bees.CLEARANCE):
		$HUD.show_message("餌台の近くには植えられない")
		return
	if world.cabin.in_yard(pos):
		$HUD.show_message("小屋の東の庭には植えられない(薪割り台と薪を置く場所)")
		return
	if selected_form == "seed" and selected_species in world.forest.SAPLING_ONLY:
		$HUD.show_message("%sは苗木から育てる(V で苗木に切り替える。市場で買える)" % world.forest.SPECIES[selected_species].name, 5.0)
		return
	if not world.forest.can_plant(selected_species, selected_form):
		$HUD.show_message("冬は地面が凍っていて植えられない(白樺の種だけは雪の上にまける)", 5.0)
		return
	if not world.forest.add_tree(pos, selected_species, selected_form):
		$HUD.show_message("%sの%sがない(市場で買える)" % [world.forest.SPECIES[selected_species].name, FORM_NAMES[selected_form]])
		return
	_act("plant", pos)
	if selected_form == "seed":
		$HUD.show_message("種をまいた。芽が出るかは1日たつと分かる")
	_check_quests()

# 2: 押すたびに次の果樹を選ぶ。苗木からしか育てない果樹なら、苗木に切り替える
func _select_next_fruit() -> void:
	var order: Array = world.forest.FRUIT_ORDER
	var i: int = order.find(selected_species)
	selected_species = order[(i + 1) % order.size()] if i >= 0 else order[0]
	if selected_species in world.forest.SAPLING_ONLY:
		selected_form = "sapling"

# 選んでいる植えるもの(HUD 用)。例: 「白樺の種」
func selected_name() -> String:
	return world.forest.SPECIES[selected_species].name + "の" + FORM_NAMES[selected_form]

# ── 小屋 ──────────────────────────────────────────────────
# H: まだ場所がなければ足元に決める。決まっていれば今日の作業をする。
# 完成していれば、ストーブの前なら台所、ベッドのそばなら日記、ほかは苗づくり
func _cabin_action() -> void:
	var c := world.cabin
	var pos := player_pos()
	if c.site == null:
		if world.bees.hives.any(func(h): return c.rect_at(pos.round()).grow(world.bees.CLEARANCE).has_point(h.pos)):
			$HUD.show_message("巣箱にかかる場所には建てられない")
			return
		if world.feeders.feeders.any(func(f): return c.rect_at(pos.round()).grow(world.bees.CLEARANCE).has_point(f.pos)):
			$HUD.show_message("餌台にかかる場所には建てられない")
			return
		$HUD.show_message(CABIN_PLACE_MESSAGES[c.place(pos)], 5.0)
		return
	if c.is_complete():
		if c.is_at_chop_block(pos):
			_split_wood()
		elif c.is_at_stool(pos):
			_open_table()
		elif c.is_at_stove(pos):
			_open_kitchen()
		elif c.is_at_bed(pos):
			_sleep()
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
			$HUD.show_message("小屋が建った。南のドアから入れる。窓辺で苗づくり(トマト [9] か きゅうり [6] を選んで H)、ストーブで料理、ベッドで日記", 8.0)
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
	match k.split():
		"split":
			_act("chop", world.cabin.chop_pos())
			$HUD.show_message("薪を割った(薪 %d回分)" % k.firewood)
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
			$HUD.show_message("%sの種を鉢にまいた(%d/%d鉢。毎日世話をすれば%d日で苗になる)" % [crop.name, sl.pots.size(), sl.POTS, sl.GROW_DAYS], 5.0)
		"far":
			$HUD.show_message("小屋まで行って作業する(%.0fm以内)" % world.cabin.REACH)
		"not_seedling":
			$HUD.show_message("苗にできるのはトマト [9] と きゅうり [6]")
		"full":
			$HUD.show_message("窓辺はいっぱい(%d鉢)。今日の世話は済んだ" % sl.POTS)
		"no_seed":
			$HUD.show_message("%sがない(市場で買える)" % crop.seed_name)

# ── ストーブ ───────────────────────────────────────────────
func _open_kitchen() -> void:
	_panel = "kitchen"
	_sfx("open")
	$Player.set_physics_process(false)  # 料理中は歩かない
	$HUD.open_shop()

# 「トマト 10kg」のような材料の文言
func _amount_text(item: String, n: int) -> String:
	return "%s %d%s" % [produce_name(item), n, produce_unit(item)]

func kitchen_rows() -> Array:
	var k := world.kitchen
	var rows := []
	for id in k.RECIPES:
		var r: Dictionary = k.RECIPES[id]
		rows.append({"id": "cook_" + id, "text": "仕込む: %s(%s → %d%s・%d日)持っている %d%s" % [
			r.name, _amount_text(r.input, r.amount), r.output, r.unit, r.days, k.input_count(id), produce_unit(r.input),
		], "column": 0})
	if k.is_empty():
		rows.append({"id": "pot_wait", "text": "鍋は空いている", "column": 1})
	elif k.is_ready():
		var r: Dictionary = k.RECIPES[k.pot.recipe]
		rows.append({"id": "pot_collect", "text": "受け取る: %s %d%s" % [r.name, r.output, r.unit], "column": 1})
	else:
		rows.append({"id": "pot_wait", "text": "鍋: %s あと%d日" % [k.RECIPES[k.pot.recipe].name, k.days_left()], "column": 1})
	rows.append({"id": "close", "text": "閉じる(H / Esc)", "column": 1})
	return rows

func _kitchen_action(id: String) -> void:
	var k := world.kitchen
	if id == "pot_collect":
		if k.collect() == "collected":
			var made: Dictionary = k.last_collected
			var r: Dictionary = k.RECIPES[made.recipe]
			$HUD.show_message("%sが%d%sできた(%s)" % [r.name, made.count, r.unit, _preserve_price_text(made.recipe, r.unit)], 5.0)
	elif id.begins_with("cook_"):
		var recipe := id.trim_prefix("cook_")
		var r: Dictionary = k.RECIPES[recipe]
		match k.start(recipe):
			"started":
				$HUD.show_message("%sを仕込んだ(%d日でできる・薪 -1回分)" % [r.name, r.days], 5.0)
			"busy":
				$HUD.show_message("鍋は使っている(受け取ってから次を仕込む)")
			"no_input":
				$HUD.show_message("%sが足りない(%d%s 必要)" % [produce_name(r.input), r.amount, produce_unit(r.input)])
			"no_wood":
				$HUD.show_message("薪がない(小屋の東の薪割り台で、H で丸太を割る)", 5.0)
	$HUD.refresh_shop()

# ── テーブルと腰掛け ──────────────────────────────────────────
# 腰掛けに座って、テーブルの保存食を 1 つ食べる。食べた日は少し速く歩ける
func _open_table() -> void:
	_panel = "table"
	_sfx("open")
	$Player.set_physics_process(false)  # 座っているあいだは歩かない
	if $Player.has_method("sit_down"):  # 3D だけ
		$Player.sit_down($Cabin.seat_spot(), $Cabin.SIT_YAW)
	$HUD.open_shop()

func table_rows() -> Array:
	var k := world.kitchen
	var rows := []
	for id in k.RECIPES:
		var n := produce_count(id)
		if n > 0:
			var r: Dictionary = k.RECIPES[id]
			var verb := "今日は食べた" if id in k.eaten_today() else "食べる"
			rows.append({"id": "eat_" + id, "text": "%s: %s(%d%s。市場で1%s %d₽)" % [verb, r.name, n, r.unit, r.unit, world.market.sell_price(id)], "column": 0})
	if rows.is_empty():
		rows.append({"id": "no_food", "text": "テーブルに保存食がない(ストーブで作る)", "column": 0})
	rows.append({"id": "close", "text": "立つ(H / Esc)", "column": 1})
	return rows

func _table_action(id: String) -> void:
	if not id.begins_with("eat_"):
		return
	var k := world.kitchen
	match k.eat(id.trim_prefix("eat_")):
		"eaten":
			if $Player.has_method("eat_motion"):
				$Player.eat_motion()
			$HUD.show_message("%sを食べた。今日は少し速く歩ける" % k.RECIPES[k.last_eaten].name, 5.0)
		"same":
			$HUD.show_message("%sは今日もう食べた(同じものは1日1つまで)" % k.RECIPES[id.trim_prefix("eat_")].name)
		"full":
			$HUD.show_message("今日はもうお腹いっぱい(1日%d種類まで)" % k.MEAL_KINDS)
	$HUD.refresh_shop()

# 「市場で1瓶 150₽で売れる。冬は225₽」のような文言。冬と春は今の値段だけ
func _preserve_price_text(id: String, unit: String) -> String:
	var m := world.market
	var text := "市場で1%s %d₽で売れる" % [unit, m.sell_price(id)]
	if m.price_rate(id, world.forest.season) > 1.0:
		return text
	return "%s。冬は%d₽" % [text, m.price_in(id, "winter")]

# HUD に出す、鍋の 1 行。鍋が空なら ""
func kitchen_line() -> String:
	var k := world.kitchen
	if k.is_empty():
		return ""
	var recipe: String = k.RECIPES[k.pot.recipe].name
	if k.is_ready():
		return "鍋: %s できた(ストーブの前で H)" % recipe
	return "鍋: %s あと%d日" % [recipe, k.days_left()]

# HUD に出す、食事の 1 行。今日まだ食べていなければ ""
func meal_line() -> String:
	var k := world.kitchen
	return "食事: 今日は %d/%d種類 食べた(少し速く歩ける)" % [k.eaten_today().size(), k.MEAL_KINDS] if k.ate_today() else ""

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
	return ""

# ── ベッド ─────────────────────────────────────────────────
# 現実の時間で進むゲームなので、寝ても時間は進まない。横になってから暗くなり、今日と明日のことを日記で見る
func _sleep() -> void:
	world.save_game()
	$Player.set_physics_process(false)
	var delay := 0.0
	if $Player.has_method("lie_down"):  # 3D だけ
		delay = $Player.LIE_SECONDS
		$Player.lie_down($Cabin.lying_spot())
		$Cabin.set_sleeping(true, delay * 0.7)
	$HUD.open_diary(diary_text(), delay + 0.5)

func _wake() -> void:
	$HUD.close_diary()
	$Player.set_physics_process(true)
	if $Player.has_method("get_up"):
		$Player.get_up()
		$Cabin.set_sleeping(false)

func diary_text() -> String:
	var f := world.forest
	var g := world.garden
	var today: String = f.today()
	var lines := PackedStringArray(["%d月%d日の日記" % [int(today.substr(5, 2)), int(today.substr(8, 2))], ""])
	var todo := PackedStringArray()
	if f.last_day == today and f.today_event != "":
		todo.append(daily_message(f.today_event))
	var now: Dictionary = g.today_counts()
	if now.ripe > 0:
		todo.append("収穫できる区画が %d ある" % now.ripe)
	if now.dry > 0:
		todo.append("まだ水をやっていない区画が %d ある" % now.dry)
	if world.seedlings.needs_care():
		todo.append("苗の世話がまだ")
	if has_node("Visitor") and world.visitors.has_request():
		todo.append("%sの頼みごとがまだ" % world.visitors.CAST[world.visitors.who()].name)
	if world.bees.ready_count() > 0:
		todo.append("はちみつが採れる巣箱が %d ある" % world.bees.ready_count())
	if world.cabin.is_complete() and world.kitchen.firewood <= 0:
		todo.append("薪がない(東の薪割り台で割る)")
	if world.feeders.hungry_count() > 0:
		todo.append("餌台の餌が切れている")
	if f.season == "winter" and f.prunable_count() > 0:
		todo.append("剪定できる果樹が %d本 ある" % f.prunable_count())
	lines.append("今日")
	lines.append_array(_bullets(todo, "やり残したことはない"))
	lines.append("")
	lines.append("明日")
	lines.append_array(_bullets(_tomorrow_lines(), "ゆっくりできそう"))
	lines.append("")
	lines.append("H / Esc / Enter で起きる")
	return "\n".join(lines)

func _tomorrow_lines() -> PackedStringArray:
	var g := world.garden
	var date: String = world.tomorrow_date()
	var season: String = world.season_for_month(int(date.substr(5, 2)))
	var plan: Dictionary = g.tomorrow_counts()
	var lines := PackedStringArray()
	var rain: bool = world.tomorrow_rain()
	if rain:
		lines.append("%sになりそう(水やりはいらない)" % ("雪" if season == "winter" else "雨"))
	if g.frost_is_near(world.forest.today()):
		lines.append("12月の霜が近い(ニンニク以外は早めに収穫を)")
	if plan.ripe > 0:
		lines.append("収穫できる区画: %d" % plan.ripe)
	if plan.spoiling > 0:
		lines.append("傷みはじめる区画: %d" % plan.spoiling)
	var to_water: int = g.crops.size() - plan.ripe
	if to_water > 0 and not rain:
		lines.append("水やりがいる区画: %d" % to_water)
	var fruiting: int = world.forest.fruiting_in(season)
	if fruiting > 0:
		lines.append("果物を収穫できる木: %d本" % fruiting)
	var pots: int = world.seedlings.grown_tomorrow()
	if pots > 0:
		lines.append("苗を受け取れる: %d鉢" % pots)
	var k := world.kitchen
	if k.ready_tomorrow():
		lines.append("鍋の%sを受け取れる" % k.RECIPES[k.pot.recipe].name)
	elif k.is_empty():
		lines.append("鍋が空いている")
	if world.bees.ready_tomorrow() > 0:
		lines.append("はちみつが採れる巣箱: %d" % world.bees.ready_tomorrow())
	if world.visitors.is_visit_day(world.forest.day_number() + 1):
		lines.append("%sが来そう" % world.visitors.CAST[world.visitors.who_on(world.forest.day_number() + 1)].name)
	return lines

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
	if c.is_complete():
		var sl := world.seedlings
		if sl.pots.is_empty():
			return "小屋: 完成(H で苗づくり)"
		var left: int = sl.days_left()
		var todo := "H で受け取る" if left == 0 else ("H で世話" if sl.needs_care() else "世話は済んだ")
		return "小屋: 苗 %d/%d鉢 あと%d日(%s)" % [sl.pots.size(), sl.POTS, left, todo]
	var s: Dictionary = c.current_stage()
	var today := "今日の作業は済んだ" if c.worked_today() else "H で作業・丸太%d本" % s.logs_per_day
	return "小屋: %s %d/%d日(%s)" % [CABIN_STAGE_NAMES[s.id], c.days_done, s.days, today]

# ── 池 ────────────────────────────────────────────────────
func _pond_action() -> void:
	var result: String = world.pond_action(player_pos())
	$HUD.show_message(POND_MESSAGES[result], 5.0)
	if result == "dug" or result == "finished":
		_act("dig", world.land.pond)
	if result == "placed" or result == "finished":
		world.save_game()
		_check_quests()

# HUD に出す、池のそばでの案内。そばにいなければ ""
func pond_beside_line() -> String:
	var p := world.pond
	if not p.is_beside(player_pos()) or p.is_frozen() or p.water < p.WATER_COST:
		return ""
	var dry: Array = p.dry_around()
	if dry[0] + dry[1] == 0:
		return ""
	return "池のそば: Q で 区画 %d・木 %d にまとめて水やり(池の水 -%d%%)" % [dry[0], dry[1], p.WATER_COST]

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
	var sl := world.seedlings
	var crop: Dictionary = g.CROPS[selected_crop]
	# 育った苗があれば、種より先に苗を使う
	var from_seedling: bool = int(sl.ready.get(selected_crop, 0)) > 0
	var result: String = sl.transplant(pos, selected_crop) if from_seedling else g.sow(pos, selected_crop)
	match result:
		"sown":
			_act("plant", world.land.plot_center(pos))
			var verb := "の苗を植えた" if from_seedling else "をまいた"
			$HUD.show_message("%s%s(毎日水をやれば%d日で収穫できる)" % [crop.name, verb, g.days_left(g.crop_at(pos))], 5.0)
		"needs_seedling":
			$HUD.show_message("%sは苗から育てる(完成した小屋で H を押して鉢にまく)" % crop.name, 5.0)
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
	return "足元の区画: %s あと%d日(%s)" % [crop_name, g.days_left(c), water]

# n 個ごとに折り返して並べる(市場の画面と重ならない幅にするため)
static func _rows(parts: PackedStringArray, n: int) -> String:
	var rows := PackedStringArray()
	for i in range(0, parts.size(), n):
		rows.append("  ".join(parts.slice(i, i + n)))
	return "\n    ".join(rows)

# HUD に出す、持っている野菜の種
func crop_seeds_line() -> String:
	var parts := PackedStringArray()
	for key in CROP_KEYS:
		var kind: String = CROP_KEYS[key]
		parts.append("%s %d" % [world.garden.CROPS[kind].name, world.garden.seeds[kind]])
	return _rows(parts, 3)

# HUD に出す、持っている収穫物(持っているものだけ。苗は seedlings_line、保存食は food_line)
func produce_line() -> String:
	var parts := PackedStringArray()
	for item in world.market.SELL_PRICES:
		var n := produce_count(item)
		if n > 0 and not item.begins_with("seedling_") and not world.kitchen.RECIPES.has(item):
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
	if world.forest.FRUITS.has(item):
		return world.forest.SPECIES[item].name
	if item == "honey":
		return "はちみつ"
	if item.begins_with("seedling_"):
		return world.garden.CROPS[item.trim_prefix("seedling_")].name + "の苗"
	if world.kitchen.RECIPES.has(item):
		return world.kitchen.RECIPES[item].name
	return world.garden.CROPS[item].name

func produce_unit(item: String) -> String:
	if world.forest.FRUITS.has(item):
		return world.forest.FRUITS[item].unit
	if world.kitchen.RECIPES.has(item):
		return world.kitchen.RECIPES[item].unit
	return "鉢" if item.begins_with("seedling_") else "kg"

func produce_count(item: String) -> int:
	if world.forest.FRUITS.has(item):
		return int(world.forest.produce[item])
	if item == "honey":
		return int(world.bees.stock.honey)
	if item.begins_with("seedling_"):
		return int(world.seedlings.ready[item.trim_prefix("seedling_")])
	if world.kitchen.RECIPES.has(item):
		return int(world.kitchen.stock[item])
	return int(world.garden.produce[item])

# ── 市場 ──────────────────────────────────────────────────
# 市場の品の表示名。例: 「白樺の種(10粒)」「リンゴの苗木(樹齢3年)」「じゃがいもの種いも(春にまく)」「丸太(5本)」
func good_name(g: Dictionary) -> String:
	if g.form == "material":
		return "丸太(%d本)" % g.amount
	if g.species == "tomato":
		return "%s(小屋で苗にする)" % world.garden.CROPS.tomato.seed_name
	if g.form == "crop_seed":
		return "%s(%sにまく)" % [world.garden.CROPS[g.species].seed_name, crop_seasons(g.species)]
	var sp: Dictionary = world.forest.SPECIES[g.species]
	if g.form == "sapling":
		return "%sの苗木(樹齢%d年)" % [sp.name, int(sp.sapling_age)]
	return "%sの種(%d粒・発芽率%d%%)" % [sp.name, g.amount, roundi(sp.germination * 100.0)]

# 右の画面の見出し
func shop_title() -> String:
	if _panel == "visitor":
		return world.visitors.CAST[world.visitors.who()].name
	if _panel == "table":
		return "腰掛け(クリックか 矢印キー + Enter で選ぶ)"
	return "ストーブ(クリックか 矢印キー + Enter で選ぶ)" if _panel == "kitchen" else "市場(クリックか 矢印キー + Enter で選ぶ)"

# 右の画面の 2 行目
func shop_header() -> String:
	if _panel == "visitor":
		return visitor_text()
	if _panel == "table":
		var k := world.kitchen
		var note := "同じものは1日1つ、%d種類まで" % k.MEAL_KINDS
		return "今日は %d/%d種類 食べた(%s)" % [k.eaten_today().size(), k.MEAL_KINDS, note] if k.ate_today() else "食べると今日は少し速く歩ける(%s)" % note
	if _panel == "kitchen":
		return "薪: %d回分   丸太: %d本(丸太1本で%d回分)" % [world.kitchen.firewood, int(world.cabin.materials.log), world.kitchen.LOG_FIRES]
	return "所持金: %s₽" % $HUD._money_text(world.market.money)

# 右の画面に並べる行 [{id, text, column}]。市場は column 0 = 買う列、1 = 売る列
func shop_rows() -> Array:
	if _panel == "kitchen":
		return kitchen_rows()
	if _panel == "table":
		return table_rows()
	if _panel == "visitor":
		return visitor_rows()
	var m := world.market
	var rows := []
	var buy_next: int = (_buy_page + 1) % BUY_PAGES.size()
	rows.append({"id": "page_buy", "text": "買う品: %s(押すと次: %s)" % [BUY_PAGES[_buy_page].name, BUY_PAGES[buy_next].name], "column": 0})
	for g in m.GOODS:
		rows.append({"id": g.id, "text": "買う: %s  %d₽" % [good_name(g), g.price], "column": 0, "page": _buy_page_of(g)})
	var sell_next: int = (_sell_page + 1) % SELL_PAGES.size()
	rows.append({"id": "page_sell", "text": "売る品: %s(押すと次: %s %d種類)" % [SELL_PAGES[_sell_page], SELL_PAGES[sell_next], _held_kinds(sell_next)], "column": 1})
	for item in m.SELL_PRICES:
		# 野菜は持っているものだけ並べる(行が多くなりすぎないように)
		var n := produce_count(item)
		if item == "apple" or n > 0:
			var dear := "(%s)" % SEASON_NAMES[world.forest.season] if m.price_rate(item, world.forest.season) > 1.0 else ""
			rows.append({"id": "sell_" + item, "text": "売る: %s %d%s × %d₽%s" % [produce_name(item), n, produce_unit(item), m.sell_price(item), dear], "column": 1, "page": _sell_page_of(item)})
	rows.append({"id": "close", "text": "閉じる(B / Esc)", "column": 1})
	return rows

func _buy_page_of(g: Dictionary) -> int:
	for i in range(BUY_PAGES.size()):
		if g.form in BUY_PAGES[i].forms:
			return i
	return 0

func _sell_page_of(item: String) -> int:
	return 1 if world.kitchen.RECIPES.has(item) else 0

# そのページで持っている品の種類の数
func _held_kinds(page: int) -> int:
	var n := 0
	for item in world.market.SELL_PRICES:
		if _sell_page_of(item) == page and produce_count(item) > 0:
			n += 1
	return n

# 右の画面に今出す行。市場は、今のページの品とページを送る行(ほかの画面は全部)
func visible_shop_rows() -> Array:
	return shop_rows().filter(func(r): return not r.has("page") or r.page == (_buy_page if r.column == 0 else _sell_page))

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
	var was_sitting: bool = _panel == "table"
	_sfx("click")
	$HUD.close_shop()
	$Player.set_physics_process(true)
	if was_sitting and $Player.has_method("stand_up"):
		$Player.stand_up()
	if was_chat:
		world.visitors.finish_chat()  # 話し終えると帰っていく
	_panel = "market"

func _on_shop_action(id: String) -> void:
	var m := world.market
	if id == "close":
		_close_shop()
		return
	if _panel == "kitchen":
		_sfx("click")
		_kitchen_action(id)
		return
	if _panel == "table":
		_sfx("click")
		_table_action(id)
		return
	if _panel == "visitor":
		_visitor_action(id)
		return
	if id == "page_buy" or id == "page_sell":
		_sfx("click")
		if id == "page_buy":
			_buy_page = (_buy_page + 1) % BUY_PAGES.size()
		else:
			_sell_page = (_sell_page + 1) % SELL_PAGES.size()
		$HUD.refresh_shop()
		return
	if id.begins_with("sell_"):
		var item := id.trim_prefix("sell_")
		var income: int = m.sell_all(item)
		_sfx("coin" if income > 0 else "click")
		$HUD.show_message("%sを売った(+%d₽)" % [produce_name(item), income] if income > 0 else "売る%sがない" % produce_name(item))
	else:
		var g: Dictionary = m.good(id)
		var bought: bool = m.buy(id) == "bought"
		_sfx("coin" if bought else "click")
		if bought:
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
		_act("pick", c.pos, kind)
		var spoiled := "傷んでいて半分だけ。" if g.last_harvest_spoiled else ""
		$HUD.show_message("%sを%dkg収穫した(%s市場で1kg %d₽で売れる)" % [g.CROPS[kind].name, g.last_harvest_kg, spoiled, world.market.SELL_PRICES[kind]])
		return
	if crop == "preview":
		$HUD.show_message(HARVEST_MESSAGES.preview)
		return
	# 足元 2m 以内の果樹を収穫する
	var result: String = world.forest.harvest_nearest(pos, REACH)
	if crop == "growing" and result != "harvested":
		$HUD.show_message("%sはまだ育っている(あと%d日)" % [g.CROPS[c.kind].name, g.days_left(c)])
		return
	if result == "harvested":
		_act("pick_high", world.forest.trees[world.forest.nearest_fruit_index(pos, REACH)].pos, world.forest.last_harvest_item)
	$HUD.show_message(HARVEST_MESSAGES[result] if HARVEST_MESSAGES.has(result) else _fruit_message(result))

func _water() -> void:
	var f := world.forest
	var g := world.garden
	var pos := player_pos()
	# 池のそばなら、まわりにまとめて水をやる。できなければ、ふつうの水やりを試す
	var pond_result: String = world.pond.water_around(pos)
	if pond_result == "watered":
		var n: Array = world.pond.last_watered
		_act("water")
		$HUD.show_message("池の水を運んだ(区画 %d・木 %d に水やり。池の水 %d%%)" % [n[0], n[1], world.pond.water], 5.0)
		return
	# 足元の区画の野菜を先に。今日もう水をあげていれば、近くの木を見る
	var crop: String = g.water_at(pos)
	if crop == "watered":
		_act("water", g.crop_at(pos).pos)
		$HUD.show_message("%sに水をあげた(水をやった日は1日ぶん、やらない日は半日ぶん育つ)" % g.CROPS[g.crop_at(pos).kind].name)
		return
	# 足元 2m 以内の木に水をあげる
	var result: String = f.water_nearest(pos, REACH)
	if crop != "none" and result != "watered":
		$HUD.show_message("もう収穫できる(E)" if crop == "ripe" else "この区画には今日もう水をあげた")
		return
	# 足元に何もない池のそば: なぜ運べないかを知らせる
	if result == "none" and POND_WATER_MESSAGES.has(pond_result):
		$HUD.show_message(POND_WATER_MESSAGES[pond_result])
		return
	var msg: String = WATER_MESSAGES[result]
	if result == "watered":
		var i: int = f.nearest_index(pos, REACH, "")
		msg = msg % [f.SPECIES[f.trees[i].species].name, f.WATER_BONUS_YEARS]
		_act("water", f.trees[i].pos)
	$HUD.show_message(msg)

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
	var falls: bool = not felled.is_empty() and $Trees.has_method("start_fall") and $Trees.start_fall(felled, pos)
	var logs: int = world.cabin.fell(pos, REACH)
	if not felled.is_empty():
		_act("chop" if falls else "pull", felled.pos)
	if falls and $Audio.has_method("play_after"):
		$Audio.play_after("tree_fall", TREE_FALL_SOUND_DELAY)
	if logs > 0:
		$HUD.show_message("木を伐った(丸太 +%d本)" % logs)
	elif logs == 0:
		$HUD.show_message("木を抜いた(細くて丸太にはならない)")
	elif world.cabin.cancel(pos):
		$HUD.show_message("小屋の場所を取り消した")
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
	if $HUD.is_diary_open():
		if event.keycode == KEY_H or event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER:
			_wake()
		return
	if $HUD.is_shop_open():
		# 開いているあいだは閉じるキーだけ(選ぶのは画面のボタン)。市場は B、ストーブは H、訪問者は C でも閉じる
		var close_key: int = {"kitchen": KEY_H, "table": KEY_H, "visitor": KEY_C}.get(_panel, KEY_B)
		if event.keycode == close_key or event.keycode == KEY_ESCAPE:
			_close_shop()
		return
	if CROP_KEYS.has(event.keycode):
		selected_crop = CROP_KEYS[event.keycode]
		return
	match event.keycode:
		KEY_TAB:
			$HUD.inventory_open = not $HUD.inventory_open
		KEY_F1:
			$HUD.help_open = not $HUD.help_open
		KEY_1:
			selected_species = "birch"
		KEY_2:
			_select_next_fruit()
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
