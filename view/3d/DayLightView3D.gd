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

# 太陽の高さ(度)ごとの光。あいだは直線でつなぐ。25〜45 度が、ふだんの昼の見た目。
# 夏の高い太陽は地面にまっすぐ当たるので、白っぽくならないように少し弱める
const KEYS := [
	{"elev": -12.0, "energy": 0.30, "light": Color(0.42, 0.55, 1.00), "top": Color(0.03, 0.05, 0.14), "horizon": Color(0.07, 0.10, 0.22), "ambient": 1.60},
	{"elev": -4.0, "energy": 0.20, "light": Color(0.50, 0.58, 0.95), "top": Color(0.22, 0.28, 0.52), "horizon": Color(0.40, 0.32, 0.46), "ambient": 3.00},
	{"elev": -1.0, "energy": 0.00, "light": Color(1.00, 0.55, 0.40), "top": Color(0.36, 0.40, 0.60), "horizon": Color(0.85, 0.50, 0.42), "ambient": 2.00},
	# 低い太陽は地面に斜めに当たって弱くなるので、夕焼けの色が地面に乗るように強めにする
	{"elev": 3.0, "energy": 1.30, "light": Color(1.00, 0.62, 0.36), "top": Color(0.36, 0.44, 0.62), "horizon": Color(1.00, 0.66, 0.46), "ambient": 0.80},
	{"elev": 12.0, "energy": 1.15, "light": Color(1.00, 0.86, 0.68), "top": Color(0.40, 0.57, 0.80), "horizon": Color(0.92, 0.80, 0.66), "ambient": 0.50},
	{"elev": 25.0, "energy": 1.00, "light": Color(1.00, 1.00, 1.00), "top": Color(0.42, 0.62, 0.86), "horizon": Color(0.78, 0.84, 0.88), "ambient": 0.40},
	{"elev": 45.0, "energy": 1.00, "light": Color(1.00, 1.00, 1.00), "top": Color(0.42, 0.62, 0.86), "horizon": Color(0.78, 0.84, 0.88), "ambient": 0.40},
	{"elev": 78.0, "energy": 0.80, "light": Color(1.00, 1.00, 1.00), "top": Color(0.42, 0.62, 0.86), "horizon": Color(0.78, 0.84, 0.88), "ambient": 0.40},
]

var clock: DayClock
var sun: DirectionalLight3D
var environment: Environment
var night := -1.0  # 今の暗さ。まだ一度も決めていないときは -1
var _shown_offset := 0.0  # 画面に出しているプレビューの時間。clock.preview_hours を追いかける
var _timer := 0.0

func setup(c: DayClock, s: DirectionalLight3D, e: Environment) -> void:
	clock = c
	sun = s
	environment = e
	apply_light()

func _process(delta: float) -> void:
	if clock == null:
		return
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
	var k := sample(elev)
	sun.basis = Basis.looking_at(-light_dir(dir))
	sun.light_energy = k.energy
	sun.light_color = k.light
	var sky: ProceduralSkyMaterial = environment.sky.sky_material
	sky.sky_top_color = k.top
	sky.sky_horizon_color = k.horizon
	sky.ground_horizon_color = k.horizon
	environment.ambient_light_energy = k.ambient
	environment.fog_light_color = k.horizon
	var amount := DayClock.darkness(elev)
	if absf(amount - night) > 0.001:
		night = amount
		night_changed.emit(night)

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
