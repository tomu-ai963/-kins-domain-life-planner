extends CharacterBody2D

signal plant_tree(pos)  # 足元の位置(m)

# 1m = 40px。設計作業がしやすいよう 5 m/s (= 200 px/s) に設定
const PIXELS_PER_METER := 40.0
const SPEED := 5.0 * PIXELS_PER_METER

# 見える範囲の倍率(大きいほど引いて土地全体が見える)。Godot 4 の Camera2D.zoom はこの逆数
const ZOOM_MIN := 0.4
const ZOOM_MAX := 4.0

@onready var _camera: Camera2D = $Camera2D

var _zoom := 1.0

func _physics_process(_delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_UP)    or Input.is_key_pressed(KEY_W): dir.y -= 1
	if Input.is_key_pressed(KEY_DOWN)  or Input.is_key_pressed(KEY_S): dir.y += 1
	if Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): dir.x += 1
	velocity = dir.normalized() * SPEED
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey \
			and event.keycode == KEY_SPACE \
			and event.pressed \
			and not event.echo:
		plant_tree.emit(ground_pos())
	elif event is InputEventMouseButton and event.pressed:
		# ホイールでズーム（引くと土地全体、寄ると足元）
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_zoom * 0.85)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom / 0.85)

# 足元の位置(m)。ロジックの座標
func ground_pos() -> Vector2:
	return global_position / PIXELS_PER_METER

func _set_zoom(z: float) -> void:
	_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	_camera.zoom = Vector2.ONE / _zoom
