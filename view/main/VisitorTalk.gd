extends RefCounted

# ── 訪ねてくる人と話す画面(3D だけ)。文言・話す画面の行・選んだとき・HUD の 1 行 ──
# Main.gd から分けた(レビュー C4)。Main が 1 つ持ち(Main.visitor_talk)、main を通して world・HUD・ほかの画面を使う
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

# 話すだけの日の言葉。{tomorrow} は明日の空模様に置き換える
const VISITOR_CHATS := {
	"nina": [
		"区画はお金がいらないけど、耕すのは1日2区画まで。\n欲張らず少しずつね。",
		"{呼}水をやった日は1日ぶん、やらない日は半日ぶん育つよ。\n毎日見てあげて。",
		"冬が来る前に、ニンニク以外は収穫しておくんだよ。\n霜は待ってくれないからね。",
	],
	"fyodor": [
		"{呼}自分の木で丸太の巣箱を作るといい。\nくり抜いてあれば、蜂を分けてあげるよ。",
		"ミツバチは野菜の花が好きでね。\n畑が増えると、うちの蜂も喜ぶよ。",
		"木が増えると小鳥が来る。\n育った木にはリスも来るさ。",
		"丸太は育った木を伐れば手に入る。\n市場で買うと高いからね。",
	],
	"tanya": [
		"{呼}夜に畑へ行くと、ノウサギがいるんだよ!\nそっと近づいてもすぐ逃げちゃうけど。",
		"ハリネズミは逃げないの。\nじっとしてるんだよ。",
		"渡り鳥を見た?\n近づくと、みんなで飛んでっちゃうんだ。",
	],
	"pavel": [
		"{tomorrow}",
		"{呼}この先の家まで配達です。\nまた寄りますね。",
		"小屋の窓辺なら、冬でも苗が育つそうですね。\n春が楽しみだ。",
	],
}
# 親しくなると増える言葉。[顔なじみ, 親しい, 家族のよう] の順で、その段階から加わる
const VISITOR_CHATS_CLOSE := {
	"nina": [
		["このあいだの畑、よく育ってたね。\n手をかけてるのが分かるよ。", "うちの畑はね、母の代からなの。\n土は急には良くならないから。"],
		["疲れた顔をしてる。\n無理しないで、ちゃんと食べるんだよ。", "あなたが来てから、この辺りが明るくなった気がする。\n本当よ。"],
		["もう、うちの子みたいなものだね。\n困ったら、まず私に言いなさい。", "春になったら、一緒に種をまこうか。\n二人だと早いよ。"],
	],
	"fyodor": [
		["蜂はね、人の顔を覚えるそうだ。\n本当かどうかは分からんがね。", "土地を見れば、持ち主が分かるものさ。\nいい土地になってきた。"],
		["若いころは、わしも木を植えて回ったよ。\n今じゃ見上げるほどだ。", "杉は急がない木だ。\n孫の代のために植えるようなものさ。"],
		["あんたになら、蜂のことを全部教えてもいいな。\nゆっくり、少しずつな。", "わしの巣箱も、いつかあんたに任せたいものだ。\nまあ、まだ当分は元気だがね。"],
	],
	"tanya": [
		["今日ね、学校で土地の絵を描いたんだ。\nここの木も描いたよ!", "お母さんがね、ここに来るなら遅くなるなって。\nでも、まだ大丈夫!"],
		["ねえ、木の名前を教えて。\n全部覚えるから!", "大きくなったら、私もこんな土地を持つんだ。\nその時は手伝ってね。"],
		["ここにいると、うちにいるみたい。\nまた来ていい?", "秘密だよ。\nここの池のそばが、いちばん好きな場所なんだ。"],
	],
	"pavel": [
		["この道を通るのが楽しみになりました。\n土地が変わっていくのが見えるので。", "配達先で、こちらの話をよく聞かれますよ。\n評判がいいんです。"],
		["実は私も、小さな畑を持ちたいと思っていまして。\nいつか相談に乗ってください。", "仕事の合間に寄るのが、いい息抜きなんです。\nお邪魔でなければ。"],
		["遠くの町の話をしましょうか。\nでも、やはりここがいちばん落ち着きます。", "何かあれば、いつでも声をかけてください。\n荷物より先に駆けつけますよ。"],
	],
}
# 贈り物を持ってきたときの言葉
const VISITOR_GIFTS := {
	"nina": "うちの分が余ったから、%sを持ってきたの。\nもらってくれる?",
	"fyodor": "今年の蜜だ。%s持っていきなさい。\n遠慮はいらんよ。",
	"tanya": "お母さんと作ったの!\n%sあげるね!",
	"pavel": "配達の帰りに、%sを分けてもらいました。\nよろしければ使ってください。",
}
# 親しさの段階が上がったときの言葉(段階 1〜3)
const VISITOR_LEVEL_UP := ["", "%sと顔なじみになった", "%sと親しくなった", "%sと家族のような仲になった"]
const VISITOR_REQUESTS := {
	"nina": "%sを%s分けてもらえない?\nお礼に%sをあげる。",
	"fyodor": "%sを%s譲ってくれないか。\nお礼に%sを持ってきたんだ。",
	"tanya": "%sを%sちょうだい!\nかわりに%sをあげるね。",
	"pavel": "%sを%s分けていただけませんか。\nお礼に%sをお渡しします。",
}
# 冬に薪を頼むときの言葉
const VISITOR_FIREWOOD := {
	"nina": "この寒さで、うちの薪が足りなくなりそうなの。
薪を%s分けてもらえない?お礼に%sをあげる。",
	"fyodor": "冬の巣箱の番で、薪を使い切ってしまってな。
薪を%s譲ってくれないか。お礼に%sを持ってきた。",
	"tanya": "おばあちゃんちのペチカの薪がないの!
薪を%sちょうだい!かわりに%sをあげるね。",
	"pavel": "配達先のお年寄りの家で、薪が切れかけていまして。
薪を%s分けていただけませんか。お礼に%sをお渡しします。",
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
	"nina": "{呼}ありがとう、助かったよ。",
	"fyodor": "{呼}ありがたい。また来るよ。",
	"tanya": "やったあ!{呼}ありがとう!",
	"pavel": "{呼}助かりました。では、配達に戻ります。",
}

func _init(m: MainScript) -> void:
	main = m

# 「ラディッシュの種 6つ」「トマトの苗 1鉢」「260₽」
func reward_text(r: Dictionary) -> String:
	match r.type:
		"crop_seed":
			return "%s %dつ" % [world.garden.CROPS[r.kind].seed_name, r.count]
		"seedling":
			return "%sの苗 %d鉢" % [world.garden.CROPS[r.kind].name, r.count]
		"item":
			return main._amount_text(r.item, r.count)
		"firewood":
			return "薪 %d回分" % r.count
	return "%s₽" % hud._money_text(int(r.amount))

# 話すだけの日に出る言葉。親しくなった段階までの言葉が加わる
func visitor_chat_lines(who: String) -> Array:
	var lines: Array = VISITOR_CHATS[who].duplicate()
	var level: int = world.visitors.level_of(who)
	for i in range(level):
		lines.append_array(VISITOR_CHATS_CLOSE[who][i])
	return lines

# 親しさの段階が上がっていたら、その知らせ(1 回だけ)。なければ ""
func _take_level_up() -> String:
	var v := world.visitors
	if v.last_level_up == "":
		return ""
	var who: String = v.last_level_up
	v.last_level_up = ""
	return VISITOR_LEVEL_UP[v.level_of(who)] % v.CAST[who].name

# HUD の持ち物に出す、近所の人との親しさ
func neighbors_line() -> String:
	var v := world.visitors
	var parts := PackedStringArray()
	for who in v.ORDER:
		parts.append("%s %s" % [v.CAST[who].name, v.LEVEL_NAMES[v.level_of(who)]])
	return main._rows(parts, 2)

# 訪問者の言葉
func visitor_text() -> String:
	var v := world.visitors
	var who: String = v.who()
	if v.has_bees():
		return VISITOR_BEES
	if v.has_help():
		var winter: bool = v.visit.reward.type == "money"
		return VISITOR_HELP[who][1 if winter else 0] % reward_text(v.visit.reward)
	if v.has_gift():
		return VISITOR_GIFTS[who] % reward_text(v.visit.reward)
	if v.has_request():
		var item: String = v.visit.item
		if item == v.FIREWOOD:
			return VISITOR_FIREWOOD[who] % ["%d回分" % v.visit.amount, reward_text(v.visit.reward)]
		return VISITOR_REQUESTS[who] % [main.produce_name(item), "%d%s" % [v.visit.amount, main.produce_unit(item)], reward_text(v.visit.reward)]
	var lines: Array = visitor_chat_lines(who)
	var line: String = lines[int(v.visit.line) % lines.size()]
	if line == "{tomorrow}":
		var rainy: bool = world.tomorrow_rain()
		return "明日は降りそうですよ。\n水やりは休めますね。" if rainy else "明日は降らなそうです。\n畑の水やりを忘れずに。"
	return main.with_call(line)

func visitor_rows() -> Array:
	var v := world.visitors
	var rows := []
	if v.has_bees():
		rows.append({"id": "receive_bees", "text": "ありがとう(巣箱に入れてもらう)", "column": 0})
		rows.append({"id": "close", "text": "今はいい(C / Esc)", "column": 0})
	elif v.has_help() or v.has_gift():
		rows.append({"id": "receive", "text": "ありがとう(%sをもらう)" % reward_text(v.visit.reward), "column": 0})
		rows.append({"id": "close", "text": "今はいい(C / Esc)", "column": 0})
	elif v.has_request():
		var item: String = v.visit.item
		var have: int = v.have(item)
		rows.append({"id": "give", "text": "渡す(%s 持っている)" % main._amount_text(item, have), "column": 0})
		rows.append({"id": "close", "text": "今はいい(C / Esc)", "column": 0})
	else:
		rows.append({"id": "chat_end", "text": "またね(C / Esc)", "column": 0})
	return rows

func _visitor_action(id: String) -> void:
	var v := world.visitors
	var who: String = v.who()
	if id == "chat_end":
		main._close_shop()
		return
	if id == "receive_bees":
		if v.receive_bees() == "received":
			hud.show_message(_with_level_up("フョードルさんが巣箱に蜂を入れてくれた。はちみつがたまるのを待とう"), 6.0)
		main._close_shop()
		return
	if id == "receive":
		var person: String = v.CAST[who].name
		if v.receive_help() == "received":
			main._sfx("coin")
			hud.show_message(_with_level_up("%sから%sをもらった" % [person, reward_text(v.last_reward)]), 6.0)
			main._close_shop()
			main._act("pick", main.get_node("Visitor").ground_pos(), "radish")
		return
	var item: String = v.visit.item
	if v.give() == "given":
		main._sfx("coin")
		hud.show_message(_with_level_up("%s(%sをもらった)" % [main.with_call(VISITOR_THANKS[who]), reward_text(v.last_reward)]), 6.0)
		main._close_shop()
		main._act("pick", main.get_node("Visitor").ground_pos(), item)
		return
	var need: int = int(v.visit.amount) - v.have(item)
	var ripe := "。畑に収穫できるものがある" if world.garden.crops.any(func(c): return c.kind == item and world.garden.is_ripe(c)) else ""
	if item == v.FIREWOOD:
		ripe = "。小屋の東の薪割り台で H を押すと割れる"
	hud.show_message("%sがあと%d%s足りない%s" % [main.produce_name(item), need, main.produce_unit(item), ripe], 5.0)

# 文言のあとに、親しくなった知らせを足す
func _with_level_up(text: String) -> String:
	var up := _take_level_up()
	return text if up == "" else "%s\n%s" % [text, up]

# HUD に出す、訪問者の 1 行。いなければ ""
func visitor_line() -> String:
	if not main.has_node("Visitor") or not world.visitors.is_here():
		return ""
	var v := world.visitors
	var person: String = v.CAST[v.who()].name
	var errand := "話がしたいらしい"
	if v.has_request():
		errand = "頼みごとがあるらしい"
	elif v.has_help() or v.has_gift():
		errand = "渡したいものがあるらしい"
	elif v.has_bees():
		errand = "蜂を分けてくれるらしい"
	if main.get_node("Visitor").can_talk(main.player_pos()):
		return "%s(C で話す)" % person
	var to: Vector2 = main.get_node("Visitor").ground_pos() - main.player_pos()
	return "%sが来ている・%s(%sへ%dm)" % [person, errand, main.compass(to), ceili(to.length())]
