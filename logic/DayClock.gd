extends RefCounted

# ── 現実の時計と太陽の位置(描画を持たない) ───────────────────────
# ゲームのルールには使わない。光の見た目(view/3d/DayLightView3D.gd)と HUD の時計のためだけ。
# 日の出・日の入りが窓の外と近くなるように、日本のまんなかあたりの緯度・経度と日付から太陽の位置を計算する。
# 向きは ロジックの座標と同じ: x = 東、y = 上、z = 南(-z = 北)。大気の屈折は入れない(数分の差)
const LATITUDE_DEG := 35.0
const LONGITUDE_DEG := 137.0
const CLOCK_MERIDIAN_DEG := 135.0  # 日本標準時の基準の経度
const AXIAL_TILT_DEG := 23.44
const PREVIEW_STEP_HOURS := 1.0

# 太陽の高さ(度)がこの間にあるとき、明かりが少しずつともる
const DARK_START_DEG := 3.0
const DARK_FULL_DEG := -4.0

const MONTH_START_DAY := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]

var preview_hours := 0.0  # N で先へ送った時間(0〜24 未満)。保存しない
var fixed_now := {}       # テスト用: 空でなければ現実の時計の代わりに使う {month, day, hour, minute, second}
var time = null           # WorldTime(GameWorld が設定する)。なければ現実の時計

func _now() -> Dictionary:
	if not fixed_now.is_empty():
		return fixed_now
	return time.now_local() if time != null else Time.get_datetime_dict_from_system()

# 現実の時刻(時間の小数)。プレビューは含まない
func real_hours() -> float:
	var t := _now()
	return t.hour + t.minute / 60.0 + t.second / 3600.0

func today_of_year() -> int:
	var t := _now()
	return day_of_year(t.month, t.day)

# HUD に出す時刻。例: 「14:05」。プレビュー中は先へ送った時刻
func time_text() -> String:
	var total := int(fposmod(real_hours() + preview_hours, 24.0) * 60.0)
	return "%02d:%02d" % [total / 60, total % 60]

func advance_preview() -> void:
	preview_hours = fposmod(preview_hours + PREVIEW_STEP_HOURS, 24.0)

func reset_preview() -> void:
	preview_hours = 0.0

func is_preview() -> bool:
	return preview_hours > 0.0

# 1 月 1 日が 1。うるう年の 1 日のずれは、光の見た目には効かないので無視する
static func day_of_year(month: int, day: int) -> int:
	return MONTH_START_DAY[month - 1] + day

static func declination_deg(doy: int) -> float:
	return -AXIAL_TILT_DEG * cos(TAU * (doy + 10) / 365.0)

# 均時差(分): 太陽の南中が時計の 12 時より何分早いか
static func equation_of_time_min(doy: int) -> float:
	var b := TAU * (doy - 81) / 364.0
	return 9.87 * sin(2.0 * b) - 7.53 * cos(b) - 1.5 * sin(b)

# 太陽のある方向(長さ 1)。hours は時計の時刻(時間の小数)
static func to_sun(hours: float, doy: int) -> Vector3:
	var solar := hours + equation_of_time_min(doy) / 60.0 + (LONGITUDE_DEG - CLOCK_MERIDIAN_DEG) / 15.0
	var hour_angle := deg_to_rad(15.0 * (solar - 12.0))
	var lat := deg_to_rad(LATITUDE_DEG)
	var dec := deg_to_rad(declination_deg(doy))
	var east := -cos(dec) * sin(hour_angle)
	var north := cos(lat) * sin(dec) - sin(lat) * cos(dec) * cos(hour_angle)
	var up := sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(hour_angle)
	return Vector3(east, up, -north)

static func elevation_deg(dir: Vector3) -> float:
	return rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))

# 暗さ(0 = 明るい昼、1 = 夜)
static func darkness(elevation: float) -> float:
	return 1.0 - smoothstep(DARK_FULL_DEG, DARK_START_DEG, elevation)
