extends Node3D

# ── 家族の 3D 表示(2026-11-16) ─────────────────────────────────
# 誰がいるか・手伝い・贈り物は logic/Family.gd。ここは土地の中を歩いて暮らす動きと、テントの形だけ。
#   昼: 畑・木・家のまわり・プレイヤーのそばを、ときどき歩いて回る(着いたらしばらく立つ)
#   朝の手伝い: その日の手伝いの場所へ行き、水をやる / 草を抜く動きをする(ルールの手伝いは朝に済んでいる)
#   暗くなると: 家(小屋の戸口か、テントの入口)へ帰って中で過ごす(小屋なら配偶者はストーブの前、子どもはテーブルのあたり。テントなら寝袋の前)
#   寝る時刻(Family.BEDTIME。子どもが先): テントなら自分の寝袋、小屋ならベッド(配偶者は大きいベッドの北の半分、子どもは 2 段ベッドなど)で横になる。
#     目を閉じ、掛け布団がかかる。寝ている人は踏めない(小屋はベッドの当たり判定、テントは寝袋の上に当たり判定)。WAKE_HOUR に起きて、明るくなったら出てくる
#   小屋が完成していれば、昼もときどき戸口から小屋に入り、配偶者はストーブの前、子どもはテーブルのあたりでしばらく過ごす(2026-11-16 とむ)
# 誘われたとき(2026-11-18。Main の話す画面から): 収穫はうしろをついてきて、自分が収穫すると近くの区画を採りに行く。
#   料理は配偶者がストーブの前で待ち、仕込むと鍋をかき混ぜる。夕食は家族がテーブルの席(西の腰掛け・北の長椅子)に座り、自分が食べると一緒に食べる
# テントは歩いて入れる大きさで、南の入口だけ当たり判定を空ける。プレイヤーが中に入ると、小屋と同じく布を影だけにして中を見せる。
# 中には寝袋(西から プレイヤー・家族の順)とランタン。プレイヤーは自分の寝袋のそばで H を押すと休める(Main)
# 体は PlayerFigure3D を色違いで使う。子どもは年齢に合わせて小さい。
# 小屋・池・木・巣箱などは回り込み、歩いているあいだはプレイヤー・訪問者・ほかの家族をよける。
# 当たり判定は立っているあいだだけ付ける(歩いているあいだはこちらがよけるので、プレイヤーを押さないように付けない)
const Family = preload("res://logic/Family.gd")
const Look = preload("res://view/3d/Look.gd")
const PlayerFigure = preload("res://view/3d/PlayerFigure3D.gd")
const Route = preload("res://view/3d/Route.gd")

const WALK_SPEED := 2.4          # 歩く速さ(m/s)。訪問者よりゆっくり
const CHILD_SPEED := 2.8
const TURN_SPEED := 8.0
const TALK_REACH := 3.0          # この距離まで近づくと話せる
const SYNC_SECONDS := 1.0
const STAND_SECONDS := [6.0, 16.0]  # 着いてから次へ歩きだすまで(秒)
const TALK_PAUSE := 8.0          # 話しかけられたら、これだけ立ち止まる
const NIGHT_AT := 0.6            # この暗さより暗いと家へ帰って、中で過ごす(寝るのは時計で決める。Family.BEDTIME)
const OBSTACLE_MARGIN := 0.8     # 小屋と池をこれだけ離れて回り込む
const TREE_MARGIN := 0.6         # 木の幹からこれだけ離れて回り込む
const PERSON_MARGIN := 0.7       # 立っている人をこれだけ離れて回り込む
const AVOID_RADIUS := 0.9        # 歩いている途中、人がこの距離に入るとよける
const NEAR_PLAYER := 0.25        # 歩く先にプレイヤーのそばを選ぶ割合(子どもは 2 倍)
const WANDER_TRIES := 8
const BODY_RADIUS := 0.3
const BODY_HEIGHT := 1.6
const TENT_HEIGHT := 2.2          # テントの高さ(m)。人が立てる高さ
const WALL_T := 0.12              # テントの当たり判定の壁の厚み
const BEDROLL_COLORS := [Color(0.24, 0.42, 0.70), Color(0.70, 0.30, 0.26), Color(0.36, 0.56, 0.34), Color(0.84, 0.62, 0.26), Color(0.56, 0.40, 0.66)]
# 寝袋で横になる姿勢(頭が北の奥、顔が上)。Player3D.LYING_BASIS(頭が西)の向きを変えたもの
const TENT_LYING_BASIS := Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0))
const LYING_Y := 0.1              # 寝袋の上に横になる高さ
# 枕が西のベッドで横になる姿勢(頭が西、顔が上。Player3D.LYING_BASIS と同じ)
const WEST_LYING_BASIS := Basis(Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, -1, 0))
const CABIN_FLOOR_Y := 0.25       # 小屋の床の高さ(CabinView3D.FLOOR_Y と同じ)
# 小屋のベッドの、床から敷布団の上までの高さ(Family.bed_spots の kind ごと。大きいベッドは CabinView3D が置く)
const BED_TOP := {"double": 0.39, "single": 0.36, "bunk_low": 0.36, "bunk_high": 1.28, "cot": 0.33}
const BUNK_POST_H := 1.75         # 2 段ベッドの柱の高さ
const BED_BODY_H := 1.9           # 2 段ベッドの当たり判定の高さ
const ROOM_HUB := Vector2(0.0, 0.5)  # 小屋の中を歩くときに通る部屋の真ん中(小屋の中心から。家具を突っ切らずにすむ)
const COVER_COLORS := {"double": Color(0.72, 0.30, 0.24), "single": Color(0.36, 0.52, 0.74), "bunk_low": Color(0.36, 0.52, 0.74), "bunk_high": Color(0.42, 0.62, 0.40), "cot": Color(0.86, 0.62, 0.30)}
const VISIT_CHANCE := 0.2         # 昼に次の行き先を決めるとき、小屋に入る割合(小屋が完成していれば)
const INDOOR_SECONDS := [20.0, 40.0]  # 小屋の中で過ごす時間(秒)
# 小屋の中で立つ場所(小屋の中心から)と、向く先。配偶者はストーブの前、子どもはテーブルのまわり(昼に入ったときと、暗くなってから寝るまで)
const INDOOR_SPOUSE := [Vector2(2.1, -0.6), Vector2(2.4, -1.45)]
const INDOOR_CHILDREN := [[Vector2(0.6, 1.65), Vector2(1.3, 1.2)], [Vector2(0.3, 0.05), Vector2(1.3, 1.2)], [Vector2(0.9, 0.05), Vector2(1.3, 1.2)]]
# 一緒にする作業(2026-11-18)
const INVITE_SECONDS := 600.0     # 誘ってから一緒にしてくれる長さ(秒。10 分)
const FOLLOW_DIST := 2.2          # 一緒に収穫するとき、プレイヤーからこれより離れるとついていく
const FOLLOW_GAP := 1.3           # ついていって立つ、プレイヤーからの距離
const COOK_AFTER := 6.0           # 鍋をかき混ぜたあと、ストーブの前にいる長さ(秒)
const DINNER_AFTER := 15.0        # みんなで食べたあと、席を立つまで(秒)
const BENCH_SEATS := [-0.35, 0.0, 0.35]  # 長椅子の席(長椅子の中心から東西に)
const HELP_ACTIONS := {"water": "water", "weed": "pull"}  # 手伝いの種類 → 体の動き

# 服の色(PlayerFigure3D の look)と、足す物
const LOOKS := {
	"alyona": {"look": {"TUNIC": Color(0.86, 0.42, 0.30), "SASH": Color(0.98, 0.90, 0.62), "TROUSERS": Color(0.36, 0.30, 0.40), "HAIR": Color(0.78, 0.58, 0.30)}, "extra": "kerchief_red"},
	"vera": {"look": {"TUNIC": Color(0.50, 0.62, 0.86), "SASH": Color(0.92, 0.92, 0.88), "TROUSERS": Color(0.30, 0.30, 0.38), "HAIR": Color(0.20, 0.12, 0.08)}, "extra": "braid"},
	"ilya": {"look": {"TUNIC": Color(0.92, 0.90, 0.82), "SASH": Color(0.70, 0.18, 0.16), "TROUSERS": Color(0.26, 0.30, 0.40), "HAIR": Color(0.58, 0.40, 0.20)}, "extra": "beard"},
	"mikhail": {"look": {"TUNIC": Color(0.40, 0.46, 0.28), "SASH": Color(0.50, 0.32, 0.18), "TROUSERS": Color(0.26, 0.24, 0.22), "HAIR": Color(0.12, 0.10, 0.08)}, "extra": "cap"},
}
# 子どもは息子か娘か(m / f)と、上から何人目か(0〜2)で服を決める
const CHILD_LOOKS := {
	"m": [
		{"look": {"TUNIC": Color(0.30, 0.60, 0.80), "SASH": Color(0.90, 0.70, 0.20), "TROUSERS": Color(0.30, 0.28, 0.26), "HAIR": Color(0.66, 0.48, 0.24)}, "extra": ""},
		{"look": {"TUNIC": Color(0.36, 0.62, 0.36), "SASH": Color(0.86, 0.30, 0.22), "TROUSERS": Color(0.32, 0.30, 0.40), "HAIR": Color(0.40, 0.26, 0.14)}, "extra": "cap_small"},
		{"look": {"TUNIC": Color(0.92, 0.58, 0.24), "SASH": Color(0.30, 0.42, 0.70), "TROUSERS": Color(0.28, 0.30, 0.26), "HAIR": Color(0.80, 0.62, 0.32)}, "extra": ""},
	],
	"f": [
		{"look": {"TUNIC": Color(0.62, 0.48, 0.84), "SASH": Color(0.98, 0.90, 0.56), "TROUSERS": Color(0.36, 0.30, 0.44), "HAIR": Color(0.48, 0.30, 0.16)}, "extra": "kerchief_white"},
		{"look": {"TUNIC": Color(0.94, 0.56, 0.66), "SASH": Color(0.98, 0.96, 0.90), "TROUSERS": Color(0.44, 0.30, 0.36), "HAIR": Color(0.84, 0.66, 0.36)}, "extra": "kerchief_white"},
		{"look": {"TUNIC": Color(0.98, 0.84, 0.36), "SASH": Color(0.40, 0.66, 0.40), "TROUSERS": Color(0.36, 0.40, 0.58), "HAIR": Color(0.56, 0.36, 0.18)}, "extra": "ribbon"},
	],
}

# その人の服(配偶者は人ごと、子どもは息子か娘かと何人目か)
static func look_of(m: Dictionary) -> Dictionary:
	if m.role != "child":
		return LOOKS.get(m.id, {})
	var slot: int = maxi(0, Family.CHILDREN.map(func(c): return c.id).find(m.id))
	return CHILD_LOOKS["m" if m.sex == "m" else "f"][slot]

var family: Family
var forest = null        # 回り込むもの(Main が setup で渡す)
var land = null
var cabin = null
var bees = null
var feeders = null
var well = null
var mill = null
var extra_avoid: Callable  # ほかによける人の足元(訪問者。Main が設定する)
var night := 0.0           # 暗さ(DayLightView3D.night_changed)
var clock = null           # logic/DayClock.gd(寝る時刻を見る。Main が setup で渡す)
var hours_override := -1.0 # テスト用: 0 以上なら時計の代わりにこの時刻

var _player: Node3D
var _people := {}          # id → {figure, pos, route, state: walk/stand/inside/sit, wait, solid, shape, tasks, action, invite, invite_t}
var _tent: Node3D
var _tent_body: StaticBody3D
var _tent_at = null        # 今テントを建てている場所(動いたら建て直す)
var _tent_count := -1      # 建てたときの寝袋の数(家族の人数が変わったら建て直す)
var _tent_cut := []        # 中に入ると影だけにする布
var _tent_light: OmniLight3D
var _in_tent := false
var _beds: Node3D          # 小屋の子どものベッド(2 段ベッド・小さいベッド)
var _beds_key := ""        # 置いたベッドの並び(変わったら置き直す)
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _help_seen := -1       # 手伝いの動きを始めた日(同じ日に 2 回しない)
var _ball := SphereMesh.new()
var _box := BoxMesh.new()
var _cylinder := CylinderMesh.new()
var _prism := PrismMesh.new()
var _mats := {}

func setup(f: Family, player: Node3D, parts: Dictionary) -> void:
	family = f
	_player = player
	forest = parts.get("forest")
	land = parts.get("land")
	cabin = parts.get("cabin")
	bees = parts.get("bees")
	feeders = parts.get("feeders")
	well = parts.get("well")
	mill = parts.get("mill")
	clock = parts.get("clock")
	_rng.randomize()
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 16
	_ball.rings = 8
	_cylinder.top_radius = 0.5
	_cylinder.bottom_radius = 0.5
	_cylinder.height = 1.0
	_cylinder.radial_segments = 16
	_cylinder.rings = 1
	family.changed.connect(sync)
	sync()

func set_night(amount: float) -> void:
	night = amount
	if _tent_light != null:
		_tent_light.visible = amount > 0.3

func is_night() -> bool:
	return night >= NIGHT_AT

# 今の時刻(0〜24)。N で先へ送ったプレビューも含む
func hours() -> float:
	if hours_override >= 0.0:
		return hours_override
	if clock != null:
		return fposmod(clock.real_hours() + clock.preview_hours, 24.0)
	return 23.0 if is_night() else 12.0

func is_bedtime(id: String) -> bool:
	var m: Dictionary = family.member(id)
	return not m.is_empty() and Family.is_bedtime(m.role, hours())

# ── 外から見る ─────────────────────────────────────────────
func people_ids() -> Array:
	return _people.keys()

func person_pos(id: String) -> Vector2:
	return _people[id].pos if _people.has(id) else Vector2.INF

func state_of(id: String) -> String:
	return _people[id].state if _people.has(id) else ""

func figure_of(id: String) -> Node3D:
	return _people[id].figure if _people.has(id) else null

func tent_node() -> Node3D:
	return _tent

# 足元から話せる距離にいる、いちばん近い家族の id。いなければ ""
func talkable(pos: Vector2) -> String:
	var best := ""
	var best_d := TALK_REACH
	for id in _people:
		var p: Dictionary = _people[id]
		if p.state == "inside":
			continue
		var d: float = pos.distance_to(p.pos)
		if d <= best_d:
			best_d = d
			best = id
	return best

# 話しかけられた: 立ち止まってこちらを向き、手を振る
func greet(id: String) -> void:
	if not _people.has(id):
		return
	var p: Dictionary = _people[id]
	if p.state == "walk":
		p.route = []
		_stand(p)
	p.wait = TALK_PAUSE
	p.talk_t = TALK_PAUSE
	_play(p, "wave")

# 外に出ている家族の足元(訪問者がよけるため)
func positions() -> Array:
	var out := []
	for id in _people:
		if _people[id].state != "inside":
			out.append(_people[id].pos)
	return out

# 訪問者が回り込むもの(テントと、立っている家族)
func obstacle_rects() -> Array:
	var list := []
	if _tent_at != null:
		list.append(family.tent_rect().grow(OBSTACLE_MARGIN * 0.5))
	for id in _people:
		var p: Dictionary = _people[id]
		if p.state == "stand":
			list.append(Rect2(p.pos - Vector2.ONE * PERSON_MARGIN, Vector2.ONE * PERSON_MARGIN * 2.0))
	return list

# ── 家族とテントを、ロジックに合わせる ─────────────────────────────
func sync() -> void:
	if family == null:
		return
	# 家族の顔ぶれ(決めたとき・読み込んだとき)
	var ids := []
	for m in family.members:
		ids.append(m.id)
		if not _people.has(m.id):
			_add_person(m)
		else:
			_fit_size(_people[m.id], m)
	for id in _people.keys():
		if not id in ids:
			_remove_person(id)
	_sync_tent()
	_sync_beds()
	_start_help()

func _add_person(m: Dictionary) -> void:
	var home = family.home_pos()
	var start: Vector2 = home if home != null else Vector2(0, 8)
	var fig := PlayerFigure.new()
	fig.name = "Family_" + m.id
	var info := look_of(m)
	fig.look = info.get("look", {})
	add_child(fig)
	var p := {"id": m.id, "figure": fig, "pos": start, "route": [], "state": "stand", "wait": _rng.randf_range(1.0, 4.0), "tasks": [], "action": ""}
	_extra(fig, str(info.get("extra", "")))
	var body := StaticBody3D.new()
	body.name = "FamilyBody_" + m.id
	var shape := CollisionShape3D.new()
	body.add_child(shape)
	add_child(body)
	p.solid = body
	p.shape = shape
	_people[m.id] = p
	_fit_size(p, m)
	_place(p)
	_stand(p)

func _remove_person(id: String) -> void:
	var p: Dictionary = _people[id]
	p.figure.queue_free()
	p.solid.queue_free()
	_remove_cover(p)
	_remove_sleep_body(p)
	_people.erase(id)

# 体の大きさ(子どもは年齢で)。当たり判定も合わせる
func _fit_size(p: Dictionary, m: Dictionary) -> void:
	var s := body_scale(m.role, family.age_of(m), m.sex)
	p.figure.scale = Vector3.ONE * s
	p.scale = s
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS * s
	capsule.height = BODY_HEIGHT * s
	p.shape.shape = capsule
	p.shape.position = Vector3(0, capsule.height * 0.5, 0)
	p.speed = CHILD_SPEED if m.role == "child" else WALK_SPEED
	p.child = m.role == "child"

static func body_scale(role: String, age: int, sex: String) -> float:
	if role != "child":
		return 0.96 if sex == "f" else 1.0
	return clampf(0.55 + age * 0.025, 0.55, 1.0)

# 朝の手伝いの場所を、人ごとに積む(その日はじめて見たとき。夜は動かない)
func _start_help() -> void:
	if family.last_help.is_empty() or _help_seen == family.helped_day:
		return
	_help_seen = family.helped_day
	for h in family.last_help:
		if _people.has(h.who):
			_people[h.who].tasks.append(h)

# ── 動き ──────────────────────────────────────────────────
func _process(delta: float) -> void:
	if family == null:
		return
	_timer += delta
	if _timer >= SYNC_SECONDS:
		_timer = 0.0
		_sync_tent()
		_sync_beds()
	_update_inside()
	step(delta)

# プレイヤーがテントの中にいるあいだは、布を影だけにして中を見せる
func _update_inside() -> void:
	var inside: bool = _tent != null and family.is_in_tent(_player.ground_pos())
	if inside == _in_tent:
		return
	_in_tent = inside
	if _player.has_method("set_indoors"):
		_player.set_indoors(inside, 0.0)
	_apply_cut()

func _apply_cut() -> void:
	var cast := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if _in_tent else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for n in _tent_cut:
		n.cast_shadow = cast

func is_in_tent() -> bool:
	return _in_tent

# プレイヤーが自分の寝袋で横になる場所(足元。世界の座標)と向き
func player_lying_spot() -> Vector3:
	var spot: Vector2 = family.bedroll_of("")
	return Vector3(spot.x, LYING_Y, spot.y + Family.BEDROLL_SIZE.y * 0.5 - 0.1)

# 1 コマ分動かす
func step(delta: float) -> void:
	for id in _people:
		_step_person(_people[id], delta)

func _step_person(p: Dictionary, delta: float) -> void:
	var home = family.home_pos()
	if p.get("invite", "") != "":
		p.invite_t -= delta
		if p.invite_t <= 0.0:
			_end_invite(p)
	match p.state:
		"inside":
			if home == null or not is_bedtime(p.id):
				_wake(p, home)
			return
		"sit":  # 夕食の席に座っている
			if p.get("busy", 0.0) > 0.0:  # 食べる動きが終わるまで
				p.busy -= delta
				return
			if home == null or is_bedtime(p.id) or p.get("invite", "") != "dinner":
				_get_up(p)
			return
		"walk":
			_walk(p, delta)
		"stand":
			p.figure.moving = false
			if p.get("talk_t", 0.0) > 0.0:  # 話しかけられたばかりなら、こちらを向く
				p.talk_t -= delta
				_face(p, _player.ground_pos() - p.pos, delta)
			if p.get("busy", 0.0) > 0.0:  # 手を振る・水をやるなどの動きが終わるまで待つ
				p.busy -= delta
				return
			p.wait -= delta
			var invite: String = p.get("invite", "")
			if home != null and is_bedtime(p.id):
				if invite != "":
					_end_invite(p)
				if p.get("indoor", false):
					_go_inner(p, bed_approach(p.id), "bed")  # 家の中から、そのまま寝床へ
				else:
					_go(p, home, "home")
			elif home != null and is_night():
				if invite == "harvest":  # 暗くなったら収穫はおしまい
					_end_invite(p)
				if invite == "dinner":
					_go_seat(p)
				elif not p.get("indoor", false):
					_go(p, home, "home")
				elif not p.get("settled", false) and p.wait <= 0.0:  # 起きたばかり: いつもの場所へ
					var spot := indoor_spot(p.id)
					p.look_at = spot[1]
					_go_inner(p, spot[0], "indoor")
			elif invite == "harvest":
				_follow(p)
			elif invite == "cook":
				if p.get("indoor", false) and p.get("settled", false):
					p.wait = maxf(p.wait, 1.0)  # ストーブの前で待つ
				elif p.wait <= 0.0:
					_go_indoor_spot(p)  # 話しかけられて止まったら、またストーブの前へ
			elif p.wait <= 0.0:
				_next_goal(p, home)
	_place(p)

# ── 一緒にする作業(2026-11-18) ───────────────────────────────
# 誘われた(Main がロジックの Family.invite を済ませてから呼ぶ)。kind: harvest / cook
func start_invite(id: String, kind: String) -> void:
	if not _people.has(id):
		return
	var p: Dictionary = _people[id]
	if p.state == "inside":
		return
	if p.state == "sit":
		_get_up(p)
	p.invite = kind
	p.invite_t = INVITE_SECONDS
	p.tasks = []  # 朝の手伝いの続きより、誘われたことを先に
	match kind:
		"harvest":
			p.wait = 0.0
			if p.state == "walk":
				_stand(p)
		"cook":  # ストーブの前へ
			_go_indoor_spot(p)

# 家の中のいつもの場所(配偶者はストーブの前)へ行く。外にいれば戸口から入る
func _go_indoor_spot(p: Dictionary) -> void:
	var spot := indoor_spot(p.id)
	p.look_at = spot[1]
	if p.get("indoor", false):
		_go_inner(p, spot[0], "indoor")
	elif family.home_pos() != null:
		_go(p, family.home_pos(), "home" if is_night() else "enter")

func invite_of(id: String) -> String:
	return _people[id].get("invite", "") if _people.has(id) else ""

func _end_invite(p: Dictionary) -> void:
	var was: String = p.get("invite", "")
	p.invite = ""
	p.invite_t = 0.0
	if was == "dinner" and p.state == "sit":
		_get_up(p)

# 一緒に収穫: プレイヤーのうしろをついていく。プレイヤーが小屋の中なら戸口の外で待つ。収穫できる区画がなくなったらおしまい
func _follow(p: Dictionary) -> void:
	if not family.any_ripe():
		_end_invite(p)
		return
	if p.get("indoor", false):  # 家の中にいたら、まず出る
		_next_goal(p, family.home_pos())
		return
	var pp: Vector2 = _player.ground_pos()
	var target: Vector2 = family.home_pos() if family.cabin.is_inside(pp) and family.home_pos() != null else pp
	if p.pos.distance_to(target) > FOLLOW_DIST:
		if p.wait <= 0.0:
			var spot = _free_near(target, FOLLOW_GAP)
			if spot != null:
				_go(p, spot, "follow")
			p.wait = 0.5
	else:
		_face(p, pp - p.pos, 0.1)

# 一緒に収穫している人(近い順)。プレイヤーが収穫したとき、この順に近くの区画を採る
func harvest_helpers() -> Array:
	var pp: Vector2 = _player.ground_pos()
	var ids: Array = _people.keys().filter(func(id): return _people[id].get("invite", "") == "harvest" and _people[id].state != "inside")
	ids.sort_custom(func(a, b): return _people[a].pos.distance_to(pp) < _people[b].pos.distance_to(pp))
	return ids

# その区画へ行って、採る動きをする(ロジックの収穫は Main が済ませている)
func help_pick(id: String, plot: Vector2) -> void:
	if not _people.has(id):
		return
	var p: Dictionary = _people[id]
	var spot = _free_near(plot, 0.9)
	p.action = "pick"
	p.help_at = plot
	_go(p, spot if spot != null else plot, "help")

# 一緒に料理: 配偶者がストーブの前(小屋の中)で待っているか。その id。いなければ ""
func cook_helper() -> String:
	for id in _people:
		var p: Dictionary = _people[id]
		if p.get("invite", "") == "cook" and p.state == "stand" and p.get("indoor", false) and family.cabin.is_inside(p.pos):
			return id
	return ""

# 仕込んだ: 鍋をかき混ぜる(石臼を回すのと同じ、取っ手を回す動き)。少しして、いつもの暮らしに戻る
func cook_with(id: String) -> void:
	if not _people.has(id):
		return
	var p: Dictionary = _people[id]
	_face_now(p, family.cabin.site + family.cabin.STOVE_OFFSET - p.pos)
	_play(p, "grind")
	p.invite_t = minf(p.invite_t, COOK_AFTER)

# 夕食の席: 配偶者は西の腰掛け、子どもは北の長椅子(上の子から西に)。[座る場所, そばの床, 向く先](世界の座標)
func seat_of(id: String) -> Array:
	var c = family.cabin
	var table: Vector2 = c.site + c.TABLE_OFFSET
	var m: Dictionary = family.member(id)
	if m.role == "spouse":
		var stool: Vector2 = c.site + c.SIDE_STOOL_OFFSET
		return [stool, stool + Vector2(-0.35, 0), table]
	var i: int = maxi(0, family.children().find(m)) % BENCH_SEATS.size()
	var seat: Vector2 = c.site + c.BENCH_OFFSET + Vector2(BENCH_SEATS[i], 0)
	return [seat, seat + Vector2(0, -0.4), seat + Vector2(0, 1.0)]

# みんなで夕食: 起きている家族が席へ行って座る
func start_dinner() -> void:
	if not family.cabin.is_complete():
		return
	for id in _people:
		var p: Dictionary = _people[id]
		if p.state == "inside" or is_bedtime(id):
			continue
		p.invite = "dinner"
		p.invite_t = INVITE_SECONDS
		p.tasks = []
		_go_seat(p)

func _go_seat(p: Dictionary) -> void:
	if p.state == "sit" or (p.state == "walk" and p.get("purpose", "") == "seat"):
		return
	_go_inner(p, seat_of(p.id)[1], "seat")

func _sit(p: Dictionary) -> void:
	var seat: Array = seat_of(p.id)
	var s: float = float(p.get("scale", 1.0))
	p.indoor = true
	p.settled = false
	p.pos = seat[0]
	p.state = "sit"
	p.figure.moving = false
	p.figure.sitting = true
	var dir: Vector2 = seat[2] - seat[0]
	p.figure.rotation = Vector3(0, atan2(-dir.x, -dir.y), 0)
	p.figure.position = Vector3(seat[0].x, CABIN_FLOOR_Y + family.cabin.SEAT_H - PlayerFigure.HIP_Y * s, seat[0].y)
	p.solid.position = Vector3(seat[0].x, CABIN_FLOOR_Y, seat[0].y)
	p.shape.disabled = false

# 席を立つ(席のそばの床に立つ)
func _get_up(p: Dictionary) -> void:
	p.figure.sitting = false
	p.pos = seat_of(p.id)[1]
	p.state = "stand"
	p.busy = 0.0
	p.settled = false
	if p.get("invite", "") == "dinner":
		p.invite = ""
	p.wait = _rng.randf_range(1.0, 3.0)
	p.figure.position = Vector3(p.pos.x, _floor_at(p.pos), p.pos.y)
	_stand(p)

func dinner_seated() -> bool:
	return _people.values().any(func(p): return p.state == "sit")

func seated_ids() -> Array:
	return _people.keys().filter(func(id): return _people[id].state == "sit")

# みんなで食べた: 座っている家族も食べる動きをして、少しして席を立つ
func dinner_eat() -> void:
	for id in seated_ids():
		var p: Dictionary = _people[id]
		_play(p, "eat")
		p.invite_t = minf(p.invite_t, DINNER_AFTER)

# 起きる: 寝床のそば(家の中)に立つ。明るければ、そのあと戸口から出ていく
func _wake(p: Dictionary, home) -> void:
	p.figure.visible = true
	p.figure.basis = Basis.from_scale(Vector3.ONE * float(p.get("scale", 1.0)))  # 起き上がる
	p.figure.set_eyes_closed(false)
	_remove_cover(p)
	_remove_sleep_body(p)
	var spot = bed_approach(p.id)
	p.indoor = spot != null
	p.pos = spot if spot != null else (home if home != null else p.pos)
	p.settled = false
	p.state = "stand"
	p.wait = _rng.randf_range(1.0, 3.0)
	_place(p)
	_stand(p)

# 寝床のそばの床(小屋ならベッドの横、テントなら寝袋の前)。どちらもなければ null
func bed_approach(id: String):
	var bed := family.bed_of(id)
	if not bed.is_empty():
		return bed.approach
	return tent_spot(id)

# テントの中で、その人の寝袋の前(南)の床。テントがなければ null
func tent_spot(id: String):
	var roll = family.bedroll_of(id) if family.has_tent() else null
	if roll == null:
		return null
	return roll + Vector2(0, Family.BEDROLL_SIZE.y * 0.5 + 0.35)

# 家の入口(小屋の戸口か、テントの入口)
func _door() -> Vector2:
	if family.cabin.is_complete():
		return family.cabin.door_pos()
	return family.tent + Vector2(0, Family.TENT_SIZE.y * 0.5)

# 家の中の target へ歩く(外にいれば入口から入る)。小屋の中は部屋の真ん中を通って、家具を突っ切らない
func _go_inner(p: Dictionary, target, purpose: String) -> void:
	if target == null:
		_stand(p)
		p.wait = _rng.randf_range(STAND_SECONDS[0], STAND_SECONDS[1])
		return
	var points := []
	if not p.get("indoor", false):
		points.append(_door())
	if family.cabin.is_complete():
		points.append(family.cabin.site + ROOM_HUB)
	points.append(target)
	_go_direct(p, points, purpose)

# 次に行く場所: 手伝いがあればそこ。なければ畑・木・家・プレイヤーのそばから選ぶ
func _next_goal(p: Dictionary, home) -> void:
	if p.get("indoor", false) and home != null:  # 家の中にいれば、まず戸口から出る
		# 出たあとは戸口の外のまわりに散らばる(みんなが同じ一点を目指すと、よけ合って戸口で止まるので)
		var out = _free_near(home, _rng.randf_range(1.2, 2.5))
		var points := [family.cabin.site + ROOM_HUB] if family.cabin.is_complete() else []
		points.append_array([_door(), home, out if out != null else home])
		_go_direct(p, points, "exit")
		return
	while not p.tasks.is_empty():
		var h: Dictionary = p.tasks.pop_front()
		var spot = _free_near(h.pos, 1.0)
		if spot != null:
			p.action = HELP_ACTIONS.get(h.kind, "")
			p.help_at = h.pos
			_go(p, spot, "help")
			return
	if family.cabin.is_complete() and home != null and _rng.randf() < VISIT_CHANCE:
		_go(p, home, "enter")  # 小屋に入ってしばらく過ごす
		return
	var near_player: float = NEAR_PLAYER * (2.0 if p.child else 1.0)
	for _i in range(WANDER_TRIES):
		var target = _wander_target(p, home, near_player)
		if target == null:
			continue
		var spot = _free_near(target, _rng.randf_range(0.8, 2.0))
		if spot != null and spot.distance_to(p.pos) > 1.5:
			_go(p, spot, "wander")
			return
	p.wait = _rng.randf_range(STAND_SECONDS[0], STAND_SECONDS[1])

func _wander_target(p: Dictionary, home, near_player: float):
	var roll := _rng.randf()
	if roll < near_player:
		return _player.ground_pos()
	roll = _rng.randf()
	if roll < 0.4 and not land.plots.is_empty():
		return land.plots[_rng.randi_range(0, land.plots.size() - 1)]
	if roll < 0.75 and not forest.trees.is_empty():
		var t: Dictionary = forest.trees[_rng.randi_range(0, forest.trees.size() - 1)]
		return t.pos
	return home if home != null else p.pos

# target のまわり(dist m)で、立てる場所
func _free_near(target: Vector2, dist: float):
	var start := _rng.randf() * TAU
	for i in range(8):
		var q: Vector2 = target + Vector2(dist, 0).rotated(start + TAU * i / 8.0)
		if is_free(q):
			return q
	return null

func _go(p: Dictionary, to: Vector2, purpose: String) -> void:
	p.route = route(p.pos, to, p.id)
	p.direct = false
	p.purpose = purpose
	p.state = "walk"
	p.shape.disabled = true

# 決めた点を順にまっすぐ歩く(戸口を通って小屋に出入りするとき。小屋の中は回り込まない)
func _go_direct(p: Dictionary, points: Array, purpose: String) -> void:
	p.route = points.duplicate()
	p.direct = true  # 戸口は狭いので、よけ合わずにそのまま通る
	p.purpose = purpose
	p.state = "walk"
	p.shape.disabled = true

func _stand(p: Dictionary) -> void:
	p.state = "stand"
	p.figure.moving = false
	p.solid.position = Vector3(p.pos.x, _floor_at(p.pos), p.pos.y)
	p.shape.disabled = false

# 足元の高さ(小屋の中は床の高さ)
func _floor_at(pos: Vector2) -> float:
	return CABIN_FLOOR_Y if family.cabin.is_inside(pos) else 0.0

# 家の中で立つ場所と、向く先(世界の座標)。小屋ならストーブの前・テーブルのまわり、テントなら寝袋の前でランタンのほうを向く
func indoor_spot(id: String) -> Array:
	if not family.cabin.is_complete():
		var spot = tent_spot(id)
		if spot == null:
			return [family.home_pos(), family.home_pos()]
		return [spot, family.tent + Vector2(0, 0.3)]
	var site: Vector2 = family.cabin.site
	var m: Dictionary = family.member(id)
	if m.role == "spouse":
		return [site + INDOOR_SPOUSE[0], site + INDOOR_SPOUSE[1]]
	var i: int = maxi(0, family.children().find(m)) % INDOOR_CHILDREN.size()
	return [site + INDOOR_CHILDREN[i][0], site + INDOOR_CHILDREN[i][1]]

func _walk(p: Dictionary, delta: float) -> void:
	p.figure.moving = true
	var left: float = p.speed * delta
	var avoid: Array = [] if p.get("direct", false) else _avoid_points(p.id)
	while left > 0.0 and not p.route.is_empty():
		var point: Vector2 = p.route[0]
		# 行き先のすぐそばに人が立っていると、よけ続けて着けない。近くまで来たら着いたことにする
		if avoid.any(func(a): return a.distance_to(point) < AVOID_RADIUS):
			if p.route.size() > 1:
				p.route.pop_front()
				continue
			if p.pos.distance_to(point) <= AVOID_RADIUS * 2.0:
				p.route.clear()
				break
		var to: Vector2 = point - p.pos
		if to.length() <= left:
			left -= to.length()
			p.pos = p.route.pop_front()
		else:
			var dir: Vector2 = Route.sidestep(p.pos, to.normalized(), avoid, AVOID_RADIUS)
			p.pos += dir * left
			_face(p, dir, delta)
			left = 0.0
	if p.route.is_empty():
		_reached(p)

func _reached(p: Dictionary) -> void:
	p.figure.moving = false
	match p.get("purpose", ""):
		"home":
			if is_bedtime(p.id):
				_go_inner(p, bed_approach(p.id), "bed")
				return
			if is_night():
				var spot := indoor_spot(p.id)
				p.look_at = spot[1]
				_go_inner(p, spot[0], "indoor")
				return
		"bed":
			p.indoor = true
			if is_bedtime(p.id):
				p.state = "inside"
				p.shape.disabled = true
				_lie_down(p)
				return
		"enter":
			if family.cabin.is_complete() and not is_night():
				var spot := indoor_spot(p.id)
				p.look_at = spot[1]
				_go_inner(p, spot[0], "indoor")
				return
		"indoor":
			p.indoor = true
			p.settled = true
			_face_now(p, p.look_at - p.pos)
			_stand(p)
			p.wait = _rng.randf_range(INDOOR_SECONDS[0], INDOOR_SECONDS[1])
			return
		"exit":
			p.indoor = false
		"help":
			_face_now(p, p.help_at - p.pos)
			if p.action != "":
				_play(p, p.action)
			p.action = ""
		"seat":
			if p.get("invite", "") == "dinner" and not is_bedtime(p.id):
				_sit(p)
				return
		"follow":
			_stand(p)
			p.wait = 0.3
			return
	_stand(p)
	p.wait = 0.5 if p.get("invite", "") == "harvest" else _rng.randf_range(STAND_SECONDS[0], STAND_SECONDS[1])

# 寝る: 小屋が完成していればベッド、テントなら自分の寝袋(どちらも屋根・布の下なので、外からは見えない)。
# 目を閉じて、掛け布団がかかる。どちらもなければ見えなくする
func _lie_down(p: Dictionary) -> void:
	var bed := family.bed_of(p.id)
	if not bed.is_empty():
		var basis: Basis = WEST_LYING_BASIS if bed.head == "west" else TENT_LYING_BASIS
		var y: float = CABIN_FLOOR_Y + float(BED_TOP[bed.kind]) + 0.1
		_lie_at(p, basis, Vector3(bed.feet.x, y, bed.feet.y))
		p.shape.disabled = true  # ベッドに当たり判定があるので、寝ている人も踏めない
		_remove_sleep_body(p)
		var width := 0.55 if bed.kind in ["double", "cot"] else 0.7
		_add_cover(p, COVER_COLORS[bed.kind], width)
		return
	var spot = family.bedroll_of(p.id) if family.has_tent() else null
	if spot == null:
		p.figure.visible = false
		return
	var feet_back: float = Family.BEDROLL_SIZE.y * 0.5 - 0.1
	_lie_at(p, TENT_LYING_BASIS, Vector3(spot.x, LYING_Y, spot.y + feet_back))
	# 寝袋の上に当たり判定(寝ている人を踏まないように)。寝ているあいだだけの体を置く
	p.shape.disabled = true
	_remove_sleep_body(p)
	var body := StaticBody3D.new()
	body.name = "SleepBody_" + str(p.id)
	body.position = Vector3(spot.x, 0, spot.y)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(family.bedroll_width(), 0.5, Family.BEDROLL_SIZE.y)
	shape.shape = box
	shape.position = Vector3(0, 0.25, 0)
	body.add_child(shape)
	add_child(body)
	p.sleep_body = body
	var i: int = family.members.map(func(m): return m.id).find(p.id) + 1
	_add_cover(p, BEDROLL_COLORS[i % BEDROLL_COLORS.size()], family.bedroll_width() - 0.04)

func _lie_at(p: Dictionary, basis: Basis, feet: Vector3) -> void:
	p.figure.visible = true
	p.figure.moving = false
	p.figure.basis = basis * Basis.from_scale(Vector3.ONE * float(p.get("scale", 1.0)))
	p.figure.position = feet
	p.figure.set_eyes_closed(true)

# 掛け布団のふくらみ(足元から頭のほうへ、胸のあたりまで)。起きると片付ける
func _add_cover(p: Dictionary, color: Color, width: float) -> void:
	_remove_cover(p)
	var s: float = float(p.get("scale", 1.0))
	var fig: Node3D = p.figure
	var head_dir: Vector3 = fig.basis.y.normalized()
	var length: float = 1.25 * s
	var cover := Look.mesh_node(_ball, _mat(color), fig.position + head_dir * (length * 0.42) + Vector3(0, 0.03, 0), Vector3.ONE)
	cover.name = "SleepCover_" + str(p.id)
	var along_x: bool = absf(head_dir.x) > 0.5
	cover.scale = Vector3(length, 0.4 * s, width) if along_x else Vector3(width, 0.4 * s, length)
	add_child(cover)
	p.cover = cover

func _remove_cover(p: Dictionary) -> void:
	if p.get("cover") != null:
		p.cover.queue_free()
		p.cover = null

# 寝袋の上の当たり判定を片付ける(木から外して、すぐに当たらなくする)
func _remove_sleep_body(p: Dictionary) -> void:
	if p.get("sleep_body") != null:
		remove_child(p.sleep_body)
		p.sleep_body.queue_free()
		p.sleep_body = null

func cover_of(id: String) -> Node3D:
	return _people[id].get("cover") if _people.has(id) else null

# 体の動きを始め、終わるまでは次へ歩きださない
func _play(p: Dictionary, kind: String) -> void:
	p.figure.play(kind)
	p.busy = float(PlayerFigure.ACTIONS[kind].seconds)

func _avoid_points(id: String) -> Array:
	var list := [_player.ground_pos()]
	for other in _people:
		if other != id and _people[other].state != "inside":
			list.append(_people[other].pos)
	if extra_avoid.is_valid():
		list.append_array(extra_avoid.call())
	return list

func _place(p: Dictionary) -> void:
	if p.state == "inside" or p.state == "sit":
		return  # 寝袋か布団で横になっている(_lie_down が置いた場所のまま)
	p.figure.position = Vector3(p.pos.x, _floor_at(p.pos), p.pos.y)

# ── 小屋の子どものベッド ──────────────────────────────────────
# 北の壁際に東西に置く(枕は西)。北西の隅に 2 段ベッド(子どもが 1 人なら 1 段)、3 人目はその東に小さいベッド。床に置く家具で、当たり判定がある
func _sync_beds() -> void:
	var spots: Array = family.bed_spots()
	var kinds: Array = spots.map(func(b): return b.kind).filter(func(k): return k != "double")
	var key := "" if kinds.is_empty() else str(family.cabin.site) + str(kinds)
	if key == _beds_key:
		return
	_beds_key = key
	if _beds != null:
		_beds.queue_free()
		_beds = null
	if key == "":
		return
	_beds = Node3D.new()
	_beds.name = "KidBeds"
	_beds.position = Vector3(family.cabin.site.x, CABIN_FLOOR_Y, family.cabin.site.y)
	add_child(_beds)
	var body := StaticBody3D.new()
	body.name = "KidBedsBody"
	_beds.add_child(body)
	var wood := _mat(Color(0.48, 0.32, 0.18))
	var sheet := _mat(Color(0.94, 0.92, 0.86))
	var b: Vector2 = Family.BUNK_OFFSET
	var bs: Vector2 = Family.BUNK_SIZE
	var bunk: bool = "bunk_high" in kinds
	# 2 段ベッド(1 人なら 1 段): 四隅の柱・下の段・上の段・南の柵・東の端のはしご
	var post_h: float = BUNK_POST_H if bunk else 0.7
	var frame := Node3D.new()
	frame.name = "Bunk" if bunk else "KidBed"
	_beds.add_child(frame)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			frame.add_child(Look.mesh_node(_box, wood, Vector3(b.x + sx * (bs.x * 0.5 - 0.03), post_h * 0.5, b.y + sz * (bs.y * 0.5 - 0.03)), Vector3(0.06, post_h, 0.06)))
	_bed_deck(frame, b, bs, BED_TOP.bunk_low, wood, sheet, COVER_COLORS.bunk_low)
	if bunk:
		_bed_deck(frame, b, bs, BED_TOP.bunk_high, wood, sheet, COVER_COLORS.bunk_high)
		var south: float = b.y + bs.y * 0.5
		frame.add_child(Look.mesh_node(_box, wood, Vector3(b.x - 0.25, BED_TOP.bunk_high + 0.18, south - 0.03), Vector3(bs.x - 0.6, 0.1, 0.04)))  # 上の段の柵
		for x in [b.x + bs.x * 0.5 - 0.45, b.x + bs.x * 0.5 - 0.1]:  # はしご(東の端)
			frame.add_child(Look.mesh_node(_box, wood, Vector3(x, BED_TOP.bunk_high * 0.5 + 0.1, south + 0.02), Vector3(0.04, BED_TOP.bunk_high + 0.2, 0.04)))
		for i in range(4):
			frame.add_child(Look.mesh_node(_box, wood, Vector3(b.x + bs.x * 0.5 - 0.275, 0.3 + i * 0.26, south + 0.02), Vector3(0.35, 0.03, 0.04)))
	_bed_body(body, b, bs, BED_BODY_H if bunk else 0.7)
	# 3 人目の小さいベッド
	if "cot" in kinds:
		var c: Vector2 = Family.COT_OFFSET
		var cs: Vector2 = Family.COT_SIZE
		var cot := Node3D.new()
		cot.name = "Cot"
		_beds.add_child(cot)
		cot.add_child(Look.mesh_node(_box, wood, Vector3(c.x, (BED_TOP.cot - 0.1) * 0.5, c.y), Vector3(cs.x, BED_TOP.cot - 0.1, cs.y)))
		_bed_deck(cot, c, cs, BED_TOP.cot, wood, sheet, COVER_COLORS.cot)
		_bed_body(body, c, cs, 0.7)

# 1 段ぶん: 床板・敷布団・足元(東)に畳んだ掛け布団・枕(西の端)。top は敷布団の上の高さ
func _bed_deck(parent: Node3D, c: Vector2, size: Vector2, top: float, wood: Material, sheet: Material, blanket: Color) -> void:
	parent.add_child(Look.mesh_node(_box, wood, Vector3(c.x, top - 0.13, c.y), Vector3(size.x, 0.08, size.y)))
	parent.add_child(Look.mesh_node(_box, sheet, Vector3(c.x, top - 0.04, c.y), Vector3(size.x - 0.08, 0.08, size.y - 0.08)))
	parent.add_child(Look.mesh_node(_box, _mat(blanket), Vector3(c.x + size.x * 0.2, top + 0.01, c.y), Vector3(size.x * 0.55, 0.04, size.y - 0.06)))
	parent.add_child(Look.mesh_node(_box, sheet, Vector3(c.x - size.x * 0.5 + 0.18, top + 0.04, c.y), Vector3(0.24, 0.08, size.y * 0.7)))

func _bed_body(body: StaticBody3D, c: Vector2, size: Vector2, h: float) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, h, size.y)
	shape.shape = box
	shape.position = Vector3(c.x, h * 0.5, c.y)
	body.add_child(shape)

func beds_node() -> Node3D:
	return _beds

func _face(p: Dictionary, dir: Vector2, delta: float) -> void:
	if dir.length() < 0.1:
		return
	p.figure.rotation.y = lerp_angle(p.figure.rotation.y, atan2(-dir.x, -dir.y), minf(1.0, TURN_SPEED * delta))

func _face_now(p: Dictionary, dir: Vector2) -> void:
	if dir.length() > 0.01:
		p.figure.rotation.y = atan2(-dir.x, -dir.y)

# ── 道 ──────────────────────────────────────────────────
func route(from: Vector2, to: Vector2, id := "") -> Array:
	return Route.plan(from, to, obstacles(id))

func is_free(p: Vector2) -> bool:
	var limit: float = land.HALF - 0.5
	if absf(p.x) > limit or absf(p.y) > limit:
		return false
	for r in obstacles():
		if r.has_point(p):
			return false
	return true

# 回り込むもの(小屋・池・木・巣箱・餌台・井戸・石臼・テント・プレイヤー・立っているほかの家族)の範囲
func obstacles(id := "") -> Array:
	var list := []
	var pp: Vector2 = _player.ground_pos()
	list.append(Rect2(pp - Vector2.ONE * PERSON_MARGIN, Vector2.ONE * PERSON_MARGIN * 2.0))
	for t in forest.trees:
		if forest.is_established(t):
			list.append(Rect2(t.pos - Vector2.ONE * TREE_MARGIN, Vector2.ONE * TREE_MARGIN * 2.0))
	for r in cabin.footprints():
		list.append(r.grow(OBSTACLE_MARGIN))
	var small := []
	if bees != null:
		small.append_array(bees.hives.map(func(h): return h.pos))
	if feeders != null:
		small.append_array(feeders.feeders.map(func(f): return f.pos))
	if well != null and well.site != null:
		small.append(well.site)
	if mill != null and mill.site != null:
		small.append(mill.site)
	for pos in small:
		list.append(Rect2(pos - Vector2.ONE * (TREE_MARGIN + 0.4), Vector2.ONE * (TREE_MARGIN + 0.4) * 2.0))
	if land.pond != null:
		var r: float = land.POND_RADIUS + OBSTACLE_MARGIN
		list.append(Rect2(land.pond - Vector2(r, r), Vector2(r, r) * 2.0))
	if _tent_at != null:
		list.append(family.tent_rect().grow(0.3))
	for other in _people:
		if other != id and _people[other].state == "stand":
			var q: Vector2 = _people[other].pos
			list.append(Rect2(q - Vector2.ONE * PERSON_MARGIN, Vector2.ONE * PERSON_MARGIN * 2.0))
	return list

# ── テント ────────────────────────────────────────────────
func _sync_tent() -> void:
	family.ensure_tent()
	var want = family.tent if family.has_tent() else null
	if want == _tent_at and (want == null or family.members.size() == _tent_count):
		return
	if _tent != null:
		_tent.queue_free()
		_tent_body.queue_free()
		_tent = null
		_tent_body = null
	_tent_at = want
	_tent_cut.clear()
	_tent_light = null
	if want != null:
		_tent_count = family.members.size()
		_build_tent(want)
		_apply_cut()
		set_night(night)
	# 寝ていた家族は、新しいテントの寝袋へ(テントが片付いたら、できた小屋のベッドへ)。
	# 起きてテントの中にいた家族は、外にいることにする(テントが動いた・なくなった)
	for id in _people:
		var p: Dictionary = _people[id]
		if p.state == "inside":
			_lie_down(p)
		elif p.get("indoor", false):
			p.indoor = false
			p.settled = false

# 三角のテント(入口は南)。人が立てる大きさで、布・入口の暗がり・棟の棒・支柱・杭。
# 中は床の敷物・寝袋(西から プレイヤー・家族)・枕・棟から吊ったランタン。当たり判定は入口を空けた壁
func _build_tent(at: Vector2) -> void:
	_tent = Node3D.new()
	_tent.name = "FamilyTent"
	_tent.position = Vector3(at.x, 0, at.y)
	add_child(_tent)
	var width: float = Family.TENT_SIZE.x
	var depth: float = Family.TENT_SIZE.y
	var cloth := Look.mesh_node(_prism, _mat(Color(0.66, 0.34, 0.24)), Vector3(0, TENT_HEIGHT * 0.5, 0), Vector3(width, TENT_HEIGHT, depth))
	cloth.name = "Cloth"
	_tent.add_child(cloth)
	var door := Look.mesh_node(_prism, _mat(Color(0.20, 0.16, 0.12)), Vector3(0, 0.85, depth * 0.5 + 0.01), Vector3(Family.TENT_DOOR * 1.4, 1.7, 0.02))
	door.name = "Door"
	_tent.add_child(door)
	_tent_cut = [cloth, door]
	var wood := _mat(Color(0.48, 0.34, 0.20))
	var ridge := Look.mesh_node(_cylinder, wood, Vector3(0, TENT_HEIGHT + 0.02, 0), Vector3(0.06, depth + 0.2, 0.06))
	ridge.rotation.x = PI * 0.5
	ridge.name = "Ridge"
	_tent.add_child(ridge)
	_tent_cut.append(ridge)
	for z in [-1.0, 1.0]:  # 前後の支柱(中に入ると影だけにする。部屋の真ん中に棒が見えないように)
		var post := Look.mesh_node(_cylinder, wood, Vector3(0, TENT_HEIGHT * 0.5, z * (depth * 0.5 + 0.06)), Vector3(0.05, TENT_HEIGHT, 0.05))
		_tent.add_child(post)
		_tent_cut.append(post)
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:  # 杭
		_tent.add_child(Look.mesh_node(_cylinder, wood, Vector3(c.x * (width * 0.5 + 0.25), 0.08, c.y * (depth * 0.5 - 0.2)), Vector3(0.05, 0.16, 0.05)))
	# 中: 敷物・寝袋・枕・ランタン
	var floor_cloth := Look.mesh_node(_box, _mat(Color(0.56, 0.50, 0.38)), Vector3(0, 0.015, 0), Vector3(width - 0.1, 0.03, depth - 0.1))
	floor_cloth.name = "Floor"
	_tent.add_child(floor_cloth)
	var bw: float = family.bedroll_width()
	var spots: Array = family.bedroll_spots()
	for i in range(spots.size()):
		var local: Vector2 = spots[i] - at
		var roll := Look.mesh_node(_box, _mat(BEDROLL_COLORS[i % BEDROLL_COLORS.size()]), Vector3(local.x, 0.06, local.y), Vector3(bw, 0.07, Family.BEDROLL_SIZE.y))
		roll.name = "Bedroll%d" % i
		_tent.add_child(roll)
		_tent.add_child(Look.mesh_node(_box, _mat(Color(0.94, 0.92, 0.86)), Vector3(local.x, 0.11, local.y - Family.BEDROLL_SIZE.y * 0.5 + 0.18), Vector3(bw * 0.8, 0.08, 0.26)))
	var lantern := Look.mesh_node(_cylinder, _mat(Color(0.95, 0.78, 0.40)), Vector3(0, TENT_HEIGHT - 0.55, 0.3), Vector3(0.14, 0.2, 0.14))
	lantern.name = "Lantern"
	_tent.add_child(lantern)
	_tent.add_child(Look.mesh_node(_cylinder, wood, Vector3(0, TENT_HEIGHT - 0.28, 0.3), Vector3(0.01, 0.4, 0.01)))
	_tent_light = OmniLight3D.new()
	_tent_light.name = "TentLight"
	_tent_light.position = Vector3(0, TENT_HEIGHT - 0.6, 0.3)
	_tent_light.light_color = Color(1.0, 0.76, 0.46)
	_tent_light.light_energy = 1.2
	_tent_light.omni_range = 3.0
	_tent_light.shadow_enabled = false
	_tent_light.visible = false
	_tent.add_child(_tent_light)
	# 当たり判定: 東・西・北の壁と、入口を空けた南の壁
	_tent_body = StaticBody3D.new()
	_tent_body.name = "FamilyTentBody"
	_tent_body.position = _tent.position
	add_child(_tent_body)
	var side: float = (width - Family.TENT_DOOR) * 0.5
	var walls := [
		[Vector3(-width * 0.5, 0, 0), Vector3(WALL_T, TENT_HEIGHT, depth)],
		[Vector3(width * 0.5, 0, 0), Vector3(WALL_T, TENT_HEIGHT, depth)],
		[Vector3(0, 0, -depth * 0.5), Vector3(width, TENT_HEIGHT, WALL_T)],
		[Vector3(-(Family.TENT_DOOR * 0.5 + side * 0.5), 0, depth * 0.5), Vector3(side, TENT_HEIGHT, WALL_T)],
		[Vector3(Family.TENT_DOOR * 0.5 + side * 0.5, 0, depth * 0.5), Vector3(side, TENT_HEIGHT, WALL_T)],
	]
	for w in walls:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w[1]
		shape.shape = box
		shape.position = w[0] + Vector3(0, TENT_HEIGHT * 0.5, 0)
		_tent_body.add_child(shape)

# ── 形 ────────────────────────────────────────────────────
func _mat(c: Color) -> Material:
	if not _mats.has(c):
		_mats[c] = Look.mat(c)
	return _mats[c]

# 頭と体に足す物
func _extra(fig: Node3D, kind: String) -> void:
	var head: Node3D = fig.get_node("Hips/Upper/Head")
	match kind:
		"kerchief_red", "kerchief_white":  # 頭に巻いた布
			var cloth := Color(0.80, 0.20, 0.18) if kind == "kerchief_red" else Color(0.96, 0.94, 0.88)
			head.add_child(Look.mesh_node(_ball, _mat(cloth), Vector3(0, 0.06, 0.055), Vector3(0.42, 0.38, 0.37)))
			head.add_child(Look.mesh_node(_box, _mat(cloth), Vector3(0, -0.12, 0.16), Vector3(0.1, 0.1, 0.06)))
		"braid":  # 背中に垂らした三つ編み
			var hair: Color = LOOKS.vera.look.HAIR
			for i in range(3):
				head.add_child(Look.mesh_node(_ball, _mat(hair), Vector3(0, -0.12 - i * 0.1, 0.19), Vector3(0.09, 0.11, 0.09)))
		"beard":  # 短いあごひげ
			head.add_child(Look.mesh_node(_ball, _mat(LOOKS.ilya.look.HAIR), Vector3(0, -0.13, -0.11), Vector3(0.2, 0.14, 0.12)))
		"ribbon":  # 頭の後ろの赤いリボン
			var red := _mat(Color(0.86, 0.22, 0.24))
			head.add_child(Look.mesh_node(_ball, red, Vector3(-0.07, 0.12, 0.17), Vector3(0.1, 0.08, 0.06)))
			head.add_child(Look.mesh_node(_ball, red, Vector3(0.07, 0.12, 0.17), Vector3(0.1, 0.08, 0.06)))
		"cap_small":  # 子どもの丸い帽子
			head.add_child(Look.mesh_node(_ball, _mat(Color(0.30, 0.28, 0.50)), Vector3(0, 0.1, 0.02), Vector3(0.4, 0.22, 0.4)))
		"cap":  # つばのある帽子
			var cap := Color(0.22, 0.22, 0.24)
			head.add_child(Look.mesh_node(_cylinder, _mat(cap), Vector3(0, 0.14, 0.02), Vector3(0.4, 0.1, 0.4)))
			head.add_child(Look.mesh_node(_box, _mat(cap), Vector3(0, 0.1, -0.2), Vector3(0.26, 0.02, 0.14)))
