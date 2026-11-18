extends SceneTree

# 家族(配偶者と子ども・朝の手伝い・話す/贈り物・テント・セーブ)のロジックテスト。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_family.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる。座標の単位は m

const GameWorld = preload("res://logic/GameWorld.gd")
const Family = preload("res://logic/Family.gd")
const Pests = preload("res://logic/Pests.gd")
const Garden = preload("res://logic/Garden.gd")
const FamilyPicker = preload("res://view/FamilyPicker.gd")

const TEST_SAVE := "user://test_family.json"

var _failed := 0
var _passed := 0

func _initialize() -> void:
	_test_choose()
	_test_ages()
	_test_water_help()
	_test_no_water()
	_test_weed_help()
	_test_new_day()
	_test_talk_and_gifts()
	_test_tent()
	_test_save()
	_test_picker()
	_test_custom_rules()
	_test_together()
	_remove_save()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)

func _remove_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func _world(pref := "tokyo") -> GameWorld:
	_remove_save()
	var w := GameWorld.new()
	w.save_path = TEST_SAVE
	w.time.set_today("2026-05-10")
	if pref != "":
		w.choose_region(pref)
	w.refresh_season()
	w.forest.last_day = w.forest.today()
	w.forest.today_event = "birds"
	w.pests.last_day = w.forest.today()
	w.pests.friendship = Pests.FRIEND_MAX  # 畑が荒らされないように
	return w

func _crop(w: GameWorld, pos: Vector2, kind := "daikon") -> Dictionary:
	w.land.toggle_plot(pos)
	w.garden.seeds[kind] = int(w.garden.seeds.get(kind, 0)) + 1
	w.garden.sow(pos, kind)
	return w.garden.crop_at(pos)

func _test_choose() -> void:
	print("家族を決める")
	var w := _world()
	var f := w.family
	_check(not f.chosen and f.members.is_empty(), "決める前は誰もいない")
	_check(f.home_pos() == null and not f.has_tent(), "決める前はテントもない")
	_check(w.choose_family("bogus", 1) == "unknown", "知らない配偶者は選べない")
	_check(w.choose_family("alyona", 4) == "unknown", "子どもは %d 人まで" % Family.MAX_CHILDREN)
	_check(not f.chosen, "選べなかったときは決まらない")
	_check(w.choose_family("alyona", 2) == "chosen", "配偶者と子ども 2 人で決める")
	_check(f.members.size() == 3, "家族は 3 人")
	_check(f.spouse().name == "アリョーナ" and f.spouse().relation == "妻", "配偶者はアリョーナ(妻)")
	var kids := f.children()
	_check(kids.size() == 2 and kids[0].name == "ワーニャ" and kids[1].name == "マーシャ", "子どもは上から ワーニャ・マーシャ")
	_check(f.age_of(kids[0]) == 9 and f.age_of(kids[1]) == 6, "はじめは 9 歳と 6 歳")
	_check(w.choose_family("ilya", 0) == "already", "あとから変えられない")
	var w2 := _world()
	_check(w2.choose_family("", 0) == "chosen" and w2.family.members.is_empty(), "配偶者も子どももいない暮らしも選べる")
	_check(w2.family.home_pos() == null and not w2.family.has_tent(), "ひとりならテントは張らない")
	var w3 := _world()
	w3.choose_family("", 3)
	_check(w3.family.spouse().is_empty() and w3.family.children().size() == 3, "配偶者なしで子ども 3 人も選べる")
	var w4 := _world()
	w4.choose_family("mikhail", 0)
	_check(w4.family.spouse().relation == "夫", "ミハイルは夫")

func _test_ages() -> void:
	print("子どもが育つ")
	var w := _world()
	var f := w.family
	f.choose("vera", 3)
	var polya: Dictionary = f.member("polya")
	_check(f.age_of(polya) == 3, "ポーリャははじめ 3 歳")
	w.time.shift_days(Family.AGE_DAYS - 1)
	_check(f.age_of(polya) == 3, "%d 日たつまでは同じ年齢" % Family.AGE_DAYS)
	w.time.shift_days(1)
	_check(f.age_of(polya) == 4, "%d 日で 1 歳育つ" % Family.AGE_DAYS)
	w.time.shift_days(Family.AGE_DAYS * 40)
	_check(f.age_of(polya) == Family.ADULT_AGE, "%d 歳で育つのが止まる" % Family.ADULT_AGE)
	_check(f.age_of(f.spouse()) == Family.ADULT_AGE, "配偶者の年齢は変わらない")

func _test_water_help() -> void:
	print("配偶者の水やり")
	var w := _world()
	var f := w.family
	f.choose("alyona", 0)
	var spots := [Vector2(-19.5, -19.5), Vector2(-16.5, -19.5), Vector2(-13.5, -19.5), Vector2(-10.5, -19.5)]
	for p in spots:
		_crop(w, p)
	var can_before: int = w.tools.can_water
	_check(w.river.exists(), "県を選ぶと川がある(水を汲める)")
	_check(f.help_today(), "朝に手伝う")
	var watered: int = w.garden.crops.filter(func(c): return w.garden.watered_today(c)).size()
	_check(watered == Family.WATER_HELP, "水をやるのは %d 区画まで(%d)" % [Family.WATER_HELP, watered])
	_check(f.help_summary().get("alyona", {}).get("water", 0) == Family.WATER_HELP, "手伝いの知らせに数が出る")
	_check(w.tools.can_water == can_before, "プレイヤーのジョウロの水は減らない")
	_check(not f.help_today(), "同じ日に 2 回は手伝わない")
	# 次の日: 区画が 1 つしか乾いていなければ、残りは木に
	w.time.shift_days(1)
	for c in w.garden.crops.slice(0, 3):
		w.garden.water_at(c.pos)
	w.forest.saplings.birch = 1
	w.forest.add_tree(Vector2(10, 10), "birch", "sapling")
	f.help_today()
	var s: Dictionary = f.help_summary().get("alyona", {})
	var tree_watered: bool = w.forest.watered_today(w.forest.trees[0])
	_check(s.get("water", 0) == 2 and tree_watered, "乾いた区画が少なければ、木にも水をやる(区画 1 + 木 1)")

func _test_no_water() -> void:
	print("水を汲めないとき")
	var w := _world("")  # 県を選ぶ前は川がない
	var f := w.family
	f.choose("ilya", 0)
	_check(not _crop(w, Vector2(-19.5, -19.5), "radish").is_empty(), "ラディッシュをまいた")
	_check(not w.river.exists() and not w.well.is_dug() and not w.pond.is_dug(), "井戸も池も川もない")
	f.help_today()
	_check(f.last_help.is_empty(), "汲む場所がなければ水やりはしない")
	w.time.shift_days(1)
	w.well.site = Vector2(20, 20)
	w.well.days_dug = w.well.DIG_DAYS
	_check(w.well.is_dug(), "井戸を掘り終えた")
	f.help_today()
	_check(f.help_summary().get("ilya", {}).get("water", 0) == 1, "井戸があれば水をやる")

func _test_weed_help() -> void:
	print("子どもの草取り")
	var w := _world()
	var f := w.family
	f.choose("", 3)  # ワーニャ 9・マーシャ 6・ポーリャ 3
	var spots := [Vector2(-19.5, -19.5), Vector2(-16.5, -19.5), Vector2(-13.5, -19.5), Vector2(-10.5, -19.5), Vector2(-7.5, -19.5)]
	for p in spots:
		_crop(w, p)
	w.time.shift_days(Garden.WEED_FREE_DAYS + 1)
	_check(w.garden.weedy_count() == spots.size(), "雑草が生えた(%d 区画)" % w.garden.weedy_count())
	f.help_today()
	var s := f.help_summary()
	_check(s.get("vanya", {}).get("weed", 0) == 1, "9 歳のワーニャは 1 区画")
	_check(s.get("masha", {}).get("weed", 0) == 1, "%d 歳のマーシャも 1 区画" % Family.HELP_AGE)
	_check(not s.has("polya"), "3 歳のポーリャはまだ手伝わない")
	_check(w.garden.weedy_count() == spots.size() - 2, "雑草は 2 区画減った")
	_check(not s.has("vanya") or s.vanya.water == 0, "子どもは水をやらない")
	# ワーニャが 10 歳になると 2 区画
	w.time.shift_days(Family.AGE_DAYS)
	f.help_today()
	_check(f.help_summary().get("vanya", {}).get("weed", 0) == 2, "%d 歳になると 1 日 2 区画" % Family.WEED_MORE_AGE)

func _test_new_day() -> void:
	print("日付が変わると手伝う")
	var w := _world()
	w.family.choose("alyona", 1)
	_crop(w, Vector2(-19.5, -19.5))
	w.time.shift_days(1)
	var id: String = w.check_new_day()
	_check(id != "", "日付が変わった")
	if id == "rain":
		_check(w.family.help_summary().is_empty(), "雨の日は水やりが要らない")
	else:
		_check(w.family.help_summary().get("alyona", {}).get("water", 0) == 1, "check_new_day で朝の水やりをする")
	_check(w.family.helped_day == w.forest.day_number(), "手伝った日を覚える")
	# 決める前のセーブでは何もしない
	var w2 := _world()
	_crop(w2, Vector2(-19.5, -19.5))
	w2.time.shift_days(1)
	w2.check_new_day()
	_check(w2.family.last_help.is_empty(), "家族を決める前は手伝いがない")

# 贈り物をくれる日を探す(人と日で決まる)
func _gift_day(w: GameWorld, id: String) -> int:
	for i in range(200):
		if Family._gift_roll(id, w.forest.day_number()):
			return i
		w.time.shift_days(1)
	return -1

func _test_talk_and_gifts() -> void:
	print("話す・贈り物")
	var w := _world()
	var f := w.family
	f.choose("alyona", 3)
	_check(f.talk("nobody") == "none", "いない人には話せない")
	_check(_gift_day(w, "alyona") >= 0, "贈り物の日がある")
	w.refresh_season()
	var g: Dictionary = Family.SPOUSE_GIFTS[w.forest.season]
	var before: int = w.market.count_of(g.item)
	_check(f.talk("alyona") == "gift", "その日はじめて話すと贈り物をくれる日がある")
	_check(w.market.count_of(g.item) == before + int(g.count), "季節の料理(%s %d)が持ち物に入る" % [g.item, g.count])
	_check(f.talk("alyona") == "chat" and f.last_gift.is_empty(), "同じ日の 2 回目は話すだけ")
	_check(f.talked_today("alyona"), "話した日を覚える")
	# 子ども: 木の種
	_check(_gift_day(w, "vanya") >= 0, "ワーニャの贈り物の日がある")
	w.refresh_season()
	var species: String = w.forest.nut_seed() if w.forest.season == "autumn" else w.forest.wind_seed()
	var seeds_before: int = int(w.forest.seeds.get(species, 0))
	_check(f.talk("vanya") == "gift" and f.last_gift.type == "tree_seed", "子どもは木の種を拾ってくる")
	_check(int(w.forest.seeds.get(species, 0)) == seeds_before + Family.CHILD_GIFT_SEEDS, "%sの種が %d 増える" % [species, Family.CHILD_GIFT_SEEDS])
	# 小さい子は拾いに行かない
	_check(_gift_day(w, "polya") >= 0, "ポーリャの贈り物の日がある")
	if f.age_of(f.member("polya")) < Family.HELP_AGE - 2:
		_check(f.talk("polya") == "chat", "小さい子は贈り物を持ってこない")
	# 話したかどうかは日付と人で決まる(開き直しても同じ)
	_check(Family._gift_roll("alyona", 100) == Family._gift_roll("alyona", 100), "贈り物の日は日付で決まる")
	var hits := 0
	for d in range(1000):
		if Family._gift_roll("masha", d):
			hits += 1
	_check(hits > 200 and hits < 400, "贈り物は 3 日に 1 回ほど(%d/1000)" % hits)

func _test_tent() -> void:
	print("テント")
	var w := _world()
	var f := w.family
	f.choose("alyona", 1)
	_check(f.has_tent() and f.tent != null, "小屋がなければテントを張る")
	_check(f.tent.length() >= Family.CENTER_CLEAR, "テントは家族の杉の場所(中心 %dm)を空ける" % Family.CENTER_CLEAR)
	var home = f.home_pos()
	_check(home != null and home.y > f.tent.y + Family.TENT_SIZE.y * 0.5 and absf(home.x - f.tent.x) < 0.1, "夜はテントの南の入口へ帰る")
	# 寝袋: 西から プレイヤー・配偶者・子ども
	var spots: Array = f.bedroll_spots()
	_check(spots.size() == 3 and spots[0].x < spots[1].x and spots[1].x < spots[2].x, "寝袋は家族の人数 + 自分の分、西から並ぶ")
	_check(f.bedroll_of("") == spots[0] and f.bedroll_of("alyona") == spots[1] and f.bedroll_of("vanya") == spots[2], "西の端が自分、次が配偶者、子どもの順")
	_check(spots.all(func(sp): return f.tent_rect().has_point(sp)), "寝袋はテントの中")
	_check(f.is_in_tent(f.tent) and not f.is_in_tent(f.tent + Vector2(Family.TENT_SIZE.x, 0)), "テントの中かどうか")
	_check(f.is_at_bedroll(spots[0]) and f.is_at_bedroll(spots[0] + Vector2(0, 1.2)), "自分の寝袋のそばなら休める")
	_check(not f.is_at_bedroll(spots[0] + Vector2(0, 4.0)), "テントの外では休めない")
	_check(w.toggle_plot(f.tent) == "tent", "テントの上に区画は作れない")
	_check(w.pond_action(f.tent + Vector2(2, 0)) == "tent", "テントにかかる場所に池は掘れない")
	_check(w.bees.is_blocked(f.tent + Vector2(1, 0)), "テントのそばに巣箱・井戸・餌台・石臼は置けない")
	# あとから物がかかったら移す(区画を作れない場所でも、木は種がまけてしまうので)
	var old: Vector2 = f.tent
	w.forest.seeds.birch = 1
	w.forest.add_tree(old + Vector2(0.5, 0), "birch", "seed")
	f.ensure_tent()
	_check(f.tent != null and f.tent != old and not f.tent_rect().grow(0.9).has_point(old + Vector2(0.5, 0)), "木がかかったらテントを移す")
	# 小屋の場所を決めると、そのそばへ
	var w2 := _world()
	w2.cabin.site = Vector2(15, 15)
	w2.family.choose("ilya", 0)
	_check(w2.family.tent.distance_to(Vector2(15, 15)) < 10.0, "小屋の場所が決まっていれば、そのそばに張る")
	_check(not w2.cabin.footprints()[0].grow(1.0).has_point(w2.family.tent), "小屋にはかからない")
	# 小屋が完成したら片付けて、小屋へ帰る
	w2.cabin.stage = w2.cabin.STAGES.size()
	w2.family.ensure_tent()
	_check(not w2.family.has_tent() and w2.family.tent == null, "小屋が完成したらテントを片付ける")
	_check(w2.family.home_pos() == w2.cabin.door_pos() + Vector2(0, Family.DOOR_OUT), "小屋が完成したら小屋の戸口の外へ帰る(そこから中へ)")
	# 小屋のベッド(2026-11-18 とむ: 小屋を 6m × 4m に広げて、家族もベッドで寝る)
	var w5 := _world()
	w5.cabin.site = Vector2(15, 15)
	w5.family.choose("vera", 3)
	_check(w5.family.bed_spots().is_empty(), "小屋が完成する前はベッドがない(テントで寝る)")
	w5.cabin.stage = w5.cabin.STAGES.size()
	var beds: Array = w5.family.bed_spots()
	_check(beds.map(func(x): return x.id) == ["vera", "vanya", "masha", "polya"], "家族の人数ぶん、寝る場所がある")
	_check(beds.map(func(x): return x.kind) == ["double", "bunk_high", "bunk_low", "cot"], "配偶者は大きいベッド、子どもは上の子から 2 段ベッドの上・下、3 人目は小さいベッド")
	var site: Vector2 = w5.cabin.site
	var c = w5.cabin
	var inner: Rect2 = c.rect().grow(-0.1)  # 壁の内側
	var bed := Rect2(site + c.BED_OFFSET - c.BED_SIZE * 0.5, c.BED_SIZE)
	var bunk := Rect2(site + Family.BUNK_OFFSET - Family.BUNK_SIZE * 0.5, Family.BUNK_SIZE)
	var cot := Rect2(site + Family.COT_OFFSET - Family.COT_SIZE * 0.5, Family.COT_SIZE)
	var stove := Rect2(site + c.STOVE_OFFSET - c.STOVE_SIZE * 0.5, c.STOVE_SIZE)
	var table := Rect2(site + Vector2(1.3, 1.2) - Vector2(0.95, 0.7) * 0.5, Vector2(0.95, 0.7))  # CabinView3D.TABLE_POS・TABLE_SIZE
	var furniture := [bed, bunk, cot, stove, table]
	_check(furniture.all(func(r): return inner.encloses(r)), "家具はみんな壁の内側に収まる")
	var apart := true
	for i in range(furniture.size()):
		for j in range(i + 1, furniture.size()):
			apart = apart and not furniture[i].grow(0.05).intersects(furniture[j])
	_check(apart, "家具どうしは重ならない")
	_check(beds.all(func(x): return inner.has_point(x.feet) and inner.has_point(x.approach)), "寝る場所とそばの床は小屋の中")
	_check(beds.all(func(x): return not furniture.any(func(r): return r.has_point(x.approach))), "ベッドのそばの床は家具にかからない(歩いて行ける)")
	_check(bed.has_point(beds[0].feet) and beds[0].feet.y < bed.get_center().y, "配偶者は大きいベッドの北の半分")
	_check(bunk.has_point(beds[1].feet) and bunk.has_point(beds[2].feet) and cot.has_point(beds[3].feet), "子どもは 2 段ベッドと小さいベッド")
	# ストーブ・戸口・西の部屋への出入り口のまわりは空いている(当たり判定のある家具でふさがない)
	var stove_front: Vector2 = site + c.STOVE_OFFSET + Vector2(-0.75, 0.6)
	_check(c.is_at_stove(stove_front) and not furniture.any(func(r): return r.grow(0.3).has_point(stove_front)), "ストーブの前に立って料理できる")
	var door_in: Vector2 = c.door_pos() + Vector2(0, -0.4)
	_check(not furniture.any(func(r): return r.grow(0.3).has_point(door_in)), "戸口を入ったところは空いている")
	var pass_in: Vector2 = site + Vector2(-c.WIDTH * 0.5 + 0.35, c.PASS_Z)
	_check(not furniture.any(func(r): return r.grow(0.2).has_point(pass_in)), "西の部屋への出入り口の前は空いている")
	_check(c.is_at_bed(site + c.BED_OFFSET + Vector2(c.BED_SIZE.x * 0.5 + 0.3, 0)), "大きいベッドのそばで休める")
	_check(w5.family.bed_of("masha").kind == "bunk_low" and w5.family.bed_of("nobody").is_empty(), "その人の寝る場所")
	var w6 := _world()
	w6.cabin.site = Vector2(15, 15)
	w6.cabin.stage = w6.cabin.STAGES.size()
	w6.family.choose("", 1)
	_check(w6.family.bed_spots().map(func(x): return x.kind) == ["single"], "子どもが 1 人なら 1 段のベッド(配偶者がいなければ大きいベッドは自分だけ)")
	# 寝る時刻(時計で決める。子どもが先)
	_check(not Family.is_bedtime("child", 20.0) and Family.is_bedtime("child", 20.5) and Family.is_bedtime("child", 23.0), "子どもは 20 時半に寝る")
	_check(not Family.is_bedtime("spouse", 21.0) and Family.is_bedtime("spouse", 22.0), "配偶者は 22 時に寝る")
	_check(Family.is_bedtime("spouse", 3.0) and Family.is_bedtime("child", 5.9) and not Family.is_bedtime("child", 6.0), "朝 6 時に起きる")
	_check(not Family.is_bedtime("child", 18.0), "暗くなってもすぐには寝ない(冬の 18 時)")
	_check(w2.toggle_plot(Vector2(-19.5, -19.5)) == "placed", "テントがなければ区画を作れる")

# 一緒にする作業(2026-11-18 とむ決定: 収穫・料理・夕食。1 日 1 回。少し得)
func _ripe(w: GameWorld, pos: Vector2, kind := "radish") -> Dictionary:
	var c := _crop(w, pos, kind)
	c.head = float(w.garden.CROPS[kind].grow_days)  # もう実っている
	return c

func _test_together() -> void:
	print("一緒にする作業")
	var w := _world()
	var f := w.family
	f.choose("alyona", 3)  # ワーニャ 9・マーシャ 6・ポーリャ 3 歳
	# 誘えるか
	_check(f.invite_problem("alyona", "harvest") == "" and f.invite_problem("masha", "harvest") == "", "収穫は配偶者と 6 歳からの子どもを誘える")
	_check(f.invite_problem("polya", "harvest") == "young", "3 歳の子は収穫に誘えない")
	_check(f.invite_problem("alyona", "cook") == "no_cabin" and f.invite_problem("alyona", "dinner") == "no_cabin", "料理と夕食は小屋ができてから")
	w.cabin.site = Vector2(20, 20)
	w.cabin.stage = w.cabin.STAGES.size()
	_check(f.invite_problem("alyona", "cook") == "" and f.invite_problem("vanya", "cook") == "spouse_only", "料理に誘えるのは配偶者")
	_check(f.invite_problem("polya", "dinner") == "", "夕食は小さい子からも誘える")
	_check(f.invite("alyona", "harvest") == "invited" and f.invited_today("alyona", "harvest"), "誘う")
	_check(f.invite("alyona", "harvest") == "done_today" and f.invite_problem("vanya", "harvest") == "", "同じ人・同じ作業は 1 日 1 回(ほかの人は誘える)")
	_check(f.invite("masha", "dinner") == "invited" and f.invite_problem("alyona", "dinner") == "done_today", "夕食はみんなで 1 日 1 回")
	w.time.shift_days(1)
	_check(f.invite_problem("alyona", "harvest") == "", "次の日はまた誘える")
	_check(f.invite("nobody", "harvest") == "unknown" and f.invite("alyona", "nap") == "unknown", "知らない人・作業は誘えない")
	# 近くの収穫できる区画
	_check(not f.any_ripe() and f.ripe_near(Vector2(-10, -10), Family.HARVEST_REACH) == null, "実った区画がなければ何もない")
	_crop(w, Vector2(-16.5, -10.5))
	var a := _ripe(w, Vector2(-13.5, -10.5))
	var b := _ripe(w, Vector2(-10.5, -10.5))
	_ripe(w, Vector2(-1.5, -10.5))
	_check(f.any_ripe(), "実った区画がある")
	_check(f.ripe_near(Vector2(-13.5, -10.5), Family.HARVEST_REACH, [a.pos]) == b.pos, "自分が採った区画のほかで、近くの実った区画(育っている区画は採らない)")
	_check(f.ripe_near(Vector2(-13.5, -10.5), Family.HARVEST_REACH, [a.pos, b.pos]) == null, "4m より遠い区画は採らない")
	# 料理: 一緒に仕込むと 2 割多くできる(少なくとも 1 つ)
	var k := w.kitchen
	k.firewood = 5
	w.garden.produce.tomato = 20
	k.active = 0
	_check(k.start("sauce", true) == "started" and k.pot.get("helped", false), "一緒に仕込んだ鍋")
	k.pot.start_day = int(k.pot.start_day) - 1
	var out: int = int(k.RECIPES.sauce.output)
	_check(k.collect() == "collected" and k.last_collected.count == out + 1 and k.last_collected.extra == 1 and k.stock.sauce == out + 1, "トマトソース 5 瓶 → 6 瓶")
	_check(k.help_extra("pirozhki") == 4 and k.help_extra("jam") == 1, "ピロシキ 20 個なら +4、ジャム 4 瓶なら +1(少なくとも 1)")
	_check(k.start("sauce") == "started" and not k.pot.has("helped"), "ひとりで仕込むと増えない")
	w.save_game()
	var wk := GameWorld.new()
	wk.save_path = TEST_SAVE
	wk.time.offset_seconds = w.time.offset_seconds
	wk.load_game()
	k.pot = {}
	# 夕食: みんなで食べた翌朝は手伝いが増える
	var w2 := _world()
	var f2 := w2.family
	f2.choose("alyona", 2)  # ワーニャ 9・マーシャ 6
	w2.time.shift_days(Family.AGE_DAYS * 2)  # ワーニャ 11 歳(2 区画)・マーシャ 8 歳(1 区画)
	var dry := []
	for i in range(8):
		dry.append(Vector2(-19.5 + i * 3.0, -19.5))
	for q in dry:
		_crop(w2, q)
	f2.help_today()
	_check(f2.help_summary().alyona.water == Family.WATER_HELP, "ふだんの朝の水やりは %d か所" % Family.WATER_HELP)
	f2.dine_together()
	_check(f2.dined_today(), "みんなで食べた")
	w2.time.shift_days(1)
	for c in w2.garden.crops:
		c.weed_days = 10  # みんな雑草が生えている
		c.weeded_day = -100
	f2.help_today()
	var sum: Dictionary = f2.help_summary()
	_check(sum.alyona.water == Family.DINNER_WATER_HELP, "みんなで夕食を食べた翌朝は、水やりが %d か所(%d)" % [Family.DINNER_WATER_HELP, sum.alyona.water])
	_check(sum.vanya.weed == 3 and sum.masha.weed == 2, "子どもの草抜きも 1 区画ずつ増える(%d・%d)" % [sum.vanya.weed, sum.masha.weed])
	w2.time.shift_days(1)
	f2.help_today()
	_check(f2.help_summary().alyona.water == Family.WATER_HELP, "その次の朝はふだんどおり")
	# セーブ
	f2.invite("alyona", "harvest")
	f2.dine_together()
	w2.save_game()
	var w3 := GameWorld.new()
	w3.save_path = TEST_SAVE
	w3.time.offset_seconds = w2.time.offset_seconds
	w3.load_game()
	_check(w3.family.invited_today("alyona", "harvest") and w3.family.dined_today(), "誘った記録と夕食の記録は読み直しても残る(同じ日に 2 回は誘えない)")
	_check(wk.kitchen.pots[0].get("helped", false) == false and wk.kitchen.pots[0].get("recipe", "") == "sauce", "鍋の記録も読み直せる")

func _test_save() -> void:
	print("セーブ")
	var w := _world()
	var f := w.family
	f.choose("vera", 2)
	w.time.shift_days(Family.AGE_DAYS * 2)
	f.help_today()
	f.talk("masha")
	var tent: Vector2 = f.tent
	w.save_game()
	var w2 := GameWorld.new()
	w2.save_path = TEST_SAVE
	w2.time.offset_seconds = w.time.offset_seconds
	w2.load_game()
	var f2 := w2.family
	_check(f2.chosen and f2.members.size() == 3, "家族を読み直せる")
	_check(f2.spouse().name == "ヴェーラ", "配偶者の名前")
	_check(f2.age_of(f2.member("vanya")) == 11 and f2.age_of(f2.member("masha")) == 8, "育った年齢のまま(11 歳と 8 歳)")
	_check(f2.tent != null and f2.tent.is_equal_approx(tent), "テントの場所")
	_check(f2.talked_today("masha") and f2.helped_day == f.helped_day, "話した日・手伝った日")
	_check(not f2.help_today(), "読み直しても、同じ日にもう一度は手伝わない")
	var text := FileAccess.get_file_as_string(TEST_SAVE)
	_check(text.contains("\"family\""), "セーブに family がある")
	# 家族の記録がない古いセーブ
	var data: Dictionary = JSON.parse_string(text)
	data.erase("family")
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var w3 := GameWorld.new()
	w3.save_path = TEST_SAVE
	w3.load_game()
	_check(not w3.family.chosen and w3.family.members.is_empty(), "家族の記録がないセーブは、まだ決めていない")
	# 壊れた記録は読み飛ばす
	data["family"] = {"chosen": true, "members": [{"id": "alyona"}, {"id": "alyona"}, {"id": "ghost"}, "x", {"id": "polya", "age": "abc"}], "talked": {"ghost": 3}, "tent": "bad"}
	file = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var w4 := GameWorld.new()
	w4.save_path = TEST_SAVE
	w4.load_game()
	var ids: Array = w4.family.members.map(func(m): return m.id)
	_check(ids == ["alyona", "polya"], "知らない人・同じ人・形の違う記録は読み飛ばす(%s)" % str(ids))
	_check(not w4.family.talked.has("ghost"), "知らない人の話した日は読まない")

func _test_picker() -> void:
	print("家族を選ぶ画面")
	var picker := FamilyPicker.new()
	root.add_child(picker)
	var got := []
	picker.chosen.connect(func(c): got.append(c))
	picker.open()
	_check(picker.visible and picker.step == "spouse", "はじめは配偶者を選ぶ")
	_check(picker.button_texts() == ["アリョーナ(妻)", "ヴェーラ(妻)", "イリヤ(夫)", "ミハイル(夫)", "配偶者はいない"], "配偶者 4 人と「いない」")
	picker.press("イリヤ(夫)")
	_check(picker.step == "spouse_name" and picker.spouse == "ilya", "次は配偶者の名前")
	_check(picker.name_text() == "イリヤ", "名前の欄には、はじめの名前が入っている")
	picker.type_name("  たろう ")
	picker.press("次へ")
	_check(picker.step == "children" and picker.spouse_name == "たろう", "名前を付けて次へ(前後の空白は取る)")
	_check(picker.button_texts() == ["子どもはいない", "1人", "2人", "3人", "← 配偶者を選び直す"], "子どもは 0〜%d 人" % Family.MAX_CHILDREN)
	picker.press("2人")
	_check(picker.step == "child" and picker.child_index == 0, "1 人ずつ決める")
	_check(picker.name_text() == "ワーニャ" and picker.age_text() == "9歳", "1 人目は ワーニャ 9 歳(息子)から")
	picker.set_sex("f")
	_check(picker.name_text() == Family.default_name(0, "f") and picker.kids[0].sex == "f", "娘にすると、決まった名前も娘の名前になる")
	picker.type_name("はな")
	picker.set_sex("m")
	_check(picker.name_text() == "はな", "自分で付けた名前は、息子/娘を変えても残る")
	picker.set_sex("f")
	for _i in range(5):
		picker.change_age(-1)
	_check(picker.age_text() == "4歳", "年齢を下げられる")
	for _i in range(30):
		picker.change_age(1)
	_check(picker.age_text() == "%d歳" % Family.MAX_START_AGE, "年齢は %d 歳まで" % Family.MAX_START_AGE)
	for _i in range(30):
		picker.change_age(-1)
	_check(picker.age_text() == "0歳", "年齢は 0 歳から")
	picker.change_age(7)
	picker.press("次へ")
	_check(picker.step == "child" and picker.child_index == 1 and picker.name_text() == "マーシャ", "2 人目へ(マーシャ 6 歳から)")
	picker.press("← 戻る")
	_check(picker.child_index == 0 and picker.name_text() == "はな" and picker.age_text() == "7歳", "戻ると 1 人目の決めた中身が残っている")
	picker.press("次へ")
	picker.type_name("")
	picker.press("次へ")
	_check(picker.step == "confirm", "最後に確かめる")
	var c: Dictionary = picker.choice()
	_check(c.spouse == "ilya" and c.spouse_name == "たろう", "配偶者と名前")
	_check(c.kids == [{"name": "はな", "sex": "f", "age": 7}, {"name": "マーシャ", "sex": "f", "age": 6}], "子どもの名前・娘・年齢(空の名前は決まった名前)(%s)" % str(c.kids))
	_check(FamilyPicker.describe(c).contains("夫: たろう") and FamilyPicker.describe(c).contains("娘: はな 7歳"), "家族の並びを見せる")
	picker.press("選び直す")
	_check(picker.step == "spouse" and got.is_empty(), "選び直せる")
	picker.press("配偶者はいない")
	_check(picker.step == "children", "配偶者がいなければ名前は飛ばす")
	picker.press("子どもはいない")
	_check(picker.step == "confirm" and FamilyPicker.describe(picker.choice()).contains("ひとりで暮らす"), "ひとりの暮らしも確かめられる")
	picker.press("この家族で暮らす")
	_check(got.size() == 1 and got[0] == {"spouse": "", "spouse_name": "", "kids": []} and not picker.visible, "決めると閉じて、選んだ中身を出す")
	picker.queue_free()
	# 選んだ中身で家族を決める
	var w := _world()
	var r: String = w.choose_family_custom({"spouse": "vera", "spouse_name": "ゆき", "kids": [{"name": "そら", "sex": "m", "age": 0}, {"name": "", "sex": "f", "age": 12}]})
	_check(r == "chosen", "名前・息子/娘・年齢まで決めて家族を決める")
	var f := w.family
	_check(f.spouse().name == "ゆき" and f.spouse().relation == "妻", "配偶者の名前")
	_check(f.member("vanya").name == "そら" and f.member("vanya").relation == "息子" and f.age_of(f.member("vanya")) == 0, "1 人目: そら(息子 0 歳)")
	_check(f.member("masha").name == "マーシャ" and f.member("masha").relation == "娘" and f.age_of(f.member("masha")) == 12, "2 人目: 空の名前は決まった名前(娘 12 歳)")

func _test_custom_rules() -> void:
	print("名前と年齢の決まり")
	var long_name := "あいうえおかきくけ"
	_check(_world().choose_family_custom({"spouse": "alyona", "spouse_name": long_name, "kids": []}) == "too_long", "%d 文字をこえる名前は付けられない" % Family.NAME_MAX)
	_check(_world().choose_family_custom({"spouse": "", "kids": [{"name": long_name, "sex": "m", "age": 3}]}) == "too_long", "子どもも %d 文字まで" % Family.NAME_MAX)
	_check(_world().choose_family_custom({"spouse": "", "kids": [{"name": "a", "sex": "x", "age": 3}]}) == "unknown", "息子か娘のどちらか")
	_check(_world().choose_family_custom({"spouse": "", "kids": [{"name": "a", "sex": "m", "age": Family.MAX_START_AGE + 1}]}) == "unknown", "年齢は %d 歳まで" % Family.MAX_START_AGE)
	_check(_world().choose_family_custom({"spouse": "", "kids": [{"name": "a", "sex": "m", "age": -1}]}) == "unknown", "年齢は 0 歳から")
	_check(_world().choose_family_custom({"spouse": "", "kids": [{}, {}, {}, {}]}) == "unknown", "子どもは %d 人まで" % Family.MAX_CHILDREN)
	_check(Family.clean_name(" a\nb\t ") == "ab", "名前の改行・タブ・前後の空白は取る")
	# 付け直す
	var w := _world()
	var f := w.family
	f.choose("mikhail", 1)
	_check(f.rename("mikhail", "けん") == "renamed" and f.spouse().name == "けん", "配偶者の名前を付け直せる")
	_check(f.rename("vanya", "  りく  ") == "renamed" and f.member("vanya").name == "りく", "子どもの名前を付け直せる")
	_check(f.rename("vanya", "りく") == "same", "同じ名前なら変わらない")
	_check(f.rename("vanya", "   ") == "empty" and f.member("vanya").name == "りく", "空にはできない(今の名前のまま)")
	_check(f.rename("vanya", long_name) == "too_long", "長すぎる名前は付けられない")
	_check(f.rename("masha", "x") == "unknown", "いない人は付け直せない")
	_check(f.member("vanya").relation == "息子" and f.age_of(f.member("vanya")) == 9, "名前を変えても、息子/娘と年齢は変わらない")
	# 付け直した名前と、息子/娘はセーブに残る
	var w2 := _world()
	w2.choose_family_custom({"spouse": "alyona", "spouse_name": "はるか", "kids": [{"name": "めい", "sex": "f", "age": 5}]})
	w2.family.rename("alyona", "ちはる")
	w2.save_game()
	var w3 := GameWorld.new()
	w3.save_path = TEST_SAVE
	w3.time.offset_seconds = w2.time.offset_seconds
	w3.load_game()
	_check(w3.family.spouse().name == "ちはる", "付け直した名前を読み直せる")
	var kid: Dictionary = w3.family.member("vanya")
	_check(kid.name == "めい" and kid.sex == "f" and kid.relation == "娘" and w3.family.age_of(kid) == 5, "1 人目の娘 めい 5 歳を読み直せる")
	# 名前が壊れていたら決まった名前
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	data.family.members[0].name = ""
	data.family.members[1].name = long_name
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var w4 := GameWorld.new()
	w4.save_path = TEST_SAVE
	w4.load_game()
	_check(w4.family.spouse().name == "アリョーナ" and w4.family.member("vanya").name == Family.default_name(0, "f"), "読めない名前は決まった名前にする")
