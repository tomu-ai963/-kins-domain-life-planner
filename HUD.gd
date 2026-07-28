extends CanvasLayer

const PIXELS_PER_METER := 40.0

onready var _label: Label = $PositionLabel

var _player: Node2D
var _trees: Node2D
var _main: Node2D

func setup(player: Node2D, trees: Node2D, main: Node2D) -> void:
	_player = player
	_trees = trees
	_main = main

func _process(_delta: float) -> void:
	if _player == null:
		return
	var pos_m: Vector2 = _player.global_position / PIXELS_PER_METER
	var dt: Dictionary = OS.get_datetime()
	var season_jp: String = _main.SEASON_NAMES[_main.season]
	var sp_name: String = _trees.SPECIES[_main.selected_species].name

	var offset := ""
	if _trees.time_offset_years > 0.0:
		offset = "  (+%d年後)" % int(_trees.time_offset_years)

	_label.text = (
		"%04d/%02d/%02d  %s%s\n" +
		"X:%6.1f m  Y:%6.1f m   木: %d本\n" +
		"選択: %s\n" +
		"[1]白樺 [2]リンゴ [3]シベリア杉\n" +
		"SPACE:植える  Z:抜く  ホイール:ズーム\n" +
		"T:+1年  G:+10年 (未来をプレビュー)"
	) % [
		dt.year, dt.month, dt.day, season_jp, offset,
		pos_m.x, pos_m.y, _trees.trees.size(),
		sp_name,
	]
