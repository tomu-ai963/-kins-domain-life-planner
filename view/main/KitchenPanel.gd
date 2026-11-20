extends RefCounted

# ── 小屋の中の画面: ストーブとかまど・テーブルと腰掛け・揺り椅子・ベッドと日記 ──
# Main.gd から分けた(レビュー C4)。Main が 1 つ持ち(Main.kitchen_panel)、main を通して world・HUD・ほかの画面を使う
const MainScript = preload("res://Main.gd")
const GameWorld = preload("res://logic/GameWorld.gd")
const Msg = preload("res://view/main/Messages.gd")

var main: MainScript
var world: GameWorld:
	get:
		return main.world
var hud: Node:
	get:
		return main.get_node("HUD")

const POT_NAMES := ["鍋", "かまどの鍋"]      # 母屋のストーブの鍋 / 増築した部屋のかまどの鍋
const POT_PLACES := ["ストーブ", "かまど"]
# ストーブと腰掛けの画面のページ(料理が増えて 1 列 15 行を超えるため分けた。材料が果物かはちみつか、野菜か)
const COOK_PAGES := ["果物とはちみつ", "野菜", "穀物と粉"]
var _cook_page := 0          # ストーブと腰掛けの画面の今のページ(COOK_PAGES)

func _init(m: MainScript) -> void:
	main = m

# 台所の画面を開く。pot: 0 = 母屋のストーブ、1 = 増築した部屋のかまど
func _open_kitchen(pot := 0) -> void:
	world.kitchen.active = pot
	main._panel = "kitchen"
	main._sfx("open")
	main.get_node("Player").set_physics_process(false)  # 料理中は歩かない
	hud.open_shop()

func kitchen_rows() -> Array:
	var k := world.kitchen
	var rows := [_cook_page_row("料理", func(p): return k.RECIPES.keys().filter(func(id): return _cook_page_of(id) == p and _recipe_shown(id)).size())]
	for id in k.RECIPES:
		if not _recipe_shown(id):
			continue
		var r: Dictionary = k.RECIPES[id]
		rows.append({"id": "cook_" + id, "text": "仕込む: %s(%s → %d%s・%d日)持っている %d%s" % [
			r.name, main._amount_text(r.input, r.amount), r.output, r.unit, r.days, k.input_count(id), main.produce_unit(r.input),
		], "column": 0, "page": _cook_page_of(id)})
	var where: String = POT_NAMES[k.active]
	if k.is_empty():
		rows.append({"id": "pot_wait", "text": "%sは空いている" % where, "column": 1})
	elif k.is_ready():
		var r: Dictionary = k.RECIPES[k.pot.recipe]
		rows.append({"id": "pot_collect", "text": "受け取る: %s %d%s" % [r.name, r.output, r.unit], "column": 1})
	else:
		rows.append({"id": "pot_wait", "text": "%s: %s あと%d日" % [where, k.RECIPES[k.pot.recipe].name, k.days_left()], "column": 1})
	rows.append({"id": "close", "text": "閉じる(H / Esc)", "column": 1})
	return rows

func _kitchen_action(id: String) -> void:
	var k := world.kitchen
	if id == "page_cook":
		_cook_page = (_cook_page + 1) % COOK_PAGES.size()
	elif id == "pot_collect":
		if k.collect() == "collected":
			var made: Dictionary = k.last_collected
			var r: Dictionary = k.RECIPES[made.recipe]
			var together: String = "。一緒に作ったぶん +%d%s" % [made.extra, r.unit] if int(made.get("extra", 0)) > 0 else ""
			hud.show_message("%sが%d%sできた(%s%s)" % [r.name, made.count, r.unit, _preserve_price_text(made.recipe, r.unit), together], 5.0)
	elif id.begins_with("cook_"):
		var recipe := id.trim_prefix("cook_")
		var r: Dictionary = k.RECIPES[recipe]
		var helper: String = main.get_node("Family").cook_helper() if main.has_node("Family") else ""
		match k.start(recipe, helper != ""):
			"started":
				var together := ""
				if helper != "":
					main.get_node("Family").cook_with(helper)
					together = "\n%sが横で鍋をかき混ぜてくれた(できる数 +%d%s)" % [world.family.member(helper).name, k.help_extra(recipe), r.unit]
				hud.show_message("%sを仕込んだ(%d日でできる・薪 -1回分)%s" % [r.name, r.days, together], 5.0)
			"busy":
				hud.show_message("%sは使っている(受け取ってから次を仕込む)" % POT_NAMES[k.active])
			"no_input":
				hud.show_message("%sが足りない(%d%s 必要)" % [main.produce_name(r.input), r.amount, main.produce_unit(r.input)])
			"no_wood":
				hud.show_message("薪がない(小屋の東の薪割り台で、H で丸太を割る)", 5.0)
	hud.refresh_shop()

# 揺り椅子に座って揺れる(見て楽しむだけ)。H / Esc で立つ
func _sit_chair() -> void:
	main._panel = "chair"
	main._sfx("open")
	main.get_node("Player").set_physics_process(false)
	if main.get_node("Player").has_method("sit_down"):  # 3D だけ
		main.get_node("Player").sit_down(main.get_node("Cabin").chair_seat_spot(), main.get_node("Cabin").CHAIR_YAW)
		main.get_node("Player").set_rocking(true)
		main.get_node("Cabin").set_rocking(true)
	hud.open_shop()

# 腰掛けに座って、テーブルの保存食を 1 つ食べる。食べた日は少し速く歩ける
func _open_table() -> void:
	main._panel = "table"
	main._sfx("open")
	main.get_node("Player").set_physics_process(false)  # 座っているあいだは歩かない
	if main.get_node("Player").has_method("sit_down"):  # 3D だけ
		main.get_node("Player").sit_down(main.get_node("Cabin").seat_spot(), main.get_node("Cabin").SIT_YAW)
	hud.open_shop()

func table_rows() -> Array:
	var k := world.kitchen
	var rows := []
	var held: Array = k.RECIPES.keys().filter(func(id): return main.produce_count(id) > 0)
	if not held.is_empty():
		rows.append(_cook_page_row("食べる", func(p): return held.filter(func(id): return _cook_page_of(id) == p).size()))
	for id in k.RECIPES:
		var n := main.produce_count(id)
		if n > 0:
			var r: Dictionary = k.RECIPES[id]
			var verb := "今日は食べた" if id in k.eaten_today() else "食べる"
			var effect: String = k.MEALS[r.meal].short
			if verb == "食べる" and k.has_effect(r.meal):
				effect = "もう効いている"
			rows.append({"id": "eat_" + id, "text": "%s: %s %d%s → %s(1%s %d₽)" % [verb, r.name, n, r.unit, effect, r.unit, world.market.sell_price(id)], "column": 0, "page": _cook_page_of(id)})
	if rows.is_empty():
		rows.append({"id": "no_food", "text": "テーブルに保存食がない(ストーブで作る)", "column": 0})
	rows.append({"id": "close", "text": "立つ(H / Esc)", "column": 1})
	return rows

func _table_action(id: String) -> void:
	if id == "page_cook":
		_cook_page = (_cook_page + 1) % COOK_PAGES.size()
		hud.refresh_shop()
		return
	if not id.begins_with("eat_"):
		return
	var k := world.kitchen
	var food := id.trim_prefix("eat_")
	var was_active: bool = k.RECIPES.has(food) and k.has_effect(k.RECIPES[food].meal)
	match k.eat(food):
		"eaten":
			if main.get_node("Player").has_method("eat_motion"):
				main.get_node("Player").eat_motion()
			var meal: Dictionary = k.MEALS[k.RECIPES[food].meal]
			var note: String = "同じ「%s」の効果はもう効いている" % meal.name if was_active else "「%s」で今日は%s" % [meal.name, meal.short]
			if main.has_node("Family") and main.get_node("Family").dinner_seated():  # みんなで夕食(2026-11-18)
				world.family.dine_together()
				main.get_node("Family").dinner_eat()
				note += "\nみんなで食べた。明日の朝の手伝いが増える"
			hud.show_message("%sを食べた。%s" % [k.RECIPES[food].name, note], 5.0)
		"same":
			hud.show_message("%sは今日もう食べた(同じものは1日1つまで)" % k.RECIPES[id.trim_prefix("eat_")].name)
		"full":
			hud.show_message("今日はもうお腹いっぱい(1日%d種類まで)" % k.MEAL_KINDS)
	hud.refresh_shop()

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
	var parts := PackedStringArray()
	for i in range(k.pots.size()):
		var text: String = k.with_pot(i, func(): return _pot_text(i))
		if text != "":
			parts.append(text)
	return "  ".join(parts)

# 鍋 1 つ(k.active)の様子。空なら ""
func _pot_text(i: int) -> String:
	var k := world.kitchen
	if k.is_empty():
		return ""
	var recipe: String = k.RECIPES[k.pot.recipe].name
	if k.is_ready():
		return "%s: %s できた(%sの前で H)" % [POT_NAMES[i], recipe, POT_PLACES[i]]
	return "%s: %s あと%d日" % [POT_NAMES[i], recipe, k.days_left()]

# HUD に出す、食事の 1 行。今日まだ食べていなければ ""
func meal_line() -> String:
	var k := world.kitchen
	return "食事(%d/%d種類): %s" % [k.eaten_today().size(), k.MEAL_KINDS, _effects_text()] if not k.eaten_today().is_empty() else ""

# 今日効いている効果の文言。例: 「速く歩ける・収穫が増える」
func _effects_text() -> String:
	var k := world.kitchen
	var parts := PackedStringArray()
	for m in k.active_effects():
		parts.append(k.MEALS[m].short)
	return "・".join(parts)

# ストーブと腰掛けの料理のページ
func _cook_page_of(id: String) -> int:
	if world.kitchen.from_grain(id):
		return 2
	return 0 if world.kitchen.from_tree(id) else 1

# ストーブの画面に並べる料理: この土地で材料が採れるか、材料かできた品を持っている
func _recipe_shown(id: String) -> bool:
	var k := world.kitchen
	return k.grows_here(id) or k.input_count(id) > 0 or int(k.stock[id]) > 0

# ページの行(ストーブ・腰掛け)。count_of: そのページの数え方
func _cook_page_row(verb: String, count_of: Callable) -> Dictionary:
	var next: int = (_cook_page + 1) % COOK_PAGES.size()
	return {"id": "page_cook", "text": "%s: %s(押すと次: %s %d種類)" % [verb, COOK_PAGES[_cook_page], COOK_PAGES[next], count_of.call(next)], "column": 0}

# 現実の時間で進むゲームなので、寝ても時間は進まない。横になってから暗くなり、今日と明日のことを日記で見る
func _sleep() -> void:
	world.save_game()
	main.get_node("Player").set_physics_process(false)
	var delay := 0.0
	if main.get_node("Player").has_method("lie_down"):  # 3D だけ
		delay = main.get_node("Player").LIE_SECONDS
		if main.has_node("Family") and world.family.is_in_tent(main.player_pos()):  # テントの寝袋で
			main.get_node("Player").lie_down(main.get_node("Family").player_lying_spot(), main.get_node("Family").TENT_LYING_BASIS)
		else:
			main.get_node("Player").lie_down(main.get_node("Cabin").lying_spot())
			main.get_node("Cabin").set_sleeping(true, delay * 0.7)
	hud.open_diary(diary_text(), delay + 0.5)

func _wake() -> void:
	hud.close_diary()
	main.get_node("Player").set_physics_process(true)
	if main.get_node("Player").has_method("get_up"):
		main.get_node("Player").get_up()
		main.get_node("Cabin").set_sleeping(false)

func diary_text() -> String:
	var f := world.forest
	var g := world.garden
	var today: String = f.today()
	var who := (" %s" % world.profile.name) if world.profile.chosen else ""
	var lines := PackedStringArray(["%d月%d日%sの日記" % [int(today.substr(5, 2)), int(today.substr(8, 2)), who], ""])
	var todo := PackedStringArray()
	if f.last_day == today and f.today_event != "":
		todo.append(main.daily_message(f.today_event))
	var now: Dictionary = g.today_counts()
	if now.ripe > 0:
		todo.append("収穫できる区画が %d ある" % now.ripe)
	if now.dry > 0:
		todo.append("まだ水をやっていない区画が %d ある" % now.dry)
	if world.seedlings.needs_care():
		todo.append("苗の世話がまだ")
	if main.has_node("Visitor") and world.visitors.has_request():
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
	lines.append_array(main._bullets(todo, "やり残したことはない"))
	lines.append("")
	lines.append("明日")
	lines.append_array(main._bullets(_tomorrow_lines(), "ゆっくりできそう"))
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
		lines.append("%sになりそう(水やりはいらない)" % ("雪" if main.is_snow_day(season) else "雨"))
	if g.frost_is_near(world.forest.today()):
		lines.append("%sの霜が近い(霜に弱い野菜は早めに収穫を)" % g.frost_date_text())
	var wild_drops: Array = world.wilds.dropping_on(world.forest.day_number() + 1)
	if not wild_drops.is_empty():
		lines.append("外の林で%sの種が落ちる日(その日だけ拾える)" % main._names_of(wild_drops))
	if plan.ripe > 0:
		lines.append("収穫できる区画: %d" % plan.ripe)
	if plan.spoiling > 0:
		lines.append("傷みはじめる区画: %d" % plan.spoiling)
	var to_water: int = g.crops.size() - plan.ripe
	if to_water > 0 and not rain:
		lines.append("水やりがいる区画: %d" % to_water)
	var fruiting: int = world.forest.ripe_fruit_count(season, 1)
	if fruiting > 0:
		lines.append("果物を収穫できる木: %d本" % fruiting)
	var pots: int = world.seedlings.grown_tomorrow()
	if pots > 0:
		lines.append("苗を受け取れる: %d鉢" % pots)
	var k := world.kitchen
	var pot_count: int = 2 if world.cabin.has_extension() else 1
	for i in range(pot_count):
		var line: String = k.with_pot(i, func():
			if k.ready_tomorrow():
				return "%sの%sを受け取れる" % [POT_NAMES[i], k.RECIPES[k.pot.recipe].name]
			return "%sが空いている" % POT_NAMES[i] if k.is_empty() else "")
		if line != "":
			lines.append(line)
	if world.bees.ready_tomorrow() > 0:
		lines.append("はちみつが採れる巣箱: %d" % world.bees.ready_tomorrow())
	if world.visitors.is_visit_day(world.forest.day_number() + 1):
		lines.append("%sが来そう" % world.visitors.CAST[world.visitors.who_on(world.forest.day_number() + 1)].name)
	return lines
