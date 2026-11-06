extends SceneTree

# ── 音を作る道具(ゲームの実行には使わない) ─────────────────────────
# 外部の素材を使わず、雑音と正弦波から自然音・足音・作業音を作って audio/ に WAV で書き出す。
# 乱数の種を固定しているので、何度実行しても同じ音になる。音を直すときはここを直して実行し直す:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tools/make_sounds.gd
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
# 音楽と、鳥・虫・生き物の声はまだ作っていない(2026-11-06 とむ: あとから)
const RATE := 22050
const OUT := "res://audio/"

var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# 流し続ける音(つなぎ目が分からないように作る)
	_save_loop("wind", _wind(14.0))
	_save_loop("leaves", _leaves(14.0))
	_save_loop("brook", _brook(12.0))
	_save_loop("rain", _rain(12.0))
	_save_loop("fire", _fire(8.0))
	# 足音(同じ音が続かないように 3 つずつ)
	for i in range(3):
		_save("step_grass_%d" % i, _step_grass(100 + i))
		_save("step_soil_%d" % i, _step_soil(200 + i))
		_save("step_wood_%d" % i, _step_wood(300 + i))
	# 作業音
	_save("water", _water())
	_save("dig", _dig())
	_save("chop", _chop())
	_save("build", _hammer())
	_save("pick", _pick())
	_save("plant", _plant())
	_save("pull", _pull())
	_save("tree_fall", _tree_fall())
	# 画面の音
	_save("click", _click())
	_save("open", _open_panel())
	_save("coin", _coin())
	print("done")
	quit(0)

# ── 書き出し ───────────────────────────────────────────────
func _save(sound: String, samples: PackedFloat32Array) -> void:
	_normalize(samples, 0.85)
	_write(sound, samples)

# 終わりを始まりに重ねて、つなぎ目を消す
func _save_loop(sound: String, samples: PackedFloat32Array) -> void:
	var fade := int(RATE * 1.0)
	var n := samples.size() - fade
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		out[i] = samples[i]
	for i in range(fade):
		var t := float(i) / fade
		out[i] = samples[i] * sqrt(t) + samples[n + i] * sqrt(1.0 - t)
	_normalize(out, 0.5)
	_write(sound, out)

func _write(sound: String, samples: PackedFloat32Array) -> void:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.save_to_wav(OUT + sound + ".wav")
	print(sound, ": ", snappedf(float(samples.size()) / RATE, 0.01), "s")

static func _normalize(s: PackedFloat32Array, peak: float) -> void:
	var top := 0.0001
	for v in s:
		top = maxf(top, absf(v))
	var gain := peak / top
	for i in range(s.size()):
		s[i] *= gain

# ── 部品 ──────────────────────────────────────────────────
func _empty(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(RATE * seconds))
	return s

# 1 次のローパスの係数
static func _lp_coef(cutoff: float) -> float:
	return 1.0 - exp(-TAU * cutoff / RATE)

# 雑音にローパスとハイパスを掛けて足す。env(t) が音量、t は 0〜1
func _add_noise(s: PackedFloat32Array, start: float, seconds: float, low: float, high: float, env: Callable, amount := 1.0) -> void:
	var a_high := _lp_coef(high)
	var a_low := _lp_coef(low)
	var lp0 := 0.0  # ローパスは 2 段重ねる(1 段では高い音が残って耳障りになる)
	var lp1 := 0.0
	var lp2 := 0.0
	var from := int(start * RATE)
	var n := int(seconds * RATE)
	for i in range(n):
		if from + i >= s.size():
			break
		var w := rng.randf_range(-1.0, 1.0)
		lp0 += a_high * (w - lp0)
		lp1 += a_high * (lp0 - lp1)
		lp2 += a_low * (lp1 - lp2)
		s[from + i] += (lp1 - lp2) * float(env.call(float(i) / n)) * amount

# 音程が下がっていく短い音。ものを叩いた響き
func _add_tone(s: PackedFloat32Array, start: float, seconds: float, f_start: float, f_end: float, decay: float, amount := 1.0) -> void:
	var from := int(start * RATE)
	var n := int(seconds * RATE)
	var phase := 0.0
	for i in range(n):
		if from + i >= s.size():
			break
		var t := float(i) / n
		phase += TAU * lerpf(f_start, f_end, t) / RATE
		s[from + i] += sin(phase) * exp(-t * decay) * minf(1.0, i / 40.0) * amount

static func _hump(t: float) -> float:
	return sin(t * PI)

static func _hit(t: float) -> float:
	return minf(1.0, t * 40.0) * exp(-t * 6.0)

# ── 流し続ける音 ───────────────────────────────────────────
# 風: 低い雑音。強さは少しだけ変わる(周期的に大きく変わると、波の音に聞こえる。2026-11-06 とむの感想)
func _wind(seconds: float) -> PackedFloat32Array:
	rng.seed = 11
	var s := _empty(seconds)
	var lp0 := 0.0
	var lp := 0.0
	var lp2 := 0.0
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	for i in range(s.size()):
		var t := float(i) / RATE
		var swell := 0.8 + 0.1 * sin(t * 0.37 + p1) + 0.1 * sin(t * 1.13 + p2)
		var a := _lp_coef(140.0 + 160.0 * swell)
		lp0 += a * (rng.randf_range(-1.0, 1.0) - lp0)
		lp += a * (lp0 - lp)
		lp2 += 0.002 * (lp - lp2)
		s[i] = (lp - lp2) * swell
	return s

# 葉の揺れる音: 高い雑音が、風に合わせて細かく強くなったり弱くなったりする
func _leaves(seconds: float) -> PackedFloat32Array:
	rng.seed = 12
	var s := _empty(seconds)
	var a_high := _lp_coef(3000.0)  # 高すぎると耳障り(2026-11-06 とむの感想)
	var a_low := _lp_coef(800.0)
	var lp0 := 0.0
	var lp1 := 0.0
	var lp2 := 0.0
	var flutter := 0.0
	var flutter_goal := 0.5
	var p := rng.randf() * TAU
	for i in range(s.size()):
		var t := float(i) / RATE
		if i % 700 == 0:
			flutter_goal = rng.randf_range(0.15, 1.0)
		flutter += 0.002 * (flutter_goal - flutter)
		var gust := 0.5 + 0.35 * sin(t * 0.9 + p) + 0.15 * sin(t * 2.3)
		var w := rng.randf_range(-1.0, 1.0)
		lp0 += a_high * (w - lp0)
		lp1 += a_high * (lp0 - lp1)
		lp2 += a_low * (lp1 - lp2)
		s[i] = (lp1 - lp2) * flutter * gust
	return s

# 川のせせらぎ: 薄い水の流れに、高めの短い水の粒をまばらに重ねる。
# 雑音が多いと海に、音程の上がる泡の音を重ねると水の中に聞こえる(どちらも 2026-11-06 とむの感想)
func _brook(seconds: float) -> PackedFloat32Array:
	rng.seed = 13
	var s := _empty(seconds)
	_add_noise(s, 0.0, seconds, 1400.0, 3200.0, func(_t): return 1.0, 0.05)
	_add_droplets(s, seconds, int(seconds * 25.0), 1300.0, 2800.0, 0.008, 0.025, 0.3)
	return s

# 水の粒: 音程がほとんど変わらない、ごく短い音
func _add_droplets(s: PackedFloat32Array, seconds: float, count: int, f_low: float, f_high: float, len_low: float, len_high: float, loud: float) -> void:
	var slot := (seconds - 0.1) / count
	for i in range(count):
		# だいたい同じ間隔で、少しずつずらす(完全な乱数だと、固まって鳴るところができる)
		var start := (i + rng.randf_range(0.0, 0.8)) * slot
		var f := rng.randf_range(f_low, f_high)
		var length := rng.randf_range(len_low, len_high)
		var amp := loud * rng.randf_range(0.3, 1.0)
		var from := int(start * RATE)
		var n := int(length * RATE)
		var phase := 0.0
		for j in range(n):
			var t := float(j) / n
			phase += TAU * f * (1.0 + 0.06 * t) / RATE
			s[from + j] += sin(phase) * _hump(t) * amp

# 雨: 高めの雑音と、ぽつぽつ当たる音
func _rain(seconds: float) -> PackedFloat32Array:
	rng.seed = 14
	var s := _empty(seconds)
	_add_noise(s, 0.0, seconds, 400.0, 3200.0, func(_t): return 1.0, 0.5)
	for _i in range(int(seconds * 35.0)):
		var start := rng.randf_range(0.0, seconds - 0.05)
		_add_noise(s, start, 0.02, 700.0, 4000.0, func(t): return _hit(t), rng.randf_range(0.15, 0.6))
	return s

# ストーブの火: 低いごうごうという音と、ぱちぱち
func _fire(seconds: float) -> PackedFloat32Array:
	rng.seed = 15
	var s := _empty(seconds)
	_add_noise(s, 0.0, seconds, 40.0, 500.0, func(_t): return 1.0, 0.8)
	for _i in range(int(seconds * 7.0)):
		var start := rng.randf_range(0.0, seconds - 0.05)
		_add_noise(s, start, 0.02, 800.0, 4000.0, func(t): return _hit(t), rng.randf_range(0.3, 1.0))
	return s

# ── 足音 ──────────────────────────────────────────────────
func _step_grass(seed_value: int) -> PackedFloat32Array:
	rng.seed = seed_value
	var s := _empty(0.2)
	_add_noise(s, 0.0, 0.14, 700.0, 3200.0, func(t): return _hump(t) * (0.6 + 0.4 * sin(t * 40.0)), 0.8)
	_add_noise(s, 0.0, 0.08, 60.0, 400.0, func(t): return _hit(t), 0.5)
	return s

func _step_soil(seed_value: int) -> PackedFloat32Array:
	rng.seed = seed_value
	var s := _empty(0.2)
	_add_noise(s, 0.0, 0.12, 80.0, 900.0, func(t): return _hit(t), 1.0)
	_add_noise(s, 0.02, 0.12, 800.0, 3500.0, func(t): return _hump(t), 0.25)
	return s

func _step_wood(seed_value: int) -> PackedFloat32Array:
	rng.seed = seed_value
	var s := _empty(0.2)
	var f := rng.randf_range(150.0, 190.0)
	_add_tone(s, 0.0, 0.14, f, f * 0.85, 7.0, 1.0)
	_add_tone(s, 0.0, 0.06, f * 2.7, f * 2.4, 8.0, 0.3)
	_add_noise(s, 0.0, 0.02, 800.0, 5000.0, func(t): return _hit(t), 0.4)
	return s

# ── 作業音 ─────────────────────────────────────────────────
# じょうろ: 水の流れと、落ちる粒
func _water() -> PackedFloat32Array:
	rng.seed = 21
	var s := _empty(0.95)
	_add_noise(s, 0.0, 0.9, 700.0, 3000.0, func(t): return minf(1.0, t * 8.0) * minf(1.0, (1.0 - t) * 5.0), 0.5)
	for _i in range(40):
		var start := rng.randf_range(0.05, 0.85)
		var f := rng.randf_range(700.0, 2200.0)
		_add_tone(s, start, 0.03, f, f * 1.4, 4.0, rng.randf_range(0.05, 0.2))
	return s

# くわ: 土に刺さる鈍い音と、土がこぼれる音
func _dig() -> PackedFloat32Array:
	rng.seed = 22
	var s := _empty(0.4)
	_add_noise(s, 0.0, 0.12, 60.0, 700.0, func(t): return _hit(t), 1.2)
	_add_tone(s, 0.0, 0.1, 110.0, 70.0, 6.0, 0.5)
	_add_noise(s, 0.06, 0.3, 1000.0, 4500.0, func(t): return _hump(t) * (0.5 + 0.5 * sin(t * 60.0)), 0.3)
	return s

# 斧: 鋭い当たりと、木の響き
func _chop() -> PackedFloat32Array:
	rng.seed = 23
	var s := _empty(0.4)
	_add_noise(s, 0.0, 0.02, 800.0, 4500.0, func(t): return _hit(t), 0.7)
	_add_tone(s, 0.0, 0.25, 240.0, 200.0, 9.0, 0.9)
	_add_tone(s, 0.0, 0.16, 520.0, 460.0, 10.0, 0.45)
	_add_noise(s, 0.0, 0.1, 300.0, 2000.0, func(t): return _hit(t), 0.4)
	return s

# 金づち: 木を叩く硬い音
func _hammer() -> PackedFloat32Array:
	rng.seed = 24
	var s := _empty(0.25)
	_add_noise(s, 0.0, 0.01, 1000.0, 4500.0, func(t): return _hit(t), 0.4)
	_add_tone(s, 0.0, 0.14, 520.0, 470.0, 12.0, 0.8)
	_add_tone(s, 0.0, 0.08, 1100.0, 1000.0, 14.0, 0.2)
	_add_tone(s, 0.0, 0.1, 150.0, 120.0, 10.0, 0.5)
	return s

# 収穫: 葉がこすれて、ぽんと取れる
func _pick() -> PackedFloat32Array:
	rng.seed = 25
	var s := _empty(0.3)
	_add_noise(s, 0.0, 0.16, 1500.0, 6500.0, func(t): return _hump(t), 0.5)
	_add_tone(s, 0.13, 0.08, 500.0, 900.0, 5.0, 0.7)
	return s

# 種まき: 土を軽く 2 回おさえる
func _plant() -> PackedFloat32Array:
	rng.seed = 26
	var s := _empty(0.35)
	_add_noise(s, 0.0, 0.08, 100.0, 1200.0, func(t): return _hit(t), 0.9)
	_add_noise(s, 0.16, 0.08, 100.0, 1200.0, func(t): return _hit(t), 0.7)
	_add_noise(s, 0.02, 0.28, 1500.0, 5000.0, func(t): return _hump(t), 0.08)
	return s

# 抜く: 土からずるっと抜ける
func _pull() -> PackedFloat32Array:
	rng.seed = 27
	var s := _empty(0.4)
	_add_noise(s, 0.0, 0.3, 200.0, 2500.0, func(t): return t * t, 0.9)
	_add_tone(s, 0.26, 0.08, 280.0, 620.0, 4.0, 0.6)
	_add_noise(s, 0.28, 0.1, 1500.0, 6000.0, func(t): return _hit(t), 0.4)
	return s

# 木が倒れる: みしみしきしんで、どさっと倒れ、枝葉が揺れる
func _tree_fall() -> PackedFloat32Array:
	rng.seed = 28
	var s := _empty(1.7)
	# きしみ: 不規則に音程が上がる短い音を重ねる
	var at := 0.0
	var f := 180.0
	while at < 0.75:
		var next := rng.randf_range(0.02, 0.09)
		_add_tone(s, at, 0.09, f, f * 1.1, 3.0, 0.1 + at * 0.35)
		f += rng.randf_range(4.0, 28.0)
		at += next
	# どさっ
	_add_noise(s, 0.8, 0.35, 30.0, 400.0, func(t): return _hit(t), 1.6)
	_add_tone(s, 0.8, 0.3, 80.0, 45.0, 5.0, 0.9)
	# 枝葉
	_add_noise(s, 0.78, 0.9, 1500.0, 7000.0, func(t): return minf(1.0, t * 20.0) * (1.0 - t) * (1.0 - t), 0.5)
	return s

# ── 画面の音 ───────────────────────────────────────────────
func _click() -> PackedFloat32Array:
	var s := _empty(0.05)
	_add_tone(s, 0.0, 0.04, 800.0, 720.0, 6.0, 1.0)
	return s

func _open_panel() -> PackedFloat32Array:
	var s := _empty(0.2)
	_add_tone(s, 0.0, 0.09, 520.0, 540.0, 5.0, 0.8)
	_add_tone(s, 0.07, 0.11, 780.0, 800.0, 5.0, 0.8)
	return s

func _coin() -> PackedFloat32Array:
	var s := _empty(0.3)
	_add_tone(s, 0.0, 0.12, 1500.0, 1500.0, 6.0, 0.7)
	_add_tone(s, 0.06, 0.22, 2000.0, 2000.0, 6.0, 0.8)
	return s
