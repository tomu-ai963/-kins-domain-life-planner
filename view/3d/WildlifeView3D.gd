extends Node3D

# ── 土地に来る生き物の 3D 表示 ───────────────────────────────────
# 何が何匹いるかは logic/Wildlife.gd。ここは数に合わせて増やしたり減らしたりし、それぞれを動かす。
# 走る生き物: 住みかのまわりを歩いて止まり、プレイヤーが近づくと逃げる(鳥は飛ぶ。ハリネズミは逃げずに止まる)。
# 飛ぶ虫: 畑の上をひらひら飛ぶ。逃げない。
# 形は見下ろしのカメラから見えるように、実物より大きく作っている。見た目だけで、ルールには関わらない
const Wildlife = preload("res://logic/Wildlife.gd")
const Look = preload("res://view/3d/Look.gd")
const Feeders = preload("res://logic/Feeders.gd")

const SYNC_SECONDS := 2.0     # 数を見直す間隔
const FADE_SECONDS := 0.4     # 現れる・消えるのにかかる時間
const FLEE_DIST := 3.0        # プレイヤーがこの距離まで来ると逃げる
const FLY_FLAP := 22.0        # 羽ばたきの速さ(rad/s)
const INSECT_FLAP := 30.0
const FLUTTER_RADIUS := 1.6   # 虫が飛ぶ範囲(m)

# roam: 住みかから歩く範囲 / speed: 歩く速さ / flee: 逃げる速さ / run: 逃げる距離 /
# hop: 動くときに跳ねる高さ / hop_rate: 跳ねる速さ / wings: 飛んで逃げる(arc は飛ぶ高さ)
# perch: 住みか(餌台)の台の上にとまる高さ / back: 離れたところから台へ飛んで戻る速さ
const MOVES := {
	"tit": {"roam": 0.26, "speed": 0.45, "flee": 8.0, "run": 8.0, "hop": 0.05, "hop_rate": 16.0, "wings": true, "arc": 2.5, "perch": Feeders.TABLE_H, "back": 5.0},
	"bullfinch": {"roam": 0.26, "speed": 0.3, "flee": 7.0, "run": 7.0, "hop": 0.04, "hop_rate": 14.0, "wings": true, "arc": 2.0, "perch": Feeders.TABLE_H, "back": 4.5},
	"sparrow": {"roam": 3.0, "speed": 1.2, "flee": 7.0, "run": 12.0, "hop": 0.1, "hop_rate": 14.0, "wings": true, "arc": 2.5},
	# アカゲラ: 育った白樺の幹(カメラの側)にとまって、幹をつつく。perch_r: 幹の中心からの距離 / side: 幹のカメラの側だけにとまる
	"woodpecker": {"roam": 0.08, "speed": 0.12, "flee": 7.0, "run": 9.0, "hop": 0.07, "hop_rate": 11.0, "wings": true, "arc": 2.5, "perch": 1.9, "back": 4.5, "perch_r": 0.16, "side": true},
	"starling": {"roam": 3.5, "speed": 1.0, "flee": 7.0, "run": 12.0, "hop": 0.06, "hop_rate": 12.0, "wings": true, "arc": 2.5},  # 巣箱の木の根元で虫を探して歩く
	"squirrel": {"roam": 5.0, "speed": 2.2, "flee": 6.0, "run": 11.0, "hop": 0.14, "hop_rate": 12.0, "wings": false, "arc": 0.0},
	"hare": {"roam": 6.0, "speed": 2.0, "flee": 8.0, "run": 18.0, "hop": 0.32, "hop_rate": 9.0, "wings": false, "arc": 0.0},
	"hedgehog": {"roam": 4.0, "speed": 0.5, "flee": 0.0, "run": 0.0, "hop": 0.0, "hop_rate": 0.0, "wings": false, "arc": 0.0},
	"migrant": {"roam": 2.5, "speed": 0.6, "flee": 8.0, "run": 24.0, "hop": 0.0, "hop_rate": 0.0, "wings": true, "arc": 5.5},
}
const FLEE_ANGLES := [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]  # 逃げ先がふさがっているときに試す向き(rad)
const FLEE_REST_MIN := 5.0    # 逃げたあと、住みかへ戻りはじめるまでの時間(秒)
const FLEE_REST_MAX := 10.0
const BUTTERFLY_COLORS := [Color(0.96, 0.96, 0.88), Color(0.96, 0.82, 0.25), Color(0.95, 0.52, 0.16)]
const FOLD_ANGLE := 1.4       # 鳥が羽を背中へたたむ角度(rad)
# 見下ろしのカメラから見えるように、形に掛ける倍率(いつものカメラの距離で点にならないところ)
const DISPLAY_SCALE := {"sparrow": 1.5,"squirrel": 1.8, "butterfly": 2.2, "bee": 2.4, "hare": 1.5, "hedgehog": 1.7, "migrant": 1.0, "tit": 1.0, "bullfinch": 1.1, "starling": 1.5, "woodpecker": 1.5}
const PERCH_SLOTS := 3        # 台の上の持ち場の数(餌台 1 つに来る鳥の数)。鳥が重なって、かたまりに見えないように分ける
const PERCH_R := 0.3          # 持ち場の、台の中心からの距離(m)
const ON_TABLE_DIST := 0.5    # 住みかからこの距離までは台の上にいる
const OFF_TABLE_DIST := 3.0   # 住みかからこの距離より遠いと地面の高さ
const SETTLE_DIST := 0.6      # 飛んで戻ってきて、歩きに変わる距離

var wildlife: Wildlife
var _player: Node3D
var _animals := []            # [{id, node, home, pos, mode, wait, target, t, from, seed, wings: [], moves}]
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _ball := SphereMesh.new()
var _box := BoxMesh.new()
var _cone := CylinderMesh.new()
var _mats := {}

func setup(w: Wildlife, player: Node3D) -> void:
	wildlife = w
	_player = player
	_rng.randomize()
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 12
	_ball.rings = 6
	_cone.top_radius = 0.0
	_cone.bottom_radius = 0.5
	_cone.height = 1.0
	_cone.radial_segments = 6
	_cone.rings = 1
	sync_animals()

func _mat(c: Color) -> Material:
	if not _mats.has(c):
		_mats[c] = Look.mat(c)
	return _mats[c]

func count(id: String) -> int:
	var n := 0
	for a in _animals:
		if a.id == id:
			n += 1
	return n

# 今の数に合わせて増やす・減らす
func sync_animals() -> void:
	var wanted: Dictionary = wildlife.counts()
	for id in Wildlife.SPECIES:
		var goal: int = int(wanted.get(id, 0))
		var now := count(id)
		for _i in range(now, goal):
			_spawn(id)
		for _i in range(goal, now):
			_remove_one(id)

func _spawn(id: String) -> void:
	var near: Vector2 = _player.ground_pos()
	var home: Vector2 = _flock_home(id, near)
	var flying: bool = not MOVES.has(id)
	var slot: int = _animals.filter(func(other): return _perches(other.id) and other.home == home).size() if _perches(id) else 0
	var pos: Vector2 = _home_spot(home, slot, id) if _perches(id) else _free_spot(home, 1.2 if flying else float(MOVES[id].roam) * 0.5)
	var a := {
		"id": id, "home": home, "slot": slot, "pos": pos, "mode": "idle", "wait": _rng.randf_range(0.2, 2.5), "target": pos, "from": pos,
		"t": _rng.randf_range(0.0, TAU), "seed": _rng.randf_range(0.0, TAU), "wings": [], "moves": MOVES.get(id, {}),
	}
	a.node = _build(id, a)
	a.node.name = "Animal_" + id
	a.node.position = Vector3(pos.x, 0.0, pos.y)
	add_child(a.node, true)
	a.node.rotation.y = _rng.randf_range(0.0, TAU)
	var full: Vector3 = a.node.scale
	a.node.scale = full * 0.01
	a.node.create_tween().tween_property(a.node, "scale", full, FADE_SECONDS)
	_animals.append(a)

func _perches(id: String) -> bool:
	return MOVES.has(id) and MOVES[id].has("perch")

# 台の上の、とまる場所。持ち場のまわりで少しずつ動く。幹にとまる鳥は、幹のカメラの側(南)
func _home_spot(home: Vector2, slot: int, id := "") -> Vector2:
	var m: Dictionary = MOVES.get(id, {})
	var angle: float = slot * TAU / PERCH_SLOTS + _rng.randf_range(-0.3, 0.3)
	if m.get("side", false):
		angle = PI * 0.5 + _rng.randf_range(-0.5, 0.5)
	return home + Vector2.from_angle(angle) * float(m.get("perch_r", PERCH_R)) * _rng.randf_range(0.8, 1.15)

# 渡り鳥は群れでいるので、同じ場所に降りる
func _flock_home(id: String, near: Vector2) -> Vector2:
	if id == "migrant":
		for a in _animals:
			if a.id == id:
				return a.home
	return wildlife.home_for(id, _rng, near)

func _free_spot(center: Vector2, radius: float) -> Vector2:
	for _i in range(8):
		var p := center + Vector2.from_angle(_rng.randf_range(0.0, TAU)) * _rng.randf_range(0.0, radius)
		if wildlife.is_free(p):
			return p
	return center

func _remove_one(id: String) -> void:
	for i in range(_animals.size() - 1, -1, -1):
		if _animals[i].id == id:
			var node: Node3D = _animals[i].node
			_animals.remove_at(i)
			var tw := node.create_tween()
			tw.tween_property(node, "scale", Vector3.ONE * 0.01, FADE_SECONDS)
			tw.tween_callback(node.queue_free)
			return

func _process(delta: float) -> void:
	if wildlife == null:
		return
	_timer += delta
	if _timer >= SYNC_SECONDS:
		_timer = 0.0
		sync_animals()
	var player_pos: Vector2 = _player.ground_pos()
	for a in _animals:
		if a.moves.is_empty():
			_flutter(a, delta)
		else:
			_walk(a, delta, player_pos)

# ── 動き ───────────────────────────────────────────────────
# 虫: 住みかの上を、ふらふら飛び回る
func _flutter(a: Dictionary, delta: float) -> void:
	a.t += delta
	var bee: bool = a.id == "bee"
	var speed: float = 1.3 if bee else 0.6
	var t: float = a.t * speed + a.seed
	var offset := Vector2(sin(t) + 0.4 * sin(t * 2.3 + 1.0), cos(t * 0.8) + 0.4 * cos(t * 1.9)) * FLUTTER_RADIUS * 0.7
	var pos: Vector2 = a.home + offset
	var y: float = 0.9 + 0.3 * sin(t * (5.0 if bee else 1.7))
	var node: Node3D = a.node
	var from: Vector3 = node.position
	node.position = Vector3(pos.x, y, pos.y)
	var d := Vector2(node.position.x - from.x, node.position.z - from.z)
	if d.length() > 0.0001:
		node.rotation.y = atan2(-d.x, -d.y)
	_flap(a, INSECT_FLAP, 0.9)

# 走る生き物: 止まる → 歩く。近づくと逃げる
func _walk(a: Dictionary, delta: float, player_pos: Vector2) -> void:
	var m: Dictionary = a.moves
	var near: bool = a.pos.distance_to(player_pos) < FLEE_DIST
	if near and float(m.flee) > 0.0 and a.mode != "flee":
		_start_flee(a, player_pos)
	elif near and float(m.flee) == 0.0:
		a.mode = "idle"  # ハリネズミは止まって、じっとする
		a.wait = 1.0
	match a.mode:
		"idle":
			a.wait -= delta
			if a.wait <= 0.0:
				a.from = a.pos
				a.target = _home_spot(a.home, a.slot, a.id) if m.has("perch") else _free_spot(a.home, float(m.roam))
				a.mode = "walk"
		"walk":
			var away: bool = m.has("back") and a.pos.distance_to(a.home) > SETTLE_DIST
			_step_toward(a, float(m.back) if away else float(m.speed), delta)
		"flee":
			_step_toward(a, float(m.flee), delta)
	_place(a, delta)

func _start_flee(a: Dictionary, player_pos: Vector2) -> void:
	var m: Dictionary = a.moves
	var away: Vector2 = a.pos - player_pos
	if away.length() < 0.01:
		away = Vector2.RIGHT
	a.from = a.pos
	a.target = _flee_goal(a.pos, away.normalized(), float(m.run), a)
	a.mode = "flee"

# プレイヤーから離れる向きの逃げ先。土地の端や池でふさがっていれば、向きを振って短くする。
# どこもだめなら住みかのまわり
func _flee_goal(from: Vector2, away: Vector2, run: float, a: Dictionary) -> Vector2:
	for length in [run, run * 0.6, run * 0.35]:
		for angle in FLEE_ANGLES:
			var goal: Vector2 = from + away.rotated(angle) * length
			if wildlife.is_free(goal):
				return goal
	return _free_spot(a.home, float(a.moves.roam))

func _step_toward(a: Dictionary, speed: float, delta: float) -> void:
	var to: Vector2 = a.target - a.pos
	var step: float = speed * delta
	if to.length() <= step:
		a.pos = a.target
		# 逃げたあとは、しばらくそこに留まる(すぐ住みかへ戻ると、また近づいてしまう)
		a.wait = _rng.randf_range(FLEE_REST_MIN, FLEE_REST_MAX) if a.mode == "flee" else _rng.randf_range(1.0, 4.0)
		a.mode = "idle"
		return
	a.pos += to.normalized() * step
	a.node.rotation.y = lerp_angle(a.node.rotation.y, atan2(-to.x, -to.y), minf(1.0, 10.0 * delta))

# 位置と高さを置く。動いているあいだは跳ねる。鳥は逃げるとき弧を描いて飛ぶ
func _place(a: Dictionary, delta: float) -> void:
	var m: Dictionary = a.moves
	# 餌台の鳥: 台のそばでは台の高さ。離れるほど地面の高さへ下りる
	var base := 0.0
	var returning := false
	if m.has("perch"):
		var from_home: float = a.pos.distance_to(a.home)
		base = float(m.perch) * (1.0 - smoothstep(ON_TABLE_DIST, OFF_TABLE_DIST, from_home))
		returning = a.mode == "walk" and from_home > SETTLE_DIST
	var y := base
	var flying: bool = (a.mode == "flee" and m.wings) or returning
	if flying:
		var whole: float = a.from.distance_to(a.target)
		var done: float = 1.0 - a.pos.distance_to(a.target) / maxf(whole, 0.01)
		y += sin(clampf(done, 0.0, 1.0) * PI) * float(m.arc)
		a.t += delta
		_flap(a, FLY_FLAP, 1.0)
	else:
		_fold(a)
		if a.mode != "idle":
			a.t += delta
			y += absf(sin(a.t * float(m.hop_rate))) * float(m.hop)
	a.node.position = Vector3(a.pos.x, y, a.pos.y)

# 羽を動かす。時間(a.t)は呼ぶ側が進める
func _flap(a: Dictionary, rate: float, amount: float) -> void:
	var angle: float = sin(a.t * rate) * amount
	for i in range(a.wings.size()):
		a.wings[i].rotation = Vector3(0.0, 0.0, angle * (1.0 if i == 0 else -1.0))

# 止まっているとき、羽を背中のほうへたたむ(0 番が左、1 番が右)
func _fold(a: Dictionary) -> void:
	for i in range(a.wings.size()):
		a.wings[i].rotation = Vector3(0.0, FOLD_ANGLE * (1.0 if i == 0 else -1.0), 0.0)

# ── 形(-z が正面。足元が y = 0) ──────────────────────────────────
func _part(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, scl: Vector3) -> MeshInstance3D:
	var mi := Look.mesh_node(mesh, _mat(c), pos, scl)
	parent.add_child(mi)
	return mi

# 羽: 付け根を軸にする。side は -1(左)か 1(右)
func _wing(a: Dictionary, parent: Node3D, c: Color, pos: Vector3, size: Vector3, side: float) -> void:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	_part(pivot, _ball, c, Vector3(side * size.x * 0.5, 0, 0), size)
	a.wings.append(pivot)

func _build(id: String, a: Dictionary) -> Node3D:
	var n := Node3D.new()
	match id:
		"sparrow":
			_sparrow(n, a)
		"squirrel":
			_squirrel(n)
		"butterfly":
			_butterfly(n, a)
		"bee":
			_bee(n, a)
		"hare":
			_hare(n)
		"hedgehog":
			_hedgehog(n)
		"migrant":
			_migrant(n, a)
		"tit":
			_tit(n, a)
		"bullfinch":
			_bullfinch(n, a)
		"starling":
			_starling(n, a)
		"woodpecker":
			_woodpecker(n, a)
	n.scale = Vector3.ONE * float(DISPLAY_SCALE[id])
	if MOVES.has(id):
		_fold(a)
	return n

func _sparrow(n: Node3D, a: Dictionary) -> void:
	var brown := Color(0.50, 0.34, 0.20)
	_part(n, _ball, brown, Vector3(0, 0.14, 0), Vector3(0.2, 0.18, 0.3))
	_part(n, _ball, Color(0.86, 0.80, 0.68), Vector3(0, 0.11, -0.03), Vector3(0.16, 0.12, 0.2))
	_part(n, _ball, brown, Vector3(0, 0.24, -0.12), Vector3.ONE * 0.15)
	_part(n, _box, Color(0.20, 0.16, 0.12), Vector3(0, 0.24, -0.21), Vector3(0.04, 0.03, 0.06))
	_part(n, _box, Color(0.36, 0.24, 0.14), Vector3(0, 0.16, 0.2), Vector3(0.06, 0.03, 0.16))
	for side in [-1.0, 1.0]:
		_wing(a, n, Color(0.36, 0.24, 0.14), Vector3(side * 0.08, 0.18, 0.02), Vector3(0.18, 0.02, 0.16), side)

# アカゲラ: 幹に縦にとまる。黒い背に白い肩、白いほお、赤い下尾筒と後頭部。くちばしは幹(体の前 = -Z)に向く
func _woodpecker(n: Node3D, a: Dictionary) -> void:
	var black := Color(0.10, 0.10, 0.12)
	var white := Color(0.95, 0.94, 0.90)
	var red := Color(0.86, 0.14, 0.12)
	_part(n, _ball, black, Vector3(0, 0.2, 0), Vector3(0.17, 0.32, 0.16))
	_part(n, _ball, Color(0.90, 0.86, 0.78), Vector3(0, 0.2, 0.05), Vector3(0.13, 0.26, 0.08))
	for side in [-1.0, 1.0]:
		_part(n, _ball, white, Vector3(side * 0.07, 0.25, -0.01), Vector3(0.05, 0.12, 0.08))
	_part(n, _ball, red, Vector3(0, 0.06, 0.04), Vector3(0.09, 0.07, 0.07))
	_part(n, _box, black, Vector3(0, 0.0, 0.03), Vector3(0.06, 0.12, 0.03))
	_part(n, _ball, black, Vector3(0, 0.39, -0.02), Vector3.ONE * 0.13)
	_part(n, _ball, white, Vector3(0, 0.38, 0.0), Vector3(0.14, 0.07, 0.09))
	_part(n, _ball, red, Vector3(0, 0.41, 0.05), Vector3(0.06, 0.05, 0.04))
	_part(n, _box, Color(0.20, 0.18, 0.16), Vector3(0, 0.39, -0.11), Vector3(0.03, 0.03, 0.08))
	for side in [-1.0, 1.0]:
		_wing(a, n, black, Vector3(side * 0.08, 0.22, 0.02), Vector3(0.14, 0.02, 0.14), side)

# ムクドリ: 緑と紫に光る黒い体に白い斑点、黄色いくちばし
func _starling(n: Node3D, a: Dictionary) -> void:
	var gloss := Color(0.14, 0.16, 0.18)
	_part(n, _ball, gloss, Vector3(0, 0.14, 0), Vector3(0.21, 0.18, 0.32))
	_part(n, _ball, Color(0.20, 0.26, 0.22), Vector3(0, 0.12, -0.04), Vector3(0.17, 0.13, 0.2))
	for i in range(4):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		_part(n, _ball, Color(0.88, 0.86, 0.80), Vector3(side * 0.06, 0.15 + (i / 2) * 0.03, 0.02 - (i / 2) * 0.06), Vector3.ONE * 0.03)
	_part(n, _ball, Color(0.18, 0.14, 0.22), Vector3(0, 0.25, -0.12), Vector3.ONE * 0.15)
	_part(n, _box, Color(0.95, 0.80, 0.20), Vector3(0, 0.24, -0.22), Vector3(0.035, 0.03, 0.08))
	_part(n, _box, gloss, Vector3(0, 0.16, 0.2), Vector3(0.06, 0.03, 0.12))
	for side in [-1.0, 1.0]:
		_wing(a, n, Color(0.22, 0.20, 0.18), Vector3(side * 0.08, 0.18, 0.02), Vector3(0.18, 0.02, 0.16), side)

# シジュウカラ: 黄色みのある腹、黒い頭と胸の線、白いほお、青みのある灰色の羽
func _tit(n: Node3D, a: Dictionary) -> void:
	var back := Color(0.44, 0.54, 0.46)
	var black := Color(0.10, 0.10, 0.12)
	_part(n, _ball, back, Vector3(0, 0.14, 0), Vector3(0.2, 0.18, 0.28))
	_part(n, _ball, Color(0.93, 0.82, 0.32), Vector3(0, 0.11, -0.03), Vector3(0.17, 0.13, 0.2))
	_part(n, _box, black, Vector3(0, 0.12, -0.11), Vector3(0.035, 0.1, 0.03))
	_part(n, _ball, black, Vector3(0, 0.25, -0.11), Vector3.ONE * 0.15)
	for side in [-1.0, 1.0]:
		_part(n, _ball, Color(0.96, 0.96, 0.94), Vector3(side * 0.05, 0.24, -0.14), Vector3(0.06, 0.07, 0.06))
	_part(n, _box, black, Vector3(0, 0.24, -0.2), Vector3(0.035, 0.03, 0.05))
	_part(n, _box, Color(0.34, 0.44, 0.50), Vector3(0, 0.16, 0.2), Vector3(0.05, 0.03, 0.18))
	for side in [-1.0, 1.0]:
		_wing(a, n, Color(0.36, 0.46, 0.54), Vector3(side * 0.08, 0.18, 0.02), Vector3(0.14, 0.02, 0.12), side)

# ウソ: 赤い胸と頬、黒い頭、灰色の背。見下ろしでも赤が見えるように、胸を横へ張らせる
func _bullfinch(n: Node3D, a: Dictionary) -> void:
	var red := Color(0.86, 0.26, 0.24)
	var black := Color(0.09, 0.09, 0.11)
	_part(n, _ball, Color(0.52, 0.54, 0.58), Vector3(0, 0.15, 0.03), Vector3(0.2, 0.18, 0.28))
	_part(n, _ball, red, Vector3(0, 0.13, -0.05), Vector3(0.25, 0.18, 0.22))
	_part(n, _ball, black, Vector3(0, 0.26, -0.13), Vector3.ONE * 0.16)
	for side in [-1.0, 1.0]:
		_part(n, _ball, red, Vector3(side * 0.06, 0.23, -0.15), Vector3(0.07, 0.08, 0.07))
	_part(n, _box, black, Vector3(0, 0.25, -0.22), Vector3(0.05, 0.04, 0.05))
	_part(n, _box, black, Vector3(0, 0.17, 0.2), Vector3(0.06, 0.03, 0.16))
	for side in [-1.0, 1.0]:
		_wing(a, n, Color(0.20, 0.20, 0.24), Vector3(side * 0.08, 0.19, 0.03), Vector3(0.14, 0.02, 0.12), side)

func _squirrel(n: Node3D) -> void:
	var fur := Color(0.70, 0.34, 0.14)
	_part(n, _ball, fur, Vector3(0, 0.16, 0), Vector3(0.18, 0.2, 0.32))
	_part(n, _ball, Color(0.92, 0.84, 0.70), Vector3(0, 0.13, -0.08), Vector3(0.12, 0.13, 0.15))
	_part(n, _ball, fur, Vector3(0, 0.27, -0.17), Vector3.ONE * 0.17)
	for side in [-1.0, 1.0]:
		_part(n, _box, fur, Vector3(side * 0.06, 0.37, -0.17), Vector3(0.03, 0.09, 0.03))
	# ふさふさの尾
	_part(n, _ball, fur, Vector3(0, 0.22, 0.2), Vector3(0.14, 0.18, 0.14))
	_part(n, _ball, fur, Vector3(0, 0.36, 0.23), Vector3(0.2, 0.2, 0.18))
	_part(n, _ball, fur, Vector3(0, 0.47, 0.17), Vector3(0.16, 0.14, 0.14))

func _butterfly(n: Node3D, a: Dictionary) -> void:
	var c: Color = BUTTERFLY_COLORS[_rng.randi_range(0, BUTTERFLY_COLORS.size() - 1)]
	_part(n, _box, Color(0.14, 0.11, 0.10), Vector3.ZERO, Vector3(0.025, 0.025, 0.16))
	for side in [-1.0, 1.0]:
		_wing(a, n, c, Vector3(side * 0.012, 0, 0), Vector3(0.17, 0.01, 0.17), side)

func _bee(n: Node3D, a: Dictionary) -> void:
	_part(n, _ball, Color(0.96, 0.74, 0.14), Vector3.ZERO, Vector3(0.1, 0.09, 0.14))
	_part(n, _box, Color(0.12, 0.09, 0.07), Vector3.ZERO, Vector3(0.103, 0.06, 0.03))
	for side in [-1.0, 1.0]:
		_wing(a, n, Color(0.92, 0.94, 0.96), Vector3(side * 0.03, 0.04, 0.0), Vector3(0.09, 0.008, 0.05), side)

func _hare(n: Node3D) -> void:
	var fur := Color(0.58, 0.48, 0.36)
	_part(n, _ball, fur, Vector3(0, 0.22, 0.05), Vector3(0.24, 0.26, 0.42))
	_part(n, _ball, fur, Vector3(0, 0.36, -0.18), Vector3(0.18, 0.18, 0.22))
	_part(n, _ball, Color(0.95, 0.94, 0.90), Vector3(0, 0.27, 0.27), Vector3.ONE * 0.1)
	_part(n, _ball, Color(0.12, 0.09, 0.08), Vector3(0, 0.33, -0.29), Vector3.ONE * 0.03)
	for side in [-1.0, 1.0]:
		var ear := _part(n, _box, fur, Vector3(side * 0.05, 0.56, -0.12), Vector3(0.05, 0.28, 0.03))
		ear.rotation.x = 0.3

func _hedgehog(n: Node3D) -> void:
	var spine := Color(0.50, 0.38, 0.26)  # 夜でも見えるように、実物より明るい色
	_part(n, _ball, spine, Vector3(0, 0.12, 0.03), Vector3(0.3, 0.24, 0.38))
	_part(n, _ball, Color(0.94, 0.84, 0.68), Vector3(0, 0.09, -0.18), Vector3(0.15, 0.12, 0.17))
	_part(n, _ball, Color(0.10, 0.08, 0.07), Vector3(0, 0.09, -0.27), Vector3.ONE * 0.035)
	# 背中のとげ
	for ring in range(3):
		var count_in_ring: int = 8 - ring * 2
		var up: float = 0.5 + ring * 0.42
		for i in range(count_in_ring):
			var around: float = PI * (i + 0.5) / count_in_ring - PI * 0.5  # 背中側だけ
			var dir := Vector3(sin(around) * cos(up), sin(up), cos(around) * cos(up))
			var pos := Vector3(0, 0.12, 0.03) + Vector3(dir.x * 0.15, dir.y * 0.12, dir.z * 0.19)
			var mi := _part(n, _cone, spine, pos, Vector3(0.03, 0.09, 0.03))
			mi.quaternion = Quaternion(Vector3.UP, dir.normalized())

func _migrant(n: Node3D, a: Dictionary) -> void:
	var grey := Color(0.58, 0.56, 0.52)
	var dark := Color(0.14, 0.13, 0.13)
	_part(n, _ball, grey, Vector3(0, 0.32, 0.05), Vector3(0.32, 0.3, 0.62))
	_part(n, _ball, Color(0.90, 0.88, 0.84), Vector3(0, 0.26, 0.25), Vector3(0.2, 0.16, 0.22))
	_part(n, _box, dark, Vector3(0, 0.55, -0.2), Vector3(0.08, 0.4, 0.08))
	_part(n, _ball, dark, Vector3(0, 0.76, -0.24), Vector3(0.13, 0.12, 0.19))
	_part(n, _ball, Color(0.92, 0.90, 0.86), Vector3(0, 0.74, -0.25), Vector3(0.135, 0.06, 0.08))
	_part(n, _box, Color(0.20, 0.18, 0.16), Vector3(0, 0.75, -0.36), Vector3(0.04, 0.03, 0.09))
	for side in [-1.0, 1.0]:
		_wing(a, n, Color(0.44, 0.42, 0.40), Vector3(side * 0.14, 0.38, 0.05), Vector3(0.5, 0.03, 0.3), side)
	_part(n, _box, dark, Vector3(-0.07, 0.08, 0.05), Vector3(0.03, 0.16, 0.03))
	_part(n, _box, dark, Vector3(0.07, 0.08, 0.05), Vector3(0.03, 0.16, 0.03))
