extends Node3D

# ── 家族の 3D 表示(2026-11-16) ─────────────────────────────────
# 誰がいるか・手伝い・贈り物は logic/Family.gd。ここは土地の中を歩いて暮らす動きと、テントの形だけ。
#   昼: 畑・木・家のまわり・プレイヤーのそばを、ときどき歩いて回る(着いたらしばらく立つ)
#   朝の手伝い: その日の手伝いの場所へ行き、水をやる / 草を抜く動きをする(ルールの手伝いは朝に済んでいる)
#   夜: 家(小屋の戸口か、テントの入口)へ帰って中に入る。テントなら自分の寝袋で横になっている(小屋なら見えなくなる)。朝になると出てくる
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
const NIGHT_AT := 0.6            # この暗さより暗いと家へ帰る
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

var _player: Node3D
var _people := {}          # id → {figure, pos, route, state: walk/stand/inside, wait, solid, shape, tasks, action}
var _tent: Node3D
var _tent_body: StaticBody3D
var _tent_at = null        # 今テントを建てている場所(動いたら建て直す)
var _tent_count := -1      # 建てたときの寝袋の数(家族の人数が変わったら建て直す)
var _tent_cut := []        # 中に入ると影だけにする布
var _tent_light: OmniLight3D
var _in_tent := false
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
	match p.state:
		"inside":
			if not is_night() and home != null:
				_come_out(p, home)
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
			if is_night() and home != null:
				_go(p, home, "home")
			elif p.wait <= 0.0:
				_next_goal(p, home)
	_place(p)

func _come_out(p: Dictionary, home: Vector2) -> void:
	p.pos = home
	p.figure.visible = true
	p.figure.basis = Basis.from_scale(Vector3.ONE * float(p.get("scale", 1.0)))  # 寝袋から起きる
	p.state = "stand"
	p.wait = _rng.randf_range(1.0, 3.0)
	_place(p)
	_stand(p)

# 次に行く場所: 手伝いがあればそこ。なければ畑・木・家・プレイヤーのそばから選ぶ
func _next_goal(p: Dictionary, home) -> void:
	while not p.tasks.is_empty():
		var h: Dictionary = p.tasks.pop_front()
		var spot = _free_near(h.pos, 1.0)
		if spot != null:
			p.action = HELP_ACTIONS.get(h.kind, "")
			p.help_at = h.pos
			_go(p, spot, "help")
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
	p.purpose = purpose
	p.state = "walk"
	p.shape.disabled = true

func _stand(p: Dictionary) -> void:
	p.state = "stand"
	p.figure.moving = false
	p.solid.position = Vector3(p.pos.x, 0.0, p.pos.y)
	p.shape.disabled = false

func _walk(p: Dictionary, delta: float) -> void:
	p.figure.moving = true
	var left: float = p.speed * delta
	var avoid := _avoid_points(p.id)
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
			if is_night():
				p.state = "inside"
				p.shape.disabled = true
				_lie_in_tent(p)
				return
		"help":
			_face_now(p, p.help_at - p.pos)
			if p.action != "":
				_play(p, p.action)
			p.action = ""
	_stand(p)
	p.wait = _rng.randf_range(STAND_SECONDS[0], STAND_SECONDS[1])

# テントがあれば自分の寝袋で横になる(布の下なので、外からは見えない)。小屋なら見えなくする
func _lie_in_tent(p: Dictionary) -> void:
	var spot = family.bedroll_of(p.id) if family.has_tent() else null
	if spot == null:
		p.figure.visible = false
		return
	p.figure.visible = true
	p.figure.moving = false
	p.figure.basis = TENT_LYING_BASIS * Basis.from_scale(Vector3.ONE * float(p.get("scale", 1.0)))
	var feet_back: float = Family.BEDROLL_SIZE.y * 0.5 - 0.1
	p.figure.position = Vector3(spot.x, LYING_Y, spot.y + feet_back)

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
	if p.state == "inside":
		return  # 寝袋で横になっている(_lie_in_tent が置いた場所のまま)
	p.figure.position = Vector3(p.pos.x, 0.0, p.pos.y)

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
	# 寝ていた家族は、新しいテントの寝袋へ(テントが片付いたら見えなくする)
	for id in _people:
		if _people[id].state == "inside":
			_lie_in_tent(_people[id])

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
