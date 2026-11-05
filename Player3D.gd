extends CharacterBody3D

# ── 3D のプレイヤーと、見下ろしの固定カメラ ─────────────────────────
# 1 unit = 1m。地面は y = 0 の平面。WASD/矢印で東西南北に歩く(画面の上 = 北 = -z)
signal plant_tree(pos)  # 足元の位置(m)

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

@onready var _body: Node3D = $Body
@onready var _figure: Node3D = $Body/Figure
@onready var _camera: Camera3D = $Camera3D
@onready var _lantern: Node3D = $Body/Lantern
@onready var _lantern_light: OmniLight3D = $LanternLight

var _cam_dist := 28.0
var shadow_light: DirectionalLight3D  # Main が太陽を渡す
var _indoors := false
var _indoor_dist := INDOOR_CAM_DIST
var _floor_y := 0.0

func _ready() -> void:
	_body.rotation.y = PI  # 始めはカメラのほうを向いて、顔が見えるように
	_figure.hold(_lantern)
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
	velocity = dir * SPEED
	move_and_slide()
	if dir != Vector3.ZERO:
		# 進む向きに体を回す(-z が正面)
		var target := atan2(-dir.x, -dir.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, target, minf(1.0, TURN_SPEED * delta))

func _process(delta: float) -> void:
	# 市場を開いている間(物理が止まる)や、壁に当たって進めないときは足を止める
	_figure.moving = is_physics_processing() and get_real_velocity().length() > 0.1
	_body.position.y = move_toward(_body.position.y, _floor_y if _indoors else 0.0, STEP_SPEED * delta)
	var goal := global_position + _cam_offset()
	_camera.global_position = _camera.global_position.lerp(goal, 1.0 - exp(-CAM_FOLLOW * delta))
	_camera.look_at(_camera.global_position - _cam_offset())

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

func _zoom(factor: float) -> void:
	if _indoors:
		_indoor_dist = clampf(_indoor_dist * factor, CAM_DIST_MIN, INDOOR_CAM_MAX)
	else:
		_cam_dist = clampf(_cam_dist * factor, CAM_DIST_MIN, CAM_DIST_MAX)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey \
			and event.keycode == KEY_SPACE \
			and event.pressed \
			and not event.echo:
		plant_tree.emit(ground_pos())
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(0.85)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 / 0.85)
		update_shadow_distance()

func update_shadow_distance() -> void:
	if shadow_light != null:
		shadow_light.directional_shadow_max_distance = clampf(view_distance() * SHADOW_DIST_PER_CAM, SHADOW_DIST_MIN, SHADOW_DIST_MAX)

# 暗くなるとランタンをともす(0 = 昼、1 = 夜)
func set_night(amount: float) -> void:
	_lantern.visible = amount > 0.0
	_figure.holding_lantern = amount > 0.0
	_lantern_light.visible = amount > 0.0
	_lantern_light.light_energy = LANTERN_ENERGY * amount

# 足元の位置(m)。ロジックの座標 Vector2(x, y) は 3D の (x, z)
func ground_pos() -> Vector2:
	return Vector2(global_position.x, global_position.z)
