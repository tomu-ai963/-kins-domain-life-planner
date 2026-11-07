extends Node

# ── 昼夜の光 ───────────────────────────────────────────────
# logic/DayClock.gd の太陽の位置から、太陽(夜は月)の向きと色・環境光・遠くのかすみを決める。
# カメラは見下ろしで空そのものは映らない。空の色は環境光(sky から取っている)とかすみの色として効く。
# 明かり(小屋・屋台・ランタン)は night_changed を受けた各 view がともす
const DayClock = preload("res://logic/DayClock.gd")

signal night_changed(amount)  # 0 = 昼、1 = 夜

const MIN_LIGHT_ELEVATION_DEG := 12.0 # これより低い太陽は高さを止める(土地の端まで届く長い影を防ぐ)
const MIN_MOON_ELEVATION_DEG := 40.0  # 月はいつもこの高さ以上から照らす(低い月だと、日没直後が夜中より暗くなる)
const MOON_BELOW_DEG := -1.0          # 太陽がこれより沈むと、光の向きを月(太陽の反対側)に切り替える。ここで光は 0
const APPLY_SECONDS := 5.0            # 太陽は 5 秒で 0.02 度しか動かない。毎フレーム計算しない
const PREVIEW_HOURS_PER_SECOND := 6.0 # N で先へ送ったとき、光が動いていく速さ
const TYPICAL_ALBEDO := 0.3           # 影つきの光を直すときの基準にする材質の明るさ(草地くらい)

# 太陽の高さ(度)ごとの光。あいだは直線でつなぐ。
# トゥーンでは光が当たる面の明るさが角度で変わらないので、太陽の高さによる明るさの差はこの表の energy で作る
const KEYS := [
	{"elev": -12.0, "energy": 0.22, "light": Color(0.42, 0.55, 1.00), "top": Color(0.03, 0.05, 0.14), "horizon": Color(0.07, 0.10, 0.22), "ambient": 1.60},
	{"elev": -4.0, "energy": 0.14, "light": Color(0.50, 0.58, 0.95), "top": Color(0.22, 0.28, 0.52), "horizon": Color(0.40, 0.32, 0.46), "ambient": 3.00},
	{"elev": -1.0, "energy": 0.00, "light": Color(1.00, 0.55, 0.40), "top": Color(0.36, 0.40, 0.60), "horizon": Color(0.85, 0.50, 0.42), "ambient": 2.00},
	{"elev": 3.0, "energy": 0.42, "light": Color(1.00, 0.62, 0.36), "top": Color(0.36, 0.44, 0.62), "horizon": Color(1.00, 0.66, 0.46), "ambient": 0.80},
	{"elev": 12.0, "energy": 0.48, "light": Color(1.00, 0.86, 0.68), "top": Color(0.40, 0.57, 0.80), "horizon": Color(0.92, 0.80, 0.66), "ambient": 0.50},
	{"elev": 25.0, "energy": 0.56, "light": Color(1.00, 1.00, 1.00), "top": Color(0.42, 0.62, 0.86), "horizon": Color(0.78, 0.84, 0.88), "ambient": 0.40},
	{"elev": 45.0, "energy": 0.68, "light": Color(1.00, 1.00, 1.00), "top": Color(0.42, 0.62, 0.86), "horizon": Color(0.78, 0.84, 0.88), "ambient": 0.40},
	{"elev": 78.0, "energy": 0.75, "light": Color(1.00, 1.00, 1.00), "top": Color(0.42, 0.62, 0.86), "horizon": Color(0.78, 0.84, 0.88), "ambient": 0.40},
]

# 雨雲の下の光: 太陽は弱く(影が薄くなる)、空は同じ明るさのまま灰色に、遠くはかすむ
const OVERCAST_SUN := 0.25        # 太陽の光に掛ける倍率
const OVERCAST_SKY_MIX := 0.85    # 空の色をどれだけ灰色に寄せるか
const OVERCAST_FOG := 0.0035      # 雨のときのかすみの濃さ
const OVERCAST_SECONDS := 3.0     # 晴れから雨に変わるのにかかる時間

var clock: DayClock
var sun: DirectionalLight3D
var environment: Environment
var night := -1.0  # 今の暗さ。まだ一度も決めていないときは -1
var overcast := 0.0  # 雲の厚さ。0 = 晴れ、1 = 雨
var _overcast_goal := 0.0
var _clear_fog := 0.0
var _shown_offset := 0.0  # 画面に出しているプレビューの時間。clock.preview_hours を追いかける
var _timer := 0.0

func setup(c: DayClock, s: DirectionalLight3D, e: Environment) -> void:
	clock = c
	sun = s
	environment = e
	_clear_fog = e.fog_density
	apply_light()

# 雲の厚さを変える。instant でなければ少しずつ変わる
func set_overcast(amount: float, instant := false) -> void:
	_overcast_goal = amount
	if instant:
		overcast = amount
		apply_light()

func _process(delta: float) -> void:
	if clock == null:
		return
	if not is_equal_approx(overcast, _overcast_goal):
		overcast = move_toward(overcast, _overcast_goal, delta / OVERCAST_SECONDS)
		apply_light()
	var diff := wrapf(clock.preview_hours - _shown_offset, -12.0, 12.0)
	if absf(diff) > 0.001:
		var step := PREVIEW_HOURS_PER_SECOND * delta
		_shown_offset = fposmod(_shown_offset + clampf(diff, -step, step), 24.0)
		apply_light()
		return
	_timer += delta
	if _timer >= APPLY_SECONDS:
		_timer = 0.0
		apply_light()

func apply_light() -> void:
	var dir := DayClock.to_sun(clock.real_hours() + _shown_offset, clock.today_of_year())
	var elev := DayClock.elevation_deg(dir)
	var k := cloudy(sample(elev), overcast)
	sun.basis = Basis.looking_at(-light_dir(dir))
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		var fixed := additive_light(k.light, k.energy, k.top)
		sun.light_energy = fixed.energy
		sun.light_color = fixed.color
	else:
		sun.light_energy = k.energy
		sun.light_color = k.light
	var sky: ProceduralSkyMaterial = environment.sky.sky_material
	sky.sky_top_color = k.top
	sky.sky_horizon_color = k.horizon
	sky.ground_horizon_color = k.horizon
	environment.ambient_light_energy = k.ambient
	environment.fog_light_color = k.horizon
	environment.fog_density = lerpf(_clear_fog, OVERCAST_FOG, overcast)
	var amount := DayClock.darkness(elev)
	if absf(amount - night) > 0.001:
		night = amount
		night_changed.emit(night)

# Compatibility(Web)では、影つきの光を環境光に sRGB のまま足すので、そのままだと明るくなりすぎる。
# 正しい明るさになるよう、足す光を弱めて返す。環境光と光はどちらも材質の色に掛かるので、
# この倍率は材質の色にほとんどよらず、太陽側で一度直せばよい。ambient は上を向いた面が受ける空の色
static func additive_light(light: Color, energy: float, ambient: Color) -> Dictionary:
	var sky := ambient.srgb_to_linear() * TYPICAL_ALBEDO
	var added := light.srgb_to_linear() * energy * TYPICAL_ALBEDO
	var base := sky.linear_to_srgb()
	var total := Color(sky.r + added.r, sky.g + added.g, sky.b + added.b).linear_to_srgb()
	var diff := Color(total.r - base.r, total.g - base.g, total.b - base.b).srgb_to_linear()
	var peak := maxf(maxf(diff.r, diff.g), diff.b) / TYPICAL_ALBEDO
	if peak <= 0.0:
		return {"energy": 0.0, "color": light}
	var color := Color(diff.r, diff.g, diff.b) / (peak * TYPICAL_ALBEDO)
	color.a = 1.0
	return {"energy": peak, "color": color.linear_to_srgb()}

# 光の来る方向。沈んだら月(太陽の反対側)。低すぎる光は高さを止める
static func light_dir(to_sun: Vector3) -> Vector3:
	var is_sun := DayClock.elevation_deg(to_sun) >= MOON_BELOW_DEG
	var d := to_sun if is_sun else -to_sun
	# 水平の向きを保ったまま、高さだけを下限まで上げる
	var min_elev := deg_to_rad(MIN_LIGHT_ELEVATION_DEG if is_sun else MIN_MOON_ELEVATION_DEG)
	if d.y < sin(min_elev):
		var flat := Vector3(d.x, 0.0, d.z).normalized()
		d = flat * cos(min_elev) + Vector3.UP * sin(min_elev)
	return d

# 晴れの光 k に雲をかける(amount: 0 = 晴れ、1 = 雨)。夜が明るくならないよう、空は明るさを保って灰色にする
static func cloudy(k: Dictionary, amount: float) -> Dictionary:
	if amount <= 0.0:
		return k
	var c := k.duplicate()
	c.energy = k.energy * lerpf(1.0, OVERCAST_SUN, amount)
	c.light = (k.light as Color).lerp(Color.WHITE, amount * 0.5)
	c.top = _to_gray(k.top, amount)
	c.horizon = _to_gray(k.horizon, amount)
	return c

static func _to_gray(c: Color, amount: float) -> Color:
	var l := c.get_luminance()
	return c.lerp(Color(l * 0.95, l, l * 1.06), amount * OVERCAST_SKY_MIX)

# 太陽の高さ elev のときの光(KEYS のあいだを直線でつなぐ)
static func sample(elev: float) -> Dictionary:
	if elev <= KEYS[0].elev:
		return KEYS[0]
	for i in range(1, KEYS.size()):
		var b: Dictionary = KEYS[i]
		if elev <= b.elev:
			var a: Dictionary = KEYS[i - 1]
			var t: float = (elev - a.elev) / (b.elev - a.elev)
			return {
				"elev": elev,
				"energy": lerpf(a.energy, b.energy, t),
				"light": (a.light as Color).lerp(b.light, t),
				"top": (a.top as Color).lerp(b.top, t),
				"horizon": (a.horizon as Color).lerp(b.horizon, t),
				"ambient": lerpf(a.ambient, b.ambient, t),
			}
	return KEYS[-1]
