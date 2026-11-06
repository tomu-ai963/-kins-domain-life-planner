extends Node3D

# ── 訪ねてくる人の 3D 表示 ─────────────────────────────────────
# 誰がいつ来るかは logic/Visitors.gd。ここは南の境界から歩いて来て、足元の近くで待ち、用が済むと帰る動きだけ。
# 体は PlayerFigure3D を色違いで使い、帽子などを足す。小屋・池・木・プレイヤーは回り込む
# (道は歩きだすときに決める。歩いている途中にプレイヤーが道に入ると、その場でよける)。
# 待っているあいだは頭の上に印を出す(頼みごとや分けてくれるものがあれば橙、話すだけなら白)。
# 当たり判定は待っているあいだだけ付ける(歩いているあいだは訪問者がよけるので、プレイヤーを押さないように付けない)
const Visitors = preload("res://logic/Visitors.gd")
const Look = preload("res://view/3d/Look.gd")
const PlayerFigure = preload("res://view/3d/PlayerFigure3D.gd")

const GATE := Vector2(0, 49.5)   # 市場へ続く小道の、土地の入口
const WALK_SPEED := 3.2          # 歩く速さ(m/s)
const TURN_SPEED := 8.0
const TALK_REACH := 3.0          # この距離まで近づくと話せる
const SYNC_SECONDS := 1.0
const GOAL_RADII := [2.5, 4.0, 6.0, 9.0]  # 足元からこの距離で、立てる場所を探す
const GOAL_ANGLES := [0.0, 0.7, -0.7, 1.4, -1.4, 2.1, -2.1, PI]  # 北から順に試す(プレイヤーの北に立つと、顔がカメラのほうを向く)
const OBSTACLE_MARGIN := 0.8     # 小屋と池をこれだけ離れて回り込む
const TREE_MARGIN := 0.6         # 木の幹からこれだけ離れて回り込む
const PLAYER_MARGIN := 1.0       # プレイヤーからこれだけ離れて回り込む(道を決めるとき)
const AVOID_RADIUS := 0.9        # 歩いている途中、プレイヤーがこの距離に入るとよける
const ROUTE_TURNS := 12          # 道を曲がる回数の上限(木が多いときのため)
const MARK_Y := 2.2              # 印の高さ(頭に重ならないところ)
const MARK_BOB := 0.08
const BODY_RADIUS := 0.3         # 当たり判定の太さ(プレイヤーと同じ)
const BODY_HEIGHT := 1.6

# 服の色(PlayerFigure3D の look)と、足す物。scale は体の大きさ
const LOOKS := {
	"nina": {"look": {"TUNIC": Color(0.72, 0.30, 0.36), "SASH": Color(0.96, 0.86, 0.50), "TROUSERS": Color(0.42, 0.30, 0.26), "HAIR": Color(0.60, 0.42, 0.22)}, "extra": "kerchief", "scale": 1.0},
	"fyodor": {"look": {"TUNIC": Color(0.90, 0.84, 0.66), "SASH": Color(0.46, 0.34, 0.18), "TROUSERS": Color(0.30, 0.32, 0.26), "HAIR": Color(0.76, 0.76, 0.74)}, "extra": "straw_hat", "scale": 1.05},
	"tanya": {"look": {"TUNIC": Color(0.96, 0.70, 0.22), "SASH": Color(0.28, 0.62, 0.42), "TROUSERS": Color(0.30, 0.38, 0.58), "HAIR": Color(0.24, 0.14, 0.08)}, "extra": "", "scale": 0.8},
	"pavel": {"look": {"TUNIC": Color(0.24, 0.42, 0.34), "SASH": Color(0.76, 0.62, 0.24), "TROUSERS": Color(0.20, 0.24, 0.26), "HAIR": Color(0.16, 0.12, 0.10)}, "extra": "cap_bag", "scale": 1.0},
}

var visitors: Visitors
var _player: Node3D
var _state := "away"   # away / arrive / wait / leave
var _who := ""
var _figure: Node3D
var _mark: Node3D
var _solid: StaticBody3D      # 待っているあいだの当たり判定
var _solid_shape: CollisionShape3D
var _pos := GATE
var _route_points := []
var _timer := 0.0
var _t := 0.0
var _ball := SphereMesh.new()
var _box := BoxMesh.new()
var _cylinder := CylinderMesh.new()
var _request_mat := Look.mat(Color(1.0, 0.55, 0.12), true, 1.5)
var _chat_mat := Look.mat(Color(0.96, 0.96, 0.92), true, 1.5)
var _mats := {}

func setup(v: Visitors, player: Node3D) -> void:
	visitors = v
	_player = player
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 16
	_ball.rings = 8
	_cylinder.top_radius = 0.5
	_cylinder.bottom_radius = 0.5
	_cylinder.height = 1.0
	_cylinder.radial_segments = 20
	_cylinder.rings = 1

func state() -> String:
	return _state

func ground_pos() -> Vector2:
	return _pos

# 足元から話せる距離にいるか
func can_talk(pos: Vector2) -> bool:
	return (_state == "wait" or _state == "arrive") and pos.distance_to(_pos) <= TALK_REACH

# 手を振る(話しかけられたとき)
func greet() -> void:
	if _figure != null:
		_figure.play("wave")

# 今の訪問に合わせて、来る・帰る
func sync_visit() -> void:
	if visitors == null:
		return
	if visitors.is_here():
		if _state == "away" or _state == "leave":
			_arrive()
		_show_mark()
	elif _state == "arrive" or _state == "wait":
		_leave()

func _arrive() -> void:
	var who: String = visitors.who()
	if _figure == null or _who != who:
		_build(who)
		_pos = GATE
	_route_points = route(_pos, goal_near(_player.ground_pos()))
	_state = "arrive"

func _leave() -> void:
	_route_points = route(_pos, GATE)
	_state = "leave"
	_mark.visible = false
	_solid_shape.disabled = true

# 足元の近くで、立てる場所。北から探す。なければ土地の入口
func goal_near(pos: Vector2) -> Vector2:
	for r in GOAL_RADII:
		for a in GOAL_ANGLES:
			var p: Vector2 = pos + Vector2(0, -1).rotated(a) * r
			if _is_free(p):
				return p
	return GATE

func _is_free(p: Vector2) -> bool:
	var limit: float = visitors.garden.land.HALF - 0.5
	if absf(p.x) > limit or absf(p.y) > limit:
		return false
	for r in _obstacles():
		if r.has_point(p):
			return false
	return true

# 回り込むもの(小屋・池・木・プレイヤー)の範囲
func _obstacles() -> Array:
	var list := []
	var player_pos: Vector2 = _player.ground_pos()
	list.append(Rect2(player_pos - Vector2.ONE * PLAYER_MARGIN, Vector2.ONE * PLAYER_MARGIN * 2.0))
	for t in visitors.forest.trees:
		if visitors.forest.is_established(t):
			list.append(Rect2(t.pos - Vector2.ONE * TREE_MARGIN, Vector2.ONE * TREE_MARGIN * 2.0))
	var cabin = visitors.market.cabin
	if cabin.site != null:
		list.append(cabin.rect().grow(OBSTACLE_MARGIN))
	if visitors.bees != null:
		for h in visitors.bees.hives:
			list.append(Rect2(h.pos - Vector2.ONE * TREE_MARGIN, Vector2.ONE * TREE_MARGIN * 2.0))
	var pond = visitors.garden.land.pond
	if pond != null:
		var r: float = visitors.garden.land.POND_RADIUS + OBSTACLE_MARGIN
		list.append(Rect2(pond - Vector2(r, r), Vector2(r, r) * 2.0))
	return list

# from から to まで、小屋・池・木・プレイヤーを避ける道(通る点の並び。最後が to)
func route(from: Vector2, to: Vector2) -> Array:
	var points := []
	var at := from
	for _i in range(ROUTE_TURNS):
		var corner = _detour(at, to)
		if corner == null:
			break
		points.append(corner)
		at = corner
	points.append(to)
	return points

# a → b がふさがっていれば、回り込む角を返す。ふさがっていなければ null
func _detour(a: Vector2, b: Vector2):
	# 近いものから順に見る(遠くの木を先に避けると、手前を通り抜けてしまう)
	var list: Array = _obstacles()
	list.sort_custom(func(p, q): return p.get_center().distance_to(a) < q.get_center().distance_to(a))
	for r in list:
		# 始まりや行き先が範囲の中なら、その範囲は避けようがない(そばに立っている木など)
		if r.has_point(a) or r.has_point(b) or not _crosses(a, b, r.grow(-0.05)):
			continue
		var best = null
		var best_len := INF
		for c in [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]:
			if c.distance_to(a) < 0.1 or _crosses(a, c, r.grow(-0.05)):
				continue
			var length: float = a.distance_to(c) + c.distance_to(b)
			if length < best_len:
				best_len = length
				best = c
		if best != null:
			return best
	return null

static func _crosses(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var corners := [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]
	for i in range(4):
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return true
	return false

func _process(delta: float) -> void:
	if visitors == null:
		return
	_timer += delta
	if _timer >= SYNC_SECONDS:
		_timer = 0.0
		sync_visit()
	step(delta)

# 1 コマ分動かす
func step(delta: float) -> void:
	if _figure == null or _state == "away":
		return
	_t += delta
	if _state == "wait":
		_figure.moving = false
		var to: Vector2 = _player.ground_pos() - _pos
		if to.length() > 0.1:
			_face(to, delta)
	else:
		_walk(delta)
		if _figure == null:  # 入口に着いて帰った
			return
	_figure.position = Vector3(_pos.x, 0.0, _pos.y)
	_mark.position = Vector3(_pos.x, MARK_Y * float(LOOKS[_who].scale) + sin(_t * 3.0) * MARK_BOB, _pos.y)

func _walk(delta: float) -> void:
	_figure.moving = true
	var left: float = WALK_SPEED * delta
	while left > 0.0 and not _route_points.is_empty():
		# 行き先のすぐそばにプレイヤーが立っていると、よけ続けて着けない。
		# 途中の角なら飛ばし、最後の行き先なら、近くまで来たところで着いたことにする
		var point: Vector2 = _route_points[0]
		if point.distance_to(_player.ground_pos()) < AVOID_RADIUS:
			if _route_points.size() > 1:
				_route_points.pop_front()
				continue
			if _pos.distance_to(point) <= AVOID_RADIUS * 2.0:
				_route_points.clear()
				break
		var to: Vector2 = point - _pos
		if to.length() <= left:
			left -= to.length()
			_pos = _route_points.pop_front()
		else:
			var dir: Vector2 = _avoid_player(to.normalized())
			_pos += dir * left
			_face(dir, delta)
			left = 0.0
	if _route_points.is_empty():
		_reached()

# プレイヤーが近くて、進む先にいるなら、横へよける向きを返す
func _avoid_player(dir: Vector2) -> Vector2:
	var to_player: Vector2 = _player.ground_pos() - _pos
	if to_player.length() >= AVOID_RADIUS or to_player.length() < 0.001 or dir.dot(to_player) <= 0.0:
		return dir
	# 進む向きのうち、プレイヤーへ向かう分を消す。まっすぐ向かっていたら右へ
	var toward: Vector2 = to_player.normalized()
	var side: Vector2 = dir - toward * dir.dot(toward)
	if side.length() < 0.1:
		side = Vector2(-toward.y, toward.x)
	return side.normalized()

func _reached() -> void:
	_figure.moving = false
	if _state == "arrive":
		_state = "wait"
		_figure.play("wave")
		_solid.position = Vector3(_pos.x, 0.0, _pos.y)
		_solid_shape.disabled = false
	else:
		_state = "away"
		_figure.queue_free()
		_figure = null
		_who = ""
		_pos = GATE

func _face(dir: Vector2, delta: float) -> void:
	_figure.rotation.y = lerp_angle(_figure.rotation.y, atan2(-dir.x, -dir.y), minf(1.0, TURN_SPEED * delta))

func _show_mark() -> void:
	if _mark == null:
		return
	_mark.visible = _state == "wait" or _state == "arrive"
	var m: Material = _request_mat if visitors.has_request() or visitors.has_help() or visitors.has_bees() else _chat_mat
	for c in _mark.get_children():
		c.material_override = m

# ── 形 ────────────────────────────────────────────────────
func _mat(c: Color) -> Material:
	if not _mats.has(c):
		_mats[c] = Look.mat(c)
	return _mats[c]

func _build(who: String) -> void:
	if _figure != null:
		_figure.queue_free()
	_who = who
	var info: Dictionary = LOOKS[who]
	_figure = PlayerFigure.new()
	_figure.name = "Visitor_" + who
	_figure.look = info.look
	_figure.scale = Vector3.ONE * float(info.scale)
	_figure.position = Vector3(_pos.x, 0.0, _pos.y)
	add_child(_figure)
	_extra(str(info.extra))
	_build_solid(float(info.scale))
	if _mark == null:
		_mark = Node3D.new()
		_mark.name = "VisitorMark"
		add_child(_mark)
		var dot := Look.mesh_node(_ball, _request_mat, Vector3(0, -0.2, 0), Vector3.ONE * 0.11)
		var bar := Look.mesh_node(_box, _request_mat, Vector3(0, 0.05, 0), Vector3(0.09, 0.26, 0.09))
		for piece in [dot, bar]:
			piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_mark.add_child(piece)

# 当たり判定を、その人の体の大きさで作る。歩いているあいだは切っておく
func _build_solid(body_scale: float) -> void:
	if _solid == null:
		_solid = StaticBody3D.new()
		_solid.name = "VisitorBody"
		_solid_shape = CollisionShape3D.new()
		_solid.add_child(_solid_shape)
		add_child(_solid)
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS * body_scale
	capsule.height = BODY_HEIGHT * body_scale
	_solid_shape.shape = capsule
	_solid_shape.position = Vector3(0, capsule.height * 0.5, 0)
	_solid_shape.disabled = true

# 頭と体に足す物
func _extra(kind: String) -> void:
	var head: Node3D = _figure.get_node("Hips/Upper/Head")
	var upper: Node3D = _figure.get_node("Hips/Upper")
	match kind:
		"kerchief":  # 頭に巻いた布
			var cloth := Color(0.94, 0.84, 0.46)
			head.add_child(Look.mesh_node(_ball, _mat(cloth), Vector3(0, 0.06, 0.055), Vector3(0.42, 0.38, 0.37)))
			head.add_child(Look.mesh_node(_box, _mat(cloth), Vector3(0, -0.12, 0.16), Vector3(0.1, 0.1, 0.06)))
		"straw_hat":  # つばの広い麦わら帽子
			var straw := Color(0.90, 0.76, 0.44)
			head.add_child(Look.mesh_node(_cylinder, _mat(straw), Vector3(0, 0.13, 0.06), Vector3(0.54, 0.025, 0.54)))  # つばは後ろへずらして顔を隠さない
			head.add_child(Look.mesh_node(_cylinder, _mat(straw), Vector3(0, 0.2, 0.05), Vector3(0.34, 0.14, 0.34)))
		"cap_bag":  # 配達の帽子とかばん
			var green := Color(0.18, 0.32, 0.26)
			head.add_child(Look.mesh_node(_cylinder, _mat(green), Vector3(0, 0.14, 0.02), Vector3(0.4, 0.1, 0.4)))
			head.add_child(Look.mesh_node(_box, _mat(green), Vector3(0, 0.1, -0.2), Vector3(0.26, 0.02, 0.14)))
			upper.add_child(Look.mesh_node(_box, _mat(Color(0.48, 0.32, 0.16)), Vector3(0.24, 0.02, 0.05), Vector3(0.1, 0.28, 0.32)))
