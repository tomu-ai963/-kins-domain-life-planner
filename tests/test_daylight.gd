extends SceneTree

# 昼夜の光のテスト。太陽の位置(logic/DayClock.gd)と、3D のシーンの光・明かり・HUD の時計。本物のセーブには触れない。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_daylight.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる

const DayClock = preload("res://logic/DayClock.gd")
const DayLight = preload("res://view/3d/DayLightView3D.gd")
const TEST_SAVE := "user://test_daylight.json"

var _failed := 0
var _passed := 0
var _frame := 0
var main

func _initialize() -> void:
	_remove_save()
	_test_sun_position()
	_test_light_keys()
	main = load("res://Main.tscn").instantiate()
	main.world.save_path = TEST_SAVE
	main.world.clock.fixed_now = {"month": 11, "day": 5, "hour": 12, "minute": 0, "second": 0}
	root.add_child(main)

func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_clear_weather()  # 天気は日付で決まる。テストを走らせる日によって結果が変わらないように、晴れにする
			_test_scene_light()
			_test_overcast()
			_test_night_lamps()
			_test_preview_keys()
			_test_rules_ignore_clock()
			_test_2d_has_no_light()
		4:
			main.queue_free()
			_remove_save()
		6:
			print("RESULT: %d passed, %d failed" % [_passed, _failed])
			quit(1 if _failed > 0 else 0)
	return false

func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)

func _remove_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func _elev(hours: float, doy: int) -> float:
	return DayClock.elevation_deg(DayClock.to_sun(hours, doy))

# 太陽の高さが 0 をまたぐ時刻を 1 分刻みで探す(from から to へ)
func _crossing(doy: int, from: float, to: float) -> float:
	var h := from
	var step := 1.0 / 60.0 * signf(to - from)
	while absf(h - to) > 0.02:
		if signf(_elev(h, doy)) != signf(_elev(from, doy)):
			return h
		h += step
	return -1.0

func _hm(h: float) -> String:
	return "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]

func _test_sun_position() -> void:
	print("太陽の位置")
	var june21 := DayClock.day_of_year(6, 21)
	var dec21 := DayClock.day_of_year(12, 21)
	var nov5 := DayClock.day_of_year(11, 5)
	_check(DayClock.day_of_year(1, 1) == 1 and DayClock.day_of_year(12, 31) == 365, "1 月 1 日が 1、12 月 31 日が 365")

	# 日本のまんなかあたりの、だいたいの日の出・日の入りと照らす(大気の屈折を入れないので数分ずれる)
	var rise_june := _crossing(june21, 12.0, 0.0)
	var set_june := _crossing(june21, 12.0, 24.0)
	var set_nov := _crossing(nov5, 12.0, 24.0)
	var rise_dec := _crossing(dec21, 12.0, 0.0)
	var set_dec := _crossing(dec21, 12.0, 24.0)
	print("    夏至 %s〜%s / 11月5日の日の入り %s / 冬至 %s〜%s" % [_hm(rise_june), _hm(set_june), _hm(set_nov), _hm(rise_dec), _hm(set_dec)])
	_check(rise_june > 4.3 and rise_june < 5.0, "夏至の日の出は 4 時台")
	_check(set_june > 18.8 and set_june < 19.4, "夏至の日の入りは 19 時ごろ")
	_check(set_nov > 16.6 and set_nov < 17.2, "11 月 5 日の日の入りは 17 時ごろ")
	_check(rise_dec > 6.7 and rise_dec < 7.3, "冬至の日の出は 7 時ごろ")
	_check(set_dec > 16.5 and set_dec < 17.0, "冬至の日の入りは 16 時台")
	_check(set_june - rise_june > (set_dec - rise_dec) + 4.0, "夏の昼は冬より 4 時間以上長い")

	var noon_june: float = _elev(12.0, june21)
	var noon_dec: float = _elev(12.0, dec21)
	print("    正午の高さ: 夏至 %.0f度 / 冬至 %.0f度" % [noon_june, noon_dec])
	_check(noon_june > 75.0 and noon_june < 80.0, "夏至の正午の太陽は 78 度くらい")
	_check(noon_dec > 29.0 and noon_dec < 33.0, "冬至の正午の太陽は 31 度くらい")

	# 東から昇って南を通り西へ沈む(x = 東、z = 南)
	var morning := DayClock.to_sun(8.0, nov5)
	var noon := DayClock.to_sun(12.0, nov5)
	var evening := DayClock.to_sun(16.0, nov5)
	_check(morning.x > 0.3, "朝の太陽は東(+x)")
	_check(noon.z > 0.5 and absf(noon.x) < 0.2, "昼の太陽は南(+z)。カメラの後ろから当たる")
	_check(evening.x < -0.3, "夕方の太陽は西(-x)")
	_check(is_equal_approx(noon.length(), 1.0), "方向の長さは 1")

	_check(DayClock.darkness(30.0) == 0.0, "太陽が高ければ暗さ 0")
	_check(DayClock.darkness(-30.0) == 1.0, "太陽が沈みきれば暗さ 1")
	_check(DayClock.darkness(1.0) > 0.0 and DayClock.darkness(1.0) < 1.0, "夕方は途中の暗さ")

func _test_light_keys() -> void:
	print("光の表")
	var day: Dictionary = DayLight.sample(40.0)
	_check(day.energy > 0.5 and is_equal_approx(day.ambient, 0.4) and day.light.is_equal_approx(Color.WHITE), "昼は白い光で、環境光 0.4")
	_check(DayLight.sample(60.0).energy > DayLight.sample(15.0).energy, "太陽が高いほど明るい")
	_check(DayLight.sample(5.0).light.b < 0.8, "太陽が低いと光が暖色になる")
	_check(DayLight.sample(-30.0).light.b > DayLight.sample(-30.0).light.r, "夜の光は青い")
	_check(DayLight.sample(-1.0).energy == 0.0, "太陽と月が入れ替わるところでは光が 0(向きが飛んでも見えない)")
	# 途切れずにつながる: 0.1 度ごとに光の強さが大きく飛ばない
	var jump := 0.0
	var e := -20.0
	while e < 40.0:
		jump = maxf(jump, absf(DayLight.sample(e + 0.1).energy - DayLight.sample(e).energy))
		e += 0.1
	_check(jump < 0.04, "光の強さは途切れずに変わる(0.1 度あたり最大 %.3f)" % jump)
	var low := DayLight.light_dir(Vector3(1, 0.02, 0).normalized())
	_check(is_equal_approx(DayClock.elevation_deg(low), 12.0) and low.x > 0.9, "低い太陽は高さだけを止める(影が伸びすぎない。向きは変えない)")
	var moon := DayLight.light_dir(Vector3(0.3, -0.8, 0.5).normalized())
	_check(moon.y > 0.5 and moon.x < 0.0, "夜は太陽の反対側の月から照らす")
	var low_moon := DayLight.light_dir(Vector3(0.9, -0.1, 0.4).normalized())
	_check(is_equal_approx(DayClock.elevation_deg(low_moon), 40.0) and low_moon.x < 0.0, "日没直後の低い月も 40 度の高さから照らす")
	_check(is_equal_approx(DayLight.light_dir(DayClock.to_sun(12.0, 172)).length(), 1.0) and is_equal_approx(low.length(), 1.0), "光の向きの長さは 1")
	_check(DayLight.sample(-30.0).energy > 0.0, "深夜の月も光る")

func _at(hour: int) -> void:
	main.world.clock.fixed_now = {"month": 11, "day": 5, "hour": hour, "minute": 0, "second": 0}
	main.get_node("DayLight").apply_light()

func _test_scene_light() -> void:
	print("シーンの光")
	var sun: DirectionalLight3D = main.get_node("Sun")
	var env: Environment = main.get_node("WorldEnvironment").environment
	_at(12)
	_check(sun.light_energy > 0.5, "正午の太陽は強い")
	var travel := -sun.global_transform.basis.z
	_check(travel.y < -0.5 and travel.z < -0.3, "正午の光は上から北へ向かって差す(影は画面の上へ伸びる)")
	var noon_sky := (env.sky.sky_material as ProceduralSkyMaterial).sky_top_color
	_at(16)
	var dusk := sun.light_color
	_check(dusk.b < 0.9, "夕方前の光は暖色になる")
	_check((-sun.global_transform.basis.z).x > 0.2, "夕方の光は西から東へ向かって差す(影は東へ伸びる)")
	_at(0)
	_check(sun.light_energy < 0.5 and sun.light_color.b > sun.light_color.r, "真夜中は弱い青い光")
	var night_sky := (env.sky.sky_material as ProceduralSkyMaterial).sky_top_color
	_check(night_sky.get_luminance() < noon_sky.get_luminance() * 0.3, "夜の空(環境光のもと)は暗い")
	_check(env.fog_light_color.get_luminance() < 0.3, "夜は遠くのかすみも暗い")
	_check(sun.light_energy >= 0.2 and env.ambient_light_energy >= 1.0, "夜でも真っ暗にはしない(月の光と、強めの環境光)")
	_at(12)

func _clear_weather() -> void:
	main.world.forest.today_event = "birds"
	main.get_node("Weather").refresh(true)

func _test_overcast() -> void:
	print("雨の光")
	var f = main.world.forest
	var weather = main.get_node("Weather")
	var light = main.get_node("DayLight")
	var sun: DirectionalLight3D = main.get_node("Sun")
	var env: Environment = main.get_node("WorldEnvironment").environment
	_at(12)
	var clear_energy := sun.light_energy
	var clear_top: Color = (env.sky.sky_material as ProceduralSkyMaterial).sky_top_color
	var clear_fog := env.fog_density
	_check(not weather.is_falling(), "晴れの日は何も降らない")

	f.last_day = f.today()
	f.today_event = "rain"
	f.season = "summer"
	weather.refresh(true)
	var top: Color = (env.sky.sky_material as ProceduralSkyMaterial).sky_top_color
	_check(sun.light_energy < clear_energy * 0.5, "雨の日は太陽の光が弱い")
	_check(top.b - top.r < clear_top.b - clear_top.r, "雨の日は空が灰色に寄る")
	_check(env.fog_density > clear_fog, "雨の日は遠くがかすむ")
	_check(weather.get_node("Rain").emitting and weather.get_node("Ripples").emitting, "雨粒が降り、地面に波紋が出る")
	_check(not weather.get_node("Snow").emitting, "冬でなければ雪は降らない")

	f.season = "winter"
	weather.refresh(true)
	_check(weather.get_node("Snow").emitting and not weather.get_node("Rain").emitting, "冬の同じ日は雪になる")
	_check(sun.light_energy < clear_energy * 0.5, "雪の日も暗い")
	_check(main.daily_message("rain").begins_with("雪"), "冬の文言は雪になる")
	f.season = "summer"
	_check(main.daily_message("rain").begins_with("雨"), "冬でなければ文言は雨のまま")

	# 雨の夜が晴れの夜より明るくならない
	_at(0)
	var rain_ambient := env.ambient_light_energy
	var rain_night_top: Color = (env.sky.sky_material as ProceduralSkyMaterial).sky_top_color
	_clear_weather()
	_at(0)
	var clear_night_top: Color = (env.sky.sky_material as ProceduralSkyMaterial).sky_top_color
	_check(rain_night_top.get_luminance() <= clear_night_top.get_luminance() + 0.02, "雨の夜の空が晴れの夜より明るくならない")
	_check(rain_ambient >= 1.0, "雨の夜も真っ暗にはならない")

	# 雨が上がる・降りだすときは少しずつ変わる
	_at(12)
	f.today_event = "rain"
	weather.refresh(false)
	_check(light.overcast == 0.0 and sun.light_energy == clear_energy, "降りだしの瞬間はまだ晴れの光")
	light._process(1.0)
	_check(light.overcast > 0.0 and light.overcast < 1.0 and sun.light_energy < clear_energy, "少しずつ暗くなる")
	light._process(10.0)
	_check(is_equal_approx(light.overcast, 1.0), "やがて雨の光になる")

	# 前の日の雨は続かない
	f.last_day = "2000-01-01"
	weather.refresh(true)
	_check(not f.is_raining() and not weather.is_falling(), "日付が変わるまでの前の日の雨は降らない")

	# 小屋の中には降らない
	f.last_day = f.today()
	weather.refresh(true)
	var player = main.get_node("Player")
	player.set_indoors(true, 0.3)
	weather._process(0.016)
	_check(not weather.visible, "小屋の中では雨を見せない")
	player.set_indoors(false)
	weather._process(0.016)
	_check(weather.visible, "外に出るとまた降っている")

	# カメラについてきて、距離に合わせて広がる
	player.global_position = Vector3(10, 0, -5)
	player._cam_dist = weather.BASE_DIST * 2.0
	weather._process(0.016)
	_check(is_equal_approx(weather.global_position.x, 10.0) and is_equal_approx(weather.global_position.z, -5.0), "降る範囲はプレイヤーについてくる")
	_check(is_equal_approx(weather.scale.x, 2.0), "カメラを引くと降る範囲も広がる")
	player.global_position = Vector3.ZERO
	player._cam_dist = weather.BASE_DIST

	_clear_weather()

func _test_night_lamps() -> void:
	print("夜の明かり")
	var player = main.get_node("Player")
	var lantern: OmniLight3D = player.get_node("LanternLight")
	var market_light: OmniLight3D = main.get_node("Market")._lantern_light
	_at(12)
	_check(not lantern.visible and not market_light.visible, "昼はランタンも屋台の明かりも消えている")
	_at(0)
	_check(lantern.visible and lantern.light_energy > 0.5, "夜はプレイヤーのランタンがともる")
	_check(market_light.visible, "夜は屋台の明かりがともる")

	var c = main.world.cabin
	var cabin_view: Node3D = main.get_node("Cabin")
	player.global_position = Vector3(20, 0, 20)
	main._cabin_action()
	player.global_position = Vector3(20, 0, 22.5)
	c.materials.log = 29
	for i in range(c.total_days() - 1):
		c.last_worked = ""
		main._cabin_action()
	_check(not c.is_complete() and cabin_view._lamp_light == null, "完成前の小屋には明かりがない")
	_check(not cabin_view._window.emission_enabled, "完成前の窓は光らない")
	c.last_worked = ""
	main._cabin_action()
	_check(c.is_complete() and cabin_view._lamp_light != null and cabin_view._lamp_light.visible, "夜に完成すると、軒の明かりがともる")
	_check(cabin_view._window.emission_enabled, "夜の窓は光る")
	_at(12)
	_check(not cabin_view._lamp_light.visible and not cabin_view._window.emission_enabled, "朝になると消える")
	_at(0)
	main.world.seedlings.changed.emit()  # 小屋を作り直しても
	_check(cabin_view._lamp_light.visible and cabin_view._window.emission_enabled, "作り直しても夜の明かりは残る")
	_at(12)

func _press(keycode: int) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	main._unhandled_input(e)

func _test_preview_keys() -> void:
	print("時間のプレビューと HUD の時計")
	var clock = main.world.clock
	var hud = main.get_node("HUD")
	var day_light = main.get_node("DayLight")
	var sun: DirectionalLight3D = main.get_node("Sun")
	clock.fixed_now = {"month": 11, "day": 5, "hour": 9, "minute": 5, "second": 0}
	day_light.apply_light()
	_check(hud.status_text().contains("09:05"), "HUD に今の時刻が出る")
	_check(not hud.status_text().contains("プレビュー中"), "ふだんはプレビューの表示なし")
	var before := sun.basis
	_press(KEY_N)
	_check(clock.preview_hours == 1.0 and hud.status_text().contains("10:05") and hud.status_text().contains("+1時間"), "N で 1 時間先の時刻になる")
	day_light._process(0.05)
	_check(sun.basis != before, "光はすぐ動きはじめる")
	day_light._process(1.0)
	_check(is_equal_approx(day_light._shown_offset, 1.0), "光が 1 時間先に追いつく")
	for i in range(23):
		_press(KEY_N)
	_check(clock.preview_hours == 0.0 and not clock.is_preview(), "24 回で一回りして今に戻る")
	for i in range(13):
		_press(KEY_N)
	_press(KEY_R)
	_check(clock.preview_hours == 0.0, "R で今に戻る")
	day_light._process(10.0)
	_check(is_equal_approx(wrapf(day_light._shown_offset, -12.0, 12.0), 0.0), "光も今に戻る")
	var t_before: float = main.world.forest.time_offset_years
	_press(KEY_N)
	_check(main.world.forest.time_offset_years == t_before, "N は木の年のプレビューを動かさない")
	_press(KEY_R)
	day_light._process(10.0)
	_press(KEY_F1)
	_check(hud.status_text().contains("N:+1時間"), "F1 の操作説明に N が出る")
	_press(KEY_F1)
	var lines: int = hud.status_text().split("\n").size()
	_check(lines <= 8, "HUD のいつもの行数は増やしていない(%d 行)" % lines)

func _test_rules_ignore_clock() -> void:
	print("ルールには効かない")
	var w = main.world
	var f = w.forest
	f.saplings.birch = 1
	f.add_tree(Vector2(-30, -30), "birch", "sapling")
	var age_probe: Dictionary = f.trees[-1]
	var age: float = f.real_age_years(age_probe)
	for i in range(5):
		_press(KEY_N)
	_check(is_equal_approx(f.real_age_years(age_probe), age), "時間のプレビューで樹齢は変わらない")
	_check(f.today() == Time.get_date_string_from_system(), "時間のプレビューで日付は変わらない")
	w.save_game()
	var saved: String = FileAccess.get_file_as_string(TEST_SAVE)
	_check(not saved.contains("preview_hours"), "時間のプレビューはセーブに書かない")
	_press(KEY_R)
	f.remove_nearest(Vector2(-30, -30), 2.0)

func _test_2d_has_no_light() -> void:
	print("2D のシーン")
	var m2d: Node = load("res://Main2D.tscn").instantiate()
	m2d.world.save_path = TEST_SAVE
	root.add_child(m2d)
	_check(m2d.get_node_or_null("DayLight") == null, "2D には昼夜の光がなく、エラーなく開く")
	var e := InputEventKey.new()
	e.keycode = KEY_N
	e.pressed = true
	m2d._unhandled_input(e)
	_check(m2d.world.clock.preview_hours == 1.0, "2D でも N は HUD の時計だけ動かす")
	m2d.free()
