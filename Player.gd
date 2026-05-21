extends KinematicBody2D

signal plant_tree(pos)

# 1m = 40px。 100mを90秒で歩く現実的な速度 ≈ 44.4 px/s
const PIXELS_PER_METER := 40.0
const SPEED := (100.0 / 90.0) * PIXELS_PER_METER

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
