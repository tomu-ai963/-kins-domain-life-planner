extends RefCounted

# ── 家族と話す画面と、一緒にする作業(3D だけ)。文言・名前・話す・誘う・HUD の行 ──
# Main.gd から分けた(レビュー C4)。Main が 1 つ持ち(Main.family_talk)、main を通して world・HUD・ほかの画面を使う
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

# 話しかけたときの言葉。配偶者はいつもの言葉と季節の言葉、子どもは年齢で変わる
const FAMILY_SPOUSE_CHATS := [
	"畑の野菜、よく育ってるね。
水やりは任せて。",
	"朝の水汲み、いい運動になるよ。",
	"この土地、少しずつ私たちの場所になってきたね。",
	"{呼}無理しないでね。
お昼はちゃんと食べること。",
]
const FAMILY_SPOUSE_SEASON := {
	"spring": "春の土の匂いがする。
今年は何をまこうか。",
	"summer": "日が長いね。
夕方の水やりが気持ちいい。",
	"autumn": "実りの季節だね。
冬の支度もしなくちゃ。",
	"winter": "寒いね。
薪は足りてる?",
}
const FAMILY_SPOUSE_TENT := "テント暮らしも悪くないけど、
小屋ができるのが楽しみ。"
const FAMILY_CHILD_SMALL := ["{親}見て見て!
ダンゴムシ!", "おなかすいた。
おやつある?", "だっこして!", "あのね、
鳥さんがいたの!"]
const FAMILY_CHILD := [
	"{親}雑草、いっぱい抜いたよ!",
	"あの木、このあいだより大きくなった!",
	"鳥の巣を見つけたんだ。
ないしょだよ。",
	"大きくなったら、自分の木を植えるんだ。",
]
const FAMILY_CHILD_TEEN := ["畑のことなら、もう任せてよ。", "いつか、この土地を守るのは自分だと思ってる。", "町の学校の話、聞く?
でも、ここがいちばん落ち着く。"]
const FAMILY_TEEN_AGE := 13
# 話す画面に出す誘い(2026-11-18 とむ決定: 収穫・料理・夕食。得は少しだけ)
const FAMILY_INVITES := {
	"harvest": "一緒に収穫しよう(となりの区画も採ってくれる)",
	"cook": "一緒に料理しよう(仕込むと 2 割多くできる)",
	"dinner": "みんなで夕食にしよう(翌朝の手伝いが増える)",
	"explore": "生き物を探しに行こう(見つけると生き物と仲良くなる)",
	"seeds": "外の林へ種を拾いに行こう(一緒に拾ってくれる)",
	"rice": "一緒に田植えしよう(となりの田んぼにも植えてくれる)",
	"snow": "一緒に雪かきしよう(横の雪もどかしてくれる)",
	"mill": "一緒に石臼を回そう(今日挽ける量が 2 倍)",
}
const FAMILY_GIFT_SPOUSE := "{呼}%sを作ったよ。
持っていって。"
const FAMILY_GIFT_CHILD := "{親}%sを拾ったよ!
あげる!"
var _family_talk := {}       # 話している家族 {id, text}(話す画面の見出しと行に使う)

func _init(m: MainScript) -> void:
	main = m

# Y: 家族の名前を付け直す画面を開く
func _open_family_names() -> void:
	var f := world.family
	var me: String = world.profile.name if world.profile.chosen else ""
	var members: Array = f.members if f.chosen else []
	if me == "" and members.is_empty():
		hud.show_message("名前を付け直せる人がいない(自分の名前と家族は、はじめに決める)")
		return
	var ages := {}
	for m in members:
		ages[m.id] = f.age_of(m)
	main.get_node("Player").set_physics_process(false)  # 名前を打つあいだは歩かない
	hud.open_family_names(members, ages, me)

func _on_family_renamed(names: Dictionary) -> void:
	main.get_node("Player").set_physics_process(true)
	var f := world.family
	var changed := PackedStringArray()
	for id in names:
		if id == "self":
			var old_name: String = world.profile.name
			if world.profile.rename(str(names[id])) == "renamed":
				changed.append("%s → %s" % [old_name, world.profile.name])
			continue
		var before: String = f.member(id).get("name", "")
		if f.rename(id, str(names[id])) == "renamed":
			changed.append("%s → %s" % [before, f.member(id).name])
	if changed.is_empty():
		hud.show_message("名前はそのまま")
	else:
		hud.show_message("名前を付け直した(%s)" % "、".join(changed), 5.0)

# 足元から話せる家族の id。いなければ ""
func family_near() -> String:
	if not main.has_node("Family"):
		return ""
	return main.get_node("Family").talkable(main.player_pos())

# その人の今日の言葉
func family_chat(id: String) -> String:
	var f := world.family
	var m: Dictionary = f.member(id)
	var lines := []
	if m.role == "spouse":
		lines = FAMILY_SPOUSE_CHATS.duplicate()
		lines.append(FAMILY_SPOUSE_SEASON.get(world.forest.season, ""))
		if f.has_tent():
			lines.append(FAMILY_SPOUSE_TENT)
	else:
		var age: int = f.age_of(m)
		if age < f.HELP_AGE:
			lines = FAMILY_CHILD_SMALL
		elif age < FAMILY_TEEN_AGE:
			lines = FAMILY_CHILD
		else:
			lines = FAMILY_CHILD_TEEN
	return main.with_call(lines[f.line_index(id) % lines.size()], m.role)

# 贈り物の名前: 「ブリヌイ 3枚」「白樺の種 2つ」
func family_gift_text(g: Dictionary) -> String:
	if g.type == "tree_seed":
		return "%sの種 %dつ" % [world.forest.SPECIES[g.species].name, int(g.count)]
	return main._amount_text(g.item, int(g.count))

func _talk_family(id: String) -> void:
	var f := world.family
	var m: Dictionary = f.member(id)
	var result: String = f.talk(id)
	main.get_node("Family").greet(id)
	var text := "「%s」" % family_chat(id)
	if result == "gift":
		var gift := family_gift_text(f.last_gift)
		var said: String = main.with_call((FAMILY_GIFT_SPOUSE if m.role == "spouse" else FAMILY_GIFT_CHILD) % gift, m.role)
		text = "「%s」\n(%sをもらった)" % [said, gift]
		main._sfx("coin")
	else:
		main._sfx("open")
	# 話す画面: 言葉と、「一緒に○○しよう」の誘い(2026-11-18 とむ決定)
	_family_talk = {"id": id, "text": text}
	main._panel = "family"
	main.get_node("Player").set_physics_process(false)
	hud.open_shop()

# 話す画面の行: そのときに誘える作業と「またね」
func family_rows() -> Array:
	var f := world.family
	var id: String = _family_talk.get("id", "")
	var rows := []
	for kind in FAMILY_INVITES:
		if f.invite_problem(id, kind) == "":
			rows.append({"id": "invite_" + kind, "text": FAMILY_INVITES[kind], "column": 0})
	rows.append({"id": "close", "text": "またね(C / Esc)", "column": 0})
	return rows

# 誘う。断られたとき(暗い・収穫できる区画がない)も、その人の言葉で知らせる
func _family_action(action: String) -> void:
	var f := world.family
	var id: String = _family_talk.get("id", "")
	var m: Dictionary = f.member(id)
	var kind := action.trim_prefix("invite_")
	if m.is_empty() or not FAMILY_INVITES.has(kind):
		return
	var line := ""
	match kind:
		"harvest":
			if main.get_node("Family").is_night():
				line = "もう暗いから、収穫は明日にしよう。"
			elif not f.any_ripe():
				line = "収穫できる畑は、まだないみたい。\n実ったら呼んでね。"
		"dinner":
			if not main.get_node("Family").is_night():
				line = "夕ごはんは、暗くなってからにしよう。"
		"explore":
			if main.get_node("Family").is_night():
				line = "暗いから、生き物探しはまた明日ね。"
		"rice", "snow", "mill":
			if main.get_node("Family").is_night():
				line = "暗いから、%sは明日にしよう。" % {"rice": "田植え", "snow": "雪かき", "mill": "石臼"}[kind]
			elif kind == "rice" and int(world.garden.seeds.get("rice", 0)) <= 0:
				line = "稲の苗がないみたい。\n(市場で買える)"
		"seeds":
			if main.get_node("Family").is_night():
				line = "暗いから、外の林はまた明日ね。"
			elif f.wild_pickups().is_empty():
				line = "今日は外の林に、種が落ちてないみたい。"
				var next: Dictionary = f.next_wild_drop()
				if not next.is_empty():
					var date: String = world.forest.date_of_day(int(next.day))
					line += "\n%d月%d日に%sの種が落ちるよ。" % [int(date.substr(5, 2)), int(date.substr(8, 2)), world.forest.SPECIES[next.species].name]
	if line == "":
		if f.invite(id, kind) != "invited":
			return
		match kind:
			"harvest":
				main.get_node("Family").start_invite(id, "harvest")
				line = "うん! 採るの得意だよ!" if m.role == "child" else "いいよ、一緒に採ろう。"
				line += "\n(ついてきて、となりの区画を採ってくれる)"
			"cook":
				main.get_node("Family").start_invite(id, "cook")
				line = "いいね。ストーブの前で待ってるね。\n(ストーブかかまどで仕込むと、一緒に作ってくれる)"
			"dinner":
				main.get_node("Family").start_dinner()
				line = "ごはんにしよう。みんな、座って!\n(テーブルの東の腰掛けで H を押して食べる)"
			"explore":
				main.get_node("Family").start_invite(id, "explore")
				line = "うん! いっぱい見つけるね!"
				var missing: Array = world.quests.guide_missing()
				if not missing.is_empty():
					line += "\nまだ見てない%sに会いたいな。" % main._creature_name(missing[0])
				line += "\n(ついてきて、近くの生き物を教えてくれる)"
				if not missing.is_empty():
					line += "\n(図鑑のヒント: %s)" % main.local_text(Msg.GUIDE_HINTS[missing[0]])
			"seeds":
				main.get_node("Family").start_invite(id, "seeds")
				line = "外の林だね! 一緒に拾おう!\n(ついてきて、近くに落ちている種を拾ってくれる)"
			"rice":
				main.get_node("Family").start_invite(id, "rice")
				line = "うん、田植えしよう! 泥んこになるぞ!" if m.role == "child" else "いいよ。田植えは二人のほうが早いね。"
				line += "\n(ついてきて、となりの空いた田んぼにも苗を植えてくれる)"
			"snow":
				main.get_node("Family").start_invite(id, "snow")
				line = "まかせて! 道を広くしよう。\n(横に並んで、となりの雪もどかしてくれる。U を押したまま歩く)"
			"mill":
				var before: int = world.mill.hand_limit()
				world.mill.add_helper()
				main.get_node("Family").start_invite(id, "mill")
				line = "いいよ、二人で回そう。\n(石臼のそばで待っている。今日手で挽ける量 %dkg → %dkg)" % [before, world.mill.hand_limit()]
	main._close_shop()
	hud.show_message("%s「%s」" % [m.name, main.with_call(line, m.role)], 6.0)

# 子どもが生き物を見つけて教えてくれた(生き物探し。2026-11-18)。今日はじめての種類なら仲良し度が上がる
func _on_family_spotted(id: String, creature: String) -> void:
	var m: Dictionary = world.family.member(id)
	var gain: int = world.family.spot_creature(creature)
	var note: String = "\n(生き物との仲良し度 +%d → %d)" % [gain, world.pests.friendship] if gain > 0 else ""
	hud.show_message("%s「あそこ! %sがいるよ!」%s" % [m.get("name", ""), main._creature_name(creature), note], 5.0)

# 一緒に田植えしている家族が、近くの空いた田んぼに 1 人 1 つ苗を植える(苗は自分の持ち物から。2026-11-18)。知らせの文言を返す
func _family_rice(done: Vector2) -> String:
	if not main.has_node("Family"):
		return ""
	var g := world.garden
	var taken := [done]
	var names := PackedStringArray()
	for id in main.get_node("Family").harvest_helpers("rice"):
		if int(g.seeds.get("rice", 0)) <= 0:
			break
		var plot = world.family.empty_paddy_near(done, world.family.HARVEST_REACH, taken)
		if plot == null:
			break
		if g.sow(plot, "rice") != "sown":
			continue
		taken.append(plot)
		main.get_node("Family").help_pick(id, plot, "plant")
		names.append(world.family.member(id).name)
	if names.is_empty():
		return ""
	return "\n%sも、となりの田んぼに植えてくれた(稲の苗 残り %d)" % ["・".join(names), int(g.seeds.get("rice", 0))]

# 一緒に雪かきしている家族が、自分の足元(横に並んだところ)の雪もどかす(2026-11-18)
func _family_snow() -> void:
	if not main.has_node("Family"):
		return
	for id in main.get_node("Family").harvest_helpers("snow"):
		var at: Vector2 = main.get_node("Family").person_pos(id)
		if world.snow.clear_at(at) == "cleared":
			main.get_node("Family").play_action(id, "shovel")

# 一緒に収穫している家族が、足元の近くの収穫できる区画を 1 人 1 つ採る(2026-11-18)。知らせの文言を返す
func _family_harvest(done: Vector2, pos: Vector2) -> String:
	if not main.has_node("Family"):
		return ""
	var g := world.garden
	var taken := [done]
	var parts := PackedStringArray()
	for id in main.get_node("Family").harvest_helpers():
		var plot = world.family.ripe_near(pos, world.family.HARVEST_REACH, taken)
		if plot == null:
			break
		var crop: Dictionary = g.crop_at(plot)
		if g.harvest_at(plot) != "harvested":
			continue
		taken.append(plot)
		main.get_node("Family").help_pick(id, plot)
		parts.append("%sが%sを%dkg" % [world.family.member(id).name, g.CROPS[crop.kind].name, g.last_harvest_kg])
	return "" if parts.is_empty() else "\n%s採ってくれた" % "、".join(parts)

# 朝の手伝いの知らせ(日記の 1 日のはじめに出す)
func family_help_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var f := world.family
	var summary: Dictionary = f.help_summary()
	for m in f.members:
		if not summary.has(m.id):
			continue
		var h: Dictionary = summary[m.id]
		if h.water > 0:
			out.append("朝、%sが畑と木に %dか所 水をやってくれた" % [m.name, h.water])
		if h.weed > 0:
			out.append("朝、%sが雑草を %d区画 抜いてくれた" % [m.name, h.weed])
	return out

# 持ち物に出す、家族の並びと住まい
func family_line() -> String:
	var f := world.family
	if not f.chosen:
		return "まだ決めていない"
	if f.members.is_empty():
		return "ひとりで暮らしている"
	var parts := PackedStringArray()
	for m in f.members:
		if m.role == "spouse":
			parts.append("%s(%s)" % [m.name, m.relation])
		else:
			parts.append("%s(%s %d歳)" % [m.name, m.relation, f.age_of(m)])
	var home := "テントで休む(小屋が完成すると小屋で)" if f.has_tent() else "小屋で暮らす"
	return "%s  %s" % ["・".join(parts), home]

# 外の林で一緒に種拾いしている子どもが、近くに落ちている種を 1 人 1 つ拾う(2026-11-18)。知らせの文言を返す
func _family_seeds() -> String:
	if not main.has_node("Family") or not world.forest.is_outside_land(main.player_pos()):
		return ""
	var parts := PackedStringArray()
	for id in main.get_node("Family").seeds_helpers():
		var pk: Dictionary = world.family.wild_pickup_near(main.player_pos(), world.family.SEEDS_REACH)
		if pk.is_empty():
			break
		var got: Array = world.forest.collect_near(pk.pos, 0.01)
		if got.is_empty():
			continue
		main.get_node("Family").help_pick(id, pk.pos)
		for g in got:
			parts.append("%sも%sの種を拾った(+%d)" % [world.family.member(id).name, world.forest.SPECIES[g.species].name, g.amount])
	return "" if parts.is_empty() else "\n" + "\n".join(parts)
