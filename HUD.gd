extends CanvasLayer

const PIXELS_PER_METER := 40.0

onready var _label: Label = $PositionLabel

var player: Node2D

func _process(_delta: float) -> void:
	if player == null:
		return
	var pos_m: Vector2 = player.global_position / PIXELS_PER_METER
	_label.text = "X: %6.1f m\nY: %6.1f m" % [pos_m.x, pos_m.y]
