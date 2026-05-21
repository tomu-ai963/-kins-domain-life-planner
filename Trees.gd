extends Node2D

# 成長速度: 1.5 px/s = 0.0375 m/s
# 最大半径: 160px = 4m (成熟した樹冠)
const GROWTH_RATE := 1.5
const MAX_RADIUS  := 160.0

var _trees := []  # Array of {pos: Vector2, age: float}

func add_tree(pos: Vector2) -> void:
	_trees.append({"pos": pos, "age": 0.0})

func _process(delta: float) -> void:
	if _trees.size() == 0:
		return
	for tree in _trees:
		tree.age += delta
	update()

func _draw() -> void:
	for tree in _trees:
		var r := min(tree.age * GROWTH_RATE, MAX_RADIUS)
		_draw_tree(tree.pos, r)

func _draw_tree(pos: Vector2, radius: float) -> void:
	if radius < 5.0:
		# 苗木フェーズ: 小さな点
		draw_circle(pos, 3.0, Color(0.15, 0.65, 0.15))
	else:
		# 成長フェーズ: 樹冠（半透明の大円）+ 幹（小さな暗い点）
		draw_circle(pos, radius,       Color(0.10, 0.55, 0.12, 0.60))
		draw_circle(pos, radius * 0.4, Color(0.08, 0.42, 0.09, 0.30))
		draw_circle(pos, 3.5,          Color(0.10, 0.30, 0.05))
