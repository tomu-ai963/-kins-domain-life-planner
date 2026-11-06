extends SceneTree

# 音ファイルのテスト。音の良し悪しは耳で確かめるしかないので、ここでは壊れていないことを数字で見る。
# 実行: Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_sounds.gd
# 標準出力に結果を出し、失敗があれば終了コード 1 で終わる

const LOOPS := ["wind", "leaves", "brook", "rain", "fire"]
const SHOTS := ["water", "dig", "chop", "build", "pick", "plant", "pull", "tree_fall", "click", "open", "coin",
	"step_grass_0", "step_grass_1", "step_grass_2", "step_soil_0", "step_soil_1", "step_soil_2", "step_wood_0", "step_wood_1", "step_wood_2"]
const DIR := "res://audio/"

var _failed := 0
var _passed := 0

func _initialize() -> void:
	for s in LOOPS:
		_test_loop(s)
	for s in SHOTS:
		_test_shot(s)
	_test_variants_differ()
	_test_character()
	_test_imported()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)

# WAV の中身を -1〜1 の数の並びにする
func _samples(sound: String) -> PackedFloat32Array:
	var wav := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(DIR + sound + ".wav"))
	var out := PackedFloat32Array()
	if wav == null or wav.format != AudioStreamWAV.FORMAT_16_BITS:
		return out
	var data: PackedByteArray = wav.data
	out.resize(data.size() / 2)
	for i in range(out.size()):
		out[i] = data.decode_s16(i * 2) / 32768.0
	return out

static func _peak(s: PackedFloat32Array) -> float:
	var top := 0.0
	for v in s:
		top = maxf(top, absf(v))
	return top

static func _rms(s: PackedFloat32Array) -> float:
	var total := 0.0
	for v in s:
		total += v * v
	return sqrt(total / maxf(s.size(), 1.0))

func _test_loop(sound: String) -> void:
	print(sound)
	var s := _samples(sound)
	_check(s.size() > 22050 * 5, "%s は 5 秒以上ある(%.1f 秒)" % [sound, s.size() / 22050.0])
	var peak := _peak(s)
	_check(peak > 0.3 and peak < 0.6, "%s は大きすぎない(最大 %.2f)" % [sound, peak])
	var rms := _rms(s)
	_check(rms > 0.02, "%s は鳴り続ける(平均 %.3f)" % [sound, rms])
	# 最後から最初へ戻るところで、音が大きく飛ばない。ふだんの隣どうしの差と比べる
	var normal := 0.0
	for i in range(1, s.size()):
		normal = maxf(normal, absf(s[i] - s[i - 1]))
	var seam: float = absf(s[0] - s[s.size() - 1])
	_check(seam <= normal, "%s のつなぎ目が目立たない(差 %.3f / ふだんの最大 %.3f)" % [sound, seam, normal])
	# 途中で無音にならない(1 秒ごとに見る)
	var quiet := 0
	for i in range(0, s.size() - 22050, 22050):
		if _rms(s.slice(i, i + 22050)) < rms * 0.15:
			quiet += 1
	_check(quiet == 0, "%s は途中で途切れない" % sound)

func _test_shot(sound: String) -> void:
	var s := _samples(sound)
	_check(s.size() > 500 and s.size() < 22050 * 2, "%s は短い音(%.2f 秒)" % [sound, s.size() / 22050.0])
	var peak := _peak(s)
	_check(peak > 0.5 and peak < 0.95, "%s は割れない大きさ(最大 %.2f)" % [sound, peak])
	_check(absf(s[s.size() - 1]) < 0.15, "%s の終わりで「ぷつっ」といわない(%.2f)" % [sound, absf(s[s.size() - 1])])

func _test_variants_differ() -> void:
	print("足音の違い")
	for surface in ["step_grass", "step_soil", "step_wood"]:
		var a := _samples(surface + "_0")
		var b := _samples(surface + "_1")
		_check(a != b, "%s の 3 つは同じ音ではない" % surface)
	var grass := _rms(_samples("step_grass_0"))
	_check(grass > 0.0, "草の足音が鳴る")

# 音の高さの目安: 隣の値と符号が変わる割合(大きいほど高い音)
static func _zero_rate(s: PackedFloat32Array) -> float:
	var n := 0
	for i in range(1, s.size()):
		if (s[i] >= 0.0) != (s[i - 1] >= 0.0):
			n += 1
	return float(n) / s.size()

# 音量の波打ち: 1 秒ごとの大きさのばらつき(平均に対する割合)。大きいと波の音のように聞こえる
func _swell(s: PackedFloat32Array) -> float:
	var levels := []
	for i in range(0, s.size() - 22050, 22050):
		levels.append(_rms(s.slice(i, i + 22050)))
	var total := 0.0
	for v in levels:
		total += v
	var mean: float = total / levels.size()
	var spread := 0.0
	for v in levels:
		spread += (v - mean) * (v - mean)
	return sqrt(spread / levels.size()) / mean

func _test_character() -> void:
	print("音の性質(2026-11-06 とむの感想: 耳障り・川が海に聞こえる)")
	var wind := _samples("wind")
	var brook := _samples("brook")
	var leaves := _samples("leaves")
	var rain := _samples("rain")
	_check(_swell(brook) < 0.12, "川の音量は波打たない(ばらつき %.1f%%)" % (_swell(brook) * 100.0))
	_check(_zero_rate(brook) > 0.1, "川は低い「とぷん」より高い音が主(%.3f)" % _zero_rate(brook))
	_check(_swell(wind) < 0.2, "風の音量は大きく波打たない(ばらつき %.1f%%)" % (_swell(wind) * 100.0))
	_check(_zero_rate(brook) > _zero_rate(wind) * 2.0, "川は風より高い音(%.3f / %.3f)" % [_zero_rate(brook), _zero_rate(wind)])
	# 雑音が多いと符号の変わり方が 0.5 に近づく。高音を削っていれば小さくなる
	for pair in [["葉", leaves], ["雨", rain], ["川", brook]]:
		var rate := _zero_rate(pair[1])
		_check(rate < 0.35, "%s に高い音が多すぎない(%.3f)" % [pair[0], rate])

func _test_imported() -> void:
	print("読み込み")
	for s in LOOPS + SHOTS:
		var stream = load(DIR + s + ".wav")
		_check(stream is AudioStream and stream.get_length() > 0.0, "%s をゲームから読める" % s)
