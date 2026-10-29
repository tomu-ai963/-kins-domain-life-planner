extends CanvasLayer

const PIXELS_PER_METER := 40.0
const MESSAGE_SECONDS := 3.0

onready var _label: Label = $PositionLabel

var _player: Node2D
var _trees: Node2D
var _main: Node2D

var _message := ""
var _message_timer := 0.0

func setup(player: Node2D, trees: Node2D, main: Node2D) -> void:
	_player = player
	_trees = trees
	_main = main

# 植えられない・収穫した などを数秒だけ出す
func show_message(text: String, seconds: float = MESSAGE_SECONDS) -> void:
	_message = text
	_message_timer = seconds

func _process(delta: float) -> void:
	if _player == null:
		return
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message = ""

	var pos_m: Vector2 = _player.global_position / PIXELS_PER_METER
	var dt: Dictionary = OS.get_datetime()
	var season_jp: String = _main.SEASON_NAMES[_main.season]
	var sp_name: String = _trees.SPECIES[_main.selected_species].name
	var seeds: Dictionary = _trees.seeds

	var offset := ""
	if _trees.time_offset_years > 0.0:
		offset = "  (+%d年後をプレビュー中)" % int(_trees.time_offset_years)

	# 今日の発見は一日中見られるように常に出す
	var today := "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]
	var found := ""
	if _trees.last_day == today and _trees.today_event != "":
		found = _main.DAILY_MESSAGES[_trees.today_event]

	_label.text = (
		"%04d/%02d/%02d  %s%s\n" +
		"X:%6.1f m  Y:%6.1f m   木: %d本\n" +
		"種: 白樺 %d  リンゴ %d  シベリア杉 %d\n" +
		"選択: %s\n" +
		"今日の発見: %s\n" +
		"[1]白樺 [2]リンゴ [3]シベリア杉\n" +
		"SPACE:植える  Q:水やり  E:収穫  Z:抜く  ホイール:ズーム\n" +
		"T:+1年  G:+10年  R:今日に戻す (未来をプレビュー)\n" +
		"%s"
	) % [
		dt.year, dt.month, dt.day, season_jp, offset,
		pos_m.x, pos_m.y, _trees.trees.size(),
		seeds.birch, seeds.apple, seeds.cedar,
		sp_name,
		found,
		_message,
	]
