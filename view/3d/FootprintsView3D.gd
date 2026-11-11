extends MultiMeshInstance3D

# ── 雪の上の足跡(見た目だけ。2026-11-11 とむ決定) ──────────────────────
# 冬、雪の上を歩くと自分の足跡が残り、しばらくすると消える。ノウサギとリスも足跡を残す(夕方から朝のノウサギの跡を、昼に見つけられるように長めに残す)。
# 雪をどかした道と小屋の中には残らない。状態はセーブしない(開き直すと消える)。
# 足跡が増えるたびに並べ直す(数は MAX_PRINTS まで)
const Snow = preload("res://logic/Snow.gd")
const Look = preload("res://view/3d/Look.gd")

const COLOR := Color(0.55, 0.63, 0.78)  # 雪のくぼみの青い影(いつものカメラの距離でも見えるように濃いめ)
const HEIGHT := 0.02         # 雪をどかした道(0.016)より上
const MAX_PRINTS := 260      # 一度に残る足跡の数の上限(古いものから消える)
const PLAYER_LIFE := 120.0   # 自分の足跡が残る時間(秒)
const ANIMAL_LIFE := 600.0   # 生き物の足跡が残る時間(秒)
const JUMP := 3.0            # これより離れて動いたら(場所の移動など)足跡をつながない
# step: 足跡の間(m) / size: 1 つの大きさ(幅, 長さ) / side: 左右の足の間 / pair: 前後 2 つずつ(跳ねる生き物)
const TRACKS := {
	"player": {"step": 0.6, "size": Vector2(0.18, 0.34), "side": 0.14, "pair": false, "life": PLAYER_LIFE},
	"hare": {"step": 1.1, "size": Vector2(0.11, 0.26), "side": 0.08, "pair": true, "life": ANIMAL_LIFE},
	"squirrel": {"step": 0.6, "size": Vector2(0.07, 0.11), "side": 0.06, "pair": true, "life": ANIMAL_LIFE},
	# 県を選ぶようにして足した生き物(雪の積もる土地にいるもの)。キツネは足を一直線に置いて歩く
	"snow_hare": {"step": 1.1, "size": Vector2(0.13, 0.30), "side": 0.09, "pair": true, "life": ANIMAL_LIFE},
	"ezo_squirrel": {"step": 0.6, "size": Vector2(0.07, 0.11), "side": 0.06, "pair": true, "life": ANIMAL_LIFE},
	"fox": {"step": 0.35, "size": Vector2(0.06, 0.08), "side": 0.0, "pair": false, "life": ANIMAL_LIFE},
	"tanuki": {"step": 0.3, "size": Vector2(0.06, 0.07), "side": 0.05, "pair": false, "life": ANIMAL_LIFE},
}

var snow: Snow
var _player: Node3D
var _wildlife: Node   # WildlifeView3D(歩いている生き物を見る)
var skip_at := Callable()  # pos に足跡を残さないなら true を返す(凍った池の上など。Main が渡す)
var _time := 0.0
var _expire_timer := 0.0
var _prints := []     # [{end: 消える時刻, xf: Transform3D}]。残した順
var _last := {}       # 足跡の持ち主 → {pos: 前の足跡の位置, left: 次が左足か}

func setup(s: Snow, player: Node3D, wildlife_view: Node) -> void:
	snow = s
	_player = player
	_wildlife = wildlife_view
	# 平たい円柱を縦横に伸ばして、楕円の足跡にする
	var oval := CylinderMesh.new()
	oval.top_radius = 0.5
	oval.bottom_radius = 0.5
	oval.height = 0.004
	oval.radial_segments = 12
	oval.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = oval
	multimesh = mm
	material_override = Look.mat(COLOR)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = Look.BEND_CULL_MARGIN
	layers = Look.GROUND_LAYER

func shown_count() -> int:
	return multimesh.instance_count if visible else 0

func _process(delta: float) -> void:
	_time += delta
	if not snow.can_clear_now():
		if not _prints.is_empty() or visible:
			_prints.clear()
			_last.clear()
			visible = false
			_rebuild()
		return
	visible = true
	var changed := false
	if _player != null and not (_player.has_method("is_indoors") and _player.is_indoors()):
		changed = _track("player", _player.ground_pos(), TRACKS.player) or changed
	if _wildlife != null:
		for a in _wildlife._animals:
			if TRACKS.has(a.id) and a.node.position.y < 0.05:  # 地面を歩いているときだけ(飛んで逃げるときは残さない)
				changed = _track(a.node.get_instance_id(), a.pos, TRACKS[a.id]) or changed
	_expire_timer += delta
	if _expire_timer >= 1.0:
		_expire_timer = 0.0
		var before := _prints.size()
		_prints = _prints.filter(func(p): return p.end > _time)  # 自分と生き物で残る時間が違うので、順番どおりには消えない
		changed = changed or _prints.size() != before
	if changed:
		_rebuild()

# 持ち主 key が pos まで歩いた。前の足跡から step 以上進んでいれば、足跡を 1 つ(跳ねる生き物は 2 つ)残す。残したら true
func _track(key, pos: Vector2, t: Dictionary) -> bool:
	if not _last.has(key):
		_last[key] = {"pos": pos, "left": true}
		return false
	var last: Dictionary = _last[key]
	var moved: Vector2 = pos - last.pos
	if moved.length() > JUMP:
		_last[key] = {"pos": pos, "left": true}
		return false
	if moved.length() < float(t.step):
		return false
	last.pos = pos
	if snow.is_cleared(pos) or snow.cabin.covers(pos) or (skip_at.is_valid() and skip_at.call(pos)):
		return false  # 雪をどかした道・小屋の中・氷の上には残らない
	var dir: Vector2 = moved.normalized()
	var side_dir := Vector2(-dir.y, dir.x)
	var size: Vector2 = t.size
	if t.pair:
		for s in [-1.0, 1.0]:
			_add(pos + side_dir * float(t.side) * s, dir, size, float(t.life))
	else:
		var s: float = -1.0 if last.left else 1.0
		last.left = not last.left
		_add(pos + side_dir * float(t.side) * s, dir, size, float(t.life))
	return true

func _add(p: Vector2, dir: Vector2, size: Vector2, life: float) -> void:
	# 板の Z を進む向きに合わせ、幅と長さに伸ばす
	var yaw: float = atan2(dir.x, dir.y)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(size.x, 1.0, size.y))
	_prints.append({"end": _time + life, "xf": Transform3D(basis, Vector3(p.x, HEIGHT, p.y))})
	if _prints.size() > MAX_PRINTS:
		_prints.pop_front()

func _rebuild() -> void:
	if multimesh.instance_count != _prints.size():
		multimesh.instance_count = _prints.size()
	for i in range(_prints.size()):
		multimesh.set_instance_transform(i, _prints[i].xf)
