extends CharacterBody3D

# ── 3D のプレイヤーと、見下ろしの固定カメラ ─────────────────────────
# 1 unit = 1m。地面は y = 0 の平面。WASD/矢印で東西南北に歩く(画面の上 = 北 = -z)
signal plant_tree(pos)  # 足元の位置(m)
signal work_sound(kind)  # 作業の道具が当たった(音を鳴らす)

const WorkEffects = preload("res://view/3d/WorkEffects3D.gd")

const SPEED := 5.0        # m/s(設計作業がしやすい速さ。2D と同じ)
const TURN_SPEED := 12.0  # 向きを変える速さ

# カメラ: 斜め上から見下ろす。ホイールで距離を変える(寄ると足元、引くと土地全体)
const CAM_PITCH_DEG := 55.0
const CAM_DIST_MIN := 6.0
const CAM_DIST_MAX := 140.0
const CAM_FOLLOW := 6.0   # 追いかけの速さ(大きいほどぴったり付いてくる)
const LANTERN_ENERGY := 0.8
# 影を描く距離はカメラの距離に合わせる(寄ったときに影がくっきりする)
const SHADOW_DIST_PER_CAM := 3.0
const SHADOW_DIST_MIN := 60.0
const SHADOW_DIST_MAX := 200.0
# 小屋の中ではカメラが寄る。外の距離は覚えておき、出ると戻る
const INDOOR_CAM_DIST := 10.0
const INDOOR_CAM_MAX := 14.0
const STEP_SPEED := 1.5   # 床の高さまで体が上がる速さ(m/s)
const WALK_LIMIT := 78.0  # 歩ける範囲(東西南北)。この外は丘(GroundView3D.HILL_START)で、体が地面に埋まる
const LIE_SECONDS := 0.8     # ベッドに横になるのにかかる時間
const GET_UP_SECONDS := 0.5  # 起き上がるのにかかる時間
const SIT_SECONDS := 0.5     # 腰掛けに座るのにかかる時間
# 横になった体の向き: 頭が西、顔が上(体の +y が西、正面の -z が上)
const LYING_BASIS := Basis(Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, -1, 0))
const FACE_MIN_DIST := 0.3   # 作業の相手がこれより近ければ、向きを変えない
const WORK_REACH := 1.0      # 作業で物が飛ぶ場所は、体からこの距離まで

@onready var _body: Node3D = $Body
@onready var _figure: Node3D = $Body/Figure
@onready var _camera: Camera3D = $Camera3D
@onready var _lantern: Node3D = $Body/Lantern
@onready var _lantern_light: OmniLight3D = $LanternLight

var speed_scale := 1.0    # 歩く速さの倍率(雪かき。Main が毎フレーム決める)
var move_input := Vector2.ZERO  # タッチのスティックの傾き(長さ 0〜1。上 = 北 = -y)
var _cam_dist := 28.0
var shadow_light: DirectionalLight3D  # Main が太陽を渡す
var _indoors := false
var _indoor_dist := INDOOR_CAM_DIST
var _floor_y := 0.0
var _night := 0.0
var _lying := false       # ベッドに横になっている
var _posing := false      # 横になる / 起き上がる動きの途中か、横になっている(体の位置と向きは _pose が動かす)
var _pose: Tween
var _stand_basis := Basis.IDENTITY  # 横になる前の体の向き
var _face_yaw = null      # 作業の相手へ向く角度。なければ null
var _effects: Node3D      # 作業のときに飛ぶもの
var _effect_tween: Tween

func _ready() -> void:
	_body.rotation.y = PI  # 始めはカメラのほうを向いて、顔が見えるように
	_figure.hold(_lantern)
	_figure.action_finished.connect(_on_action_finished)
	_effects = WorkEffects.new()
	_effects.name = "WorkEffects"
	_effects.top_level = true
	_effects.figure = _figure
	add_child(_effects)
	_camera.top_level = true  # プレイヤーの回転に引きずられないように、カメラは独立して動かす
	_camera.global_position = global_position + _cam_offset()
	_camera.look_at(global_position)

func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_UP)    or Input.is_key_pressed(KEY_W): dir.z -= 1
	if Input.is_key_pressed(KEY_DOWN)  or Input.is_key_pressed(KEY_S): dir.z += 1
	if Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): dir.x += 1
	dir = dir.normalized()
	if dir == Vector3.ZERO:
		dir = Vector3(move_input.x, 0.0, move_input.y)  # タッチのスティック。傾きで速さが変わる
	velocity = dir * SPEED * speed_scale
	move_and_slide()
	position.x = clampf(position.x, -WALK_LIMIT, WALK_LIMIT)
	position.z = clampf(position.z, -WALK_LIMIT, WALK_LIMIT)
	if dir != Vector3.ZERO and not _posing:
		_face_yaw = null  # 歩きだしたら、進む向きが優先
		# 進む向きに体を回す(-z が正面)
		var target := atan2(-dir.x, -dir.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, target, minf(1.0, TURN_SPEED * delta))

func _process(delta: float) -> void:
	# 市場を開いている間(物理が止まる)や、壁に当たって進めないときは足を止める
	_figure.moving = is_physics_processing() and get_real_velocity().length() > 0.1
	if not _posing:
		_body.position.y = move_toward(_body.position.y, _floor_y if _indoors else 0.0, STEP_SPEED * delta)
		if _face_yaw != null:
			_body.rotation.y = lerp_angle(_body.rotation.y, _face_yaw, minf(1.0, TURN_SPEED * delta))
	var goal := global_position + _cam_offset()
	_camera.global_position = _camera.global_position.lerp(goal, 1.0 - exp(-CAM_FOLLOW * delta))
	_camera.look_at(_camera.global_position - _cam_offset())
	# 世界が丸く曲がる中心は、カメラが見ている地面の場所
	RenderingServer.global_shader_parameter_set("bend_center", _camera.global_position - _cam_offset())

func _cam_offset() -> Vector3:
	var pitch := deg_to_rad(CAM_PITCH_DEG)
	return Vector3(0, sin(pitch), cos(pitch)) * view_distance()

# 今のカメラの距離(小屋の中と外で別に覚える)
func view_distance() -> float:
	return _indoor_dist if _indoors else _cam_dist

func is_indoors() -> bool:
	return _indoors

# 小屋に入った / 出た。floor_y は床の高さ(m)
func set_indoors(indoors: bool, floor_y := 0.0) -> void:
	_indoors = indoors
	_floor_y = floor_y
	update_shadow_distance()

# 作業の動きをする。kind は PlayerFigure3D.ACTIONS のどれか。target は相手の位置(m の Vector2。なければ今の向きのまま)、
# item は収穫物(飛ぶ玉の色)。歩いているあいだもできる(足はそのまま動く)
func act(kind: String, target = null, item := "") -> void:
	if _posing:
		return
	var here := Vector3(global_position.x, 0.0, global_position.z)
	var front: Vector3 = -_body.global_basis.z
	var reach := WORK_REACH * 0.8
	if target != null:
		var to := Vector3(target.x, 0.0, target.y) - here
		if to.length() > FACE_MIN_DIST:
			front = to.normalized()
			_face_yaw = atan2(-front.x, -front.z)
			reach = minf(to.length(), WORK_REACH)
	var spot: Vector3 = here + Vector3(front.x, 0.0, front.z) * reach
	spot.y = _floor_y if _indoors else 0.0
	_figure.play(kind)
	_apply_lantern()
	if _effect_tween != null:
		_effect_tween.kill()
	_effect_tween = create_tween()
	_effect_tween.tween_callback(_on_work_hit.bind(kind, spot, item)).set_delay(float(_figure.ACTIONS[kind].hit))

func _on_work_hit(kind: String, spot: Vector3, item: String) -> void:
	_effects.play(kind, spot, item)
	work_sound.emit(kind)

# 歩いているか(足音を鳴らす)
func is_walking() -> bool:
	return is_physics_processing() and get_real_velocity().length() > 0.1

func _on_action_finished() -> void:
	_apply_lantern()

func is_lying() -> bool:
	return _lying

# ベッドに横になる。spot は足の裏の位置(世界の座標)。動くのは見た目の体だけで、足元の位置(当たり判定)は変わらない
func lie_down(spot: Vector3) -> void:
	_lying = true
	_posing = true
	_stand_basis = _body.basis
	_apply_lantern()
	_move_pose(spot - global_position, LYING_BASIS, LIE_SECONDS)

# 起き上がる。動きの途中でも歩きはじめられる(体があとから追いつく)
func get_up() -> void:
	_lying = false
	_move_pose(Vector3(0.0, _floor_y if _indoors else 0.0, 0.0), _stand_basis, GET_UP_SECONDS)
	_pose.finished.connect(_on_got_up)

# 腰掛けに座る。seat は座面の中心(世界の座標)、yaw は向き。動くのは見た目の体だけで、足元の位置は変わらない
func sit_down(seat: Vector3, yaw: float) -> void:
	_posing = true
	_stand_basis = _body.basis
	_figure.sitting = true
	_apply_lantern()
	_move_pose(seat - Vector3(0.0, _figure.HIP_Y, 0.0) - global_position, Basis(Vector3.UP, yaw), SIT_SECONDS)

func stand_up() -> void:
	_figure.sitting = false
	_move_pose(Vector3(0.0, _floor_y if _indoors else 0.0, 0.0), _stand_basis, GET_UP_SECONDS)
	_pose.finished.connect(_on_got_up)

# 座ったまま食べる動き(座っているあいだも動く)
func eat_motion() -> void:
	_figure.play("eat")

func _on_got_up() -> void:
	_posing = false
	_apply_lantern()

func _move_pose(offset: Vector3, basis_to: Basis, seconds: float) -> void:
	if _pose != null:
		_pose.kill()
	_pose = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pose.tween_property(_body, "position", offset, seconds)
	_pose.tween_property(_body, "quaternion", basis_to.get_rotation_quaternion(), seconds)

func zoom(factor: float) -> void:
	if _indoors:
		_indoor_dist = clampf(_indoor_dist * factor, CAM_DIST_MIN, INDOOR_CAM_MAX)
	else:
		_cam_dist = clampf(_cam_dist * factor, CAM_DIST_MIN, CAM_DIST_MAX)
	update_shadow_distance()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey \
			and event.keycode == KEY_SPACE \
			and event.pressed \
			and not event.echo:
		plant_tree.emit(ground_pos())
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(0.85)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1.0 / 0.85)

func update_shadow_distance() -> void:
	if shadow_light != null:
		shadow_light.directional_shadow_max_distance = clampf(view_distance() * SHADOW_DIST_PER_CAM, SHADOW_DIST_MIN, SHADOW_DIST_MAX)

# 暗くなるとランタンをともす(0 = 昼、1 = 夜)
func set_night(amount: float) -> void:
	_night = amount
	_apply_lantern()
	_lantern_light.visible = amount > 0.0
	_lantern_light.light_energy = LANTERN_ENERGY * amount

# 横になっているあいだと、道具を持つ作業のあいだはランタンを手に持たない
func _apply_lantern() -> void:
	var holding: bool = _night > 0.0 and not _posing and not _figure.is_acting()
	_lantern.visible = holding
	_figure.holding_lantern = holding

# 向いている方向(長さ 1。ロジックの座標)
func facing() -> Vector2:
	var f: Vector3 = -_body.global_basis.z
	return Vector2(f.x, f.z).normalized()

# 足元の位置(m)。ロジックの座標 Vector2(x, y) は 3D の (x, z)
func ground_pos() -> Vector2:
	return Vector2(global_position.x, global_position.z)
