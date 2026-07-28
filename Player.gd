extends KinematicBody2D

signal plant_tree(pos)

# 1m = 40px。設計作業がしやすいよう 5 m/s (= 200 px/s) に設定
const PIXELS_PER_METER := 40.0
const SPEED := 5.0 * PIXELS_PER_METER

const ZOOM_MIN := 0.4
const ZOOM_MAX := 4.0

onready var _camera: Camera2D = $Camera2D

var _zoom := 1.0

func _physics_process(_delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_UP)    or Input.is_key_pressed(KEY_W): dir.y -= 1
	if Input.is_key_pressed(KEY_DOWN)  or Input.is_key_pressed(KEY_S): dir.y += 1
	if Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): dir.x += 1
	if dir.length() > 0:
		dir = dir.normalized()
	move_and_slide(dir * SPEED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey \
			and event.scancode == KEY_SPACE \
			and event.pressed \
			and not event.echo:
		emit_signal("plant_tree", global_position)
	elif event is InputEventMouseButton and event.pressed:
		# ホイールでズーム（引くと土地全体、寄ると足元）
		if event.button_index == BUTTON_WHEEL_UP:
			_set_zoom(_zoom * 0.85)
		elif event.button_index == BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom / 0.85)

func _set_zoom(z: float) -> void:
	_zoom = clamp(z, ZOOM_MIN, ZOOM_MAX)
	_camera.zoom = Vector2(_zoom, _zoom)
